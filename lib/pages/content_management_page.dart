// lib/pages/content_management_page.dart
//
// Admin-only page. Lists all content uploaded to the system with
// search, filter by status/type, and quick actions (View, Edit, Delete).
// Matches the Intercen theme: Playfair Display headings, DM Sans body,
// cream background (#F9F5EF), primary red (#B11226), charcoal nav.

import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

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

// ── Constants ──────────────────────────────────────────────────────────────
const _kCard = 12.0;

const _kStatusColors = {
  'published':     (_kGreen,    _kGreenBg),
  'draft':         (_kMuted,    Color(0xFFF3F4F6)),
  'pending_review':(_kAmber,    _kAmberBg),
  'archived':      (_kMutedLt,  Color(0xFFF3F4F6)),
  'rejected':      (_kRed,      _kRedBg),
};

const _kTypeColors = {
  'book':         (_kBlue,   _kBlueBg),
  'ebook':        (_kPurple, _kPurpleBg),
  'document':     (_kMuted,  Color(0xFFF3F4F6)),
  'paper':        (_kGreen,  _kGreenBg),
  'report':       (_kAmber,  _kAmberBg),
  'manual':       (_kCharcoal, Color(0xFFE5E7EB)),
  'guide':        (_kBlue,   _kBlueBg),
  'manuscript':   (_kPrimary, Color(0xFFFEE2E2)),
  'article':      (_kGreen,  _kGreenBg),
  'thesis':       (_kPurple, _kPurpleBg),
  'dissertation': (_kPrimary, Color(0xFFFEE2E2)),
};

class ContentManagementPage extends StatefulWidget {
  const ContentManagementPage({Key? key}) : super(key: key);
  @override
  State<ContentManagementPage> createState() => _ContentManagementPageState();
}

class _ContentManagementPageState extends State<ContentManagementPage> {
  final _sb = Supabase.instance.client;

  List<Map<String, dynamic>> _all      = [];
  List<Map<String, dynamic>> _filtered = [];
  bool   _loading     = true;
  bool   _isAdmin     = false;
  String _search      = '';
  String _statusFilter = 'all';
  String _typeFilter   = 'all';
  String _sortBy       = 'newest';

  final _searchCtrl = TextEditingController();

  // ── lifecycle ──────────────────────────────────────────────────────────
  @override
  void initState() {
    super.initState();
    _checkAdminAndLoad();
  }

  @override
  void dispose() {
    _searchCtrl.dispose();
    super.dispose();
  }

  // ── admin guard ────────────────────────────────────────────────────────
  Future<void> _checkAdminAndLoad() async {
    await RoleService.instance.load();
    final role = RoleService.instance.role;
    if (role != 'admin') {
      if (mounted) {
        Navigator.pushReplacementNamed(context, '/home');
        _toast('Access denied. Admin only.', err: true);
      }
      return;
    }
    setState(() => _isAdmin = true);
    await _loadContent();
  }

  // ── data ───────────────────────────────────────────────────────────────
  Future<void> _loadContent() async {
    setState(() => _loading = true);
    try {
      final data = await _sb
          .from('content')
          .select(
              'id,title,author,content_type,status,visibility,price,'
              'cover_image_url,view_count,total_downloads,created_at,'
              'updated_at,uploaded_by')
          .order('created_at', ascending: false);

      if (!mounted) return;
      setState(() {
        _all = List<Map<String, dynamic>>.from(data as List);
        _applyFilters();
      });
    } catch (e) {
      _toast('Failed to load content: $e', err: true);
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  void _applyFilters() {
    var list = List<Map<String, dynamic>>.from(_all);

    // search
    if (_search.isNotEmpty) {
      final q = _search.toLowerCase();
      list = list.where((c) {
        final t = (c['title']        as String? ?? '').toLowerCase();
        final a = (c['author']       as String? ?? '').toLowerCase();
        final y = (c['content_type'] as String? ?? '').toLowerCase();
        return t.contains(q) || a.contains(q) || y.contains(q);
      }).toList();
    }

    // status
    if (_statusFilter != 'all') {
      list = list.where((c) => c['status'] == _statusFilter).toList();
    }

    // type
    if (_typeFilter != 'all') {
      list = list.where((c) => c['content_type'] == _typeFilter).toList();
    }

    // sort
    switch (_sortBy) {
      case 'newest':
        list.sort((a, b) => (b['created_at'] as String? ?? '')
            .compareTo(a['created_at'] as String? ?? ''));
        break;
      case 'oldest':
        list.sort((a, b) => (a['created_at'] as String? ?? '')
            .compareTo(b['created_at'] as String? ?? ''));
        break;
      case 'title':
        list.sort((a, b) => (a['title'] as String? ?? '')
            .compareTo(b['title'] as String? ?? ''));
        break;
      case 'views':
        list.sort((a, b) =>
            (b['view_count'] as int? ?? 0)
                .compareTo(a['view_count'] as int? ?? 0));
        break;
    }

    setState(() => _filtered = list);
  }

  Future<void> _deleteContent(String id, String title) async {
    final confirmed = await _showDeleteDialog(title);
    if (!confirmed) return;

    try {
      await _sb.from('content').delete().eq('id', id);
      setState(() {
        _all      = _all.where((c) => c['id'] != id).toList();
        _filtered = _filtered.where((c) => c['id'] != id).toList();
      });
      _toast('Deleted "$title"');
    } catch (e) {
      _toast('Delete failed: $e', err: true);
    }
  }

  Future<bool> _showDeleteDialog(String title) async {
    return await showDialog<bool>(
          context: context,
          builder: (ctx) => AlertDialog(
            shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(16)),
            title: const Text('Delete Content',
                style: TextStyle(
                    fontFamily: 'PlayfairDisplay',
                    fontWeight: FontWeight.w700)),
            content: Text(
              'Are you sure you want to permanently delete "$title"? '
              'This cannot be undone.',
              style: const TextStyle(
                  fontFamily: 'DM Sans', color: _kMuted, height: 1.5),
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(ctx, false),
                child: const Text('Cancel',
                    style: TextStyle(
                        fontFamily: 'DM Sans', color: _kMuted)),
              ),
              ElevatedButton(
                onPressed: () => Navigator.pop(ctx, true),
                style: ElevatedButton.styleFrom(
                  backgroundColor: _kRed,
                  foregroundColor: _kWhite,
                  elevation: 0,
                  shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(8)),
                ),
                child: const Text('Delete',
                    style: TextStyle(
                        fontFamily: 'DM Sans',
                        fontWeight: FontWeight.w700)),
              ),
            ],
          ),
        ) ??
        false;
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

  // ── unique filter values ────────────────────────────────────────────────
  List<String> get _statusOptions {
    final s = {'all', ..._all.map((c) => c['status'] as String? ?? 'draft')};
    return s.toList()..sort();
  }

  List<String> get _typeOptions {
    final s = {
      'all',
      ..._all.map((c) => c['content_type'] as String? ?? 'book')
    };
    return s.toList()..sort();
  }

  // ── stats ──────────────────────────────────────────────────────────────
  int get _publishedCount =>
      _all.where((c) => c['status'] == 'published').length;
  int get _draftCount =>
      _all.where((c) => c['status'] == 'draft').length;
  int get _pendingCount =>
      _all.where((c) => c['status'] == 'pending_review').length;
  int get _totalViews =>
      _all.fold(0, (s, c) => s + (c['view_count'] as int? ?? 0));

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
      floatingActionButton: _fab(),
      body: RefreshIndicator(
        color: _kPrimary,
        onRefresh: _loadContent,
        child: _loading
            ? const Center(
                child: CircularProgressIndicator(
                    valueColor: AlwaysStoppedAnimation(_kPrimary)))
            : CustomScrollView(
                slivers: [
                  SliverToBoxAdapter(child: _statsRow(w)),
                  SliverToBoxAdapter(child: _filterBar(w)),
                  SliverToBoxAdapter(child: _resultsHeader()),
                  _filtered.isEmpty
                      ? SliverFillRemaining(child: _emptyState())
                      : SliverList(
                          delegate: SliverChildBuilderDelegate(
                            (_, i) => _contentCard(_filtered[i], w),
                            childCount: _filtered.length,
                          ),
                        ),
                  const SliverToBoxAdapter(child: SizedBox(height: 100)),
                ],
              ),
      ),
    );
  }

  Widget _splash() => Scaffold(
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
              const Text('Verifying access…',
                  style: TextStyle(
                      fontFamily: 'DM Sans',
                      color: _kMuted,
                      fontSize: 14)),
            ],
          ),
        ),
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
            Text('Content Management',
                style: TextStyle(
                    fontFamily: 'PlayfairDisplay',
                    fontSize: 17,
                    fontWeight: FontWeight.w700,
                    color: _kWhite)),
            Text('Admin — full library',
                style: TextStyle(
                    fontFamily: 'DM Sans',
                    fontSize: 11,
                    color: Colors.white54)),
          ],
        ),
        actions: [
          IconButton(
            icon: const Icon(Icons.refresh_rounded,
                size: 20, color: Colors.white70),
            onPressed: _loadContent,
            tooltip: 'Refresh',
          ),
          IconButton(
            icon: const Icon(Icons.upload_rounded,
                size: 20, color: Colors.white70),
            onPressed: () => Navigator.pushNamed(context, '/upload'),
            tooltip: 'Upload',
          ),
        ],
        bottom: PreferredSize(
          preferredSize: const Size.fromHeight(1),
          child: Container(height: 1, color: Colors.white12),
        ),
      );

  Widget _fab() => FloatingActionButton.extended(
        onPressed: () => Navigator.pushNamed(context, '/upload'),
        backgroundColor: _kPrimary,
        foregroundColor: _kWhite,
        icon: const Icon(Icons.add_rounded),
        label: const Text('Upload',
            style: TextStyle(
                fontFamily: 'DM Sans', fontWeight: FontWeight.w700)),
      );

  // ── stats row ──────────────────────────────────────────────────────────
  Widget _statsRow(double w) {
    final pad  = _hp(w);
    final cols = w >= 600 ? 4 : 2;
    final stats = [
      _SD('Total',     '${_all.length}',     Icons.inventory_2_outlined,   _kBlue,    _kBlueBg),
      _SD('Published', '$_publishedCount',   Icons.check_circle_outlined,  _kGreen,   _kGreenBg),
      _SD('Pending',   '$_pendingCount',     Icons.access_time_rounded,    _kAmber,   _kAmberBg),
      _SD('Total Views','$_totalViews',      Icons.visibility_outlined,    _kPurple,  _kPurpleBg),
    ];
    return Padding(
      padding: EdgeInsets.fromLTRB(pad, 20, pad, 0),
      child: GridView.count(
        shrinkWrap: true,
        physics: const NeverScrollableScrollPhysics(),
        crossAxisCount: cols,
        crossAxisSpacing: 12,
        mainAxisSpacing: 12,
        childAspectRatio: w < 400 ? 2.0 : 2.4,
        children: stats.map((s) => _StatTile(s)).toList(),
      ),
    );
  }

  // ── filter bar ─────────────────────────────────────────────────────────
  Widget _filterBar(double w) {
    final pad = _hp(w);
    return Padding(
      padding: EdgeInsets.fromLTRB(pad, 20, pad, 0),
      child: Column(
        children: [
          // search
          TextField(
            controller: _searchCtrl,
            style: const TextStyle(
                fontFamily: 'DM Sans', fontSize: 14, color: _kCharcoal),
            onChanged: (v) {
              _search = v;
              _applyFilters();
            },
            decoration: InputDecoration(
              hintText: 'Search by title, author or type…',
              hintStyle: const TextStyle(
                  fontFamily: 'DM Sans', fontSize: 13, color: _kMutedLt),
              prefixIcon: const Icon(Icons.search_rounded,
                  size: 18, color: _kMutedLt),
              suffixIcon: _search.isNotEmpty
                  ? IconButton(
                      icon: const Icon(Icons.close_rounded,
                          size: 16, color: _kMutedLt),
                      onPressed: () {
                        _searchCtrl.clear();
                        _search = '';
                        _applyFilters();
                      },
                    )
                  : null,
              filled: true,
              fillColor: _kWhite,
              contentPadding: const EdgeInsets.symmetric(
                  horizontal: 16, vertical: 12),
              border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(10),
                  borderSide: const BorderSide(color: _kBorder)),
              enabledBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(10),
                  borderSide: const BorderSide(color: _kBorder)),
              focusedBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(10),
                  borderSide:
                      const BorderSide(color: _kPrimary, width: 1.5)),
            ),
          ),
          const SizedBox(height: 12),
          // chip filters
          SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            child: Row(
              children: [
                // status
                ..._statusOptions.map((s) => _FilterChip(
                      label: s == 'all' ? 'All Status' : s.replaceAll('_', ' '),
                      selected: _statusFilter == s,
                      onTap: () {
                        _statusFilter = s;
                        _applyFilters();
                      },
                    )),
                const SizedBox(width: 8),
                Container(width: 1, height: 20, color: _kBorder),
                const SizedBox(width: 8),
                // sort
                ...[
                  ('newest', 'Newest'),
                  ('oldest', 'Oldest'),
                  ('title', 'A–Z'),
                  ('views', 'Most Viewed'),
                ].map((t) => _FilterChip(
                      label: t.$2,
                      selected: _sortBy == t.$1,
                      color: _kBlue,
                      onTap: () {
                        _sortBy = t.$1;
                        _applyFilters();
                      },
                    )),
              ],
            ),
          ),
          const SizedBox(height: 8),
          // type chips
          SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            child: Row(
              children: _typeOptions.map((t) => _FilterChip(
                    label: t == 'all' ? 'All Types' : t,
                    selected: _typeFilter == t,
                    color: _kPurple,
                    onTap: () {
                      _typeFilter = t;
                      _applyFilters();
                    },
                  )).toList(),
            ),
          ),
        ],
      ),
    );
  }

  Widget _resultsHeader() {
    final pad = _hp(MediaQuery.of(context).size.width);
    return Padding(
      padding: EdgeInsets.fromLTRB(pad, 20, pad, 8),
      child: Row(children: [
        Text('${_filtered.length} result${_filtered.length == 1 ? '' : 's'}',
            style: const TextStyle(
                fontFamily: 'DM Sans',
                fontSize: 13,
                fontWeight: FontWeight.w600,
                color: _kMuted)),
        const Spacer(),
        if (_search.isNotEmpty ||
            _statusFilter != 'all' ||
            _typeFilter != 'all')
          GestureDetector(
            onTap: () {
              _searchCtrl.clear();
              _search       = '';
              _statusFilter = 'all';
              _typeFilter   = 'all';
              _sortBy       = 'newest';
              _applyFilters();
            },
            child: const Text('Clear filters',
                style: TextStyle(
                    fontFamily: 'DM Sans',
                    fontSize: 12,
                    color: _kPrimary,
                    fontWeight: FontWeight.w600,
                    decoration: TextDecoration.underline)),
          ),
      ]),
    );
  }

  // ── content card ───────────────────────────────────────────────────────
  Widget _contentCard(Map<String, dynamic> c, double w) {
    final pad    = _hp(w);
    final status = c['status'] as String? ?? 'draft';
    final type   = c['content_type'] as String? ?? 'book';
    final sc     = _kStatusColors[status] ?? (_kMuted, const Color(0xFFF3F4F6));
    final tc     = _kTypeColors[type]   ?? (_kMuted, const Color(0xFFF3F4F6));
    final price  = double.tryParse(c['price']?.toString() ?? '0') ?? 0;

    return Padding(
      padding: EdgeInsets.fromLTRB(pad, 0, pad, 12),
      child: Container(
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
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // ── top row: cover + meta ──────────────────────────────────
            Padding(
              padding: const EdgeInsets.all(14),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // cover thumbnail
                  ClipRRect(
                    borderRadius: BorderRadius.circular(8),
                    child: SizedBox(
                      width: 56, height: 76,
                      child: _cover(c['cover_image_url'] as String?),
                    ),
                  ),
                  const SizedBox(width: 12),
                  // meta
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        // title + status
                        Row(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Expanded(
                              child: Text(
                                c['title'] as String? ?? 'Untitled',
                                style: const TextStyle(
                                  fontFamily: 'PlayfairDisplay',
                                  fontSize: 15,
                                  fontWeight: FontWeight.w700,
                                  color: _kCharcoal,
                                  height: 1.3,
                                ),
                                maxLines: 2,
                                overflow: TextOverflow.ellipsis,
                              ),
                            ),
                            const SizedBox(width: 8),
                            _Pill(sc.$1, sc.$2, status.replaceAll('_', ' ')),
                          ],
                        ),
                        const SizedBox(height: 4),
                        // author
                        if ((c['author'] as String? ?? '').isNotEmpty)
                          Text('by ${c['author']}',
                              style: const TextStyle(
                                  fontFamily: 'DM Sans',
                                  fontSize: 12,
                                  color: _kMuted)),
                        const SizedBox(height: 6),
                        // type + price
                        Wrap(spacing: 6, runSpacing: 4, children: [
                          _Pill(tc.$1, tc.$2, type),
                          _Pill(
                            _kCharcoal,
                            const Color(0xFFF3F4F6),
                            price == 0
                                ? 'Free'
                                : 'KES ${price.toStringAsFixed(0)}',
                          ),
                          if ((c['visibility'] as String? ?? '') == 'public')
                            _Pill(_kGreen, _kGreenBg, 'public'),
                        ]),
                        const SizedBox(height: 6),
                        // metrics
                        Row(children: [
                          _Metric(Icons.visibility_outlined,
                              '${c['view_count'] ?? 0}'),
                          const SizedBox(width: 10),
                          _Metric(Icons.download_outlined,
                              '${c['total_downloads'] ?? 0}'),
                          const SizedBox(width: 10),
                          _Metric(Icons.calendar_today_outlined,
                              _date(c['created_at'])),
                        ]),
                      ],
                    ),
                  ),
                ],
              ),
            ),
            // ── action row ─────────────────────────────────────────────
            Container(
              decoration: const BoxDecoration(
                border: Border(top: BorderSide(color: _kBorder)),
              ),
              padding: const EdgeInsets.symmetric(
                  horizontal: 14, vertical: 10),
              child: Row(
                children: [
                  _ActionBtn(
                    icon: Icons.visibility_outlined,
                    label: 'View',
                    color: _kBlue,
                    onTap: () => Navigator.pushNamed(
                        context, '/content/${c['id']}'),
                  ),
                  const SizedBox(width: 8),
                  _ActionBtn(
                    icon: Icons.edit_outlined,
                    label: 'Edit',
                    color: _kCharcoal,
                    onTap: () => Navigator.pushNamed(
                        context, '/content/update/${c['id']}'),
                  ),
                  const Spacer(),
                  _ActionBtn(
                    icon: Icons.delete_outline_rounded,
                    label: 'Delete',
                    color: _kRed,
                    onTap: () => _deleteContent(
                        c['id'] as String,
                        c['title'] as String? ?? 'Untitled'),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _emptyState() => Center(
        child: Padding(
          padding: const EdgeInsets.all(40),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Container(
                width: 80, height: 80,
                decoration: BoxDecoration(
                    color: const Color(0xFFF3F4F6),
                    borderRadius: BorderRadius.circular(40)),
                child: const Icon(Icons.library_books_outlined,
                    size: 40, color: _kMutedLt),
              ),
              const SizedBox(height: 16),
              const Text('No content found',
                  style: TextStyle(
                      fontFamily: 'PlayfairDisplay',
                      fontSize: 18,
                      fontWeight: FontWeight.w700,
                      color: _kCharcoal)),
              const SizedBox(height: 8),
              const Text(
                'Try adjusting your search or filters,\n'
                'or upload some new content.',
                textAlign: TextAlign.center,
                style: TextStyle(
                    fontFamily: 'DM Sans',
                    color: _kMuted,
                    fontSize: 13,
                    height: 1.5),
              ),
              const SizedBox(height: 24),
              ElevatedButton.icon(
                icon: const Icon(Icons.add_rounded, size: 16),
                label: const Text('Upload Content',
                    style: TextStyle(fontFamily: 'DM Sans')),
                style: ElevatedButton.styleFrom(
                  backgroundColor: _kPrimary,
                  foregroundColor: _kWhite,
                  elevation: 0,
                  shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(8)),
                ),
                onPressed: () =>
                    Navigator.pushNamed(context, '/upload'),
              ),
            ],
          ),
        ),
      );

  // ── helpers ────────────────────────────────────────────────────────────
  Widget _cover(String? url) {
    if (url != null && url.isNotEmpty) {
      return CachedNetworkImage(
        imageUrl: url,
        fit: BoxFit.cover,
        placeholder: (_, __) => Container(color: const Color(0xFFE5E7EB)),
        errorWidget: (_, __, ___) => _fallback(),
      );
    }
    return _fallback();
  }

  Widget _fallback() => Container(
        color: const Color(0xFFE5E7EB),
        child: const Center(
          child: Icon(Icons.book_outlined, size: 24, color: _kMutedLt),
        ),
      );

  String _date(dynamic raw) {
    if (raw == null) return '';
    try {
      final d = DateTime.parse(raw as String).toLocal();
      return '${d.day}/${d.month}/${d.year}';
    } catch (_) { return ''; }
  }

  static double _hp(double w) {
    if (w >= 900) return 32;
    if (w >= 600) return 20;
    return 16;
  }
}

// ── Stat data ──────────────────────────────────────────────────────────────
class _SD {
  final String label, value; final IconData icon;
  final Color color, bg;
  const _SD(this.label, this.value, this.icon, this.color, this.bg);
}

class _StatTile extends StatelessWidget {
  final _SD d;
  // ignore: use_super_parameters
  const _StatTile(this.d, {Key? key}) : super(key: key);
  @override
  Widget build(BuildContext context) => Container(
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          color: _kWhite,
          borderRadius: BorderRadius.circular(_kCard),
          boxShadow: [
            BoxShadow(color: Colors.black.withOpacity(0.05),
                blurRadius: 6, offset: const Offset(0, 2)),
          ],
        ),
        child: Row(children: [
          Container(
            width: 36, height: 36,
            decoration: BoxDecoration(
                color: d.bg, borderRadius: BorderRadius.circular(8)),
            child: Icon(d.icon, color: d.color, size: 18),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                FittedBox(
                  fit: BoxFit.scaleDown,
                  alignment: Alignment.centerLeft,
                  child: Text(d.value,
                      style: const TextStyle(
                          fontFamily: 'DM Sans',
                          fontSize: 20, fontWeight: FontWeight.w800,
                          color: _kCharcoal)),
                ),
                Text(d.label,
                    style: const TextStyle(
                        fontFamily: 'DM Sans',
                        fontSize: 10, color: _kMutedLt),
                    overflow: TextOverflow.ellipsis),
              ],
            ),
          ),
        ]),
      );
}

class _Pill extends StatelessWidget {
  final Color fg, bg; final String label;
  // ignore: use_super_parameters
  const _Pill(this.fg, this.bg, this.label, {Key? key}) : super(key: key);
  @override
  Widget build(BuildContext context) => Container(
        padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2),
        decoration: BoxDecoration(
          color: bg,
          borderRadius: BorderRadius.circular(20),
          border: Border.all(color: fg.withOpacity(0.2)),
        ),
        child: Text(label,
            style: TextStyle(
                fontFamily: 'DM Sans',
                fontSize: 10,
                fontWeight: FontWeight.w700,
                color: fg)),
      );
}

class _Metric extends StatelessWidget {
  final IconData icon; final String value;
  // ignore: use_super_parameters
  const _Metric(this.icon, this.value, {Key? key}) : super(key: key);
  @override
  Widget build(BuildContext context) => Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 11, color: _kMutedLt),
          const SizedBox(width: 3),
          Text(value,
              style: const TextStyle(
                  fontFamily: 'DM Sans',
                  fontSize: 11, color: _kMutedLt)),
        ],
      );
}

class _FilterChip extends StatelessWidget {
  final String label; final bool selected;
  final Color color; final VoidCallback onTap;
  // ignore: use_super_parameters
  const _FilterChip({
    required this.label, required this.selected,
    required this.onTap,
    this.color = _kPrimary, Key? key,
  }) : super(key: key);
  @override
  Widget build(BuildContext context) => GestureDetector(
        onTap: onTap,
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 160),
          margin: const EdgeInsets.only(right: 6),
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
          decoration: BoxDecoration(
            color: selected ? color : _kWhite,
            borderRadius: BorderRadius.circular(20),
            border: Border.all(
                color: selected ? color : _kBorder, width: 1.2),
          ),
          child: Text(label,
              style: TextStyle(
                  fontFamily: 'DM Sans',
                  fontSize: 11,
                  fontWeight: FontWeight.w600,
                  color: selected ? _kWhite : _kMuted)),
        ),
      );
}

class _ActionBtn extends StatelessWidget {
  final IconData icon; final String label;
  final Color color; final VoidCallback onTap;
  // ignore: use_super_parameters
  const _ActionBtn({
    required this.icon, required this.label,
    required this.color, required this.onTap, Key? key,
  }) : super(key: key);
  @override
  Widget build(BuildContext context) => GestureDetector(
        onTap: onTap,
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 7),
          decoration: BoxDecoration(
            color: color.withOpacity(0.07),
            border: Border.all(color: color.withOpacity(0.2)),
            borderRadius: BorderRadius.circular(8),
          ),
          child: Row(mainAxisSize: MainAxisSize.min, children: [
            Icon(icon, size: 13, color: color),
            const SizedBox(width: 5),
            Text(label,
                style: TextStyle(
                    fontFamily: 'DM Sans',
                    fontSize: 12,
                    fontWeight: FontWeight.w700,
                    color: color)),
          ]),
        ),
      );
}