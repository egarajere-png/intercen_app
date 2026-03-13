import 'dart:io';
import 'dart:convert';

import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:image_picker/image_picker.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:intl/intl.dart';

import '../theme/app_colors.dart';

// ─────────────────────────────────────────────────────────────────────────────
// PROFILE PAGE
// Shown for returning authenticated users. Displays the full profile with
// editable fields, avatar upload, a live order history modal, and uploaded
// content navigation.
// ─────────────────────────────────────────────────────────────────────────────

class ProfilePage extends StatefulWidget {
  const ProfilePage({super.key});

  @override
  State<ProfilePage> createState() => _ProfilePageState();
}

class _ProfilePageState extends State<ProfilePage>
    with SingleTickerProviderStateMixin {
  final _sb     = Supabase.instance.client;
  final _picker = ImagePicker();

  // ── Profile data ──────────────────────────────────────────────────────────
  Map<String, dynamic>? _profile;
  User? _user;

  // ── Loading states ────────────────────────────────────────────────────────
  bool _loading       = true;
  bool _saving        = false;
  bool _loadingOrders = false;
  String? _loadError;

  // ── Form controllers ──────────────────────────────────────────────────────
  final _fullNameCtrl   = TextEditingController();
  final _phoneCtrl      = TextEditingController();
  final _addressCtrl    = TextEditingController();
  final _orgCtrl        = TextEditingController();
  final _departmentCtrl = TextEditingController();
  final _bioCtrl        = TextEditingController();
  final _formKey        = GlobalKey<FormState>();

  // ── Selects ───────────────────────────────────────────────────────────────
  String _accountType = 'personal';

  // ── Avatar ────────────────────────────────────────────────────────────────
  File?   _avatarFile;
  String? _avatarBase64;
  String? _avatarUrl;

  // ── Orders ────────────────────────────────────────────────────────────────
  List<Map<String, dynamic>> _orders = [];
  bool _ordersLoaded = false;

  // ── UI state ──────────────────────────────────────────────────────────────
  bool _showOrders  = false;
  bool _isEditing   = false;
  bool _hasChanges  = false;

  late final AnimationController _fadeCtrl;
  late final Animation<double>   _fadeAnim;

  @override
  void initState() {
    super.initState();
    _fadeCtrl = AnimationController(
        vsync: this, duration: const Duration(milliseconds: 500));
    _fadeAnim = CurvedAnimation(parent: _fadeCtrl, curve: Curves.easeOut);
    _loadProfile();
  }

  @override
  void dispose() {
    _fullNameCtrl.dispose();
    _phoneCtrl.dispose();
    _addressCtrl.dispose();
    _orgCtrl.dispose();
    _departmentCtrl.dispose();
    _bioCtrl.dispose();
    _fadeCtrl.dispose();
    super.dispose();
  }

  // ── Load profile ──────────────────────────────────────────────────────────
  Future<void> _loadProfile() async {
    setState(() { _loading = true; _loadError = null; });
    try {
      final session = _sb.auth.currentSession;
      if (session == null) {
        Navigator.pushReplacementNamed(context, '/login');
        return;
      }
      _user = session.user;

      final data = await _sb
          .from('profiles')
          .select('*')
          .eq('id', session.user.id)
          .maybeSingle();

      if (data == null) {
        // No profile row — redirect to setup
        Navigator.pushReplacementNamed(context, '/profile-setup');
        return;
      }

      _profile = data;
      _populateControllers(data);
      _fadeCtrl.forward();
    } catch (e) {
      setState(() => _loadError = e.toString().replaceFirst('Exception: ', ''));
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  void _populateControllers(Map<String, dynamic> p) {
    _fullNameCtrl.text   = p['full_name']    as String? ?? '';
    _phoneCtrl.text      = p['phone']        as String? ?? '';
    _addressCtrl.text    = p['address']      as String? ?? '';
    _orgCtrl.text        = p['organization'] as String? ?? '';
    _departmentCtrl.text = p['department']   as String? ?? '';
    _bioCtrl.text        = p['bio']          as String? ?? '';
    _accountType         = p['account_type'] as String? ?? 'personal';
    _avatarUrl           = p['avatar_url']   as String?;

    // Listen for changes
    for (final ctrl in [
      _fullNameCtrl, _phoneCtrl, _addressCtrl,
      _orgCtrl, _departmentCtrl, _bioCtrl
    ]) {
      ctrl.addListener(_onFieldChanged);
    }
  }

  void _onFieldChanged() {
    final p = _profile!;
    setState(() {
      _hasChanges =
          _fullNameCtrl.text   != (p['full_name']    ?? '') ||
          _phoneCtrl.text      != (p['phone']        ?? '') ||
          _addressCtrl.text    != (p['address']      ?? '') ||
          _orgCtrl.text        != (p['organization'] ?? '') ||
          _departmentCtrl.text != (p['department']   ?? '') ||
          _bioCtrl.text        != (p['bio']          ?? '') ||
          _accountType         != (p['account_type'] ?? 'personal') ||
          _avatarBase64 != null;
    });
  }

  // ── Avatar picker ─────────────────────────────────────────────────────────
  Future<void> _pickAvatar() async {
    if (!_isEditing) return;
    final picked = await _picker.pickImage(
        source: ImageSource.gallery, imageQuality: 80, maxWidth: 512);
    if (picked == null) return;
    final file  = File(picked.path);
    final bytes = await file.readAsBytes();
    if (bytes.lengthInBytes > 5 * 1024 * 1024) {
      _showSnack('Image must be under 5 MB');
      return;
    }
    setState(() {
      _avatarFile   = file;
      _avatarBase64 = 'data:image/jpeg;base64,${base64Encode(bytes)}';
      _hasChanges   = true;
    });
  }

  void _clearAvatar() => setState(() {
        _avatarFile   = null;
        _avatarBase64 = null;
        _onFieldChanged();
      });

  // ── Save changes ──────────────────────────────────────────────────────────
  Future<void> _save() async {
    if (!(_formKey.currentState?.validate() ?? false)) return;
    if (!_hasChanges) {
      _showSnack('No changes to save');
      return;
    }
    setState(() { _saving = true; });
    try {
      final session = _sb.auth.currentSession;
      if (session == null) throw Exception('Session expired.');

      final payload = <String, dynamic>{
        'full_name':    _fullNameCtrl.text.trim(),
        'phone':        _phoneCtrl.text.trim().isEmpty ? null : _phoneCtrl.text.trim(),
        'address':      _addressCtrl.text.trim().isEmpty ? null : _addressCtrl.text.trim(),
        'organization': _orgCtrl.text.trim().isEmpty ? null : _orgCtrl.text.trim(),
        'department':   _departmentCtrl.text.trim().isEmpty ? null : _departmentCtrl.text.trim(),
        'bio':          _bioCtrl.text.trim().isEmpty ? null : _bioCtrl.text.trim(),
        'account_type': _accountType,
        if (_avatarBase64 != null) 'avatar_base64': _avatarBase64,
      };

      final r = await _sb.functions.invoke(
        'profile-info-edit',
        body: payload,
        headers: {'Authorization': 'Bearer ${session.accessToken}'},
      );
      if (r.status != 200) {
        throw Exception((r.data as Map?)?['error'] ?? 'Save failed');
      }

      // Refresh from DB
      final fresh = await _sb
          .from('profiles')
          .select('*')
          .eq('id', session.user.id)
          .single();

      setState(() {
        _profile    = fresh;
        _avatarUrl  = fresh['avatar_url'] as String?;
        _avatarFile = null;
        _avatarBase64 = null;
        _hasChanges = false;
        _isEditing  = false;
      });

      _showSnack('Profile updated ✓', success: true);
    } catch (e) {
      _showSnack(e.toString().replaceFirst('Exception: ', ''));
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  // ── Discard edits ─────────────────────────────────────────────────────────
  void _discardEdits() {
    _populateControllers(_profile!);
    setState(() {
      _isEditing    = false;
      _hasChanges   = false;
      _avatarFile   = null;
      _avatarBase64 = null;
    });
  }

  // ── Fetch orders ──────────────────────────────────────────────────────────
  Future<void> _fetchOrders() async {
    if (_ordersLoaded) return;
    setState(() => _loadingOrders = true);
    try {
      final data = await _sb.from('orders').select('''
        id, order_number, status, payment_status,
        total_price, created_at,
        order_items(
          id, quantity, unit_price,
          content:content_id(id, title, cover_image_url)
        )
      ''').eq('user_id', _user!.id).order('created_at', ascending: false);

      setState(() {
        _orders = List<Map<String, dynamic>>.from(data);
        _ordersLoaded = true;
      });
    } catch (e) {
      _showSnack('Could not load orders');
    } finally {
      if (mounted) setState(() => _loadingOrders = false);
    }
  }

  // ── Sign out ──────────────────────────────────────────────────────────────
  Future<void> _signOut() async {
    final confirmed = await _confirmDialog(
        'Sign Out', 'Are you sure you want to sign out?');
    if (!confirmed) return;
    await _sb.auth.signOut();
    if (mounted) {
      Navigator.pushNamedAndRemoveUntil(context, '/onboarding', (_) => false);
    }
  }

  // ── Helpers ───────────────────────────────────────────────────────────────
  void _showSnack(String msg, {bool success = false}) {
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(
      content: Text(msg, style: const TextStyle(fontFamily: 'DM Sans')),
      backgroundColor:
          success ? const Color(0xFF16A34A) : AppColors.primary,
      behavior: SnackBarBehavior.floating,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
    ));
  }

  Future<bool> _confirmDialog(String title, String body) async {
    return await showDialog<bool>(
          context: context,
          builder: (_) => AlertDialog(
            shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(20)),
            title: Text(title,
                style: const TextStyle(
                    fontFamily: 'PlayfairDisplay',
                    fontWeight: FontWeight.w800)),
            content: Text(body,
                style: const TextStyle(
                    fontFamily: 'DM Sans', color: Color(0xFF6B7280))),
            actions: [
              TextButton(
                  onPressed: () => Navigator.pop(context, false),
                  child: const Text('Cancel')),
              ElevatedButton(
                  onPressed: () => Navigator.pop(context, true),
                  style: ElevatedButton.styleFrom(
                      backgroundColor: AppColors.primary,
                      foregroundColor: Colors.white),
                  child: const Text('Confirm')),
            ],
          ),
        ) ??
        false;
  }

  InputDecoration _fieldDeco(String label, {String? hint, IconData? icon}) =>
      InputDecoration(
        labelText: label,
        hintText: hint,
        prefixIcon: icon != null
            ? Icon(icon, size: 20, color: const Color(0xFF9CA3AF))
            : null,
        labelStyle: const TextStyle(
            fontFamily: 'DM Sans', fontSize: 13, color: Color(0xFF6B7280)),
        hintStyle: const TextStyle(
            fontFamily: 'DM Sans', fontSize: 13, color: Color(0xFFD1D5DB)),
        filled: true,
        fillColor: _isEditing ? Colors.white : const Color(0xFFF9FAFB),
        contentPadding:
            const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
        border: OutlineInputBorder(
            borderRadius: BorderRadius.circular(12),
            borderSide: const BorderSide(color: Color(0xFFE5E7EB))),
        enabledBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(12),
            borderSide: const BorderSide(color: Color(0xFFE5E7EB))),
        disabledBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(12),
            borderSide: const BorderSide(color: Color(0xFFF3F4F6))),
        focusedBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(12),
            borderSide: BorderSide(color: AppColors.primary, width: 2)),
        errorBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(12),
            borderSide: const BorderSide(color: Color(0xFFEF4444))),
        focusedErrorBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(12),
            borderSide: const BorderSide(color: Color(0xFFEF4444), width: 2)),
      );

  // ── BUILD ─────────────────────────────────────────────────────────────────
  @override
  Widget build(BuildContext context) {
    if (_loading) return _loadingView();
    if (_loadError != null) return _errorView();

    return Scaffold(
      backgroundColor: const Color(0xFFF9F5EF),
      body: Stack(children: [
        NestedScrollView(
          headerSliverBuilder: (_, __) => [_buildSliverAppBar()],
          body: FadeTransition(
            opacity: _fadeAnim,
            child: Form(
              key: _formKey,
              child: ListView(
                padding: const EdgeInsets.fromLTRB(16, 16, 16, 100),
                children: [
                  // ── Quick action cards ─────────────────────────────────────
                  _buildQuickActions(),
                  const SizedBox(height: 20),

                  // ── Identity section ───────────────────────────────────────
                  _SectionHeader('Personal Details'),
                  const SizedBox(height: 12),
                  _buildIdentityCard(),
                  const SizedBox(height: 20),

                  // ── Contact section ────────────────────────────────────────
                  _SectionHeader('Contact & Address'),
                  const SizedBox(height: 12),
                  _buildContactCard(),
                  const SizedBox(height: 20),

                  // ── Bio section ────────────────────────────────────────────
                  _SectionHeader('About You'),
                  const SizedBox(height: 12),
                  _buildBioCard(),
                  const SizedBox(height: 20),

                  // ── Account section ────────────────────────────────────────
                  _SectionHeader('Account'),
                  const SizedBox(height: 12),
                  _buildAccountCard(),
                  const SizedBox(height: 32),

                  // ── Sign out ───────────────────────────────────────────────
                  _buildSignOutButton(),
                ],
              ),
            ),
          ),
        ),

        // ── Bottom save bar ────────────────────────────────────────────────
        if (_isEditing) _buildSaveBar(),

        // ── Orders modal ───────────────────────────────────────────────────
        if (_showOrders) _buildOrdersModal(),
      ]),
    );
  }

  // ── Sliver AppBar with avatar ─────────────────────────────────────────────
  Widget _buildSliverAppBar() => SliverAppBar(
        expandedHeight: 220,
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
          if (!_isEditing)
            TextButton.icon(
              onPressed: () => setState(() => _isEditing = true),
              icon: Icon(Icons.edit_outlined,
                  size: 16, color: AppColors.primary),
              label: Text('Edit',
                  style: TextStyle(
                      fontFamily: 'DM Sans',
                      fontWeight: FontWeight.w700,
                      color: AppColors.primary)),
            )
          else ...[
            TextButton(
              onPressed: _discardEdits,
              child: const Text('Cancel',
                  style: TextStyle(
                      fontFamily: 'DM Sans', color: Color(0xFF6B7280))),
            ),
          ],
          const SizedBox(width: 4),
        ],
        flexibleSpace: FlexibleSpaceBar(
          background: Container(
            decoration: const BoxDecoration(
              gradient: LinearGradient(
                begin: Alignment.topCenter,
                end: Alignment.bottomCenter,
                colors: [Color(0xFFFDF8F3), Color(0xFFF9F5EF)],
              ),
            ),
            child: SafeArea(
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 16.0, vertical: 8.0),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    const SizedBox(height: 48),

                    // Avatar
                    GestureDetector(
                      onTap: _pickAvatar,
                      child: Stack(children: [
                        Container(
                          width: 88, height: 88,
                          decoration: BoxDecoration(
                              shape: BoxShape.circle,
                              border: Border.all(
                                  color: AppColors.primary.withOpacity(0.25),
                                  width: 3),
                              boxShadow: [
                                BoxShadow(
                                    color: Colors.black.withOpacity(0.08),
                                    blurRadius: 12,
                                    offset: const Offset(0, 4))
                              ]),
                          child: ClipOval(
                            child: _avatarFile != null
                                ? Image.file(_avatarFile!, fit: BoxFit.cover)
                                : _avatarUrl != null && _avatarUrl!.isNotEmpty
                                    ? CachedNetworkImage(
                                        imageUrl: _avatarUrl!,
                                        fit: BoxFit.cover,
                                        placeholder: (_, __) => Container(
                                            color: const Color(0xFFF3F4F6)),
                                        errorWidget: (_, __, ___) =>
                                            _avatarPlaceholder())
                                    : _avatarPlaceholder(),
                          ),
                        ),
                        if (_isEditing)
                          Positioned(
                            bottom: 0, right: 0,
                            child: Container(
                              width: 28, height: 28,
                              decoration: BoxDecoration(
                                  color: AppColors.primary,
                                  shape: BoxShape.circle,
                                  border:
                                      Border.all(color: Colors.white, width: 2)),
                              child: const Icon(Icons.camera_alt_rounded,
                                  size: 13, color: Colors.white),
                            ),
                          ),
                      ]),
                    ),
                    const SizedBox(height: 12),

                    Text(
                      _fullNameCtrl.text.isNotEmpty
                          ? _fullNameCtrl.text
                          : 'Your Name',
                      style: const TextStyle(
                          fontFamily: 'PlayfairDisplay',
                          fontSize: 20,
                          fontWeight: FontWeight.w800,
                          color: Color(0xFF111827)),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      _user?.email ?? '',
                      style: const TextStyle(
                          fontFamily: 'DM Sans',
                          fontSize: 12,
                          color: Color(0xFF9CA3AF)),
                    ),
                    const SizedBox(height: 8),
                    _RoleBadge(_profile?['role'] as String? ?? 'reader'),
                  ],
                ),
              ),
            ),
          ),
        ),
        bottom: PreferredSize(
          preferredSize: const Size.fromHeight(1),
          child: Container(height: 1, color: const Color(0xFFE5E7EB)),
        ),
      );

  // ── Quick action cards ────────────────────────────────────────────────────
  Widget _buildQuickActions() => Row(children: [
        _QuickActionCard(
          icon: Icons.receipt_long_outlined,
          label: 'My Orders',
          count: _ordersLoaded ? '${_orders.length}' : null,
          color: const Color(0xFF2563EB),
          bg: const Color(0xFFEFF6FF),
          onTap: () {
            setState(() => _showOrders = true);
            _fetchOrders();
          },
        ),
        const SizedBox(width: 12),
        _QuickActionCard(
          icon: Icons.library_books_outlined,
          label: 'My Content',
          color: const Color(0xFF7C3AED),
          bg: const Color(0xFFF5F3FF),
          onTap: () => Navigator.pushNamed(context, '/content-management'),
        ),
        const SizedBox(width: 12),
        _QuickActionCard(
          icon: Icons.shopping_bag_outlined,
          label: 'Shop',
          color: AppColors.primary,
          bg: AppColors.primary.withOpacity(0.08),
          onTap: () => Navigator.pushNamed(context, '/books'),
        ),
      ]);

  // ── Identity card ─────────────────────────────────────────────────────────
  Widget _buildIdentityCard() => _Card(
        child: Column(children: [
          // Email read-only
          _ReadOnlyField(
              label: 'Email', value: _user?.email ?? '', icon: Icons.email_outlined),
          const SizedBox(height: 16),

          TextFormField(
            controller: _fullNameCtrl,
            decoration: _fieldDeco('Full Name',
                hint: 'Mwangi Kamau', icon: Icons.badge_outlined),
            enabled: _isEditing,
            maxLength: 100,
            style: const TextStyle(fontFamily: 'DM Sans', fontSize: 14),
            validator: (v) => (v == null || v.trim().isEmpty)
                ? 'Full name is required'
                : null,
          ),
          const SizedBox(height: 16),

          // Account type
          const Align(
            alignment: Alignment.centerLeft,
            child: Text('Account Type',
                style: TextStyle(
                    fontFamily: 'DM Sans',
                    fontSize: 13,
                    fontWeight: FontWeight.w600,
                    color: Color(0xFF374151))),
          ),
          const SizedBox(height: 8),
          Row(children: [
            _TypeChip(
              label: 'Personal',
              icon: Icons.person_rounded,
              selected: _accountType == 'personal',
              enabled: _isEditing,
              onTap: () {
                if (_isEditing) setState(() { _accountType = 'personal'; _onFieldChanged(); });
              },
            ),
            const SizedBox(width: 8),
            _TypeChip(
              label: 'Corporate',
              icon: Icons.business_rounded,
              selected: _accountType == 'corporate',
              enabled: _isEditing,
              onTap: () {
                if (_isEditing) setState(() { _accountType = 'corporate'; _onFieldChanged(); });
              },
            ),
            const SizedBox(width: 8),
            _TypeChip(
              label: 'Institution',
              icon: Icons.school_rounded,
              selected: _accountType == 'institutional',
              enabled: _isEditing,
              onTap: () {
                if (_isEditing) setState(() { _accountType = 'institutional'; _onFieldChanged(); });
              },
            ),
          ]),

          if (_accountType != 'personal') ...[
            const SizedBox(height: 16),
            TextFormField(
              controller: _orgCtrl,
              decoration: _fieldDeco(
                  _accountType == 'corporate'
                      ? 'Company / Organization'
                      : 'Institution',
                  icon: Icons.domain_rounded),
              enabled: _isEditing,
              style: const TextStyle(fontFamily: 'DM Sans', fontSize: 14),
            ),
            const SizedBox(height: 16),
            TextFormField(
              controller: _departmentCtrl,
              decoration:
                  _fieldDeco('Department / Faculty', icon: Icons.account_tree_outlined),
              enabled: _isEditing,
              style: const TextStyle(fontFamily: 'DM Sans', fontSize: 14),
            ),
          ],
        ]),
      );

  // ── Contact card ──────────────────────────────────────────────────────────
  Widget _buildContactCard() => _Card(
        child: Column(children: [
          TextFormField(
            controller: _phoneCtrl,
            decoration: _fieldDeco('Phone Number',
                hint: '+254 712 345 678', icon: Icons.phone_outlined),
            enabled: _isEditing,
            keyboardType: TextInputType.phone,
            maxLength: 20,
            inputFormatters: [FilteringTextInputFormatter.allow(RegExp(r'[+\d\s\-()]'))],
            style: const TextStyle(fontFamily: 'DM Sans', fontSize: 14),
          ),
          const SizedBox(height: 16),
          TextFormField(
            controller: _addressCtrl,
            decoration: _fieldDeco('Delivery Address',
                hint: 'P.O. Box 12345-00100, Nairobi',
                icon: Icons.home_outlined),
            enabled: _isEditing,
            maxLines: 3,
            style: const TextStyle(fontFamily: 'DM Sans', fontSize: 14),
          ),
        ]),
      );

  // ── Bio card ──────────────────────────────────────────────────────────────
  Widget _buildBioCard() => _Card(
        child: TextFormField(
          controller: _bioCtrl,
          decoration: _fieldDeco('Bio',
              hint: 'A few words about yourself…'),
          enabled: _isEditing,
          maxLines: 5,
          maxLength: 500,
          style: const TextStyle(fontFamily: 'DM Sans', fontSize: 14),
        ),
      );

  // ── Account info card ─────────────────────────────────────────────────────
  Widget _buildAccountCard() => _Card(
        child: Column(children: [
          _ReadOnlyField(
              label: 'Role',
              value: _cap(_profile?['role'] as String? ?? 'reader'),
              icon: Icons.verified_user_outlined),
          const SizedBox(height: 16),
          _ReadOnlyField(
              label: 'Member Since',
              value: _formatDate(_profile?['created_at'] as String?),
              icon: Icons.calendar_today_outlined),
        ]),
      );

  // ── Sign out button ───────────────────────────────────────────────────────
  Widget _buildSignOutButton() => SizedBox(
        width: double.infinity,
        height: 50,
        child: OutlinedButton.icon(
          onPressed: _signOut,
          icon: Icon(Icons.logout_rounded, size: 18, color: AppColors.primary),
          label: Text('Sign Out',
              style: TextStyle(
                  fontFamily: 'DM Sans',
                  fontWeight: FontWeight.w700,
                  color: AppColors.primary)),
          style: OutlinedButton.styleFrom(
              side: BorderSide(color: AppColors.primary.withOpacity(0.4)),
              shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(14))),
        ),
      );

  // ── Bottom save bar ───────────────────────────────────────────────────────
  Widget _buildSaveBar() => Positioned(
        bottom: 0, left: 0, right: 0,
        child: Container(
          padding: EdgeInsets.fromLTRB(
              16, 12, 16, 12 + MediaQuery.of(context).padding.bottom),
          decoration: BoxDecoration(
            color: Colors.white,
            border: const Border(top: BorderSide(color: Color(0xFFE5E7EB))),
            boxShadow: [
              BoxShadow(
                  color: Colors.black.withOpacity(0.06),
                  blurRadius: 16,
                  offset: const Offset(0, -4))
            ],
          ),
          child: SizedBox(
            width: double.infinity,
            height: 52,
            child: ElevatedButton(
              onPressed: (_saving || !_hasChanges) ? null : _save,
              style: ElevatedButton.styleFrom(
                  backgroundColor:
                      _hasChanges ? AppColors.primary : const Color(0xFFE5E7EB),
                  foregroundColor:
                      _hasChanges ? Colors.white : const Color(0xFF9CA3AF),
                  elevation: _hasChanges ? 2 : 0,
                  shadowColor: AppColors.primary.withOpacity(0.35),
                  shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(14))),
              child: _saving
                  ? const SizedBox(
                      width: 22, height: 22,
                      child: CircularProgressIndicator(
                          strokeWidth: 2.5,
                          valueColor:
                              AlwaysStoppedAnimation(Colors.white)))
                  : const Text('Save Changes',
                      style: TextStyle(
                          fontFamily: 'DM Sans',
                          fontSize: 16,
                          fontWeight: FontWeight.w700)),
            ),
          ),
        ),
      );

  // ── Orders modal ──────────────────────────────────────────────────────────
  Widget _buildOrdersModal() => GestureDetector(
        onTap: () => setState(() => _showOrders = false),
        child: Container(
          color: Colors.black54,
          alignment: Alignment.bottomCenter,
          child: GestureDetector(
            onTap: () {}, // prevent closing when tapping inside
            child: Container(
              height: MediaQuery.of(context).size.height * 0.80,
              decoration: const BoxDecoration(
                  color: Color(0xFFF9F5EF),
                  borderRadius:
                      BorderRadius.vertical(top: Radius.circular(24))),
              child: Column(children: [
                // Handle
                Container(
                  width: 40, height: 4,
                  margin: const EdgeInsets.only(top: 12),
                  decoration: BoxDecoration(
                      color: const Color(0xFFD1D5DB),
                      borderRadius: BorderRadius.circular(2)),
                ),
                // Title
                Padding(
                  padding: const EdgeInsets.fromLTRB(20, 16, 20, 0),
                  child: Row(children: [
                    const Text('My Orders',
                        style: TextStyle(
                            fontFamily: 'PlayfairDisplay',
                            fontSize: 20,
                            fontWeight: FontWeight.w800,
                            color: Color(0xFF111827))),
                    const Spacer(),
                    IconButton(
                        icon: const Icon(Icons.close_rounded,
                            color: Color(0xFF6B7280)),
                        onPressed: () =>
                            setState(() => _showOrders = false)),
                  ]),
                ),
                const Divider(height: 1),

                // Content
                Expanded(
                  child: _loadingOrders
                      ? Center(
                          child: CircularProgressIndicator(
                              valueColor: AlwaysStoppedAnimation(
                                  AppColors.primary)))
                      : _orders.isEmpty
                          ? _emptyOrders()
                          : ListView.separated(
                              padding: const EdgeInsets.all(16),
                              itemCount: _orders.length,
                              separatorBuilder: (_, __) =>
                                  const SizedBox(height: 12),
                              itemBuilder: (_, i) =>
                                  _OrderCard(_orders[i], onAccessContent: (id) {
                                setState(() => _showOrders = false);
                                Navigator.pushNamed(context, '/content/$id');
                              }),
                            ),
                ),
              ]),
            ),
          ),
        ),
      );

  Widget _emptyOrders() => Center(
        child: Column(mainAxisAlignment: MainAxisAlignment.center, children: [
          Icon(Icons.receipt_long_outlined,
              size: 60, color: const Color(0xFFD1D5DB)),
          const SizedBox(height: 16),
          const Text('No orders yet',
              style: TextStyle(
                  fontFamily: 'PlayfairDisplay',
                  fontSize: 18,
                  fontWeight: FontWeight.w700,
                  color: Color(0xFF6B7280))),
          const SizedBox(height: 8),
          const Text('Your purchased books will appear here.',
              style: TextStyle(
                  fontFamily: 'DM Sans',
                  fontSize: 13,
                  color: Color(0xFF9CA3AF))),
          const SizedBox(height: 24),
          ElevatedButton(
            onPressed: () {
              setState(() => _showOrders = false);
              Navigator.pushNamed(context, '/books');
            },
            style: ElevatedButton.styleFrom(
                backgroundColor: AppColors.primary,
                foregroundColor: Colors.white,
                shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(12))),
            child: const Text('Browse Books',
                style: TextStyle(fontFamily: 'DM Sans')),
          ),
        ]),
      );

  // ── Misc helpers ──────────────────────────────────────────────────────────
  Widget _avatarPlaceholder() => Container(
        color: const Color(0xFFF3F4F6),
        child: const Icon(Icons.person_rounded,
            size: 44, color: Color(0xFFD1D5DB)),
      );

  Widget _loadingView() => Scaffold(
        backgroundColor: const Color(0xFFF9F5EF),
        body: Center(
          child: Column(mainAxisAlignment: MainAxisAlignment.center, children: [
            CircularProgressIndicator(
                valueColor: AlwaysStoppedAnimation(AppColors.primary)),
            const SizedBox(height: 20),
            const Text('Loading profile…',
                style: TextStyle(
                    fontFamily: 'DM Sans',
                    color: Color(0xFF6B7280),
                    fontSize: 14)),
          ]),
        ),
      );

  Widget _errorView() => Scaffold(
        backgroundColor: const Color(0xFFF9F5EF),
        appBar: AppBar(
            backgroundColor: Colors.white,
            elevation: 0,
            leading: IconButton(
                icon: const Icon(Icons.arrow_back_ios_new_rounded, size: 20),
                onPressed: () => Navigator.pop(context))),
        body: Center(
          child: Padding(
            padding: const EdgeInsets.all(32),
            child: Column(mainAxisAlignment: MainAxisAlignment.center, children: [
              const Icon(Icons.error_outline_rounded,
                  size: 60, color: Color(0xFFEF4444)),
              const SizedBox(height: 16),
              const Text('Could not load profile',
                  style: TextStyle(
                      fontFamily: 'PlayfairDisplay',
                      fontSize: 20,
                      fontWeight: FontWeight.w800)),
              const SizedBox(height: 8),
              Text(_loadError ?? '',
                  textAlign: TextAlign.center,
                  style: const TextStyle(
                      fontFamily: 'DM Sans',
                      color: Color(0xFF6B7280),
                      height: 1.5)),
              const SizedBox(height: 24),
              ElevatedButton(
                onPressed: _loadProfile,
                style: ElevatedButton.styleFrom(
                    backgroundColor: AppColors.primary,
                    foregroundColor: Colors.white),
                child: const Text('Try Again'),
              ),
            ]),
          ),
        ),
      );

  String _cap(String s) => s.isEmpty ? s : s[0].toUpperCase() + s.substring(1);

  String _formatDate(String? iso) {
    if (iso == null) return '—';
    try {
      final dt = DateTime.parse(iso).toLocal();
      return DateFormat('MMMM yyyy').format(dt);
    } catch (_) { return iso; }
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// ORDER CARD
// ─────────────────────────────────────────────────────────────────────────────

class _OrderCard extends StatefulWidget {
  final Map<String, dynamic> order;
  final void Function(String contentId) onAccessContent;
  const _OrderCard(this.order, {required this.onAccessContent});

  @override
  State<_OrderCard> createState() => _OrderCardState();
}

class _OrderCardState extends State<_OrderCard> {
  bool _expanded = false;

  @override
  Widget build(BuildContext context) {
    final o           = widget.order;
    final isPaid      = o['payment_status'] == 'paid';
    final orderNumber = o['order_number'] as String? ?? '—';
    final status      = o['status']       as String? ?? 'pending';
    final payStatus   = o['payment_status'] as String? ?? 'pending';
    final total       = (o['total_price'] as num?)?.toDouble() ?? 0;
    final createdAt   = o['created_at'] as String?;
    final items       = (o['order_items'] as List<dynamic>?) ?? [];

    String dateStr = '—';
    if (createdAt != null) {
      try {
        dateStr = DateFormat('d MMM yyyy').format(DateTime.parse(createdAt).toLocal());
      } catch (_) {}
    }

    final payColor = isPaid
        ? const Color(0xFF16A34A)
        : payStatus == 'failed'
            ? const Color(0xFFDC2626)
            : const Color(0xFFD97706);

    return Container(
      decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(16),
          boxShadow: [
            BoxShadow(
                color: Colors.black.withOpacity(0.04),
                blurRadius: 8,
                offset: const Offset(0, 2))
          ]),
      child: Column(children: [
        // Header
        GestureDetector(
          onTap: () => setState(() => _expanded = !_expanded),
          behavior: HitTestBehavior.opaque,
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Row(children: [
              Container(
                width: 40, height: 40,
                decoration: BoxDecoration(
                    color: isPaid
                        ? const Color(0xFFF0FDF4)
                        : const Color(0xFFFFF7ED),
                    shape: BoxShape.circle),
                child: Icon(
                    isPaid
                        ? Icons.check_circle_outline_rounded
                        : Icons.access_time_rounded,
                    color: payColor, size: 20),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                  Text('Order #$orderNumber',
                      style: const TextStyle(
                          fontFamily: 'DM Sans',
                          fontSize: 14,
                          fontWeight: FontWeight.w700,
                          color: Color(0xFF111827))),
                  const SizedBox(height: 2),
                  Text(dateStr,
                      style: const TextStyle(
                          fontFamily: 'DM Sans',
                          fontSize: 12,
                          color: Color(0xFF9CA3AF))),
                ]),
              ),
              Column(crossAxisAlignment: CrossAxisAlignment.end, children: [
                Text('KES ${_formatAmount(total)}',
                    style: TextStyle(
                        fontFamily: 'DM Sans',
                        fontSize: 14,
                        fontWeight: FontWeight.w800,
                        color: AppColors.primary)),
                const SizedBox(height: 4),
                _StatusBadge(payStatus),
              ]),
              const SizedBox(width: 8),
              Icon(
                  _expanded
                      ? Icons.keyboard_arrow_up_rounded
                      : Icons.keyboard_arrow_down_rounded,
                  color: const Color(0xFF9CA3AF)),
            ]),
          ),
        ),

        // Expanded items
        if (_expanded) ...[
          const Divider(height: 1, indent: 16, endIndent: 16),
          ...items.map<Widget>((item) {
            final i       = item as Map<String, dynamic>;
            final content = (i['content'] as Map<String, dynamic>?) ?? {};
            final title   = content['title'] as String? ?? 'Untitled';
            final imgUrl  = content['cover_image_url'] as String?;
            final cId     = content['id'] as String? ?? '';
            final qty     = (i['quantity'] as num?)?.toInt() ?? 1;
            final price   = (i['unit_price'] as num?)?.toDouble() ?? 0;

            return Padding(
              padding: const EdgeInsets.fromLTRB(16, 12, 16, 0),
              child: Row(children: [
                ClipRRect(
                  borderRadius: BorderRadius.circular(8),
                  child: SizedBox(
                    width: 44, height: 60,
                    child: imgUrl != null
                        ? CachedNetworkImage(
                            imageUrl: imgUrl, fit: BoxFit.cover,
                            errorWidget: (_, __, ___) => Container(
                                color: const Color(0xFFE5E7EB)))
                        : Container(color: const Color(0xFFE5E7EB),
                            child: const Icon(Icons.book_outlined,
                                size: 20, color: Color(0xFF9CA3AF))),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                    Text(title,
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                            fontFamily: 'DM Sans',
                            fontSize: 13,
                            fontWeight: FontWeight.w600,
                            color: Color(0xFF111827))),
                    const SizedBox(height: 2),
                    Text('Qty: $qty  ·  KES ${_formatAmount(price)}',
                        style: const TextStyle(
                            fontFamily: 'DM Sans',
                            fontSize: 11,
                            color: Color(0xFF9CA3AF))),
                  ]),
                ),
                const SizedBox(width: 8),
                if (isPaid && cId.isNotEmpty)
                  TextButton(
                    onPressed: () => widget.onAccessContent(cId),
                    style: TextButton.styleFrom(
                        foregroundColor: AppColors.primary,
                        padding: const EdgeInsets.symmetric(
                            horizontal: 10, vertical: 6)),
                    child: const Text('Read',
                        style: TextStyle(
                            fontFamily: 'DM Sans',
                            fontSize: 12,
                            fontWeight: FontWeight.w700)),
                  )
                else if (!isPaid)
                  Text('Pay to read',
                      style: const TextStyle(
                          fontFamily: 'DM Sans',
                          fontSize: 11,
                          color: Color(0xFF9CA3AF))),
              ]),
            );
          }),
          const SizedBox(height: 16),
        ],
      ]),
    );
  }

  String _formatAmount(double v) => v
      .toStringAsFixed(0)
      .replaceAllMapped(RegExp(r'\B(?=(\d{3})+(?!\d))'), (_) => ',');
}

// ─────────────────────────────────────────────────────────────────────────────
// SHARED SUB-WIDGETS
// ─────────────────────────────────────────────────────────────────────────────

class _Card extends StatelessWidget {
  final Widget child;
  const _Card({required this.child});

  @override
  Widget build(BuildContext context) => Container(
        width: double.infinity,
        padding: const EdgeInsets.all(20),
        decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(16),
            boxShadow: [
              BoxShadow(
                  color: Colors.black.withOpacity(0.04),
                  blurRadius: 8,
                  offset: const Offset(0, 2))
            ]),
        child: child,
      );
}

class _SectionHeader extends StatelessWidget {
  final String text;
  const _SectionHeader(this.text);

  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.symmetric(horizontal: 4),
        child: Text(text,
            style: const TextStyle(
                fontFamily: 'PlayfairDisplay',
                fontSize: 14,
                fontWeight: FontWeight.w700,
                color: Color(0xFF6B7280),
                letterSpacing: 0.5)),
      );
}

class _ReadOnlyField extends StatelessWidget {
  final String label, value;
  final IconData icon;
  const _ReadOnlyField(
      {required this.label, required this.value, required this.icon});

  @override
  Widget build(BuildContext context) => Container(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
        decoration: BoxDecoration(
            color: const Color(0xFFF9FAFB),
            borderRadius: BorderRadius.circular(12),
            border: Border.all(color: const Color(0xFFF3F4F6))),
        child: Row(children: [
          Icon(icon, size: 18, color: const Color(0xFF9CA3AF)),
          const SizedBox(width: 10),
          Expanded(
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text(label,
                  style: const TextStyle(
                      fontFamily: 'DM Sans',
                      fontSize: 11,
                      color: Color(0xFF9CA3AF))),
              const SizedBox(height: 2),
              Text(value,
                  style: const TextStyle(
                      fontFamily: 'DM Sans',
                      fontSize: 14,
                      fontWeight: FontWeight.w600,
                      color: Color(0xFF374151))),
            ]),
          ),
          const Icon(Icons.lock_outline_rounded,
              size: 14, color: Color(0xFFD1D5DB)),
        ]),
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

  @override
  Widget build(BuildContext context) => Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
        decoration: BoxDecoration(
            color: _color.withOpacity(0.1),
            borderRadius: BorderRadius.circular(20),
            border: Border.all(color: _color.withOpacity(0.3))),
        child: Text(
          role == 'corporate_user' ? 'Corporate' : _cap(role),
          style: TextStyle(
              fontFamily: 'DM Sans',
              fontSize: 11,
              fontWeight: FontWeight.w700,
              color: _color),
        ),
      );

  String _cap(String s) => s.isEmpty ? s : s[0].toUpperCase() + s.substring(1);
}

class _StatusBadge extends StatelessWidget {
  final String status;
  const _StatusBadge(this.status);

  @override
  Widget build(BuildContext context) {
    final (color, bg) = switch (status) {
      'paid'      => (const Color(0xFF16A34A), const Color(0xFFF0FDF4)),
      'failed'    => (const Color(0xFFDC2626), const Color(0xFFFEF2F2)),
      'cancelled' => (const Color(0xFFDC2626), const Color(0xFFFEF2F2)),
      _           => (const Color(0xFFD97706), const Color(0xFFFFFBEB)),
    };
    final label = status == 'paid' ? 'Paid' : _cap(status);
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      decoration: BoxDecoration(
          color: bg, borderRadius: BorderRadius.circular(8)),
      child: Text(label,
          style: TextStyle(
              fontFamily: 'DM Sans',
              fontSize: 10,
              fontWeight: FontWeight.w700,
              color: color)),
    );
  }

  String _cap(String s) => s.isEmpty ? s : s[0].toUpperCase() + s.substring(1);
}

class _QuickActionCard extends StatelessWidget {
  final IconData icon;
  final String label;
  final String? count;
  final Color color, bg;
  final VoidCallback onTap;

  const _QuickActionCard({
    required this.icon,
    required this.label,
    required this.color,
    required this.bg,
    required this.onTap,
    this.count,
  });

  @override
  Widget build(BuildContext context) => Expanded(
        child: GestureDetector(
          onTap: onTap,
          child: Container(
            padding: const EdgeInsets.symmetric(vertical: 14),
            decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(14),
                boxShadow: [
                  BoxShadow(
                      color: Colors.black.withOpacity(0.04),
                      blurRadius: 8,
                      offset: const Offset(0, 2))
                ]),
            child: Column(mainAxisSize: MainAxisSize.min, children: [
              Stack(children: [
                Container(
                  width: 42, height: 42,
                  decoration: BoxDecoration(color: bg, shape: BoxShape.circle),
                  child: Icon(icon, color: color, size: 20),
                ),
                if (count != null)
                  Positioned(
                    top: 0, right: 0,
                    child: Container(
                      width: 16, height: 16,
                      decoration: BoxDecoration(
                          color: color, shape: BoxShape.circle),
                      child: Center(
                        child: Text(count!,
                            style: const TextStyle(
                                fontFamily: 'DM Sans',
                                fontSize: 9,
                                fontWeight: FontWeight.w700,
                                color: Colors.white)),
                      ),
                    ),
                  ),
              ]),
              const SizedBox(height: 8),
              Text(label,
                  style: const TextStyle(
                      fontFamily: 'DM Sans',
                      fontSize: 11,
                      fontWeight: FontWeight.w600,
                      color: Color(0xFF374151))),
            ]),
          ),
        ),
      );
}

class _TypeChip extends StatelessWidget {
  final String label;
  final IconData icon;
  final bool selected, enabled;
  final VoidCallback onTap;

  const _TypeChip({
    required this.label,
    required this.icon,
    required this.selected,
    required this.enabled,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) => Expanded(
        child: GestureDetector(
          onTap: enabled ? onTap : null,
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 200),
            padding: const EdgeInsets.symmetric(vertical: 8),
            decoration: BoxDecoration(
                color: selected
                    ? AppColors.primary.withOpacity(0.08)
                    : const Color(0xFFF9FAFB),
                border: Border.all(
                    color: selected
                        ? AppColors.primary
                        : const Color(0xFFE5E7EB),
                    width: selected ? 2 : 1),
                borderRadius: BorderRadius.circular(10)),
            child: Column(mainAxisSize: MainAxisSize.min, children: [
              Icon(icon,
                  size: 18,
                  color: selected
                      ? AppColors.primary
                      : const Color(0xFFD1D5DB)),
              const SizedBox(height: 4),
              Text(label,
                  style: TextStyle(
                      fontFamily: 'DM Sans',
                      fontSize: 10,
                      fontWeight: FontWeight.w600,
                      color: selected
                          ? AppColors.primary
                          : const Color(0xFF9CA3AF))),
            ]),
          ),
        ),
      );
}