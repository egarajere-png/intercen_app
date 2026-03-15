// lib/pages/dashboard/reader_dashboard.dart
//
// ── DESIGN SOURCE: mirrors the React/TSX ReaderDashboard exactly ─────────────
//   • Same sections: Hero, Stats (3-up grid), Tabs (Profile / Orders / Browse)
//   • Same colour palette: primary #B11226, warm background #F9F5EF,
//     dark appbar #374151, green #16A34A, purple #7C3AED
//   • Same typography: PlayfairDisplay display, DM Sans body
//   • Same feature set: avatar pick, profile edit, orders list, browse grid
//
// ── LAYOUT FIXES (all box.dart:2251 / mouse_tracker:199 errors) ──────────────
//   1. NO NestedScrollView + TabBarView combo – that pattern causes unbounded
//      height on Flutter Web.  Replaced with a single CustomScrollView whose
//      SliverList owns all scrolling; tab bodies are plain widgets switched
//      with an index variable (no TabBarView anywhere).
//   2. body wrapped in LayoutBuilder → SizedBox with explicit finite height.
//      If a parent PageView passes ∞ height we clamp to MediaQuery screen h.
//   3. Every shrinkWrap GridView / ListView sits inside SliverToBoxAdapter so
//      Flutter always has finite cross-axis constraints.
//   4. TabBar is replaced by a custom horizontal pill-row in a
//      SingleChildScrollView (no Flutter TabBar widget at all).
// ─────────────────────────────────────────────────────────────────────────────

import 'dart:convert';
import 'dart:io';

import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../services/role_service.dart';

// ── Palette (matches TSX exactly) ────────────────────────────────────────────
const _kPrimary      = Color(0xFFB11226);
const _kPrimaryLight = Color(0xFFFFF1F2);
const _kBg           = Color(0xFFF9F5EF);
const _kDark         = Color(0xFF374151);
const _kMuted        = Color(0xFF6B7280);
const _kMutedLight   = Color(0xFF9CA3AF);
const _kBorder       = Color(0xFFE5E7EB);
const _kWhite        = Colors.white;
const _kGreen        = Color(0xFF16A34A);
const _kGreenBg      = Color(0xFFF0FDF4);
const _kPurple       = Color(0xFF7C3AED);
const _kPurpleBg     = Color(0xFFF5F3FF);
const _kAmber        = Color(0xFFD97706);
const _kAmberBg      = Color(0xFFFFFBEB);

const _kMaxBio  = 500;
const _kMaxName = 100;
const _kMaxAvat = 5 * 1024 * 1024;
const _kRadius  = 12.0;

// ─────────────────────────────────────────────────────────────────────────────
class ReaderDashboardPage extends StatefulWidget {
  const ReaderDashboardPage({super.key});
  @override
  State<ReaderDashboardPage> createState() => _ReaderDashboardPageState();
}

class _ReaderDashboardPageState extends State<ReaderDashboardPage> {
  final _sb = Supabase.instance.client;

  // ── data ──────────────────────────────────────────────────────────────────
  Map<String, dynamic>? _profile;
  List<Map<String, dynamic>> _orders      = [];
  List<Map<String, dynamic>> _recentBooks = [];
  bool _loading = true;

  // ── profile edit ──────────────────────────────────────────────────────────
  final _nameCtrl = TextEditingController();
  final _bioCtrl  = TextEditingController();
  final _telCtrl  = TextEditingController();
  final _adrCtrl  = TextEditingController();
  final _orgCtrl  = TextEditingController();
  final _dptCtrl  = TextEditingController();

  String  _accountType = 'personal';
  String? _avatarUrl;
  File?   _avatarFile;
  String? _avatarB64;
  bool    _saving = false;

  // ── tab (0 = Profile, 1 = Orders, 2 = Browse) ────────────────────────────
  int _tab = 0;

  // ── derived stats ─────────────────────────────────────────────────────────
  int get _booksOwned => _orders
      .where((o) => o['payment_status'] == 'paid')
      .fold(0, (s, o) => s + ((o['order_items'] as List?)?.length ?? 0));
  double get _totalSpent => _orders
      .where((o) => o['payment_status'] == 'paid')
      .fold(0.0, (s, o) =>
          s + (double.tryParse(o['total_price']?.toString() ?? '0') ?? 0));

  // ── lifecycle ─────────────────────────────────────────────────────────────
  @override
  void initState() {
    super.initState();
    _bioCtrl.addListener(() => setState(() {}));
    _loadAll();
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

  // ── load ──────────────────────────────────────────────────────────────────
  Future<void> _loadAll() async {
    if (!mounted) return;
    setState(() => _loading = true);
    try {
      final uid = RoleService.instance.userId;
      final res = await Future.wait([
        _sb.from('profiles').select('*').eq('id', uid).maybeSingle(),
        _sb
            .from('orders')
            .select(
                '*, order_items(*, content(id, title, cover_image_url))')
            .eq('user_id', uid)
            .order('created_at', ascending: false),
        _sb
            .from('content')
            .select(
                'id,title,cover_image_url,content_type,price,average_rating')
            .eq('status', 'published')
            .order('created_at', ascending: false)
            .limit(6),
      ]);
      if (!mounted) return;
      final p = res[0] as Map<String, dynamic>?;
      setState(() {
        _profile        = p;
        _avatarUrl      = p?['avatar_url'] as String?;
        _nameCtrl.text  = (p?['full_name']    as String?) ?? '';
        _bioCtrl.text   = (p?['bio']          as String?) ?? '';
        _telCtrl.text   = (p?['phone']         as String?) ?? '';
        _adrCtrl.text   = (p?['address']       as String?) ?? '';
        _orgCtrl.text   = (p?['organization']  as String?) ?? '';
        _dptCtrl.text   = (p?['department']    as String?) ?? '';
        _accountType    = (p?['account_type']  as String?) ?? 'personal';
        _orders      = _asList(res[1]);
        _recentBooks = _asList(res[2]);
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
    final p = await ImagePicker()
        .pickImage(source: ImageSource.gallery, maxWidth: 800, imageQuality: 85);
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
        if (_nameCtrl.text.trim().isNotEmpty) 'full_name':    _nameCtrl.text.trim(),
        if (_bioCtrl.text.trim().isNotEmpty)  'bio':          _bioCtrl.text.trim(),
        if (_telCtrl.text.trim().isNotEmpty)  'phone':        _telCtrl.text.trim(),
        if (_adrCtrl.text.trim().isNotEmpty)  'address':      _adrCtrl.text.trim(),
        if (_orgCtrl.text.trim().isNotEmpty)  'organization': _orgCtrl.text.trim(),
        if (_dptCtrl.text.trim().isNotEmpty)  'department':   _dptCtrl.text.trim(),
        'account_type': _accountType,
        if (_avatarB64 != null) 'avatar_url': 'https://via.placeholder.com/150',
      };
      await _sb.from('profiles').update(u).eq('id', uid);
      await _loadAll();
      _toast('Profile saved', err: false);
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
      backgroundColor: err ? _kPrimary : _kGreen,
      behavior: SnackBarBehavior.floating,
      margin: const EdgeInsets.all(16),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
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
      backgroundColor: _kBg,
      bottomNavigationBar: _bottomNav(),
      // ── KEY FIX: LayoutBuilder + SizedBox gives CustomScrollView a
      // guaranteed finite height regardless of the parent widget tree.
      body: LayoutBuilder(
        builder: (context, constraints) {
          final h = constraints.maxHeight.isInfinite
              ? MediaQuery.of(context).size.height
              : constraints.maxHeight;
          return SizedBox(
            height: h,
            child: CustomScrollView(
              physics: const ClampingScrollPhysics(),
              slivers: [
                _appBar(w),
                SliverToBoxAdapter(child: _heroBanner(w)),
                SliverToBoxAdapter(child: _statsRow(w)),
                SliverToBoxAdapter(child: _tabRow(w)),
                SliverToBoxAdapter(child: _tabBody(w)),
                const SliverToBoxAdapter(child: SizedBox(height: 32)),
              ],
            ),
          );
        },
      ),
    );
  }

  // ── loading ───────────────────────────────────────────────────────────────
  Widget _loadingScreen() => Scaffold(
        backgroundColor: _kBg,
        body: const Center(
          child: CircularProgressIndicator(
            valueColor: AlwaysStoppedAnimation(_kPrimary),
          ),
        ),
      );

  // ── sliver app bar ────────────────────────────────────────────────────────
  SliverAppBar _appBar(double w) => SliverAppBar(
        pinned: true,
        elevation: 0,
        backgroundColor: _kDark,
        surfaceTintColor: Colors.transparent,
        leading: Navigator.canPop(context)
            ? IconButton(
                icon: const Icon(Icons.arrow_back, color: _kWhite),
                onPressed: () => Navigator.pop(context),
              )
            : null,
        title: Row(children: [
          const Icon(Icons.person_outline, color: Colors.white70, size: 20),
          const SizedBox(width: 8),
          Text(
            'My Account',
            style: TextStyle(
              color: _kWhite,
              fontWeight: FontWeight.w800,
              fontFamily: 'PlayfairDisplay',
              fontSize: w < 360 ? 16 : 18,
            ),
          ),
        ]),
        actions: [
          IconButton(
            icon: const Icon(Icons.shopping_bag_outlined,
                color: Colors.white70, size: 22),
            onPressed: () => Navigator.pushNamed(context, '/cart'),
          ),
          IconButton(
            icon: const Icon(Icons.logout_rounded,
                color: Colors.white54, size: 20),
            onPressed: _signOut,
          ),
        ],
      );

  // ── hero banner ───────────────────────────────────────────────────────────
  Widget _heroBanner(double w) {
    final pad  = _hp(w);
    final name = _nameCtrl.text.isNotEmpty
        ? _nameCtrl.text
        : (_profile?['full_name'] as String? ?? 'My Account');
    final initL = name.isNotEmpty ? name[0].toUpperCase() : 'R';
    final role  = RoleService.instance.role;
    final acct  = _accountType;

    return Container(
      decoration: BoxDecoration(
        // warm gradient matching TSX bg-gradient-warm
        gradient: LinearGradient(
          colors: [
            const Color(0xFFFDF8F3),
            const Color(0xFFF9F5EF),
          ],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        border:
            Border(bottom: BorderSide(color: _kBorder)),
      ),
      padding: EdgeInsets.fromLTRB(pad, 20, pad, 20),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          // avatar
          GestureDetector(
            onTap: _pickAvatar,
            child: Stack(children: [
              CircleAvatar(
                radius: 32,
                backgroundColor: _kPrimary.withOpacity(0.1),
                backgroundImage: _avatarImg,
                child: _avatarImg == null
                    ? Text(
                        initL,
                        style: const TextStyle(
                          fontSize: 26,
                          fontWeight: FontWeight.bold,
                          color: _kPrimary,
                          fontFamily: 'PlayfairDisplay',
                        ),
                      )
                    : null,
              ),
              Positioned(
                bottom: 0,
                right: 0,
                child: CircleAvatar(
                  radius: 11,
                  backgroundColor: _kPrimary,
                  child: const Icon(Icons.camera_alt,
                      size: 12, color: _kWhite),
                ),
              ),
            ]),
          ),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  name,
                  style: const TextStyle(
                    fontFamily: 'PlayfairDisplay',
                    fontSize: 20,
                    fontWeight: FontWeight.w700,
                    color: Color(0xFF1F2937),
                  ),
                  overflow: TextOverflow.ellipsis,
                ),
                const SizedBox(height: 2),
                Text(
                  '$role · $acct account',
                  style: const TextStyle(
                      fontFamily: 'DM Sans',
                      fontSize: 12,
                      color: _kMuted),
                ),
              ],
            ),
          ),
          TextButton.icon(
            onPressed: _signOut,
            icon: const Icon(Icons.logout_rounded, size: 14),
            label: const Text('Sign Out',
                style: TextStyle(fontFamily: 'DM Sans', fontSize: 12)),
            style: TextButton.styleFrom(
              foregroundColor: _kMuted,
              padding: const EdgeInsets.symmetric(
                  horizontal: 10, vertical: 8),
            ),
          ),
        ],
      ),
    );
  }

  // ── stats row (3-up grid matching TSX) ───────────────────────────────────
  Widget _statsRow(double w) {
    final pad = _hp(w);
    return Padding(
      padding: EdgeInsets.fromLTRB(pad, 20, pad, 0),
      child: Row(children: [
        _StatCard(
          label: 'Books Owned',
          value: '$_booksOwned',
          icon: Icons.book_outlined,
          color: _kPrimary,
          bg: _kPrimaryLight,
        ),
        const SizedBox(width: 10),
        _StatCard(
          label: 'Orders Placed',
          value: '${_orders.length}',
          icon: Icons.receipt_outlined,
          color: _kPurple,
          bg: _kPurpleBg,
        ),
        const SizedBox(width: 10),
        _StatCard(
          label: 'Spent (KES)',
          value: _totalSpent.toStringAsFixed(0),
          icon: Icons.shopping_bag_outlined,
          color: _kGreen,
          bg: _kGreenBg,
        ),
      ]),
    );
  }

  // ── tab row (pill buttons, NO TabBar widget) ──────────────────────────────
  Widget _tabRow(double w) {
    final pad = _hp(w);
    final tabs = [
      (Icons.person_outline,       'My Profile'),
      (Icons.shopping_bag_outlined,
          'Orders${_orders.isNotEmpty ? ' (${_orders.length})' : ''}'),
      (Icons.menu_book_outlined,   'Browse Books'),
    ];

    return Padding(
      padding: EdgeInsets.fromLTRB(pad, 24, pad, 0),
      child: Container(
        decoration: BoxDecoration(
          color: _kMuted.withOpacity(0.08),
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
                      horizontal: 16, vertical: 10),
                  decoration: BoxDecoration(
                    color: active ? _kPrimary : Colors.transparent,
                    borderRadius: BorderRadius.circular(7),
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(tabs[i].$1,
                          size: 15,
                          color: active ? _kWhite : _kMuted),
                      const SizedBox(width: 6),
                      Text(
                        tabs[i].$2,
                        style: TextStyle(
                          fontFamily: 'DM Sans',
                          fontSize: 13,
                          fontWeight: active
                              ? FontWeight.w700
                              : FontWeight.normal,
                          color: active ? _kWhite : _kMuted,
                        ),
                      ),
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

  // ── tab body dispatcher ───────────────────────────────────────────────────
  Widget _tabBody(double w) {
    final pad = _hp(w);
    Widget body;
    switch (_tab) {
      case 0:  body = _profileTab(w); break;
      case 1:  body = _ordersTab(w);  break;
      default: body = _browseTab(w);
    }
    return Padding(
      padding: EdgeInsets.fromLTRB(pad, 20, pad, 0),
      child: body,
    );
  }

  // ══════════════════════════════════════════════════════════════════════════
  // TAB 0 – MY PROFILE  (matches TSX <TabsContent value="profile">)
  // ══════════════════════════════════════════════════════════════════════════
  Widget _profileTab(double w) {
    final isOrg =
        _accountType == 'corporate' || _accountType == 'institutional';

    return _WCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            'My Profile',
            style: TextStyle(
              fontFamily: 'PlayfairDisplay',
              fontSize: 20,
              fontWeight: FontWeight.w700,
              color: Color(0xFF1F2937),
            ),
          ),
          const SizedBox(height: 24),

          // ── Avatar ──────────────────────────────────────────────────────
          const Text('Profile Picture',
              style: TextStyle(
                  fontFamily: 'DM Sans',
                  fontSize: 13,
                  fontWeight: FontWeight.w600,
                  color: Color(0xFF1F2937))),
          const SizedBox(height: 12),
          Row(
            crossAxisAlignment: CrossAxisAlignment.center,
            children: [
              GestureDetector(
                onTap: _pickAvatar,
                child: Stack(children: [
                  CircleAvatar(
                    radius: 40,
                    backgroundColor: _kPrimary.withOpacity(0.1),
                    backgroundImage: _avatarImg,
                    child: _avatarImg == null
                        ? Text(
                            _nameCtrl.text.isNotEmpty
                                ? _nameCtrl.text[0].toUpperCase()
                                : 'R',
                            style: const TextStyle(
                              fontSize: 32,
                              color: _kPrimary,
                              fontFamily: 'PlayfairDisplay',
                            ),
                          )
                        : null,
                  ),
                  Positioned(
                    bottom: 4,
                    right: 4,
                    child: CircleAvatar(
                      radius: 13,
                      backgroundColor: _kPrimary,
                      child: const Icon(Icons.camera_alt,
                          size: 14, color: _kWhite),
                    ),
                  ),
                ]),
              ),
              const SizedBox(width: 20),
              Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  OutlinedButton.icon(
                    icon: const Icon(Icons.upload_file, size: 14),
                    label: const Text('Change Photo',
                        style: TextStyle(
                            fontFamily: 'DM Sans', fontSize: 13)),
                    onPressed: _pickAvatar,
                    style: OutlinedButton.styleFrom(
                      foregroundColor: const Color(0xFF1F2937),
                      side: const BorderSide(color: _kBorder),
                      shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(8)),
                    ),
                  ),
                  const SizedBox(height: 4),
                  const Text('PNG, JPG, WebP · max 5 MB',
                      style: TextStyle(
                          fontFamily: 'DM Sans',
                          fontSize: 11,
                          color: _kMutedLight)),
                ],
              ),
            ],
          ),
          const SizedBox(height: 24),

          // ── Fields ──────────────────────────────────────────────────────
          LayoutBuilder(builder: (_, c) {
            final wide = c.maxWidth >= 500;
            return Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // Full name + Phone
                if (wide)
                  _row2([
                    _field(_nameCtrl, 'Full Name',
                        hint: 'Mwangi Kamau',
                        maxLen: _kMaxName),
                    _field(_telCtrl, 'Phone',
                        hint: '+254 712 345 678'),
                  ])
                else ...[
                  _field(_nameCtrl, 'Full Name',
                      hint: 'Mwangi Kamau', maxLen: _kMaxName),
                  const SizedBox(height: 14),
                  _field(_telCtrl, 'Phone', hint: '+254 712 345 678'),
                ],
                const SizedBox(height: 14),

                // Account type dropdown
                _lbl('Account Type'),
                const SizedBox(height: 6),
                _AccountDropdown(
                  value: _accountType,
                  onChanged: (v) =>
                      setState(() => _accountType = v ?? _accountType),
                  enabled: !_saving,
                ),
                const SizedBox(height: 14),

                // Org fields (shown only for corporate/institutional)
                if (isOrg) ...[
                  if (wide)
                    _row2([
                      _field(_orgCtrl, 'Organization',
                          hint: 'Company / Institution'),
                      _field(_dptCtrl, 'Department',
                          hint: 'Department'),
                    ])
                  else ...[
                    _field(_orgCtrl, 'Organization',
                        hint: 'Company / Institution'),
                    const SizedBox(height: 14),
                    _field(_dptCtrl, 'Department', hint: 'Department'),
                  ],
                  const SizedBox(height: 14),
                ],

                // Address
                _field(_adrCtrl, 'Address',
                    hint: 'P.O. Box 12345-00100, Nairobi, Kenya',
                    lines: 2),
                const SizedBox(height: 14),

                // Role (read-only)
                _lbl('Role'),
                const SizedBox(height: 6),
                TextField(
                  controller: TextEditingController(
                      text: RoleService.instance.role),
                  readOnly: true,
                  style: const TextStyle(
                      fontFamily: 'DM Sans',
                      color: _kMuted,
                      fontSize: 14),
                  decoration: InputDecoration(
                    border: _border(),
                    enabledBorder: _border(),
                    filled: true,
                    fillColor: const Color(0xFFF3F4F6),
                    contentPadding: const EdgeInsets.symmetric(
                        horizontal: 14, vertical: 12),
                    suffixIcon: const Icon(Icons.lock_outline,
                        size: 15, color: _kMutedLight),
                    helperText: RoleService.instance.role == 'reader'
                        ? 'Want to publish? Contact us to become an author.'
                        : 'Role is assigned by admin.',
                    helperStyle: const TextStyle(
                        fontFamily: 'DM Sans',
                        fontSize: 11,
                        color: _kMutedLight),
                  ),
                ),
                const SizedBox(height: 14),

                // Bio
                Row(children: [
                  _lbl('Bio'),
                  const Spacer(),
                  Text(
                    '${_bioCtrl.text.length}/$_kMaxBio',
                    style: const TextStyle(
                        fontFamily: 'DM Sans',
                        fontSize: 11,
                        color: _kMutedLight),
                  ),
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
                      color: Color(0xFF1F2937)),
                  decoration: InputDecoration(
                    border: _border(),
                    enabledBorder: _border(),
                    focusedBorder: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(8),
                      borderSide:
                          const BorderSide(color: _kPrimary, width: 1.5),
                    ),
                    hintText: 'Passionate about reading…',
                    hintStyle: const TextStyle(
                        fontFamily: 'DM Sans',
                        color: _kMutedLight,
                        fontSize: 14),
                    contentPadding: const EdgeInsets.all(14),
                    filled: true,
                    fillColor: _kWhite,
                  ),
                ),
              ],
            );
          }),
          const SizedBox(height: 28),

          // ── Buttons ─────────────────────────────────────────────────────
          Wrap(spacing: 12, runSpacing: 12, children: [
            SizedBox(
              height: 46,
              child: ElevatedButton.icon(
                icon: _saving
                    ? const SizedBox(
                        width: 16,
                        height: 16,
                        child: CircularProgressIndicator(
                            strokeWidth: 2, color: _kWhite),
                      )
                    : const Icon(Icons.save_outlined, size: 16),
                label: Text(
                  _saving ? 'Saving…' : 'Save Changes',
                  style: const TextStyle(
                      fontFamily: 'DM Sans', fontWeight: FontWeight.w700),
                ),
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
                  foregroundColor: const Color(0xFF1F2937),
                  side: const BorderSide(color: _kBorder),
                  padding: const EdgeInsets.symmetric(
                      horizontal: 20, vertical: 12),
                  shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(8)),
                  textStyle: const TextStyle(fontFamily: 'DM Sans'),
                ),
                child: const Text('Back'),
              ),
            ),
          ]),
        ],
      ),
    );
  }

  // ══════════════════════════════════════════════════════════════════════════
  // TAB 1 – ORDERS  (matches TSX <TabsContent value="orders">)
  // ══════════════════════════════════════════════════════════════════════════
  Widget _ordersTab(double w) => _WCard(
        padding: EdgeInsets.zero,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Padding(
              padding: EdgeInsets.all(20),
              child: Text(
                'Order History',
                style: TextStyle(
                  fontFamily: 'PlayfairDisplay',
                  fontSize: 20,
                  fontWeight: FontWeight.w700,
                  color: Color(0xFF1F2937),
                ),
              ),
            ),
            Divider(height: 1, color: _kBorder),
            if (_orders.isEmpty)
              Padding(
                padding: const EdgeInsets.symmetric(vertical: 48),
                child: Center(
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(Icons.shopping_bag_outlined,
                          size: 48,
                          color: _kMutedLight.withOpacity(0.5)),
                      const SizedBox(height: 12),
                      const Text('No orders yet.',
                          style: TextStyle(
                              fontFamily: 'DM Sans',
                              color: _kMutedLight,
                              fontSize: 14)),
                      const SizedBox(height: 20),
                      ElevatedButton.icon(
                        icon: const Icon(Icons.menu_book_outlined,
                            size: 16),
                        label: const Text('Browse Books',
                            style: TextStyle(
                                fontFamily: 'DM Sans',
                                fontWeight: FontWeight.w700)),
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
                    Divider(height: 1, color: _kBorder),
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
          // header row
          Wrap(
            spacing: 12,
            runSpacing: 6,
            crossAxisAlignment: WrapCrossAlignment.center,
            children: [
              Text(
                'Order #${o['order_number'] ?? ''}',
                style: const TextStyle(
                  fontFamily: 'DM Sans',
                  fontWeight: FontWeight.w700,
                  fontSize: 14,
                  color: Color(0xFF1F2937),
                ),
              ),
              Text(
                _date(o['created_at']),
                style: const TextStyle(
                    fontFamily: 'DM Sans',
                    fontSize: 12,
                    color: _kMutedLight),
              ),
              _StatusBadge(o['payment_status'] as String? ?? 'pending'),
              Text(
                'KES ${_price(o['total_price'])}',
                style: const TextStyle(
                  fontFamily: 'DM Sans',
                  fontWeight: FontWeight.w800,
                  fontSize: 14,
                  color: _kPrimary,
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          Text(
            'Status: ${o['status'] ?? ''}',
            style: const TextStyle(
                fontFamily: 'DM Sans',
                fontSize: 12,
                color: _kMuted),
          ),
          const SizedBox(height: 8),
          // items
          ...items.map<Widget>((item) {
            final c = (item['content'] as Map<String, dynamic>?) ?? {};
            final coverUrl = c['cover_image_url'] as String?;
            return Padding(
              padding: const EdgeInsets.symmetric(vertical: 4),
              child: Row(children: [
                if (coverUrl != null && coverUrl.isNotEmpty)
                  ClipRRect(
                    borderRadius: BorderRadius.circular(4),
                    child: CachedNetworkImage(
                      imageUrl: coverUrl,
                      width: 24,
                      height: 32,
                      fit: BoxFit.cover,
                      errorWidget: (_, __, ___) => const SizedBox(
                          width: 24, height: 32),
                    ),
                  ),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    c['title'] as String? ?? 'Content',
                    style: const TextStyle(
                        fontFamily: 'DM Sans',
                        fontSize: 12,
                        color: _kMuted),
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
                const SizedBox(width: 8),
                if (isPaid)
                  TextButton.icon(
                    onPressed: () => Navigator.pushNamed(
                        context, '/book-detail',
                        arguments: c),
                    icon: const Icon(Icons.visibility_outlined,
                        size: 13),
                    label: const Text('Access Content',
                        style: TextStyle(
                            fontFamily: 'DM Sans',
                            fontSize: 11,
                            fontWeight: FontWeight.w700)),
                    style: TextButton.styleFrom(
                      foregroundColor: _kPrimary,
                      padding: const EdgeInsets.symmetric(
                          horizontal: 8, vertical: 4),
                      minimumSize: Size.zero,
                      tapTargetSize:
                          MaterialTapTargetSize.shrinkWrap,
                    ),
                  )
                else
                  const Text('Pay to access',
                      style: TextStyle(
                          fontFamily: 'DM Sans',
                          fontSize: 11,
                          color: _kMutedLight)),
              ]),
            );
          }),
        ],
      ),
    );
  }

  // ══════════════════════════════════════════════════════════════════════════
  // TAB 2 – BROWSE  (matches TSX <TabsContent value="browse">)
  // ══════════════════════════════════════════════════════════════════════════
  Widget _browseTab(double w) {
    final cols = w >= 900 ? 3 : 2;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // header
        Row(children: [
          const Text(
            'Recently Added',
            style: TextStyle(
              fontFamily: 'PlayfairDisplay',
              fontSize: 20,
              fontWeight: FontWeight.w700,
              color: Color(0xFF1F2937),
            ),
          ),
          const Spacer(),
          OutlinedButton.icon(
            onPressed: () => Navigator.pushNamed(context, '/books'),
            icon: const Icon(Icons.chevron_right, size: 16),
            label: const Text('View All',
                style: TextStyle(
                    fontFamily: 'DM Sans', fontSize: 12)),
            style: OutlinedButton.styleFrom(
              foregroundColor: _kMuted,
              side: const BorderSide(color: _kBorder),
              padding: const EdgeInsets.symmetric(
                  horizontal: 12, vertical: 8),
              shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(8)),
            ),
          ),
        ]),
        const SizedBox(height: 16),

        // grid or empty state
        if (_recentBooks.isEmpty)
          _WCard(
            child: Padding(
              padding: const EdgeInsets.symmetric(vertical: 48),
              child: Center(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(Icons.menu_book_outlined,
                        size: 48,
                        color: _kMutedLight.withOpacity(0.5)),
                    const SizedBox(height: 12),
                    const Text('No books available yet.',
                        style: TextStyle(
                            fontFamily: 'DM Sans',
                            color: _kMutedLight,
                            fontSize: 14)),
                  ],
                ),
              ),
            ),
          )
        else
          GridView.builder(
            shrinkWrap: true,
            physics: const NeverScrollableScrollPhysics(),
            gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
              crossAxisCount: cols,
              crossAxisSpacing: 12,
              mainAxisSpacing: 12,
              childAspectRatio: w >= 600 ? 0.68 : 0.62,
            ),
            itemCount: _recentBooks.length,
            itemBuilder: (_, i) => _BookCard(
              book: _recentBooks[i],
              onTap: () => Navigator.pushNamed(
                  context, '/book-detail',
                  arguments: _recentBooks[i]),
            ),
          ),

        const SizedBox(height: 20),

        // Browse all button
        SizedBox(
          width: double.infinity,
          height: 48,
          child: ElevatedButton.icon(
            icon: const Icon(Icons.search_outlined, size: 18),
            label: const Text('Browse All Books',
                style: TextStyle(
                    fontFamily: 'DM Sans',
                    fontWeight: FontWeight.w700,
                    fontSize: 15)),
            style: _primaryBtn(),
            onPressed: () => Navigator.pushNamed(context, '/books'),
          ),
        ),

        const SizedBox(height: 16),

        // Publish promo card (matching TSX amber promo box)
        Container(
          padding: const EdgeInsets.all(14),
          decoration: BoxDecoration(
            color: _kAmberBg,
            borderRadius: BorderRadius.circular(12),
            border: Border.all(color: const Color(0xFFFED7AA)),
          ),
          child: Row(children: [
            const Icon(Icons.auto_stories_rounded,
                color: _kAmber, size: 20),
            const SizedBox(width: 10),
            const Expanded(
              child: Text(
                'Are you an author? Publish your book with us.',
                style: TextStyle(
                    fontFamily: 'DM Sans',
                    fontSize: 12,
                    color: Color(0xFF92400E)),
              ),
            ),
            TextButton(
              onPressed: () =>
                  Navigator.pushNamed(context, '/publish'),
              style: TextButton.styleFrom(
                foregroundColor: _kAmber,
                padding: EdgeInsets.zero,
                minimumSize: Size.zero,
                tapTargetSize: MaterialTapTargetSize.shrinkWrap,
              ),
              child: const Text('Learn more →',
                  style: TextStyle(
                      fontFamily: 'DM Sans',
                      fontSize: 11,
                      fontWeight: FontWeight.w700)),
            ),
          ]),
        ),
      ],
    );
  }

  // ── bottom nav ────────────────────────────────────────────────────────────
  Widget _bottomNav() => Container(
        height: 64,
        decoration: BoxDecoration(
          color: _kWhite,
          border: Border(top: BorderSide(color: _kBorder)),
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
              onTap: () => Navigator.pushNamed(context, '/books'),
            ),
            _NavItem(
              icon: Icons.shopping_cart_outlined,
              label: 'Cart',
              onTap: () => Navigator.pushNamed(context, '/cart'),
            ),
            const _NavItem(
                icon: Icons.person, label: 'Profile', active: true),
          ],
        ),
      );

  // ─────────────────────────────────────────────────────────────────────────
  // Shared helpers
  // ─────────────────────────────────────────────────────────────────────────
  Widget _field(
    TextEditingController ctrl,
    String label, {
    int lines     = 1,
    String? hint,
    int? maxLen,
  }) =>
      Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _lbl(label),
          const SizedBox(height: 6),
          TextField(
            controller: ctrl,
            maxLines: lines,
            maxLength: maxLen,
            buildCounter: maxLen == null
                ? null
                : (_, {required currentLength,
                        required isFocused, maxLength}) =>
                    null,
            style: const TextStyle(
                fontFamily: 'DM Sans',
                fontSize: 14,
                color: Color(0xFF1F2937)),
            decoration: InputDecoration(
              border: _border(),
              enabledBorder: _border(),
              focusedBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(8),
                borderSide:
                    const BorderSide(color: _kPrimary, width: 1.5),
              ),
              hintText: hint,
              hintStyle: const TextStyle(
                  fontFamily: 'DM Sans',
                  color: _kMutedLight,
                  fontSize: 14),
              filled: true,
              fillColor: _kWhite,
              contentPadding: const EdgeInsets.symmetric(
                  horizontal: 14, vertical: 12),
            ),
          ),
        ],
      );

  Widget _row2(List<Widget> kids) => Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: kids
            .expand((w) => [Expanded(child: w), const SizedBox(width: 14)])
            .toList()
          ..removeLast(),
      );

  Widget _lbl(String t) => Text(
        t,
        style: const TextStyle(
          fontFamily: 'DM Sans',
          fontSize: 13,
          fontWeight: FontWeight.w600,
          color: Color(0xFF1F2937),
        ),
      );

  ButtonStyle _primaryBtn() => ElevatedButton.styleFrom(
        backgroundColor: _kPrimary,
        foregroundColor: _kWhite,
        elevation: 0,
        textStyle: const TextStyle(
            fontFamily: 'DM Sans',
            fontSize: 14,
            fontWeight: FontWeight.w700),
        padding:
            const EdgeInsets.symmetric(horizontal: 24, vertical: 12),
        shape:
            RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
      );

  OutlineInputBorder _border() => OutlineInputBorder(
        borderRadius: BorderRadius.circular(8),
        borderSide: const BorderSide(color: _kBorder),
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
    final d = double.tryParse(raw?.toString() ?? '0') ?? 0;
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
// Stat card (3-up row matching TSX grid)
// ─────────────────────────────────────────────────────────────────────────────
class _StatCard extends StatelessWidget {
  final String label, value;
  final IconData icon;
  final Color color, bg;

  const _StatCard({
    required this.label,
    required this.value,
    required this.icon,
    required this.color,
    required this.bg,
  });

  @override
  Widget build(BuildContext context) => Expanded(
        child: Container(
          padding: const EdgeInsets.symmetric(vertical: 14, horizontal: 12),
          decoration: BoxDecoration(
            color: _kWhite,
            borderRadius: BorderRadius.circular(_kRadius),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withOpacity(0.05),
                blurRadius: 6,
                offset: const Offset(0, 2),
              ),
            ],
          ),
          child: Row(children: [
            Container(
              width: 38,
              height: 38,
              decoration: BoxDecoration(
                  color: bg, borderRadius: BorderRadius.circular(8)),
              child: Icon(icon, color: color, size: 18),
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
                    child: Text(
                      value,
                      style: const TextStyle(
                        fontFamily: 'DM Sans',
                        fontSize: 20,
                        fontWeight: FontWeight.w800,
                        color: Color(0xFF1F2937),
                      ),
                    ),
                  ),
                  Text(
                    label,
                    style: const TextStyle(
                        fontFamily: 'DM Sans',
                        fontSize: 9,
                        color: _kMutedLight),
                    overflow: TextOverflow.ellipsis,
                  ),
                ],
              ),
            ),
          ]),
        ),
      );
}

// ─────────────────────────────────────────────────────────────────────────────
// Status badge
// ─────────────────────────────────────────────────────────────────────────────
class _StatusBadge extends StatelessWidget {
  final String status;
  const _StatusBadge(this.status);

  Color get _color => switch (status) {
        'paid' || 'published' || 'approved' => _kGreen,
        'rejected'                          => const Color(0xFFDC2626),
        'pending'                           => _kAmber,
        _                                   => _kMuted,
      };

  @override
  Widget build(BuildContext context) => Container(
        padding:
            const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
        decoration: BoxDecoration(
          color: _color.withOpacity(0.1),
          borderRadius: BorderRadius.circular(6),
        ),
        child: Text(
          status,
          style: TextStyle(
            fontFamily: 'DM Sans',
            fontSize: 10,
            fontWeight: FontWeight.w700,
            color: _color,
          ),
        ),
      );
}

// ─────────────────────────────────────────────────────────────────────────────
// Account type dropdown
// ─────────────────────────────────────────────────────────────────────────────
class _AccountDropdown extends StatelessWidget {
  final String value;
  final ValueChanged<String?> onChanged;
  final bool enabled;

  const _AccountDropdown({
    required this.value,
    required this.onChanged,
    required this.enabled,
  });

  @override
  Widget build(BuildContext context) => DropdownButtonFormField<String>(
        value: value,
        onChanged: enabled ? onChanged : null,
        decoration: InputDecoration(
          border: OutlineInputBorder(
            borderRadius: BorderRadius.circular(8),
            borderSide: const BorderSide(color: _kBorder),
          ),
          enabledBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(8),
            borderSide: const BorderSide(color: _kBorder),
          ),
          focusedBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(8),
            borderSide:
                const BorderSide(color: _kPrimary, width: 1.5),
          ),
          filled: true,
          fillColor: _kWhite,
          contentPadding: const EdgeInsets.symmetric(
              horizontal: 14, vertical: 12),
        ),
        style: const TextStyle(
            fontFamily: 'DM Sans',
            fontSize: 14,
            color: Color(0xFF1F2937)),
        items: const [
          DropdownMenuItem(value: 'personal',      child: Text('Personal')),
          DropdownMenuItem(value: 'corporate',     child: Text('Corporate')),
          DropdownMenuItem(value: 'institutional', child: Text('Institutional')),
        ],
      );
}

// ─────────────────────────────────────────────────────────────────────────────
// Book card (matches TSX grid card)
// ─────────────────────────────────────────────────────────────────────────────
class _BookCard extends StatelessWidget {
  final Map<String, dynamic> book;
  final VoidCallback onTap;

  const _BookCard({required this.book, required this.onTap});

  @override
  Widget build(BuildContext context) {
    final coverUrl = book['cover_image_url'] as String?;
    final price    =
        double.tryParse(book['price']?.toString() ?? '0') ?? 0;
    final rating   =
        double.tryParse(book['average_rating']?.toString() ?? '0') ?? 0;

    return GestureDetector(
      onTap: onTap,
      child: Container(
        decoration: BoxDecoration(
          color: _kWhite,
          borderRadius: BorderRadius.circular(_kRadius),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withOpacity(0.05),
              blurRadius: 6,
              offset: const Offset(0, 2),
            ),
          ],
        ),
        clipBehavior: Clip.antiAlias,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Expanded(
              child: coverUrl != null && coverUrl.isNotEmpty
                  ? CachedNetworkImage(
                      imageUrl: coverUrl,
                      fit: BoxFit.cover,
                      width: double.infinity,
                      errorWidget: (_, __, ___) => _fallback(),
                    )
                  : _fallback(),
            ),
            Padding(
              padding: const EdgeInsets.all(10),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    book['title'] as String? ?? '—',
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                      fontFamily: 'DM Sans',
                      fontWeight: FontWeight.w600,
                      fontSize: 12,
                      color: Color(0xFF1F2937),
                    ),
                  ),
                  const SizedBox(height: 6),
                  Row(children: [
                    if (rating > 0) ...[
                      const Icon(Icons.star_rounded,
                          size: 12, color: _kAmber),
                      const SizedBox(width: 2),
                      Text(
                        rating.toStringAsFixed(1),
                        style: const TextStyle(
                            fontFamily: 'DM Sans',
                            fontSize: 10,
                            color: _kAmber,
                            fontWeight: FontWeight.w600),
                      ),
                      const SizedBox(width: 6),
                    ],
                    const Spacer(),
                    Text(
                      price > 0
                          ? 'KES ${price.toStringAsFixed(0)}'
                          : 'Free',
                      style: const TextStyle(
                        fontFamily: 'DM Sans',
                        fontWeight: FontWeight.w800,
                        fontSize: 12,
                        color: _kPrimary,
                      ),
                    ),
                  ]),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _fallback() => Container(
        color: const Color(0xFFE5E7EB),
        child: const Center(
          child: Icon(Icons.book_outlined,
              size: 28, color: Color(0xFF9CA3AF)),
        ),
      );
}

// ─────────────────────────────────────────────────────────────────────────────
// Shared card container
// ─────────────────────────────────────────────────────────────────────────────
class _WCard extends StatelessWidget {
  final Widget child;
  final EdgeInsetsGeometry? padding;

  const _WCard({required this.child, this.padding});

  @override
  Widget build(BuildContext context) => Container(
        decoration: BoxDecoration(
          color: _kWhite,
          borderRadius: BorderRadius.circular(_kRadius),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withOpacity(0.05),
              blurRadius: 8,
              offset: const Offset(0, 2),
            ),
          ],
        ),
        padding: padding ?? const EdgeInsets.all(20),
        child: child,
      );
}

// ─────────────────────────────────────────────────────────────────────────────
// Bottom nav item
// ─────────────────────────────────────────────────────────────────────────────
class _NavItem extends StatelessWidget {
  final IconData icon;
  final String label;
  final bool active;
  final VoidCallback? onTap;

  const _NavItem({
    required this.icon,
    required this.label,
    this.active = false,
    this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final c = active ? _kPrimary : Colors.grey;
    return GestureDetector(
      onTap: onTap,
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(icon, color: c, size: 22),
          const SizedBox(height: 3),
          Text(
            label,
            style: TextStyle(
              fontFamily: 'DM Sans',
              fontSize: 11,
              color: c,
              fontWeight:
                  active ? FontWeight.w700 : FontWeight.normal,
            ),
          ),
        ],
      ),
    );
  }
}