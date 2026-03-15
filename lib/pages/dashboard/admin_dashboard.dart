// lib/pages/dashboard/admin_dashboard.dart
//
// ── DESIGN SOURCE: mirrors the React/TSX AdminDashboard exactly ──────────────
//   • Same sections: Hero (charcoal), Stats (5-up), Pending alert,
//     Tabs (Users / Submissions / Content / Orders / My Profile)
//   • Same colour palette: primary #B11226, charcoal #1A1A2E, bg #F9F5EF,
//     green #16A34A, amber #D97706, blue #2563EB, purple #7C3AED, red #DC2626
//   • Same typography: PlayfairDisplay display, DM Sans body
//   • Users tab: search box + table with inline role dropdown + active toggle
//   • Submissions tab: per-card approve/review/reject + rejection dialog overlay
//   • Content tab: table with view/edit actions
//   • Orders tab: table
//   • Profile tab: full self-contained edit form
//
// ── LAYOUT FIXES (box.dart:2251 / mouse_tracker:199) ─────────────────────────
//   1. NO NestedScrollView + TabBarView — replaced with a single
//      CustomScrollView inside LayoutBuilder → SizedBox (finite height).
//   2. Every list/grid uses shrinkWrap + NeverScrollableScrollPhysics inside
//      a SliverToBoxAdapter.
//   3. NO Flutter TabBar widget — custom horizontal pill row.
//   4. Rejection dialog is a Stack overlay inside the body, NOT a Dialog
//      widget (avoids extra route / context issues on Flutter Web).
// ─────────────────────────────────────────────────────────────────────────────

import 'dart:convert';
import 'dart:io';

import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../services/role_service.dart';

// ── Palette ───────────────────────────────────────────────────────────────────
const _kPrimary   = Color(0xFFB11226);
const _kCharcoal  = Color(0xFF1A1A2E);
const _kBg        = Color(0xFFF9F5EF);
const _kWhite     = Colors.white;
const _kBorder    = Color(0xFFE5E7EB);
const _kMuted     = Color(0xFF6B7280);
const _kMutedLt   = Color(0xFF9CA3AF);
const _kGreen     = Color(0xFF16A34A);
const _kGreenBg   = Color(0xFFF0FDF4);
const _kAmber     = Color(0xFFD97706);
const _kAmberBg   = Color(0xFFFFFBEB);
const _kBlue      = Color(0xFF2563EB);
const _kBlueBg    = Color(0xFFEFF6FF);
const _kPurple    = Color(0xFF7C3AED);
const _kPurpleBg  = Color(0xFFF5F3FF);
const _kRed       = Color(0xFFDC2626);
const _kRedBg     = Color(0xFFFEF2F2);
const _kEmerald   = Color(0xFF059669);
const _kEmeraldBg = Color(0xFFECFDF5);
const _kCard      = 12.0;
const _kMaxBio    = 500;
const _kMaxName   = 100;
const _kMaxAvat   = 5 * 1024 * 1024;

const _adminIds = {
  '5fbc35df-ae08-4f8a-b0b3-dd6bb4610ebd',
  'e2925b0b-c730-484c-b4f1-1361380bccd3',
};

const _roles = [
  'reader', 'author', 'publisher', 'editor',
  'moderator', 'admin', 'corporate_user',
];

// ─────────────────────────────────────────────────────────────────────────────
class AdminDashboardPage extends StatefulWidget {
  const AdminDashboardPage({super.key});
  @override
  State<AdminDashboardPage> createState() => _AdminDashboardPageState();
}

class _AdminDashboardPageState extends State<AdminDashboardPage> {
  final _sb = Supabase.instance.client;

  // ── data ──────────────────────────────────────────────────────────────────
  Map<String, dynamic>? _profile;
  List<Map<String, dynamic>> _users        = [];
  List<Map<String, dynamic>> _filteredUsers = [];
  List<Map<String, dynamic>> _publications = [];
  List<Map<String, dynamic>> _contents     = [];
  List<Map<String, dynamic>> _orders       = [];

  int    _statUsers   = 0;
  int    _statContent = 0;
  int    _statPending = 0;
  int    _statOrders  = 0;
  double _revenue     = 0;
  bool   _loading     = true;

  // ── user search ───────────────────────────────────────────────────────────
  final _searchCtrl = TextEditingController();
  String _savingRole = '';

  // ── rejection overlay ─────────────────────────────────────────────────────
  Map<String, dynamic>? _rejectTarget;
  final _feedbackCtrl = TextEditingController();
  bool  _processingPub = false;

  // ── profile edit ──────────────────────────────────────────────────────────
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

  // ── active tab ────────────────────────────────────────────────────────────
  int _tab = 0;

  // ── lifecycle ─────────────────────────────────────────────────────────────
  @override
  void initState() {
    super.initState();
    _bioCtrl.addListener(() => setState(() {}));
    _searchCtrl.addListener(_filterUsers);
    _loadAll();
  }

  @override
  void dispose() {
    for (final c in [
      _nameCtrl, _bioCtrl, _telCtrl, _adrCtrl,
      _orgCtrl, _dptCtrl, _feedbackCtrl, _searchCtrl,
    ]) {
      c.dispose();
    }
    super.dispose();
  }

  void _filterUsers() {
    final q = _searchCtrl.text.toLowerCase();
    setState(() {
      _filteredUsers = q.isEmpty
          ? List.from(_users)
          : _users.where((u) {
              final name  = (u['full_name']  as String? ?? '').toLowerCase();
              final email = (u['email']      as String? ?? '').toLowerCase();
              final role  = (u['role']       as String? ?? '').toLowerCase();
              return name.contains(q) || email.contains(q) || role.contains(q);
            }).toList();
    });
  }

  // ── load ──────────────────────────────────────────────────────────────────
  Future<void> _loadAll() async {
    if (!mounted) return;
    setState(() => _loading = true);
    try {
      final uid = RoleService.instance.userId;
      final res = await Future.wait([
        _sb.from('profiles').select('*').eq('id', uid).maybeSingle(),
        _sb.from('profiles').select('*').order('created_at', ascending: false),
        _sb.from('content')
            .select('id,title,status,content_type,created_at,view_count,total_downloads')
            .order('created_at', ascending: false)
            .limit(50),
        _sb.from('publications')
            .select('*')
            .order('created_at', ascending: false),
        _sb.from('orders')
            .select('id,status,payment_status,total_price,created_at')
            .order('created_at', ascending: false)
            .limit(50),
      ]);
      if (!mounted) return;

      final p      = res[0] as Map<String, dynamic>?;
      final users  = _asList(res[1]);
      final cont   = _asList(res[2]);
      final pubs   = _asList(res[3]);
      final ords   = _asList(res[4]);
      final rev    = ords
          .where((o) => o['payment_status'] == 'paid')
          .fold(0.0, (s, o) =>
              s + (double.tryParse(o['total_price']?.toString() ?? '0') ?? 0));

      setState(() {
        _profile        = p;
        _avatarUrl      = p?['avatar_url'] as String?;
        _nameCtrl.text  = (p?['full_name']   as String?) ?? '';
        _bioCtrl.text   = (p?['bio']         as String?) ?? '';
        _telCtrl.text   = (p?['phone']        as String?) ?? '';
        _adrCtrl.text   = (p?['address']      as String?) ?? '';
        _orgCtrl.text   = (p?['organization'] as String?) ?? '';
        _dptCtrl.text   = (p?['department']   as String?) ?? '';
        _users          = users;
        _filteredUsers  = List.from(users);
        _contents       = cont;
        _publications   = pubs;
        _orders         = ords;
        _statUsers      = users.length;
        _statContent    = cont.length;
        _statPending    = pubs.where((x) => x['status'] == 'pending').length;
        _statOrders     = ords.length;
        _revenue        = rev;
      });
    } catch (e) {
      _toast('Load failed: $e', err: true);
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  List<Map<String, dynamic>> _asList(dynamic raw) =>
      List<Map<String, dynamic>>.from((raw as List?) ?? []);

  // ── role change ───────────────────────────────────────────────────────────
  Future<void> _changeRole(String targetId, String newRole) async {
    if (_adminIds.contains(targetId) && newRole != 'admin') {
      _toast('Protected admin — role cannot be changed.', err: true);
      return;
    }
    setState(() => _savingRole = targetId);
    try {
      await _sb.from('profiles').update({
        'role': newRole,
        'updated_at': DateTime.now().toIso8601String(),
      }).eq('id', targetId);
      await _sb.from('notifications').insert({
        'user_id': targetId,
        'type': 'general',
        'title': 'Your role has been updated',
        'message': 'An admin changed your role to "$newRole".',
      });
      setState(() {
        _users = _users
            .map((u) => u['id'] == targetId ? {...u, 'role': newRole} : u)
            .toList();
        _filteredUsers = _filteredUsers
            .map((u) => u['id'] == targetId ? {...u, 'role': newRole} : u)
            .toList();
      });
      _toast('Role updated to $newRole');
    } catch (e) {
      _toast('Failed: $e', err: true);
    } finally {
      if (mounted) setState(() => _savingRole = '');
    }
  }

  // ── active toggle ─────────────────────────────────────────────────────────
  Future<void> _toggleActive(String targetId, bool current) async {
    if (_adminIds.contains(targetId)) {
      _toast('Protected admins cannot be deactivated.', err: true);
      return;
    }
    final err = await _sb
        .from('profiles')
        .update({'is_active': !current})
        .eq('id', targetId);
    setState(() {
      _users = _users
          .map((u) => u['id'] == targetId ? {...u, 'is_active': !current} : u)
          .toList();
      _filteredUsers = _filteredUsers
          .map((u) => u['id'] == targetId ? {...u, 'is_active': !current} : u)
          .toList();
    });
  }

  // ── pub action ────────────────────────────────────────────────────────────
  Future<void> _pubAction(String pubId, String action) async {
    setState(() => _processingPub = true);
    try {
      final updates = <String, dynamic>{
        'status': action,
        'reviewed_by': RoleService.instance.userId,
        'reviewed_at': DateTime.now().toIso8601String(),
      };
      if (action == 'rejected') {
        updates['rejection_feedback'] = _feedbackCtrl.text.trim();
      }
      await _sb.from('publications').update(updates).eq('id', pubId);

      final pub = _publications.firstWhere(
          (p) => p['id'] == pubId, orElse: () => {});
      final submittedBy = pub['submitted_by'] as String?;
      if (submittedBy != null) {
        final fb = _feedbackCtrl.text.trim();
        final msgs = {
          'approved': 'Your manuscript "${pub['title']}" has been approved!',
          'rejected': 'Your manuscript "${pub['title']}" was not approved.'
              '${fb.isNotEmpty ? ' Feedback: $fb' : ''}',
          'under_review':
              'Your manuscript "${pub['title']}" is now under review.',
        };
        await _sb.from('notifications').insert({
          'user_id': submittedBy,
          'type': action == 'approved'
              ? 'content_approved'
              : action == 'rejected'
                  ? 'content_rejected'
                  : 'general',
          'title': action == 'approved'
              ? 'Manuscript Approved!'
              : action == 'rejected'
                  ? 'Submission Decision'
                  : 'Under Review',
          'message': msgs[action],
        });
      }

      setState(() {
        _publications = _publications
            .map((p) => p['id'] == pubId ? {...p, 'status': action} : p)
            .toList();
        _statPending = _publications
            .where((p) => p['status'] == 'pending')
            .length;
        _rejectTarget = null;
        _feedbackCtrl.clear();
      });
      _toast('Publication marked as $action');
    } catch (e) {
      _toast('Failed: $e', err: true);
    } finally {
      if (mounted) setState(() => _processingPub = false);
    }
  }

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
    setState(() { _avatarFile = f; _avatarB64 = base64Encode(b); });
  }

  ImageProvider? get _avatarImg {
    if (_avatarFile != null) return FileImage(_avatarFile!);
    if (_avatarUrl != null && _avatarUrl!.isNotEmpty)
      return CachedNetworkImageProvider(_avatarUrl!);
    return null;
  }

  // ── save profile ──────────────────────────────────────────────────────────
  Future<void> _saveProfile() async {
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
        if (_avatarB64 != null) 'avatar_url': 'https://via.placeholder.com/150',
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
    final pendingPubs =
        _publications.where((p) => p['status'] == 'pending').toList();

    return Scaffold(
      backgroundColor: _kBg,
      bottomNavigationBar: _bottomNav(),
      body: LayoutBuilder(
        builder: (context, constraints) {
          final h = constraints.maxHeight.isInfinite
              ? MediaQuery.of(context).size.height
              : constraints.maxHeight;
          return SizedBox(
            height: h,
            child: Stack(
              children: [
                // ── Main scrollable content ──────────────────────────────
                CustomScrollView(
                  physics: const ClampingScrollPhysics(),
                  slivers: [
                    _appBar(w),
                    SliverToBoxAdapter(child: _heroBanner(w)),
                    SliverToBoxAdapter(child: _statsRow(w)),
                    if (pendingPubs.isNotEmpty)
                      SliverToBoxAdapter(
                          child: _pendingAlert(pendingPubs.length, w)),
                    SliverToBoxAdapter(child: _tabRow(w)),
                    SliverToBoxAdapter(child: _tabBody(w)),
                    const SliverToBoxAdapter(child: SizedBox(height: 32)),
                  ],
                ),
                // ── Rejection overlay (on top of everything) ─────────────
                if (_rejectTarget != null)
                  _RejectOverlay(
                    pub: _rejectTarget!,
                    ctrl: _feedbackCtrl,
                    processing: _processingPub,
                    onConfirm: () =>
                        _pubAction(_rejectTarget!['id'] as String, 'rejected'),
                    onCancel: () => setState(() {
                      _rejectTarget = null;
                      _feedbackCtrl.clear();
                    }),
                  ),
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
              valueColor: AlwaysStoppedAnimation(_kPrimary)),
        ),
      );

  // ── sliver app bar ────────────────────────────────────────────────────────
  SliverAppBar _appBar(double w) => SliverAppBar(
        pinned: true,
        elevation: 0,
        backgroundColor: _kCharcoal,
        surfaceTintColor: Colors.transparent,
        leading: Navigator.canPop(context)
            ? IconButton(
                icon: const Icon(Icons.arrow_back, color: Colors.white70),
                onPressed: () => Navigator.pop(context),
              )
            : null,
        title: Row(children: [
          const Icon(Icons.shield_rounded, color: _kRed, size: 18),
          const SizedBox(width: 8),
          Text(
            'Admin Panel',
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
            icon: const Icon(Icons.upload_rounded,
                color: Colors.white70, size: 22),
            tooltip: 'Upload Content',
            onPressed: () => Navigator.pushNamed(context, '/upload'),
          ),
          IconButton(
            icon: const Icon(Icons.library_books_outlined,
                color: Colors.white70, size: 20),
            tooltip: 'Manage Content',
            onPressed: () =>
                Navigator.pushNamed(context, '/content-management'),
          ),
          IconButton(
            icon: const Icon(Icons.logout_rounded,
                color: Colors.white54, size: 20),
            onPressed: _signOut,
          ),
        ],
      );

  // ── hero banner (charcoal, matching TSX) ─────────────────────────────────
  Widget _heroBanner(double w) {
    final pad  = _hp(w);
    final name = _nameCtrl.text.isNotEmpty
        ? _nameCtrl.text
        : (_profile?['full_name'] as String? ?? 'Administrator');
    final initL = name.isNotEmpty ? name[0].toUpperCase() : 'A';
    final email = _profile?['email'] as String? ?? 'Administration Panel';

    return Container(
      color: _kCharcoal,
      padding: EdgeInsets.fromLTRB(pad, 16, pad, 20),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          // avatar with red shield badge
          Stack(children: [
            GestureDetector(
              onTap: _pickAvatar,
              child: CircleAvatar(
                radius: 30,
                backgroundColor: _kRed.withOpacity(0.2),
                backgroundImage: _avatarImg,
                child: _avatarImg == null
                    ? Text(initL,
                        style: const TextStyle(
                          fontSize: 24,
                          fontWeight: FontWeight.bold,
                          color: _kRed,
                          fontFamily: 'PlayfairDisplay',
                        ))
                    : null,
              ),
            ),
            Positioned(
              bottom: 0, right: 0,
              child: Container(
                width: 20, height: 20,
                decoration: BoxDecoration(
                  color: _kRed,
                  shape: BoxShape.circle,
                  border: Border.all(color: _kCharcoal, width: 2),
                ),
                child: const Icon(Icons.shield_rounded,
                    size: 10, color: _kWhite),
              ),
            ),
          ]),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(children: [
                  Flexible(
                    child: Text(name,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                          fontFamily: 'PlayfairDisplay',
                          fontSize: 18,
                          fontWeight: FontWeight.w700,
                          color: _kWhite,
                        )),
                  ),
                  const SizedBox(width: 8),
                  Container(
                    padding: const EdgeInsets.symmetric(
                        horizontal: 8, vertical: 2),
                    decoration: BoxDecoration(
                      color: _kRed.withOpacity(0.2),
                      borderRadius: BorderRadius.circular(20),
                      border: Border.all(
                          color: _kRed.withOpacity(0.4)),
                    ),
                    child: const Text('ADMIN',
                        style: TextStyle(
                            fontFamily: 'DM Sans',
                            fontSize: 10,
                            fontWeight: FontWeight.w800,
                            color: Color(0xFFFCA5A5))),
                  ),
                ]),
                const SizedBox(height: 2),
                Text(email,
                    style: const TextStyle(
                        fontFamily: 'DM Sans',
                        fontSize: 12,
                        color: Colors.white54),
                    overflow: TextOverflow.ellipsis),
              ],
            ),
          ),
          // action buttons (visible on wider screens)
          if (w >= 500) ...[
            _HeroBtnOutline(
              label: 'Upload',
              icon: Icons.upload_rounded,
              onTap: () => Navigator.pushNamed(context, '/upload'),
            ),
            const SizedBox(width: 8),
            _HeroBtnOutline(
              label: 'Manage',
              icon: Icons.library_books_outlined,
              onTap: () =>
                  Navigator.pushNamed(context, '/content-management'),
            ),
          ],
        ],
      ),
    );
  }

  // ── stats row (5-up, matching TSX grid) ──────────────────────────────────
  Widget _statsRow(double w) {
    final pad  = _hp(w);
    final cols = w >= 700 ? 5 : 3;
    final stats = [
      _StatData('Total Users',    '$_statUsers',
          Icons.people_outline,        _kBlue,    _kBlueBg),
      _StatData('Content Items',  '$_statContent',
          Icons.book_outlined,         _kGreen,   _kGreenBg),
      _StatData('Pending Review', '$_statPending',
          Icons.access_time_rounded,   _kAmber,   _kAmberBg),
      _StatData('Orders',         '$_statOrders',
          Icons.shopping_bag_outlined, _kPurple,  _kPurpleBg),
      _StatData('Revenue (KES)',  _revenue.toStringAsFixed(0),
          Icons.trending_up_rounded,   _kEmerald, _kEmeraldBg),
    ];

    return Padding(
      padding: EdgeInsets.fromLTRB(pad, 20, pad, 0),
      child: GridView.count(
        shrinkWrap: true,
        physics: const NeverScrollableScrollPhysics(),
        crossAxisCount: cols,
        crossAxisSpacing: 10,
        mainAxisSpacing: 10,
        childAspectRatio: w < 400 ? 1.5 : 1.8,
        children: stats.map((s) => _StatCard(s)).toList(),
      ),
    );
  }

  // ── pending alert (matches TSX amber banner) ──────────────────────────────
  Widget _pendingAlert(int count, double w) {
    final pad = _hp(w);
    return Padding(
      padding: EdgeInsets.fromLTRB(pad, 16, pad, 0),
      child: Container(
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          color: _kAmberBg,
          border: Border.all(color: const Color(0xFFFDE68A)),
          borderRadius: BorderRadius.circular(12),
        ),
        child: Row(children: [
          const Icon(Icons.warning_amber_rounded,
              color: _kAmber, size: 20),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              '$count manuscript${count > 1 ? 's' : ''} awaiting review',
              style: const TextStyle(
                fontFamily: 'DM Sans',
                fontWeight: FontWeight.w600,
                fontSize: 13,
                color: Color(0xFF92400E),
              ),
            ),
          ),
          GestureDetector(
            onTap: () => setState(() => _tab = 1),
            child: Container(
              padding: const EdgeInsets.symmetric(
                  horizontal: 12, vertical: 7),
              decoration: BoxDecoration(
                color: _kAmber,
                borderRadius: BorderRadius.circular(8),
              ),
              child: const Text('Review Now',
                  style: TextStyle(
                      fontFamily: 'DM Sans',
                      fontSize: 12,
                      fontWeight: FontWeight.w700,
                      color: _kWhite)),
            ),
          ),
        ]),
      ),
    );
  }

  // ── tab pill row ──────────────────────────────────────────────────────────
  Widget _tabRow(double w) {
    final pad = _hp(w);
    final pending = _publications.where((p) => p['status'] == 'pending').length;
    final tabs = [
      (Icons.people_outline,       'Users'),
      (Icons.description_outlined,
          'Submissions${pending > 0 ? ' ($pending)' : ''}'),
      (Icons.book_outlined,        'Content'),
      (Icons.shopping_bag_outlined,'Orders'),
      (Icons.person_outline,       'My Profile'),
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
                      horizontal: 14, vertical: 10),
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
                      Text(tabs[i].$2,
                          style: TextStyle(
                            fontFamily: 'DM Sans',
                            fontSize: 13,
                            fontWeight: active
                                ? FontWeight.w700
                                : FontWeight.normal,
                            color: active ? _kWhite : _kMuted,
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

  // ── tab body dispatcher ───────────────────────────────────────────────────
  Widget _tabBody(double w) {
    final pad = _hp(w);
    Widget body;
    switch (_tab) {
      case 0:  body = _usersTab(w);       break;
      case 1:  body = _submissionsTab(w); break;
      case 2:  body = _contentTab(w);     break;
      case 3:  body = _ordersTab(w);      break;
      default: body = _profileTab(w);
    }
    return Padding(
      padding: EdgeInsets.fromLTRB(pad, 20, pad, 0),
      child: body,
    );
  }

  // ══════════════════════════════════════════════════════════════════════════
  // TAB 0 – USERS
  // ══════════════════════════════════════════════════════════════════════════
  Widget _usersTab(double w) => _WCard(
        padding: EdgeInsets.zero,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // header + search
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 20, 20, 16),
              child: Wrap(
                spacing: 12,
                runSpacing: 12,
                crossAxisAlignment: WrapCrossAlignment.center,
                children: [
                  const Text('User Management',
                      style: TextStyle(
                        fontFamily: 'PlayfairDisplay',
                        fontSize: 18,
                        fontWeight: FontWeight.w700,
                        color: Color(0xFF1F2937),
                      )),
                  SizedBox(
                    width: 220,
                    height: 38,
                    child: TextField(
                      controller: _searchCtrl,
                      style: const TextStyle(
                          fontFamily: 'DM Sans', fontSize: 13),
                      decoration: InputDecoration(
                        hintText: 'Search users…',
                        hintStyle: const TextStyle(
                            fontFamily: 'DM Sans',
                            fontSize: 13,
                            color: _kMutedLt),
                        prefixIcon: const Icon(Icons.search,
                            size: 16, color: _kMutedLt),
                        contentPadding:
                            const EdgeInsets.symmetric(vertical: 0),
                        border: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(8),
                            borderSide:
                                const BorderSide(color: _kBorder)),
                        enabledBorder: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(8),
                            borderSide:
                                const BorderSide(color: _kBorder)),
                        filled: true,
                        fillColor: _kWhite,
                      ),
                    ),
                  ),
                  OutlinedButton.icon(
                    onPressed: _loadAll,
                    icon: const Icon(Icons.refresh_rounded, size: 14),
                    label: const Text('Refresh',
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
                ],
              ),
            ),
            Divider(height: 1, color: _kBorder),
            if (_filteredUsers.isEmpty)
              const Padding(
                padding: EdgeInsets.symmetric(vertical: 48),
                child: Center(
                  child: Text('No users found.',
                      style: TextStyle(
                          fontFamily: 'DM Sans',
                          color: _kMutedLt,
                          fontSize: 14)),
                ),
              )
            else
              ListView.separated(
                shrinkWrap: true,
                physics: const NeverScrollableScrollPhysics(),
                itemCount: _filteredUsers.length,
                separatorBuilder: (_, __) =>
                    Divider(height: 1, color: _kBorder),
                itemBuilder: (_, i) => _userRow(_filteredUsers[i]),
              ),
          ],
        ),
      );

  Widget _userRow(Map<String, dynamic> u) {
    final isProtected = _adminIds.contains(u['id'] as String?);
    final role        = u['role'] as String? ?? 'reader';
    final isActive    = u['is_active'] != false;
    final name        = u['full_name'] as String? ?? '—';
    final email       = u['email']    as String? ??
        ((u['id'] as String).substring(0, 12) + '…');
    final avatarUrl   = u['avatar_url'] as String?;
    final initial     = name.isNotEmpty ? name[0].toUpperCase() : '?';
    final joined      = _date(u['created_at']);
    final acctType    = u['account_type'] as String? ?? 'personal';

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          // avatar
          SizedBox(
            width: 38, height: 38,
            child: ClipOval(
              child: avatarUrl != null && avatarUrl.isNotEmpty
                  ? CachedNetworkImage(
                      imageUrl: avatarUrl, fit: BoxFit.cover,
                      errorWidget: (_, __, ___) =>
                          _initAvatar(initial))
                  : _initAvatar(initial),
            ),
          ),
          const SizedBox(width: 12),
          // name / email
          Expanded(
            flex: 3,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(children: [
                  Flexible(
                    child: Text(name,
                        style: const TextStyle(
                            fontFamily: 'DM Sans',
                            fontWeight: FontWeight.w600,
                            fontSize: 13,
                            color: Color(0xFF1F2937)),
                        overflow: TextOverflow.ellipsis),
                  ),
                  if (isProtected) ...[
                    const SizedBox(width: 4),
                    const Icon(Icons.shield_rounded,
                        size: 13, color: _kRed),
                  ],
                ]),
                Text(email,
                    style: const TextStyle(
                        fontFamily: 'DM Sans',
                        fontSize: 11,
                        color: _kMutedLt),
                    overflow: TextOverflow.ellipsis),
              ],
            ),
          ),
          const SizedBox(width: 8),
          // role selector or locked pill
          if (isProtected)
            _RolePill('admin', _roleColor('admin'))
          else
            _RoleDropdown(
              value: role,
              saving: _savingRole == u['id'],
              onChanged: (r) =>
                  _changeRole(u['id'] as String, r ?? role),
            ),
          const SizedBox(width: 8),
          // account type
          if (MediaQuery.of(context).size.width >= 600)
            Padding(
              padding: const EdgeInsets.only(right: 8),
              child: Text(acctType,
                  style: const TextStyle(
                      fontFamily: 'DM Sans',
                      fontSize: 11,
                      color: _kMutedLt)),
            ),
          // active toggle
          GestureDetector(
            onTap: isProtected
                ? null
                : () => _toggleActive(
                    u['id'] as String, isActive),
            child: Container(
              padding: const EdgeInsets.symmetric(
                  horizontal: 8, vertical: 3),
              decoration: BoxDecoration(
                color: isActive ? _kGreenBg : _kRedBg,
                borderRadius: BorderRadius.circular(6),
              ),
              child: Text(
                isActive ? 'Active' : 'Inactive',
                style: TextStyle(
                  fontFamily: 'DM Sans',
                  fontSize: 10,
                  fontWeight: FontWeight.w700,
                  color: isActive ? _kGreen : _kRed,
                ),
              ),
            ),
          ),
          // joined date
          if (MediaQuery.of(context).size.width >= 700)
            Padding(
              padding: const EdgeInsets.only(left: 8),
              child: Text(joined,
                  style: const TextStyle(
                      fontFamily: 'DM Sans',
                      fontSize: 11,
                      color: _kMutedLt)),
            ),
        ],
      ),
    );
  }

  Widget _initAvatar(String i) => Container(
        color: const Color(0xFFE5E7EB),
        child: Center(
          child: Text(i,
              style: const TextStyle(
                  fontFamily: 'DM Sans',
                  fontWeight: FontWeight.w700,
                  fontSize: 15,
                  color: _kMuted)),
        ),
      );

  // ══════════════════════════════════════════════════════════════════════════
  // TAB 1 – SUBMISSIONS
  // ══════════════════════════════════════════════════════════════════════════
  Widget _submissionsTab(double w) {
    if (_publications.isEmpty) {
      return _WCard(
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: 48),
          child: Center(
            child: Column(mainAxisSize: MainAxisSize.min, children: [
              Icon(Icons.description_outlined,
                  size: 48,
                  color: _kMutedLt.withOpacity(0.5)),
              const SizedBox(height: 12),
              const Text('No manuscript submissions yet.',
                  style: TextStyle(
                      fontFamily: 'DM Sans',
                      color: _kMutedLt,
                      fontSize: 14)),
            ]),
          ),
        ),
      );
    }

    return ListView.separated(
      shrinkWrap: true,
      physics: const NeverScrollableScrollPhysics(),
      itemCount: _publications.length,
      separatorBuilder: (_, __) => const SizedBox(height: 12),
      itemBuilder: (_, i) => _subCard(_publications[i]),
    );
  }

  Widget _subCard(Map<String, dynamic> pub) {
    final status = pub['status'] as String? ?? 'pending';
    final canAct = status == 'pending' || status == 'under_review';

    return _WCard(
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
                    Wrap(spacing: 8, runSpacing: 4,
                        crossAxisAlignment: WrapCrossAlignment.center,
                        children: [
                          Text(pub['title'] as String? ?? '—',
                              style: const TextStyle(
                                fontFamily: 'PlayfairDisplay',
                                fontSize: 16,
                                fontWeight: FontWeight.w700,
                                color: Color(0xFF1F2937),
                              )),
                          _StatusPill(status),
                        ]),
                    const SizedBox(height: 4),
                    Text(
                      'By ${pub['author_name'] ?? '—'}'
                      '${pub['publishing_type'] != null ? '  ·  ${pub['publishing_type']} publishing' : ''}',
                      style: const TextStyle(
                          fontFamily: 'DM Sans',
                          fontSize: 12,
                          color: _kMuted),
                    ),
                    if ((pub['description'] as String? ?? '').isNotEmpty) ...[
                      const SizedBox(height: 6),
                      Text(pub['description'] as String,
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(
                              fontFamily: 'DM Sans',
                              fontSize: 12,
                              color: _kMutedLt)),
                    ],
                    const SizedBox(height: 6),
                    Wrap(spacing: 14, runSpacing: 4, children: [
                      if (pub['language'] != null)
                        _metaTag(pub['language'] as String),
                      if (pub['pages'] != null)
                        _metaTag('${pub['pages']} pages'),
                      _metaTag('Submitted ${_date(pub['created_at'])}'),
                    ]),
                  ],
                ),
              ),
              if (pub['manuscript_file_url'] != null) ...[
                const SizedBox(width: 8),
                OutlinedButton.icon(
                  icon: const Icon(Icons.visibility_outlined, size: 13),
                  label: const Text('View File',
                      style: TextStyle(
                          fontFamily: 'DM Sans', fontSize: 12)),
                  onPressed: () {},
                  style: OutlinedButton.styleFrom(
                    foregroundColor: _kMuted,
                    side: const BorderSide(color: _kBorder),
                    padding: const EdgeInsets.symmetric(
                        horizontal: 10, vertical: 6),
                    shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(7)),
                  ),
                ),
              ],
            ],
          ),
          if (canAct) ...[
            const SizedBox(height: 12),
            Row(children: [
              Expanded(
                child: _ActionBtn(
                  label: 'Approve',
                  icon: Icons.check_circle_outline,
                  color: _kGreen,
                  onTap: () =>
                      _pubAction(pub['id'] as String, 'approved'),
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: _ActionBtn(
                  label: 'Review',
                  icon: Icons.access_time_rounded,
                  color: _kBlue,
                  onTap: () =>
                      _pubAction(pub['id'] as String, 'under_review'),
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: _ActionBtn(
                  label: 'Reject',
                  icon: Icons.cancel_outlined,
                  color: _kRed,
                  onTap: () => setState(() => _rejectTarget = pub),
                ),
              ),
            ]),
          ],
          if ((pub['rejection_feedback'] as String? ?? '').isNotEmpty) ...[
            const SizedBox(height: 10),
            Container(
              padding: const EdgeInsets.all(10),
              decoration: BoxDecoration(
                color: _kRedBg,
                border: Border.all(
                    color: const Color(0xFFFECACA)),
                borderRadius: BorderRadius.circular(8),
              ),
              child: RichText(
                text: TextSpan(
                  style: const TextStyle(
                      fontFamily: 'DM Sans',
                      fontSize: 12,
                      color: _kRed),
                  children: [
                    const TextSpan(
                        text: 'Feedback: ',
                        style: TextStyle(fontWeight: FontWeight.w700)),
                    TextSpan(
                        text: pub['rejection_feedback'] as String),
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
  // TAB 2 – CONTENT
  // ══════════════════════════════════════════════════════════════════════════
  Widget _contentTab(double w) => _WCard(
        padding: EdgeInsets.zero,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 20, 20, 16),
              child: Row(children: [
                const Text('Content Library',
                    style: TextStyle(
                      fontFamily: 'PlayfairDisplay',
                      fontSize: 18,
                      fontWeight: FontWeight.w700,
                      color: Color(0xFF1F2937),
                    )),
                const Spacer(),
                _SmallBtn(
                  label: 'Upload',
                  icon: Icons.upload_rounded,
                  onTap: () => Navigator.pushNamed(context, '/upload'),
                ),
                const SizedBox(width: 8),
                _SmallBtn(
                  label: 'Manage All',
                  icon: Icons.settings_outlined,
                  onTap: () => Navigator.pushNamed(
                      context, '/content-management'),
                ),
              ]),
            ),
            Divider(height: 1, color: _kBorder),
            if (_contents.isEmpty)
              Padding(
                padding: const EdgeInsets.symmetric(vertical: 48),
                child: Center(
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(Icons.library_books_outlined,
                          size: 48,
                          color: _kMutedLt.withOpacity(0.5)),
                      const SizedBox(height: 12),
                      const Text('No content yet.',
                          style: TextStyle(
                              fontFamily: 'DM Sans',
                              color: _kMutedLt,
                              fontSize: 14)),
                      const SizedBox(height: 16),
                      ElevatedButton.icon(
                        icon: const Icon(Icons.upload_rounded,
                            size: 14),
                        label: const Text('Upload Some',
                            style: TextStyle(fontFamily: 'DM Sans')),
                        style: ElevatedButton.styleFrom(
                          backgroundColor: _kPrimary,
                          foregroundColor: _kWhite,
                          elevation: 0,
                          shape: RoundedRectangleBorder(
                              borderRadius:
                                  BorderRadius.circular(8)),
                        ),
                        onPressed: () =>
                            Navigator.pushNamed(context, '/upload'),
                      ),
                    ],
                  ),
                ),
              )
            else
              ListView.separated(
                shrinkWrap: true,
                physics: const NeverScrollableScrollPhysics(),
                itemCount: _contents.length,
                separatorBuilder: (_, __) =>
                    Divider(height: 1, color: _kBorder),
                itemBuilder: (_, i) => _contentRow(_contents[i]),
              ),
          ],
        ),
      );

  Widget _contentRow(Map<String, dynamic> c) {
    final status = c['status'] as String? ?? 'draft';
    return Padding(
      padding: const EdgeInsets.symmetric(
          horizontal: 20, vertical: 12),
      child: Row(children: [
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(c['title'] as String? ?? '—',
                  style: const TextStyle(
                      fontFamily: 'DM Sans',
                      fontWeight: FontWeight.w600,
                      fontSize: 13,
                      color: Color(0xFF1F2937)),
                  overflow: TextOverflow.ellipsis),
              const SizedBox(height: 3),
              Row(children: [
                Text(c['content_type'] as String? ?? '—',
                    style: const TextStyle(
                        fontFamily: 'DM Sans',
                        fontSize: 11,
                        color: _kMutedLt)),
                const SizedBox(width: 8),
                _StatusPill(status),
                const SizedBox(width: 8),
                Text('${c['view_count'] ?? 0} views · '
                    '${c['total_downloads'] ?? 0} dl',
                    style: const TextStyle(
                        fontFamily: 'DM Sans',
                        fontSize: 10,
                        color: _kMutedLt)),
              ]),
            ],
          ),
        ),
        Text(_date(c['created_at']),
            style: const TextStyle(
                fontFamily: 'DM Sans',
                fontSize: 11,
                color: _kMutedLt)),
        const SizedBox(width: 12),
        // view
        IconButton(
          icon: const Icon(Icons.visibility_outlined,
              size: 16, color: _kMuted),
          onPressed: () => Navigator.pushNamed(
              context, '/book-detail', arguments: c),
          tooltip: 'View',
          padding: EdgeInsets.zero,
          constraints: const BoxConstraints(
              minWidth: 28, minHeight: 28),
        ),
        // edit
        IconButton(
          icon: const Icon(Icons.edit_outlined,
              size: 16, color: _kMuted),
          onPressed: () => Navigator.pushNamed(
              context, '/content/update/${c['id']}'),
          tooltip: 'Edit',
          padding: EdgeInsets.zero,
          constraints: const BoxConstraints(
              minWidth: 28, minHeight: 28),
        ),
      ]),
    );
  }

  // ══════════════════════════════════════════════════════════════════════════
  // TAB 3 – ORDERS
  // ══════════════════════════════════════════════════════════════════════════
  Widget _ordersTab(double w) => _WCard(
        padding: EdgeInsets.zero,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Padding(
              padding: EdgeInsets.all(20),
              child: Text('Recent Orders',
                  style: TextStyle(
                    fontFamily: 'PlayfairDisplay',
                    fontSize: 18,
                    fontWeight: FontWeight.w700,
                    color: Color(0xFF1F2937),
                  )),
            ),
            Divider(height: 1, color: _kBorder),
            if (_orders.isEmpty)
              const Padding(
                padding: EdgeInsets.symmetric(vertical: 48),
                child: Center(
                  child: Text('No orders yet.',
                      style: TextStyle(
                          fontFamily: 'DM Sans',
                          color: _kMutedLt,
                          fontSize: 14)),
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
    final isPaid = o['payment_status'] == 'paid';
    return Padding(
      padding: const EdgeInsets.symmetric(
          horizontal: 20, vertical: 12),
      child: Row(children: [
        // ID
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                '${(o['id'] as String).substring(0, 8)}…',
                style: const TextStyle(
                    fontFamily: 'monospace',
                    fontWeight: FontWeight.w600,
                    fontSize: 12,
                    color: Color(0xFF1F2937)),
              ),
              const SizedBox(height: 3),
              Row(children: [
                _StatusPill(o['status'] as String? ?? 'pending'),
                const SizedBox(width: 8),
                Text(
                  o['payment_status'] as String? ?? '—',
                  style: TextStyle(
                    fontFamily: 'DM Sans',
                    fontSize: 11,
                    fontWeight: FontWeight.w600,
                    color: isPaid ? _kGreen : _kAmber,
                  ),
                ),
              ]),
            ],
          ),
        ),
        Column(crossAxisAlignment: CrossAxisAlignment.end, children: [
          Text(
            'KES ${_price(o['total_price'])}',
            style: const TextStyle(
              fontFamily: 'DM Sans',
              fontWeight: FontWeight.w800,
              fontSize: 14,
              color: _kPrimary,
            ),
          ),
          Text(_date(o['created_at']),
              style: const TextStyle(
                  fontFamily: 'DM Sans',
                  fontSize: 11,
                  color: _kMutedLt)),
        ]),
      ]),
    );
  }

  // ══════════════════════════════════════════════════════════════════════════
  // TAB 4 – MY PROFILE
  // ══════════════════════════════════════════════════════════════════════════
  Widget _profileTab(double w) => _WCard(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text('My Profile',
                style: TextStyle(
                  fontFamily: 'PlayfairDisplay',
                  fontSize: 20,
                  fontWeight: FontWeight.w700,
                  color: Color(0xFF1F2937),
                )),
            const SizedBox(height: 24),

            // avatar
            const Text('Profile Picture',
                style: TextStyle(
                    fontFamily: 'DM Sans',
                    fontSize: 13,
                    fontWeight: FontWeight.w600,
                    color: Color(0xFF1F2937))),
            const SizedBox(height: 12),
            Row(crossAxisAlignment: CrossAxisAlignment.center, children: [
              GestureDetector(
                onTap: _pickAvatar,
                child: Stack(children: [
                  CircleAvatar(
                    radius: 40,
                    backgroundColor: _kRed.withOpacity(0.1),
                    backgroundImage: _avatarImg,
                    child: _avatarImg == null
                        ? Text(
                            _nameCtrl.text.isNotEmpty
                                ? _nameCtrl.text[0].toUpperCase()
                                : 'A',
                            style: const TextStyle(
                              fontSize: 32,
                              color: _kRed,
                              fontFamily: 'PlayfairDisplay',
                            ))
                        : null,
                  ),
                  Positioned(
                    bottom: 4, right: 4,
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
              Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                OutlinedButton.icon(
                  icon: const Icon(Icons.upload_file, size: 14),
                  label: const Text('Change Photo',
                      style:
                          TextStyle(fontFamily: 'DM Sans', fontSize: 13)),
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
                        color: _kMutedLt)),
              ]),
            ]),
            const SizedBox(height: 24),

            // Email read-only
            _lbl('Email'),
            const SizedBox(height: 6),
            TextField(
              controller: TextEditingController(
                  text: _profile?['email'] as String? ?? ''),
              readOnly: true,
              style: const TextStyle(
                  fontFamily: 'DM Sans', color: _kMuted, fontSize: 14),
              decoration: InputDecoration(
                border: _border(),
                enabledBorder: _border(),
                filled: true,
                fillColor: const Color(0xFFF3F4F6),
                contentPadding: const EdgeInsets.symmetric(
                    horizontal: 14, vertical: 12),
                suffixIcon: const Icon(Icons.lock_outline,
                    size: 15, color: _kMutedLt),
              ),
            ),
            const SizedBox(height: 14),

            // fields
            LayoutBuilder(builder: (_, c) {
              final wide = c.maxWidth >= 500;
              return Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  if (wide)
                    _row2([
                      _field(_nameCtrl, 'Full Name',
                          hint: 'Your name', maxLen: _kMaxName),
                      _field(_telCtrl, 'Phone',
                          hint: '+254 7xx xxx xxx'),
                    ])
                  else ...[
                    _field(_nameCtrl, 'Full Name',
                        hint: 'Your name', maxLen: _kMaxName),
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
                      _field(_orgCtrl, 'Organization',
                          hint: 'Intercen Books'),
                      _field(_dptCtrl, 'Department',
                          hint: 'Editorial'),
                    ])
                  else ...[
                    _field(_orgCtrl, 'Organization',
                        hint: 'Intercen Books'),
                    const SizedBox(height: 14),
                    _field(_dptCtrl, 'Department', hint: 'Editorial'),
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
                          size: 15, color: _kMutedLt),
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
                            color: _kMutedLt)),
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
                        borderSide: const BorderSide(
                            color: _kPrimary, width: 1.5),
                      ),
                      hintText: 'About you…',
                      hintStyle: const TextStyle(
                          fontFamily: 'DM Sans',
                          color: _kMutedLt,
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

            Wrap(spacing: 12, runSpacing: 12, children: [
              SizedBox(
                height: 46,
                child: ElevatedButton.icon(
                  icon: _saving
                      ? const SizedBox(
                          width: 16, height: 16,
                          child: CircularProgressIndicator(
                              strokeWidth: 2, color: _kWhite))
                      : const Icon(Icons.save_outlined, size: 16),
                  label: Text(_saving ? 'Saving…' : 'Save Changes',
                      style: const TextStyle(
                          fontFamily: 'DM Sans',
                          fontWeight: FontWeight.w700)),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: _kPrimary,
                    foregroundColor: _kWhite,
                    elevation: 0,
                    padding: const EdgeInsets.symmetric(
                        horizontal: 24, vertical: 12),
                    shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(8)),
                  ),
                  onPressed: _saving ? null : _saveProfile,
                ),
              ),
              SizedBox(
                height: 46,
                child: OutlinedButton(
                  onPressed: _saving
                      ? null
                      : () => Navigator.maybePop(context),
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
              icon: Icons.upload_outlined,
              label: 'Upload',
              onTap: () => Navigator.pushNamed(context, '/upload'),
            ),
            const _NavItem(
                icon: Icons.admin_panel_settings_outlined,
                label: 'Admin',
                active: true),
          ],
        ),
      );

  // ─────────────────────────────────────────────────────────────────────────
  // Shared helpers
  // ─────────────────────────────────────────────────────────────────────────
  Widget _field(TextEditingController ctrl, String label,
      {int lines = 1, String? hint, int? maxLen}) =>
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
                  color: _kMutedLt,
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

  Widget _lbl(String t) => Text(t,
      style: const TextStyle(
          fontFamily: 'DM Sans',
          fontSize: 13,
          fontWeight: FontWeight.w600,
          color: Color(0xFF1F2937)));

  Widget _metaTag(String t) => Text(t,
      style: const TextStyle(
          fontFamily: 'DM Sans', fontSize: 11, color: _kMutedLt));

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

  Color _roleColor(String role) => switch (role) {
        'admin'          => _kRed,
        'author'         => _kBlue,
        'publisher'      => _kPurple,
        'editor'         => _kAmber,
        'moderator'      => _kGreen,
        'corporate_user' => const Color(0xFF4F46E5),
        _                => _kMuted,
      };
}

// ─────────────────────────────────────────────────────────────────────────────
// _StatData  (value object for stat cards)
// ─────────────────────────────────────────────────────────────────────────────
class _StatData {
  final String label, value;
  final IconData icon;
  final Color color, bg;
  const _StatData(this.label, this.value, this.icon, this.color, this.bg);
}

// ─────────────────────────────────────────────────────────────────────────────
// Stat card
// ─────────────────────────────────────────────────────────────────────────────
class _StatCard extends StatelessWidget {
  final _StatData d;
  const _StatCard(this.d);

  @override
  Widget build(BuildContext context) => Container(
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          color: _kWhite,
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
                          fontSize: 18,
                          fontWeight: FontWeight.w800,
                          color: Color(0xFF1F2937))),
                ),
                Text(d.label,
                    style: const TextStyle(
                        fontFamily: 'DM Sans',
                        fontSize: 9,
                        color: _kMutedLt),
                    overflow: TextOverflow.ellipsis),
              ],
            ),
          ),
        ]),
      );
}

// ─────────────────────────────────────────────────────────────────────────────
// Role pill badge
// ─────────────────────────────────────────────────────────────────────────────
class _RolePill extends StatelessWidget {
  final String label;
  final Color color;
  const _RolePill(this.label, this.color);

  @override
  Widget build(BuildContext context) => Container(
        padding:
            const EdgeInsets.symmetric(horizontal: 7, vertical: 2),
        decoration: BoxDecoration(
          color: color.withOpacity(0.1),
          border: Border.all(color: color.withOpacity(0.3)),
          borderRadius: BorderRadius.circular(6),
        ),
        child: Text(label,
            style: TextStyle(
                fontFamily: 'DM Sans',
                fontSize: 9,
                fontWeight: FontWeight.w800,
                color: color)),
      );
}

// ─────────────────────────────────────────────────────────────────────────────
// Role dropdown (inline select for user rows)
// ─────────────────────────────────────────────────────────────────────────────
class _RoleDropdown extends StatelessWidget {
  final String value;
  final bool saving;
  final ValueChanged<String?> onChanged;
  const _RoleDropdown({
    required this.value,
    required this.saving,
    required this.onChanged,
  });

  Color _color(String r) => switch (r) {
        'admin'          => _kRed,
        'author'         => _kBlue,
        'publisher'      => _kPurple,
        'editor'         => _kAmber,
        'moderator'      => _kGreen,
        'corporate_user' => const Color(0xFF4F46E5),
        _                => _kMuted,
      };

  @override
  Widget build(BuildContext context) {
    final c = _color(value);
    return saving
        ? SizedBox(
            width: 16, height: 16,
            child: CircularProgressIndicator(
                strokeWidth: 2, color: c),
          )
        : DropdownButton<String>(
            value: value,
            isDense: true,
            underline: const SizedBox.shrink(),
            style: TextStyle(
                fontFamily: 'DM Sans',
                fontSize: 11,
                fontWeight: FontWeight.w700,
                color: c),
            onChanged: onChanged,
            items: _roles
                .map((r) => DropdownMenuItem(
                      value: r,
                      child: Text(r,
                          style: TextStyle(
                              fontFamily: 'DM Sans',
                              fontSize: 12,
                              fontWeight: FontWeight.w600,
                              color: _color(r))),
                    ))
                .toList(),
          );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Status pill
// ─────────────────────────────────────────────────────────────────────────────
class _StatusPill extends StatelessWidget {
  final String status;
  const _StatusPill(this.status);

  Color get _color => switch (status) {
        'published' || 'approved' || 'completed' => _kGreen,
        'rejected'  || 'cancelled'               => _kRed,
        'under_review'                           => _kBlue,
        'pending'                                => _kAmber,
        _                                        => _kMuted,
      };

  @override
  Widget build(BuildContext context) => Container(
        padding:
            const EdgeInsets.symmetric(horizontal: 7, vertical: 2),
        decoration: BoxDecoration(
          color: _color.withOpacity(0.1),
          borderRadius: BorderRadius.circular(6),
        ),
        child: Text(
          status.replaceAll('_', ' '),
          style: TextStyle(
              fontFamily: 'DM Sans',
              fontSize: 10,
              fontWeight: FontWeight.w700,
              color: _color),
        ),
      );
}

// ─────────────────────────────────────────────────────────────────────────────
// Action button (Approve / Review / Reject)
// ─────────────────────────────────────────────────────────────────────────────
class _ActionBtn extends StatelessWidget {
  final String label;
  final IconData icon;
  final Color color;
  final VoidCallback onTap;
  const _ActionBtn(
      {required this.label,
      required this.icon,
      required this.color,
      required this.onTap});

  @override
  Widget build(BuildContext context) => GestureDetector(
        onTap: onTap,
        child: Container(
          padding: const EdgeInsets.symmetric(vertical: 8),
          decoration: BoxDecoration(
            color: color.withOpacity(0.08),
            border: Border.all(color: color.withOpacity(0.25)),
            borderRadius: BorderRadius.circular(8),
          ),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(icon, size: 13, color: color),
              const SizedBox(width: 5),
              Text(label,
                  style: TextStyle(
                      fontFamily: 'DM Sans',
                      fontSize: 12,
                      fontWeight: FontWeight.w700,
                      color: color)),
            ],
          ),
        ),
      );
}

// ─────────────────────────────────────────────────────────────────────────────
// Small outlined button (header actions)
// ─────────────────────────────────────────────────────────────────────────────
class _SmallBtn extends StatelessWidget {
  final String label;
  final IconData icon;
  final VoidCallback onTap;
  const _SmallBtn(
      {required this.label, required this.icon, required this.onTap});

  @override
  Widget build(BuildContext context) => GestureDetector(
        onTap: onTap,
        child: Container(
          padding:
              const EdgeInsets.symmetric(horizontal: 12, vertical: 7),
          decoration: BoxDecoration(
            border: Border.all(color: _kBorder),
            borderRadius: BorderRadius.circular(8),
          ),
          child: Row(mainAxisSize: MainAxisSize.min, children: [
            Icon(icon, size: 14, color: _kMuted),
            const SizedBox(width: 5),
            Text(label,
                style: const TextStyle(
                    fontFamily: 'DM Sans',
                    fontSize: 12,
                    color: _kMuted)),
          ]),
        ),
      );
}

// ─────────────────────────────────────────────────────────────────────────────
// Hero outline button (charcoal banner)
// ─────────────────────────────────────────────────────────────────────────────
class _HeroBtnOutline extends StatelessWidget {
  final String label;
  final IconData icon;
  final VoidCallback onTap;
  const _HeroBtnOutline(
      {required this.label, required this.icon, required this.onTap});

  @override
  Widget build(BuildContext context) => GestureDetector(
        onTap: onTap,
        child: Container(
          padding:
              const EdgeInsets.symmetric(horizontal: 12, vertical: 7),
          decoration: BoxDecoration(
            border: Border.all(color: Colors.white.withOpacity(0.2)),
            borderRadius: BorderRadius.circular(8),
          ),
          child: Row(mainAxisSize: MainAxisSize.min, children: [
            Icon(icon, size: 14, color: Colors.white70),
            const SizedBox(width: 5),
            Text(label,
                style: const TextStyle(
                    fontFamily: 'DM Sans',
                    fontSize: 12,
                    color: Colors.white70)),
          ]),
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
          borderRadius: BorderRadius.circular(_kCard),
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
// Rejection overlay (Stack-based, not a Dialog)
// ─────────────────────────────────────────────────────────────────────────────
class _RejectOverlay extends StatelessWidget {
  final Map<String, dynamic> pub;
  final TextEditingController ctrl;
  final bool processing;
  final VoidCallback onConfirm, onCancel;
  const _RejectOverlay({
    required this.pub,
    required this.ctrl,
    required this.processing,
    required this.onConfirm,
    required this.onCancel,
  });

  @override
  Widget build(BuildContext context) => GestureDetector(
        onTap: onCancel,
        child: Container(
          color: Colors.black.withOpacity(0.4),
          alignment: Alignment.center,
          child: GestureDetector(
            onTap: () {},
            child: Container(
              margin: const EdgeInsets.all(24),
              padding: const EdgeInsets.all(24),
              decoration: BoxDecoration(
                color: _kWhite,
                borderRadius: BorderRadius.circular(20),
                boxShadow: [
                  BoxShadow(
                    color: Colors.black.withOpacity(0.15),
                    blurRadius: 24,
                  ),
                ],
              ),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text('Reject Submission',
                      style: TextStyle(
                        fontFamily: 'PlayfairDisplay',
                        fontSize: 18,
                        fontWeight: FontWeight.w700,
                        color: Color(0xFF1F2937),
                      )),
                  const SizedBox(height: 4),
                  Text(
                    '"${pub['title']}" by ${pub['author_name'] ?? '—'}',
                    style: const TextStyle(
                        fontFamily: 'DM Sans',
                        fontSize: 13,
                        color: _kMuted),
                  ),
                  const SizedBox(height: 16),
                  TextField(
                    controller: ctrl,
                    maxLines: 4,
                    style: const TextStyle(
                        fontFamily: 'DM Sans', fontSize: 13),
                    decoration: InputDecoration(
                      hintText:
                          'Provide feedback to the author (optional but recommended)…',
                      hintStyle: const TextStyle(
                          fontFamily: 'DM Sans',
                          fontSize: 13,
                          color: _kMutedLt),
                      filled: true,
                      fillColor: const Color(0xFFF9FAFB),
                      border: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(10),
                          borderSide:
                              const BorderSide(color: _kBorder)),
                      enabledBorder: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(10),
                          borderSide:
                              const BorderSide(color: _kBorder)),
                      focusedBorder: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(10),
                          borderSide:
                              const BorderSide(color: _kRed, width: 1.5)),
                      contentPadding: const EdgeInsets.all(14),
                    ),
                  ),
                  const SizedBox(height: 16),
                  Row(children: [
                    Expanded(
                      child: OutlinedButton(
                        onPressed: onCancel,
                        style: OutlinedButton.styleFrom(
                          foregroundColor: const Color(0xFF1F2937),
                          side: const BorderSide(color: _kBorder),
                          shape: RoundedRectangleBorder(
                              borderRadius:
                                  BorderRadius.circular(8)),
                          padding: const EdgeInsets.symmetric(
                              vertical: 12),
                          textStyle: const TextStyle(
                              fontFamily: 'DM Sans'),
                        ),
                        child: const Text('Cancel'),
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: ElevatedButton(
                        onPressed:
                            processing ? null : onConfirm,
                        style: ElevatedButton.styleFrom(
                          backgroundColor: _kRed,
                          foregroundColor: _kWhite,
                          elevation: 0,
                          shape: RoundedRectangleBorder(
                              borderRadius:
                                  BorderRadius.circular(8)),
                          padding: const EdgeInsets.symmetric(
                              vertical: 12),
                          textStyle: const TextStyle(
                              fontFamily: 'DM Sans',
                              fontWeight: FontWeight.w700),
                        ),
                        child: processing
                            ? const SizedBox(
                                width: 18,
                                height: 18,
                                child: CircularProgressIndicator(
                                    strokeWidth: 2,
                                    color: _kWhite))
                            : const Text('Confirm Rejection'),
                      ),
                    ),
                  ]),
                ],
              ),
            ),
          ),
        ),
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
          Text(label,
              style: TextStyle(
                  fontFamily: 'DM Sans',
                  fontSize: 11,
                  color: c,
                  fontWeight: active
                      ? FontWeight.w700
                      : FontWeight.normal)),
        ],
      ),
    );
  }
}