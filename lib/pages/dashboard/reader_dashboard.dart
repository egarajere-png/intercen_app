// lib/pages/dashboard/reader_dashboard.dart
//
// FIX: Added initialTab support via WidgetsBinding.instance.addPostFrameCallback
// in initState. When Settings navigates here with arguments: {'initialTab': n},
// the dashboard opens on the correct tab:
//   0 = My Profile
//   1 = My Orders   (My Orders tile in Settings)
//   2 = Browse

import 'dart:convert';
import 'dart:io';

import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../services/role_service.dart';
import '../../theme/app_colors.dart';

const _kCard   = 12.0;
const _kMaxBio = 500;
const _kMaxAvat = 5 * 1024 * 1024;

class ReaderDashboardPage extends StatefulWidget {
  // ignore: use_super_parameters
  const ReaderDashboardPage({Key? key}) : super(key: key);
  @override
  State<ReaderDashboardPage> createState() => _ReaderDashboardPageState();
}

class _ReaderDashboardPageState extends State<ReaderDashboardPage> {
  final _sb = Supabase.instance.client;

  // ── data ──────────────────────────────────────────────────────────────────
  Map<String, dynamic>? _profile;
  List<Map<String, dynamic>> _orders  = [];
  List<Map<String, dynamic>> _library = [];
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

  // ── active tab (0-2) ──────────────────────────────────────────────────────
  // 0 = My Profile | 1 = My Orders | 2 = Browse
  int _tab = 0;

  // ── derived stats ─────────────────────────────────────────────────────────
  int get _orderCount => _orders.length;

  int get _paidCount =>
      _orders.where((o) => o['payment_status'] == 'paid').length;

  double get _totalSpent => _orders
      .where((o) => o['payment_status'] == 'paid')
      .fold(0.0, (s, o) =>
          s + (double.tryParse(o['total_price']?.toString() ?? '0') ?? 0));

  int get _libraryCount => _library.length;

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
    //   0 = My Profile | 1 = My Orders | 2 = Browse
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
            .from('orders')
            .select(
                'id,order_number,status,payment_status,total_price,'
                'created_at,order_items(*,content(id,title,cover_image_url))')
            .eq('user_id', uid)
            .order('created_at', ascending: false),
        _sb
            .from('user_library')
            .select('*, content(id,title,cover_image_url,content_type,author)')
            .eq('user_id', uid)
            .order('added_at', ascending: false),
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
        _orders  = _asList(res[1]);
        _library = _asList(res[2]);
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
        if (_avatarB64 != null)
          'avatar_url': 'https://via.placeholder.com/150',
      };
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
      content: Text(msg,
          style: const TextStyle(
              fontFamily: 'DM Sans', fontWeight: FontWeight.w500)),
      backgroundColor:
          err ? AppColors.primary : const Color(0xFF16A34A),
      behavior: SnackBarBehavior.floating,
      margin: const EdgeInsets.all(16),
      shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(10)),
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
          _statsRow(w),
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
              const Text('Loading your dashboard…',
                  style: TextStyle(
                    color: AppColors.mutedForeground,
                    fontSize: 15,
                    fontWeight: FontWeight.w500,
                    fontFamily: 'DM Sans',
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
          const Icon(Icons.auto_stories_outlined,
              color: AppColors.primary, size: 20),
          const SizedBox(width: 8),
          Text('My Dashboard',
              style: TextStyle(
                color: AppColors.foreground,
                fontWeight: FontWeight.w800,
                fontFamily: 'PlayfairDisplay',
                fontSize: w < 360 ? 16 : 18,
              )),
        ]),
        actions: [
          IconButton(
            icon: const Icon(Icons.menu_book_outlined,
                color: AppColors.foreground, size: 22),
            tooltip: 'Browse Books',
            onPressed: () => Navigator.pushNamed(context, '/books'),
          ),
          IconButton(
            icon: const Icon(Icons.logout,
                color: AppColors.foreground, size: 20),
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
    final pad   = _hp(w);
    final name  = _nameCtrl.text.isNotEmpty ? _nameCtrl.text : 'Reader';
    final initL = name.isNotEmpty ? name[0].toUpperCase() : 'R';

    return Container(
      decoration: BoxDecoration(
        color: AppColors.muted.withOpacity(0.5),
        border: Border(bottom: BorderSide(color: Colors.grey.shade200)),
      ),
      padding: EdgeInsets.fromLTRB(pad, 20, pad, 20),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // breadcrumb
          Row(children: [
            GestureDetector(
              onTap: () => Navigator.pushNamedAndRemoveUntil(
                  context, '/home', (r) => false),
              child: const Text('Home',
                  style: TextStyle(
                      fontFamily: 'DM Sans',
                      color: AppColors.mutedForeground,
                      fontSize: 13)),
            ),
            const Padding(
              padding: EdgeInsets.symmetric(horizontal: 4),
              child: Icon(Icons.chevron_right,
                  size: 14, color: AppColors.mutedForeground),
            ),
            const Text('My Account',
                style: TextStyle(
                    fontFamily: 'DM Sans',
                    color: AppColors.foreground,
                    fontSize: 13,
                    fontWeight: FontWeight.w500)),
          ]),
          const SizedBox(height: 16),
          Row(
            crossAxisAlignment: CrossAxisAlignment.center,
            children: [
              // avatar
              GestureDetector(
                onTap: _pickAvatar,
                child: Stack(children: [
                  CircleAvatar(
                    radius: 30,
                    backgroundColor: AppColors.primary.withOpacity(0.1),
                    backgroundImage: _avatarImg,
                    child: _avatarImg == null
                        ? Text(initL,
                            style: const TextStyle(
                              fontSize: 22,
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
                          size: 12, color: Colors.white),
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
                        Text(name,
                            style: TextStyle(
                              fontFamily: 'PlayfairDisplay',
                              fontSize: w >= 600 ? 22 : 18,
                              fontWeight: FontWeight.w700,
                              color: AppColors.foreground,
                            )),
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
                              fontFamily: 'DM Sans',
                              fontSize: 10,
                              fontWeight: FontWeight.w700,
                              color: AppColors.primary,
                            ),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 4),
                    Text(
                        _profile?['email'] as String? ??
                            'Reader Account',
                        style: const TextStyle(
                            fontFamily: 'DM Sans',
                            color: AppColors.mutedForeground,
                            fontSize: 13),
                        overflow: TextOverflow.ellipsis),
                  ],
                ),
              ),
              if (w >= 480)
                OutlinedButton.icon(
                  icon: const Icon(Icons.shopping_bag_outlined, size: 15),
                  label: const Text('Shop',
                      style: TextStyle(fontFamily: 'DM Sans')),
                  onPressed: () =>
                      Navigator.pushNamed(context, '/books'),
                  style: OutlinedButton.styleFrom(
                    foregroundColor: AppColors.foreground,
                    side: BorderSide(color: Colors.grey.shade300),
                    padding: const EdgeInsets.symmetric(
                        horizontal: 14, vertical: 10),
                    shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(8)),
                    textStyle: const TextStyle(
                        fontFamily: 'DM Sans',
                        fontSize: 13,
                        fontWeight: FontWeight.w600),
                  ),
                ),
            ],
          ),
        ],
      ),
    );
  }

  // ── stats row ─────────────────────────────────────────────────────────────
  Widget _statsRow(double w) {
    final pad = _hp(w);
    final items = [
      _StatItem(
        label: 'Total Orders',
        value: '$_orderCount',
        icon: Icons.shopping_bag_outlined,
        color: AppColors.primary,
        bg: AppColors.primaryLight,
      ),
      _StatItem(
        label: 'Paid Orders',
        value: '$_paidCount',
        icon: Icons.check_circle_outline,
        color: const Color(0xFF16A34A),
        bg: const Color(0xFFF0FDF4),
      ),
      _StatItem(
        label: 'Total Spent (KES)',
        value: _price(_totalSpent),
        icon: Icons.account_balance_wallet_outlined,
        color: const Color(0xFF7C3AED),
        bg: const Color(0xFFF5F3FF),
      ),
      _StatItem(
        label: 'Library',
        value: '$_libraryCount',
        icon: Icons.auto_stories_outlined,
        color: const Color(0xFF0369A1),
        bg: const Color(0xFFE0F2FE),
      ),
    ];

    return Padding(
      padding: EdgeInsets.fromLTRB(pad, 20, pad, 0),
      child: GridView.count(
        shrinkWrap: true,
        physics: const NeverScrollableScrollPhysics(),
        crossAxisCount: w >= 600 ? 4 : 2,
        crossAxisSpacing: 12,
        mainAxisSpacing: 12,
        childAspectRatio: w < 400 ? 1.8 : 2.1,
        children: items.map((s) => _StatCard(s)).toList(),
      ),
    );
  }

  // ── tab row ───────────────────────────────────────────────────────────────
  Widget _tabRow(double w) {
    final pad  = _hp(w);
    final tabs = [
      (Icons.person_outline, 'My Profile'),
      (Icons.shopping_bag_outlined,
          'My Orders${_orders.isNotEmpty ? ' (${_orders.length})' : ''}'),
      (Icons.menu_book_outlined, 'Browse'),
    ];

    return Padding(
      padding: EdgeInsets.fromLTRB(pad, 24, pad, 0),
      child: Container(
        decoration: BoxDecoration(
          color: AppColors.muted.withOpacity(0.5),
          borderRadius: BorderRadius.circular(10),
        ),
        padding: const EdgeInsets.all(4),
        child: Row(
          children: List.generate(tabs.length, (i) {
            final active = _tab == i;
            return Expanded(
              child: GestureDetector(
                onTap: () => setState(() => _tab = i),
                child: AnimatedContainer(
                  duration: const Duration(milliseconds: 180),
                  padding: const EdgeInsets.symmetric(
                      horizontal: 10, vertical: 10),
                  decoration: BoxDecoration(
                    color: active
                        ? AppColors.primary
                        : Colors.transparent,
                    borderRadius: BorderRadius.circular(7),
                  ),
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(tabs[i].$1,
                          size: 15,
                          color: active
                              ? Colors.white
                              : AppColors.mutedForeground),
                      const SizedBox(width: 5),
                      Flexible(
                        child: Text(tabs[i].$2,
                            overflow: TextOverflow.ellipsis,
                            style: TextStyle(
                              fontFamily: 'DM Sans',
                              fontSize: 12,
                              fontWeight: active
                                  ? FontWeight.w700
                                  : FontWeight.normal,
                              color: active
                                  ? Colors.white
                                  : AppColors.mutedForeground,
                            )),
                      ),
                    ],
                  ),
                ),
              ),
            );
          }),
        ),
      ),
    );
  }

  // ── tab body ──────────────────────────────────────────────────────────────
  Widget _tabBody(double w) {
    final pad = _hp(w);
    Widget body;
    switch (_tab) {
      case 1:  body = _ordersTab(w); break;
      case 2:  body = _browseTab(w); break;
      default: body = _profileTab(w);
    }
    return Padding(
      padding: EdgeInsets.fromLTRB(pad, 20, pad, 0),
      child: body,
    );
  }

  // ══════════════════════════════════════════════════════════════════════════
  // TAB 0 – MY PROFILE
  // ══════════════════════════════════════════════════════════════════════════
  Widget _profileTab(double w) => _WCard(
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

            // avatar section
            const Text('Profile Picture',
                style: TextStyle(
                    fontFamily: 'DM Sans',
                    fontSize: 13,
                    fontWeight: FontWeight.w600,
                    color: AppColors.foreground)),
            const SizedBox(height: 12),
            Row(crossAxisAlignment: CrossAxisAlignment.center, children: [
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
                                : 'R',
                            style: const TextStyle(
                              fontSize: 34,
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
              Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                OutlinedButton.icon(
                  icon: const Icon(Icons.upload_file, size: 14),
                  label: const Text('Change Photo',
                      style: TextStyle(fontFamily: 'DM Sans')),
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
                        fontFamily: 'DM Sans',
                        fontSize: 11,
                        color: AppColors.mutedForeground)),
              ]),
            ]),
            const SizedBox(height: 28),

            // form fields
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
                      hint: 'P.O. Box …', lines: 2),
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
                        fontFamily: 'DM Sans',
                        color: AppColors.mutedForeground,
                        fontSize: 14),
                    decoration: InputDecoration(
                      border: _border(),
                      enabledBorder: _border(),
                      filled: true,
                      fillColor: AppColors.muted,
                      contentPadding: const EdgeInsets.symmetric(
                          horizontal: 14, vertical: 12),
                      suffixIcon: const Icon(Icons.lock_outline,
                          size: 15,
                          color: AppColors.mutedForeground),
                      helperText: 'Role is assigned by admin.',
                      helperStyle: const TextStyle(
                          fontFamily: 'DM Sans',
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
                            fontFamily: 'DM Sans',
                            fontSize: 11,
                            color: AppColors.mutedForeground)),
                  ]),
                  const SizedBox(height: 6),
                  TextField(
                    controller: _bioCtrl,
                    maxLines: 4,
                    maxLength: _kMaxBio,
                    buildCounter: (_, {required currentLength,
                            required isFocused, maxLength}) =>
                        null,
                    style: const TextStyle(
                        fontFamily: 'DM Sans',
                        fontSize: 14,
                        color: AppColors.foreground),
                    decoration: InputDecoration(
                      border: _border(),
                      enabledBorder: _border(),
                      focusedBorder: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(8),
                        borderSide: const BorderSide(
                            color: AppColors.primary, width: 1.5),
                      ),
                      hintText: 'Tell us a bit about yourself…',
                      hintStyle: const TextStyle(
                          fontFamily: 'DM Sans',
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

            // save / cancel
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
                  label: Text(_saving ? 'Saving…' : 'Save Changes',
                      style: const TextStyle(fontFamily: 'DM Sans')),
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
                    textStyle:
                        const TextStyle(fontFamily: 'DM Sans'),
                  ),
                  child: const Text('Back'),
                ),
              ),
            ]),
          ],
        ),
      );

  // ══════════════════════════════════════════════════════════════════════════
  // TAB 1 – MY ORDERS
  // ══════════════════════════════════════════════════════════════════════════
  Widget _ordersTab(double w) => _WCard(
        padding: EdgeInsets.zero,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 20, 20, 16),
              child: Row(
                children: [
                  const Text('Purchase History',
                      style: TextStyle(
                        fontFamily: 'PlayfairDisplay',
                        fontSize: 18,
                        fontWeight: FontWeight.w700,
                        color: AppColors.foreground,
                      )),
                  const Spacer(),
                  if (_orders.isNotEmpty)
                    Text('${_orders.length} orders',
                        style: const TextStyle(
                            fontFamily: 'DM Sans',
                            fontSize: 13,
                            color: AppColors.mutedForeground)),
                ],
              ),
            ),
            Divider(height: 1, color: Colors.grey.shade200),
            if (_orders.isEmpty)
              Padding(
                padding: const EdgeInsets.symmetric(vertical: 56),
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
                        child: Icon(Icons.shopping_bag_outlined,
                            size: 36,
                            color: AppColors.mutedForeground
                                .withOpacity(0.5)),
                      ),
                      const SizedBox(height: 16),
                      const Text("You haven't placed any orders yet.",
                          style: TextStyle(
                              fontFamily: 'DM Sans',
                              color: AppColors.mutedForeground,
                              fontSize: 14)),
                      const SizedBox(height: 20),
                      ElevatedButton.icon(
                        icon: const Icon(Icons.menu_book_outlined,
                            size: 16),
                        label: const Text('Browse Books',
                            style: TextStyle(fontFamily: 'DM Sans')),
                        style: _primaryBtn(),
                        onPressed: () =>
                            Navigator.pushNamed(context, '/books'),
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
    final status = o['payment_status'] as String? ?? 'pending';

    return Padding(
      padding: const EdgeInsets.all(20),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // header row
          Row(children: [
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text('#${o['order_number'] ?? ''}',
                      style: const TextStyle(
                        fontFamily: 'monospace',
                        fontWeight: FontWeight.w700,
                        fontSize: 13,
                        color: AppColors.foreground,
                      )),
                  const SizedBox(height: 2),
                  Text(_date(o['created_at']),
                      style: const TextStyle(
                          fontFamily: 'DM Sans',
                          color: AppColors.mutedForeground,
                          fontSize: 12)),
                ],
              ),
            ),
            Column(crossAxisAlignment: CrossAxisAlignment.end, children: [
              _StatusBadge(status),
              const SizedBox(height: 4),
              Text('KES ${_price(o['total_price'])}',
                  style: const TextStyle(
                      fontFamily: 'DM Sans',
                      fontWeight: FontWeight.w800,
                      fontSize: 14,
                      color: AppColors.foreground)),
            ]),
          ]),

          // items
          if (items.isNotEmpty) ...[
            const SizedBox(height: 12),
            ...items.map<Widget>((item) {
              final c = item['content'] as Map<String, dynamic>?;
              if (c == null) return const SizedBox.shrink();
              return Padding(
                padding: const EdgeInsets.only(bottom: 8),
                child: Row(children: [
                  ClipRRect(
                    borderRadius: BorderRadius.circular(6),
                    child: SizedBox(
                      width: 38, height: 52,
                      child: _coverImg(c['cover_image_url'] as String?),
                    ),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Text(c['title']?.toString() ?? 'Content',
                        style: const TextStyle(
                            fontFamily: 'DM Sans',
                            fontSize: 13,
                            fontWeight: FontWeight.w500,
                            color: AppColors.foreground),
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis),
                  ),
                  if (isPaid)
                    TextButton.icon(
                      onPressed: () => Navigator.pushNamed(
                          context, '/book-detail', arguments: c),
                      icon: const Icon(Icons.auto_stories_outlined,
                          size: 13),
                      label: const Text('Read',
                          style: TextStyle(
                              fontFamily: 'DM Sans', fontSize: 12)),
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

          // retry button for unpaid
          if (!isPaid) ...[
            const SizedBox(height: 10),
            SizedBox(
              width: double.infinity,
              child: OutlinedButton.icon(
                onPressed: () => Navigator.pushNamed(
                    context, '/checkout/payment',
                    arguments: {'order_id': o['id']}),
                icon: const Icon(Icons.payment_outlined, size: 14),
                label: const Text('Complete Payment',
                    style: TextStyle(
                        fontFamily: 'DM Sans', fontSize: 13)),
                style: OutlinedButton.styleFrom(
                  foregroundColor: AppColors.primary,
                  side: BorderSide(
                      color: AppColors.primary.withOpacity(0.4)),
                  padding: const EdgeInsets.symmetric(
                      horizontal: 14, vertical: 10),
                  shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(8)),
                ),
              ),
            ),
          ],
        ],
      ),
    );
  }

  // ══════════════════════════════════════════════════════════════════════════
  // TAB 2 – BROWSE
  // ══════════════════════════════════════════════════════════════════════════
  Widget _browseTab(double w) {
    if (_library.isEmpty) {
      return _WCard(
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: 48),
          child: Center(
            child: Column(mainAxisSize: MainAxisSize.min, children: [
              Container(
                width: 72, height: 72,
                decoration: BoxDecoration(
                    color: AppColors.muted,
                    borderRadius: BorderRadius.circular(36)),
                child: Icon(Icons.auto_stories_outlined,
                    size: 36,
                    color: AppColors.mutedForeground.withOpacity(0.5)),
              ),
              const SizedBox(height: 16),
              const Text('Your library is empty.',
                  style: TextStyle(
                      fontFamily: 'DM Sans',
                      color: AppColors.mutedForeground,
                      fontSize: 14)),
              const SizedBox(height: 8),
              const Text(
                  'Books you purchase or save will appear here.',
                  textAlign: TextAlign.center,
                  style: TextStyle(
                      fontFamily: 'DM Sans',
                      color: AppColors.mutedForeground,
                      fontSize: 12)),
              const SizedBox(height: 20),
              ElevatedButton.icon(
                icon: const Icon(Icons.menu_book_outlined, size: 16),
                label: const Text('Browse Books',
                    style: TextStyle(fontFamily: 'DM Sans')),
                style: _primaryBtn(),
                onPressed: () =>
                    Navigator.pushNamed(context, '/books'),
              ),
            ]),
          ),
        ),
      );
    }

    final cols = w >= 900
        ? 4
        : w >= 600
            ? 3
            : 2;

    return GridView.builder(
      shrinkWrap: true,
      physics: const NeverScrollableScrollPhysics(),
      gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
        crossAxisCount: cols,
        mainAxisSpacing: 16,
        crossAxisSpacing: 14,
        childAspectRatio: 0.65,
      ),
      itemCount: _library.length,
      itemBuilder: (_, i) => _libraryCard(_library[i]),
    );
  }

  Widget _libraryCard(Map<String, dynamic> item) {
    final c = item['content'] as Map<String, dynamic>? ?? {};
    return Card(
      elevation: 1,
      shadowColor: Colors.black.withOpacity(0.08),
      shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(_kCard)),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: () =>
            Navigator.pushNamed(context, '/book-detail', arguments: c),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            SizedBox(
              height: 150, width: double.infinity,
              child: _coverImg(c['cover_image_url'] as String?),
            ),
            Expanded(
              child: Padding(
                padding: const EdgeInsets.all(10),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(c['title']?.toString() ?? 'Untitled',
                        style: const TextStyle(
                          fontFamily: 'DM Sans',
                          fontWeight: FontWeight.w600,
                          fontSize: 13,
                          color: AppColors.foreground,
                          height: 1.3,
                        ),
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis),
                    if ((c['author'] as String? ?? '').isNotEmpty) ...[
                      const SizedBox(height: 3),
                      Text('by ${c['author']}',
                          style: const TextStyle(
                              fontFamily: 'DM Sans',
                              fontSize: 11,
                              color: AppColors.mutedForeground),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis),
                    ],
                    const Spacer(),
                    SizedBox(
                      width: double.infinity,
                      child: ElevatedButton(
                        onPressed: () => Navigator.pushNamed(
                            context, '/book-detail', arguments: c),
                        style: ElevatedButton.styleFrom(
                          backgroundColor: AppColors.primary,
                          foregroundColor: Colors.white,
                          elevation: 0,
                          padding: const EdgeInsets.symmetric(
                              vertical: 8),
                          minimumSize: const Size(0, 32),
                          tapTargetSize:
                              MaterialTapTargetSize.shrinkWrap,
                          shape: RoundedRectangleBorder(
                              borderRadius:
                                  BorderRadius.circular(6)),
                          textStyle: const TextStyle(
                              fontFamily: 'DM Sans',
                              fontSize: 12,
                              fontWeight: FontWeight.w600),
                        ),
                        child: const Text('Read'),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

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
            _NavItem(
              icon: Icons.home_outlined,
              label: 'Home',
              onTap: () => Navigator.pushNamedAndRemoveUntil(
                  context, '/home', (r) => false),
            ),
            _NavItem(
              icon: Icons.menu_book_outlined,
              label: 'Books',
              onTap: () =>
                  Navigator.pushNamed(context, '/books'),
            ),
            _NavItem(
              icon: Icons.shopping_cart_outlined,
              label: 'Cart',
              onTap: () =>
                  Navigator.pushNamed(context, '/cart'),
            ),
            const _NavItem(
                icon: Icons.person,
                label: 'Profile',
                active: true),
          ],
        ),
      );

  // ── helpers ───────────────────────────────────────────────────────────────
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
                fontFamily: 'DM Sans',
                fontSize: 14,
                color: AppColors.foreground),
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
                  fontFamily: 'DM Sans',
                  color: AppColors.mutedForeground,
                  fontSize: 14),
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
        fontFamily: 'DM Sans',
        fontSize: 13,
        fontWeight: FontWeight.w600,
        color: AppColors.foreground,
      ));

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
              size: 32, color: AppColors.mutedForeground),
        ),
      );

  ButtonStyle _primaryBtn() => ElevatedButton.styleFrom(
        backgroundColor: AppColors.primary,
        foregroundColor: Colors.white,
        elevation: 0,
        textStyle: const TextStyle(
            fontFamily: 'DM Sans',
            fontSize: 14,
            fontWeight: FontWeight.w600),
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
    } catch (_) {
      return '';
    }
  }

  String _price(dynamic raw) {
    final d = raw is double ? raw : double.tryParse(raw?.toString() ?? '0') ?? 0;
    return d.toStringAsFixed(0).replaceAllMapped(
        RegExp(r'(\d)(?=(\d{3})+(?!\d))'), (m) => '${m[1]},');
  }

  static double _hp(double w) {
    if (w >= 900) return 32;
    if (w >= 600) return 24;
    return 16;
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// SHARED WIDGETS
// ─────────────────────────────────────────────────────────────────────────────

class _StatItem {
  final String label, value;
  final IconData icon;
  final Color color, bg;
  const _StatItem({
    required this.label, required this.value,
    required this.icon,  required this.color, required this.bg,
  });
}

class _StatCard extends StatelessWidget {
  final _StatItem d;
  // ignore: use_super_parameters
  const _StatCard(this.d, {Key? key}) : super(key: key);

  @override
  Widget build(BuildContext context) => Container(
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(_kCard),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withOpacity(0.05),
              blurRadius: 6, offset: const Offset(0, 2),
            ),
          ],
        ),
        child: Row(children: [
          Container(
            width: 38, height: 38,
            decoration: BoxDecoration(
                color: d.bg, borderRadius: BorderRadius.circular(9)),
            child: Icon(d.icon, color: d.color, size: 19),
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
                        fontSize: 20,
                        fontWeight: FontWeight.w800,
                        color: AppColors.foreground,
                      )),
                ),
                Text(d.label,
                    style: const TextStyle(
                        fontFamily: 'DM Sans',
                        fontSize: 10,
                        color: AppColors.mutedForeground),
                    overflow: TextOverflow.ellipsis),
              ],
            ),
          ),
        ]),
      );
}

class _StatusBadge extends StatelessWidget {
  final String status;
  // ignore: use_super_parameters
  const _StatusBadge(this.status, {Key? key}) : super(key: key);

  Color get _bg => switch (status) {
        'paid' || 'completed'        => const Color(0xFFF0FDF4),
        'pending'                    => const Color(0xFFFFFBEB),
        'cancelled' || 'failed'      => const Color(0xFFFEF2F2),
        _                            => const Color(0xFFF3F4F6),
      };

  Color get _fg => switch (status) {
        'paid' || 'completed'        => const Color(0xFF16A34A),
        'pending'                    => const Color(0xFFD97706),
        'cancelled' || 'failed'      => const Color(0xFFDC2626),
        _                            => const Color(0xFF6B7280),
      };

  @override
  Widget build(BuildContext context) => Container(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
        decoration: BoxDecoration(
          color: _bg,
          borderRadius: BorderRadius.circular(20),
          border: Border.all(color: _fg.withOpacity(0.3)),
        ),
        child: Text(status,
            style: TextStyle(
              fontFamily: 'DM Sans',
              fontSize: 11,
              fontWeight: FontWeight.w700,
              color: _fg,
            )),
      );
}

class _WCard extends StatelessWidget {
  final Widget child;
  final EdgeInsetsGeometry? padding;
  // ignore: use_super_parameters
  const _WCard({required this.child, this.padding, Key? key}) : super(key: key);

  @override
  Widget build(BuildContext context) => Container(
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(_kCard),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withOpacity(0.05),
              blurRadius: 8, offset: const Offset(0, 2),
            ),
          ],
        ),
        padding: padding ?? const EdgeInsets.all(20),
        child: child,
      );
}

class _NavItem extends StatelessWidget {
  final IconData icon;
  final String label;
  final bool active;
  final VoidCallback? onTap;
  // ignore: use_super_parameters
  const _NavItem(
      {required this.icon, required this.label,
       this.active = false, this.onTap, Key? key}) : super(key: key);

  @override
  Widget build(BuildContext context) {
    final c = active ? AppColors.primary : Colors.grey;
    return GestureDetector(
      onTap: onTap,
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(icon, color: c, size: 22),
          const SizedBox(height: 3),
          Text(label,
              style: TextStyle(
                fontFamily: 'DM Sans',
                fontSize: 11,
                color: c,
                fontWeight:
                    active ? FontWeight.w700 : FontWeight.normal,
              )),
        ],
      ),
    );
  }
}