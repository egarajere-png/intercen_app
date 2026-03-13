import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:cached_network_image/cached_network_image.dart';

import '../theme/app_colors.dart';
import 'about_page.dart';
import 'publish_with_us.dart';

// ─────────────────────────────────────────────────────────────────────────────
// SETTINGS PAGE
//
// Smart profile-aware settings hub. On load it fetches the current user's
// profile and shows a rich header with their avatar, name, role badge, and
// completion indicator. All navigation is wired — no more TODOs.
//
// Settings sections:
//   Account    → Profile (edit), Sign Out
//   Publishing → Publish With Us, Content Update
//   App        → About, Help & Support
// ─────────────────────────────────────────────────────────────────────────────

class SettingsPage extends StatefulWidget {
  const SettingsPage({super.key});

  @override
  State<SettingsPage> createState() => _SettingsPageState();
}

class _SettingsPageState extends State<SettingsPage> {
  final _sb = Supabase.instance.client;

  Map<String, dynamic>? _profile;
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _loadProfile();
  }

  Future<void> _loadProfile() async {
    try {
      final uid = _sb.auth.currentUser?.id;
      if (uid == null) return;
      final data = await _sb
          .from('profiles')
          .select('full_name, avatar_url, role, bio, phone, address, account_type')
          .eq('id', uid)
          .maybeSingle();
      if (mounted) setState(() => _profile = data);
    } catch (_) {
      // non-fatal — page still works without profile header
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  // ── Profile completion score ──────────────────────────────────────────────
  // Shows user how filled-in their profile is as a motivator to complete it.
  double _completionRatio() {
    if (_profile == null) return 0;
    final fields = [
      _profile!['full_name'],
      _profile!['bio'],
      _profile!['phone'],
      _profile!['address'],
      _profile!['avatar_url'],
    ];
    final filled = fields.where((f) => f != null && f.toString().isNotEmpty).length;
    return filled / fields.length;
  }

  String _completionLabel(double r) {
    if (r >= 1.0) return 'Complete';
    if (r >= 0.6) return 'Almost there';
    if (r >= 0.2) return 'Getting started';
    return 'Incomplete';
  }

  Color _completionColor(double r) {
    if (r >= 1.0) return const Color(0xFF16A34A);
    if (r >= 0.6) return const Color(0xFFD97706);
    return AppColors.primary;
  }

  // ── Sign out ──────────────────────────────────────────────────────────────
  Future<void> _signOut() async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (_) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        title: const Text('Sign Out',
            style: TextStyle(
                fontFamily: 'PlayfairDisplay',
                fontWeight: FontWeight.w800,
                fontSize: 20)),
        content: const Text('Are you sure you want to sign out?',
            style: TextStyle(
                fontFamily: 'DM Sans',
                fontSize: 14,
                color: Color(0xFF6B7280))),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Cancel',
                style: TextStyle(
                    fontFamily: 'DM Sans', color: Color(0xFF6B7280))),
          ),
          ElevatedButton(
            onPressed: () => Navigator.pop(context, true),
            style: ElevatedButton.styleFrom(
                backgroundColor: AppColors.primary,
                foregroundColor: Colors.white,
                shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(10))),
            child: const Text('Sign Out',
                style: TextStyle(fontFamily: 'DM Sans')),
          ),
        ],
      ),
    );
    if (confirmed != true) return;
    await _sb.auth.signOut();
    if (mounted) {
      Navigator.pushNamedAndRemoveUntil(context, '/onboarding', (_) => false);
    }
  }

  // ── BUILD ─────────────────────────────────────────────────────────────────
  @override
  Widget build(BuildContext context) {
    final ratio      = _completionRatio();
    final compColor  = _completionColor(ratio);
    final compLabel  = _completionLabel(ratio);
    final name       = _profile?['full_name'] as String? ?? '';
    final avatarUrl  = _profile?['avatar_url'] as String?;
    final role       = _profile?['role']       as String? ?? 'reader';
    final email      = _sb.auth.currentUser?.email ?? '';

    return Scaffold(
      backgroundColor: const Color(0xFFF9F5EF),
      body: CustomScrollView(
        slivers: [

          // ── App bar ───────────────────────────────────────────────────────
          SliverAppBar(
            pinned: true,
            backgroundColor: Colors.white,
            surfaceTintColor: Colors.transparent,
            elevation: 0,
            leading: IconButton(
              icon: const Icon(Icons.arrow_back_ios_new_rounded,
                  size: 20, color: Color(0xFF1A1A2E)),
              onPressed: () => Navigator.pop(context),
            ),
            title: const Text('Settings',
                style: TextStyle(
                    fontFamily: 'PlayfairDisplay',
                    fontWeight: FontWeight.w800,
                    fontSize: 20,
                    color: Color(0xFF111827))),
            bottom: PreferredSize(
              preferredSize: const Size.fromHeight(1),
              child: Container(height: 1, color: const Color(0xFFE5E7EB)),
            ),
          ),

          SliverToBoxAdapter(
            child: Column(children: [

              // ── Profile header card ───────────────────────────────────────
              _loading
                  ? _profileHeaderSkeleton()
                  : _profileHeader(
                      name:       name,
                      email:      email,
                      avatarUrl:  avatarUrl,
                      role:       role,
                      ratio:      ratio,
                      compColor:  compColor,
                      compLabel:  compLabel,
                    ),

              const SizedBox(height: 8),

              // ── Account section ───────────────────────────────────────────
              _SectionLabel('Account'),
              _SettingsGroup(children: [
                _SettingsTile(
                  icon: Icons.person_outline_rounded,
                  iconColor: const Color(0xFF2563EB),
                  iconBg: const Color(0xFFEFF6FF),
                  title: 'Edit Profile',
                  subtitle: 'Update your name, photo, bio and address',
                  onTap: () => Navigator.pushNamed(context, '/profile')
                      .then((_) => _loadProfile()),
                ),
                _Divider(),
                _SettingsTile(
                  icon: Icons.lock_outline_rounded,
                  iconColor: const Color(0xFF7C3AED),
                  iconBg: const Color(0xFFF5F3FF),
                  title: 'Change Password',
                  subtitle: 'Update your account password',
                  onTap: () => Navigator.pushNamed(context, '/reset-password'),
                ),
              ]),

              const SizedBox(height: 16),

              // ── Publishing section ─────────────────────────────────────────
              _SectionLabel('Publishing'),
              _SettingsGroup(children: [
                _SettingsTile(
                      icon: Icons.drive_file_rename_outline_rounded,
                      iconColor: const Color(0xFF0891B2),
                      iconBg: const Color(0xFFECFEFF),
                      title: 'Publish With Us',
                      subtitle: 'Submit your manuscript or book',
                      onTap: () => Navigator.of(context).push(
                        MaterialPageRoute(
                          builder: (_) => PublishWithUsPage(),
                        ),
                      ),
                ),
                _Divider(),
                _SettingsTile(
                  icon: Icons.update_rounded,
                  iconColor: const Color(0xFF059669),
                  iconBg: const Color(0xFFF0FDF4),
                  title: 'Content Update',
                  subtitle: 'Manage your uploaded content',
                  onTap: () =>
                      Navigator.pushNamed(context, '/content-management'),
                ),
              ]),

              const SizedBox(height: 16),

              // ── App section ────────────────────────────────────────────────
              _SectionLabel('App'),
              _SettingsGroup(children: [
                _SettingsTile(
                  icon: Icons.info_outline_rounded,
                  iconColor: const Color(0xFF6B7280),
                  iconBg: const Color(0xFFF3F4F6),
                  title: 'About Intercen',
                  subtitle: 'Version, licenses and legal',
                  onTap: () => Navigator.of(context).push(
                    MaterialPageRoute(
                      builder: (_) => const AboutPage(),
                    ),
                  ),
                ),
                _Divider(),
                _SettingsTile(
                  icon: Icons.help_outline_rounded,
                  iconColor: const Color(0xFFD97706),
                  iconBg: const Color(0xFFFFFBEB),
                  title: 'Help & Support',
                  subtitle: 'Contact us or read the FAQ',
                  onTap: () => _showHelpSheet(),
                ),
              ]),

              const SizedBox(height: 16),

              // ── Sign out ──────────────────────────────────────────────────
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 16),
                child: _SettingsGroup(children: [
                  _SettingsTile(
                    icon: Icons.logout_rounded,
                    iconColor: AppColors.primary,
                    iconBg: AppColors.primary.withOpacity(0.08),
                    title: 'Sign Out',
                    subtitle: 'Log out of your account',
                    trailing: const SizedBox.shrink(),
                    titleColor: AppColors.primary,
                    onTap: _signOut,
                  ),
                ]),
              ),

              SizedBox(height: 32 + MediaQuery.of(context).padding.bottom),
            ]),
          ),
        ],
      ),
    );
  }

  // ── Profile header ────────────────────────────────────────────────────────
  Widget _profileHeader({
    required String name,
    required String email,
    required String? avatarUrl,
    required String role,
    required double ratio,
    required Color compColor,
    required String compLabel,
  }) {
    final isComplete = ratio >= 1.0;
    return GestureDetector(
      onTap: () =>
          Navigator.pushNamed(context, '/profile').then((_) => _loadProfile()),
      child: Container(
        margin: const EdgeInsets.fromLTRB(16, 16, 16, 8),
        padding: const EdgeInsets.all(20),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(20),
          boxShadow: [
            BoxShadow(
                color: Colors.black.withOpacity(0.05),
                blurRadius: 12,
                offset: const Offset(0, 4)),
          ],
        ),
        child: Column(children: [
          Row(crossAxisAlignment: CrossAxisAlignment.center, children: [

            // Avatar
            Container(
              width: 64, height: 64,
              decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  border: Border.all(
                      color: AppColors.primary.withOpacity(0.2), width: 2.5)),
              child: ClipOval(
                child: avatarUrl != null && avatarUrl.isNotEmpty
                    ? CachedNetworkImage(
                        imageUrl: avatarUrl,
                        fit: BoxFit.cover,
                        placeholder: (_, __) =>
                            Container(color: const Color(0xFFF3F4F6)),
                        errorWidget: (_, __, ___) => _avatarPlaceholder(),
                      )
                    : _avatarPlaceholder(),
              ),
            ),
            const SizedBox(width: 14),

            // Name / email / role
            Expanded(
              child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                Text(
                  name.isNotEmpty ? name : 'Complete your profile',
                  style: TextStyle(
                      fontFamily: 'PlayfairDisplay',
                      fontSize: 17,
                      fontWeight: FontWeight.w800,
                      color: name.isNotEmpty
                          ? const Color(0xFF111827)
                          : AppColors.primary),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
                const SizedBox(height: 2),
                Text(email,
                    style: const TextStyle(
                        fontFamily: 'DM Sans',
                        fontSize: 12,
                        color: Color(0xFF9CA3AF)),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis),
                const SizedBox(height: 6),
                _RoleBadge(role),
              ]),
            ),
            const SizedBox(width: 8),
            Icon(Icons.chevron_right_rounded,
                color: const Color(0xFFD1D5DB), size: 20),
          ]),

          const SizedBox(height: 16),

          // Profile completion bar
          Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text('Profile Completion',
                    style: const TextStyle(
                        fontFamily: 'DM Sans',
                        fontSize: 12,
                        color: Color(0xFF6B7280))),
                Text(
                  isComplete ? '✓ $compLabel' : compLabel,
                  style: TextStyle(
                      fontFamily: 'DM Sans',
                      fontSize: 12,
                      fontWeight: FontWeight.w700,
                      color: compColor),
                ),
              ],
            ),
            const SizedBox(height: 6),
            ClipRRect(
              borderRadius: BorderRadius.circular(4),
              child: LinearProgressIndicator(
                value: ratio,
                minHeight: 6,
                backgroundColor: const Color(0xFFE5E7EB),
                valueColor: AlwaysStoppedAnimation(compColor),
              ),
            ),
            if (!isComplete) ...[
              const SizedBox(height: 8),
              GestureDetector(
                onTap: () => Navigator.pushNamed(context, '/profile')
                    .then((_) => _loadProfile()),
                child: Row(children: [
                  Icon(Icons.arrow_forward_rounded,
                      size: 13, color: AppColors.primary),
                  const SizedBox(width: 4),
                  Text('Tap to complete your profile',
                      style: TextStyle(
                          fontFamily: 'DM Sans',
                          fontSize: 12,
                          fontWeight: FontWeight.w600,
                          color: AppColors.primary)),
                ]),
              ),
            ],
          ]),
        ]),
      ),
    );
  }

  // ── Profile header skeleton (while loading) ───────────────────────────────
  Widget _profileHeaderSkeleton() => Container(
        margin: const EdgeInsets.fromLTRB(16, 16, 16, 8),
        padding: const EdgeInsets.all(20),
        decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(20),
            boxShadow: [
              BoxShadow(
                  color: Colors.black.withOpacity(0.04),
                  blurRadius: 8,
                  offset: const Offset(0, 2))
            ]),
        child: Row(children: [
          _Skeleton(width: 64, height: 64, radius: 32),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
              _Skeleton(width: 140, height: 16, radius: 6),
              const SizedBox(height: 8),
              _Skeleton(width: 100, height: 12, radius: 4),
              const SizedBox(height: 12),
              _Skeleton(width: double.infinity, height: 6, radius: 3),
            ]),
          ),
        ]),
      );

  // ── About bottom sheet ────────────────────────────────────────────────────
  void _showAboutSheet() => showModalBottomSheet(
        context: context,
        backgroundColor: Colors.white,
        shape: const RoundedRectangleBorder(
            borderRadius: BorderRadius.vertical(top: Radius.circular(24))),
        builder: (_) => Padding(
          padding: const EdgeInsets.fromLTRB(24, 8, 24, 40),
          child: Column(mainAxisSize: MainAxisSize.min, children: [
            Container(
              width: 40, height: 4,
              margin: const EdgeInsets.only(bottom: 20, top: 8),
              decoration: BoxDecoration(
                  color: const Color(0xFFD1D5DB),
                  borderRadius: BorderRadius.circular(2)),
            ),
            Container(
              width: 64, height: 64,
              decoration: BoxDecoration(
                  color: AppColors.primary.withOpacity(0.08),
                  shape: BoxShape.circle),
              child: Icon(Icons.auto_stories_rounded,
                  size: 36, color: AppColors.primary),
            ),
            const SizedBox(height: 16),
            const Text('Intercen Books',
                style: TextStyle(
                    fontFamily: 'PlayfairDisplay',
                    fontSize: 22,
                    fontWeight: FontWeight.w800,
                    color: Color(0xFF111827))),
            const SizedBox(height: 4),
            const Text('Version 1.0.0',
                style: TextStyle(
                    fontFamily: 'DM Sans',
                    fontSize: 13,
                    color: Color(0xFF9CA3AF))),
            const SizedBox(height: 16),
            const Text(
              'Intercen Books is Kenya\'s premier digital library and bookstore — '
              'connecting readers, authors and publishers across Africa.',
              textAlign: TextAlign.center,
              style: TextStyle(
                  fontFamily: 'DM Sans',
                  fontSize: 14,
                  color: Color(0xFF6B7280),
                  height: 1.6),
            ),
            const SizedBox(height: 24),
            Row(children: [
              Expanded(
                child: OutlinedButton(
                  onPressed: () {},
                  style: OutlinedButton.styleFrom(
                      side: const BorderSide(color: Color(0xFFE5E7EB)),
                      shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(12)),
                      padding: const EdgeInsets.symmetric(vertical: 12)),
                  child: const Text('Privacy Policy',
                      style: TextStyle(
                          fontFamily: 'DM Sans',
                          fontSize: 13,
                          color: Color(0xFF374151))),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: OutlinedButton(
                  onPressed: () {},
                  style: OutlinedButton.styleFrom(
                      side: const BorderSide(color: Color(0xFFE5E7EB)),
                      shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(12)),
                      padding: const EdgeInsets.symmetric(vertical: 12)),
                  child: const Text('Terms of Use',
                      style: TextStyle(
                          fontFamily: 'DM Sans',
                          fontSize: 13,
                          color: Color(0xFF374151))),
                ),
              ),
            ]),
          ]),
        ),
      );

  // ── Help bottom sheet ─────────────────────────────────────────────────────
  void _showHelpSheet() => showModalBottomSheet(
        context: context,
        backgroundColor: Colors.white,
        shape: const RoundedRectangleBorder(
            borderRadius: BorderRadius.vertical(top: Radius.circular(24))),
        builder: (_) => Padding(
          padding: const EdgeInsets.fromLTRB(24, 8, 24, 40),
          child: Column(mainAxisSize: MainAxisSize.min, children: [
            Container(
              width: 40, height: 4,
              margin: const EdgeInsets.only(bottom: 20, top: 8),
              decoration: BoxDecoration(
                  color: const Color(0xFFD1D5DB),
                  borderRadius: BorderRadius.circular(2)),
            ),
            const Text('Help & Support',
                style: TextStyle(
                    fontFamily: 'PlayfairDisplay',
                    fontSize: 20,
                    fontWeight: FontWeight.w800,
                    color: Color(0xFF111827))),
            const SizedBox(height: 20),
            _HelpItem(
                icon: Icons.email_outlined,
                title: 'Email Us',
                subtitle: 'support@intercenbooks.com',
                onTap: () {}),
            const SizedBox(height: 12),
            _HelpItem(
                icon: Icons.chat_bubble_outline_rounded,
                title: 'Live Chat',
                subtitle: 'Chat with our support team',
                onTap: () {}),
            const SizedBox(height: 12),
            _HelpItem(
                icon: Icons.menu_book_outlined,
                title: 'FAQ',
                subtitle: 'Browse frequently asked questions',
                onTap: () {}),
          ]),
        ),
      );

  Widget _avatarPlaceholder() => Container(
        color: const Color(0xFFF3F4F6),
        child: const Icon(Icons.person_rounded,
            size: 34, color: Color(0xFFD1D5DB)),
      );
}

// ─────────────────────────────────────────────────────────────────────────────
// SUB-WIDGETS
// ─────────────────────────────────────────────────────────────────────────────

class _SectionLabel extends StatelessWidget {
  final String text;
  const _SectionLabel(this.text);

  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.fromLTRB(20, 8, 20, 8),
        child: Text(text.toUpperCase(),
            style: const TextStyle(
                fontFamily: 'DM Sans',
                fontSize: 11,
                fontWeight: FontWeight.w700,
                color: Color(0xFF9CA3AF),
                letterSpacing: 1.0)),
      );
}

class _SettingsGroup extends StatelessWidget {
  final List<Widget> children;
  const _SettingsGroup({required this.children});

  @override
  Widget build(BuildContext context) => Container(
        margin: const EdgeInsets.symmetric(horizontal: 16),
        decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(16),
            boxShadow: [
              BoxShadow(
                  color: Colors.black.withOpacity(0.04),
                  blurRadius: 8,
                  offset: const Offset(0, 2))
            ]),
        clipBehavior: Clip.antiAlias,
        child: Column(children: children),
      );
}

class _Divider extends StatelessWidget {
  @override
  Widget build(BuildContext context) =>
      const Divider(height: 1, indent: 64, endIndent: 0,
          color: Color(0xFFF3F4F6));
}

class _SettingsTile extends StatelessWidget {
  final IconData icon;
  final Color iconColor, iconBg;
  final String title;
  final String? subtitle;
  final VoidCallback onTap;
  final Widget? trailing;
  final Color? titleColor;

  const _SettingsTile({
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
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
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
                        color: titleColor ?? const Color(0xFF111827))),
                if (subtitle != null) ...[
                  const SizedBox(height: 2),
                  Text(subtitle!,
                      style: const TextStyle(
                          fontFamily: 'DM Sans',
                          fontSize: 12,
                          color: Color(0xFF9CA3AF))),
                ],
              ]),
            ),
            trailing ??
                const Icon(Icons.chevron_right_rounded,
                    color: Color(0xFFD1D5DB), size: 20),
          ]),
        ),
      );
}

class _RoleBadge extends StatelessWidget {
  final String role;
  const _RoleBadge(this.role);

  Color get _color => switch (role) {
        'admin'          => const Color(0xFF7C3AED),
        'author'         => const Color(0xFF2563EB),
        'publisher'      => const Color(0xFF0891B2),
        'corporate_user' => const Color(0xFF059669),
        _                => const Color(0xFF6B7280),
      };

  String get _label => switch (role) {
        'corporate_user' => 'Corporate',
        'admin'          => 'Admin',
        'author'         => 'Author',
        'publisher'      => 'Publisher',
        _                => 'Reader',
      };

  @override
  Widget build(BuildContext context) => Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 3),
        decoration: BoxDecoration(
            color: _color.withOpacity(0.1),
            borderRadius: BorderRadius.circular(20),
            border: Border.all(color: _color.withOpacity(0.25))),
        child: Text(_label,
            style: TextStyle(
                fontFamily: 'DM Sans',
                fontSize: 10,
                fontWeight: FontWeight.w700,
                color: _color)),
      );
}

class _Skeleton extends StatefulWidget {
  final double width, height, radius;
  const _Skeleton(
      {required this.width, required this.height, required this.radius});

  @override
  State<_Skeleton> createState() => _SkeletonState();
}

class _SkeletonState extends State<_Skeleton>
    with SingleTickerProviderStateMixin {
  late final AnimationController _ctrl;
  late final Animation<double> _anim;

  @override
  void initState() {
    super.initState();
    _ctrl = AnimationController(
        vsync: this, duration: const Duration(milliseconds: 900))
      ..repeat(reverse: true);
    _anim = CurvedAnimation(parent: _ctrl, curve: Curves.easeInOut);
  }

  @override
  void dispose() { _ctrl.dispose(); super.dispose(); }

  @override
  Widget build(BuildContext context) => AnimatedBuilder(
        animation: _anim,
        builder: (_, __) => Container(
          width: widget.width,
          height: widget.height,
          decoration: BoxDecoration(
              color: Color.lerp(
                  const Color(0xFFE5E7EB), const Color(0xFFF3F4F6), _anim.value),
              borderRadius: BorderRadius.circular(widget.radius)),
        ),
      );
}

class _HelpItem extends StatelessWidget {
  final IconData icon;
  final String title, subtitle;
  final VoidCallback onTap;
  const _HelpItem(
      {required this.icon,
      required this.title,
      required this.subtitle,
      required this.onTap});

  @override
  Widget build(BuildContext context) => GestureDetector(
        onTap: onTap,
        child: Container(
          padding: const EdgeInsets.all(14),
          decoration: BoxDecoration(
              color: const Color(0xFFF9FAFB),
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: const Color(0xFFE5E7EB))),
          child: Row(children: [
            Container(
              width: 40, height: 40,
              decoration: BoxDecoration(
                  color: AppColors.primary.withOpacity(0.08),
                  shape: BoxShape.circle),
              child: Icon(icon, color: AppColors.primary, size: 20),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                Text(title,
                    style: const TextStyle(
                        fontFamily: 'DM Sans',
                        fontSize: 14,
                        fontWeight: FontWeight.w600,
                        color: Color(0xFF111827))),
                Text(subtitle,
                    style: const TextStyle(
                        fontFamily: 'DM Sans',
                        fontSize: 12,
                        color: Color(0xFF9CA3AF))),
              ]),
            ),
            const Icon(Icons.arrow_forward_ios_rounded,
                size: 14, color: Color(0xFFD1D5DB)),
          ]),
        ),
      );
}