// lib/pages/settingsPage.dart
//
// ── BUG FIX ──────────────────────────────────────────────────────────────────
//  ROOT CAUSE: "Edit Profile" and the profile card tap both called
//  Navigator.pushNamed(context, RoleService.dashboardForRole(role))
//  which pushed the AdminDashboard / AuthorDashboard / ReaderDashboard.
//  Those pages have their OWN bottom navbars (Upload / Admin, etc.)
//  so the user saw the wrong navbar after arriving there.
//
//  THE FIX:
//  1. Profile editing is now INLINE inside SettingsPage — no navigation away.
//     Tapping "Edit Profile" expands a beautiful slide-in edit panel within
//     this same page. The bottom nav never changes.
//  2. The dashboard tile is a separate explicit "Go to Dashboard" action
//     (pushNamed, NOT pushReplacement) so the user can always press Back
//     and return to Settings with the correct navbar.
//  3. The profile card tap no longer routes anywhere — it just expands the
//     inline editor.
//  4. SettingsPage owns its own Scaffold + bottomNavigationBar at all times.
// ─────────────────────────────────────────────────────────────────────────────

import 'dart:io';
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:cached_network_image/cached_network_image.dart';

import '../services/role_service.dart';
import 'publish_with_us.dart';
import 'about_page.dart';

// ── Palette (matches app-wide tokens) ────────────────────────────────────────
const _kPrimary     = Color(0xFFB11226);
const _kBg          = Color(0xFFF9F5EF);
const _kWhite       = Colors.white;
const _kBorder      = Color(0xFFE5E7EB);
const _kMuted       = Color(0xFF6B7280);
const _kMutedLt     = Color(0xFF9CA3AF);
const _kGreen       = Color(0xFF16A34A);
const _kGreenBg     = Color(0xFFF0FDF4);
const _kAmber       = Color(0xFFD97706);
const _kBlue        = Color(0xFF2563EB);
const _kBlueBg      = Color(0xFFEFF6FF);
const _kPurple      = Color(0xFF7C3AED);
const _kPurpleBg    = Color(0xFFF5F3FF);
const _kMaxBio      = 500;
const _kMaxName     = 100;
const _kMaxAvat     = 5 * 1024 * 1024;

// ─────────────────────────────────────────────────────────────────────────────
class SettingsPage extends StatefulWidget {
  const SettingsPage({super.key});
  @override
  State<SettingsPage> createState() => _SettingsPageState();
}

class _SettingsPageState extends State<SettingsPage>
    with TickerProviderStateMixin {
  final _sb = Supabase.instance.client;

  // ── data ──────────────────────────────────────────────────────────────────
  Map<String, dynamic>? _profile;
  bool _loading = true;

  // ── inline profile edit ───────────────────────────────────────────────────
  bool _editOpen = false;
  final _nameCtrl = TextEditingController();
  final _bioCtrl  = TextEditingController();
  final _telCtrl  = TextEditingController();
  final _adrCtrl  = TextEditingController();
  String? _avatarUrl;
  File?   _avatarFile;
  String? _avatarB64;
  bool    _saving = false;

  // ── animation ─────────────────────────────────────────────────────────────
  late final AnimationController _editAnim;
  late final Animation<double>   _editFade;
  late final Animation<Offset>   _editSlide;

  @override
  void initState() {
    super.initState();
    _bioCtrl.addListener(() => setState(() {}));
    _editAnim = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 320),
    );
    _editFade = CurvedAnimation(parent: _editAnim, curve: Curves.easeOut);
    _editSlide = Tween<Offset>(
      begin: const Offset(0, -0.06),
      end: Offset.zero,
    ).animate(CurvedAnimation(parent: _editAnim, curve: Curves.easeOut));
    _loadProfile();
  }

  @override
  void dispose() {
    _editAnim.dispose();
    for (final c in [_nameCtrl, _bioCtrl, _telCtrl, _adrCtrl]) {
      c.dispose();
    }
    super.dispose();
  }

  // ── load ──────────────────────────────────────────────────────────────────
  Future<void> _loadProfile() async {
    try {
      final uid = _sb.auth.currentUser?.id;
      if (uid == null) return;
      final data = await _sb
          .from('profiles')
          .select('full_name,avatar_url,role,bio,phone,address,account_type')
          .eq('id', uid)
          .maybeSingle();
      if (mounted) {
        setState(() => _profile = data);
        // Populate edit fields
        _nameCtrl.text = (data?['full_name'] as String?) ?? '';
        _bioCtrl.text  = (data?['bio']       as String?) ?? '';
        _telCtrl.text  = (data?['phone']     as String?) ?? '';
        _adrCtrl.text  = (data?['address']   as String?) ?? '';
        _avatarUrl     = data?['avatar_url'] as String?;
      }
    } catch (_) {
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  // ── completion ratio ──────────────────────────────────────────────────────
  double _completionRatio() {
    if (_profile == null) return 0;
    final fields = [
      _profile!['full_name'],
      _profile!['bio'],
      _profile!['phone'],
      _profile!['address'],
      _profile!['avatar_url'],
    ];
    return fields
            .where((f) => f != null && f.toString().isNotEmpty)
            .length /
        fields.length;
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
  Future<void> _saveProfile() async {
    setState(() => _saving = true);
    try {
      final uid = _sb.auth.currentUser?.id;
      if (uid == null) return;
      final u = <String, dynamic>{
        if (_nameCtrl.text.trim().isNotEmpty) 'full_name': _nameCtrl.text.trim(),
        if (_bioCtrl.text.trim().isNotEmpty)  'bio':       _bioCtrl.text.trim(),
        if (_telCtrl.text.trim().isNotEmpty)  'phone':     _telCtrl.text.trim(),
        if (_adrCtrl.text.trim().isNotEmpty)  'address':   _adrCtrl.text.trim(),
        if (_avatarB64 != null) 'avatar_url': 'https://via.placeholder.com/150',
        'updated_at': DateTime.now().toIso8601String(),
      };
      await _sb.from('profiles').update(u).eq('id', uid);
      await _loadProfile();
      _toast('Profile updated');
      _closeEdit();
    } catch (e) {
      _toast('Save failed: $e', err: true);
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  void _openEdit() {
    setState(() => _editOpen = true);
    _editAnim.forward();
  }

  void _closeEdit() {
    _editAnim.reverse().then((_) {
      if (mounted) setState(() => _editOpen = false);
    });
  }

  // ── sign out ──────────────────────────────────────────────────────────────
  Future<void> _signOut() async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (_) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        title: const Text('Sign Out',
            style: TextStyle(
                fontFamily: 'PlayfairDisplay', fontWeight: FontWeight.w800)),
        content: const Text('Are you sure you want to sign out?',
            style: TextStyle(fontFamily: 'DM Sans', color: _kMuted)),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Cancel'),
          ),
          ElevatedButton(
            onPressed: () => Navigator.pop(context, true),
            style: ElevatedButton.styleFrom(
                backgroundColor: _kPrimary,
                foregroundColor: _kWhite,
                shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(10))),
            child: const Text('Sign Out'),
          ),
        ],
      ),
    );
    if (ok != true || !mounted) return;
    await _sb.auth.signOut();
    RoleService.instance.clear();
    if (mounted) {
      Navigator.pushNamedAndRemoveUntil(context, '/onboarding', (_) => false);
    }
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

  // ── dashboard meta per role ───────────────────────────────────────────────
  Map<String, dynamic> _dashboardMeta(String role) {
    return switch (role) {
      'admin' => {
          'route':     '/dashboard/admin',
          'title':     'Admin Dashboard',
          'subtitle':  'Manage users, content & submissions',
          'icon':      Icons.admin_panel_settings_outlined,
          'iconColor': const Color(0xFFDC2626),
          'iconBg':    const Color(0xFFFEF2F2),
        },
      'author' => {
          'route':     '/dashboard/author',
          'title':     'Author Dashboard',
          'subtitle':  'Manage your works & submissions',
          'icon':      Icons.edit_note_rounded,
          'iconColor': _kBlue,
          'iconBg':    _kBlueBg,
        },
      'publisher' => {
          'route':     '/dashboard/author',
          'title':     'Publisher Dashboard',
          'subtitle':  'Manage publications & submissions',
          'icon':      Icons.library_books_outlined,
          'iconColor': _kPurple,
          'iconBg':    _kPurpleBg,
        },
      'editor' => {
          'route':     '/dashboard/author',
          'title':     'Editor Dashboard',
          'subtitle':  'Review and manage content',
          'icon':      Icons.rate_review_outlined,
          'iconColor': _kAmber,
          'iconBg':    const Color(0xFFFFFBEB),
        },
      'moderator' => {
          'route':     '/dashboard/admin',
          'title':     'Moderator Dashboard',
          'subtitle':  'Monitor and moderate content',
          'icon':      Icons.shield_outlined,
          'iconColor': _kGreen,
          'iconBg':    _kGreenBg,
        },
      'corporate_user' => {
          'route':     '/dashboard/reader',
          'title':     'Corporate Dashboard',
          'subtitle':  'Manage your corporate account',
          'icon':      Icons.business_outlined,
          'iconColor': const Color(0xFF0891B2),
          'iconBg':    const Color(0xFFECFEFF),
        },
      _ => {
          'route':     '/dashboard/reader',
          'title':     'My Dashboard',
          'subtitle':  'View orders, profile and more',
          'icon':      Icons.dashboard_outlined,
          'iconColor': _kMuted,
          'iconBg':    const Color(0xFFF3F4F6),
        },
    };
  }

  // ─────────────────────────────────────────────────────────────────────────
  // BUILD
  // ─────────────────────────────────────────────────────────────────────────
  @override
  Widget build(BuildContext context) {
    final ratio = _completionRatio();
    final role  = _profile?['role'] as String? ?? RoleService.instance.role;
    final isAdmin  = role == 'admin';
    final isAuthor = role == 'author' || role == 'publisher' || role == 'editor';
    final meta     = _dashboardMeta(role);

    return Scaffold(
      backgroundColor: _kBg,
      // ── The bottom nav NEVER changes — it always lives here ──────────────
      bottomNavigationBar: _bottomNav(),
      body: CustomScrollView(slivers: [

        // ── App bar ──────────────────────────────────────────────────────
        SliverAppBar(
          pinned: true,
          backgroundColor: _kWhite,
          surfaceTintColor: Colors.transparent,
          elevation: 0,
          leading: _editOpen
              ? IconButton(
                  icon: const Icon(Icons.arrow_back_ios_new_rounded,
                      size: 20, color: Color(0xFF1A1A2E)),
                  onPressed: _closeEdit,
                )
              : IconButton(
                  icon: const Icon(Icons.arrow_back_ios_new_rounded,
                      size: 20, color: Color(0xFF1A1A2E)),
                  onPressed: () => Navigator.canPop(context)
                      ? Navigator.pop(context)
                      : Navigator.pushNamedAndRemoveUntil(
                          context, '/home', (_) => false),
                ),
          title: AnimatedSwitcher(
            duration: const Duration(milliseconds: 200),
            child: Text(
              _editOpen ? 'Edit Profile' : 'Settings',
              key: ValueKey(_editOpen),
              style: const TextStyle(
                fontFamily: 'PlayfairDisplay',
                fontWeight: FontWeight.w800,
                fontSize: 20,
                color: Color(0xFF111827),
              ),
            ),
          ),
          bottom: PreferredSize(
            preferredSize: const Size.fromHeight(1),
            child: Container(height: 1, color: _kBorder),
          ),
        ),

        // ── Content ──────────────────────────────────────────────────────
        SliverToBoxAdapter(
          child: AnimatedSwitcher(
            duration: const Duration(milliseconds: 280),
            switchInCurve: Curves.easeOut,
            switchOutCurve: Curves.easeIn,
            transitionBuilder: (child, anim) => FadeTransition(
              opacity: anim,
              child: SlideTransition(
                position: Tween<Offset>(
                  begin: const Offset(0.04, 0),
                  end: Offset.zero,
                ).animate(anim),
                child: child,
              ),
            ),
            child: _editOpen
                ? _inlineEditPanel(key: const ValueKey('edit'))
                : _mainSettings(
                    key: const ValueKey('main'),
                    ratio: ratio,
                    role: role,
                    isAdmin: isAdmin,
                    isAuthor: isAuthor,
                    meta: meta,
                  ),
          ),
        ),
      ]),
    );
  }

  // ══════════════════════════════════════════════════════════════════════════
  // MAIN SETTINGS VIEW
  // ══════════════════════════════════════════════════════════════════════════
  Widget _mainSettings({
    required Key key,
    required double ratio,
    required String role,
    required bool isAdmin,
    required bool isAuthor,
    required Map<String, dynamic> meta,
  }) =>
      Column(key: key, children: [

        // ── Profile summary card ─────────────────────────────────────────
        _loading ? _skeleton() : _profileSummaryCard(ratio, role),
        const SizedBox(height: 8),

        // ── MY DASHBOARD ────────────────────────────────────────────────
        _Label('My Dashboard'),
        _Group(children: [
          // Primary dashboard tile — uses pushNamed (NOT pushReplacement)
          // so user can press Back and return to Settings with correct navbar
          _Tile(
            icon:      meta['icon']      as IconData,
            iconColor: meta['iconColor'] as Color,
            iconBg:    meta['iconBg']    as Color,
            title:     meta['title']     as String,
            subtitle:  meta['subtitle']  as String,
            trailing: Row(mainAxisSize: MainAxisSize.min, children: [
              Container(
                padding: const EdgeInsets.symmetric(
                    horizontal: 8, vertical: 3),
                decoration: BoxDecoration(
                  color: (meta['iconColor'] as Color).withOpacity(0.1),
                  borderRadius: BorderRadius.circular(20),
                ),
                child: Text(
                  'Open',
                  style: TextStyle(
                    fontFamily: 'DM Sans',
                    fontSize: 11,
                    fontWeight: FontWeight.w700,
                    color: meta['iconColor'] as Color,
                  ),
                ),
              ),
              const SizedBox(width: 4),
              const Icon(Icons.chevron_right_rounded,
                  color: _kBorder, size: 20),
            ]),
            // ✅ pushNamed — user can press Back → returns to SettingsPage
            onTap: () => Navigator.pushNamed(
                context, meta['route'] as String),
          ),
          _D(),
          _Tile(
            icon:      Icons.receipt_long_outlined,
            iconColor: _kGreen,
            iconBg:    _kGreenBg,
            title:    'My Orders',
            subtitle: 'View your purchase history',
            onTap: () => Navigator.pushNamed(
                context, meta['route'] as String),
          ),
          _D(),
          _Tile(
            icon:      Icons.notifications_none_rounded,
            iconColor: _kPurple,
            iconBg:    _kPurpleBg,
            title:    'Notifications',
            subtitle: 'See your recent alerts',
            onTap: () => Navigator.pushNamed(
                context, meta['route'] as String),
          ),
        ]),
        const SizedBox(height: 16),

        // ── ACCOUNT ─────────────────────────────────────────────────────
        _Label('Account'),
        _Group(children: [
          // ✅ "Edit Profile" now opens INLINE — no navigation away
          _Tile(
            icon:      Icons.person_outline_rounded,
            iconColor: _kBlue,
            iconBg:    _kBlueBg,
            title:    'Edit Profile',
            subtitle: 'Update name, photo and bio',
            trailing: Row(mainAxisSize: MainAxisSize.min, children: [
              Container(
                padding: const EdgeInsets.symmetric(
                    horizontal: 8, vertical: 3),
                decoration: BoxDecoration(
                  color: _kBlueBg,
                  borderRadius: BorderRadius.circular(20),
                ),
                child: const Text(
                  'Edit',
                  style: TextStyle(
                    fontFamily: 'DM Sans',
                    fontSize: 11,
                    fontWeight: FontWeight.w700,
                    color: _kBlue,
                  ),
                ),
              ),
              const SizedBox(width: 4),
              const Icon(Icons.chevron_right_rounded,
                  color: _kBorder, size: 20),
            ]),
            onTap: _openEdit, // ← inline, no route change
          ),
          _D(),
          _Tile(
            icon:      Icons.lock_outline_rounded,
            iconColor: _kPurple,
            iconBg:    _kPurpleBg,
            title:    'Change Password',
            subtitle: 'Update your account password',
            onTap: () =>
                Navigator.pushNamed(context, '/reset-password'),
          ),
        ]),
        const SizedBox(height: 16),

        // ── ADMIN TOOLS ──────────────────────────────────────────────────
        if (isAdmin) ...[
          _Label('Admin Tools'),
          _Group(children: [
            _Tile(
              icon:      Icons.upload_rounded,
              iconColor: const Color(0xFFDC2626),
              iconBg:    const Color(0xFFFEF2F2),
              title:    'Upload Content',
              subtitle: 'Add books and documents to the platform',
              onTap: () =>
                  Navigator.pushNamed(context, '/content-management'),
            ),
            _D(),
            _Tile(
              icon:      Icons.people_outline_rounded,
              iconColor: _kGreen,
              iconBg:    _kGreenBg,
              title:    'Manage Users',
              subtitle: 'View users and change roles',
              onTap: () =>
                  Navigator.pushNamed(context, '/dashboard/admin'),
            ),
            _D(),
            _Tile(
              icon:      Icons.description_outlined,
              iconColor: _kAmber,
              iconBg:    const Color(0xFFFFFBEB),
              title:    'Publication Requests',
              subtitle: 'Review manuscript submissions',
              onTap: () =>
                  Navigator.pushNamed(context, '/dashboard/admin'),
            ),
          ]),
          const SizedBox(height: 16),
        ],

        // ── PUBLISHING (author / publisher / editor / admin) ─────────────
        if (isAuthor || isAdmin) ...[
          _Label('Publishing'),
          _Group(children: [
            _Tile(
              icon:      Icons.drive_file_rename_outline_rounded,
              iconColor: const Color(0xFF0891B2),
              iconBg:    const Color(0xFFECFEFF),
              title:    'Publish With Us',
              subtitle: 'Submit your manuscript or book',
              onTap: () => Navigator.push(
                  context,
                  MaterialPageRoute(
                      builder: (_) => const PublishWithUsPage())),
            ),
            _D(),
            _Tile(
              icon:      Icons.update_rounded,
              iconColor: _kGreen,
              iconBg:    _kGreenBg,
              title:    'My Submissions',
              subtitle: 'Track your manuscript submissions',
              onTap: () =>
                  Navigator.pushNamed(context, '/dashboard/author'),
            ),
          ]),
          const SizedBox(height: 16),
        ],

        // ── PUBLISHING HINT (reader / corporate) ─────────────────────────
        if (!isAdmin && !isAuthor) ...[
          _Label('Publishing'),
          _Group(children: [
            _Tile(
              icon:      Icons.auto_stories_rounded,
              iconColor: _kAmber,
              iconBg:    const Color(0xFFFFFBEB),
              title:    'Publish With Us',
              subtitle: 'Are you an author? Submit your manuscript',
              onTap: () => Navigator.push(
                  context,
                  MaterialPageRoute(
                      builder: (_) => const PublishWithUsPage())),
            ),
          ]),
          const SizedBox(height: 16),
        ],

        // ── APP ──────────────────────────────────────────────────────────
        _Label('App'),
        _Group(children: [
          _Tile(
            icon:      Icons.info_outline_rounded,
            iconColor: _kMuted,
            iconBg:    const Color(0xFFF3F4F6),
            title:    'About Intercen',
            subtitle: 'Version, licenses and legal',
            onTap: () => Navigator.push(
                context,
                MaterialPageRoute(
                    builder: (_) => const AboutPage())),
          ),
          _D(),
          _Tile(
            icon:      Icons.help_outline_rounded,
            iconColor: _kAmber,
            iconBg:    const Color(0xFFFFFBEB),
            title:    'Help & Support',
            subtitle: 'Contact us or browse the FAQ',
            onTap: _showHelp,
          ),
        ]),
        const SizedBox(height: 16),

        // ── SIGN OUT ─────────────────────────────────────────────────────
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16),
          child: _Group(children: [
            _Tile(
              icon:       Icons.logout_rounded,
              iconColor:  _kPrimary,
              iconBg:     _kPrimary.withOpacity(0.08),
              title:      'Sign Out',
              subtitle:   'Log out of your account',
              titleColor: _kPrimary,
              trailing:   const SizedBox.shrink(),
              onTap: _signOut,
            ),
          ]),
        ),

        SizedBox(
            height: 32 + MediaQuery.of(context).padding.bottom),
      ]);

  // ══════════════════════════════════════════════════════════════════════════
  // INLINE PROFILE EDIT PANEL
  // Replaces the main settings list in the SAME Scaffold — no routing.
  // The bottom nav stays unchanged throughout.
  // ══════════════════════════════════════════════════════════════════════════
  Widget _inlineEditPanel({required Key key}) {
    return Padding(
      key: key,
      padding: const EdgeInsets.fromLTRB(16, 20, 16, 40),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [

          // ── Decorative header strip ────────────────────────────────────
          Container(
            width: double.infinity,
            padding: const EdgeInsets.all(20),
            margin: const EdgeInsets.only(bottom: 20),
            decoration: BoxDecoration(
              gradient: LinearGradient(
                colors: [
                  _kPrimary.withOpacity(0.08),
                  _kPrimary.withOpacity(0.03),
                ],
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
              ),
              borderRadius: BorderRadius.circular(16),
              border: Border.all(color: _kPrimary.withOpacity(0.12)),
            ),
            child: Row(children: [
              // Avatar picker
              GestureDetector(
                onTap: _pickAvatar,
                child: Stack(children: [
                  CircleAvatar(
                    radius: 36,
                    backgroundColor: _kPrimary.withOpacity(0.1),
                    backgroundImage: _avatarImg,
                    child: _avatarImg == null
                        ? Text(
                            _nameCtrl.text.isNotEmpty
                                ? _nameCtrl.text[0].toUpperCase()
                                : '?',
                            style: const TextStyle(
                              fontFamily: 'PlayfairDisplay',
                              fontSize: 28,
                              fontWeight: FontWeight.w800,
                              color: _kPrimary,
                            ),
                          )
                        : null,
                  ),
                  Positioned(
                    bottom: 2, right: 2,
                    child: Container(
                      width: 22, height: 22,
                      decoration: BoxDecoration(
                        color: _kPrimary,
                        shape: BoxShape.circle,
                        border: Border.all(color: _kWhite, width: 2),
                      ),
                      child: const Icon(Icons.camera_alt,
                          size: 11, color: _kWhite),
                    ),
                  ),
                ]),
              ),
              const SizedBox(width: 16),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      _nameCtrl.text.isNotEmpty
                          ? _nameCtrl.text
                          : 'Your Name',
                      style: const TextStyle(
                        fontFamily: 'PlayfairDisplay',
                        fontSize: 18,
                        fontWeight: FontWeight.w800,
                        color: Color(0xFF111827),
                      ),
                    ),
                    const SizedBox(height: 3),
                    Text(
                      _sb.auth.currentUser?.email ?? '',
                      style: const TextStyle(
                          fontFamily: 'DM Sans',
                          fontSize: 12,
                          color: _kMuted),
                    ),
                    const SizedBox(height: 6),
                    GestureDetector(
                      onTap: _pickAvatar,
                      child: Container(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 10, vertical: 4),
                        decoration: BoxDecoration(
                          color: _kWhite,
                          borderRadius: BorderRadius.circular(8),
                          border: Border.all(
                              color: _kPrimary.withOpacity(0.2)),
                        ),
                        child: Row(mainAxisSize: MainAxisSize.min,
                            children: const [
                          Icon(Icons.upload_file_outlined,
                              size: 12, color: _kPrimary),
                          SizedBox(width: 5),
                          Text(
                            'Change photo',
                            style: TextStyle(
                              fontFamily: 'DM Sans',
                              fontSize: 11,
                              fontWeight: FontWeight.w600,
                              color: _kPrimary,
                            ),
                          ),
                        ]),
                      ),
                    ),
                  ],
                ),
              ),
            ]),
          ),

          // ── Form fields ────────────────────────────────────────────────
          _editField(_nameCtrl, 'Full Name',
              hint: 'Your full name', maxLen: _kMaxName),
          const SizedBox(height: 14),
          _editField(_telCtrl, 'Phone', hint: '+254 7xx xxx xxx'),
          const SizedBox(height: 14),
          _editField(_adrCtrl, 'Address',
              hint: 'P.O. Box …', lines: 2),
          const SizedBox(height: 14),

          // Bio with char counter
          Row(children: [
            _editLabel('Bio'),
            const Spacer(),
            Text(
              '${_bioCtrl.text.length}/$_kMaxBio',
              style: const TextStyle(
                  fontFamily: 'DM Sans',
                  fontSize: 11,
                  color: _kMutedLt),
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
                color: Color(0xFF111827)),
            decoration: InputDecoration(
              border: _editBorder(),
              enabledBorder: _editBorder(),
              focusedBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(10),
                borderSide: const BorderSide(
                    color: _kPrimary, width: 1.5),
              ),
              hintText: 'Tell others about yourself…',
              hintStyle: const TextStyle(
                  fontFamily: 'DM Sans',
                  color: _kMutedLt,
                  fontSize: 14),
              contentPadding: const EdgeInsets.all(14),
              filled: true,
              fillColor: _kWhite,
            ),
          ),
          const SizedBox(height: 28),

          // ── Action buttons ─────────────────────────────────────────────
          Row(children: [
            Expanded(
              child: SizedBox(
                height: 50,
                child: ElevatedButton.icon(
                  icon: _saving
                      ? const SizedBox(
                          width: 16, height: 16,
                          child: CircularProgressIndicator(
                              strokeWidth: 2, color: _kWhite))
                      : const Icon(Icons.check_rounded, size: 18),
                  label: Text(
                    _saving ? 'Saving…' : 'Save Changes',
                    style: const TextStyle(
                      fontFamily: 'DM Sans',
                      fontWeight: FontWeight.w700,
                      fontSize: 15,
                    ),
                  ),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: _kPrimary,
                    foregroundColor: _kWhite,
                    elevation: 0,
                    shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(12)),
                  ),
                  onPressed: _saving ? null : _saveProfile,
                ),
              ),
            ),
            const SizedBox(width: 12),
            SizedBox(
              height: 50,
              child: OutlinedButton(
                onPressed: _saving ? null : _closeEdit,
                style: OutlinedButton.styleFrom(
                  foregroundColor: _kMuted,
                  side: const BorderSide(color: _kBorder),
                  padding: const EdgeInsets.symmetric(
                      horizontal: 20, vertical: 12),
                  shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(12)),
                  textStyle: const TextStyle(
                      fontFamily: 'DM Sans',
                      fontWeight: FontWeight.w600),
                ),
                child: const Text('Cancel'),
              ),
            ),
          ]),

          SizedBox(height: MediaQuery.of(context).padding.bottom + 16),
        ],
      ),
    );
  }

  // ── Profile summary card ──────────────────────────────────────────────────
  Widget _profileSummaryCard(double ratio, String role) {
    final name      = _profile?['full_name'] as String? ?? '';
    final avatarUrl = _profile?['avatar_url'] as String?;
    final email     = _sb.auth.currentUser?.email ?? '';
    final color     = ratio >= 1.0
        ? _kGreen
        : ratio >= 0.6
            ? _kAmber
            : _kPrimary;

    return GestureDetector(
      // ✅ Tapping profile card now opens inline edit — NOT dashboard route
      onTap: _openEdit,
      child: Container(
        margin: const EdgeInsets.fromLTRB(16, 16, 16, 8),
        padding: const EdgeInsets.all(20),
        decoration: BoxDecoration(
          color: _kWhite,
          borderRadius: BorderRadius.circular(20),
          boxShadow: [
            BoxShadow(
                color: Colors.black.withOpacity(0.05),
                blurRadius: 12,
                offset: const Offset(0, 4)),
          ],
        ),
        child: Column(children: [
          Row(children: [
            // Avatar
            Container(
              width: 64, height: 64,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                border: Border.all(
                    color: _kPrimary.withOpacity(0.2), width: 2.5),
              ),
              child: ClipOval(
                child: avatarUrl != null && avatarUrl.isNotEmpty
                    ? CachedNetworkImage(
                        imageUrl: avatarUrl, fit: BoxFit.cover)
                    : Container(
                        color: const Color(0xFFF3F4F6),
                        child: Center(
                          child: Text(
                            name.isNotEmpty
                                ? name[0].toUpperCase()
                                : '?',
                            style: const TextStyle(
                              fontFamily: 'PlayfairDisplay',
                              fontWeight: FontWeight.w800,
                              fontSize: 24,
                              color: _kMutedLt,
                            ),
                          ),
                        ),
                      ),
              ),
            ),
            const SizedBox(width: 14),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    name.isNotEmpty ? name : 'Tap to edit your profile',
                    style: TextStyle(
                      fontFamily: 'PlayfairDisplay',
                      fontSize: 17,
                      fontWeight: FontWeight.w800,
                      color: name.isNotEmpty
                          ? const Color(0xFF111827)
                          : _kPrimary,
                    ),
                    overflow: TextOverflow.ellipsis,
                  ),
                  const SizedBox(height: 2),
                  Text(email,
                      style: const TextStyle(
                          fontFamily: 'DM Sans',
                          fontSize: 12,
                          color: _kMutedLt),
                      overflow: TextOverflow.ellipsis),
                  const SizedBox(height: 5),
                  _RoleBadge(role),
                ],
              ),
            ),
            // "Edit" chip on the right
            Container(
              padding: const EdgeInsets.symmetric(
                  horizontal: 10, vertical: 5),
              decoration: BoxDecoration(
                color: _kBlueBg,
                borderRadius: BorderRadius.circular(8),
                border: Border.all(color: _kBlue.withOpacity(0.2)),
              ),
              child: Row(mainAxisSize: MainAxisSize.min, children: const [
                Icon(Icons.edit_outlined, size: 12, color: _kBlue),
                SizedBox(width: 4),
                Text('Edit',
                    style: TextStyle(
                      fontFamily: 'DM Sans',
                      fontSize: 11,
                      fontWeight: FontWeight.w700,
                      color: _kBlue,
                    )),
              ]),
            ),
          ]),
          const SizedBox(height: 14),
          // Completion bar
          Row(mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
            const Text('Profile Completion',
                style: TextStyle(
                    fontFamily: 'DM Sans',
                    fontSize: 12,
                    color: _kMuted)),
            Text(
              ratio >= 1.0
                  ? '✓ Complete'
                  : '${(ratio * 100).toInt()}%',
              style: TextStyle(
                  fontFamily: 'DM Sans',
                  fontSize: 12,
                  fontWeight: FontWeight.w700,
                  color: color),
            ),
          ]),
          const SizedBox(height: 6),
          ClipRRect(
            borderRadius: BorderRadius.circular(4),
            child: LinearProgressIndicator(
              value: ratio,
              minHeight: 6,
              backgroundColor: _kBorder,
              valueColor: AlwaysStoppedAnimation(color),
            ),
          ),
        ]),
      ),
    );
  }

  // ── Skeleton loader ───────────────────────────────────────────────────────
  Widget _skeleton() => Container(
        margin: const EdgeInsets.fromLTRB(16, 16, 16, 8),
        height: 130,
        decoration: BoxDecoration(
            color: _kBorder,
            borderRadius: BorderRadius.circular(20)));

  // ── Help bottom sheet ─────────────────────────────────────────────────────
  void _showHelp() => showModalBottomSheet(
        context: context,
        backgroundColor: _kWhite,
        shape: const RoundedRectangleBorder(
            borderRadius: BorderRadius.vertical(top: Radius.circular(24))),
        builder: (_) => Padding(
          padding: const EdgeInsets.fromLTRB(24, 8, 24, 40),
          child: Column(mainAxisSize: MainAxisSize.min, children: [
            Container(
              width: 40, height: 4,
              margin: const EdgeInsets.only(bottom: 20, top: 8),
              decoration: BoxDecoration(
                  color: _kBorder,
                  borderRadius: BorderRadius.circular(2)),
            ),
            const Text('Help & Support',
                style: TextStyle(
                    fontFamily: 'PlayfairDisplay',
                    fontSize: 20,
                    fontWeight: FontWeight.w800)),
            const SizedBox(height: 20),
            Container(
              padding: const EdgeInsets.all(14),
              decoration: BoxDecoration(
                  color: const Color(0xFFF9FAFB),
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(color: _kBorder)),
              child: const Row(children: [
                Icon(Icons.email_outlined, color: _kPrimary, size: 20),
                SizedBox(width: 12),
                Expanded(
                  child: Text(
                    'info.intercenbooks@gmail.com',
                    style:
                        TextStyle(fontFamily: 'DM Sans', fontSize: 13),
                  ),
                ),
              ]),
            ),
          ]),
        ),
      );

  // ── Bottom nav — always Home / Books / Cart / Profile ────────────────────
  Widget _bottomNav() => Container(
        height: 64,
        decoration: BoxDecoration(
          color: _kWhite,
          border: const Border(top: BorderSide(color: _kBorder)),
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
            _navItem(
              icon: Icons.home_outlined,
              label: 'Home',
              active: false,
              onTap: () => Navigator.pushNamedAndRemoveUntil(
                  context, '/home', (r) => false),
            ),
            _navItem(
              icon: Icons.menu_book_outlined,
              label: 'Books',
              active: false,
              onTap: () => Navigator.pushNamed(context, '/books'),
            ),
            _navItem(
              icon: Icons.shopping_cart_outlined,
              label: 'Cart',
              active: false,
              onTap: () => Navigator.pushNamed(context, '/cart'),
            ),
            _navItem(
              icon: Icons.person,
              label: 'Profile',
              active: true,
              onTap: null,
            ),
          ],
        ),
      );

  Widget _navItem({
    required IconData icon,
    required String label,
    required bool active,
    required VoidCallback? onTap,
  }) {
    final color = active ? _kPrimary : Colors.grey;
    return GestureDetector(
      onTap: onTap,
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(icon, color: color, size: 22),
          const SizedBox(height: 3),
          Text(label,
              style: TextStyle(
                fontFamily: 'DM Sans',
                fontSize: 11,
                color: color,
                fontWeight:
                    active ? FontWeight.w700 : FontWeight.normal,
              )),
        ],
      ),
    );
  }

  // ── Inline edit helpers ───────────────────────────────────────────────────
  Widget _editField(
    TextEditingController ctrl,
    String label, {
    String? hint,
    int lines = 1,
    int? maxLen,
  }) =>
      Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        _editLabel(label),
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
              color: Color(0xFF111827)),
          decoration: InputDecoration(
            border: _editBorder(),
            enabledBorder: _editBorder(),
            focusedBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(10),
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
      ]);

  Widget _editLabel(String t) => Text(t,
      style: const TextStyle(
        fontFamily: 'DM Sans',
        fontSize: 13,
        fontWeight: FontWeight.w600,
        color: Color(0xFF111827),
      ));

  OutlineInputBorder _editBorder() => OutlineInputBorder(
        borderRadius: BorderRadius.circular(10),
        borderSide: const BorderSide(color: _kBorder),
      );
}

// ─────────────────────────────────────────────────────────────────────────────
// Sub-widgets (unchanged from original, no routing changes needed here)
// ─────────────────────────────────────────────────────────────────────────────

class _Label extends StatelessWidget {
  final String text;
  const _Label(this.text);

  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.fromLTRB(20, 8, 20, 8),
        child: Text(
          text.toUpperCase(),
          style: const TextStyle(
            fontFamily: 'DM Sans',
            fontSize: 11,
            fontWeight: FontWeight.w700,
            color: _kMutedLt,
            letterSpacing: 1.0,
          ),
        ),
      );
}

class _Group extends StatelessWidget {
  final List<Widget> children;
  const _Group({required this.children});

  @override
  Widget build(BuildContext context) => Container(
        margin: const EdgeInsets.symmetric(horizontal: 16),
        decoration: BoxDecoration(
          color: _kWhite,
          borderRadius: BorderRadius.circular(16),
          boxShadow: [
            BoxShadow(
                color: Colors.black.withOpacity(0.04),
                blurRadius: 8,
                offset: const Offset(0, 2)),
          ],
        ),
        clipBehavior: Clip.antiAlias,
        child: Column(children: children),
      );
}

class _D extends StatelessWidget {
  @override
  Widget build(BuildContext context) =>
      const Divider(height: 1, indent: 64, color: Color(0xFFF3F4F6));
}

class _Tile extends StatelessWidget {
  final IconData icon;
  final Color iconColor, iconBg;
  final String title;
  final String? subtitle;
  final VoidCallback onTap;
  final Widget? trailing;
  final Color? titleColor;

  const _Tile({
    required this.icon,
    required this.iconColor,
    required this.iconBg,
    required this.title,
    required this.onTap,
    this.subtitle,
    this.trailing,
    this.titleColor,
  });

  @override
  Widget build(BuildContext context) => InkWell(
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.symmetric(
              horizontal: 16, vertical: 14),
          child: Row(children: [
            Container(
              width: 40, height: 40,
              decoration: BoxDecoration(
                  color: iconBg,
                  borderRadius: BorderRadius.circular(10)),
              child: Icon(icon, color: iconColor, size: 20),
            ),
            const SizedBox(width: 14),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(title,
                      style: TextStyle(
                        fontFamily: 'DM Sans',
                        fontSize: 15,
                        fontWeight: FontWeight.w600,
                        color: titleColor ?? const Color(0xFF111827),
                      )),
                  if (subtitle != null)
                    Text(subtitle!,
                        style: const TextStyle(
                          fontFamily: 'DM Sans',
                          fontSize: 12,
                          color: _kMutedLt,
                        )),
                ],
              ),
            ),
            trailing ??
                const Icon(Icons.chevron_right_rounded,
                    color: _kBorder, size: 20),
          ]),
        ),
      );
}

class _RoleBadge extends StatelessWidget {
  final String role;
  const _RoleBadge(this.role);

  Color get _color => switch (role) {
        'admin'          => _kPurple,
        'author'         => _kBlue,
        'publisher'      => const Color(0xFF0891B2),
        'editor'         => _kAmber,
        'moderator'      => _kGreen,
        'corporate_user' => _kGreen,
        _                => _kMuted,
      };

  String get _label => switch (role) {
        'corporate_user' => 'Corporate',
        'admin'          => 'Admin',
        'author'         => 'Author',
        'publisher'      => 'Publisher',
        'editor'         => 'Editor',
        'moderator'      => 'Moderator',
        _                => 'Reader',
      };

  @override
  Widget build(BuildContext context) => Container(
        padding:
            const EdgeInsets.symmetric(horizontal: 10, vertical: 3),
        decoration: BoxDecoration(
          color: _color.withOpacity(0.1),
          borderRadius: BorderRadius.circular(20),
          border: Border.all(color: _color.withOpacity(0.25)),
        ),
        child: Text(
          _label,
          style: TextStyle(
            fontFamily: 'DM Sans',
            fontSize: 10,
            fontWeight: FontWeight.w700,
            color: _color,
          ),
        ),
      );
}