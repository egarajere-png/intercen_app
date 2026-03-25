import 'dart:async';
// ignore: avoid_web_libraries_in_flutter

import 'web_stub.dart'
    if (dart.library.html) 'web_impl.dart';

import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:url_launcher/url_launcher.dart';

import '../theme/app_colors.dart';

// ─────────────────────────────────────────────────────────────────────────────
// CONTENT READER PAGE
//
// Route  : /content/:contentId
//
// FILE OPENING STRATEGY:
//   Web (Chrome/Safari/etc.)
//     → Forces a browser download via a hidden <a download> anchor click.
//       The OS then opens the file in the user's default app
//       (WPS Office, Microsoft Word, Adobe Acrobat, etc.).
//       This bypasses the browser's built-in PDF/DOCX viewer entirely.
//
//   Mobile (Android/iOS)
//     → url_launcher fires an OS intent / share sheet.
//       User picks WPS, Word, Adobe, etc. from their installed apps.
//
// VIEWER ROUTING (fallback when no file, or for images):
//   .jpg/.jpeg/.png/.webp  → _ImagePageViewer  (swipeable, pinch-to-zoom)
//   no file / text only    → scrollable paragraph reader
//
// ACCESS MODEL (tiered):
//   Tier 0  public + free          → no login
//   Tier 1  public + auth          → login required, no purchase
//   Tier 2  paid (is_for_sale/price > 0) → must have paid order_item
//   Tier 3  org-restricted (private) → must be org member
// ─────────────────────────────────────────────────────────────────────────────

// ── Viewer mode ───────────────────────────────────────────────────────────────

enum _ViewerMode { externalFile, image, text }

// ── Reader theme ──────────────────────────────────────────────────────────────

enum _ReaderTheme { parchment, white, dark, sepia }

extension _ReaderThemeX on _ReaderTheme {
  Color get bg => switch (this) {
        _ReaderTheme.white => const Color(0xFFFFFFFF),
        _ReaderTheme.dark => const Color(0xFF141420),
        _ReaderTheme.sepia => const Color(0xFFF6ECD8),
        _ => const Color(0xFFF8F4EE),
      };
  Color get surface => switch (this) {
        _ReaderTheme.dark => const Color(0xFF1E1E2E),
        _ReaderTheme.sepia => const Color(0xFFEEDFC4),
        _ReaderTheme.white => const Color(0xFFF8F8F8),
        _ => const Color(0xFFF0EAE0),
      };
  Color get text => switch (this) {
        _ReaderTheme.dark => const Color(0xFFE4E2D8),
        _ => const Color(0xFF1C1C28),
      };
  Color get subText => switch (this) {
        _ReaderTheme.dark => const Color(0xFF8B8FA8),
        _ReaderTheme.sepia => const Color(0xFF7A6A52),
        _ => const Color(0xFF6B7080),
      };
  Color get divider => switch (this) {
        _ReaderTheme.dark => const Color(0xFF2E2E40),
        _ => const Color(0xFFE0DAD2),
      };
  String get label => switch (this) {
        _ReaderTheme.white => 'White',
        _ReaderTheme.dark => 'Dark',
        _ReaderTheme.sepia => 'Sepia',
        _ => 'Parchment',
      };
  bool get isDark => this == _ReaderTheme.dark;
}

// ── Reader settings ───────────────────────────────────────────────────────────

class _ReaderSettings {
  double fontSize;
  String fontFamily;
  double lineHeight;
  _ReaderTheme theme;
  bool immersive;

  _ReaderSettings({
    this.fontSize = 16.0,
    this.fontFamily = 'DM Sans',
    this.lineHeight = 1.5,
    this.theme = _ReaderTheme.white,
    this.immersive = false,
  });
}

// ── File type info helper ─────────────────────────────────────────────────────

class _FileTypeInfo {
  final String label;
  final String mimeType;
  final IconData icon;
  final Color color;
  final List<String> suggestedApps;

  const _FileTypeInfo({
    required this.label,
    required this.mimeType,
    required this.icon,
    required this.color,
    required this.suggestedApps,
  });

  static _FileTypeInfo fromUrl(String? url) {
    if (url == null) return _unknown;
    final q = url.toLowerCase().split('?').first;
    if (q.endsWith('.pdf'))  return _pdf;
    if (q.endsWith('.epub')) return _epub;
    if (q.endsWith('.doc'))  return _doc;
    if (q.endsWith('.docx')) return _docx;
    if (q.endsWith('.txt'))  return _txt;
    return _unknown;
  }

  /// Returns a suggested filename derived from the URL, e.g. "my-book.pdf"
  static String fileNameFromUrl(String url) {
    try {
      final path = Uri.parse(url).pathSegments;
      if (path.isNotEmpty && path.last.contains('.')) return path.last;
    } catch (_) {}
    return 'document';
  }

  static const _pdf = _FileTypeInfo(
    label: 'PDF Document',
    mimeType: 'application/pdf',
    icon: Icons.picture_as_pdf_rounded,
    color: Color(0xFFEF4444),
    suggestedApps: ['Adobe Acrobat', 'WPS Office', 'Google Drive', 'Files'],
  );
  static const _epub = _FileTypeInfo(
    label: 'EPUB eBook',
    mimeType: 'application/epub+zip',
    icon: Icons.auto_stories_rounded,
    color: Color(0xFF8B5CF6),
    suggestedApps: ['Google Play Books', 'Moon+ Reader', 'ReadEra', 'Calibre'],
  );
  static const _doc = _FileTypeInfo(
    label: 'Word Document',
    mimeType: 'application/msword',
    icon: Icons.description_rounded,
    color: Color(0xFF2563EB),
    suggestedApps: ['Microsoft Word', 'WPS Office', 'Google Docs'],
  );
  static const _docx = _FileTypeInfo(
    label: 'Word Document',
    mimeType:
        'application/vnd.openxmlformats-officedocument.wordprocessingml.document',
    icon: Icons.description_rounded,
    color: Color(0xFF2563EB),
    suggestedApps: ['Microsoft Word', 'WPS Office', 'Google Docs'],
  );
  static const _txt = _FileTypeInfo(
    label: 'Text File',
    mimeType: 'text/plain',
    icon: Icons.text_snippet_rounded,
    color: Color(0xFF6B7280),
    suggestedApps: ['Notes', 'Google Docs', 'WPS Office'],
  );
  static const _unknown = _FileTypeInfo(
    label: 'Document',
    mimeType: 'application/octet-stream',
    icon: Icons.insert_drive_file_rounded,
    color: Color(0xFF6B7280),
    suggestedApps: ['WPS Office', 'Microsoft Office', 'Google Drive'],
  );
}

// ─────────────────────────────────────────────────────────────────────────────
// PAGE
// ─────────────────────────────────────────────────────────────────────────────

class ContentReaderPage extends StatefulWidget {
  final String contentId;
  const ContentReaderPage({super.key, required this.contentId});

  @override
  State<ContentReaderPage> createState() => _ContentReaderPageState();
}

class _ContentReaderPageState extends State<ContentReaderPage>
    with WidgetsBindingObserver {
  final _sb = Supabase.instance.client;
  final _scrollCtrl = ScrollController();
  final _settings = _ReaderSettings();

  // ── State ────────────────────────────────────────────────────────────────
  Map<String, dynamic>? _content;
  String? _bodyText;
  bool _loading = true;
  String? _accessError;

  // Viewer
  _ViewerMode _viewerMode = _ViewerMode.text;
  String? _fileUrl;
  bool _isLaunching = false;

  // Toolbar
  bool _toolbarVisible = true;
  Timer? _toolbarTimer;

  // Progress
  double _readProgress = 0;
  bool _reviewPrompted = false;
  bool _showSettings = false;
  bool _bookmarked = false;

  // Reading progress sync
  Timer? _progressSaveTimer;

  // ── Helpers ───────────────────────────────────────────────────────────────
  int get _estMinutes {
    if (_bodyText == null || _viewerMode != _ViewerMode.text) return 0;
    return (_bodyText!.trim().split(RegExp(r'\s+')).length / 250).ceil();
  }

  double get _progress => _readProgress;

  bool get _hasFile => _fileUrl != null && _fileUrl!.isNotEmpty;

  static _ViewerMode _detectMode(
    String? fileUrl,
    String? contentType,
    String? coverImageUrl,
  ) {
    if (fileUrl != null && fileUrl.isNotEmpty) {
      final q = fileUrl.toLowerCase().split('?').first;
      if (q.endsWith('.jpg') ||
          q.endsWith('.jpeg') ||
          q.endsWith('.png') ||
          q.endsWith('.webp')) {
        return _ViewerMode.image;
      }
      final ct = (contentType ?? '').toLowerCase();
      if (ct.contains('image')) return _ViewerMode.image;
      return _ViewerMode.externalFile;
    }

    if (coverImageUrl != null && coverImageUrl.isNotEmpty) {
      return _ViewerMode.image;
    }

    return _ViewerMode.text;
  }

  // ─────────────────────────────────────────────────────────────────────────
  // OPEN WITH EXTERNAL APP
  // ─────────────────────────────────────────────────────────────────────────
  Future<void> _openWithExternalApp() async {
    if (!_hasFile) return;

    final fileInfo = _FileTypeInfo.fromUrl(_fileUrl);

    if (kIsWeb) {
      await _launchFileUrl();
      return;
    }

    if (!mounted) return;
    final shouldOpen = await showModalBottomSheet<bool>(
      context: context,
      backgroundColor: Colors.transparent,
      isScrollControlled: true,
      builder: (_) => _OpenWithSheet(
        fileInfo: fileInfo,
        fileName: _content?['title'] as String? ?? 'Document',
        onOpen: () => Navigator.pop(context, true),
        onCancel: () => Navigator.pop(context, false),
      ),
    );

    if (shouldOpen == true) {
      await _launchFileUrl();
    }
  }

  // ─────────────────────────────────────────────────────────────────────────
  // WEB: Force-download via the platform-conditional downloadFile() function.
  //
  // On web  → web_impl.dart creates a hidden <a download> anchor and clicks it.
  // On mobile → web_stub.dart throws UnsupportedError (never called on mobile).
  //
  // This method is only ever invoked when kIsWeb == true (see _launchFileUrl),
  // so the stub will never actually throw in practice.
  // ─────────────────────────────────────────────────────────────────────────
  void _downloadFileWeb() {
    final url      = _fileUrl!;
    final fileName = _FileTypeInfo.fileNameFromUrl(url);

    // Delegates to web_impl.dart on web, web_stub.dart on mobile.
    // Since this is only called when kIsWeb == true, the stub is never reached.
    downloadFile(url, fileName);

    debugPrint('[Reader] Web download triggered: $fileName');
  }

  Future<void> _launchFileUrl() async {
    if (!_hasFile || _isLaunching) return;
    setState(() => _isLaunching = true);

    try {
      if (kIsWeb) {
        // ── WEB: force download via hidden <a download> anchor ────────────
        _downloadFileWeb();

        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(SnackBar(
            content: Row(children: [
              const Icon(Icons.download_done_rounded,
                  color: Colors.white, size: 18),
              const SizedBox(width: 10),
              const Expanded(
                child: Text(
                  'Download started — open the file with WPS, Word, or your default app.',
                  style: TextStyle(fontFamily: 'DM Sans', fontSize: 13),
                ),
              ),
            ]),
            backgroundColor: const Color(0xFF16A34A),
            behavior: SnackBarBehavior.floating,
            shape:
                RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
            margin: const EdgeInsets.all(12),
            duration: const Duration(seconds: 5),
            action: SnackBarAction(
              label: 'Copy Link',
              textColor: Colors.white,
              onPressed: () {
                Clipboard.setData(ClipboardData(text: _fileUrl ?? ''));
                ScaffoldMessenger.of(context).showSnackBar(SnackBar(
                  content: const Text('Link copied to clipboard',
                      style: TextStyle(fontFamily: 'DM Sans', fontSize: 13)),
                  backgroundColor: const Color(0xFF2563EB),
                  behavior: SnackBarBehavior.floating,
                  shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(10)),
                  margin: const EdgeInsets.all(12),
                ));
              },
            ),
          ));
        }
      } else {
        // ── MOBILE: OS intent / share sheet ──────────────────────────────
        final uri = Uri.parse(_fileUrl!);

        final launched = await launchUrl(
          uri,
          mode: LaunchMode.externalApplication,
        );

        if (!launched && mounted) {
          final fallback = await launchUrl(
            uri,
            mode: LaunchMode.inAppBrowserView,
          );
          if (!fallback && mounted) _showLaunchError();
        }
      }

      _saveReadingProgress();
    } catch (e) {
      debugPrint('[Reader] Failed to open file: $e');
      if (mounted) _showLaunchError();
    } finally {
      if (mounted) setState(() => _isLaunching = false);
    }
  }

  void _showLaunchError() {
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(
      content: const Text(
        'Could not open file. No compatible app found.',
        style: TextStyle(fontFamily: 'DM Sans', fontSize: 13),
      ),
      backgroundColor: const Color(0xFFEF4444),
      behavior: SnackBarBehavior.floating,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
      margin: const EdgeInsets.all(12),
      action: SnackBarAction(
        label: 'Copy Link',
        textColor: Colors.white,
        onPressed: () {
          Clipboard.setData(ClipboardData(text: _fileUrl ?? ''));
          ScaffoldMessenger.of(context).showSnackBar(SnackBar(
            content: const Text('Link copied to clipboard',
                style: TextStyle(fontFamily: 'DM Sans', fontSize: 13)),
            backgroundColor: const Color(0xFF16A34A),
            behavior: SnackBarBehavior.floating,
            shape:
                RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
            margin: const EdgeInsets.all(12),
          ));
        },
      ),
    ));
  }

  // ─────────────────────────────────────────────────────────────────────────
  // LIFECYCLE
  // ─────────────────────────────────────────────────────────────────────────
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _scrollCtrl.addListener(_onScroll);
    _loadAndVerify();
  }

  @override
  void dispose() {
    _toolbarTimer?.cancel();
    _progressSaveTimer?.cancel();
    _saveReadingProgress();
    _scrollCtrl
      ..removeListener(_onScroll)
      ..dispose();
    WidgetsBinding.instance.removeObserver(this);
    SystemChrome.setEnabledSystemUIMode(SystemUiMode.edgeToEdge);
    super.dispose();
  }

  // ─────────────────────────────────────────────────────────────────────────
  // ACCESS VERIFICATION
  // ─────────────────────────────────────────────────────────────────────────
  Future<void> _loadAndVerify() async {
    setState(() {
      _loading = true;
      _accessError = null;
    });

    try {
      final data = await _sb.from('content').select('''
        id, title, subtitle, author, content_type, description,
        cover_image_url, backpage_image_url, page_count, language,
        publisher, file_url, isbn, version,
        total_downloads, total_reviews, created_at, updated_at,
        visibility, access_level, is_free, is_for_sale, price,
        organization_id, status, uploaded_by
      ''').eq('id', widget.contentId).eq('status', 'published').maybeSingle();

      if (data == null) {
        setState(() {
          _accessError = 'not_found';
          _loading = false;
        });
        return;
      }

      final visibility = data['visibility'] as String? ?? 'private';
      final isFree = data['is_free'] as bool? ?? false;
      final price = (data['price'] as num?)?.toDouble() ?? 0.0;
      final isForSale = data['is_for_sale'] as bool? ?? false;
      final orgId = data['organization_id'] as String?;
      final isPublicFree =
          visibility == 'public' && (isFree || price == 0.0) && !isForSale;

      if (!isPublicFree) {
        final session = _sb.auth.currentSession;
        if (session == null) {
          WidgetsBinding.instance.addPostFrameCallback((_) {
            if (mounted) {
              Navigator.pushNamedAndRemoveUntil(
                  context, '/login', (_) => false,
                  arguments: {'redirect': '/content/${widget.contentId}'});
            }
          });
          return;
        }
        try {
          await _sb.auth.refreshSession();
        } catch (_) {
          if (mounted) {
            Navigator.pushNamedAndRemoveUntil(
                context, '/login', (_) => false);
          }
          return;
        }

        final uid = _sb.auth.currentUser!.id;

        if (visibility == 'private' && orgId != null) {
          final orgCheck = await _sb
              .from('organization_members')
              .select('role')
              .eq('organization_id', orgId)
              .eq('user_id', uid)
              .maybeSingle();
          if (orgCheck == null) {
            setState(() {
              _accessError = 'org_required';
              _loading = false;
            });
            return;
          }
        }

        if (isForSale || price > 0.0) {
          final purchase = await _sb
              .from('order_items')
              .select('id, orders!inner(user_id, payment_status)')
              .eq('content_id', widget.contentId)
              .eq('orders.user_id', uid)
              .eq('orders.payment_status', 'paid')
              .limit(1);
          final isUploader = data['uploaded_by'] == uid;
          if (purchase.isEmpty && !isUploader) {
            setState(() {
              _accessError = 'purchase_required';
              _content = data;
              _loading = false;
            });
            return;
          }
        }
      }

      final downloads = (data['total_downloads'] as int?) ?? 0;
      _sb
          .from('content')
          .update({'total_downloads': downloads + 1})
          .eq('id', widget.contentId)
          .ignore();

      final fileUrl = data['file_url'] as String?;
      final contentType = data['content_type'] as String?;
      final description = data['description'] as String?;
      final coverUrl = data['cover_image_url'] as String?;
      final mode = _detectMode(fileUrl, contentType, coverUrl);

      debugPrint('[Reader] contentId=${widget.contentId}');
      debugPrint('[Reader] file_url=$fileUrl  cover=$coverUrl');
      debugPrint('[Reader] content_type=$contentType  mode=$mode');

      if (mounted) {
        setState(() {
          _content = data;
          _fileUrl = fileUrl;
          _viewerMode = mode;
          _bodyText = (description != null && description.isNotEmpty)
              ? description
              : null;
          _loading = false;
        });
      }
      _loadBookmarkState();
      _loadReadingProgress();
    } catch (e) {
      debugPrint('ContentReaderPage error: $e');
      if (mounted) {
        setState(() {
          _accessError = 'not_found';
          _loading = false;
        });
      }
    }
  }

  // ── Bookmark ──────────────────────────────────────────────────────────────
  Future<void> _loadBookmarkState() async {
    final user = _sb.auth.currentUser;
    if (user == null) return;
    try {
      final r = await _sb
          .from('bookmarks')
          .select('id')
          .eq('user_id', user.id)
          .eq('content_id', widget.contentId)
          .limit(1)
          .maybeSingle();
      if (mounted) setState(() => _bookmarked = r != null);
    } catch (e) {
      debugPrint('loadBookmarkState error: $e');
    }
  }

  Future<void> _toggleBookmark() async {
    final user = _sb.auth.currentUser;
    if (user == null) return;
    final was = _bookmarked;
    setState(() => _bookmarked = !_bookmarked);
    try {
      if (was) {
        await _sb
            .from('bookmarks')
            .delete()
            .eq('user_id', user.id)
            .eq('content_id', widget.contentId);
      } else {
        await _sb.from('bookmarks').insert({
          'user_id': user.id,
          'content_id': widget.contentId,
          'created_at': DateTime.now().toIso8601String(),
        });
      }
    } catch (e) {
      debugPrint('toggleBookmark error: $e');
      if (mounted) setState(() => _bookmarked = was);
    }
  }

  // ── Reading progress ───────────────────────────────────────────────────────
  Future<void> _loadReadingProgress() async {
    final user = _sb.auth.currentUser;
    if (user == null) return;
    try {
      final r = await _sb
          .from('reading_progress')
          .select('percentage, current_page, total_pages')
          .eq('user_id', user.id)
          .eq('content_id', widget.contentId)
          .maybeSingle();
      if (r != null && mounted) {
        final pct = (r['percentage'] as num?)?.toDouble() ?? 0;
        setState(() => _readProgress = (pct / 100).clamp(0.0, 1.0));
        if (_viewerMode == _ViewerMode.text && _scrollCtrl.hasClients) {
          final max = _scrollCtrl.position.maxScrollExtent;
          _scrollCtrl.jumpTo((_readProgress * max).clamp(0, max));
        }
      }
    } catch (e) {
      debugPrint('loadReadingProgress error: $e');
    }
  }

  void _scheduleProgressSave() {
    _progressSaveTimer?.cancel();
    _progressSaveTimer =
        Timer(const Duration(seconds: 3), _saveReadingProgress);
  }

  Future<void> _saveReadingProgress() async {
    final user = _sb.auth.currentUser;
    if (user == null) return;
    try {
      final pct = (_readProgress * 100).clamp(0.0, 100.0);
      await _sb.from('reading_progress').upsert({
        'user_id': user.id,
        'content_id': widget.contentId,
        'percentage': double.parse(pct.toStringAsFixed(2)),
        'completed': _readProgress >= 0.98,
        'last_read_at': DateTime.now().toIso8601String(),
      }, onConflict: 'user_id,content_id');
    } catch (e) {
      debugPrint('saveReadingProgress error: $e');
    }
  }

  // ── Scroll ────────────────────────────────────────────────────────────────
  void _onScroll() {
    final max = _scrollCtrl.position.maxScrollExtent;
    if (max <= 0) return;
    final p = (_scrollCtrl.offset / max).clamp(0.0, 1.0);
    if ((p - _readProgress).abs() > 0.005) {
      setState(() => _readProgress = p);
      _scheduleProgressSave();
    }
    if (p >= 0.30 && !_reviewPrompted) {
      _reviewPrompted = true;
      Future.delayed(const Duration(seconds: 2), _showReviewPrompt);
    }
    _scheduleToolbarHide();
  }

  // ── Toolbar ───────────────────────────────────────────────────────────────
  void _scheduleToolbarHide() {
    _toolbarTimer?.cancel();
    if (!_toolbarVisible) return;
    _toolbarTimer = Timer(const Duration(seconds: 3), () {
      if (mounted) setState(() => _toolbarVisible = false);
    });
  }

  void _toggleToolbar() {
    _toolbarTimer?.cancel();
    setState(() {
      _toolbarVisible = !_toolbarVisible;
      if (_showSettings && !_toolbarVisible) _showSettings = false;
    });
    if (_toolbarVisible) _scheduleToolbarHide();
  }

  void _setImmersive(bool on) {
    setState(() => _settings.immersive = on);
    SystemChrome.setEnabledSystemUIMode(
        on ? SystemUiMode.immersiveSticky : SystemUiMode.edgeToEdge);
  }

  // ── Review ────────────────────────────────────────────────────────────────
  void _showReviewPrompt() {
    if (!mounted) return;
    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.transparent,
      isScrollControlled: true,
      builder: (_) => _ReviewSheet(
        contentId: widget.contentId,
        title: _content?['title'] as String? ?? '',
        onSubmit: (rating, text) async {
          final user = _sb.auth.currentUser;
          if (user == null) return;
          await _sb.from('reviews').insert({
            'content_id': widget.contentId,
            'user_id': user.id,
            'rating': rating,
            'review_text': text,
            'created_at': DateTime.now().toIso8601String(),
          });
          if (mounted) {
            ScaffoldMessenger.of(context).showSnackBar(SnackBar(
              content: const Text('Thank you for your review!',
                  style: TextStyle(fontFamily: 'DM Sans', fontSize: 13)),
              backgroundColor: const Color(0xFF16A34A),
              behavior: SnackBarBehavior.floating,
              shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(10)),
              margin: const EdgeInsets.all(12),
            ));
          }
        },
      ),
    );
  }

  // ─────────────────────────────────────────────────────────────────────────
  // BUILD
  // ─────────────────────────────────────────────────────────────────────────
  @override
  Widget build(BuildContext context) {
    if (_loading) return _loadingView();
    if (_accessError != null) return _accessGateView();
    if (_content == null) return _loadingView();

    final theme = _settings.theme;

    Widget mainViewer;
    switch (_viewerMode) {
      case _ViewerMode.externalFile:
        mainViewer = _buildExternalFileView(theme);
        break;
      case _ViewerMode.image:
        mainViewer = _buildImageViewer();
        break;
      case _ViewerMode.text:
        mainViewer = _buildTextViewer(theme);
        break;
    }

    return AnnotatedRegion<SystemUiOverlayStyle>(
      value:
          theme.isDark ? SystemUiOverlayStyle.light : SystemUiOverlayStyle.dark,
      child: Scaffold(
        backgroundColor:
            _viewerMode == _ViewerMode.image ? Colors.black : theme.bg,
        body: GestureDetector(
          onTap: _viewerMode == _ViewerMode.image ? _toggleToolbar : null,
          behavior: HitTestBehavior.translucent,
          child: Stack(children: [
            Positioned.fill(child: mainViewer),

            // Progress line
            Positioned(
              top: 0,
              left: 0,
              right: 0,
              child: LinearProgressIndicator(
                value: _progress,
                minHeight: 2.5,
                backgroundColor: Colors.transparent,
                valueColor: AlwaysStoppedAnimation(AppColors.primary),
              ),
            ),

            // Top toolbar
            AnimatedPositioned(
              duration: const Duration(milliseconds: 260),
              curve: Curves.easeInOut,
              top: _toolbarVisible ? 0 : -80,
              left: 0,
              right: 0,
              child: _buildTopBar(theme),
            ),

            // Bottom bar
            AnimatedPositioned(
              duration: const Duration(milliseconds: 260),
              curve: Curves.easeInOut,
              bottom: _toolbarVisible ? 0 : -80,
              left: 0,
              right: 0,
              child: _buildBottomBar(theme),
            ),

            // Settings panel
            (_showSettings && _viewerMode == _ViewerMode.text)
                ? _buildSettingsPanel(theme)
                : const SizedBox.shrink(),
          ]),
        ),
      ),
    );
  }

  // ═══════════════════════════════════════════════════════════════════════════
  // EXTERNAL FILE VIEW
  // ═══════════════════════════════════════════════════════════════════════════
  Widget _buildExternalFileView(_ReaderTheme theme) {
    final c = _content!;
    final cover = c['cover_image_url'] as String?;
    final backpage = c['backpage_image_url'] as String?;
    final title = c['title'] as String? ?? 'Untitled';
    final subtitle = c['subtitle'] as String?;
    final author = c['author'] as String?;
    final publisher = c['publisher'] as String?;
    final description = c['description'] as String?;
    final ct = c['content_type'] as String? ?? '';
    final language = c['language'] as String? ?? 'en';
    final pageCount = c['page_count'] as int?;
    final fileInfo = _FileTypeInfo.fromUrl(_fileUrl);

    return CustomScrollView(
      controller: _scrollCtrl,
      physics: const BouncingScrollPhysics(),
      slivers: [
        // ── Full-bleed cover hero ──────────────────────────────────────────
        SliverToBoxAdapter(
          child: SizedBox(
            height: MediaQuery.of(context).size.height * 0.55,
            child: Stack(fit: StackFit.expand, children: [
              if (cover != null && cover.isNotEmpty)
                CachedNetworkImage(
                  imageUrl: cover,
                  fit: BoxFit.cover,
                  errorWidget: (_, __, ___) => _coverFallback(fileInfo),
                )
              else
                _coverFallback(fileInfo),
              Positioned.fill(
                  child: Container(
                decoration: BoxDecoration(
                    gradient: LinearGradient(
                  begin: Alignment.topCenter,
                  end: Alignment.bottomCenter,
                  colors: [Colors.black.withOpacity(0.15), theme.bg],
                  stops: const [0.3, 1.0],
                )),
              )),
              // File type badge
              Positioned(
                top: MediaQuery.of(context).padding.top + 58,
                right: 20,
                child: Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
                  decoration: BoxDecoration(
                    color: fileInfo.color,
                    borderRadius: BorderRadius.circular(20),
                    boxShadow: [
                      BoxShadow(
                          color: fileInfo.color.withOpacity(0.35),
                          blurRadius: 10,
                          offset: const Offset(0, 4))
                    ],
                  ),
                  child: Row(mainAxisSize: MainAxisSize.min, children: [
                    Icon(fileInfo.icon, size: 12, color: Colors.white),
                    const SizedBox(width: 5),
                    Text(fileInfo.label,
                        style: const TextStyle(
                            fontFamily: 'DM Sans',
                            fontSize: 11,
                            fontWeight: FontWeight.w700,
                            color: Colors.white)),
                  ]),
                ),
              ),
            ]),
          ),
        ),

        // ── Metadata + CTA ────────────────────────────────────────────────
        SliverToBoxAdapter(
          child: Padding(
            padding: const EdgeInsets.fromLTRB(22, 0, 22, 0),
            child:
                Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Container(
                padding:
                    const EdgeInsets.symmetric(horizontal: 10, vertical: 3),
                decoration: BoxDecoration(
                  color: AppColors.primary.withOpacity(0.10),
                  borderRadius: BorderRadius.circular(20),
                ),
                child: Text(ct.toUpperCase(),
                    style: TextStyle(
                        fontFamily: 'DM Sans',
                        fontSize: 10,
                        fontWeight: FontWeight.w800,
                        letterSpacing: 1.1,
                        color: AppColors.primary)),
              ),
              const SizedBox(height: 10),

              Text(title,
                  style: TextStyle(
                      fontFamily: 'PlayfairDisplay',
                      fontSize: 26,
                      fontWeight: FontWeight.w800,
                      color: theme.text,
                      height: 1.2)),
              if (subtitle != null && subtitle.isNotEmpty) ...[
                const SizedBox(height: 6),
                Text(subtitle,
                    style: TextStyle(
                        fontFamily: 'DM Sans',
                        fontSize: 15,
                        color: theme.subText,
                        fontStyle: FontStyle.italic)),
              ],
              const SizedBox(height: 12),

              Wrap(spacing: 16, runSpacing: 8, children: [
                if (author != null && author.isNotEmpty)
                  Row(mainAxisSize: MainAxisSize.min, children: [
                    Icon(Icons.person_outline_rounded,
                        size: 14, color: theme.subText),
                    const SizedBox(width: 4),
                    Text(author,
                        style: TextStyle(
                            fontFamily: 'DM Sans',
                            fontSize: 13,
                            fontWeight: FontWeight.w600,
                            color: theme.text)),
                  ]),
                if (publisher != null && publisher.isNotEmpty)
                  Row(mainAxisSize: MainAxisSize.min, children: [
                    Icon(Icons.business_outlined,
                        size: 14, color: theme.subText),
                    const SizedBox(width: 4),
                    Text(publisher,
                        style: TextStyle(
                            fontFamily: 'DM Sans',
                            fontSize: 13,
                            color: theme.subText)),
                  ]),
              ]),
              const SizedBox(height: 12),

              Wrap(spacing: 16, runSpacing: 8, children: [
                if (pageCount != null)
                  _statChip(
                      Icons.menu_book_outlined, '$pageCount pages', theme),
                _statChip(
                    Icons.language_rounded, language.toUpperCase(), theme),
                if ((c['total_reviews'] as int? ?? 0) > 0)
                  _statChip(
                      Icons.star_rounded, '${c['total_reviews']} reviews', theme,
                      iconColor: const Color(0xFFF59E0B)),
              ]),
              const SizedBox(height: 28),

              // ── PRIMARY BUTTON ──────────────────────────────────────────
              _buildOpenWithExternalButton(fileInfo, theme),
              const SizedBox(height: 28),

              _sectionDivider('ABOUT THIS CONTENT', theme),
              const SizedBox(height: 20),

              if (description != null && description.isNotEmpty)
                Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: description.split(RegExp(r'\n{2,}')).map((p) {
                    final t = p.trim();
                    if (t.isEmpty) return const SizedBox(height: 8);
                    return Padding(
                      padding: const EdgeInsets.only(bottom: 18),
                      child: Text(t,
                          style: TextStyle(
                            fontFamily: _settings.fontFamily,
                            fontSize: _settings.fontSize,
                            height: _settings.lineHeight,
                            color: theme.text,
                            letterSpacing: 0.12,
                          )),
                    );
                  }).toList(),
                )
              else
                Text('No description available.',
                    style: TextStyle(
                        fontFamily: 'DM Sans',
                        fontSize: 14,
                        color: theme.subText,
                        fontStyle: FontStyle.italic)),
            ]),
          ),
        ),

        // ── Back cover ────────────────────────────────────────────────────
        if (backpage != null && backpage.isNotEmpty)
          SliverToBoxAdapter(
            child: Padding(
              padding: const EdgeInsets.fromLTRB(22, 32, 22, 0),
              child:
                  Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                _sectionDivider('BACK COVER', theme),
                const SizedBox(height: 16),
                ClipRRect(
                  borderRadius: BorderRadius.circular(12),
                  child: CachedNetworkImage(
                      imageUrl: backpage,
                      width: double.infinity,
                      fit: BoxFit.fitWidth,
                      errorWidget: (_, __, ___) => const SizedBox.shrink()),
                ),
              ]),
            ),
          ),

        SliverToBoxAdapter(
          child: SizedBox(
              height: MediaQuery.of(context).padding.bottom + 100),
        ),
      ],
    );
  }

  // ─────────────────────────────────────────────────────────────────────────
  // "Download / Open in App" button
  // ─────────────────────────────────────────────────────────────────────────
  Widget _buildOpenWithExternalButton(
      _FileTypeInfo fileInfo, _ReaderTheme theme) {
    final isWeb = kIsWeb;

    final label = isWeb ? 'Download to Open' : 'Open in App';
    final subLabel = isWeb
        ? 'Downloads the file — open it with WPS, Word, or your default app'
        : 'Opens with ${fileInfo.suggestedApps.take(2).join(', ')} or your default reader';

    return Column(children: [
      SizedBox(
        width: double.infinity,
        height: 56,
        child: ElevatedButton(
          onPressed: _isLaunching ? null : _openWithExternalApp,
          style: ElevatedButton.styleFrom(
            backgroundColor: AppColors.primary,
            foregroundColor: Colors.white,
            elevation: 0,
            shape:
                RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
            disabledBackgroundColor: AppColors.primary.withOpacity(0.6),
          ),
          child: _isLaunching
              ? const SizedBox(
                  width: 22,
                  height: 22,
                  child: CircularProgressIndicator(
                      strokeWidth: 2.5,
                      valueColor: AlwaysStoppedAnimation(Colors.white)))
              : Row(mainAxisAlignment: MainAxisAlignment.center, children: [
                  Container(
                    padding: const EdgeInsets.all(6),
                    decoration: BoxDecoration(
                      color: Colors.white.withOpacity(0.18),
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: Icon(
                        isWeb
                            ? Icons.download_rounded
                            : Icons.open_in_browser,
                        size: 18,
                        color: Colors.white),
                  ),
                  const SizedBox(width: 12),
                  Text(label,
                      style: const TextStyle(
                          fontFamily: 'DM Sans',
                          fontSize: 16,
                          fontWeight: FontWeight.w700)),
                ]),
        ),
      ),
      const SizedBox(height: 10),

      Row(mainAxisAlignment: MainAxisAlignment.center, children: [
        Icon(
            isWeb
                ? Icons.download_for_offline_outlined
                : Icons.info_outline_rounded,
            size: 12,
            color: theme.subText.withOpacity(0.7)),
        const SizedBox(width: 5),
        Flexible(
          child: Text(subLabel,
              textAlign: TextAlign.center,
              style: TextStyle(
                  fontFamily: 'DM Sans',
                  fontSize: 11,
                  color: theme.subText.withOpacity(0.8))),
        ),
      ]),

      if (!isWeb) ...[
        const SizedBox(height: 14),
        _buildCompatibleAppsRow(fileInfo, theme),
      ],

      if (isWeb) ...[
        const SizedBox(height: 14),
        Container(
          padding: const EdgeInsets.all(14),
          decoration: BoxDecoration(
            color: theme.surface,
            borderRadius: BorderRadius.circular(12),
            border: Border.all(color: theme.divider),
          ),
          child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Icon(Icons.tips_and_updates_outlined,
                size: 16, color: theme.subText),
            const SizedBox(width: 10),
            Expanded(
              child: Text(
                'After downloading, find the file in your Downloads folder '
                'and open it with WPS Office, Microsoft Word, Adobe Acrobat, '
                'or whichever app you prefer.',
                style: TextStyle(
                    fontFamily: 'DM Sans',
                    fontSize: 12,
                    color: theme.subText,
                    height: 1.55),
              ),
            ),
          ]),
        ),
      ],
    ]);
  }

  Widget _buildCompatibleAppsRow(_FileTypeInfo fileInfo, _ReaderTheme theme) {
    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      Text('Compatible apps on your device:',
          style: TextStyle(
              fontFamily: 'DM Sans',
              fontSize: 11,
              fontWeight: FontWeight.w600,
              color: theme.subText)),
      const SizedBox(height: 8),
      Wrap(
        spacing: 8,
        runSpacing: 8,
        children: fileInfo.suggestedApps
            .map((app) => Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
                  decoration: BoxDecoration(
                    color: theme.surface,
                    borderRadius: BorderRadius.circular(20),
                    border: Border.all(color: theme.divider),
                  ),
                  child: Text(app,
                      style: TextStyle(
                          fontFamily: 'DM Sans',
                          fontSize: 11,
                          fontWeight: FontWeight.w600,
                          color: theme.subText)),
                ))
            .toList(),
      ),
    ]);
  }

  Widget _coverFallback(_FileTypeInfo fileInfo) => Container(
        color: fileInfo.color.withOpacity(0.08),
        child: Center(
            child: Column(mainAxisSize: MainAxisSize.min, children: [
          Icon(fileInfo.icon,
              size: 72, color: fileInfo.color.withOpacity(0.4)),
          const SizedBox(height: 12),
          Text(fileInfo.label,
              style: TextStyle(
                  fontFamily: 'DM Sans',
                  fontSize: 13,
                  color: fileInfo.color.withOpacity(0.5),
                  fontWeight: FontWeight.w600)),
        ])),
      );

  Widget _sectionDivider(String label, _ReaderTheme theme) =>
      Row(children: [
        Expanded(child: Divider(color: theme.divider, thickness: 1)),
        Padding(
            padding: const EdgeInsets.symmetric(horizontal: 14),
            child: Text(label,
                style: TextStyle(
                    fontFamily: 'DM Sans',
                    fontSize: 10,
                    fontWeight: FontWeight.w700,
                    letterSpacing: 1.4,
                    color: theme.subText))),
        Expanded(child: Divider(color: theme.divider, thickness: 1)),
      ]);

  // ═══════════════════════════════════════════════════════════════════════════
  // IMAGE VIEWER
  // ═══════════════════════════════════════════════════════════════════════════
  Widget _buildImageViewer() {
    final cover = _content?['cover_image_url'] as String?;
    final backpage = _content?['backpage_image_url'] as String?;
    final hasRealFile = _fileUrl != null && _fileUrl!.isNotEmpty;

    if (hasRealFile) {
      final images = <String>[];
      if (cover != null && cover.isNotEmpty) images.add(cover);
      if (_fileUrl != null &&
          _fileUrl!.isNotEmpty &&
          _fileUrl != cover) images.add(_fileUrl!);
      if (backpage != null &&
          backpage.isNotEmpty &&
          backpage != cover) images.add(backpage);

      if (images.isNotEmpty) {
        return _ImagePageViewer(
          imageUrls: images,
          onPageChanged: (page, total) {
            final p = total > 0 ? page / total : 0.0;
            setState(() => _readProgress = p);
            if (p >= 0.30 && !_reviewPrompted) {
              _reviewPrompted = true;
              Future.delayed(
                  const Duration(seconds: 2), _showReviewPrompt);
            }
            _scheduleToolbarHide();
          },
          onTap: _toggleToolbar,
        );
      }
    }

    return _buildContentDetailPage(cover, backpage);
  }

  Widget _buildContentDetailPage(String? cover, String? backpage) {
    final theme = _settings.theme;
    final c = _content!;
    final title = c['title'] as String? ?? 'Untitled';
    final subtitle = c['subtitle'] as String?;
    final author = c['author'] as String?;
    final publisher = c['publisher'] as String?;
    final description = c['description'] as String?;
    final ct = c['content_type'] as String? ?? '';
    final language = c['language'] as String? ?? 'en';
    final pageCount = c['page_count'] as int?;
    final isbn = c['isbn'] as String?;

    return CustomScrollView(
      controller: _scrollCtrl,
      physics: const BouncingScrollPhysics(),
      slivers: [
        SliverToBoxAdapter(
          child: SizedBox(
            height: MediaQuery.of(context).size.height * 0.62,
            child: Stack(fit: StackFit.expand, children: [
              if (cover != null && cover.isNotEmpty)
                CachedNetworkImage(
                    imageUrl: cover,
                    fit: BoxFit.cover,
                    errorWidget: (_, __, ___) => Container(
                        color: AppColors.primary.withOpacity(0.08),
                        child: Center(
                            child: Icon(Icons.menu_book_rounded,
                                size: 80,
                                color: AppColors.primary.withOpacity(0.3)))))
              else
                Container(
                    color: AppColors.primary.withOpacity(0.06),
                    child: Center(
                        child: Icon(Icons.menu_book_rounded,
                            size: 80,
                            color: AppColors.primary.withOpacity(0.25)))),
              Positioned(
                  bottom: 0,
                  left: 0,
                  right: 0,
                  child: Container(
                      height: 180,
                      decoration: BoxDecoration(
                          gradient: LinearGradient(
                              begin: Alignment.topCenter,
                              end: Alignment.bottomCenter,
                              colors: [Colors.transparent, theme.bg])))),
            ]),
          ),
        ),
        SliverToBoxAdapter(
          child: Padding(
            padding: const EdgeInsets.fromLTRB(22, 0, 22, 0),
            child:
                Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Container(
                padding:
                    const EdgeInsets.symmetric(horizontal: 10, vertical: 3),
                decoration: BoxDecoration(
                    color: AppColors.primary.withOpacity(0.10),
                    borderRadius: BorderRadius.circular(20)),
                child: Text(ct.toUpperCase(),
                    style: TextStyle(
                        fontFamily: 'DM Sans',
                        fontSize: 10,
                        fontWeight: FontWeight.w800,
                        letterSpacing: 1.1,
                        color: AppColors.primary)),
              ),
              const SizedBox(height: 10),
              Text(title,
                  style: TextStyle(
                      fontFamily: 'PlayfairDisplay',
                      fontSize: 28,
                      fontWeight: FontWeight.w800,
                      color: theme.text,
                      height: 1.2)),
              if (subtitle != null && subtitle.isNotEmpty) ...[
                const SizedBox(height: 6),
                Text(subtitle,
                    style: TextStyle(
                        fontFamily: 'DM Sans',
                        fontSize: 16,
                        color: theme.subText,
                        fontStyle: FontStyle.italic)),
              ],
              const SizedBox(height: 14),
              Wrap(spacing: 16, runSpacing: 8, children: [
                if (author != null && author.isNotEmpty)
                  Row(mainAxisSize: MainAxisSize.min, children: [
                    Icon(Icons.person_outline_rounded,
                        size: 14, color: theme.subText),
                    const SizedBox(width: 4),
                    Text(author,
                        style: TextStyle(
                            fontFamily: 'DM Sans',
                            fontSize: 13,
                            fontWeight: FontWeight.w600,
                            color: theme.text)),
                  ]),
                if (publisher != null && publisher.isNotEmpty)
                  Row(mainAxisSize: MainAxisSize.min, children: [
                    Icon(Icons.business_outlined,
                        size: 14, color: theme.subText),
                    const SizedBox(width: 4),
                    Text(publisher,
                        style: TextStyle(
                            fontFamily: 'DM Sans',
                            fontSize: 13,
                            color: theme.subText)),
                  ]),
              ]),
              const SizedBox(height: 14),
              Wrap(spacing: 16, runSpacing: 8, children: [
                if (pageCount != null)
                  _statChip(
                      Icons.menu_book_outlined, '$pageCount pages', theme),
                _statChip(
                    Icons.language_rounded, language.toUpperCase(), theme),
                if (isbn != null && isbn.isNotEmpty)
                  _statChip(Icons.qr_code_rounded, isbn, theme),
                if ((c['total_reviews'] as int? ?? 0) > 0)
                  _statChip(
                      Icons.star_rounded, '${c['total_reviews']} reviews', theme,
                      iconColor: const Color(0xFFF59E0B)),
              ]),
              const SizedBox(height: 24),
              _sectionDivider('ABOUT THIS CONTENT', theme),
              const SizedBox(height: 20),
              if (description != null && description.isNotEmpty)
                Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: description.split(RegExp(r'\n{2,}')).map((p) {
                    final t = p.trim();
                    if (t.isEmpty) return const SizedBox(height: 8);
                    return Padding(
                      padding: const EdgeInsets.only(bottom: 18),
                      child: Text(t,
                          style: TextStyle(
                            fontFamily: _settings.fontFamily,
                            fontSize: _settings.fontSize,
                            height: _settings.lineHeight,
                            color: theme.text,
                            letterSpacing: 0.12,
                          )),
                    );
                  }).toList(),
                )
              else
                Text('No description available.',
                    style: TextStyle(
                        fontFamily: 'DM Sans',
                        fontSize: 14,
                        color: theme.subText,
                        fontStyle: FontStyle.italic)),
            ]),
          ),
        ),
        if (backpage != null && backpage.isNotEmpty)
          SliverToBoxAdapter(
            child: Padding(
              padding: const EdgeInsets.fromLTRB(22, 32, 22, 0),
              child:
                  Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                _sectionDivider('BACK COVER', theme),
                const SizedBox(height: 16),
                ClipRRect(
                    borderRadius: BorderRadius.circular(12),
                    child: CachedNetworkImage(
                        imageUrl: backpage,
                        width: double.infinity,
                        fit: BoxFit.fitWidth,
                        errorWidget: (_, __, ___) =>
                            const SizedBox.shrink())),
              ]),
            ),
          ),
        SliverToBoxAdapter(
            child: SizedBox(
                height: MediaQuery.of(context).padding.bottom + 100)),
      ],
    );
  }

  // ═══════════════════════════════════════════════════════════════════════════
  // TEXT VIEWER
  // ═══════════════════════════════════════════════════════════════════════════
  Widget _buildTextViewer(_ReaderTheme theme) {
    return CustomScrollView(
      controller: _scrollCtrl,
      physics: const BouncingScrollPhysics(),
      slivers: [
        SliverToBoxAdapter(
            child: SizedBox(
                height: MediaQuery.of(context).padding.top + 56)),
        SliverToBoxAdapter(child: _buildCoverHeader(theme)),
        SliverToBoxAdapter(child: _buildChapterDivider(theme)),
        SliverPadding(
          padding: EdgeInsets.fromLTRB(
              22, 4, 22, MediaQuery.of(context).padding.bottom + 80),
          sliver: SliverToBoxAdapter(
            child: _bodyText != null && _bodyText!.isNotEmpty
                ? _buildParagraphs(theme)
                : _buildNoPreviewCard(theme),
          ),
        ),
      ],
    );
  }

  Widget _buildParagraphs(_ReaderTheme theme) {
    final paras = _bodyText!.split(RegExp(r'\n\n+'));
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: paras.map((p) {
        final t = p.trim();
        if (t.isEmpty) return const SizedBox(height: 8);
        return Padding(
          padding: const EdgeInsets.only(bottom: 20),
          child: Text(t,
              style: TextStyle(
                fontFamily: _settings.fontFamily,
                fontSize: _settings.fontSize,
                height: _settings.lineHeight,
                color: theme.text,
                letterSpacing: 0.12,
              )),
        );
      }).toList(),
    );
  }

  Widget _buildNoPreviewCard(_ReaderTheme theme) => Container(
      margin: const EdgeInsets.symmetric(vertical: 24),
      padding: const EdgeInsets.all(28),
      decoration: BoxDecoration(
          color: theme.surface,
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: theme.divider)),
      child: Column(children: [
        Container(
            width: 64,
            height: 64,
            decoration: BoxDecoration(
                color: AppColors.primary.withOpacity(0.08),
                shape: BoxShape.circle),
            child: Icon(Icons.info_outline_rounded,
                size: 30, color: AppColors.primary)),
        const SizedBox(height: 14),
        Text('No Preview Available',
            style: TextStyle(
                fontFamily: 'PlayfairDisplay',
                fontSize: 17,
                fontWeight: FontWeight.w800,
                color: theme.text)),
        const SizedBox(height: 8),
        Text(
            'No readable content available for this item. '
            'Please contact the publisher for access.',
            textAlign: TextAlign.center,
            style: TextStyle(
                fontFamily: 'DM Sans',
                fontSize: 13,
                color: theme.subText,
                height: 1.6)),
      ]));

  Widget _buildCoverHeader(_ReaderTheme theme) {
    final c = _content!;
    final cover = c['cover_image_url'] as String?;
    final title = c['title'] as String? ?? 'Untitled';
    final subtitle = c['subtitle'] as String?;
    final author = c['author'] as String?;
    final ct = c['content_type'] as String? ?? '';
    final pageCount = c['page_count'] as int?;
    final publisher = c['publisher'] as String?;
    final language = c['language'] as String? ?? 'en';

    return Container(
      color: theme.surface,
      child:
          Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        if (cover != null && cover.isNotEmpty)
          Stack(children: [
            CachedNetworkImage(
                imageUrl: cover,
                width: double.infinity,
                height: 260,
                fit: BoxFit.cover,
                errorWidget: (_, __, ___) =>
                    _coverPlaceholder(theme, 260)),
            Positioned(
                bottom: 0,
                left: 0,
                right: 0,
                child: Container(
                    height: 100,
                    decoration: BoxDecoration(
                        gradient: LinearGradient(
                            begin: Alignment.topCenter,
                            end: Alignment.bottomCenter,
                            colors: [
                          Colors.transparent,
                          theme.surface.withOpacity(0.95)
                        ])))),
          ])
        else
          _coverPlaceholder(theme, 160),
        Padding(
          padding: const EdgeInsets.fromLTRB(20, 16, 20, 20),
          child:
              Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Container(
              padding:
                  const EdgeInsets.symmetric(horizontal: 10, vertical: 3),
              decoration: BoxDecoration(
                  color: AppColors.primary.withOpacity(0.10),
                  borderRadius: BorderRadius.circular(20)),
              child: Text(ct.toUpperCase(),
                  style: TextStyle(
                      fontFamily: 'DM Sans',
                      fontSize: 10,
                      fontWeight: FontWeight.w800,
                      letterSpacing: 1.1,
                      color: AppColors.primary)),
            ),
            const SizedBox(height: 10),
            Text(title,
                style: TextStyle(
                    fontFamily: 'PlayfairDisplay',
                    fontSize: 26,
                    fontWeight: FontWeight.w800,
                    color: theme.text,
                    height: 1.2)),
            if (subtitle != null && subtitle.isNotEmpty) ...[
              const SizedBox(height: 6),
              Text(subtitle,
                  style: TextStyle(
                      fontFamily: 'DM Sans',
                      fontSize: 15,
                      color: theme.subText,
                      fontStyle: FontStyle.italic)),
            ],
            const SizedBox(height: 12),
            Row(children: [
              if (author != null && author.isNotEmpty) ...[
                Icon(Icons.person_outline_rounded,
                    size: 14, color: theme.subText),
                const SizedBox(width: 4),
                Text(author,
                    style: TextStyle(
                        fontFamily: 'DM Sans',
                        fontSize: 13,
                        fontWeight: FontWeight.w600,
                        color: theme.text)),
              ],
              if (publisher != null && publisher.isNotEmpty)
                Text('  ·  $publisher',
                    style: TextStyle(
                        fontFamily: 'DM Sans',
                        fontSize: 13,
                        color: theme.subText)),
            ]),
            const SizedBox(height: 14),
            Wrap(spacing: 16, runSpacing: 8, children: [
              _statChip(Icons.schedule_rounded,
                  '~$_estMinutes min read', theme),
              if (pageCount != null)
                _statChip(
                    Icons.menu_book_outlined, '$pageCount pages', theme),
              _statChip(
                  Icons.language_rounded, language.toUpperCase(), theme),
              if ((c['total_reviews'] as int? ?? 0) > 0)
                _statChip(Icons.star_rounded,
                    '${c['total_reviews']} reviews', theme,
                    iconColor: const Color(0xFFF59E0B)),
            ]),
            const SizedBox(height: 16),
            ClipRRect(
              borderRadius: BorderRadius.circular(8),
              child: LinearProgressIndicator(
                  value: _readProgress,
                  minHeight: 6,
                  backgroundColor: theme.divider,
                  valueColor: AlwaysStoppedAnimation(AppColors.primary)),
            ),
            const SizedBox(height: 6),
            Text('${(_readProgress * 100).toStringAsFixed(0)}% read',
                style: TextStyle(
                    fontFamily: 'DM Sans',
                    fontSize: 11,
                    fontWeight: FontWeight.w600,
                    color: AppColors.primary)),
          ]),
        ),
      ]),
    );
  }

  Widget _coverPlaceholder(_ReaderTheme theme, double h) => Container(
      width: double.infinity,
      height: h,
      color: AppColors.primary.withOpacity(0.06),
      child: Center(
          child: Icon(Icons.menu_book_rounded,
              size: 56, color: AppColors.primary.withOpacity(0.3))));

  Widget _statChip(IconData icon, String label, _ReaderTheme theme,
          {Color? iconColor}) =>
      Row(mainAxisSize: MainAxisSize.min, children: [
        Icon(icon, size: 13, color: iconColor ?? theme.subText),
        const SizedBox(width: 4),
        Text(label,
            style: TextStyle(
                fontFamily: 'DM Sans',
                fontSize: 12,
                color: theme.subText)),
      ]);

  Widget _buildChapterDivider(_ReaderTheme theme) => Padding(
      padding: const EdgeInsets.fromLTRB(22, 24, 22, 20),
      child: Row(children: [
        Expanded(child: Divider(color: theme.divider, thickness: 1)),
        Padding(
            padding: const EdgeInsets.symmetric(horizontal: 14),
            child: Text('BEGIN READING',
                style: TextStyle(
                    fontFamily: 'DM Sans',
                    fontSize: 10,
                    fontWeight: FontWeight.w700,
                    letterSpacing: 1.4,
                    color: theme.subText))),
        Expanded(child: Divider(color: theme.divider, thickness: 1)),
      ]));

  // ─────────────────────────────────────────────────────────────────────────
  // TOP BAR
  // ─────────────────────────────────────────────────────────────────────────
  Widget _buildTopBar(_ReaderTheme theme) {
    final isMedia = _viewerMode == _ViewerMode.image;
    final barBg = isMedia ? const Color(0xCC141420) : theme.surface;
    final titleClr = isMedia
        ? Colors.white
        : (theme.isDark
            ? const Color(0xFFE4E2D8)
            : const Color(0xFF111827));
    final iconClr = isMedia ? Colors.white70 : theme.subText;

    return Container(
      padding: EdgeInsets.only(
          top: MediaQuery.of(context).padding.top, left: 4, right: 4),
      decoration: BoxDecoration(
        color: barBg,
        border: isMedia
            ? null
            : Border(
                bottom: BorderSide(color: theme.divider, width: 0.5)),
        boxShadow: [
          BoxShadow(
              color: Colors.black.withOpacity(isMedia ? 0.35 : 0.06),
              blurRadius: 8,
              offset: const Offset(0, 2))
        ],
      ),
      child: SizedBox(
          height: 52,
          child: Row(children: [
            IconButton(
              icon: Icon(Icons.arrow_back_ios_new_rounded,
                  size: 18, color: titleClr),
              onPressed: () => Navigator.pop(context),
            ),
            Expanded(
                child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                  Text(_content?['title'] as String? ?? '',
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                          fontFamily: 'PlayfairDisplay',
                          fontSize: 14,
                          fontWeight: FontWeight.w700,
                          color: titleClr)),
                  if (_viewerMode == _ViewerMode.externalFile && _hasFile)
                    Text(
                      kIsWeb
                          ? 'Tap "Download to Open" to read'
                          : 'Tap "Open in App" to read',
                      style: TextStyle(
                          fontFamily: 'DM Sans',
                          fontSize: 10,
                          color: iconClr),
                    ),
                ])),
            IconButton(
              icon: Icon(
                  _bookmarked
                      ? Icons.bookmark_rounded
                      : Icons.bookmark_border_rounded,
                  size: 20,
                  color: _bookmarked ? AppColors.primary : iconClr),
              onPressed: _toggleBookmark,
            ),
            if (_viewerMode == _ViewerMode.text)
              IconButton(
                icon: Icon(Icons.text_fields_rounded,
                    size: 20, color: iconClr),
                onPressed: () =>
                    setState(() => _showSettings = !_showSettings),
                tooltip: 'Reader settings',
              ),
            if (_viewerMode == _ViewerMode.externalFile && _hasFile)
              IconButton(
                icon: Icon(
                    kIsWeb
                        ? Icons.download_rounded
                        : Icons.open_in_browser,
                    size: 20,
                    color: AppColors.primary),
                onPressed: _isLaunching ? null : _openWithExternalApp,
                tooltip: kIsWeb ? 'Download file' : 'Open in app',
              ),
          ])),
    );
  }

  // ─────────────────────────────────────────────────────────────────────────
  // BOTTOM BAR
  // ─────────────────────────────────────────────────────────────────────────
  Widget _buildBottomBar(_ReaderTheme theme) {
    final isMedia = _viewerMode == _ViewerMode.image;
    final barBg = isMedia ? const Color(0xCC141420) : theme.surface;
    final subClr = isMedia ? Colors.white54 : theme.subText;

    return Container(
      padding: EdgeInsets.only(
          bottom: MediaQuery.of(context).padding.bottom + 6,
          left: 20,
          right: 20,
          top: 10),
      decoration: BoxDecoration(
        color: barBg,
        border: isMedia
            ? null
            : Border(top: BorderSide(color: theme.divider, width: 0.5)),
      ),
      child: Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Text(
              _viewerMode == _ViewerMode.externalFile
                  ? (_hasFile
                      ? (_FileTypeInfo.fromUrl(_fileUrl).label)
                      : 'No file attached')
                  : '${(_progress * 100).toStringAsFixed(0)}%  ·  $_estMinutes min',
              style: TextStyle(
                  fontFamily: 'DM Sans', fontSize: 12, color: subClr),
            ),
            if (_viewerMode != _ViewerMode.externalFile)
              GestureDetector(
                onTap: () => _setImmersive(!_settings.immersive),
                child: AnimatedContainer(
                  duration: const Duration(milliseconds: 200),
                  padding: const EdgeInsets.symmetric(
                      horizontal: 12, vertical: 6),
                  decoration: BoxDecoration(
                    color: _settings.immersive
                        ? AppColors.primary
                        : AppColors.primary.withOpacity(0.10),
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Row(mainAxisSize: MainAxisSize.min, children: [
                    Icon(
                        _settings.immersive
                            ? Icons.fullscreen_exit_rounded
                            : Icons.fullscreen_rounded,
                        size: 14,
                        color: _settings.immersive
                            ? Colors.white
                            : AppColors.primary),
                    const SizedBox(width: 4),
                    Text(
                        _settings.immersive ? 'Exit Focus' : 'Focus Mode',
                        style: TextStyle(
                            fontFamily: 'DM Sans',
                            fontSize: 11,
                            fontWeight: FontWeight.w700,
                            color: _settings.immersive
                                ? Colors.white
                                : AppColors.primary)),
                  ]),
                ),
              )
            else
              const SizedBox.shrink(),
            GestureDetector(
              onTap: _showReviewPrompt,
              child: Text('Rate & Review',
                  style: TextStyle(
                      fontFamily: 'DM Sans',
                      fontSize: 12,
                      fontWeight: FontWeight.w600,
                      color: AppColors.primary,
                      decoration: TextDecoration.underline,
                      decorationColor: AppColors.primary)),
            ),
          ]),
    );
  }

  // ─────────────────────────────────────────────────────────────────────────
  // SETTINGS PANEL
  // ─────────────────────────────────────────────────────────────────────────
  Widget _buildSettingsPanel(_ReaderTheme theme) {
    return Positioned(
      top: 0,
      left: 0,
      right: 0,
      bottom: 0,
      child: GestureDetector(
        onTap: () => setState(() => _showSettings = false),
        child: Container(
          color: Colors.black45,
          alignment: Alignment.topCenter,
          child: GestureDetector(
            onTap: () {},
            child: Container(
              margin: EdgeInsets.only(
                  top: MediaQuery.of(context).padding.top + 52),
              decoration: BoxDecoration(
                color: theme.surface,
                borderRadius: const BorderRadius.only(
                    bottomLeft: Radius.circular(24),
                    bottomRight: Radius.circular(24)),
                boxShadow: [
                  BoxShadow(
                      color: Colors.black.withOpacity(0.14),
                      blurRadius: 24,
                      offset: const Offset(0, 10))
                ],
              ),
              padding: const EdgeInsets.fromLTRB(22, 20, 22, 28),
              child: Column(mainAxisSize: MainAxisSize.min, children: [
                Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Text('Reader Settings',
                          style: TextStyle(
                              fontFamily: 'PlayfairDisplay',
                              fontSize: 17,
                              fontWeight: FontWeight.w800,
                              color: theme.text)),
                      GestureDetector(
                          onTap: () =>
                              setState(() => _showSettings = false),
                          child: Icon(Icons.close_rounded,
                              color: theme.subText)),
                    ]),
                const SizedBox(height: 22),
                _SettingsRow(
                    label: 'Font Size',
                    theme: theme,
                    child: Row(mainAxisSize: MainAxisSize.min, children: [
                      _SettingsIconBtn(
                          icon: Icons.remove_rounded,
                          theme: theme,
                          onTap: () => setState(() =>
                              _settings.fontSize =
                                  (_settings.fontSize - 1).clamp(12, 30))),
                      const SizedBox(width: 10),
                      SizedBox(
                          width: 28,
                          child: Text('${_settings.fontSize.toInt()}',
                              textAlign: TextAlign.center,
                              style: TextStyle(
                                  fontFamily: 'DM Sans',
                                  fontSize: 14,
                                  fontWeight: FontWeight.w700,
                                  color: theme.text))),
                      const SizedBox(width: 10),
                      _SettingsIconBtn(
                          icon: Icons.add_rounded,
                          theme: theme,
                          onTap: () => setState(() =>
                              _settings.fontSize =
                                  (_settings.fontSize + 1).clamp(12, 30))),
                    ])),
                const SizedBox(height: 18),
                _SettingsRow(
                    label: 'Font',
                    theme: theme,
                    child: Row(mainAxisSize: MainAxisSize.min, children: [
                      _FontChip(
                          label: 'Sans',
                          fontFamily: 'DM Sans',
                          current: _settings.fontFamily,
                          theme: theme,
                          onTap: () => setState(
                              () => _settings.fontFamily = 'DM Sans')),
                      const SizedBox(width: 8),
                      _FontChip(
                          label: 'Serif',
                          fontFamily: 'PlayfairDisplay',
                          current: _settings.fontFamily,
                          theme: theme,
                          onTap: () => setState(() =>
                              _settings.fontFamily = 'PlayfairDisplay')),
                      const SizedBox(width: 8),
                      _FontChip(
                          label: 'Mono',
                          fontFamily: 'RobotoMono',
                          current: _settings.fontFamily,
                          theme: theme,
                          onTap: () => setState(
                              () => _settings.fontFamily = 'RobotoMono')),
                    ])),
                const SizedBox(height: 18),
                _SettingsRow(
                    label: 'Line Height',
                    theme: theme,
                    child: Row(mainAxisSize: MainAxisSize.min, children: [
                      _SettingsIconBtn(
                          icon: Icons.density_small_rounded,
                          theme: theme,
                          onTap: () => setState(() =>
                              _settings.lineHeight =
                                  (_settings.lineHeight - 0.1)
                                      .clamp(1.3, 2.5))),
                      const SizedBox(width: 10),
                      Text(_settings.lineHeight.toStringAsFixed(1),
                          style: TextStyle(
                              fontFamily: 'DM Sans',
                              fontSize: 14,
                              fontWeight: FontWeight.w700,
                              color: theme.text)),
                      const SizedBox(width: 10),
                      _SettingsIconBtn(
                          icon: Icons.density_large_rounded,
                          theme: theme,
                          onTap: () => setState(() =>
                              _settings.lineHeight =
                                  (_settings.lineHeight + 0.1)
                                      .clamp(1.3, 2.5))),
                    ])),
                const SizedBox(height: 20),
                _SettingsRow(
                    label: 'Theme',
                    theme: theme,
                    child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: _ReaderTheme.values
                            .map((t) => _ThemeSwatch(
                                readerTheme: t,
                                selected: _settings.theme == t,
                                onTap: () =>
                                    setState(() => _settings.theme = t)))
                            .toList())),
              ]),
            ),
          ),
        ),
      ),
    );
  }

  // ─────────────────────────────────────────────────────────────────────────
  // ACCESS GATE VIEW
  // ─────────────────────────────────────────────────────────────────────────
  Widget _accessGateView() {
    final isPurchase = _accessError == 'purchase_required';
    final isOrg = _accessError == 'org_required';
    final cover = _content?['cover_image_url'] as String?;
    final title = _content?['title'] as String?;
    final author = _content?['author'] as String?;
    final price = (_content?['price'] as num?)?.toDouble() ?? 0.0;

    final gateIcon = isPurchase
        ? Icons.lock_outline_rounded
        : isOrg
            ? Icons.corporate_fare_rounded
            : Icons.search_off_rounded;
    final gateTitle = isPurchase
        ? 'Purchase Required'
        : isOrg
            ? 'Restricted Access'
            : 'Content Not Found';
    final gateBody = isPurchase
        ? 'Unlock the full content to start reading. Your progress will be saved automatically.'
        : isOrg
            ? 'This content is restricted to organisation members. Contact your administrator.'
            : 'This content could not be found or is no longer available.';

    return Scaffold(
      backgroundColor: const Color(0xFFF8F4EE),
      body: CustomScrollView(slivers: [
        SliverAppBar(
          backgroundColor: Colors.white,
          elevation: 0,
          pinned: true,
          leading: IconButton(
            icon: const Icon(Icons.arrow_back_ios_new_rounded,
                size: 20, color: Color(0xFF1A1A2E)),
            onPressed: () => Navigator.pop(context),
          ),
          title: Text(gateTitle,
              style: const TextStyle(
                  fontFamily: 'PlayfairDisplay',
                  fontSize: 16,
                  fontWeight: FontWeight.w700,
                  color: Color(0xFF111827))),
        ),
        SliverToBoxAdapter(
            child: Padding(
          padding: const EdgeInsets.all(28),
          child: Column(children: [
            const SizedBox(height: 12),
            if (cover != null && title != null) ...[
              Stack(alignment: Alignment.center, children: [
                ClipRRect(
                    borderRadius: BorderRadius.circular(16),
                    child: ColorFiltered(
                      colorFilter: ColorFilter.mode(
                          Colors.black.withOpacity(0.45),
                          BlendMode.darken),
                      child: CachedNetworkImage(
                          imageUrl: cover,
                          width: 140,
                          height: 200,
                          fit: BoxFit.cover,
                          errorWidget: (_, __, ___) => Container(
                              width: 140,
                              height: 200,
                              decoration: BoxDecoration(
                                  color:
                                      AppColors.primary.withOpacity(0.08),
                                  borderRadius:
                                      BorderRadius.circular(16)))),
                    )),
                Container(
                    width: 52,
                    height: 52,
                    decoration: const BoxDecoration(
                        color: Colors.white, shape: BoxShape.circle),
                    child: Icon(gateIcon,
                        size: 26, color: AppColors.primary)),
              ]),
              const SizedBox(height: 16),
              Text(title,
                  textAlign: TextAlign.center,
                  style: const TextStyle(
                      fontFamily: 'PlayfairDisplay',
                      fontSize: 20,
                      fontWeight: FontWeight.w800,
                      color: Color(0xFF111827))),
              if (author != null)
                Text('by $author',
                    style: const TextStyle(
                        fontFamily: 'DM Sans',
                        fontSize: 14,
                        color: Color(0xFF6B7080))),
              if (isPurchase && price > 0) ...[
                const SizedBox(height: 6),
                Container(
                  padding: const EdgeInsets.symmetric(
                      horizontal: 14, vertical: 5),
                  decoration: BoxDecoration(
                      color: AppColors.primary,
                      borderRadius: BorderRadius.circular(20)),
                  child: Text('KSH ${price.toStringAsFixed(0)}',
                      style: const TextStyle(
                          fontFamily: 'DM Sans',
                          fontSize: 13,
                          fontWeight: FontWeight.w800,
                          color: Colors.white)),
                ),
              ],
              const SizedBox(height: 28),
            ] else ...[
              Container(
                  width: 90,
                  height: 90,
                  decoration: BoxDecoration(
                      color: AppColors.primary.withOpacity(0.07),
                      shape: BoxShape.circle),
                  child: Icon(gateIcon,
                      size: 44, color: AppColors.primary)),
              const SizedBox(height: 24),
            ],
            Text(gateTitle,
                style: const TextStyle(
                    fontFamily: 'PlayfairDisplay',
                    fontSize: 22,
                    fontWeight: FontWeight.w800,
                    color: Color(0xFF111827))),
            const SizedBox(height: 10),
            Text(gateBody,
                textAlign: TextAlign.center,
                style: const TextStyle(
                    fontFamily: 'DM Sans',
                    fontSize: 14,
                    color: Color(0xFF6B7080),
                    height: 1.6)),
            const SizedBox(height: 36),
            if (isPurchase) ...[
              SizedBox(
                  width: double.infinity,
                  height: 52,
                  child: ElevatedButton.icon(
                    onPressed: () => Navigator.pushNamed(
                        context, '/book-detail',
                        arguments: widget.contentId),
                    icon: const Icon(Icons.shopping_cart_outlined,
                        size: 18),
                    label: const Text('View & Purchase',
                        style: TextStyle(
                            fontFamily: 'DM Sans',
                            fontSize: 15,
                            fontWeight: FontWeight.w700)),
                    style: ElevatedButton.styleFrom(
                        backgroundColor: AppColors.primary,
                        foregroundColor: Colors.white,
                        elevation: 0,
                        shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(14))),
                  )),
              const SizedBox(height: 12),
              SizedBox(
                  width: double.infinity,
                  height: 52,
                  child: OutlinedButton(
                    onPressed: () =>
                        Navigator.pushNamed(context, '/browse'),
                    style: OutlinedButton.styleFrom(
                        foregroundColor: AppColors.primary,
                        side: BorderSide(
                            color: AppColors.primary.withOpacity(0.35)),
                        shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(14))),
                    child: const Text('Browse Other Content',
                        style: TextStyle(
                            fontFamily: 'DM Sans',
                            fontSize: 14,
                            fontWeight: FontWeight.w700)),
                  )),
            ] else
              SizedBox(
                  width: double.infinity,
                  height: 52,
                  child: ElevatedButton(
                    onPressed: () => Navigator.pop(context),
                    style: ElevatedButton.styleFrom(
                        backgroundColor: AppColors.primary,
                        foregroundColor: Colors.white,
                        elevation: 0,
                        shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(14))),
                    child: const Text('Go Back',
                        style: TextStyle(
                            fontFamily: 'DM Sans',
                            fontSize: 15,
                            fontWeight: FontWeight.w700)),
                  )),
          ]),
        )),
      ]),
    );
  }

  Widget _loadingView() => Scaffold(
      backgroundColor: const Color(0xFFF8F4EE),
      body: Center(
          child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
            CircularProgressIndicator(
                valueColor: AlwaysStoppedAnimation(AppColors.primary),
                strokeWidth: 2.5),
            const SizedBox(height: 20),
            const Text('Opening your book…',
                style: TextStyle(
                    fontFamily: 'DM Sans',
                    color: Color(0xFF6B7080),
                    fontSize: 14)),
          ])));
}

// ─────────────────────────────────────────────────────────────────────────────
// OPEN WITH SHEET  (mobile only)
// ─────────────────────────────────────────────────────────────────────────────

class _OpenWithSheet extends StatelessWidget {
  final _FileTypeInfo fileInfo;
  final String fileName;
  final VoidCallback onOpen;
  final VoidCallback onCancel;

  // ignore: prefer_const_constructors_in_immutables
  _OpenWithSheet({
    required this.fileInfo,
    required this.fileName,
    required this.onOpen,
    required this.onCancel,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: const BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.vertical(top: Radius.circular(28)),
      ),
      padding: EdgeInsets.fromLTRB(
          24, 8, 24, 32 + MediaQuery.of(context).padding.bottom),
      child: Column(mainAxisSize: MainAxisSize.min, children: [
        Container(
            width: 40,
            height: 4,
            margin: const EdgeInsets.only(bottom: 24),
            decoration: BoxDecoration(
                color: const Color(0xFFD1D5DB),
                borderRadius: BorderRadius.circular(2))),

        Container(
          width: 72,
          height: 72,
          decoration: BoxDecoration(
            color: fileInfo.color.withOpacity(0.10),
            shape: BoxShape.circle,
          ),
          child: Icon(fileInfo.icon, size: 34, color: fileInfo.color),
        ),
        const SizedBox(height: 16),

        Text('Open ${fileInfo.label}',
            style: const TextStyle(
                fontFamily: 'PlayfairDisplay',
                fontSize: 20,
                fontWeight: FontWeight.w800,
                color: Color(0xFF111827))),
        const SizedBox(height: 6),
        Text(fileName,
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
            textAlign: TextAlign.center,
            style: const TextStyle(
                fontFamily: 'DM Sans',
                fontSize: 13,
                color: Color(0xFF6B7080))),
        const SizedBox(height: 20),

        Container(
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            color: const Color(0xFFF9FAFB),
            borderRadius: BorderRadius.circular(14),
            border: Border.all(color: const Color(0xFFE5E7EB)),
          ),
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            const Text('Your device will open this with:',
                style: TextStyle(
                    fontFamily: 'DM Sans',
                    fontSize: 12,
                    fontWeight: FontWeight.w600,
                    color: Color(0xFF374151))),
            const SizedBox(height: 10),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: fileInfo.suggestedApps
                  .map((app) => Container(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 10, vertical: 5),
                        decoration: BoxDecoration(
                          color: Colors.white,
                          borderRadius: BorderRadius.circular(20),
                          border:
                              Border.all(color: const Color(0xFFE5E7EB)),
                          boxShadow: [
                            BoxShadow(
                                color: Colors.black.withOpacity(0.04),
                                blurRadius: 4,
                                offset: const Offset(0, 1))
                          ],
                        ),
                        child: Text(app,
                            style: const TextStyle(
                                fontFamily: 'DM Sans',
                                fontSize: 12,
                                fontWeight: FontWeight.w600,
                                color: Color(0xFF374151))),
                      ))
                  .toList(),
            ),
            const SizedBox(height: 10),
            Row(children: [
              Icon(Icons.info_outline_rounded,
                  size: 12,
                  color: const Color(0xFF6B7080).withOpacity(0.7)),
              const SizedBox(width: 6),
              const Flexible(
                  child: Text(
                'The file will open in your default app. '
                'You can change this in your device settings.',
                style: TextStyle(
                    fontFamily: 'DM Sans',
                    fontSize: 11,
                    color: Color(0xFF9CA3AF),
                    height: 1.4),
              )),
            ]),
          ]),
        ),
        const SizedBox(height: 20),

        SizedBox(
          width: double.infinity,
          height: 52,
          child: ElevatedButton(
            onPressed: onOpen,
            style: ElevatedButton.styleFrom(
              backgroundColor: AppColors.primary,
              foregroundColor: Colors.white,
              elevation: 0,
              shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(14)),
            ),
            child: Row(mainAxisAlignment: MainAxisAlignment.center, children: [
              Icon(fileInfo.icon, size: 18),
              const SizedBox(width: 10),
              const Text('Open Now',
                  style: TextStyle(
                      fontFamily: 'DM Sans',
                      fontSize: 15,
                      fontWeight: FontWeight.w700)),
            ]),
          ),
        ),
        const SizedBox(height: 10),

        SizedBox(
          width: double.infinity,
          height: 48,
          child: TextButton(
            onPressed: onCancel,
            style: TextButton.styleFrom(
              foregroundColor: const Color(0xFF6B7080),
              shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(14)),
            ),
            child: const Text('Cancel',
                style: TextStyle(
                    fontFamily: 'DM Sans',
                    fontSize: 14,
                    fontWeight: FontWeight.w600)),
          ),
        ),
      ]),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// IMAGE PAGE VIEWER
// ─────────────────────────────────────────────────────────────────────────────

class _ImagePageViewer extends StatefulWidget {
  final List<String> imageUrls;
  final void Function(int page, int total) onPageChanged;
  final VoidCallback onTap;

  // ignore: prefer_const_constructors_in_immutables
  _ImagePageViewer({
    required this.imageUrls,
    required this.onPageChanged,
    required this.onTap,
  });

  @override
  State<_ImagePageViewer> createState() => _ImagePageViewerState();
}

class _ImagePageViewerState extends State<_ImagePageViewer> {
  late final PageController _pageCtrl;
  int _current = 0;

  @override
  void initState() {
    super.initState();
    _pageCtrl = PageController();
  }

  @override
  void dispose() {
    _pageCtrl.dispose();
    super.dispose();
  }

  void _goTo(int page) {
    _pageCtrl.animateToPage(page,
        duration: const Duration(milliseconds: 280),
        curve: Curves.easeInOut);
  }

  @override
  Widget build(BuildContext context) {
    final total = widget.imageUrls.length;
    return Stack(children: [
      PageView.builder(
        controller: _pageCtrl,
        onPageChanged: (i) {
          setState(() => _current = i);
          widget.onPageChanged(i + 1, total);
        },
        itemCount: total,
        itemBuilder: (_, i) => GestureDetector(
          onTap: widget.onTap,
          child: InteractiveViewer(
            minScale: 1.0,
            maxScale: 4.0,
            child: Container(
              color: Colors.black,
              alignment: Alignment.center,
              child: CachedNetworkImage(
                imageUrl: widget.imageUrls[i],
                fit: BoxFit.contain,
                width: double.infinity,
                height: double.infinity,
                placeholder: (_, __) => const Center(
                    child: CircularProgressIndicator(
                        strokeWidth: 2,
                        valueColor:
                            AlwaysStoppedAnimation(Colors.white38))),
                errorWidget: (_, __, ___) => const Center(
                    child: Icon(Icons.broken_image_outlined,
                        size: 52, color: Colors.white24)),
              ),
            ),
          ),
        ),
      ),
      if (total > 1)
        Positioned(
          bottom: 88,
          left: 0,
          right: 0,
          child: Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: List.generate(
                total.clamp(0, 20),
                (i) => AnimatedContainer(
                      duration: const Duration(milliseconds: 200),
                      margin:
                          const EdgeInsets.symmetric(horizontal: 3),
                      width: i == _current ? 20 : 6,
                      height: 6,
                      decoration: BoxDecoration(
                        color: i == _current
                            ? AppColors.primary
                            : Colors.white.withOpacity(0.35),
                        borderRadius: BorderRadius.circular(3),
                      ),
                    )),
          ),
        ),
      Positioned(
        left: 0,
        top: 60,
        bottom: 72,
        width: 72,
        child: GestureDetector(
          onTap: () {
            if (_current > 0) _goTo(_current - 1);
          },
          child: Container(color: Colors.transparent),
        ),
      ),
      Positioned(
        right: 0,
        top: 60,
        bottom: 72,
        width: 72,
        child: GestureDetector(
          onTap: () {
            if (_current < total - 1) _goTo(_current + 1);
          },
          child: Container(color: Colors.transparent),
        ),
      ),
      Positioned(
        bottom: 72,
        left: 0,
        right: 0,
        child: Center(
          child: Container(
            padding:
                const EdgeInsets.symmetric(horizontal: 10, vertical: 3),
            decoration: BoxDecoration(
                color: Colors.black54,
                borderRadius: BorderRadius.circular(12)),
            child: Text('${_current + 1} / $total',
                style: const TextStyle(
                    fontFamily: 'DM Sans',
                    fontSize: 11,
                    color: Colors.white70)),
          ),
        ),
      ),
    ]);
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// REVIEW BOTTOM SHEET
// ─────────────────────────────────────────────────────────────────────────────

class _ReviewSheet extends StatefulWidget {
  final String contentId, title;
  final Future<void> Function(int rating, String text) onSubmit;

  // ignore: prefer_const_constructors_in_immutables
  _ReviewSheet({
    required this.contentId,
    required this.title,
    required this.onSubmit,
  });

  @override
  State<_ReviewSheet> createState() => _ReviewSheetState();
}

class _ReviewSheetState extends State<_ReviewSheet> {
  int _rating = 5;
  bool _saving = false;
  final _ctrl = TextEditingController();

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  String get _label => switch (_rating) {
        1 => 'Poor',
        2 => 'Fair',
        3 => 'Good',
        4 => 'Very Good',
        _ => 'Outstanding'
      };

  @override
  Widget build(BuildContext context) => Container(
      decoration: const BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.vertical(top: Radius.circular(24))),
      padding: EdgeInsets.fromLTRB(
          24, 8, 24, 24 + MediaQuery.of(context).viewInsets.bottom),
      child: Column(mainAxisSize: MainAxisSize.min, children: [
        Container(
            width: 40,
            height: 4,
            margin: const EdgeInsets.only(bottom: 18),
            decoration: BoxDecoration(
                color: const Color(0xFFD1D5DB),
                borderRadius: BorderRadius.circular(2))),
        const Text('Rate This Content',
            style: TextStyle(
                fontFamily: 'PlayfairDisplay',
                fontSize: 18,
                fontWeight: FontWeight.w800,
                color: Color(0xFF111827))),
        const SizedBox(height: 4),
        Text(widget.title,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: const TextStyle(
                fontFamily: 'DM Sans',
                fontSize: 13,
                color: Color(0xFF9CA3AF))),
        const SizedBox(height: 20),
        Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: List.generate(
                5,
                (i) => GestureDetector(
                      onTap: () => setState(() => _rating = i + 1),
                      child: Padding(
                          padding:
                              const EdgeInsets.symmetric(horizontal: 5),
                          child: Icon(
                              i < _rating
                                  ? Icons.star_rounded
                                  : Icons.star_outline_rounded,
                              size: 38,
                              color: i < _rating
                                  ? const Color(0xFFF59E0B)
                                  : const Color(0xFFD1D5DB))),
                    ))),
        const SizedBox(height: 6),
        Text(_label,
            style: TextStyle(
                fontFamily: 'DM Sans',
                fontSize: 12,
                fontWeight: FontWeight.w600,
                color: AppColors.primary)),
        const SizedBox(height: 16),
        TextField(
          controller: _ctrl,
          maxLines: 4,
          maxLength: 500,
          style: const TextStyle(fontFamily: 'DM Sans', fontSize: 14),
          decoration: InputDecoration(
            hintText: 'Share your thoughts…',
            hintStyle: const TextStyle(
                color: Color(0xFFD1D5DB), fontSize: 13),
            filled: true,
            fillColor: const Color(0xFFF9FAFB),
            contentPadding: const EdgeInsets.all(14),
            border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(12),
                borderSide:
                    const BorderSide(color: Color(0xFFE5E7EB))),
            enabledBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(12),
                borderSide:
                    const BorderSide(color: Color(0xFFE5E7EB))),
            focusedBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(12),
                borderSide:
                    BorderSide(color: AppColors.primary, width: 1.5)),
          ),
        ),
        const SizedBox(height: 14),
        SizedBox(
            width: double.infinity,
            height: 50,
            child: ElevatedButton(
              onPressed: _saving
                  ? null
                  : () async {
                      setState(() => _saving = true);
                      try {
                        await widget.onSubmit(
                            _rating, _ctrl.text.trim());
                      } finally {
                        if (mounted) Navigator.pop(context);
                      }
                    },
              style: ElevatedButton.styleFrom(
                  backgroundColor: AppColors.primary,
                  foregroundColor: Colors.white,
                  elevation: 0,
                  shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(12))),
              child: _saving
                  ? const SizedBox(
                      width: 20,
                      height: 20,
                      child: CircularProgressIndicator(
                          strokeWidth: 2.5,
                          valueColor:
                              AlwaysStoppedAnimation(Colors.white)))
                  : const Text('Submit Review',
                      style: TextStyle(
                          fontFamily: 'DM Sans',
                          fontSize: 15,
                          fontWeight: FontWeight.w700)),
            )),
      ]));
}

// ─────────────────────────────────────────────────────────────────────────────
// SETTINGS SUB-WIDGETS
// ─────────────────────────────────────────────────────────────────────────────

class _SettingsRow extends StatelessWidget {
  final String label;
  final Widget child;
  final _ReaderTheme theme;
  // ignore: prefer_const_constructors_in_immutables
  _SettingsRow(
      {required this.label, required this.child, required this.theme});

  @override
  Widget build(BuildContext context) => Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Text(label,
                style: TextStyle(
                    fontFamily: 'DM Sans',
                    fontSize: 13,
                    fontWeight: FontWeight.w600,
                    color: theme.subText)),
            child,
          ]);
}

class _SettingsIconBtn extends StatelessWidget {
  final IconData icon;
  final VoidCallback onTap;
  final _ReaderTheme theme;
  // ignore: prefer_const_constructors_in_immutables
  _SettingsIconBtn(
      {required this.icon, required this.onTap, required this.theme});

  @override
  Widget build(BuildContext context) => GestureDetector(
      onTap: onTap,
      child: Container(
          width: 34,
          height: 34,
          decoration: BoxDecoration(
              color: theme.isDark
                  ? const Color(0xFF2E2E40)
                  : const Color(0xFFF3F4F6),
              borderRadius: BorderRadius.circular(8)),
          child: Icon(icon,
              size: 16,
              color: theme.isDark
                  ? Colors.white
                  : const Color(0xFF374151))));
}

class _FontChip extends StatelessWidget {
  final String label, fontFamily, current;
  final _ReaderTheme theme;
  final VoidCallback onTap;
  // ignore: prefer_const_constructors_in_immutables
  _FontChip(
      {required this.label,
      required this.fontFamily,
      required this.current,
      required this.theme,
      required this.onTap});

  @override
  Widget build(BuildContext context) {
    final sel = current == fontFamily;
    return GestureDetector(
      onTap: onTap,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 150),
        padding:
            const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
        decoration: BoxDecoration(
          color: sel
              ? AppColors.primary
              : (theme.isDark
                  ? const Color(0xFF2E2E40)
                  : const Color(0xFFF3F4F6)),
          borderRadius: BorderRadius.circular(8),
          border: sel
              ? null
              : Border.all(
                  color: theme.isDark
                      ? const Color(0xFF3E3E52)
                      : const Color(0xFFE5E7EB)),
        ),
        child: Text(label,
            style: TextStyle(
                fontFamily: fontFamily,
                fontSize: 12,
                fontWeight: FontWeight.w600,
                color: sel
                    ? Colors.white
                    : (theme.isDark
                        ? Colors.white70
                        : const Color(0xFF374151)))),
      ),
    );
  }
}

class _ThemeSwatch extends StatelessWidget {
  final _ReaderTheme readerTheme;
  final bool selected;
  final VoidCallback onTap;
  // ignore: prefer_const_constructors_in_immutables
  _ThemeSwatch(
      {required this.readerTheme,
      required this.selected,
      required this.onTap});

  @override
  Widget build(BuildContext context) => GestureDetector(
      onTap: onTap,
      child: Tooltip(
        message: readerTheme.label,
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 150),
          width: 34,
          height: 34,
          margin: const EdgeInsets.only(right: 8),
          decoration: BoxDecoration(
            color: readerTheme.bg,
            shape: BoxShape.circle,
            border: Border.all(
                color: selected
                    ? AppColors.primary
                    : const Color(0xFFD1D5DB),
                width: selected ? 2.5 : 1.5),
            boxShadow: selected
                ? [
                    BoxShadow(
                        color: AppColors.primary.withOpacity(0.25),
                        blurRadius: 6)
                  ]
                : null,
          ),
          child: selected
              ? Icon(Icons.check_rounded,
                  size: 16, color: AppColors.primary)
              : null,
        ),
      ));
}