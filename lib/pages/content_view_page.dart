// lib/pages/content_view_page.dart
//
// Admin-only. Mirrors ContentViewPage.tsx.
// Shows full content metadata, cover + backpage images,
// file download link, and navigation to Edit.
// Route: /content/:id  → pass id via Navigator arguments.

import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
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
const _kRedBg    = Color(0xFFFEF2F2);
const _kPurple   = Color(0xFF7C3AED);
const _kPurpleBg = Color(0xFFF5F3FF);
const _kCard     = 12.0;

class ContentViewPage extends StatefulWidget {
  /// Pass the content id as Navigator route arguments (String).
  const ContentViewPage({Key? key}) : super(key: key);
  @override
  State<ContentViewPage> createState() => _ContentViewPageState();
}

class _ContentViewPageState extends State<ContentViewPage> {
  final _sb = Supabase.instance.client;

  bool _loading     = true;
  bool _isAdmin     = false;
  bool _authChecked = false;

  Map<String, dynamic>? _content;
  String? _contentId;

  @override
  void initState() {
    super.initState();
    // id is read in didChangeDependencies so ModalRoute args are available
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

  Future<void> _checkAdminAndLoad() async {
    await RoleService.instance.load();
    if (RoleService.instance.role != 'admin') {
      if (mounted) {
        Navigator.pushReplacementNamed(context, '/home');
        _toast('Access denied. Admin only.', err: true);
      }
      return;
    }
    setState(() => _isAdmin = true);
    await _loadContent();
  }

  Future<void> _loadContent() async {
    if (_contentId == null) {
      _toast('No content ID provided.', err: true);
      if (mounted) Navigator.pop(context);
      return;
    }
    setState(() => _loading = true);
    try {
      final data = await _sb
          .from('content')
          .select('*')
          .eq('id', _contentId!)
          .single();
      if (!mounted) return;
      setState(() => _content = data as Map<String, dynamic>);
    } catch (e) {
      _toast('Failed to load content: $e', err: true);
      if (mounted) Navigator.pop(context);
    } finally {
      if (mounted) setState(() => _loading = false);
    }
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

  Future<void> _openUrl(String? url) async {
    if (url == null || url.isEmpty) return;
    final uri = Uri.parse(url);
    if (await canLaunchUrl(uri)) {
      await launchUrl(uri, mode: LaunchMode.externalApplication);
    } else {
      _toast('Could not open link.', err: true);
    }
  }

  // ─────────────────────────────────────────────────────────────────────────
  // BUILD
  // ─────────────────────────────────────────────────────────────────────────
  @override
  Widget build(BuildContext context) {
    if (!_isAdmin && _loading) return _splash();
    if (!_isAdmin) return const SizedBox.shrink();

    final w = MediaQuery.of(context).size.width;

    return Scaffold(
      backgroundColor: _kBg,
      appBar: _appBar(),
      body: _loading
          ? const Center(
              child: CircularProgressIndicator(
                  valueColor: AlwaysStoppedAnimation(_kPrimary)))
          : _content == null
              ? const SizedBox.shrink()
              : RefreshIndicator(
                  color: _kPrimary,
                  onRefresh: _loadContent,
                  child: SingleChildScrollView(
                    physics: const AlwaysScrollableScrollPhysics(),
                    padding: EdgeInsets.fromLTRB(_hp(w), 20, _hp(w), 60),
                    child: _body(w),
                  ),
                ),
    );
  }

  Widget _body(double w) {
    final c = _content!;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // ── Header ────────────────────────────────────────────────────────
        _header(c, w),
        const SizedBox(height: 20),

        // ── Cover image ───────────────────────────────────────────────────
        if ((c['cover_image_url'] as String? ?? '').isNotEmpty) ...[
          _sectionTitle('Cover Image'),
          const SizedBox(height: 10),
          ClipRRect(
            borderRadius: BorderRadius.circular(_kCard),
            child: SizedBox(
              width: double.infinity,
              child: CachedNetworkImage(
                imageUrl: c['cover_image_url'] as String,
                fit: BoxFit.contain,
                placeholder: (_, __) => Container(
                    height: 220, color: const Color(0xFFE5E7EB)),
                errorWidget: (_, __, ___) =>
                    Container(height: 220, color: const Color(0xFFE5E7EB)),
              ),
            ),
          ),
          const SizedBox(height: 20),
        ],

        // ── Backpage image (only if different from cover) ─────────────────
        if ((c['backpage_image_url'] as String? ?? '').isNotEmpty &&
            c['backpage_image_url'] != c['cover_image_url']) ...[
          _sectionTitle('Back Cover'),
          const SizedBox(height: 10),
          Container(
            width: double.infinity,
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: const Color(0xFFF9FAFB),
              borderRadius: BorderRadius.circular(_kCard),
              border: Border.all(color: _kBorder),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text(
                    'Back cover preview as shown in published content.',
                    style: TextStyle(
                        fontFamily: 'DM Sans',
                        fontSize: 12, color: _kMuted)),
                const SizedBox(height: 12),
                ClipRRect(
                  borderRadius: BorderRadius.circular(8),
                  child: CachedNetworkImage(
                    imageUrl: c['backpage_image_url'] as String,
                    width: double.infinity,
                    fit: BoxFit.contain,
                    placeholder: (_, __) =>
                        Container(height: 200, color: const Color(0xFFE5E7EB)),
                    errorWidget: (_, __, ___) =>
                        Container(height: 200, color: const Color(0xFFE5E7EB)),
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 20),
        ],

        // ── Metadata grid ─────────────────────────────────────────────────
        _sectionTitle('Details'),
        const SizedBox(height: 10),
        _metaGrid(c, w),
        const SizedBox(height: 20),

        // ── Description ───────────────────────────────────────────────────
        if ((c['description'] as String? ?? '').isNotEmpty) ...[
          _sectionTitle('Description'),
          const SizedBox(height: 10),
          _wcard(
            child: Text(c['description'] as String,
                style: const TextStyle(
                    fontFamily: 'DM Sans',
                    fontSize: 14, color: _kMuted,
                    height: 1.65)),
          ),
          const SizedBox(height: 20),
        ],

        // ── File link ─────────────────────────────────────────────────────
        if ((c['file_url'] as String? ?? '').isNotEmpty) ...[
          _sectionTitle('Content File'),
          const SizedBox(height: 10),
          _wcard(
            child: Row(children: [
              Container(
                width: 42, height: 42,
                decoration: BoxDecoration(
                    color: _kBlueBg,
                    borderRadius: BorderRadius.circular(10)),
                child: const Icon(Icons.insert_drive_file_outlined,
                    color: _kBlue, size: 22),
              ),
              const SizedBox(width: 12),
              const Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text('Content File',
                        style: TextStyle(
                            fontFamily: 'DM Sans',
                            fontWeight: FontWeight.w600,
                            fontSize: 14, color: _kCharcoal)),
                    Text('Tap to open in browser',
                        style: TextStyle(
                            fontFamily: 'DM Sans',
                            fontSize: 12, color: _kMutedLt)),
                  ],
                ),
              ),
              TextButton.icon(
                onPressed: () => _openUrl(c['file_url'] as String?),
                icon: const Icon(Icons.open_in_new_rounded, size: 15),
                label: const Text('Open',
                    style: TextStyle(fontFamily: 'DM Sans')),
                style: TextButton.styleFrom(
                    foregroundColor: _kBlue),
              ),
            ]),
          ),
        ],
      ],
    );
  }

  // ── header ────────────────────────────────────────────────────────────────
  Widget _header(Map<String, dynamic> c, double w) {
    final status = c['status'] as String? ?? 'draft';
    final type   = c['content_type'] as String? ?? 'book';
    final sc = _statusColor(status);
    final tc = _typeColor(type);

    return _wcard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(c['title'] as String? ?? 'Untitled',
                        style: const TextStyle(
                          fontFamily: 'PlayfairDisplay',
                          fontSize: 22, fontWeight: FontWeight.w800,
                          color: _kCharcoal, height: 1.3,
                        )),
                    const SizedBox(height: 6),
                    Wrap(spacing: 8, runSpacing: 4, children: [
                      if ((c['author'] as String? ?? '').isNotEmpty)
                        Text('by ${c['author']}',
                            style: const TextStyle(
                                fontFamily: 'DM Sans',
                                fontSize: 13, color: _kMuted)),
                      const Text('·',
                          style: TextStyle(color: _kMutedLt)),
                      _Pill(tc.$1, tc.$2, type),
                      _Pill(sc.$1, sc.$2, status.replaceAll('_', ' ')),
                    ]),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 16),
          const Divider(height: 1, color: _kBorder),
          const SizedBox(height: 14),
          // action buttons
          Wrap(spacing: 10, runSpacing: 10, children: [
            _Btn(
              label: 'Edit',
              icon: Icons.edit_outlined,
              color: _kCharcoal,
              onTap: () => Navigator.pushNamed(
                  context, '/content/update/$_contentId'),
            ),
            _Btn(
              label: 'Back',
              icon: Icons.arrow_back_ios_new_rounded,
              color: _kMuted,
              onTap: () => Navigator.pop(context),
            ),
            if ((c['file_url'] as String? ?? '').isNotEmpty)
              _Btn(
                label: 'Download File',
                icon: Icons.download_rounded,
                color: _kBlue,
                primary: true,
                onTap: () => _openUrl(c['file_url'] as String?),
              ),
          ]),
        ],
      ),
    );
  }

  // ── metadata grid ─────────────────────────────────────────────────────────
  Widget _metaGrid(Map<String, dynamic> c, double w) {
    final price = double.tryParse(c['price']?.toString() ?? '0') ?? 0;
    final rows = [
      ('Publisher',    c['publisher']                         ?? 'N/A'),
      ('ISBN',         c['isbn']                              ?? 'N/A'),
      ('Language',     c['language']                          ?? 'N/A'),
      ('Content Type', c['content_type']                      ?? 'N/A'),
      ('Category',     c['category_id']                       ?? 'N/A'),
      ('Page Count',   c['page_count']?.toString()            ?? 'N/A'),
      ('Version',      c['version']                           ?? '1.0'),
      ('Visibility',   c['visibility']                        ?? 'private'),
      ('Status',       (c['status'] as String? ?? 'draft')
                           .replaceAll('_', ' ')),
      ('Price',        price == 0
                           ? 'Free'
                           : 'KES ${price.toStringAsFixed(0)}'),
      ('Uploaded',     _dt(c['created_at'])),
      ('Last Updated', _dt(c['updated_at'])),
      ('Downloads',    c['total_downloads']?.toString()       ?? '0'),
      ('Views',        c['view_count']?.toString()            ?? '0'),
      ('Reviews',      c['total_reviews']?.toString()         ?? '0'),
    ];

    return _wcard(
      padding: EdgeInsets.zero,
      child: GridView.builder(
        shrinkWrap: true,
        physics: const NeverScrollableScrollPhysics(),
        gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
          crossAxisCount: w >= 500 ? 2 : 1,
          childAspectRatio: w >= 500 ? 4.5 : 5.0,
          crossAxisSpacing: 0,
          mainAxisSpacing: 0,
        ),
        itemCount: rows.length,
        itemBuilder: (_, i) {
          final r = rows[i];
          return Container(
            padding: const EdgeInsets.symmetric(
                horizontal: 16, vertical: 10),
            decoration: BoxDecoration(
              border: Border(
                bottom: BorderSide(
                    color: _kBorder.withOpacity(
                        i == rows.length - 1 || i == rows.length - 2
                            ? 0
                            : 1)),
                right: BorderSide(
                    color: _kBorder.withOpacity(
                        w >= 500 && i.isEven ? 1 : 0)),
              ),
            ),
            child: Row(children: [
              SizedBox(
                width: 100,
                child: Text(r.$1,
                    style: const TextStyle(
                        fontFamily: 'DM Sans',
                        fontSize: 12, fontWeight: FontWeight.w600,
                        color: _kMuted)),
              ),
              Expanded(
                child: Text(r.$2,
                    style: const TextStyle(
                        fontFamily: 'DM Sans',
                        fontSize: 13, color: _kCharcoal,
                        fontWeight: FontWeight.w500),
                    overflow: TextOverflow.ellipsis),
              ),
            ]),
          );
        },
      ),
    );
  }

  // ── section title ─────────────────────────────────────────────────────────
  Widget _sectionTitle(String t) => Text(t,
      style: const TextStyle(
          fontFamily: 'PlayfairDisplay',
          fontSize: 16, fontWeight: FontWeight.w700,
          color: _kCharcoal));

  Widget _wcard({required Widget child, EdgeInsetsGeometry? padding}) =>
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
        padding: padding ?? const EdgeInsets.all(16),
        child: child,
      );

  AppBar _appBar() {
    final title = _content?['title'] as String? ?? 'Content Details';
    return AppBar(
      backgroundColor: _kCharcoal,
      surfaceTintColor: Colors.transparent,
      elevation: 0,
      leading: IconButton(
        icon: const Icon(Icons.arrow_back_ios_new_rounded,
            size: 18, color: Colors.white70),
        onPressed: () => Navigator.pop(context),
      ),
      title: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(title,
              style: const TextStyle(
                  fontFamily: 'PlayfairDisplay',
                  fontSize: 15, fontWeight: FontWeight.w700,
                  color: _kWhite),
              overflow: TextOverflow.ellipsis),
          const Text('Admin — content detail',
              style: TextStyle(
                  fontFamily: 'DM Sans',
                  fontSize: 11, color: Colors.white54)),
        ],
      ),
      actions: [
        if (_contentId != null)
          IconButton(
            icon: const Icon(Icons.edit_outlined,
                size: 20, color: Colors.white70),
            onPressed: () => Navigator.pushNamed(
                context, '/content/update/$_contentId'),
            tooltip: 'Edit',
          ),
      ],
    );
  }

  Widget _splash() => Scaffold(
        backgroundColor: _kBg,
        body: const Center(
          child: CircularProgressIndicator(
              valueColor: AlwaysStoppedAnimation(_kPrimary)),
        ),
      );

  // ── helpers ───────────────────────────────────────────────────────────────
  String _dt(dynamic raw) {
    if (raw == null) return 'Unknown';
    try {
      return DateTime.parse(raw as String)
          .toLocal()
          .toString()
          .substring(0, 16);
    } catch (_) { return 'Unknown'; }
  }

  (Color, Color) _statusColor(String s) => switch (s) {
        'published'      => (_kGreen,   _kGreenBg),
        'pending_review' => (_kAmber,   _kAmberBg),
        'rejected'       => (_kRed,     _kRedBg),
        'archived'       => (_kMutedLt, const Color(0xFFF3F4F6)),
        _                => (_kMuted,   const Color(0xFFF3F4F6)),
      };

  (Color, Color) _typeColor(String t) => switch (t) {
        'book'         => (_kBlue,     _kBlueBg),
        'ebook'        => (_kPurple,   _kPurpleBg),
        'paper'        => (_kGreen,    _kGreenBg),
        'report'       => (_kAmber,    _kAmberBg),
        'manuscript'   => (_kPrimary,  const Color(0xFFFEE2E2)),
        'thesis'       => (_kPurple,   _kPurpleBg),
        'dissertation' => (_kPrimary,  const Color(0xFFFEE2E2)),
        _              => (_kMuted,    const Color(0xFFF3F4F6)),
      };

  static double _hp(double w) {
    if (w >= 900) return 32;
    if (w >= 600) return 20;
    return 16;
  }
}

// ── Shared widgets ──────────────────────────────────────────────────────────
class _Pill extends StatelessWidget {
  final Color fg, bg; final String label;
  // ignore: use_super_parameters
  const _Pill(this.fg, this.bg, this.label, {Key? key}) : super(key: key);
  @override
  Widget build(BuildContext context) => Container(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
        decoration: BoxDecoration(
          color: bg,
          borderRadius: BorderRadius.circular(20),
          border: Border.all(color: fg.withOpacity(0.25)),
        ),
        child: Text(label,
            style: TextStyle(
                fontFamily: 'DM Sans',
                fontSize: 11, fontWeight: FontWeight.w700, color: fg)),
      );
}

class _Btn extends StatelessWidget {
  final String label; final IconData icon;
  final Color color; final bool primary; final VoidCallback onTap;
  // ignore: use_super_parameters
  const _Btn({
    required this.label, required this.icon,
    required this.color, required this.onTap,
    this.primary = false, Key? key,
  }) : super(key: key);
  @override
  Widget build(BuildContext context) => GestureDetector(
        onTap: onTap,
        child: Container(
          padding: const EdgeInsets.symmetric(
              horizontal: 14, vertical: 9),
          decoration: BoxDecoration(
            color: primary ? color : color.withOpacity(0.07),
            borderRadius: BorderRadius.circular(8),
            border: Border.all(color: color.withOpacity(0.3)),
          ),
          child: Row(mainAxisSize: MainAxisSize.min, children: [
            Icon(icon, size: 14,
                color: primary ? Colors.white : color),
            const SizedBox(width: 6),
            Text(label,
                style: TextStyle(
                    fontFamily: 'DM Sans',
                    fontSize: 13, fontWeight: FontWeight.w700,
                    color: primary ? Colors.white : color)),
          ]),
        ),
      );
}