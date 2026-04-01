// lib/pages/content_upload_page.dart
//
// Admin-only. Mirrors ContentUploadPage.tsx:
// title, content type, author, price, ISBN, language, visibility, status,
// description, cover image, backpage image (required only for ebooks).
// Calls the Supabase Edge Function `content-upload` via multipart FormData.

import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:image_picker/image_picker.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:http/http.dart' as http;
import 'package:http_parser/http_parser.dart';
import 'dart:convert';

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
const _kRed      = Color(0xFFDC2626);
const _kAmber    = Color(0xFFD97706);
const _kAmberBg  = Color(0xFFFFFBEB);
const _kCard     = 12.0;

const _kMaxFileSize = 10 * 1024 * 1024; // 10 MB

const _kContentTypes = [
  'book', 'ebook', 'document', 'paper',
  'report', 'manual', 'guide',
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
];

const _kLanguages = [
  ('en', 'English'),
  ('sw', 'Swahili'),
  ('fr', 'French'),
  ('ar', 'Arabic'),
  ('es', 'Spanish'),
  ('de', 'German'),
  ('zh', 'Chinese'),
];

class ContentUploadPage extends StatefulWidget {
  const ContentUploadPage({Key? key}) : super(key: key);
  @override
  State<ContentUploadPage> createState() => _ContentUploadPageState();
}

class _ContentUploadPageState extends State<ContentUploadPage> {
  final _sb  = Supabase.instance.client;
  final _picker = ImagePicker();

  bool _checkingAuth = true;
  bool _isAdmin      = false;
  bool _uploading    = false;

  // ── form fields ──────────────────────────────────────────────────────────
  final _titleCtrl       = TextEditingController();
  final _authorCtrl      = TextEditingController();
  final _priceCtrl       = TextEditingController();
  final _isbnCtrl        = TextEditingController();
  final _descriptionCtrl = TextEditingController();

  String  _contentType = '';
  String  _visibility  = 'private';
  String  _status      = 'draft';
  String  _language    = 'en';

  File?   _coverFile;
  File?   _backpageFile;
  String? _coverName;
  String? _backpageName;

  bool get _isEbook => _contentType == 'ebook';

  // ── lifecycle ──────────────────────────────────────────────────────────
  @override
  void initState() {
    super.initState();
    _checkAdmin();
  }

  @override
  void dispose() {
    _titleCtrl.dispose();
    _authorCtrl.dispose();
    _priceCtrl.dispose();
    _isbnCtrl.dispose();
    _descriptionCtrl.dispose();
    super.dispose();
  }

  Future<void> _checkAdmin() async {
    await RoleService.instance.load();
    if (RoleService.instance.role != 'admin') {
      if (mounted) {
        Navigator.pushReplacementNamed(context, '/home');
        _toast('Access denied. Admin only.', err: true);
      }
      return;
    }
    if (mounted) setState(() { _isAdmin = true; _checkingAuth = false; });
  }

  // ── file pickers ─────────────────────────────────────────────────────────
  Future<void> _pickImage(bool isCover) async {
    final xf = await _picker.pickImage(
        source: ImageSource.gallery, imageQuality: 90);
    if (xf == null) return;
    final f = File(xf.path);
    final size = await f.length();
    if (size > _kMaxFileSize) {
      _toast('Image must be under 10 MB', err: true);
      return;
    }
    setState(() {
      if (isCover) {
        _coverFile = f;
        _coverName = xf.name;
      } else {
        _backpageFile = f;
        _backpageName = xf.name;
      }
    });
  }

  void _removeFile(bool isCover) {
    setState(() {
      if (isCover) { _coverFile = null; _coverName = null; }
      else         { _backpageFile = null; _backpageName = null; }
    });
  }

  // ── validation ────────────────────────────────────────────────────────────
  bool _validate() {
    if (_titleCtrl.text.trim().isEmpty) {
      _toast('Title is required', err: true); return false;
    }
    if (_contentType.isEmpty) {
      _toast('Content Type is required', err: true); return false;
    }
    if (_isEbook) {
      if (_coverFile == null) {
        _toast('Cover image is required for ebooks', err: true); return false;
      }
      if (_backpageFile == null) {
        _toast('Backpage image is required for ebooks', err: true); return false;
      }
    }
    return true;
  }

  // ── submit ────────────────────────────────────────────────────────────────
  Future<void> _submit() async {
    if (!_validate()) return;
    setState(() => _uploading = true);

    try {
      final session = _sb.auth.currentSession;
      if (session == null) {
        _toast('Session expired. Please log in again.', err: true);
        Navigator.pushReplacementNamed(context, '/login');
        return;
      }

      const supabaseUrl = 'https://nnljrawwhibazudjudht.supabase.co';
      final req = http.MultipartRequest(
        'POST',
        Uri.parse('$supabaseUrl/functions/v1/content-upload'),
      );

      req.headers['Authorization'] = 'Bearer ${session.accessToken}';

      req.fields['title']        = _titleCtrl.text.trim();
      req.fields['author']       = _authorCtrl.text.trim();
      req.fields['description']  = _descriptionCtrl.text.trim();
      req.fields['content_type'] = _contentType;
      req.fields['price']        = _priceCtrl.text.isNotEmpty
          ? _priceCtrl.text
          : '0';
      req.fields['isbn']         = _isbnCtrl.text.trim();
      req.fields['language']     = _language;
      req.fields['visibility']   = _visibility;
      req.fields['status']       = _status;

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
            'Upload failed. Please try again.', err: true);
        return;
      }

      _toast('Content uploaded successfully!');
      _resetForm();
    } catch (e) {
      _toast('Upload failed: $e', err: true);
    } finally {
      if (mounted) setState(() => _uploading = false);
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

  void _resetForm() {
    _titleCtrl.clear();
    _authorCtrl.clear();
    _priceCtrl.clear();
    _isbnCtrl.clear();
    _descriptionCtrl.clear();
    setState(() {
      _contentType  = '';
      _visibility   = 'private';
      _status       = 'draft';
      _language     = 'en';
      _coverFile    = null;
      _backpageFile = null;
      _coverName    = null;
      _backpageName = null;
    });
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
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
      duration: const Duration(seconds: 3),
    ));
  }

  // ─────────────────────────────────────────────────────────────────────────
  // BUILD
  // ─────────────────────────────────────────────────────────────────────────
  @override
  Widget build(BuildContext context) {
    if (_checkingAuth) return _splash('Verifying access…');
    if (!_isAdmin)     return const SizedBox.shrink();

    final w = MediaQuery.of(context).size.width;
    final pad = _hp(w);

    return Scaffold(
      backgroundColor: _kBg,
      appBar: _appBar(),
      body: SingleChildScrollView(
        padding: EdgeInsets.fromLTRB(pad, 24, pad, 120),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // page header
            const Text('Upload New Content',
                style: TextStyle(
                  fontFamily: 'PlayfairDisplay',
                  fontSize: 26,
                  fontWeight: FontWeight.w800,
                  color: _kCharcoal,
                )),
            const SizedBox(height: 4),
            const Text('Fill in the details below to add content to the library.',
                style: TextStyle(
                    fontFamily: 'DM Sans',
                    fontSize: 13,
                    color: _kMuted)),
            const SizedBox(height: 28),

            // ── Section: Core Details ────────────────────────────────
            _sectionCard(
              title: 'Core Details',
              icon: Icons.info_outline_rounded,
              children: [
                _row2(w, [
                  _field(_titleCtrl, 'Title', required: true,
                      hint: 'Enter content title'),
                  _dropdown(
                    label: 'Content Type',
                    required: true,
                    value: _contentType.isEmpty ? null : _contentType,
                    hint: 'Select type',
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
                        setState(() => _contentType = v ?? ''),
                  ),
                ]),
                if (_isEbook)
                  Container(
                    margin: const EdgeInsets.only(top: 8),
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(
                      color: _kAmberBg,
                      borderRadius: BorderRadius.circular(8),
                      border: Border.all(
                          color: const Color(0xFFFDE68A)),
                    ),
                    child: const Row(children: [
                      Icon(Icons.info_outline_rounded,
                          size: 16, color: _kAmber),
                      SizedBox(width: 8),
                      Expanded(
                        child: Text(
                          'Ebooks require both a cover image and a backpage image.',
                          style: TextStyle(
                              fontFamily: 'DM Sans',
                              fontSize: 12,
                              color: Color(0xFF92400E)),
                        ),
                      ),
                    ]),
                  ),
                const SizedBox(height: 4),
                _row2(w, [
                  _field(_authorCtrl, 'Author',
                      hint: 'Author name'),
                  _field(_priceCtrl, 'Price (KES)',
                      hint: '0.00',
                      keyboard: TextInputType.numberWithOptions(
                          decimal: true),
                      inputFormatters: [
                        FilteringTextInputFormatter.allow(
                            RegExp(r'^\d*\.?\d{0,2}')),
                      ]),
                ]),
                _row2(w, [
                  _field(_isbnCtrl, 'ISBN (optional)',
                      hint: 'e.g. 978-3-16-148410-0'),
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
                ]),
              ],
            ),
            const SizedBox(height: 16),

            // ── Section: Publishing ──────────────────────────────────
            _sectionCard(
              title: 'Publishing',
              icon: Icons.public_rounded,
              children: [
                _row2(w, [
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
              ],
            ),
            const SizedBox(height: 16),

            // ── Section: Description ─────────────────────────────────
            _sectionCard(
              title: 'Description',
              icon: Icons.notes_rounded,
              children: [
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
                      'Describe the content…'),
                ),
              ],
            ),
            const SizedBox(height: 16),

            // ── Section: Images ──────────────────────────────────────
            _sectionCard(
              title: 'Images',
              icon: Icons.image_outlined,
              children: [
                LayoutBuilder(builder: (_, c) {
                  if (c.maxWidth >= 500) {
                    return Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Expanded(
                            child: _imagePicker(
                                label: 'Cover Image',
                                required: _isEbook,
                                file: _coverFile,
                                name: _coverName,
                                onPick: () => _pickImage(true),
                                onRemove: () => _removeFile(true))),
                        const SizedBox(width: 16),
                        Expanded(
                            child: _imagePicker(
                                label: 'Backpage Image',
                                required: _isEbook,
                                file: _backpageFile,
                                name: _backpageName,
                                onPick: () => _pickImage(false),
                                onRemove: () => _removeFile(false))),
                      ],
                    );
                  }
                  return Column(children: [
                    _imagePicker(
                        label: 'Cover Image',
                        required: _isEbook,
                        file: _coverFile,
                        name: _coverName,
                        onPick: () => _pickImage(true),
                        onRemove: () => _removeFile(true)),
                    const SizedBox(height: 14),
                    _imagePicker(
                        label: 'Backpage Image',
                        required: _isEbook,
                        file: _backpageFile,
                        name: _backpageName,
                        onPick: () => _pickImage(false),
                        onRemove: () => _removeFile(false)),
                  ]);
                }),
              ],
            ),
            const SizedBox(height: 28),

            // ── Submit ───────────────────────────────────────────────
            SizedBox(
              width: double.infinity, height: 52,
              child: ElevatedButton(
                onPressed: _uploading ? null : _submit,
                style: ElevatedButton.styleFrom(
                  backgroundColor: _kPrimary,
                  foregroundColor: _kWhite,
                  elevation: 0,
                  shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(12)),
                  disabledBackgroundColor:
                      _kPrimary.withOpacity(0.5),
                ),
                child: _uploading
                    ? const Row(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          SizedBox(
                            width: 18, height: 18,
                            child: CircularProgressIndicator(
                                strokeWidth: 2.5,
                                color: _kWhite),
                          ),
                          SizedBox(width: 12),
                          Text('Uploading…',
                              style: TextStyle(
                                  fontFamily: 'DM Sans',
                                  fontSize: 16,
                                  fontWeight: FontWeight.w700)),
                        ],
                      )
                    : const Row(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          Icon(Icons.upload_rounded, size: 20),
                          SizedBox(width: 8),
                          Text('Upload Content',
                              style: TextStyle(
                                  fontFamily: 'DM Sans',
                                  fontSize: 16,
                                  fontWeight: FontWeight.w700)),
                        ],
                      ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  // ── section card ──────────────────────────────────────────────────────────
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
            const SizedBox(height: 16),
            const Divider(height: 1, color: _kBorder),
            const SizedBox(height: 16),
            ...children,
          ],
        ),
      );

  // ── image picker tile ─────────────────────────────────────────────────────
  Widget _imagePicker({
    required String label,
    required bool required,
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
            if (required)
              const Text('*',
                  style: TextStyle(
                      color: _kRed,
                      fontWeight: FontWeight.bold))
            else
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
              height: file != null ? null : 100,
              decoration: BoxDecoration(
                color: file != null ? _kWhite : const Color(0xFFF9FAFB),
                borderRadius: BorderRadius.circular(10),
                border: Border.all(
                  color: file != null
                      ? _kGreen.withOpacity(0.4)
                      : const Color(0xFFD1D5DB),
                  style: file != null
                      ? BorderStyle.solid
                      : BorderStyle.solid,
                ),
              ),
              child: file != null
                  ? Padding(
                      padding: const EdgeInsets.all(12),
                      child: Row(children: [
                        ClipRRect(
                          borderRadius: BorderRadius.circular(6),
                          child: Image.file(file,
                              width: 52, height: 70,
                              fit: BoxFit.cover),
                        ),
                        const SizedBox(width: 10),
                        Expanded(
                          child: Column(
                            crossAxisAlignment:
                                CrossAxisAlignment.start,
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
                              Row(children: [
                                const Icon(Icons.check_circle_outline,
                                    size: 13, color: _kGreen),
                                const SizedBox(width: 4),
                                const Text('Selected',
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
                              size: 18, color: _kMuted),
                          onPressed: onRemove,
                          padding: EdgeInsets.zero,
                          constraints: const BoxConstraints(
                              minWidth: 28, minHeight: 28),
                        ),
                      ]),
                    )
                  : Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Icon(Icons.add_photo_alternate_outlined,
                            size: 28, color: _kMutedLt),
                        const SizedBox(height: 6),
                        const Text('Tap to select image',
                            style: TextStyle(
                                fontFamily: 'DM Sans',
                                fontSize: 12,
                                color: _kMutedLt)),
                        const Text('JPG, PNG, WebP · max 10 MB',
                            style: TextStyle(
                                fontFamily: 'DM Sans',
                                fontSize: 10,
                                color: _kMutedLt)),
                      ],
                    ),
            ),
          ),
          if (file == null && !required) ...[
            const SizedBox(height: 6),
            GestureDetector(
              onTap: onPick,
              child: const Text('Browse gallery',
                  style: TextStyle(
                      fontFamily: 'DM Sans',
                      fontSize: 12,
                      color: _kPrimary,
                      fontWeight: FontWeight.w600,
                      decoration: TextDecoration.underline)),
            ),
          ],
        ],
      );

  // ── helpers ───────────────────────────────────────────────────────────────
  Widget _row2(double w, List<Widget> kids) {
    if (w >= 500) {
      return Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: kids
            .expand((c) => [Expanded(child: c), const SizedBox(width: 14)])
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
            style: const TextStyle(
                fontFamily: 'DM Sans',
                fontSize: 14, color: _kCharcoal),
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
          DropdownButtonFormField<String>(
            value: value,
            items: items,
            onChanged: onChanged,
            style: const TextStyle(
                fontFamily: 'DM Sans',
                fontSize: 14, color: _kCharcoal),
            decoration: _inputDec(hint),
            isExpanded: true,
            dropdownColor: _kWhite,
            icon: const Icon(Icons.keyboard_arrow_down_rounded,
                color: _kMuted, size: 20),
          ),
        ],
      );

  InputDecoration _inputDec(String? hint) => InputDecoration(
        hintText: hint,
        hintStyle: const TextStyle(
            fontFamily: 'DM Sans', fontSize: 14, color: _kMutedLt),
        filled: true,
        fillColor: _kWhite,
        contentPadding: const EdgeInsets.symmetric(
            horizontal: 14, vertical: 12),
        border: OutlineInputBorder(
            borderRadius: BorderRadius.circular(8),
            borderSide: const BorderSide(color: _kBorder)),
        enabledBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(8),
            borderSide: const BorderSide(color: _kBorder)),
        focusedBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(8),
            borderSide: const BorderSide(
                color: _kPrimary, width: 1.5)),
      );

  Widget _lbl(String t) => Text(t,
      style: const TextStyle(
          fontFamily: 'DM Sans',
          fontSize: 13, fontWeight: FontWeight.w600,
          color: _kCharcoal));

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
            Text('Upload Content',
                style: TextStyle(
                    fontFamily: 'PlayfairDisplay',
                    fontSize: 17,
                    fontWeight: FontWeight.w700,
                    color: _kWhite)),
            Text('Admin — add to library',
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

  static double _hp(double w) {
    if (w >= 900) return 32;
    if (w >= 600) return 20;
    return 16;
  }

  String _cap(String s) =>
      s.isEmpty ? s : s[0].toUpperCase() + s.substring(1);
}