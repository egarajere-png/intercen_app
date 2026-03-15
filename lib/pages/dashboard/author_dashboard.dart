// lib/pages/dashboard/author_dashboard.dart
//
// FIX: Added initialTab support via WidgetsBinding.instance.addPostFrameCallback
// in initState. When Settings navigates here with arguments: {'initialTab': n},
// the dashboard opens on the correct tab:
//   1 = Submissions  (My Submissions tile in Settings)
//   3 = My Orders    (My Orders tile in Settings)

import 'dart:convert';
import 'dart:io';

import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../services/role_service.dart';
import '../../theme/app_colors.dart';

const _kCard    = 12.0;
const _kMaxBio  = 500;
const _kMaxAvat = 5 * 1024 * 1024;

class AuthorDashboardPage extends StatefulWidget {
  const AuthorDashboardPage({Key? key}) : super(key: key);
  @override
  State<AuthorDashboardPage> createState() => _AuthorDashboardState();
}

class _AuthorDashboardState extends State<AuthorDashboardPage> {
  final _sb = Supabase.instance.client;

  // ── data ──────────────────────────────────────────────────────────────────
  Map<String, dynamic>? _profile;
  List<Map<String, dynamic>> _subs   = [];
  List<Map<String, dynamic>> _works  = [];
  List<Map<String, dynamic>> _orders = [];
  bool _loading = true;

  // ── profile-edit controllers ──────────────────────────────────────────────
  final _nameCtrl = TextEditingController();
  final _bioCtrl  = TextEditingController();
  final _telCtrl  = TextEditingController();
  final _adrCtrl  = TextEditingController();
  final _orgCtrl  = TextEditingController();
  final _dptCtrl  = TextEditingController();

  String? _avatarUrl;
  File?   _avatarFile;
  String? _avatarB64;
  bool    _saving = false;

  // ── active tab (0-4) ──────────────────────────────────────────────────────
  int _tab = 0;

  // ── derived stats ─────────────────────────────────────────────────────────
  int get _pubCount =>
      _works.where((w) => w['status'] == 'published').length;

  int get _views =>
      _works.fold(0, (s, w) => s + (w['view_count'] as int? ?? 0));

  int get _downloads =>
      _works.fold(0, (s, w) => s + (w['total_downloads'] as int? ?? 0));

  String get _rating {
    final rated = _works
        .where((w) =>
            (double.tryParse(w['average_rating']?.toString() ?? '0') ?? 0) > 0)
        .toList();
    if (rated.isEmpty) return '—';
    final sum = rated.fold<double>(
        0,
        (s, w) =>
            s + (double.tryParse(w['average_rating'].toString()) ?? 0));
    return (sum / rated.length).toStringAsFixed(1);
  }

  // ── lifecycle ─────────────────────────────────────────────────────────────
  @override
  void initState() {
    super.initState();
    _bioCtrl.addListener(() => setState(() {}));
    _loadAll();

    // ✅ FIX: Read initialTab argument from Navigator route settings.
    // ModalRoute.of(context) is null during initState so we must defer
    // to addPostFrameCallback when the widget is fully in the route tree.
    // Tab mapping:
    //   0 = Overview | 1 = Submissions | 2 = My Works
    //   3 = My Orders | 4 = Edit Profile
    WidgetsBinding.instance.addPostFrameCallback((_) {
      final args = ModalRoute.of(context)?.settings.arguments;
      if (args is Map<String, dynamic>) {
        final t = args['initialTab'];
        if (t is int && mounted) setState(() => _tab = t);
      }
    });
  }

  @override
  void dispose() {
    for (final c in [
      _nameCtrl, _bioCtrl, _telCtrl, _adrCtrl, _orgCtrl, _dptCtrl,
    ]) {
      c.dispose();
    }
    super.dispose();
  }

  // ── data load ─────────────────────────────────────────────────────────────
  Future<void> _loadAll() async {
    if (!mounted) return;
    setState(() => _loading = true);
    try {
      final uid = RoleService.instance.userId;
      final res = await Future.wait([
        _sb.from('profiles').select().eq('id', uid).maybeSingle(),
        _sb
            .from('publications')
            .select()
            .eq('submitted_by', uid)
            .order('created_at', ascending: false),
        _sb
            .from('content')
            .select(
                'id,title,status,content_type,view_count,total_downloads,'
                'average_rating,total_reviews,price,cover_image_url,created_at')
            .eq('uploaded_by', uid)
            .order('created_at', ascending: false),
        _sb
            .from('orders')
            .select(
                'id,order_number,status,payment_status,total_price,'
                'created_at,order_items(*,content(id,title))')
            .eq('user_id', uid)
            .order('created_at', ascending: false),
      ]);
      if (!mounted) return;
      final p = res[0] as Map<String, dynamic>?;
      setState(() {
        _profile        = p;
        _avatarUrl      = p?['avatar_url']    as String?;
        _nameCtrl.text  = (p?['full_name']    as String?) ?? '';
        _bioCtrl.text   = (p?['bio']          as String?) ?? '';
        _telCtrl.text   = (p?['phone']        as String?) ?? '';
        _adrCtrl.text   = (p?['address']      as String?) ?? '';
        _orgCtrl.text   = (p?['organization'] as String?) ?? '';
        _dptCtrl.text   = (p?['department']   as String?) ?? '';
        _subs   = _asList(res[1]);
        _works  = _asList(res[2]);
        _orders = _asList(res[3]);
      });
    } catch (e) {
      _toast('Load failed: $e', err: true);
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  List<Map<String, dynamic>> _asList(dynamic raw) =>
      List<Map<String, dynamic>>.from((raw as List?) ?? []);

  // ── avatar ────────────────────────────────────────────────────────────────
  Future<void> _pickAvatar() async {
    final p = await ImagePicker().pickImage(
        source: ImageSource.gallery, maxWidth: 800, imageQuality: 85);
    if (p == null) return;
    final f = File(p.path);
    final b = await f.readAsBytes();
    if (b.lengthInBytes > _kMaxAvat) {
      _toast('Image must be ≤ 5 MB', err: true);
      return;
    }
    setState(() {
      _avatarFile = f;
      _avatarB64  = base64Encode(b);
    });
  }

  ImageProvider? get _avatarImg {
    if (_avatarFile != null) return FileImage(_avatarFile!);
    if (_avatarUrl != null && _avatarUrl!.isNotEmpty)
      return CachedNetworkImageProvider(_avatarUrl!);
    return null;
  }

  // ── save profile ──────────────────────────────────────────────────────────
  Future<void> _save() async {
    setState(() => _saving = true);
    try {
      final uid = RoleService.instance.userId;
      final u = <String, dynamic>{
        if (_nameCtrl.text.trim().isNotEmpty)
          'full_name': _nameCtrl.text.trim(),
        if (_bioCtrl.text.trim().isNotEmpty)
          'bio': _bioCtrl.text.trim(),
        if (_telCtrl.text.trim().isNotEmpty)
          'phone': _telCtrl.text.trim(),
        if (_adrCtrl.text.trim().isNotEmpty)
          'address': _adrCtrl.text.trim(),
        if (_orgCtrl.text.trim().isNotEmpty)
          'organization': _orgCtrl.text.trim(),
        if (_dptCtrl.text.trim().isNotEmpty)
          'department': _dptCtrl.text.trim(),
      };
      if (_avatarB64 != null)
        u['avatar_url'] = 'https://via.placeholder.com/150';
      await _sb.from('profiles').update(u).eq('id', uid);
      await _loadAll();
      _toast('Profile saved');
    } catch (e) {
      _toast('Save failed: $e', err: true);
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  Future<void> _signOut() async {
    await _sb.auth.signOut();
    RoleService.instance.clear();
    if (mounted) Navigator.pushReplacementNamed(context, '/onboarding');
  }

  void _toast(String msg, {bool err = false}) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(
      content:
          Text(msg, style: const TextStyle(fontWeight: FontWeight.w500)),
      backgroundColor: err ? AppColors.primary : AppColors.secondary,
      behavior: SnackBarBehavior.floating,
      margin: const EdgeInsets.all(16),
      shape:
          RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
      duration: const Duration(seconds: 2),
    ));
  }

  // ─────────────────────────────────────────────────────────────────────────
  // BUILD
  // ─────────────────────────────────────────────────────────────────────────
  @override
  Widget build(BuildContext context) {
    if (_loading) return _loadingScreen();
    final w = MediaQuery.of(context).size.width;

    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: _appBar(w),
      bottomNavigationBar: _bottomNav(),
      body: ListView(
        physics: const ClampingScrollPhysics(),
        children: [
          _heroBanner(w),
          _statsGrid(w),
          _tabRow(w),
          _tabBody(w),
          const SizedBox(height: 32),
        ],
      ),
    );
  }

  // ── loading screen ────────────────────────────────────────────────────────
  Widget _loadingScreen() => Scaffold(
        backgroundColor: AppColors.background,
        body: Center(
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              SizedBox(
                width: 48, height: 48,
                child: CircularProgressIndicator(
                  color: AppColors.primary,
                  strokeWidth: 3,
                  backgroundColor: AppColors.primary.withOpacity(0.1),
                ),
              ),
              const SizedBox(height: 20),
              const Text('Loading dashboard…',
                  style: TextStyle(
                    color: AppColors.mutedForeground,
                    fontSize: 15,
                    fontWeight: FontWeight.w500,
                  )),
            ],
          ),
        ),
      );

  // ── AppBar ────────────────────────────────────────────────────────────────
  AppBar _appBar(double w) => AppBar(
        elevation: 0,
        backgroundColor: AppColors.background,
        surfaceTintColor: Colors.transparent,
        leading: Navigator.canPop(context)
            ? IconButton(
                icon: const Icon(Icons.arrow_back,
                    color: AppColors.foreground),
                onPressed: () => Navigator.pop(context),
              )
            : null,
        title: Row(children: [
          const Icon(Icons.person_outline,
              color: AppColors.primary, size: 20),
          const SizedBox(width: 8),
          Text('Author Dashboard',
              style: TextStyle(
                color: AppColors.foreground,
                fontWeight: FontWeight.w800,
                fontFamily: 'PlayfairDisplay',
                fontSize: w < 360 ? 16 : 18,
              )),
        ]),
        actions: [
          IconButton(
            icon: const Icon(Icons.add_circle_outline,
                color: AppColors.foreground),
            onPressed: () =>
                Navigator.pushNamed(context, '/publish/submit'),
          ),
          IconButton(
            icon: const Icon(Icons.logout, color: AppColors.foreground),
            onPressed: _signOut,
          ),
        ],
        bottom: PreferredSize(
          preferredSize: const Size.fromHeight(1),
          child: Container(height: 1, color: Colors.grey.shade200),
        ),
      );

  // ── hero banner ───────────────────────────────────────────────────────────
  Widget _heroBanner(double w) {
    final pad  = _hp(w);
    final wide = w >= 600;
    final initL =
        _nameCtrl.text.isNotEmpty ? _nameCtrl.text[0].toUpperCase() : 'A';

    return Container(
      decoration: BoxDecoration(
        color: AppColors.muted.withOpacity(0.6),
        border: Border(bottom: BorderSide(color: Colors.grey.shade200)),
      ),
      padding: EdgeInsets.fromLTRB(pad, 20, pad, 20),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(children: [
            GestureDetector(
              onTap: () => Navigator.pushNamedAndRemoveUntil(
                  context, '/home', (r) => false),
              child: const Text('Home',
                  style: TextStyle(
                      color: AppColors.mutedForeground, fontSize: 13)),
            ),
            const Padding(
              padding: EdgeInsets.symmetric(horizontal: 4),
              child: Icon(Icons.chevron_right,
                  size: 14, color: AppColors.mutedForeground),
            ),
            const Text('Author Portal',
                style: TextStyle(
                  color: AppColors.foreground,
                  fontSize: 13,
                  fontWeight: FontWeight.w500,
                )),
          ]),
          const SizedBox(height: 16),
          Row(
            crossAxisAlignment: CrossAxisAlignment.center,
            children: [
              GestureDetector(
                onTap: _pickAvatar,
                child: Stack(children: [
                  CircleAvatar(
                    radius: wide ? 36 : 30,
                    backgroundColor: AppColors.primary.withOpacity(0.1),
                    backgroundImage: _avatarImg,
                    child: _avatarImg == null
                        ? Text(initL,
                            style: TextStyle(
                              fontSize: wide ? 28 : 22,
                              fontWeight: FontWeight.bold,
                              color: AppColors.primary,
                              fontFamily: 'PlayfairDisplay',
                            ))
                        : null,
                  ),
                  Positioned(
                    bottom: 0, right: 0,
                    child: CircleAvatar(
                      radius: 11,
                      backgroundColor: AppColors.primary,
                      child: const Icon(Icons.camera_alt,
                          size: 13, color: Colors.white),
                    ),
                  ),
                ]),
              ),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Wrap(
                      crossAxisAlignment: WrapCrossAlignment.center,
                      spacing: 8, runSpacing: 4,
                      children: [
                        Text(
                          _nameCtrl.text.isNotEmpty
                              ? _nameCtrl.text
                              : 'Author Dashboard',
                          style: TextStyle(
                            fontFamily: 'PlayfairDisplay',
                            fontSize: wide ? 24 : 20,
                            fontWeight: FontWeight.w700,
                            color: AppColors.foreground,
                          ),
                        ),
                        Container(
                          padding: const EdgeInsets.symmetric(
                              horizontal: 10, vertical: 3),
                          decoration: BoxDecoration(
                            color: AppColors.primary.withOpacity(0.1),
                            borderRadius: BorderRadius.circular(20),
                            border: Border.all(
                                color: AppColors.primary.withOpacity(0.3)),
                          ),
                          child: Text(
                            RoleService.instance.role.toUpperCase(),
                            style: const TextStyle(
                              fontSize: 11,
                              fontWeight: FontWeight.w600,
                              color: AppColors.primary,
                            ),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 4),
                    const Text(
                      'Author Portal · Manage your works & submissions',
                      style: TextStyle(
                          color: AppColors.mutedForeground, fontSize: 13),
                    ),
                  ],
                ),
              ),
              if (wide)
                ElevatedButton.icon(
                  icon: const Icon(Icons.add, size: 16),
                  label: const Text('Submit'),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: AppColors.primary,
                    foregroundColor: Colors.white,
                    elevation: 0,
                    padding: const EdgeInsets.symmetric(
                        horizontal: 16, vertical: 10),
                    textStyle: const TextStyle(
                        fontSize: 13, fontWeight: FontWeight.w600),
                    shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(8)),
                  ),
                  onPressed: () =>
                      Navigator.pushNamed(context, '/publish/submit'),
                ),
            ],
          ),
        ],
      ),
    );
  }

  // ── stats grid ────────────────────────────────────────────────────────────
  Widget _statsGrid(double w) {
    final pad  = _hp(w);
    final cols = w >= 900 ? 4 : 2;
    final cards = [
      _SC(
        label: 'Published Works',
        value: '$_pubCount',
        icon: Icons.book_outlined,
        color: AppColors.primary,
        bg: AppColors.primaryLight,
      ),
      _SC(
        label: 'Total Views',
        value: '$_views',
        icon: Icons.visibility_outlined,
        color: const Color(0xFF16A34A),
        bg: const Color(0xFFF0FDF4),
      ),
      _SC(
        label: 'Downloads',
        value: '$_downloads',
        icon: Icons.download_outlined,
        color: const Color(0xFF7C3AED),
        bg: const Color(0xFFF5F3FF),
      ),
      _SC(
        label: 'Avg. Rating',
        value: _rating,
        icon: Icons.star_outline,
        color: const Color(0xFFD97706),
        bg: const Color(0xFFFFFBEB),
      ),
    ];
    return Padding(
      padding: EdgeInsets.fromLTRB(pad, 24, pad, 0),
      child: GridView.count(
        shrinkWrap: true,
        physics: const NeverScrollableScrollPhysics(),
        crossAxisCount: cols,
        crossAxisSpacing: 14,
        mainAxisSpacing: 14,
        childAspectRatio: w < 400 ? 1.9 : 2.2,
        children: cards,
      ),
    );
  }

  // ── tab row ───────────────────────────────────────────────────────────────
  Widget _tabRow(double w) {
    final pad = _hp(w);
    final tabs = [
      (Icons.bar_chart_outlined, 'Overview'),
      (Icons.description_outlined,
          'Submissions${_subs.isNotEmpty ? ' (${_subs.length})' : ''}'),
      (Icons.book_outlined, 'My Works'),
      (Icons.shopping_bag_outlined, 'My Orders'),
      (Icons.person_outline, 'Edit Profile'),
    ];

    return Padding(
      padding: EdgeInsets.fromLTRB(pad, 28, pad, 0),
      child: Container(
        decoration: BoxDecoration(
          color: AppColors.muted.withOpacity(0.5),
          borderRadius: BorderRadius.circular(10),
        ),
        padding: const EdgeInsets.all(4),
        child: SingleChildScrollView(
          scrollDirection: Axis.horizontal,
          child: Row(
            children: List.generate(tabs.length, (i) {
              final active = _tab == i;
              return GestureDetector(
                onTap: () => setState(() => _tab = i),
                child: AnimatedContainer(
                  duration: const Duration(milliseconds: 180),
                  margin: const EdgeInsets.only(right: 2),
                  padding: const EdgeInsets.symmetric(
                      horizontal: 14, vertical: 10),
                  decoration: BoxDecoration(
                    color: active
                        ? AppColors.primary
                        : Colors.transparent,
                    borderRadius: BorderRadius.circular(7),
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(tabs[i].$1,
                          size: 15,
                          color: active
                              ? Colors.white
                              : AppColors.mutedForeground),
                      const SizedBox(width: 6),
                      Text(tabs[i].$2,
                          style: TextStyle(
                            fontSize: 13,
                            fontWeight: active
                                ? FontWeight.w600
                                : FontWeight.normal,
                            color: active
                                ? Colors.white
                                : AppColors.mutedForeground,
                          )),
                    ],
                  ),
                ),
              );
            }),
          ),
        ),
      ),
    );
  }

  // ── tab body ──────────────────────────────────────────────────────────────
  Widget _tabBody(double w) {
    final pad = _hp(w);
    Widget body;
    switch (_tab) {
      case 0:  body = _overview(w);  break;
      case 1:  body = _subsTab();    break;
      case 2:  body = _worksTab(w);  break;
      case 3:  body = _ordersTab();  break;
      default: body = _profileTab(w);
    }
    return Padding(
      padding: EdgeInsets.fromLTRB(pad, 20, pad, 0),
      child: body,
    );
  }

  // ══════════════════════════════════════════════════════════════════════════
  // TAB 0 – OVERVIEW
  // ══════════════════════════════════════════════════════════════════════════
  Widget _overview(double w) {
    final pending  = _subs.where((s) => s['status'] == 'pending').length;
    final approved = _subs.where((s) => s['status'] == 'approved').length;
    final under    = _subs.where((s) => s['status'] == 'under_review').length;
    final rejected = _subs.where((s) => s['status'] == 'rejected').length;
    final published = _works.where((x) => x['status'] == 'published').toList();

    if (w >= 640) {
      return Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Expanded(
              child: _subStatusCard(pending, approved, under, rejected)),
          const SizedBox(width: 16),
          Expanded(child: _topWorksCard(published)),
        ],
      );
    }
    return Column(children: [
      _subStatusCard(pending, approved, under, rejected),
      const SizedBox(height: 16),
      _topWorksCard(published),
    ]);
  }

  Widget _subStatusCard(int p, int a, int u, int r) => _Card(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            _CardHdr(Icons.description_outlined, 'Submission Status',
                AppColors.primary),
            const SizedBox(height: 16),
            _Dot('Pending Review', p, const Color(0xFFFBBF24)),
            _Dot('Approved',       a, const Color(0xFF22C55E)),
            _Dot('Under Review',   u, const Color(0xFF3B82F6)),
            _Dot('Rejected',       r, const Color(0xFFEF4444)),
            const SizedBox(height: 20),
            SizedBox(
              width: double.infinity, height: 46,
              child: ElevatedButton.icon(
                icon: const Icon(Icons.add, size: 16),
                label: const Text('Submit New Manuscript'),
                style: _primaryBtn(),
                onPressed: () =>
                    Navigator.pushNamed(context, '/publish/submit'),
              ),
            ),
          ],
        ),
      );

  Widget _topWorksCard(List<Map<String, dynamic>> pub) => _Card(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            _CardHdr(Icons.trending_up, 'Top Performing Works',
                const Color(0xFF16A34A)),
            const SizedBox(height: 16),
            if (pub.isEmpty)
              _emptyInline(Icons.book_outlined, 'No published works yet.')
            else
              ...pub.take(5).map(_topWorkRow),
          ],
        ),
      );

  Widget _topWorkRow(Map<String, dynamic> w) {
    final rating =
        double.tryParse(w['average_rating']?.toString() ?? '0') ?? 0;
    return InkWell(
      onTap: () =>
          Navigator.pushNamed(context, '/book-detail', arguments: w),
      borderRadius: BorderRadius.circular(8),
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 7, horizontal: 4),
        child: Row(children: [
          ClipRRect(
            borderRadius: BorderRadius.circular(5),
            child: SizedBox(
              width: 36, height: 50,
              child: _coverImg(w['cover_image_url'] as String?),
            ),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(w['title']?.toString() ?? 'Untitled',
                    style: const TextStyle(
                        fontWeight: FontWeight.w500, fontSize: 13),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis),
                const SizedBox(height: 2),
                Text(
                    '${w['view_count'] ?? 0} views · '
                    '${w['total_downloads'] ?? 0} downloads',
                    style: const TextStyle(
                        fontSize: 11,
                        color: AppColors.mutedForeground)),
              ],
            ),
          ),
          if (rating > 0)
            Row(mainAxisSize: MainAxisSize.min, children: [
              const Icon(Icons.star_rounded,
                  size: 12, color: AppColors.primary),
              const SizedBox(width: 2),
              Text(rating.toStringAsFixed(1),
                  style: const TextStyle(
                    fontSize: 11,
                    color: AppColors.primary,
                    fontWeight: FontWeight.w600,
                  )),
            ]),
        ]),
      ),
    );
  }

  // ══════════════════════════════════════════════════════════════════════════
  // TAB 1 – SUBMISSIONS
  // ══════════════════════════════════════════════════════════════════════════
  Widget _subsTab() {
    if (_subs.isEmpty) {
      return _emptyCard(
        Icons.description_outlined,
        'No manuscripts submitted yet.',
        action: 'Submit Your First Manuscript',
        onTap: () => Navigator.pushNamed(context, '/publish/submit'),
      );
    }
    return ListView.separated(
      shrinkWrap: true,
      physics: const NeverScrollableScrollPhysics(),
      itemCount: _subs.length,
      separatorBuilder: (_, __) => const SizedBox(height: 12),
      itemBuilder: (_, i) => _subCard(_subs[i]),
    );
  }

  Widget _subCard(Map<String, dynamic> s) {
    final status = s['status'] as String? ?? '';
    return _Card(
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
                    Wrap(
                      spacing: 8, runSpacing: 4,
                      crossAxisAlignment: WrapCrossAlignment.center,
                      children: [
                        Text(s['title']?.toString() ?? 'Untitled',
                            style: const TextStyle(
                              fontFamily: 'PlayfairDisplay',
                              fontWeight: FontWeight.w700,
                              fontSize: 16,
                              color: AppColors.foreground,
                            )),
                        _Badge(status),
                      ],
                    ),
                    if ((s['description'] as String? ?? '').isNotEmpty) ...[
                      const SizedBox(height: 6),
                      Text(s['description'] as String,
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(
                            color: AppColors.mutedForeground,
                            fontSize: 13,
                            height: 1.4,
                          )),
                    ],
                    const SizedBox(height: 8),
                    Wrap(spacing: 14, runSpacing: 4, children: [
                      if (s['publishing_type'] != null)
                        _meta('${s['publishing_type']} publishing'),
                      if (s['language'] != null)
                        _meta(s['language'] as String),
                      _meta('Submitted ${_date(s['created_at'])}'),
                    ]),
                  ],
                ),
              ),
              if (status == 'approved')
                const Padding(
                  padding: EdgeInsets.only(left: 8, top: 2),
                  child: Icon(Icons.check_circle,
                      color: Color(0xFF16A34A), size: 20),
                ),
            ],
          ),
          if ((s['rejection_feedback'] as String? ?? '').isNotEmpty) ...[
            const SizedBox(height: 12),
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: AppColors.primaryLight,
                border: Border.all(
                    color: AppColors.primary.withOpacity(0.2)),
                borderRadius: BorderRadius.circular(8),
              ),
              child: RichText(
                text: TextSpan(
                  style: const TextStyle(
                      fontSize: 13,
                      color: AppColors.primary,
                      height: 1.5),
                  children: [
                    const TextSpan(
                        text: 'Feedback: ',
                        style: TextStyle(fontWeight: FontWeight.w700)),
                    TextSpan(text: s['rejection_feedback'] as String),
                  ],
                ),
              ),
            ),
          ],
        ],
      ),
    );
  }

  // ══════════════════════════════════════════════════════════════════════════
  // TAB 2 – MY WORKS
  // ══════════════════════════════════════════════════════════════════════════
  Widget _worksTab(double w) {
    if (_works.isEmpty) {
      return _emptyCard(Icons.book_outlined, 'No content uploaded yet.');
    }
    final cols = w >= 900 ? 3 : 2;
    return GridView.builder(
      shrinkWrap: true,
      physics: const NeverScrollableScrollPhysics(),
      gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
        crossAxisCount: cols,
        mainAxisSpacing: 16,
        crossAxisSpacing: 14,
        childAspectRatio: w >= 600 ? 0.68 : 0.60,
      ),
      itemCount: _works.length,
      itemBuilder: (_, i) => _workCard(_works[i]),
    );
  }

  Widget _workCard(Map<String, dynamic> w) {
    final status = w['status'] as String? ?? '';
    final rating =
        double.tryParse(w['average_rating']?.toString() ?? '0') ?? 0;
    return Card(
      elevation: 1,
      shadowColor: Colors.black.withOpacity(0.08),
      shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(_kCard)),
      clipBehavior: Clip.antiAlias,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            height: 150, width: double.infinity,
            child: _coverImg(w['cover_image_url'] as String?),
          ),
          Expanded(
            child: Padding(
              padding: const EdgeInsets.all(10),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Expanded(
                        child: Text(
                            w['title']?.toString() ?? 'Untitled',
                            style: const TextStyle(
                              fontWeight: FontWeight.w600,
                              fontSize: 13,
                              color: AppColors.foreground,
                              height: 1.3,
                            ),
                            maxLines: 2,
                            overflow: TextOverflow.ellipsis),
                      ),
                      const SizedBox(width: 4),
                      _Badge(status, small: true),
                    ],
                  ),
                  const SizedBox(height: 6),
                  Row(children: [
                    _Metric(Icons.visibility_outlined,
                        '${w['view_count'] ?? 0}'),
                    const SizedBox(width: 8),
                    _Metric(Icons.download_outlined,
                        '${w['total_downloads'] ?? 0}'),
                    if (rating > 0) ...[
                      const SizedBox(width: 8),
                      _Metric(Icons.star_outline,
                          rating.toStringAsFixed(1),
                          color: const Color(0xFFD97706)),
                    ],
                  ]),
                  const Spacer(),
                  Row(children: [
                    Expanded(
                      child: _miniBtn('View', () =>
                          Navigator.pushNamed(context, '/book-detail',
                              arguments: w)),
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: _miniBtn('Edit', () =>
                          Navigator.pushNamed(context,
                              '/content/update/${w['id']}')),
                    ),
                  ]),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  // ══════════════════════════════════════════════════════════════════════════
  // TAB 3 – MY ORDERS
  // ══════════════════════════════════════════════════════════════════════════
  Widget _ordersTab() => _Card(
        padding: EdgeInsets.zero,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Padding(
              padding: EdgeInsets.all(20),
              child: Text('Purchase History',
                  style: TextStyle(
                    fontFamily: 'PlayfairDisplay',
                    fontSize: 18,
                    fontWeight: FontWeight.w700,
                    color: AppColors.foreground,
                  )),
            ),
            Divider(height: 1, color: Colors.grey.shade200),
            if (_orders.isEmpty)
              Padding(
                padding: const EdgeInsets.symmetric(vertical: 48),
                child: Center(
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(Icons.shopping_bag_outlined,
                          size: 48,
                          color: AppColors.mutedForeground.withOpacity(0.3)),
                      const SizedBox(height: 12),
                      const Text('No orders yet.',
                          style: TextStyle(
                              color: AppColors.mutedForeground,
                              fontSize: 14)),
                      const SizedBox(height: 8),
                      TextButton(
                        onPressed: () =>
                            Navigator.pushNamed(context, '/books'),
                        child: const Text('Browse books',
                            style: TextStyle(
                              color: AppColors.primary,
                              fontWeight: FontWeight.w600,
                            )),
                      ),
                    ],
                  ),
                ),
              )
            else
              ListView.separated(
                shrinkWrap: true,
                physics: const NeverScrollableScrollPhysics(),
                itemCount: _orders.length,
                separatorBuilder: (_, __) =>
                    Divider(height: 1, color: Colors.grey.shade200),
                itemBuilder: (_, i) => _orderRow(_orders[i]),
              ),
          ],
        ),
      );

  Widget _orderRow(Map<String, dynamic> o) {
    final items  = (o['order_items'] as List<dynamic>?) ?? [];
    final isPaid = o['payment_status'] == 'paid';
    return Padding(
      padding: const EdgeInsets.all(20),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(children: [
            Text('#${o['order_number'] ?? ''}',
                style: const TextStyle(
                  fontWeight: FontWeight.w600,
                  fontFamily: 'monospace',
                  color: AppColors.foreground,
                )),
            const SizedBox(width: 10),
            Text(_date(o['created_at']),
                style: const TextStyle(
                    color: AppColors.mutedForeground, fontSize: 12)),
            const Spacer(),
            _Badge(o['payment_status'] ?? '', small: true),
            const SizedBox(width: 8),
            Text('KES ${_price(o['total_price'])}',
                style: const TextStyle(
                    fontWeight: FontWeight.w700,
                    color: AppColors.foreground)),
          ]),
          const SizedBox(height: 10),
          ...items.map<Widget>((item) {
            final c = item['content'] as Map<String, dynamic>?;
            return Padding(
              padding: const EdgeInsets.symmetric(vertical: 4),
              child: Row(children: [
                Expanded(
                  child: Text(c?['title']?.toString() ?? 'Content',
                      style: const TextStyle(
                          color: AppColors.mutedForeground,
                          fontSize: 13)),
                ),
                if (isPaid)
                  TextButton.icon(
                    onPressed: () => Navigator.pushNamed(
                        context, '/book-detail', arguments: c),
                    icon: const Icon(Icons.visibility_outlined,
                        size: 13),
                    label: const Text('Access',
                        style: TextStyle(fontSize: 12)),
                    style: TextButton.styleFrom(
                      foregroundColor: AppColors.primary,
                      padding: const EdgeInsets.symmetric(
                          horizontal: 10, vertical: 6),
                    ),
                  ),
              ]),
            );
          }),
        ],
      ),
    );
  }

  // ══════════════════════════════════════════════════════════════════════════
  // TAB 4 – EDIT PROFILE
  // ══════════════════════════════════════════════════════════════════════════
  Widget _profileTab(double w) => _Card(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text('Edit Profile',
                style: TextStyle(
                  fontFamily: 'PlayfairDisplay',
                  fontSize: 20,
                  fontWeight: FontWeight.w700,
                  color: AppColors.foreground,
                )),
            const SizedBox(height: 24),
            const Text('Profile Picture',
                style: TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.w600,
                    color: AppColors.foreground)),
            const SizedBox(height: 12),
            Row(
              crossAxisAlignment: CrossAxisAlignment.center,
              children: [
                GestureDetector(
                  onTap: _pickAvatar,
                  child: Stack(children: [
                    CircleAvatar(
                      radius: 44,
                      backgroundColor: AppColors.primary.withOpacity(0.1),
                      backgroundImage: _avatarImg,
                      child: _avatarImg == null
                          ? Text(
                              _nameCtrl.text.isNotEmpty
                                  ? _nameCtrl.text[0].toUpperCase()
                                  : 'A',
                              style: const TextStyle(
                                fontSize: 36,
                                color: AppColors.primary,
                                fontFamily: 'PlayfairDisplay',
                              ))
                          : null,
                    ),
                    Positioned(
                      bottom: 4, right: 4,
                      child: CircleAvatar(
                        radius: 14,
                        backgroundColor: AppColors.primary,
                        child: const Icon(Icons.camera_alt,
                            size: 15, color: Colors.white),
                      ),
                    ),
                  ]),
                ),
                const SizedBox(width: 20),
                Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    OutlinedButton.icon(
                      icon: const Icon(Icons.upload_file, size: 15),
                      label: const Text('Change Photo'),
                      onPressed: _pickAvatar,
                      style: OutlinedButton.styleFrom(
                        foregroundColor: AppColors.foreground,
                        side: BorderSide(color: Colors.grey.shade300),
                        shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(8)),
                      ),
                    ),
                    const SizedBox(height: 5),
                    const Text('PNG, JPG, WebP · max 5 MB',
                        style: TextStyle(
                            fontSize: 11,
                            color: AppColors.mutedForeground)),
                  ],
                ),
              ],
            ),
            const SizedBox(height: 28),
            LayoutBuilder(builder: (_, c) {
              final wide = c.maxWidth >= 500;
              return Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  if (wide)
                    _row2([
                      _field(_nameCtrl, 'Full Name'),
                      _field(_telCtrl, 'Phone',
                          hint: '+254 7xx xxx xxx'),
                    ])
                  else ...[
                    _field(_nameCtrl, 'Full Name'),
                    const SizedBox(height: 14),
                    _field(_telCtrl, 'Phone',
                        hint: '+254 7xx xxx xxx'),
                  ],
                  const SizedBox(height: 14),
                  _field(_adrCtrl, 'Address',
                      lines: 2, hint: 'P.O. Box …'),
                  const SizedBox(height: 14),
                  if (wide)
                    _row2([
                      _field(_orgCtrl, 'Organization'),
                      _field(_dptCtrl, 'Department'),
                    ])
                  else ...[
                    _field(_orgCtrl, 'Organization'),
                    const SizedBox(height: 14),
                    _field(_dptCtrl, 'Department'),
                  ],
                  const SizedBox(height: 14),
                  _lbl('Role'),
                  const SizedBox(height: 6),
                  TextField(
                    controller: TextEditingController(
                        text: RoleService.instance.role),
                    readOnly: true,
                    style: const TextStyle(
                        color: AppColors.mutedForeground, fontSize: 14),
                    decoration: InputDecoration(
                      border: _border(),
                      enabledBorder: _border(),
                      filled: true,
                      fillColor: AppColors.muted,
                      contentPadding: const EdgeInsets.symmetric(
                          horizontal: 14, vertical: 12),
                      suffixIcon: const Icon(Icons.lock_outline,
                          size: 15, color: AppColors.mutedForeground),
                      helperText: 'Role is assigned by admin.',
                      helperStyle: const TextStyle(
                          fontSize: 11,
                          color: AppColors.mutedForeground),
                    ),
                  ),
                  const SizedBox(height: 14),
                  Row(children: [
                    _lbl('Bio'),
                    const Spacer(),
                    Text('${_bioCtrl.text.length}/$_kMaxBio',
                        style: const TextStyle(
                            fontSize: 11,
                            color: AppColors.mutedForeground)),
                  ]),
                  const SizedBox(height: 6),
                  TextField(
                    controller: _bioCtrl,
                    maxLines: 5,
                    maxLength: _kMaxBio,
                    buildCounter: (_, {required currentLength,
                            required isFocused, maxLength}) =>
                        null,
                    style: const TextStyle(
                        fontSize: 14, color: AppColors.foreground),
                    decoration: InputDecoration(
                      border: _border(),
                      enabledBorder: _border(),
                      focusedBorder: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(8),
                        borderSide: const BorderSide(
                            color: AppColors.primary, width: 1.5),
                      ),
                      hintText: 'Tell readers about yourself…',
                      hintStyle: const TextStyle(
                          color: AppColors.mutedForeground,
                          fontSize: 14),
                      contentPadding: const EdgeInsets.all(14),
                      filled: true,
                      fillColor: Colors.white,
                    ),
                  ),
                ],
              );
            }),
            const SizedBox(height: 28),
            Wrap(spacing: 12, runSpacing: 12, children: [
              SizedBox(
                height: 46,
                child: ElevatedButton.icon(
                  icon: _saving
                      ? const SizedBox(
                          width: 16, height: 16,
                          child: CircularProgressIndicator(
                              strokeWidth: 2, color: Colors.white))
                      : const Icon(Icons.save_outlined, size: 16),
                  label: Text(_saving ? 'Saving…' : 'Save Changes'),
                  style: _primaryBtn(),
                  onPressed: _saving ? null : _save,
                ),
              ),
              SizedBox(
                height: 46,
                child: OutlinedButton(
                  onPressed:
                      _saving ? null : () => Navigator.maybePop(context),
                  style: OutlinedButton.styleFrom(
                    foregroundColor: AppColors.foreground,
                    side: BorderSide(color: Colors.grey.shade300),
                    padding: const EdgeInsets.symmetric(
                        horizontal: 20, vertical: 12),
                    shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(8)),
                  ),
                  child: const Text('Back'),
                ),
              ),
            ]),
          ],
        ),
      );

  // ── bottom nav ────────────────────────────────────────────────────────────
  Widget _bottomNav() => Container(
        height: 64,
        decoration: BoxDecoration(
          color: Colors.white,
          border: Border(top: BorderSide(color: Colors.grey.shade200)),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withOpacity(0.06),
              blurRadius: 12,
              offset: const Offset(0, -4),
            ),
          ],
        ),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.spaceAround,
          children: [
            _Nav(
              icon: Icons.home_outlined,
              label: 'Home',
              onTap: () => Navigator.pushNamedAndRemoveUntil(
                  context, '/home', (r) => false),
            ),
            _Nav(
              icon: Icons.menu_book_outlined,
              label: 'Books',
              onTap: () => Navigator.pushNamed(context, '/books'),
            ),
            _Nav(
              icon: Icons.shopping_cart_outlined,
              label: 'Cart',
              onTap: () => Navigator.pushNamed(context, '/cart'),
            ),
            const _Nav(
                icon: Icons.person, label: 'Profile', active: true),
          ],
        ),
      );

  // ── small helpers ─────────────────────────────────────────────────────────
  Widget _field(TextEditingController ctrl, String label,
      {int lines = 1, String? hint}) =>
      Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _lbl(label),
          const SizedBox(height: 6),
          TextField(
            controller: ctrl,
            maxLines: lines,
            style: const TextStyle(
                fontSize: 14, color: AppColors.foreground),
            decoration: InputDecoration(
              border: _border(),
              enabledBorder: _border(),
              focusedBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(8),
                borderSide: const BorderSide(
                    color: AppColors.primary, width: 1.5),
              ),
              hintText: hint,
              hintStyle: const TextStyle(
                  color: AppColors.mutedForeground, fontSize: 14),
              filled: true,
              fillColor: Colors.white,
              contentPadding: const EdgeInsets.symmetric(
                  horizontal: 14, vertical: 12),
            ),
          ),
        ],
      );

  Widget _row2(List<Widget> kids) => Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: kids
            .expand((w) =>
                [Expanded(child: w), const SizedBox(width: 14)])
            .toList()
          ..removeLast(),
      );

  Widget _lbl(String t) => Text(t,
      style: const TextStyle(
        fontSize: 13,
        fontWeight: FontWeight.w600,
        color: AppColors.foreground,
      ));

  Widget _meta(String t) => Text(t,
      style: const TextStyle(
          fontSize: 12, color: AppColors.mutedForeground));

  Widget _miniBtn(String label, VoidCallback fn) => OutlinedButton(
        onPressed: fn,
        style: OutlinedButton.styleFrom(
          foregroundColor: AppColors.foreground,
          side: BorderSide(color: Colors.grey.shade300),
          padding: const EdgeInsets.symmetric(
              horizontal: 8, vertical: 6),
          minimumSize: const Size(0, 32),
          tapTargetSize: MaterialTapTargetSize.shrinkWrap,
          shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(6)),
          textStyle: const TextStyle(
              fontSize: 12, fontWeight: FontWeight.w500),
        ),
        child: Text(label),
      );

  Widget _emptyInline(IconData icon, String msg) => Padding(
        padding: const EdgeInsets.symmetric(vertical: 32),
        child: Center(
          child: Column(mainAxisSize: MainAxisSize.min, children: [
            Icon(icon,
                size: 40,
                color: AppColors.mutedForeground.withOpacity(0.4)),
            const SizedBox(height: 10),
            Text(msg,
                style: const TextStyle(
                    color: AppColors.mutedForeground, fontSize: 14)),
          ]),
        ),
      );

  Widget _emptyCard(IconData icon, String msg,
      {String? action, VoidCallback? onTap}) =>
      _Card(
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: 48),
          child: Center(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Container(
                  width: 72, height: 72,
                  decoration: BoxDecoration(
                    color: AppColors.muted,
                    borderRadius: BorderRadius.circular(36),
                  ),
                  child: Icon(icon,
                      size: 36,
                      color: AppColors.mutedForeground.withOpacity(0.5)),
                ),
                const SizedBox(height: 16),
                Text(msg,
                    style: const TextStyle(
                        color: AppColors.mutedForeground, fontSize: 14)),
                if (action != null && onTap != null) ...[
                  const SizedBox(height: 20),
                  ElevatedButton.icon(
                    icon: const Icon(Icons.add, size: 16),
                    label: Text(action),
                    style: _primaryBtn(),
                    onPressed: onTap,
                  ),
                ],
              ],
            ),
          ),
        ),
      );

  Widget _coverImg(String? url) {
    if (url != null && url.isNotEmpty) {
      return CachedNetworkImage(
        imageUrl: url,
        fit: BoxFit.cover,
        placeholder: (_, __) => Container(
          color: AppColors.muted,
          child: const Center(
            child: SizedBox(
              width: 20, height: 20,
              child: CircularProgressIndicator(
                  strokeWidth: 2,
                  color: AppColors.mutedForeground),
            ),
          ),
        ),
        errorWidget: (_, __, ___) => _fallback(),
      );
    }
    return _fallback();
  }

  Widget _fallback() => Container(
        color: AppColors.muted,
        child: const Center(
          child: Icon(Icons.book_outlined,
              size: 36, color: AppColors.mutedForeground),
        ),
      );

  ButtonStyle _primaryBtn() => ElevatedButton.styleFrom(
        backgroundColor: AppColors.primary,
        foregroundColor: Colors.white,
        elevation: 0,
        textStyle: const TextStyle(
            fontSize: 14, fontWeight: FontWeight.w600),
        padding: const EdgeInsets.symmetric(
            horizontal: 24, vertical: 12),
        shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(8)),
      );

  OutlineInputBorder _border() => OutlineInputBorder(
        borderRadius: BorderRadius.circular(8),
        borderSide: BorderSide(color: Colors.grey.shade300),
      );

  String _date(dynamic raw) {
    if (raw == null) return '';
    try {
      final d = DateTime.parse(raw as String).toLocal();
      return '${d.day}/${d.month}/${d.year}';
    } catch (_) { return ''; }
  }

  String _price(dynamic raw) {
    final d = double.tryParse(raw?.toString() ?? '0') ?? 0;
    return d.toStringAsFixed(2).replaceAllMapped(
        RegExp(r'(\d)(?=(\d{3})+(?!\d))'), (m) => '${m[1]},');
  }

  static double _hp(double w) {
    if (w >= 900) return 32;
    if (w >= 600) return 24;
    return 16;
  }
}

// ── Stat card ──────────────────────────────────────────────────────────────
class _SC extends StatelessWidget {
  final String label, value;
  final IconData icon;
  final Color color, bg;
  const _SC({required this.label, required this.value,
      required this.icon, required this.color, required this.bg, Key? key}) : super(key: key);

  @override
  Widget build(BuildContext context) => Card(
        elevation: 1,
        shadowColor: Colors.black.withOpacity(0.08),
        color: Colors.white,
        shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(12)),
        child: Padding(
          padding: const EdgeInsets.all(14),
          child: Row(children: [
            Container(
              width: 40, height: 40,
              decoration: BoxDecoration(
                  color: bg, borderRadius: BorderRadius.circular(10)),
              child: Icon(icon, color: color, size: 20),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  FittedBox(
                    fit: BoxFit.scaleDown,
                    alignment: Alignment.centerLeft,
                    child: Text(value,
                        style: const TextStyle(
                          fontSize: 22,
                          fontWeight: FontWeight.bold,
                          color: AppColors.foreground,
                        )),
                  ),
                  Text(label,
                      style: const TextStyle(
                          fontSize: 11,
                          color: AppColors.mutedForeground),
                      overflow: TextOverflow.ellipsis),
                ],
              ),
            ),
          ]),
        ),
      );
}

// ── Status badge ───────────────────────────────────────────────────────────
class _Badge extends StatelessWidget {
  final String status;
  final bool small;
  const _Badge(this.status, {this.small = false});

  @override
  Widget build(BuildContext context) {
    Color bg, fg, bdr;
    switch (status) {
      case 'approved': case 'published': case 'paid':
        bg = const Color(0xFFF0FDF4); fg = const Color(0xFF16A34A);
        bdr = const Color(0xFFBBF7D0); break;
      case 'rejected':
        bg = const Color(0xFFFEF2F2); fg = const Color(0xFFDC2626);
        bdr = const Color(0xFFFECACA); break;
      case 'under_review':
        bg = const Color(0xFFEFF6FF); fg = const Color(0xFF2563EB);
        bdr = const Color(0xFFBFDBFE); break;
      default:
        bg = const Color(0xFFFFFBEB); fg = const Color(0xFFD97706);
        bdr = const Color(0xFFFDE68A);
    }
    return Container(
      padding: EdgeInsets.symmetric(
          horizontal: small ? 7 : 10, vertical: small ? 2 : 4),
      decoration: BoxDecoration(
        color: bg, border: Border.all(color: bdr),
        borderRadius: BorderRadius.circular(20),
      ),
      child: Text(status,
          style: TextStyle(
            fontSize: small ? 10 : 12,
            fontWeight: FontWeight.w600,
            color: fg,
          )),
    );
  }
}

// ── Card container ─────────────────────────────────────────────────────────
class _Card extends StatelessWidget {
  final Widget child;
  final EdgeInsetsGeometry? padding;
  const _Card({required this.child, this.padding});

  @override
  Widget build(BuildContext context) => Container(
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(12),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withOpacity(0.06),
              blurRadius: 8, offset: const Offset(0, 2),
            ),
          ],
        ),
        padding: padding ?? const EdgeInsets.all(20),
        child: child,
      );
}

class _CardHdr extends StatelessWidget {
  final IconData icon; final String title; final Color color;
  const _CardHdr(this.icon, this.title, this.color);
  @override
  Widget build(BuildContext context) => Row(children: [
        Icon(icon, color: color, size: 18),
        const SizedBox(width: 8),
        Text(title,
            style: const TextStyle(
              fontFamily: 'PlayfairDisplay',
              fontSize: 16, fontWeight: FontWeight.w700,
              color: AppColors.foreground,
            )),
      ]);
}

class _Dot extends StatelessWidget {
  final String label; final int count; final Color color;
  const _Dot(this.label, this.count, this.color);
  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.symmetric(vertical: 6),
        child: Row(children: [
          Container(width: 10, height: 10,
              decoration: BoxDecoration(color: color, shape: BoxShape.circle)),
          const SizedBox(width: 12),
          Expanded(child: Text(label,
              style: const TextStyle(
                  color: AppColors.mutedForeground, fontSize: 14))),
          Text('$count',
              style: const TextStyle(
                fontWeight: FontWeight.w700, fontSize: 14,
                color: AppColors.foreground,
              )),
        ]),
      );
}

class _Metric extends StatelessWidget {
  final IconData icon; final String value; final Color color;
  const _Metric(this.icon, this.value,
      {this.color = AppColors.mutedForeground});
  @override
  Widget build(BuildContext context) => Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 12, color: color),
          const SizedBox(width: 3),
          Text(value,
              style: TextStyle(
                fontSize: 11, color: color, fontWeight: FontWeight.w500)),
        ],
      );
}

class _Nav extends StatelessWidget {
  final IconData icon; final String label;
  final bool active; final VoidCallback? onTap;
  const _Nav({required this.icon, required this.label,
      this.active = false, this.onTap});
  @override
  Widget build(BuildContext context) {
    final c = active ? AppColors.primary : Colors.grey;
    return GestureDetector(
      onTap: onTap,
      child: Column(mainAxisAlignment: MainAxisAlignment.center, children: [
        Icon(icon, color: c, size: 22),
        const SizedBox(height: 3),
        Text(label,
            style: TextStyle(
              fontSize: 11, color: c,
              fontWeight: active ? FontWeight.w700 : FontWeight.normal,
            )),
      ]),
    );
  }
}