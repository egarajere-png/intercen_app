// lib/pages/content_update_page.dart
//
// CORRECTIONS vs TSX ContentUpdatePage:
//   • Added _isFree toggle + sent in full submit (matches is_free checkbox)
//   • Added full "Linked Author Profile" card:
//       - Live debounced search against profiles (role=author)
//       - Linked author chip with avatar/initials + Unlink button
//       - handleAuthorSelect: updates UI + immediately partial-saves content_owner
//       - handleAuthorClear:  clears UI  + immediately partial-saves null
//   • content_owner loaded from DB, hydrated as linked author chip
//   • content_owner sent in full form submit
//   • Tags: falls back to meta_keywords if tags column is empty/null
//   • Toolbar: added Refresh and Publish Now buttons
//   • _ownerSaving flag disables submit while content_owner is being persisted

import 'dart:async';
import 'dart:io';
import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:image_picker/image_picker.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:http/http.dart' as http;
import 'package:http_parser/http_parser.dart';
import 'package:url_launcher/url_launcher.dart';

import '../services/role_service.dart';

// ── Palette ────────────────────────────────────────────────────────────────
const _kPrimary  = Color(0xFFB11226);
const _kCharcoal = Color(0xFF1A1A2E);
const _kBg       = Color(0xFFF9F5EF);
const _kWhite    = Colors.white;
const _kBorder   = Color(0xFFE5E7EB);
const _kMuted    = Color(0xFF6B7280);
const _kMutedLt  = Color(0xFF9CA3AF);
const _kGreen    = Color(0xFF16A34A);
const _kGreenBg  = Color(0xFFF0FDF4);
const _kAmber    = Color(0xFFD97706);
const _kAmberBg  = Color(0xFFFFFBEB);
const _kBlue     = Color(0xFF2563EB);
const _kBlueBg   = Color(0xFFEFF6FF);
const _kRed      = Color(0xFFDC2626);
const _kCard     = 12.0;

const _kMaxFileSize = 10 * 1024 * 1024; // 10 MB

const _kContentTypes = [
  'book', 'ebook', 'document', 'paper', 'report',
  'manual', 'guide', 'manuscript', 'article', 'thesis', 'dissertation',
];

const _kVisibilityOptions = [
  ('private',      'Private'),
  ('organization', 'Organization Only'),
  ('restricted',   'Restricted'),
  ('public',       'Public'),
];

const _kStatusOptions = [
  ('draft',          'Draft'),
  ('pending_review', 'Pending Review'),
  ('published',      'Published'),
  ('archived',       'Archived'),
];

const _kValidStatuses = {
  'draft', 'pending_review', 'published', 'archived',
};

const _kLanguages = [
  ('en', 'English'),
  ('sw', 'Swahili'),
  ('fr', 'French'),
  ('ar', 'Arabic'),
  ('es', 'Spanish'),
  ('de', 'German'),
  ('zh', 'Chinese'),
];

const _kSupabaseUrl = 'https://nnljrawwhibazudjudht.supabase.co';

// ── Author profile model ───────────────────────────────────────────────────

class _AuthorProfile {
  final String id;
  final String? fullName;
  final String? email;
  final String? avatarUrl;

  const _AuthorProfile({
    required this.id,
    this.fullName,
    this.email,
    this.avatarUrl,
  });

  factory _AuthorProfile.fromMap(Map<String, dynamic> m) => _AuthorProfile(
        id: m['id'] as String? ?? '',
        fullName: m['full_name'] as String?,
        email: m['email'] as String?,
        avatarUrl: m['avatar_url'] as String?,
      );

  String get initials {
    final src = fullName ?? email ?? '?';
    return src[0].toUpperCase();
  }
}

// ── Page ───────────────────────────────────────────────────────────────────

class ContentUpdatePage extends StatefulWidget {
  const ContentUpdatePage({Key? key}) : super(key: key);
  @override
  State<ContentUpdatePage> createState() => _ContentUpdatePageState();
}

class _ContentUpdatePageState extends State<ContentUpdatePage> {
  final _sb     = Supabase.instance.client;
  final _picker = ImagePicker();

  bool _checkingAuth = true;
  bool _isAdmin      = false;
  bool _loading      = true;
  bool _updating     = false;
  bool _showHistory  = false;
  bool _ownerSaving  = false;       // mirrors TSX ownerSaving

  String? _contentId;
  bool    _authChecked = false;

  // ── version history / categories ────────────────────────────────────────
  List<Map<String, dynamic>> _history    = [];
  List<Map<String, dynamic>> _categories = [];

  // ── form controllers ─────────────────────────────────────────────────────
  final _titleCtrl       = TextEditingController();
  final _subtitleCtrl    = TextEditingController();
  final _authorCtrl      = TextEditingController();
  final _publisherCtrl   = TextEditingController();
  final _priceCtrl       = TextEditingController();
  final _isbnCtrl        = TextEditingController();
  final _descriptionCtrl = TextEditingController();
  final _tagsCtrl        = TextEditingController();
  final _versionCtrl     = TextEditingController(text: '1.0');
  final _pageCountCtrl   = TextEditingController();
  final _stockCtrl       = TextEditingController();

  String _contentType = 'book';
  String _visibility  = 'private';
  String _status      = 'draft';
  String _language    = 'en';
  String _categoryId  = '';
  bool   _isFeatured  = false;
  bool   _isForSale   = false;
  bool   _isFree      = false;       // ← ADDED (matches TSX is_free)

  // content_owner (UUID of linked author)
  String _contentOwner = '';        // ← ADDED

  // current file URLs
  String _currentFileUrl     = '';
  String _currentCoverUrl    = '';
  String _currentBackpageUrl = '';

  // new files to upload
  File?   _coverFile;
  File?   _backpageFile;
  String? _coverName;
  String? _backpageName;

  // ── Author linking state (matches TSX author-linking) ────────────────────
  _AuthorProfile? _linkedAuthor;
  String _authorQuery    = '';
  List<_AuthorProfile> _authorResults = [];
  bool _authorSearching  = false;
  Timer? _authorDebounce;
  final _authorSearchCtrl = TextEditingController();
  final _authorOverlayKey = GlobalKey();
  OverlayEntry? _authorOverlay;

  bool get _isEbook => _contentType == 'ebook';

  // ── Lifecycle ──────────────────────────────────────────────────────────
  @override
  void initState() {
    super.initState();
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (!_authChecked) {
      _authChecked = true;
      final args = ModalRoute.of(context)?.settings.arguments;
      _contentId  = args is String ? args : null;
      _checkAdminAndLoad();
    }
  }

  @override
  void dispose() {
    for (final c in [
      _titleCtrl, _subtitleCtrl, _authorCtrl, _publisherCtrl,
      _priceCtrl, _isbnCtrl, _descriptionCtrl, _tagsCtrl,
      _versionCtrl, _pageCountCtrl, _stockCtrl, _authorSearchCtrl,
    ]) { c.dispose(); }
    _authorDebounce?.cancel();
    _removeAuthorOverlay();
    super.dispose();
  }

  // ── Admin guard ────────────────────────────────────────────────────────
  Future<void> _checkAdminAndLoad() async {
    await RoleService.instance.load();
    if (RoleService.instance.role != 'admin') {
      if (mounted) {
        Navigator.pushReplacementNamed(context, '/home');
        _toast('Access denied. Admin only.', err: true);
      }
      return;
    }
    setState(() { _isAdmin = true; _checkingAuth = false; });
    await Future.wait([_loadContent(), _loadCategories()]);
  }

  // ── Loaders ────────────────────────────────────────────────────────────
  Future<void> _loadContent() async {
    if (_contentId == null) return;
    setState(() => _loading = true);
    try {
      final data = await _sb
          .from('content')
          .select('*')
          .eq('id', _contentId!)
          .single();

      final d = data as Map<String, dynamic>;

      // ── Tags: prefer 'tags', fall back to 'meta_keywords' (matches TSX) ──
      String tagsString = '';
      final rawTags = d['tags'];
      final rawMeta = d['meta_keywords'];
      if (rawTags is List && (rawTags).isNotEmpty) {
        tagsString = rawTags.join(', ');
      } else if (rawMeta is List && (rawMeta).isNotEmpty) {
        tagsString = rawMeta.join(', ');
      }

      setState(() {
        _titleCtrl.text       = d['title']        as String? ?? '';
        _subtitleCtrl.text    = d['subtitle']      as String? ?? '';
        _authorCtrl.text      = d['author']        as String? ?? '';
        _publisherCtrl.text   = d['publisher']     as String? ?? '';
        _priceCtrl.text       = d['price']?.toString()          ?? '';
        _isbnCtrl.text        = d['isbn']          as String? ?? '';
        _descriptionCtrl.text = d['description']   as String? ?? '';
        _versionCtrl.text     = d['version']       as String? ?? '1.0';
        _pageCountCtrl.text   = d['page_count']?.toString()     ?? '';
        _stockCtrl.text       = d['stock_quantity']?.toString() ?? '';
        _tagsCtrl.text        = tagsString;
        _contentType          = d['content_type']  as String? ?? 'book';
        _visibility           = d['visibility']    as String? ?? 'private';
        _status               = _sanitiseStatus(d['status'] as String? ?? 'draft');
        _language             = d['language']      as String? ?? 'en';
        _categoryId           = d['category_id']   as String? ?? '';
        _isFeatured           = d['is_featured']   == true;
        _isForSale            = d['is_for_sale']   == true;
        _isFree               = d['is_free']       == true;           // ← ADDED
        _contentOwner         = d['content_owner'] as String? ?? ''; // ← ADDED
        _currentFileUrl       = d['file_url']            as String? ?? '';
        _currentCoverUrl      = d['cover_image_url']     as String? ?? '';
        _currentBackpageUrl   = d['backpage_image_url']  as String? ?? '';
      });

      // ── Hydrate linked author chip from content_owner (matches TSX) ──────
      if ((d['content_owner'] as String? ?? '').isNotEmpty) {
        try {
          final profileData = await _sb
              .from('profiles')
              .select('id, full_name, email, avatar_url')
              .eq('id', d['content_owner'] as String)
              .eq('role', 'author')
              .maybeSingle();
          if (mounted) {
            setState(() {
              _linkedAuthor = profileData != null
                  ? _AuthorProfile.fromMap(
                      Map<String, dynamic>.from(profileData as Map))
                  : null;
            });
          }
        } catch (_) {}
      } else {
        if (mounted) setState(() => _linkedAuthor = null);
      }
    } catch (e) {
      _toast('Failed to load content: $e', err: true);
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _loadCategories() async {
    try {
      final data = await _sb
          .from('categories')
          .select('id, name')
          .order('name');
      setState(() {
        _categories = List<Map<String, dynamic>>.from(data as List);
      });
    } catch (_) {}
  }

  Future<void> _loadVersionHistory() async {
    try {
      final res = await _sb.rpc('get_content_version_history',
          params: {'p_content_id': _contentId});
      setState(() {
        _history     = List<Map<String, dynamic>>.from(res as List? ?? []);
        _showHistory = true;
      });
    } catch (e) {
      _toast('Failed to load version history: $e', err: true);
    }
  }

  // ── Author search (matches TSX searchAuthors + handleAuthorInputChange) ──

  void _onAuthorQueryChanged(String val) {
    setState(() => _authorQuery = val);
    _authorDebounce?.cancel();

    if (val.trim().length < 2) {
      setState(() { _authorResults = []; _authorSearching = false; });
      _removeAuthorOverlay();
      return;
    }

    setState(() => _authorSearching = true);
    _authorDebounce = Timer(const Duration(milliseconds: 300), () {
      _searchAuthors(val.trim());
    });
  }

  Future<void> _searchAuthors(String q) async {
    try {
      final data = await _sb
          .from('profiles')
          .select('id, full_name, email, avatar_url')
          .eq('role', 'author')
          .or('full_name.ilike.%$q%,email.ilike.%$q%')
          .order('full_name')
          .limit(8);

      if (!mounted) return;
      final results = (data as List)
          .map((item) => _AuthorProfile.fromMap(
              Map<String, dynamic>.from(item as Map)))
          .toList();
      setState(() {
        _authorResults  = results;
        _authorSearching = false;
      });
      _showAuthorOverlay();
    } catch (e) {
      if (mounted) setState(() => _authorSearching = false);
      _toast('Could not search authors', err: true);
    }
  }

  // ── Select author: update UI + immediately partial-save content_owner ────
  Future<void> _handleAuthorSelect(_AuthorProfile profile) async {
    _removeAuthorOverlay();
    _authorSearchCtrl.clear();
    setState(() {
      _linkedAuthor   = profile;
      _authorQuery    = '';
      _authorResults  = [];
      _contentOwner   = profile.id;
      // Mirror TSX: fill author display name if empty
      if (_authorCtrl.text.trim().isEmpty) {
        _authorCtrl.text = profile.fullName ?? '';
      }
    });

    _ownerSaving = true;
    try {
      await _partialSave({'content_owner': profile.id});
      _toast('Author linked: ${profile.fullName ?? profile.email}');
    } finally {
      if (mounted) setState(() => _ownerSaving = false);
    }
  }

  // ── Unlink author: clear UI + immediately partial-save null ─────────────
  Future<void> _handleAuthorClear() async {
    setState(() {
      _linkedAuthor = null;
      _contentOwner = '';
    });
    setState(() => _ownerSaving = true);
    try {
      await _partialSave({'content_owner': null});
      _toast('Author unlinked');
    } finally {
      if (mounted) setState(() => _ownerSaving = false);
    }
  }

  // ── Overlay for author dropdown ──────────────────────────────────────────
  void _showAuthorOverlay() {
    _removeAuthorOverlay();
    if (_authorResults.isEmpty && !_authorSearching) return;

    final renderBox = _authorOverlayKey.currentContext
        ?.findRenderObject() as RenderBox?;
    if (renderBox == null) return;

    final offset = renderBox.localToGlobal(Offset.zero);
    final size   = renderBox.size;

    _authorOverlay = OverlayEntry(
      builder: (_) => Positioned(
        top:   offset.dy + size.height + 4,
        left:  offset.dx,
        width: size.width,
        child: Material(
          elevation: 6,
          borderRadius: BorderRadius.circular(10),
          color: _kWhite,
          child: ClipRRect(
            borderRadius: BorderRadius.circular(10),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                if (_authorSearching && _authorResults.isEmpty)
                  const Padding(
                    padding: EdgeInsets.all(14),
                    child: Row(
                      children: [
                        SizedBox(
                          width: 14, height: 14,
                          child: CircularProgressIndicator(
                              strokeWidth: 2, color: _kMuted),
                        ),
                        SizedBox(width: 10),
                        Text('Searching…',
                            style: TextStyle(
                                fontFamily: 'DM Sans',
                                fontSize: 13, color: _kMuted)),
                      ],
                    ),
                  ),
                ..._authorResults.map((p) => _AuthorResultTile(
                      profile: p,
                      onTap: () => _handleAuthorSelect(p),
                    )),
                if (!_authorSearching && _authorResults.isEmpty)
                  Padding(
                    padding: const EdgeInsets.all(14),
                    child: Text(
                      'No author profiles found for "$_authorQuery"',
                      textAlign: TextAlign.center,
                      style: const TextStyle(
                          fontFamily: 'DM Sans',
                          fontSize: 13, color: _kMuted),
                    ),
                  ),
              ],
            ),
          ),
        ),
      ),
    );
    Overlay.of(context).insert(_authorOverlay!);
  }

  void _removeAuthorOverlay() {
    _authorOverlay?.remove();
    _authorOverlay = null;
  }

  // ── File picker ────────────────────────────────────────────────────────
  Future<void> _pickImage(bool isCover) async {
    final xf = await _picker.pickImage(
        source: ImageSource.gallery, imageQuality: 90);
    if (xf == null) return;
    final f    = File(xf.path);
    final size = await f.length();
    if (size > _kMaxFileSize) {
      _toast('Image must be under 10 MB', err: true);
      return;
    }
    setState(() {
      if (isCover) { _coverFile = f; _coverName = xf.name; }
      else         { _backpageFile = f; _backpageName = xf.name; }
    });
  }

  void _removeFile(bool isCover) => setState(() {
        if (isCover) { _coverFile = null; _coverName = null; }
        else         { _backpageFile = null; _backpageName = null; }
      });

  // ── Partial save ──────────────────────────────────────────────────────
  Future<void> _partialSave(Map<String, dynamic> updates) async {
    try {
      final session = _sb.auth.currentSession;
      if (session == null) return;
      await _sb.functions.invoke(
        'content-part-update',
        body: {'content_id': _contentId!, ...updates},
      );
    } catch (e) {
      debugPrint('[ContentUpdate] partial save: $e');
    }
  }

  // ── Full submit ────────────────────────────────────────────────────────
  Future<void> _submit() async {
    if (_titleCtrl.text.trim().isEmpty) {
      _toast('Title is required', err: true); return;
    }
    if (_contentType.isEmpty) {
      _toast('Content type is required', err: true); return;
    }
    setState(() => _updating = true);

    try {
      final session = _sb.auth.currentSession;
      if (session == null) {
        _toast('Session expired.', err: true); return;
      }

      final req = http.MultipartRequest(
        'POST',
        Uri.parse('$_kSupabaseUrl/functions/v1/content-update'),
      );
      req.headers['Authorization'] = 'Bearer ${session.accessToken}';

      req.fields['content_id']   = _contentId!;
      req.fields['title']        = _titleCtrl.text.trim();
      req.fields['subtitle']     = _subtitleCtrl.text.trim();
      req.fields['author']       = _authorCtrl.text.trim();
      req.fields['publisher']    = _publisherCtrl.text.trim();
      req.fields['description']  = _descriptionCtrl.text.trim();
      req.fields['content_type'] = _contentType;
      req.fields['price']        =
          _priceCtrl.text.isNotEmpty ? _priceCtrl.text : '0';
      req.fields['isbn']         = _isbnCtrl.text.trim();
      req.fields['language']     = _language;
      req.fields['visibility']   = _visibility;
      req.fields['status']       = _status;
      req.fields['version']      = _versionCtrl.text.trim();
      req.fields['is_featured']  = _isFeatured.toString();
      req.fields['is_for_sale']  = _isForSale.toString();
      req.fields['is_free']      = _isFree.toString();        // ← ADDED
      // Send content_owner UUID; empty string = explicit unlink (matches TSX)
      req.fields['content_owner'] = _contentOwner;            // ← ADDED

      if (_categoryId.isNotEmpty) req.fields['category_id']    = _categoryId;
      if (_pageCountCtrl.text.isNotEmpty) req.fields['page_count']  = _pageCountCtrl.text;
      if (_stockCtrl.text.isNotEmpty)     req.fields['stock_quantity'] = _stockCtrl.text;

      final tagsRaw = _tagsCtrl.text.trim();
      if (tagsRaw.isNotEmpty) {
        final tags = tagsRaw
            .split(',')
            .map((t) => t.trim())
            .where((t) => t.isNotEmpty)
            .toList();
        req.fields['tags'] = jsonEncode(tags);
      }

      if (_coverFile != null) {
        req.files.add(await http.MultipartFile.fromPath(
          'cover_image', _coverFile!.path,
          contentType: _mediaType(_coverName ?? ''),
        ));
      }
      if (_backpageFile != null) {
        req.files.add(await http.MultipartFile.fromPath(
          'backpage_image', _backpageFile!.path,
          contentType: _mediaType(_backpageName ?? ''),
        ));
      }

      final streamed = await req.send();
      final resp     = await http.Response.fromStream(streamed);
      final body     = jsonDecode(resp.body) as Map<String, dynamic>;

      if (resp.statusCode != 200 && resp.statusCode != 201) {
        _toast(body['error']?.toString() ??
            'Update failed. Please try again.', err: true);
        return;
      }

      _toast('Content updated successfully!');
      setState(() { _coverFile = null; _backpageFile = null; });
      await _loadContent();
    } catch (e) {
      _toast('Update failed: $e', err: true);
    } finally {
      if (mounted) setState(() => _updating = false);
    }
  }

  MediaType _mediaType(String name) {
    final ext = name.split('.').last.toLowerCase();
    return switch (ext) {
      'png'  => MediaType('image', 'png'),
      'webp' => MediaType('image', 'webp'),
      _      => MediaType('image', 'jpeg'),
    };
  }

  void _toast(String msg, {bool err = false}) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(
      content: Text(msg,
          style: const TextStyle(
              fontFamily: 'DM Sans', fontWeight: FontWeight.w500)),
      backgroundColor: err ? _kRed : _kGreen,
      behavior: SnackBarBehavior.floating,
      margin: const EdgeInsets.all(16),
      shape:
          RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
      duration: const Duration(seconds: 3),
    ));
  }

  // ══════════════════════════════════════════════════════════════════════════
  // BUILD
  // ══════════════════════════════════════════════════════════════════════════

  @override
  Widget build(BuildContext context) {
    if (_checkingAuth) return _splash('Verifying access…');
    if (!_isAdmin) return const SizedBox.shrink();

    final w   = MediaQuery.of(context).size.width;
    final pad = _hp(w);

    return GestureDetector(
      onTap: _removeAuthorOverlay,
      child: Scaffold(
        backgroundColor: _kBg,
        appBar: _appBar(),
        body: _loading
            ? const Center(
                child: CircularProgressIndicator(
                    valueColor: AlwaysStoppedAnimation(_kPrimary)))
            : SingleChildScrollView(
                padding: EdgeInsets.fromLTRB(pad, 24, pad, 120),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    // page header
                    const Text('Update Content',
                        style: TextStyle(
                          fontFamily: 'PlayfairDisplay',
                          fontSize: 26,
                          fontWeight: FontWeight.w800,
                          color: _kCharcoal,
                        )),
                    const SizedBox(height: 4),
                    const Text(
                        'Modify metadata or replace images for this content.',
                        style: TextStyle(
                            fontFamily: 'DM Sans',
                            fontSize: 13,
                            color: _kMuted)),
                    const SizedBox(height: 20),

                    // ── Toolbar ───────────────────────────────────────────
                    Wrap(spacing: 10, runSpacing: 10, children: [
                      _ToolBtn(
                        icon: Icons.history_rounded,
                        label: 'Version History',
                        onTap: _loadVersionHistory,
                      ),
                      // Publish Now (matches TSX)
                      _ToolBtn(
                        icon: Icons.publish_rounded,
                        label: 'Publish Now',
                        onTap: () => Navigator.pushNamed(
                            context, '/content/publish/$_contentId'),
                      ),
                      // Refresh (matches TSX)
                      _ToolBtn(
                        icon: Icons.refresh_rounded,
                        label: 'Refresh',
                        onTap: () async {
                          await Future.wait(
                              [_loadContent(), _loadCategories()]);
                        },
                      ),
                    ]),
                    const SizedBox(height: 20),

                    // ── Current Files ─────────────────────────────────────
                    _sectionCard(
                      title: 'Current Files',
                      icon: Icons.folder_open_outlined,
                      children: [
                        if (_currentFileUrl.isNotEmpty)
                          _FileRow(
                            icon: Icons.insert_drive_file_outlined,
                            iconColor: _kBlue,
                            iconBg: _kBlueBg,
                            title: 'Content File',
                            subtitle: 'v${_versionCtrl.text}',
                            url: _currentFileUrl,
                          ),
                        if (_currentCoverUrl.isNotEmpty)
                          _FileRow(
                            icon: Icons.image_outlined,
                            iconColor: _kPrimary,
                            iconBg: const Color(0xFFFEE2E2),
                            title: 'Cover Image',
                            url: _currentCoverUrl,
                          ),
                        if (_currentBackpageUrl.isNotEmpty)
                          _FileRow(
                            icon: Icons.image_outlined,
                            iconColor: _kMuted,
                            iconBg: const Color(0xFFF3F4F6),
                            title: 'Backpage Image',
                            url: _currentBackpageUrl,
                          ),
                        if (_currentFileUrl.isEmpty &&
                            _currentCoverUrl.isEmpty &&
                            _currentBackpageUrl.isEmpty)
                          const Text(
                              'No files currently attached to this content.',
                              style: TextStyle(
                                  fontFamily: 'DM Sans',
                                  fontSize: 13,
                                  color: _kMutedLt)),
                      ],
                    ),
                    const SizedBox(height: 16),

                    // ── Version history panel ─────────────────────────────
                    if (_showHistory) ...[
                      _versionHistoryPanel(),
                      const SizedBox(height: 16),
                    ],

                    // ── Basic Information ─────────────────────────────────
                    _sectionCard(
                      title: 'Basic Information',
                      icon: Icons.info_outline_rounded,
                      children: [
                        _field(_titleCtrl, 'Title',
                            required: true,
                            hint: 'Content title'),
                        const SizedBox(height: 14),
                        _field(_subtitleCtrl, 'Subtitle',
                            hint: 'Subtitle (optional)'),
                        const SizedBox(height: 14),
                        _row2(w, [
                          _dropdown(
                            label: 'Content Type',
                            required: true,
                            value: _contentType,
                            items: _kContentTypes
                                .map((t) => DropdownMenuItem(
                                      value: t,
                                      child: Text(_cap(t),
                                          style: const TextStyle(
                                              fontFamily: 'DM Sans',
                                              fontSize: 14)),
                                    ))
                                .toList(),
                            onChanged: (v) =>
                                setState(() => _contentType = v ?? 'book'),
                          ),
                          _dropdown(
                            label: 'Status',
                            value: _status,
                            items: _kStatusOptions
                                .map((o) => DropdownMenuItem(
                                      value: o.$1,
                                      child: Text(o.$2,
                                          style: const TextStyle(
                                              fontFamily: 'DM Sans',
                                              fontSize: 14)),
                                    ))
                                .toList(),
                            onChanged: (v) =>
                                setState(() => _status = v ?? 'draft'),
                          ),
                        ]),
                        if (_isEbook) ...[
                          const SizedBox(height: 8),
                          _amberNote(
                              'Ebooks require cover and backpage images.'),
                        ],
                        if (_status == 'published') ...[
                          const SizedBox(height: 8),
                          Container(
                            padding: const EdgeInsets.all(10),
                            decoration: BoxDecoration(
                              color: _kGreenBg,
                              borderRadius: BorderRadius.circular(8),
                              border: Border.all(
                                  color: _kGreen.withOpacity(0.3)),
                            ),
                            child: const Row(children: [
                              Icon(Icons.check_circle_outline,
                                  size: 14, color: _kGreen),
                              SizedBox(width: 8),
                              Expanded(
                                child: Text(
                                    'This content is currently live and visible to users.',
                                    style: TextStyle(
                                        fontFamily: 'DM Sans',
                                        fontSize: 11,
                                        color: _kGreen)),
                              ),
                            ]),
                          ),
                        ],
                        const SizedBox(height: 14),
                        _row2(w, [
                          Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              _field(_authorCtrl, 'Author (display name)',
                                  hint: 'Author name or pen name'),
                              const SizedBox(height: 4),
                              const Text(
                                  'Shown on the listing. Can differ from the linked profile below.',
                                  style: TextStyle(
                                      fontFamily: 'DM Sans',
                                      fontSize: 11,
                                      color: _kMutedLt)),
                            ],
                          ),
                          _field(_publisherCtrl, 'Publisher',
                              hint: 'Publisher name'),
                        ]),
                      ],
                    ),
                    const SizedBox(height: 16),

                    // ── Linked Author Profile (NEW — matches TSX) ─────────
                    _linkedAuthorCard(),
                    const SizedBox(height: 16),

                    // ── Category & Tags ───────────────────────────────────
                    _sectionCard(
                      title: 'Category & Tags',
                      icon: Icons.label_outline_rounded,
                      children: [
                        _dropdown(
                          label: 'Category',
                          value: _categoryId.isEmpty ? null : _categoryId,
                          hint: 'Select a category',
                          items: _categories
                              .map((cat) => DropdownMenuItem(
                                    value: cat['id'] as String,
                                    child: Text(cat['name'] as String,
                                        style: const TextStyle(
                                            fontFamily: 'DM Sans',
                                            fontSize: 14)),
                                  ))
                              .toList(),
                          onChanged: (v) {
                            setState(() => _categoryId = v ?? '');
                            if (v != null) _partialSave({'category_id': v});
                          },
                        ),
                        const SizedBox(height: 14),
                        _field(_tagsCtrl, 'Tags',
                            hint: 'fiction, adventure, fantasy…'),
                        const SizedBox(height: 4),
                        const Text('Separate tags with commas.',
                            style: TextStyle(
                                fontFamily: 'DM Sans',
                                fontSize: 11,
                                color: _kMutedLt)),
                      ],
                    ),
                    const SizedBox(height: 16),

                    // ── Sales & Inventory ─────────────────────────────────
                    _sectionCard(
                      title: 'Sales & Inventory',
                      icon: Icons.storefront_outlined,
                      children: [
                        _row2(w, [
                          _field(_priceCtrl, 'Price (KES)',
                              hint: '0.00',
                              keyboard: const TextInputType
                                  .numberWithOptions(decimal: true),
                              inputFormatters: [
                                FilteringTextInputFormatter.allow(
                                    RegExp(r'^\d*\.?\d{0,2}'))
                              ],
                              onEditingComplete: () => _partialSave({
                                    'price': _priceCtrl.text.isNotEmpty
                                        ? _priceCtrl.text
                                        : '0'
                                  })),
                          _field(_stockCtrl, 'Stock Quantity',
                              hint: '0',
                              keyboard: TextInputType.number,
                              inputFormatters: [
                                FilteringTextInputFormatter.digitsOnly
                              ],
                              onEditingComplete: () => _partialSave({
                                    'stock_quantity':
                                        _stockCtrl.text.isNotEmpty
                                            ? _stockCtrl.text
                                            : '0'
                                  })),
                        ]),
                        const SizedBox(height: 16),
                        // is_free toggle (ADDED — matches TSX)
                        _Toggle(
                          label: 'Free content (no purchase required)',
                          value: _isFree,
                          onChanged: (v) {
                            setState(() => _isFree = v);
                            _partialSave({'is_free': v});
                          },
                        ),
                        const SizedBox(height: 10),
                        _Toggle(
                          label: 'Available for sale',
                          value: _isForSale,
                          onChanged: (v) {
                            setState(() => _isForSale = v);
                            _partialSave({'is_for_sale': v});
                          },
                        ),
                        const SizedBox(height: 10),
                        _Toggle(
                          label: 'Feature this content',
                          value: _isFeatured,
                          onChanged: (v) {
                            setState(() => _isFeatured = v);
                            _partialSave({'is_featured': v});
                          },
                        ),
                      ],
                    ),
                    const SizedBox(height: 16),

                    // ── Additional Details ────────────────────────────────
                    _sectionCard(
                      title: 'Additional Details',
                      icon: Icons.tune_rounded,
                      children: [
                        _row2(w, [
                          _field(_isbnCtrl, 'ISBN', hint: 'Enter ISBN'),
                          _field(_pageCountCtrl, 'Page Count',
                              hint: '0',
                              keyboard: TextInputType.number,
                              inputFormatters: [
                                FilteringTextInputFormatter.digitsOnly
                              ],
                              onEditingComplete: () => _partialSave(
                                  {'page_count': _pageCountCtrl.text})),
                        ]),
                        const SizedBox(height: 14),
                        _row2(w, [
                          _dropdown(
                            label: 'Language',
                            value: _language,
                            items: _kLanguages
                                .map((l) => DropdownMenuItem(
                                      value: l.$1,
                                      child: Text(l.$2,
                                          style: const TextStyle(
                                              fontFamily: 'DM Sans',
                                              fontSize: 14)),
                                    ))
                                .toList(),
                            onChanged: (v) =>
                                setState(() => _language = v ?? 'en'),
                          ),
                          _dropdown(
                            label: 'Visibility',
                            value: _visibility,
                            items: _kVisibilityOptions
                                .map((o) => DropdownMenuItem(
                                      value: o.$1,
                                      child: Text(o.$2,
                                          style: const TextStyle(
                                              fontFamily: 'DM Sans',
                                              fontSize: 14)),
                                    ))
                                .toList(),
                            onChanged: (v) =>
                                setState(() => _visibility = v ?? 'private'),
                          ),
                        ]),
                        const SizedBox(height: 14),
                        _field(_versionCtrl, 'Version', hint: '1.0'),
                        const SizedBox(height: 14),
                        _lbl('Description'),
                        const SizedBox(height: 6),
                        TextField(
                          controller: _descriptionCtrl,
                          maxLines: 5,
                          style: const TextStyle(
                              fontFamily: 'DM Sans',
                              fontSize: 14,
                              color: _kCharcoal),
                          decoration: _inputDec(
                              'Provide a detailed description…'),
                        ),
                      ],
                    ),
                    const SizedBox(height: 16),

                    // ── Replace Images ────────────────────────────────────
                    _sectionCard(
                      title: 'Replace Images',
                      icon: Icons.image_outlined,
                      children: [
                        LayoutBuilder(builder: (_, c) {
                          if (c.maxWidth >= 500) {
                            return Row(
                              crossAxisAlignment:
                                  CrossAxisAlignment.start,
                              children: [
                                Expanded(
                                    child: _imagePicker(
                                        label: 'Replace Cover Image',
                                        file: _coverFile,
                                        name: _coverName,
                                        onPick: () => _pickImage(true),
                                        onRemove: () =>
                                            _removeFile(true))),
                                const SizedBox(width: 16),
                                Expanded(
                                    child: _imagePicker(
                                        label: 'Replace Backpage Image',
                                        file: _backpageFile,
                                        name: _backpageName,
                                        onPick: () => _pickImage(false),
                                        onRemove: () =>
                                            _removeFile(false))),
                              ],
                            );
                          }
                          return Column(children: [
                            _imagePicker(
                                label: 'Replace Cover Image',
                                file: _coverFile,
                                name: _coverName,
                                onPick: () => _pickImage(true),
                                onRemove: () => _removeFile(true)),
                            const SizedBox(height: 14),
                            _imagePicker(
                                label: 'Replace Backpage Image',
                                file: _backpageFile,
                                name: _backpageName,
                                onPick: () => _pickImage(false),
                                onRemove: () => _removeFile(false)),
                          ]);
                        }),
                      ],
                    ),
                    const SizedBox(height: 28),

                    // ── Submit / Cancel ───────────────────────────────────
                    Row(children: [
                      Expanded(
                        child: SizedBox(
                          height: 52,
                          child: ElevatedButton(
                            onPressed: (_updating || _ownerSaving)
                                ? null
                                : _submit,
                            style: ElevatedButton.styleFrom(
                              backgroundColor: _kPrimary,
                              foregroundColor: _kWhite,
                              elevation: 0,
                              disabledBackgroundColor:
                                  _kPrimary.withOpacity(0.5),
                              shape: RoundedRectangleBorder(
                                  borderRadius:
                                      BorderRadius.circular(12)),
                            ),
                            child: _updating
                                ? const Row(
                                    mainAxisAlignment:
                                        MainAxisAlignment.center,
                                    children: [
                                      SizedBox(
                                        width: 18, height: 18,
                                        child:
                                            CircularProgressIndicator(
                                                strokeWidth: 2.5,
                                                color: _kWhite),
                                      ),
                                      SizedBox(width: 10),
                                      Text('Updating…',
                                          style: TextStyle(
                                              fontFamily: 'DM Sans',
                                              fontWeight:
                                                  FontWeight.w700,
                                              fontSize: 15)),
                                    ],
                                  )
                                : const Row(
                                    mainAxisAlignment:
                                        MainAxisAlignment.center,
                                    children: [
                                      Icon(Icons.save_outlined,
                                          size: 18),
                                      SizedBox(width: 8),
                                      Text('Save Changes',
                                          style: TextStyle(
                                              fontFamily: 'DM Sans',
                                              fontWeight:
                                                  FontWeight.w700,
                                              fontSize: 15)),
                                    ],
                                  ),
                          ),
                        ),
                      ),
                      const SizedBox(width: 12),
                      SizedBox(
                        height: 52,
                        child: OutlinedButton(
                          onPressed: (_updating || _ownerSaving)
                              ? null
                              : () => Navigator.pop(context),
                          style: OutlinedButton.styleFrom(
                            foregroundColor: _kMuted,
                            side: const BorderSide(color: _kBorder),
                            shape: RoundedRectangleBorder(
                                borderRadius:
                                    BorderRadius.circular(12)),
                            padding: const EdgeInsets.symmetric(
                                horizontal: 20),
                          ),
                          child: const Text('Cancel',
                              style: TextStyle(
                                  fontFamily: 'DM Sans',
                                  fontWeight: FontWeight.w600)),
                        ),
                      ),
                    ]),
                  ],
                ),
              ),
      ),
    );
  }

  // ══════════════════════════════════════════════════════════════════════════
  // LINKED AUTHOR CARD  (NEW — mirrors TSX "Linked Author Profile" card)
  // ══════════════════════════════════════════════════════════════════════════

  Widget _linkedAuthorCard() => _sectionCard(
        title: 'Linked Author Profile',
        icon: Icons.person_pin_outlined,
        children: [
          // ── Currently linked author chip ────────────────────────────────
          if (_linkedAuthor != null)
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: const Color(0xFFF9FAFB),
                borderRadius: BorderRadius.circular(10),
                border: Border.all(color: _kBorder),
              ),
              child: Row(children: [
                _authorAvatar(_linkedAuthor!, size: 40),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        _linkedAuthor!.fullName ?? '—',
                        style: const TextStyle(
                            fontFamily: 'DM Sans',
                            fontSize: 13,
                            fontWeight: FontWeight.w600,
                            color: _kCharcoal),
                      ),
                      if (_linkedAuthor!.email != null)
                        Text(
                          _linkedAuthor!.email!,
                          style: const TextStyle(
                              fontFamily: 'DM Sans',
                              fontSize: 11,
                              color: _kMuted),
                        ),
                    ],
                  ),
                ),
                Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 7, vertical: 3),
                  decoration: BoxDecoration(
                    color: const Color(0xFFF3F4F6),
                    borderRadius: BorderRadius.circular(6),
                  ),
                  child: const Text('Author',
                      style: TextStyle(
                          fontFamily: 'DM Sans',
                          fontSize: 10,
                          fontWeight: FontWeight.w700,
                          color: _kMuted)),
                ),
                const SizedBox(width: 8),
                // Unlink button
                GestureDetector(
                  onTap: _ownerSaving ? null : _handleAuthorClear,
                  child: Container(
                    padding: const EdgeInsets.symmetric(
                        horizontal: 10, vertical: 6),
                    decoration: BoxDecoration(
                      border: Border.all(
                          color: _kRed.withOpacity(0.3)),
                      borderRadius: BorderRadius.circular(6),
                    ),
                    child: _ownerSaving
                        ? const SizedBox(
                            width: 12, height: 12,
                            child: CircularProgressIndicator(
                                strokeWidth: 2, color: _kRed))
                        : const Row(mainAxisSize: MainAxisSize.min, children: [
                            Icon(Icons.link_off_rounded,
                                size: 12, color: _kRed),
                            SizedBox(width: 4),
                            Text('Unlink',
                                style: TextStyle(
                                    fontFamily: 'DM Sans',
                                    fontSize: 11,
                                    fontWeight: FontWeight.w600,
                                    color: _kRed)),
                          ]),
                  ),
                ),
              ]),
            )
          else
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: const Color(0xFFF9FAFB),
                borderRadius: BorderRadius.circular(10),
                border: Border.all(
                    color: _kBorder, style: BorderStyle.solid),
              ),
              child: const Row(children: [
                Icon(Icons.person_search_outlined,
                    size: 16, color: _kMutedLt),
                SizedBox(width: 8),
                Expanded(
                  child: Text(
                    'No author profile linked. Use the search below to '
                    'connect this content to a registered author account.',
                    style: TextStyle(
                        fontFamily: 'DM Sans',
                        fontSize: 12,
                        color: _kMuted),
                  ),
                ),
              ]),
            ),

          const SizedBox(height: 14),

          // ── Author search input ──────────────────────────────────────────
          _lbl(_linkedAuthor != null
              ? 'Change linked author'
              : 'Search author profiles'),
          const SizedBox(height: 6),
          CompositedTransformTarget(
            link: LayerLink(),
            child: KeyedSubtree(
              key: _authorOverlayKey,
              child: TextField(
                controller: _authorSearchCtrl,
                onChanged: _onAuthorQueryChanged,
                enabled: !_ownerSaving,
                style: const TextStyle(
                    fontFamily: 'DM Sans',
                    fontSize: 14,
                    color: _kCharcoal),
                decoration: _inputDec('Type a name or email…').copyWith(
                  suffixIcon: _authorSearching
                      ? const Padding(
                          padding: EdgeInsets.all(12),
                          child: SizedBox(
                            width: 16, height: 16,
                            child: CircularProgressIndicator(
                                strokeWidth: 2, color: _kMuted),
                          ),
                        )
                      : null,
                ),
              ),
            ),
          ),

          const SizedBox(height: 10),
          RichText(
            text: const TextSpan(
              style: TextStyle(
                  fontFamily: 'DM Sans',
                  fontSize: 11,
                  color: _kMutedLt),
              children: [
                TextSpan(text: 'Linking sets '),
                TextSpan(
                    text: 'content_owner',
                    style: TextStyle(
                        fontFamily: 'DM Mono',
                        fontSize: 10,
                        color: _kCharcoal,
                        backgroundColor: Color(0xFFF3F4F6))),
                TextSpan(
                    text: ' to the selected author\'s UUID. '
                        'Changes save immediately. Only '
                        'author-role accounts appear in results.'),
              ],
            ),
          ),
        ],
      );

  Widget _authorAvatar(_AuthorProfile p, {double size = 36}) {
    if (p.avatarUrl != null && p.avatarUrl!.isNotEmpty) {
      return ClipOval(
        child: Image.network(p.avatarUrl!,
            width: size,
            height: size,
            fit: BoxFit.cover,
            errorBuilder: (_, __, ___) => _initialsAvatar(p, size)),
      );
    }
    return _initialsAvatar(p, size);
  }

  Widget _initialsAvatar(_AuthorProfile p, double size) => Container(
        width: size, height: size,
        decoration: BoxDecoration(
          color: _kPrimary.withOpacity(0.1),
          shape: BoxShape.circle,
          border: Border.all(color: _kPrimary.withOpacity(0.2)),
        ),
        child: Center(
          child: Text(p.initials,
              style: const TextStyle(
                  fontFamily: 'DM Sans',
                  fontWeight: FontWeight.w700,
                  fontSize: 13,
                  color: _kPrimary)),
        ),
      );

  // ══════════════════════════════════════════════════════════════════════════
  // VERSION HISTORY PANEL
  // ══════════════════════════════════════════════════════════════════════════

  Widget _versionHistoryPanel() => Container(
        decoration: BoxDecoration(
          color: _kWhite,
          borderRadius: BorderRadius.circular(_kCard),
          border: Border.all(color: _kPrimary.withOpacity(0.3), width: 1.5),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withOpacity(0.05),
              blurRadius: 8, offset: const Offset(0, 2),
            ),
          ],
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 14, 12, 0),
              child: Row(children: [
                const Icon(Icons.history_rounded,
                    size: 16, color: _kPrimary),
                const SizedBox(width: 8),
                const Text('Version History',
                    style: TextStyle(
                        fontFamily: 'PlayfairDisplay',
                        fontSize: 15,
                        fontWeight: FontWeight.w700,
                        color: _kCharcoal)),
                const Spacer(),
                TextButton(
                  onPressed: () =>
                      setState(() => _showHistory = false),
                  child: const Text('Close',
                      style: TextStyle(
                          fontFamily: 'DM Sans',
                          fontSize: 12,
                          color: _kMuted)),
                ),
              ]),
            ),
            const Divider(color: _kBorder),
            if (_history.isEmpty)
              Padding(
                padding: const EdgeInsets.symmetric(vertical: 32),
                child: Center(
                  child: Column(mainAxisSize: MainAxisSize.min, children: [
                    Icon(Icons.history_rounded,
                        size: 36,
                        color: _kMutedLt.withOpacity(0.5)),
                    const SizedBox(height: 10),
                    const Text('No version history available.',
                        style: TextStyle(
                            fontFamily: 'DM Sans',
                            fontSize: 13,
                            color: _kMutedLt)),
                  ]),
                ),
              )
            else
              ...List.generate(_history.length, (i) {
                final v = _history[i];
                return Container(
                  padding: const EdgeInsets.all(16),
                  decoration: BoxDecoration(
                    border: i < _history.length - 1
                        ? const Border(
                            bottom: BorderSide(color: _kBorder))
                        : null,
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(children: [
                        Text('Version ${v['version_number'] ?? '—'}',
                            style: const TextStyle(
                                fontFamily: 'DM Sans',
                                fontWeight: FontWeight.w700,
                                fontSize: 13,
                                color: _kCharcoal)),
                        const Spacer(),
                        Container(
                          padding: const EdgeInsets.symmetric(
                              horizontal: 7, vertical: 2),
                          decoration: BoxDecoration(
                            color: const Color(0xFFF3F4F6),
                            borderRadius: BorderRadius.circular(6),
                          ),
                          child: Text(v['format'] as String? ?? '—',
                              style: const TextStyle(
                                  fontFamily: 'DM Sans',
                                  fontSize: 10,
                                  fontWeight: FontWeight.w600,
                                  color: _kMuted)),
                        ),
                      ]),
                      const SizedBox(height: 3),
                      Text(
                          '${_dt(v['changed_at'])} · by '
                          '${v['changed_by_name'] ?? 'Unknown'}',
                          style: const TextStyle(
                              fontFamily: 'DM Sans',
                              fontSize: 11,
                              color: _kMutedLt)),
                      if ((v['change_summary'] as String? ?? '')
                          .isNotEmpty) ...[
                        const SizedBox(height: 6),
                        Text(v['change_summary'] as String,
                            style: const TextStyle(
                                fontFamily: 'DM Sans',
                                fontSize: 12,
                                color: _kMuted,
                                height: 1.4)),
                      ],
                    ],
                  ),
                );
              }),
          ],
        ),
      );

  // ══════════════════════════════════════════════════════════════════════════
  // REUSABLE WIDGET HELPERS
  // ══════════════════════════════════════════════════════════════════════════

  Widget _sectionCard({
    required String title,
    required IconData icon,
    required List<Widget> children,
  }) =>
      Container(
        decoration: BoxDecoration(
          color: _kWhite,
          borderRadius: BorderRadius.circular(_kCard),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withOpacity(0.05),
              blurRadius: 8, offset: const Offset(0, 2),
            ),
          ],
        ),
        padding: const EdgeInsets.all(20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(children: [
              Icon(icon, size: 16, color: _kPrimary),
              const SizedBox(width: 8),
              Text(title,
                  style: const TextStyle(
                      fontFamily: 'PlayfairDisplay',
                      fontSize: 16,
                      fontWeight: FontWeight.w700,
                      color: _kCharcoal)),
            ]),
            const SizedBox(height: 14),
            const Divider(height: 1, color: _kBorder),
            const SizedBox(height: 16),
            ...children,
          ],
        ),
      );

  Widget _imagePicker({
    required String label,
    required File? file,
    required String? name,
    required VoidCallback onPick,
    required VoidCallback onRemove,
  }) =>
      Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(children: [
            _lbl(label),
            const SizedBox(width: 4),
            const Text(' (optional)',
                style: TextStyle(
                    fontFamily: 'DM Sans',
                    fontSize: 12,
                    color: _kMutedLt)),
          ]),
          const SizedBox(height: 8),
          GestureDetector(
            onTap: file == null ? onPick : null,
            child: AnimatedContainer(
              duration: const Duration(milliseconds: 200),
              width: double.infinity,
              height: file != null ? null : 90,
              decoration: BoxDecoration(
                color: file != null ? _kWhite : const Color(0xFFF9FAFB),
                borderRadius: BorderRadius.circular(10),
                border: Border.all(
                  color: file != null
                      ? _kGreen.withOpacity(0.4)
                      : const Color(0xFFD1D5DB),
                ),
              ),
              child: file != null
                  ? Padding(
                      padding: const EdgeInsets.all(12),
                      child: Row(children: [
                        ClipRRect(
                          borderRadius: BorderRadius.circular(6),
                          child: Image.file(file,
                              width: 46, height: 62, fit: BoxFit.cover),
                        ),
                        const SizedBox(width: 10),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(name ?? 'image',
                                  style: const TextStyle(
                                      fontFamily: 'DM Sans',
                                      fontSize: 12,
                                      fontWeight: FontWeight.w600,
                                      color: _kCharcoal),
                                  maxLines: 2,
                                  overflow: TextOverflow.ellipsis),
                              const SizedBox(height: 4),
                              const Row(children: [
                                Icon(Icons.check_circle_outline,
                                    size: 12, color: _kGreen),
                                SizedBox(width: 4),
                                Text('Ready to replace',
                                    style: TextStyle(
                                        fontFamily: 'DM Sans',
                                        fontSize: 11,
                                        color: _kGreen)),
                              ]),
                            ],
                          ),
                        ),
                        IconButton(
                          icon: const Icon(Icons.close_rounded,
                              size: 16, color: _kMuted),
                          onPressed: onRemove,
                          padding: EdgeInsets.zero,
                          constraints: const BoxConstraints(
                              minWidth: 24, minHeight: 24),
                        ),
                      ]),
                    )
                  : Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: const [
                        Icon(Icons.add_photo_alternate_outlined,
                            size: 24, color: _kMutedLt),
                        SizedBox(height: 4),
                        Text('Tap to select new image',
                            style: TextStyle(
                                fontFamily: 'DM Sans',
                                fontSize: 11,
                                color: _kMutedLt)),
                        Text('JPG, PNG, WebP · max 10 MB',
                            style: TextStyle(
                                fontFamily: 'DM Sans',
                                fontSize: 10,
                                color: _kMutedLt)),
                      ],
                    ),
            ),
          ),
        ],
      );

  Widget _row2(double w, List<Widget> kids) {
    if (w >= 500) {
      return Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: kids
            .expand((c) =>
                [Expanded(child: c), const SizedBox(width: 14)])
            .toList()
          ..removeLast(),
      );
    }
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: kids
          .expand((c) => [c, const SizedBox(height: 14)])
          .toList()
        ..removeLast(),
    );
  }

  Widget _field(
    TextEditingController ctrl,
    String label, {
    bool required = false,
    String? hint,
    TextInputType keyboard = TextInputType.text,
    List<TextInputFormatter>? inputFormatters,
    VoidCallback? onEditingComplete,
  }) =>
      Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(children: [
            _lbl(label),
            if (required)
              const Text(' *',
                  style: TextStyle(
                      color: _kRed, fontWeight: FontWeight.bold)),
          ]),
          const SizedBox(height: 6),
          TextField(
            controller: ctrl,
            keyboardType: keyboard,
            inputFormatters: inputFormatters,
            onEditingComplete: onEditingComplete,
            style: const TextStyle(
                fontFamily: 'DM Sans', fontSize: 14, color: _kCharcoal),
            decoration: _inputDec(hint),
          ),
        ],
      );

  Widget _dropdown({
    required String label,
    required String? value,
    required List<DropdownMenuItem<String>> items,
    required ValueChanged<String?> onChanged,
    bool required = false,
    String hint = 'Select…',
  }) {
    final validValues = items
        .where((item) => item.value != null)
        .map((item) => item.value!)
        .toSet();
    final safeValue =
        (value != null && validValues.contains(value)) ? value : null;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(children: [
          _lbl(label),
          if (required)
            const Text(' *',
                style: TextStyle(
                    color: _kRed, fontWeight: FontWeight.bold)),
        ]),
        const SizedBox(height: 6),
        DropdownButtonFormField<String>(
          value: safeValue,
          items: items,
          onChanged: onChanged,
          style: const TextStyle(
              fontFamily: 'DM Sans', fontSize: 14, color: _kCharcoal),
          decoration: _inputDec(hint),
          isExpanded: true,
          dropdownColor: _kWhite,
          icon: const Icon(Icons.keyboard_arrow_down_rounded,
              color: _kMuted, size: 20),
        ),
      ],
    );
  }

  InputDecoration _inputDec(String? hint) => InputDecoration(
        hintText: hint,
        hintStyle: const TextStyle(
            fontFamily: 'DM Sans', fontSize: 14, color: _kMutedLt),
        filled: true,
        fillColor: _kWhite,
        contentPadding:
            const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
        border: OutlineInputBorder(
            borderRadius: BorderRadius.circular(8),
            borderSide: const BorderSide(color: _kBorder)),
        enabledBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(8),
            borderSide: const BorderSide(color: _kBorder)),
        focusedBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(8),
            borderSide: const BorderSide(color: _kPrimary, width: 1.5)),
      );

  Widget _lbl(String t) => Text(t,
      style: const TextStyle(
          fontFamily: 'DM Sans',
          fontSize: 13,
          fontWeight: FontWeight.w600,
          color: _kCharcoal));

  Widget _amberNote(String msg) => Container(
        padding: const EdgeInsets.all(10),
        decoration: BoxDecoration(
          color: _kAmberBg,
          border: Border.all(color: const Color(0xFFFDE68A)),
          borderRadius: BorderRadius.circular(8),
        ),
        child: Row(children: [
          const Icon(Icons.info_outline_rounded, size: 14, color: _kAmber),
          const SizedBox(width: 8),
          Expanded(
            child: Text(msg,
                style: const TextStyle(
                    fontFamily: 'DM Sans',
                    fontSize: 11,
                    color: Color(0xFF92400E))),
          ),
        ]),
      );

  AppBar _appBar() => AppBar(
        backgroundColor: _kCharcoal,
        surfaceTintColor: Colors.transparent,
        elevation: 0,
        leading: Navigator.canPop(context)
            ? IconButton(
                icon: const Icon(Icons.arrow_back_ios_new_rounded,
                    size: 18, color: Colors.white70),
                onPressed: () => Navigator.pop(context),
              )
            : null,
        title: const Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('Update Content',
                style: TextStyle(
                    fontFamily: 'PlayfairDisplay',
                    fontSize: 17,
                    fontWeight: FontWeight.w700,
                    color: _kWhite)),
            Text('Admin — edit content',
                style: TextStyle(
                    fontFamily: 'DM Sans',
                    fontSize: 11,
                    color: Colors.white54)),
          ],
        ),
      );

  Widget _splash(String msg) => Scaffold(
        backgroundColor: _kBg,
        body: Center(
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              const SizedBox(
                width: 40, height: 40,
                child: CircularProgressIndicator(
                    strokeWidth: 3,
                    valueColor: AlwaysStoppedAnimation(_kPrimary)),
              ),
              const SizedBox(height: 16),
              Text(msg,
                  style: const TextStyle(
                      fontFamily: 'DM Sans',
                      color: _kMuted,
                      fontSize: 14)),
            ],
          ),
        ),
      );

  String _dt(dynamic raw) {
    if (raw == null) return '—';
    try {
      final d = DateTime.parse(raw as String).toLocal();
      return '${d.day}/${d.month}/${d.year}';
    } catch (_) { return '—'; }
  }

  static double _hp(double w) {
    if (w >= 900) return 32;
    if (w >= 600) return 20;
    return 16;
  }

  String _cap(String s) =>
      s.isEmpty ? s : s[0].toUpperCase() + s.substring(1);

  static String _sanitiseStatus(String raw) =>
      _kValidStatuses.contains(raw) ? raw : 'draft';
}

// ── Author search result tile ─────────────────────────────────────────────

class _AuthorResultTile extends StatelessWidget {
  final _AuthorProfile profile;
  final VoidCallback onTap;
  const _AuthorResultTile({required this.profile, required this.onTap});

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
        decoration: const BoxDecoration(
          border: Border(bottom: BorderSide(color: _kBorder)),
        ),
        child: Row(children: [
          _avatar(),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(profile.fullName ?? '—',
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                        fontFamily: 'DM Sans',
                        fontSize: 13,
                        fontWeight: FontWeight.w600,
                        color: _kCharcoal)),
                if (profile.email != null)
                  Text(profile.email!,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                          fontFamily: 'DM Sans',
                          fontSize: 11,
                          color: _kMuted)),
              ],
            ),
          ),
          Container(
            padding:
                const EdgeInsets.symmetric(horizontal: 7, vertical: 2),
            decoration: BoxDecoration(
              border: Border.all(color: _kBorder),
              borderRadius: BorderRadius.circular(6),
            ),
            child: const Text('Author',
                style: TextStyle(
                    fontFamily: 'DM Sans',
                    fontSize: 10,
                    fontWeight: FontWeight.w600,
                    color: _kMuted)),
          ),
        ]),
      ),
    );
  }

  Widget _avatar() {
    if (profile.avatarUrl != null && profile.avatarUrl!.isNotEmpty) {
      return ClipOval(
        child: Image.network(profile.avatarUrl!,
            width: 32, height: 32, fit: BoxFit.cover,
            errorBuilder: (_, __, ___) => _initials()),
      );
    }
    return _initials();
  }

  Widget _initials() => Container(
        width: 32, height: 32,
        decoration: BoxDecoration(
          color: _kPrimary.withOpacity(0.1),
          shape: BoxShape.circle,
        ),
        child: Center(
          child: Text(profile.initials,
              style: const TextStyle(
                  fontFamily: 'DM Sans',
                  fontWeight: FontWeight.w700,
                  fontSize: 12,
                  color: _kPrimary)),
        ),
      );
}

// ── Shared stateless widgets ──────────────────────────────────────────────

class _FileRow extends StatelessWidget {
  final IconData icon;
  final Color iconColor, iconBg;
  final String title;
  final String? subtitle, url;
  const _FileRow({
    required this.icon,
    required this.iconColor,
    required this.iconBg,
    required this.title,
    this.subtitle,
    this.url,
    Key? key,
  }) : super(key: key);

  @override
  Widget build(BuildContext context) => Container(
        margin: const EdgeInsets.only(bottom: 10),
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          border: Border.all(color: _kBorder),
          borderRadius: BorderRadius.circular(10),
        ),
        child: Row(children: [
          Container(
            width: 38, height: 38,
            decoration: BoxDecoration(
                color: iconBg, borderRadius: BorderRadius.circular(9)),
            child: Icon(icon, color: iconColor, size: 18),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(title,
                    style: const TextStyle(
                        fontFamily: 'DM Sans',
                        fontSize: 13,
                        fontWeight: FontWeight.w600,
                        color: _kCharcoal)),
                if (url != null && url!.isNotEmpty)
                  GestureDetector(
                    onTap: () async {
                      final uri = Uri.parse(url!);
                      if (await canLaunchUrl(uri)) {
                        await launchUrl(uri,
                            mode: LaunchMode.externalApplication);
                      }
                    },
                    child: const Text('View current file',
                        style: TextStyle(
                            fontFamily: 'DM Sans',
                            fontSize: 11,
                            color: _kBlue,
                            decoration: TextDecoration.underline)),
                  ),
              ],
            ),
          ),
          if (subtitle != null)
            Container(
              padding: const EdgeInsets.symmetric(
                  horizontal: 7, vertical: 2),
              decoration: BoxDecoration(
                color: const Color(0xFFF3F4F6),
                borderRadius: BorderRadius.circular(6),
              ),
              child: Text(subtitle!,
                  style: const TextStyle(
                      fontFamily: 'DM Sans',
                      fontSize: 10,
                      fontWeight: FontWeight.w700,
                      color: _kMuted)),
            ),
        ]),
      );
}

class _Toggle extends StatelessWidget {
  final String label;
  final bool value;
  final ValueChanged<bool> onChanged;
  const _Toggle({
    required this.label,
    required this.value,
    required this.onChanged,
    Key? key,
  }) : super(key: key);

  @override
  Widget build(BuildContext context) => GestureDetector(
        onTap: () => onChanged(!value),
        child: Row(children: [
          AnimatedContainer(
            duration: const Duration(milliseconds: 180),
            width: 44, height: 24,
            decoration: BoxDecoration(
              color: value ? _kPrimary : const Color(0xFFD1D5DB),
              borderRadius: BorderRadius.circular(12),
            ),
            child: AnimatedAlign(
              duration: const Duration(milliseconds: 180),
              alignment:
                  value ? Alignment.centerRight : Alignment.centerLeft,
              child: Container(
                margin: const EdgeInsets.all(2),
                width: 20, height: 20,
                decoration: const BoxDecoration(
                    color: _kWhite, shape: BoxShape.circle),
              ),
            ),
          ),
          const SizedBox(width: 10),
          Text(label,
              style: const TextStyle(
                  fontFamily: 'DM Sans',
                  fontSize: 13,
                  color: _kCharcoal,
                  fontWeight: FontWeight.w500)),
        ]),
      );
}

class _ToolBtn extends StatelessWidget {
  final IconData icon;
  final String label;
  final VoidCallback onTap;
  const _ToolBtn({
    required this.icon,
    required this.label,
    required this.onTap,
    Key? key,
  }) : super(key: key);

  @override
  Widget build(BuildContext context) => GestureDetector(
        onTap: onTap,
        child: Container(
          padding:
              const EdgeInsets.symmetric(horizontal: 14, vertical: 9),
          decoration: BoxDecoration(
            border: Border.all(color: _kBorder),
            borderRadius: BorderRadius.circular(8),
            color: _kWhite,
          ),
          child: Row(mainAxisSize: MainAxisSize.min, children: [
            Icon(icon, size: 15, color: _kMuted),
            const SizedBox(width: 6),
            Text(label,
                style: const TextStyle(
                    fontFamily: 'DM Sans',
                    fontSize: 12,
                    color: _kMuted,
                    fontWeight: FontWeight.w600)),
          ]),
        ),
      );
}