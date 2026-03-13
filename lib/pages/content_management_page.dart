import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../theme/app_colors.dart';

// ─────────────────────────────────────────────────────────────────────────────
// CONTENT MANAGEMENT PAGE
//
// Route: /content-management
// Guard: AuthGuard (session required)
//
// The publisher / author's personal content library. Shows every piece of
// content the logged-in user has uploaded with rich status chips, stats, and
// full CRUD (view, edit, unpublish/publish, delete).
//
// Security model:
//   • All queries are filtered by `uploaded_by = auth.uid()` both here AND
//     enforced at the DB level via RLS — so even a spoofed route param can
//     never surface another user's content.
//   • Session is re-validated on initState; stale / missing sessions redirect
//     immediately to /login.
//   • Delete requires a double-confirm dialog with the content title typed
//     back in to prevent accidental permanent deletions.
// ─────────────────────────────────────────────────────────────────────────────

class ContentManagementPage extends StatefulWidget {
  const ContentManagementPage({super.key});

  @override
  State<ContentManagementPage> createState() => _ContentManagementPageState();
}

class _ContentManagementPageState extends State<ContentManagementPage>
    with SingleTickerProviderStateMixin {
  final _sb = Supabase.instance.client;

  List<Map<String, dynamic>> _allContent    = [];
  List<Map<String, dynamic>> _filtered      = [];
  bool   _loading   = true;
  String? _error;

  // ── Filters ───────────────────────────────────────────────────────────────
  String _search      = '';
  String _statusFilter = 'all';   // all | published | draft | under_review
  String _typeFilter   = 'all';   // all | book | article | journal | ...
  String _sortBy       = 'newest'; // newest | oldest | title | price

  final _searchCtrl = TextEditingController();

  late final TabController _tabCtrl;
  static const _tabs = ['all', 'published', 'draft', 'under_review'];
  static const _tabLabels = ['All', 'Published', 'Draft', 'In Review'];

  @override
  void initState() {
    super.initState();
    _tabCtrl = TabController(length: _tabs.length, vsync: this)
      ..addListener(() {
        if (!_tabCtrl.indexIsChanging) {
          setState(() {
            _statusFilter = _tabs[_tabCtrl.index];
            _applyFilters();
          });
        }
      });
    _secureLoad();
  }

  @override
  void dispose() {
    _tabCtrl.dispose();
    _searchCtrl.dispose();
    super.dispose();
  }

  // ── Security: validate session before any data fetch ─────────────────────
  Future<void> _secureLoad() async {
    final session = _sb.auth.currentSession;
    if (session == null) {
      WidgetsBinding.instance.addPostFrameCallback((_) =>
          Navigator.pushNamedAndRemoveUntil(
              context, '/login', (_) => false));
      return;
    }
    // Refresh session token to ensure it hasn't silently expired
    try {
      await _sb.auth.refreshSession();
    } catch (_) {
      if (mounted) {
        Navigator.pushNamedAndRemoveUntil(context, '/login', (_) => false);
      }
      return;
    }
    _fetchContent();
  }

  // ── Fetch — always scoped to current user via RLS ─────────────────────────
  Future<void> _fetchContent() async {
    if (!mounted) return;
    setState(() { _loading = true; _error = null; });
    try {
      final uid = _sb.auth.currentUser!.id;
      final data = await _sb
          .from('content')
          .select('''
            id, title, author, content_type, status, visibility,
            cover_image_url, price, page_count, total_downloads,
            total_reviews, created_at, updated_at, description,
            is_for_sale, stock_quantity
          ''')
          .eq('uploaded_by', uid)          // ✅ FIXED: was 'uploader_id'
          .order('created_at', ascending: false);

      setState(() {
        _allContent = List<Map<String, dynamic>>.from(data);
        _applyFilters();
      });
    } catch (e) {
      setState(() => _error = e.toString().replaceFirst('Exception: ', ''));
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  void _applyFilters() {
    var list = List<Map<String, dynamic>>.from(_allContent);

    // Status tab filter
    if (_statusFilter != 'all') {
      list = list.where((c) => c['status'] == _statusFilter).toList();
    }

    // Type filter
    if (_typeFilter != 'all') {
      list = list.where((c) => c['content_type'] == _typeFilter).toList();
    }

    // Search
    if (_search.trim().isNotEmpty) {
      final q = _search.toLowerCase();
      list = list.where((c) {
        final title  = (c['title']  as String? ?? '').toLowerCase();
        final author = (c['author'] as String? ?? '').toLowerCase();
        return title.contains(q) || author.contains(q);
      }).toList();
    }

    // Sort
    switch (_sortBy) {
      case 'oldest':
        list.sort((a, b) =>
            (a['created_at'] as String).compareTo(b['created_at'] as String));
      case 'title':
        list.sort((a, b) =>
            (a['title'] as String? ?? '').compareTo(b['title'] as String? ?? ''));
      case 'price':
        list.sort((a, b) {
          final pa = (a['price'] as num?)?.toDouble() ?? 0;
          final pb = (b['price'] as num?)?.toDouble() ?? 0;
          return pb.compareTo(pa);
        });
      default: // newest — already sorted by DB
        break;
    }

    setState(() => _filtered = list);
  }

  // ── Toggle publish / unpublish ────────────────────────────────────────────
  Future<void> _toggleStatus(Map<String, dynamic> item) async {
    final id         = item['id'] as String;
    final current    = item['status'] as String? ?? 'draft';
    final newStatus  = current == 'published' ? 'draft' : 'published';
    final label      = newStatus == 'published' ? 'publish' : 'unpublish';

    final confirmed = await _confirmDialog(
      title: '${label[0].toUpperCase()}${label.substring(1)} Content',
      body:  'Are you sure you want to $label "${item['title']}"?',
      confirmLabel: label[0].toUpperCase() + label.substring(1),
      destructive: newStatus != 'published',
    );
    if (!confirmed) return;

    try {
      await _sb.from('content').update({
        'status':     newStatus,
        'updated_at': DateTime.now().toIso8601String(),
      })
          .eq('id', id)
          .eq('uploaded_by', _sb.auth.currentUser!.id); // ✅ FIXED: was 'uploader_id'

      _showSnack(
        '"${item['title']}" ${newStatus == 'published' ? 'published ✓' : 'unpublished'}',
        success: newStatus == 'published',
      );
      _fetchContent();
    } catch (e) {
      _showSnack('Failed to update status');
    }
  }

  // ── Permanent delete with title-confirmation ──────────────────────────────
  Future<void> _deleteContent(Map<String, dynamic> item) async {
    final id    = item['id']    as String;
    final title = item['title'] as String? ?? 'this content';

    // Step 1: soft confirm
    final step1 = await _confirmDialog(
      title:        'Delete Content',
      body:         'This will permanently delete "$title" and cannot be undone.',
      confirmLabel: 'Continue',
      destructive:  true,
    );
    if (!step1) return;

    // Step 2: type-the-title confirmation for irreversible action
    final titleCtrl = TextEditingController();
    final step2 = await showDialog<bool>(
      context: context,
      barrierDismissible: false,
      builder: (_) => StatefulBuilder(
        builder: (ctx, setSt) => AlertDialog(
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
          title: const Row(children: [
            Icon(Icons.warning_amber_rounded,
                color: Color(0xFFDC2626), size: 22),
            SizedBox(width: 8),
            Text('Confirm Deletion',
                style: TextStyle(
                    fontFamily: 'PlayfairDisplay',
                    fontWeight: FontWeight.w800,
                    fontSize: 18)),
          ]),
          content: Column(mainAxisSize: MainAxisSize.min, children: [
            RichText(text: TextSpan(
              style: const TextStyle(fontFamily: 'DM Sans',
                  fontSize: 13, color: Color(0xFF374151), height: 1.5),
              children: [
                const TextSpan(text: 'Type '),
                TextSpan(text: '"$title"',
                    style: const TextStyle(fontWeight: FontWeight.w700,
                        color: Color(0xFFDC2626))),
                const TextSpan(text: ' to confirm permanent deletion.'),
              ],
            )),
            const SizedBox(height: 14),
            TextField(
              controller: titleCtrl,
              autofocus: true,
              style: const TextStyle(fontFamily: 'DM Sans', fontSize: 14),
              onChanged: (_) => setSt(() {}),
              decoration: InputDecoration(
                hintText: title,
                hintStyle: const TextStyle(color: Color(0xFFD1D5DB)),
                border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(10),
                    borderSide:
                        const BorderSide(color: Color(0xFFE5E7EB))),
                focusedBorder: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(10),
                    borderSide: const BorderSide(
                        color: Color(0xFFDC2626), width: 2)),
                contentPadding: const EdgeInsets.symmetric(
                    horizontal: 12, vertical: 12),
              ),
            ),
          ]),
          actions: [
            TextButton(
                onPressed: () => Navigator.pop(ctx, false),
                child: const Text('Cancel')),
            ElevatedButton(
              onPressed: titleCtrl.text.trim() == title
                  ? () => Navigator.pop(ctx, true)
                  : null,
              style: ElevatedButton.styleFrom(
                  backgroundColor: const Color(0xFFDC2626),
                  foregroundColor: Colors.white,
                  shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(10))),
              child: const Text('Delete Forever',
                  style: TextStyle(fontFamily: 'DM Sans')),
            ),
          ],
        ),
      ),
    ) ?? false;

    if (!step2) return;

    try {
      await _sb.from('content')
          .delete()
          .eq('id', id)
          .eq('uploaded_by', _sb.auth.currentUser!.id); // ✅ FIXED: was 'uploader_id'
      _showSnack('"$title" deleted permanently');
      _fetchContent();
    } catch (e) {
      _showSnack('Failed to delete content');
    }
  }

  // ── Helpers ───────────────────────────────────────────────────────────────
  void _showSnack(String msg, {bool success = false}) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(
      content: Text(msg, style: const TextStyle(fontFamily: 'DM Sans')),
      backgroundColor: success ? const Color(0xFF16A34A) : AppColors.primary,
      behavior: SnackBarBehavior.floating,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
    ));
  }

  Future<bool> _confirmDialog({
    required String title,
    required String body,
    required String confirmLabel,
    bool destructive = false,
  }) async =>
      await showDialog<bool>(
        context: context,
        builder: (_) => AlertDialog(
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
          title: Text(title,
              style: const TextStyle(
                  fontFamily: 'PlayfairDisplay', fontWeight: FontWeight.w800)),
          content: Text(body,
              style: const TextStyle(
                  fontFamily: 'DM Sans',
                  color: Color(0xFF6B7280),
                  height: 1.5)),
          actions: [
            TextButton(
                onPressed: () => Navigator.pop(context, false),
                child: const Text('Cancel',
                    style: TextStyle(fontFamily: 'DM Sans'))),
            ElevatedButton(
              onPressed: () => Navigator.pop(context, true),
              style: ElevatedButton.styleFrom(
                  backgroundColor: destructive
                      ? const Color(0xFFDC2626)
                      : AppColors.primary,
                  foregroundColor: Colors.white,
                  shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(10))),
              child: Text(confirmLabel,
                  style: const TextStyle(fontFamily: 'DM Sans')),
            ),
          ],
        ),
      ) ??
      false;

  // ── Stats banner ──────────────────────────────────────────────────────────
  Map<String, int> get _stats => {
        'total':     _allContent.length,
        'published': _allContent.where((c) => c['status'] == 'published').length,
        'draft':     _allContent.where((c) => c['status'] == 'draft').length,
        'review':    _allContent.where((c) =>
            c['status'] == 'under_review').length,
      };

  // ════════════════════════════════════════════════════════════════════════════
  // BUILD
  // ════════════════════════════════════════════════════════════════════════════
  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFF9F5EF),
      body: NestedScrollView(
        headerSliverBuilder: (_, __) => [_buildAppBar()],
        body: _loading
            ? _loadingState()
            : _error != null
                ? _errorState()
                : _allContent.isEmpty
                    ? _emptyFirstState()
                    : _buildBody(),
      ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: () =>
            Navigator.pushNamed(context, '/publish')
                .then((_) => _fetchContent()),
        backgroundColor: AppColors.primary,
        foregroundColor: Colors.white,
        elevation: 3,
        icon: const Icon(Icons.add_rounded),
        label: const Text('New Content',
            style: TextStyle(
                fontFamily: 'DM Sans', fontWeight: FontWeight.w700)),
      ),
    );
  }

  // ── App bar ───────────────────────────────────────────────────────────────
  Widget _buildAppBar() => SliverAppBar(
        expandedHeight: 160,
        pinned: true,
        backgroundColor: Colors.white,
        surfaceTintColor: Colors.transparent,
        elevation: 0,
        leading: IconButton(
          icon: const Icon(Icons.arrow_back_ios_new_rounded,
              size: 20, color: Color(0xFF1A1A2E)),
          onPressed: () => Navigator.pop(context),
        ),
        actions: [
          IconButton(
            icon: const Icon(Icons.refresh_rounded,
                color: Color(0xFF6B7280), size: 22),
            onPressed: _fetchContent,
            tooltip: 'Refresh',
          ),
          _SortButton(
            current: _sortBy,
            onChanged: (v) => setState(() { _sortBy = v; _applyFilters(); }),
          ),
          const SizedBox(width: 8),
        ],
        flexibleSpace: FlexibleSpaceBar(
          collapseMode: CollapseMode.pin,
          background: Container(
            color: Colors.white,
            child: SafeArea(
              child: Padding(
                padding: const EdgeInsets.fromLTRB(20, 56, 20, 0),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const Text('My Content',
                        style: TextStyle(
                            fontFamily: 'PlayfairDisplay',
                            fontSize: 26,
                            fontWeight: FontWeight.w800,
                            color: Color(0xFF111827))),
                    const SizedBox(height: 12),
                    // Stats row
                    Row(children: [
                      _StatPill('${_stats['total']}', 'Total',
                          const Color(0xFF2563EB), const Color(0xFFEFF6FF)),
                      const SizedBox(width: 8),
                      _StatPill('${_stats['published']}', 'Live',
                          const Color(0xFF16A34A), const Color(0xFFF0FDF4)),
                      const SizedBox(width: 8),
                      _StatPill('${_stats['draft']}', 'Draft',
                          const Color(0xFF6B7280), const Color(0xFFF3F4F6)),
                      const SizedBox(width: 8),
                      _StatPill('${_stats['review']}', 'Review',
                          const Color(0xFFD97706), const Color(0xFFFFFBEB)),
                    ]),
                  ],
                ),
              ),
            ),
          ),
        ),
        bottom: PreferredSize(
          preferredSize: const Size.fromHeight(96),
          child: Container(
            color: Colors.white,
            child: Column(mainAxisSize: MainAxisSize.min, children: [
              // Search
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 8, 16, 0),
                child: TextField(
                  controller: _searchCtrl,
                  onChanged: (v) =>
                      setState(() { _search = v; _applyFilters(); }),
                  style: const TextStyle(fontFamily: 'DM Sans', fontSize: 14),
                  decoration: InputDecoration(
                    hintText: 'Search your content…',
                    hintStyle: const TextStyle(
                        color: Color(0xFFD1D5DB), fontSize: 13),
                    prefixIcon: const Icon(Icons.search_rounded,
                        color: Color(0xFF9CA3AF), size: 20),
                    suffixIcon: _search.isNotEmpty
                        ? IconButton(
                            icon: const Icon(Icons.close_rounded,
                                size: 18, color: Color(0xFF9CA3AF)),
                            onPressed: () {
                              _searchCtrl.clear();
                              setState(() { _search = ''; _applyFilters(); });
                            })
                        : null,
                    filled: true,
                    fillColor: const Color(0xFFF3F4F6),
                    contentPadding: const EdgeInsets.symmetric(
                        horizontal: 16, vertical: 11),
                    border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(12),
                        borderSide: BorderSide.none),
                    isDense: true,
                  ),
                ),
              ),
              // Status tabs
              TabBar(
                controller: _tabCtrl,
                isScrollable: true,
                tabAlignment: TabAlignment.start,
                labelStyle: const TextStyle(
                    fontFamily: 'DM Sans',
                    fontSize: 13,
                    fontWeight: FontWeight.w700),
                unselectedLabelStyle: const TextStyle(
                    fontFamily: 'DM Sans', fontSize: 13),
                labelColor: AppColors.primary,
                unselectedLabelColor: const Color(0xFF9CA3AF),
                indicatorColor: AppColors.primary,
                indicatorWeight: 3,
                dividerColor: const Color(0xFFE5E7EB),
                tabs: List.generate(_tabs.length, (i) {
                  final count = _tabs[i] == 'all'
                      ? _allContent.length
                      : _allContent
                          .where((c) => c['status'] == _tabs[i])
                          .length;
                  return Tab(
                    child: Row(mainAxisSize: MainAxisSize.min, children: [
                      Text(_tabLabels[i]),
                      if (count > 0) ...[
                        const SizedBox(width: 5),
                        Container(
                          padding: const EdgeInsets.symmetric(
                              horizontal: 6, vertical: 1),
                          decoration: BoxDecoration(
                              color: AppColors.primary.withOpacity(0.1),
                              borderRadius: BorderRadius.circular(8)),
                          child: Text('$count',
                              style: TextStyle(
                                  fontSize: 10,
                                  fontWeight: FontWeight.w800,
                                  color: AppColors.primary)),
                        ),
                      ],
                    ]),
                  );
                }),
              ),
            ]),
          ),
        ),
      );

  // ── Body ──────────────────────────────────────────────────────────────────
  Widget _buildBody() {
    if (_filtered.isEmpty) {
      return Center(
        child: Column(mainAxisAlignment: MainAxisAlignment.center, children: [
          Icon(Icons.search_off_rounded,
              size: 56, color: const Color(0xFFD1D5DB)),
          const SizedBox(height: 12),
          const Text('No content matches your filter',
              style: TextStyle(fontFamily: 'DM Sans',
                  fontSize: 15, color: Color(0xFF9CA3AF))),
          const SizedBox(height: 8),
          TextButton(
            onPressed: () {
              _searchCtrl.clear();
              setState(() {
                _search = ''; _statusFilter = 'all';
                _typeFilter = 'all'; _tabCtrl.animateTo(0);
                _applyFilters();
              });
            },
            child: Text('Clear filters',
                style: TextStyle(color: AppColors.primary,
                    fontFamily: 'DM Sans', fontWeight: FontWeight.w600)),
          ),
        ]),
      );
    }

    return ListView.separated(
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 100),
      itemCount: _filtered.length,
      separatorBuilder: (_, __) => const SizedBox(height: 12),
      itemBuilder: (_, i) => _ContentCard(
        item: _filtered[i],
        onView: () => Navigator.pushNamed(
            context, '/content-view/${_filtered[i]['id']}'),
        onEdit: () => Navigator.pushNamed(
            context, '/content/update/${_filtered[i]['id']}')
              .then((_) => _fetchContent()),
        onToggleStatus: () => _toggleStatus(_filtered[i]),
        onDelete: () => _deleteContent(_filtered[i]),
      ),
    );
  }

  Widget _loadingState() => Center(
        child: Column(mainAxisAlignment: MainAxisAlignment.center, children: [
          CircularProgressIndicator(
              valueColor: AlwaysStoppedAnimation(AppColors.primary)),
          const SizedBox(height: 16),
          const Text('Loading your content…',
              style: TextStyle(fontFamily: 'DM Sans',
                  color: Color(0xFF6B7280), fontSize: 14)),
        ]));

  Widget _errorState() => Center(
        child: Padding(
          padding: const EdgeInsets.all(32),
          child: Column(mainAxisAlignment: MainAxisAlignment.center, children: [
            const Icon(Icons.error_outline_rounded,
                size: 56, color: Color(0xFFEF4444)),
            const SizedBox(height: 14),
            const Text('Could not load content',
                style: TextStyle(fontFamily: 'PlayfairDisplay',
                    fontSize: 20, fontWeight: FontWeight.w800)),
            const SizedBox(height: 8),
            Text(_error ?? '',
                textAlign: TextAlign.center,
                style: const TextStyle(fontFamily: 'DM Sans',
                    color: Color(0xFF6B7280), height: 1.5)),
            const SizedBox(height: 24),
            ElevatedButton(
                onPressed: _fetchContent,
                style: ElevatedButton.styleFrom(
                    backgroundColor: AppColors.primary,
                    foregroundColor: Colors.white),
                child: const Text('Retry')),
          ]),
        ));

  Widget _emptyFirstState() => Center(
        child: Padding(
          padding: const EdgeInsets.all(40),
          child: Column(mainAxisAlignment: MainAxisAlignment.center, children: [
            Container(
              width: 80, height: 80,
              decoration: BoxDecoration(
                  color: AppColors.primary.withOpacity(0.06),
                  shape: BoxShape.circle),
              child: Icon(Icons.drive_file_rename_outline_rounded,
                  size: 40, color: AppColors.primary),
            ),
            const SizedBox(height: 20),
            const Text('No content yet',
                style: TextStyle(fontFamily: 'PlayfairDisplay',
                    fontSize: 22, fontWeight: FontWeight.w800,
                    color: Color(0xFF111827))),
            const SizedBox(height: 8),
            const Text(
              'Start publishing your books, articles, and journals to reach readers across Africa.',
              textAlign: TextAlign.center,
              style: TextStyle(fontFamily: 'DM Sans',
                  color: Color(0xFF6B7280), height: 1.6, fontSize: 14),
            ),
            const SizedBox(height: 28),
            ElevatedButton.icon(
              onPressed: () =>
                  Navigator.pushNamed(context, '/publish')
                      .then((_) => _fetchContent()),
              icon: const Icon(Icons.add_rounded, size: 18),
              label: const Text('Publish Your First Work',
                  style: TextStyle(fontFamily: 'DM Sans',
                      fontWeight: FontWeight.w700)),
              style: ElevatedButton.styleFrom(
                  backgroundColor: AppColors.primary,
                  foregroundColor: Colors.white,
                  padding: const EdgeInsets.symmetric(
                      horizontal: 24, vertical: 14),
                  shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(12))),
            ),
          ]),
        ));
}

// ─────────────────────────────────────────────────────────────────────────────
// CONTENT CARD
// ─────────────────────────────────────────────────────────────────────────────
class _ContentCard extends StatelessWidget {
  final Map<String, dynamic> item;
  final VoidCallback onView;
  final VoidCallback onEdit;
  final VoidCallback onToggleStatus;
  final VoidCallback onDelete;

  const _ContentCard({
    required this.item,
    required this.onView,
    required this.onEdit,
    required this.onToggleStatus,
    required this.onDelete,
  });

  @override
  Widget build(BuildContext context) {
    final title       = item['title']        as String? ?? 'Untitled';
    final author      = item['author']       as String? ?? '—';
    final status      = item['status']       as String? ?? 'draft';
    final type        = item['content_type'] as String? ?? '—';
    final price       = (item['price'] as num?)?.toDouble() ?? 0;
    final downloads   = (item['total_downloads'] as num?)?.toInt() ?? 0;
    final reviews     = (item['total_reviews']   as num?)?.toInt() ?? 0;
    final coverUrl    = item['cover_image_url']  as String?;
    final isPublished = status == 'published';
    final isReview    = status == 'under_review';

    return GestureDetector(
      onTap: onView,
      child: Container(
        decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(16),
            boxShadow: [
              BoxShadow(color: Colors.black.withOpacity(0.04),
                  blurRadius: 8, offset: const Offset(0, 2))
            ]),
        child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
          // Cover
          ClipRRect(
            borderRadius: const BorderRadius.only(
                topLeft: Radius.circular(16),
                bottomLeft: Radius.circular(16)),
            child: SizedBox(
              width: 80, height: 110,
              child: coverUrl != null && coverUrl.isNotEmpty
                  ? CachedNetworkImage(imageUrl: coverUrl,
                      fit: BoxFit.cover,
                      errorWidget: (_, __, ___) => _coverFallback(type))
                  : _coverFallback(type),
            ),
          ),

          // Info
          Expanded(
            child: Padding(
              padding: const EdgeInsets.all(14),
              child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                // Title + status
                Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                  Expanded(
                    child: Text(title,
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                            fontFamily: 'PlayfairDisplay',
                            fontSize: 14,
                            fontWeight: FontWeight.w800,
                            color: Color(0xFF111827))),
                  ),
                  const SizedBox(width: 8),
                  _StatusBadge(status),
                ]),

                const SizedBox(height: 3),
                Text(author,
                    style: const TextStyle(
                        fontFamily: 'DM Sans',
                        fontSize: 12,
                        color: Color(0xFF9CA3AF))),

                const SizedBox(height: 8),

                // Type + price row
                Row(children: [
                  _TypeTag(type),
                  const Spacer(),
                  Text(
                    price == 0 ? 'Free' : 'KES ${price.toStringAsFixed(0)}',
                    style: TextStyle(
                        fontFamily: 'DM Sans',
                        fontSize: 13,
                        fontWeight: FontWeight.w800,
                        color: AppColors.primary),
                  ),
                ]),

                const SizedBox(height: 8),

                // Stats
                Row(children: [
                  Icon(Icons.download_rounded,
                      size: 13, color: const Color(0xFF9CA3AF)),
                  const SizedBox(width: 3),
                  Text('$downloads',
                      style: const TextStyle(fontFamily: 'DM Sans',
                          fontSize: 11, color: Color(0xFF9CA3AF))),
                  const SizedBox(width: 12),
                  Icon(Icons.star_rounded,
                      size: 13, color: const Color(0xFFF59E0B)),
                  const SizedBox(width: 3),
                  Text('$reviews',
                      style: const TextStyle(fontFamily: 'DM Sans',
                          fontSize: 11, color: Color(0xFF9CA3AF))),
                ]),

                const SizedBox(height: 10),

                // Actions
                Row(children: [
                  // Edit
                  _CardAction(
                    icon: Icons.edit_outlined,
                    label: 'Edit',
                    color: const Color(0xFF2563EB),
                    bg: const Color(0xFFEFF6FF),
                    onTap: onEdit,
                  ),
                  const SizedBox(width: 6),

                  // Publish / Unpublish (disabled when in review)
                  if (!isReview)
                    _CardAction(
                      icon: isPublished
                          ? Icons.visibility_off_outlined
                          : Icons.public_rounded,
                      label: isPublished ? 'Unpublish' : 'Publish',
                      color: isPublished
                          ? const Color(0xFF6B7280)
                          : const Color(0xFF16A34A),
                      bg: isPublished
                          ? const Color(0xFFF3F4F6)
                          : const Color(0xFFF0FDF4),
                      onTap: onToggleStatus,
                    ),
                  if (isReview)
                    _CardAction(
                      icon: Icons.hourglass_top_rounded,
                      label: 'In Review',
                      color: const Color(0xFFD97706),
                      bg: const Color(0xFFFFFBEB),
                      onTap: () {},
                    ),

                  const Spacer(),

                  // Delete
                  GestureDetector(
                    onTap: onDelete,
                    child: Container(
                      padding: const EdgeInsets.all(7),
                      decoration: BoxDecoration(
                          color: const Color(0xFFFEF2F2),
                          borderRadius: BorderRadius.circular(8)),
                      child: const Icon(Icons.delete_outline_rounded,
                          size: 15, color: Color(0xFFDC2626)),
                    ),
                  ),
                ]),
              ]),
            ),
          ),
        ]),
      ),
    );
  }

  Widget _coverFallback(String type) => Container(
        color: AppColors.primary.withOpacity(0.07),
        child: Column(mainAxisAlignment: MainAxisAlignment.center, children: [
          Icon(_typeIcon(type), size: 28, color: AppColors.primary.withOpacity(0.4)),
        ]));

  IconData _typeIcon(String type) => switch (type) {
        'article'  => Icons.article_outlined,
        'journal'  => Icons.book_outlined,
        'magazine' => Icons.menu_book_outlined,
        _          => Icons.auto_stories_rounded,
      };
}

// ─────────────────────────────────────────────────────────────────────────────
// SMALL REUSABLES
// ─────────────────────────────────────────────────────────────────────────────

class _StatPill extends StatelessWidget {
  final String count, label;
  final Color color, bg;
  const _StatPill(this.count, this.label, this.color, this.bg);
  @override
  Widget build(BuildContext context) => Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
        decoration: BoxDecoration(
            color: bg, borderRadius: BorderRadius.circular(20)),
        child: Row(mainAxisSize: MainAxisSize.min, children: [
          Text(count,
              style: TextStyle(fontFamily: 'DM Sans', fontSize: 13,
                  fontWeight: FontWeight.w800, color: color)),
          const SizedBox(width: 4),
          Text(label,
              style: TextStyle(fontFamily: 'DM Sans', fontSize: 11, color: color)),
        ]));
}

class _StatusBadge extends StatelessWidget {
  final String status;
  const _StatusBadge(this.status);
  @override
  Widget build(BuildContext context) {
    final (color, bg, label) = switch (status) {
      'published'    => (const Color(0xFF16A34A), const Color(0xFFF0FDF4), 'Live'),
      'under_review' => (const Color(0xFFD97706), const Color(0xFFFFFBEB), 'Review'),
      'discontinued' => (const Color(0xFFDC2626), const Color(0xFFFEF2F2), 'Discontinued'),
      _              => (const Color(0xFF6B7280), const Color(0xFFF3F4F6), 'Draft'),
    };
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 3),
      decoration: BoxDecoration(
          color: bg, borderRadius: BorderRadius.circular(6)),
      child: Text(label,
          style: TextStyle(fontFamily: 'DM Sans', fontSize: 9,
              fontWeight: FontWeight.w800, color: color)));
  }
}

class _TypeTag extends StatelessWidget {
  final String type;
  const _TypeTag(this.type);
  @override
  Widget build(BuildContext context) => Container(
        padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2),
        decoration: BoxDecoration(
            color: AppColors.primary.withOpacity(0.07),
            borderRadius: BorderRadius.circular(6)),
        child: Text(type.isEmpty ? 'Content' : type[0].toUpperCase() + type.substring(1),
            style: TextStyle(fontFamily: 'DM Sans', fontSize: 10,
                fontWeight: FontWeight.w600, color: AppColors.primary)));
}

class _CardAction extends StatelessWidget {
  final IconData icon;
  final String label;
  final Color color, bg;
  final VoidCallback onTap;
  const _CardAction({required this.icon, required this.label,
      required this.color, required this.bg, required this.onTap});
  @override
  Widget build(BuildContext context) => GestureDetector(
        onTap: onTap,
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 5),
          decoration: BoxDecoration(
              color: bg, borderRadius: BorderRadius.circular(8)),
          child: Row(mainAxisSize: MainAxisSize.min, children: [
            Icon(icon, size: 13, color: color),
            const SizedBox(width: 4),
            Text(label,
                style: TextStyle(fontFamily: 'DM Sans', fontSize: 11,
                    fontWeight: FontWeight.w700, color: color)),
          ]),
        ));
}

class _SortButton extends StatelessWidget {
  final String current;
  final void Function(String) onChanged;
  const _SortButton({required this.current, required this.onChanged});
  @override
  Widget build(BuildContext context) => PopupMenuButton<String>(
        icon: const Icon(Icons.sort_rounded,
            color: Color(0xFF6B7280), size: 22),
        tooltip: 'Sort by',
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
        onSelected: onChanged,
        itemBuilder: (_) => [
          _sortItem('newest', 'Newest First', Icons.arrow_downward_rounded, current),
          _sortItem('oldest', 'Oldest First', Icons.arrow_upward_rounded, current),
          _sortItem('title',  'Title A→Z',    Icons.sort_by_alpha_rounded, current),
          _sortItem('price',  'Price High→Low', Icons.attach_money_rounded, current),
        ]);

  PopupMenuItem<String> _sortItem(
      String value, String label, IconData icon, String current) =>
      PopupMenuItem(
        value: value,
        child: Row(children: [
          Icon(icon, size: 18,
              color: value == current ? AppColors.primary : const Color(0xFF6B7280)),
          const SizedBox(width: 10),
          Text(label,
              style: TextStyle(fontFamily: 'DM Sans', fontSize: 13,
                  fontWeight: value == current ? FontWeight.w700 : FontWeight.w400,
                  color: value == current ? AppColors.primary : const Color(0xFF374151))),
          if (value == current) ...[
            const Spacer(),
            Icon(Icons.check_rounded, size: 16, color: AppColors.primary),
          ],
        ]),
      );
}