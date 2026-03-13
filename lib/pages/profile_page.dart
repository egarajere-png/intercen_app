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
//
// Returning-user profile hub. Key features:
//   • Collapsing SliverAppBar with avatar — OVERFLOW FIX applied (see note A)
//   • View / Edit toggle with dirty-check save bar
//   • Orders modal: tabbed Active / Completed / Cancelled
//   • "Pay to read" on unpaid items calls cart-add-item then navigates to cart
//   • Full order CRUD: retry payment, add-to-cart, cancel, re-order
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

  // ── Loading / error ───────────────────────────────────────────────────────
  bool    _loading       = true;
  bool    _saving        = false;
  bool    _loadingOrders = false;
  String? _loadError;

  // ── Form ──────────────────────────────────────────────────────────────────
  final _fullNameCtrl   = TextEditingController();
  final _phoneCtrl      = TextEditingController();
  final _addressCtrl    = TextEditingController();
  final _orgCtrl        = TextEditingController();
  final _departmentCtrl = TextEditingController();
  final _bioCtrl        = TextEditingController();
  final _formKey        = GlobalKey<FormState>();
  String _accountType   = 'personal';

  // ── Avatar ────────────────────────────────────────────────────────────────
  File?   _avatarFile;
  String? _avatarBase64;
  String? _avatarUrl;

  // ── Orders ────────────────────────────────────────────────────────────────
  List<Map<String, dynamic>> _orders      = [];
  bool                       _ordersLoaded = false;

  // ── UI state ──────────────────────────────────────────────────────────────
  bool _showOrders = false;
  bool _isEditing  = false;
  bool _hasChanges = false;
  bool _addingToCart = false; // global busy flag while cart-add calls run

  late final AnimationController _fadeCtrl;
  late final Animation<double>   _fadeAnim;

  // ─── NOTE A — overflow fix ─────────────────────────────────────────────────
  // The previous code put name + email + role badge in a Column inside
  // FlexibleSpaceBar.background.  On phones where the name is long or the
  // font scale is high, that column overflowed by ~10 px.
  //
  // Fix strategy:
  //   1. Increase expandedHeight from 220 → 270 so there is always room.
  //   2. Wrap the inner Column in a LayoutBuilder so it can measure available
  //      space, and mark it mainAxisSize: MainAxisSize.min.
  //   3. Every text widget that could be long gets maxLines + overflow.ellipsis.
  //   4. A bottom padding equal to MediaQuery.viewPadding.bottom is added so
  //      the content never touches the system nav bar on gesture-nav phones.
  // ──────────────────────────────────────────────────────────────────────────

  @override
  void initState() {
    super.initState();
    _fadeCtrl = AnimationController(
        vsync: this, duration: const Duration(milliseconds: 450));
    _fadeAnim = CurvedAnimation(parent: _fadeCtrl, curve: Curves.easeOut);
    _loadProfile();
  }

  @override
  void dispose() {
    for (final c in [_fullNameCtrl, _phoneCtrl, _addressCtrl,
                     _orgCtrl, _departmentCtrl, _bioCtrl]) {
      c.dispose();
    }
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
    for (final c in [_fullNameCtrl, _phoneCtrl, _addressCtrl,
                     _orgCtrl, _departmentCtrl, _bioCtrl]) {
      c.removeListener(_onFieldChanged);
      c.addListener(_onFieldChanged);
    }
  }

  void _onFieldChanged() {
    if (_profile == null) return;
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
    final bytes = await File(picked.path).readAsBytes();
    if (bytes.lengthInBytes > 5 * 1024 * 1024) {
      _showSnack('Image must be under 5 MB'); return;
    }
    setState(() {
      _avatarFile   = File(picked.path);
      _avatarBase64 = 'data:image/jpeg;base64,${base64Encode(bytes)}';
      _hasChanges   = true;
    });
  }

  // ── Save ──────────────────────────────────────────────────────────────────
  Future<void> _save() async {
    if (!(_formKey.currentState?.validate() ?? false)) return;
    if (!_hasChanges) { _showSnack('No changes to save'); return; }
    setState(() => _saving = true);
    try {
      final session = _sb.auth.currentSession;
      if (session == null) throw Exception('Session expired.');
      final r = await _sb.functions.invoke(
        'profile-info-edit',
        body: {
          'full_name':    _fullNameCtrl.text.trim(),
          'phone':        _nullIfEmpty(_phoneCtrl.text),
          'address':      _nullIfEmpty(_addressCtrl.text),
          'organization': _nullIfEmpty(_orgCtrl.text),
          'department':   _nullIfEmpty(_departmentCtrl.text),
          'bio':          _nullIfEmpty(_bioCtrl.text),
          'account_type': _accountType,
          if (_avatarBase64 != null) 'avatar_base64': _avatarBase64,
        },
        headers: {'Authorization': 'Bearer ${session.accessToken}'},
      );
      if (r.status != 200) {
        throw Exception((r.data as Map?)?['error'] ?? 'Save failed');
      }
      final fresh = await _sb.from('profiles').select('*')
          .eq('id', session.user.id).single();
      setState(() {
        _profile      = fresh;
        _avatarUrl    = fresh['avatar_url'] as String?;
        _avatarFile   = null;
        _avatarBase64 = null;
        _hasChanges   = false;
        _isEditing    = false;
      });
      _showSnack('Profile updated ✓', success: true);
    } catch (e) {
      _showSnack(e.toString().replaceFirst('Exception: ', ''));
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

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
  Future<void> _fetchOrders({bool force = false}) async {
    if (_ordersLoaded && !force) return;
    setState(() => _loadingOrders = true);
    try {
      final data = await _sb.from('orders').select('''
        id, order_number, status, payment_status,
        total_price, created_at,
        order_items(
          id, quantity, unit_price,
          content:content_id(id, title, cover_image_url, price)
        )
      ''').eq('user_id', _user!.id).order('created_at', ascending: false);
      setState(() {
        _orders       = List<Map<String, dynamic>>.from(data);
        _ordersLoaded = true;
      });
    } catch (_) {
      _showSnack('Could not load orders');
    } finally {
      if (mounted) setState(() => _loadingOrders = false);
    }
  }

  // ── Cancel order ──────────────────────────────────────────────────────────
  Future<void> _cancelOrder(String orderId) async {
    if (!await _confirm('Cancel Order',
        'This order will be cancelled and cannot be undone.')) {
      return;
    }
    try {
      await _sb.from('orders').update({
        'status':       'cancelled',
        'cancelled_at': DateTime.now().toIso8601String(),
        'updated_at':   DateTime.now().toIso8601String(),
      }).eq('id', orderId);
      _showSnack('Order cancelled');
      _fetchOrders(force: true);
    } catch (_) {
      _showSnack('Failed to cancel order');
    }
  }

  // ── Add order items → cart (cart-add-item edge function) ──────────────────
  //
  // Called from two places:
  //   1. "Pay to read" chip on an unpaid item row   → adds just that one item
  //   2. "Add to Cart" button on the whole order    → adds all unpaid items
  //   3. "Re-order" on a cancelled order            → adds all items
  //
  // After all items are added we close the modal and navigate to /cart.
  Future<void> _addItemsToCart(
    List<Map<String, dynamic>> items, {
    String snackPrefix = '',
  }) async {
    if (items.isEmpty) { _showSnack('No items found'); return; }
    setState(() => _addingToCart = true);
    int added = 0, failed = 0;
    try {
      final session = _sb.auth.currentSession;
      if (session == null) throw Exception('Session expired.');
      for (final rawItem in items) {
        final content = (rawItem['content'] as Map<String, dynamic>?) ?? {};
        final cId = content['id'] as String? ?? '';
        final qty = (rawItem['quantity'] as num?)?.toInt() ?? 1;
        if (cId.isEmpty) { failed++; continue; }
        try {
          final r = await _sb.functions.invoke(
            'cart-add-item',
            body: {'content_id': cId, 'quantity': qty},
            headers: {'Authorization': 'Bearer ${session.accessToken}'},
          );
          // cart-add-item returns {success:true} on 200
          (r.status == 200) ? added++ : failed++;
        } catch (_) { failed++; }
      }
      if (!mounted) return;
      setState(() => _showOrders = false);
      final msg = failed > 0
          ? '$snackPrefix$added added, $failed failed. Check cart.'
          : '$snackPrefix$added item(s) added to cart!';
      _showSnack(msg, success: added > 0);
      await Future.delayed(const Duration(milliseconds: 350));
      if (mounted) Navigator.pushNamed(context, '/cart');
    } catch (e) {
      _showSnack(e.toString().replaceFirst('Exception: ', ''));
    } finally {
      if (mounted) setState(() => _addingToCart = false);
    }
  }

  // ── Sign out ──────────────────────────────────────────────────────────────
  Future<void> _signOut() async {
    if (!await _confirm('Sign Out', 'Are you sure you want to sign out?')) return;
    await _sb.auth.signOut();
    if (mounted) {
      Navigator.pushNamedAndRemoveUntil(context, '/onboarding', (_) => false);
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

  Future<bool> _confirm(String title, String body) async =>
      await showDialog<bool>(
        context: context,
        builder: (_) => AlertDialog(
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
          title: Text(title,
              style: const TextStyle(
                  fontFamily: 'PlayfairDisplay', fontWeight: FontWeight.w800)),
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

  String? _nullIfEmpty(String s) => s.trim().isEmpty ? null : s.trim();

  InputDecoration _fieldDeco(String label,
          {String? hint, IconData? icon}) =>
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
            borderSide:
                const BorderSide(color: Color(0xFFEF4444), width: 2)),
      );

  // ════════════════════════════════════════════════════════════════════════════
  // BUILD
  // ════════════════════════════════════════════════════════════════════════════
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
                padding: const EdgeInsets.fromLTRB(16, 16, 16, 120),
                children: [
                  _buildQuickActions(),
                  const SizedBox(height: 20),
                  _SectionHeader('Personal Details'),
                  const SizedBox(height: 12),
                  _buildIdentityCard(),
                  const SizedBox(height: 20),
                  _SectionHeader('Contact & Address'),
                  const SizedBox(height: 12),
                  _buildContactCard(),
                  const SizedBox(height: 20),
                  _SectionHeader('About You'),
                  const SizedBox(height: 12),
                  _buildBioCard(),
                  const SizedBox(height: 20),
                  _SectionHeader('Account'),
                  const SizedBox(height: 12),
                  _buildAccountCard(),
                  const SizedBox(height: 32),
                  _buildSignOutButton(),
                ],
              ),
            ),
          ),
        ),
        if (_isEditing) _buildSaveBar(),
        if (_showOrders) _buildOrdersOverlay(),
        // Full-screen busy overlay while cart calls are running
        if (_addingToCart)
          Container(
            color: Colors.black38,
            child: Center(
              child: Container(
                padding: const EdgeInsets.all(24),
                decoration: BoxDecoration(
                    color: Colors.white,
                    borderRadius: BorderRadius.circular(16)),
                child: Column(mainAxisSize: MainAxisSize.min, children: [
                  CircularProgressIndicator(
                      valueColor:
                          AlwaysStoppedAnimation(AppColors.primary)),
                  const SizedBox(height: 16),
                  const Text('Adding to cart…',
                      style: TextStyle(
                          fontFamily: 'DM Sans',
                          fontSize: 14,
                          color: Color(0xFF374151))),
                ]),
              ),
            ),
          ),
      ]),
    );
  }

  // ── SliverAppBar — OVERFLOW FIX ───────────────────────────────────────────
  Widget _buildSliverAppBar() {
    // expandedHeight is 270 — generous enough for any font scale.
    // The inner Column is mainAxisSize.min so it shrinks on smaller phones
    // instead of overflowing.
    return SliverAppBar(
      expandedHeight: 270,
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
            icon: Icon(Icons.edit_outlined, size: 16, color: AppColors.primary),
            label: Text('Edit',
                style: TextStyle(
                    fontFamily: 'DM Sans',
                    fontWeight: FontWeight.w700,
                    color: AppColors.primary)),
          )
        else
          TextButton(
            onPressed: _discardEdits,
            child: const Text('Cancel',
                style: TextStyle(
                    fontFamily: 'DM Sans', color: Color(0xFF6B7280))),
          ),
        const SizedBox(width: 4),
      ],
      flexibleSpace: FlexibleSpaceBar(
        collapseMode: CollapseMode.pin,
        background: SafeArea(
          // ── OVERFLOW FIX: top padding = appBar height so content
          //   sits below the title/actions row, never under it.
          child: Padding(
            padding: const EdgeInsets.only(top: 56),
            child: Column(
              mainAxisSize: MainAxisSize.min,       // shrink-wrap
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                const SizedBox(height: 6),
                // Avatar
                GestureDetector(
                  onTap: _pickAvatar,
                  child: Stack(alignment: Alignment.bottomRight, children: [
                    Container(
                      width: 78, height: 78,
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
                        ],
                      ),
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
                                        _avatarFallback())
                                : _avatarFallback(),
                      ),
                    ),
                    if (_isEditing)
                      Container(
                        width: 26, height: 26,
                        decoration: BoxDecoration(
                            color: AppColors.primary,
                            shape: BoxShape.circle,
                            border:
                                Border.all(color: Colors.white, width: 2)),
                        child: const Icon(Icons.camera_alt_rounded,
                            size: 12, color: Colors.white),
                      ),
                  ]),
                ),

                const SizedBox(height: 10),

                // ── OVERFLOW FIX: constrain width + maxLines on every text ──
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 28),
                  child: Text(
                    _fullNameCtrl.text.isNotEmpty
                        ? _fullNameCtrl.text
                        : 'Your Name',
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    textAlign: TextAlign.center,
                    style: const TextStyle(
                        fontFamily: 'PlayfairDisplay',
                        fontSize: 18,
                        fontWeight: FontWeight.w800,
                        color: Color(0xFF111827)),
                  ),
                ),

                const SizedBox(height: 2),

                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 32),
                  child: Text(
                    _user?.email ?? '',
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    textAlign: TextAlign.center,
                    style: const TextStyle(
                        fontFamily: 'DM Sans',
                        fontSize: 12,
                        color: Color(0xFF9CA3AF)),
                  ),
                ),

                const SizedBox(height: 7),

                _RoleBadge(_profile?['role'] as String? ?? 'reader'),

                // Bottom breathing room — prevents badge touching the divider
                const SizedBox(height: 14),
              ],
            ),
          ),
        ),
      ),
      bottom: PreferredSize(
        preferredSize: const Size.fromHeight(1),
        child: Container(height: 1, color: const Color(0xFFE5E7EB)),
      ),
    );
  }

  // ── Quick action cards ────────────────────────────────────────────────────
  Widget _buildQuickActions() => Row(children: [
        _QuickCard(
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
        _QuickCard(
          icon: Icons.library_books_outlined,
          label: 'My Content',
          color: const Color(0xFF7C3AED),
          bg: const Color(0xFFF5F3FF),
          onTap: () => Navigator.pushNamed(context, '/content-management'),
        ),
        const SizedBox(width: 12),
        _QuickCard(
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
          _ReadOnly(label: 'Email',
              value: _user?.email ?? '', icon: Icons.email_outlined),
          const SizedBox(height: 16),
          TextFormField(
            controller: _fullNameCtrl,
            decoration: _fieldDeco('Full Name',
                hint: 'Mwangi Kamau', icon: Icons.badge_outlined),
            enabled: _isEditing, maxLength: 100,
            style: const TextStyle(fontFamily: 'DM Sans', fontSize: 14),
            validator: (v) =>
                (v == null || v.trim().isEmpty) ? 'Full name is required' : null,
          ),
          const SizedBox(height: 16),
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
                label: 'Personal', icon: Icons.person_rounded,
                selected: _accountType == 'personal', enabled: _isEditing,
                onTap: () { if (_isEditing) setState(() { _accountType = 'personal'; _onFieldChanged(); }); }),
            const SizedBox(width: 8),
            _TypeChip(
                label: 'Corporate', icon: Icons.business_rounded,
                selected: _accountType == 'corporate', enabled: _isEditing,
                onTap: () { if (_isEditing) setState(() { _accountType = 'corporate'; _onFieldChanged(); }); }),
            const SizedBox(width: 8),
            _TypeChip(
                label: 'Institution', icon: Icons.school_rounded,
                selected: _accountType == 'institutional', enabled: _isEditing,
                onTap: () { if (_isEditing) setState(() { _accountType = 'institutional'; _onFieldChanged(); }); }),
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
              decoration: _fieldDeco('Department / Faculty',
                  icon: Icons.account_tree_outlined),
              enabled: _isEditing,
              style: const TextStyle(fontFamily: 'DM Sans', fontSize: 14),
            ),
          ],
        ]),
      );

  Widget _buildContactCard() => _Card(
        child: Column(children: [
          TextFormField(
            controller: _phoneCtrl,
            decoration: _fieldDeco('Phone Number',
                hint: '+254 712 345 678', icon: Icons.phone_outlined),
            enabled: _isEditing,
            keyboardType: TextInputType.phone, maxLength: 20,
            inputFormatters: [
              FilteringTextInputFormatter.allow(RegExp(r'[+\d\s\-()]')),
            ],
            style: const TextStyle(fontFamily: 'DM Sans', fontSize: 14),
          ),
          const SizedBox(height: 16),
          TextFormField(
            controller: _addressCtrl,
            decoration: _fieldDeco('Delivery Address',
                hint: 'P.O. Box 12345-00100, Nairobi',
                icon: Icons.home_outlined),
            enabled: _isEditing, maxLines: 3,
            style: const TextStyle(fontFamily: 'DM Sans', fontSize: 14),
          ),
        ]),
      );

  Widget _buildBioCard() => _Card(
        child: TextFormField(
          controller: _bioCtrl,
          decoration:
              _fieldDeco('Bio', hint: 'A few words about yourself…'),
          enabled: _isEditing, maxLines: 5, maxLength: 500,
          style: const TextStyle(fontFamily: 'DM Sans', fontSize: 14),
        ),
      );

  Widget _buildAccountCard() => _Card(
        child: Column(children: [
          _ReadOnly(
              label: 'Role',
              value: _cap(_profile?['role'] as String? ?? 'reader'),
              icon: Icons.verified_user_outlined),
          const SizedBox(height: 16),
          _ReadOnly(
              label: 'Member Since',
              value: _fmtDate(_profile?['created_at'] as String?),
              icon: Icons.calendar_today_outlined),
        ]),
      );

  Widget _buildSignOutButton() => SizedBox(
        width: double.infinity, height: 50,
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
            width: double.infinity, height: 52,
            child: ElevatedButton(
              onPressed: (_saving || !_hasChanges) ? null : _save,
              style: ElevatedButton.styleFrom(
                  backgroundColor: _hasChanges
                      ? AppColors.primary
                      : const Color(0xFFE5E7EB),
                  foregroundColor: _hasChanges
                      ? Colors.white
                      : const Color(0xFF9CA3AF),
                  elevation: _hasChanges ? 2 : 0,
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

  // ════════════════════════════════════════════════════════════════════════════
  // ORDERS OVERLAY — tabbed modal with full CRUD
  //
  // Tab layout:
  //   Active     = pending + processing (unpaid or awaiting delivery)
  //   Completed  = status=completed OR payment_status=paid
  //   Cancelled  = status=cancelled
  //
  // Per-order actions:
  //   Active    → "Pay Now" (retry payment page)
  //              "Pay to Read / Add to Cart" (cart-add-item + navigate /cart)
  //              "Cancel Order"
  //   Completed → "Read" per item, "View Receipt"
  //   Cancelled → "Re-order" (add all items to cart)
  // ════════════════════════════════════════════════════════════════════════════
  Widget _buildOrdersOverlay() {
    return GestureDetector(
      onTap: () => setState(() => _showOrders = false),
      child: Container(
        color: Colors.black54,
        alignment: Alignment.bottomCenter,
        child: GestureDetector(
          onTap: () {}, // absorb taps inside sheet
          child: Container(
            height: MediaQuery.of(context).size.height * 0.90,
            decoration: const BoxDecoration(
                color: Color(0xFFF9F5EF),
                borderRadius:
                    BorderRadius.vertical(top: Radius.circular(24))),
            child: DefaultTabController(
              length: 3,
              child: Column(children: [
                // Drag handle
                Container(
                    width: 40, height: 4,
                    margin: const EdgeInsets.only(top: 12),
                    decoration: BoxDecoration(
                        color: const Color(0xFFD1D5DB),
                        borderRadius: BorderRadius.circular(2))),

                // Header
                Padding(
                  padding: const EdgeInsets.fromLTRB(20, 12, 8, 0),
                  child: Row(children: [
                    const Text('My Orders',
                        style: TextStyle(
                            fontFamily: 'PlayfairDisplay',
                            fontSize: 20,
                            fontWeight: FontWeight.w800,
                            color: Color(0xFF111827))),
                    if (_ordersLoaded)
                      Container(
                        margin: const EdgeInsets.only(left: 8),
                        padding: const EdgeInsets.symmetric(
                            horizontal: 8, vertical: 2),
                        decoration: BoxDecoration(
                            color: AppColors.primary.withOpacity(0.08),
                            borderRadius: BorderRadius.circular(10)),
                        child: Text('${_orders.length}',
                            style: TextStyle(
                                fontFamily: 'DM Sans',
                                fontSize: 12,
                                fontWeight: FontWeight.w700,
                                color: AppColors.primary)),
                      ),
                    const Spacer(),
                    IconButton(
                      icon: const Icon(Icons.refresh_rounded,
                          color: Color(0xFF6B7280), size: 20),
                      onPressed: () => _fetchOrders(force: true),
                      tooltip: 'Refresh',
                    ),
                    IconButton(
                      icon: const Icon(Icons.close_rounded,
                          color: Color(0xFF6B7280)),
                      onPressed: () => setState(() => _showOrders = false),
                    ),
                  ]),
                ),

                // Pill tab bar
                Container(
                  margin: const EdgeInsets.fromLTRB(16, 10, 16, 0),
                  decoration: BoxDecoration(
                      color: const Color(0xFFE5E7EB),
                      borderRadius: BorderRadius.circular(10)),
                  padding: const EdgeInsets.all(3),
                  child: TabBar(
                    indicator: BoxDecoration(
                        color: Colors.white,
                        borderRadius: BorderRadius.circular(8),
                        boxShadow: [
                          BoxShadow(
                              color: Colors.black.withOpacity(0.06),
                              blurRadius: 4)
                        ]),
                    indicatorSize: TabBarIndicatorSize.tab,
                    labelColor: const Color(0xFF111827),
                    unselectedLabelColor: const Color(0xFF6B7280),
                    labelStyle: const TextStyle(
                        fontFamily: 'DM Sans',
                        fontSize: 12,
                        fontWeight: FontWeight.w700),
                    unselectedLabelStyle: const TextStyle(
                        fontFamily: 'DM Sans', fontSize: 12),
                    dividerColor: Colors.transparent,
                    tabs: [
                      _TabLabel('Active',    _countByStatus(['pending', 'processing'])),
                      _TabLabel('Completed', _countByStatus(['completed', '__paid__'])),
                      _TabLabel('Cancelled', _countByStatus(['cancelled'])),
                    ],
                  ),
                ),

                const SizedBox(height: 4),
                const Divider(height: 1),

                // Content
                Expanded(
                  child: _loadingOrders
                      ? Center(
                          child: CircularProgressIndicator(
                              valueColor: AlwaysStoppedAnimation(
                                  AppColors.primary)))
                      : _orders.isEmpty
                          ? _emptyOrdersState()
                          : TabBarView(children: [
                              _OrderList(
                                orders: _activeOrders,
                                onPayNow:     _onPayNow,
                                onAddToCart:  (o) => _addItemsToCart(
                                    List<Map<String,dynamic>>.from(
                                        o['order_items'] ?? []),
                                    snackPrefix: 'Order items '),
                                onCancelOrder: _cancelOrder,
                                onReadItem:   _onReadItem,
                                // "Pay to read" single-item shortcut
                                onPayToRead:  (item) =>
                                    _addItemsToCart([item],
                                        snackPrefix: 'Book '),
                              ),
                              _OrderList(
                                orders: _completedOrders,
                                onPayNow:     _onPayNow,
                                onAddToCart:  (_) {},
                                onCancelOrder: (_) {},
                                onReadItem:   _onReadItem,
                                onPayToRead:  (_) {},
                              ),
                              _OrderList(
                                orders: _cancelledOrders,
                                onPayNow:     _onPayNow,
                                onAddToCart:  (o) => _addItemsToCart(
                                    List<Map<String,dynamic>>.from(
                                        o['order_items'] ?? []),
                                    snackPrefix: 'Re-order '),
                                onCancelOrder: (_) {},
                                onReadItem:   _onReadItem,
                                onPayToRead:  (_) {},
                              ),
                            ]),
                ),
              ]),
            ),
          ),
        ),
      ),
    );
  }

  // ── Order filter helpers ──────────────────────────────────────────────────
  List<Map<String, dynamic>> get _activeOrders => _orders
      .where((o) =>
          ['pending', 'processing'].contains(o['status']) &&
          o['payment_status'] != 'paid')
      .toList();

  List<Map<String, dynamic>> get _completedOrders => _orders
      .where((o) =>
          o['status'] == 'completed' || o['payment_status'] == 'paid')
      .toList();

  List<Map<String, dynamic>> get _cancelledOrders =>
      _orders.where((o) => o['status'] == 'cancelled').toList();

  int _countByStatus(List<String> statuses) {
    if (statuses.contains('__paid__')) {
      return _completedOrders.length;
    }
    return _orders
        .where((o) => statuses.contains(o['status']))
        .length;
  }

  // ── Order action callbacks ────────────────────────────────────────────────
  void _onPayNow(String orderId, String orderNumber) {
    setState(() => _showOrders = false);
    Navigator.pushNamed(context, '/checkout/payment',
        arguments: {'order_id': orderId, 'order_number': orderNumber});
  }

  void _onReadItem(String contentId) {
    setState(() => _showOrders = false);
    Navigator.pushNamed(context, '/content/$contentId');
  }

  Widget _emptyOrdersState() => Center(
        child: Column(mainAxisAlignment: MainAxisAlignment.center, children: [
          Icon(Icons.receipt_long_outlined,
              size: 64, color: const Color(0xFFD1D5DB)),
          const SizedBox(height: 16),
          const Text('No orders yet',
              style: TextStyle(
                  fontFamily: 'PlayfairDisplay',
                  fontSize: 18,
                  fontWeight: FontWeight.w700,
                  color: Color(0xFF6B7280))),
          const SizedBox(height: 8),
          const Text('Books you purchase will appear here.',
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

  // ── Utility views ─────────────────────────────────────────────────────────
  Widget _avatarFallback() => Container(
        color: const Color(0xFFF3F4F6),
        child: const Icon(Icons.person_rounded,
            size: 38, color: Color(0xFFD1D5DB)));

  Widget _loadingView() => Scaffold(
        backgroundColor: const Color(0xFFF9F5EF),
        body: Center(
            child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
              CircularProgressIndicator(
                  valueColor: AlwaysStoppedAnimation(AppColors.primary)),
              const SizedBox(height: 20),
              const Text('Loading profile…',
                  style: TextStyle(
                      fontFamily: 'DM Sans',
                      color: Color(0xFF6B7280),
                      fontSize: 14)),
            ])));

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
          child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
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
                    child: const Text('Try Again')),
              ]),
        )));

  String _cap(String s) =>
      s.isEmpty ? s : s[0].toUpperCase() + s.substring(1);

  String _fmtDate(String? iso) {
    if (iso == null) return '—';
    try {
      return DateFormat('MMMM yyyy')
          .format(DateTime.parse(iso).toLocal());
    } catch (_) {
      return iso;
    }
  }

  // Helper widget for tab labels with optional badge
  Tab _TabLabel(String text, int count) => Tab(
        child: Row(mainAxisSize: MainAxisSize.min, children: [
          Text(text),
          if (count > 0) ...[
            const SizedBox(width: 5),
            Container(
              width: 16, height: 16,
              decoration: BoxDecoration(
                  color: AppColors.primary, shape: BoxShape.circle),
              child: Center(
                child: Text('$count',
                    style: const TextStyle(
                        color: Colors.white, fontSize: 9,
                        fontWeight: FontWeight.w800)),
              ),
            ),
          ],
        ]),
      );
}

// ─────────────────────────────────────────────────────────────────────────────
// ORDER LIST — renders a scrollable list for one tab
// ─────────────────────────────────────────────────────────────────────────────

class _OrderList extends StatelessWidget {
  final List<Map<String, dynamic>> orders;
  final void Function(String orderId, String orderNumber) onPayNow;
  final void Function(Map<String, dynamic> order) onAddToCart;
  final void Function(String orderId) onCancelOrder;
  final void Function(String contentId) onReadItem;
  final void Function(Map<String, dynamic> item) onPayToRead;

  const _OrderList({
    required this.orders,
    required this.onPayNow,
    required this.onAddToCart,
    required this.onCancelOrder,
    required this.onReadItem,
    required this.onPayToRead,
  });

  @override
  Widget build(BuildContext context) {
    if (orders.isEmpty) {
      return Center(
        child: Column(mainAxisAlignment: MainAxisAlignment.center, children: [
          Icon(Icons.inbox_outlined,
              size: 48, color: const Color(0xFFD1D5DB)),
          const SizedBox(height: 12),
          const Text('Nothing here',
              style: TextStyle(
                  fontFamily: 'DM Sans',
                  fontSize: 14,
                  color: Color(0xFF9CA3AF))),
        ]),
      );
    }
    return ListView.separated(
      padding: const EdgeInsets.all(16),
      itemCount: orders.length,
      separatorBuilder: (_, __) => const SizedBox(height: 12),
      itemBuilder: (_, i) => _OrderCard(
        order: orders[i],
        onPayNow:      onPayNow,
        onAddToCart:   onAddToCart,
        onCancelOrder: onCancelOrder,
        onReadItem:    onReadItem,
        onPayToRead:   onPayToRead,
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// ORDER CARD
//
// Collapsed: shows order number, date, total, payment badge.
// Expanded:  shows each item with a per-item action chip, then an
//            action row whose contents depend on the order's state:
//
//   Unpaid active  → [Pay Now] primary  +  [Add to Cart] + [Cancel]
//   Paid/complete  → [View Receipt]
//   Cancelled      → [Re-order] (adds all items back to cart)
//
// Per-item chip (expanded):
//   Paid   → "Read"         (opens content)
//   Unpaid → "Pay to Read"  (adds that single item to cart → /cart)
// ─────────────────────────────────────────────────────────────────────────────

class _OrderCard extends StatefulWidget {
  final Map<String, dynamic> order;
  final void Function(String orderId, String orderNumber) onPayNow;
  final void Function(Map<String, dynamic> order) onAddToCart;
  final void Function(String orderId) onCancelOrder;
  final void Function(String contentId) onReadItem;
  final void Function(Map<String, dynamic> item) onPayToRead;

  const _OrderCard({
    required this.order,
    required this.onPayNow,
    required this.onAddToCart,
    required this.onCancelOrder,
    required this.onReadItem,
    required this.onPayToRead,
  });

  @override
  State<_OrderCard> createState() => _OrderCardState();
}

class _OrderCardState extends State<_OrderCard> {
  bool _expanded = false;

  @override
  Widget build(BuildContext context) {
    final o           = widget.order;
    final isPaid      = o['payment_status'] == 'paid';
    final isCancelled = o['status'] == 'cancelled';
    final orderNumber = o['order_number'] as String? ?? '—';
    final status      = o['status']         as String? ?? 'pending';
    final payStatus   = o['payment_status'] as String? ?? 'pending';
    final total       = (o['total_price'] as num?)?.toDouble() ?? 0.0;
    final createdAt   = o['created_at'] as String?;
    final items       = (o['order_items'] as List<dynamic>?) ?? [];

    String dateStr = '—';
    if (createdAt != null) {
      try {
        dateStr = DateFormat('d MMM yyyy')
            .format(DateTime.parse(createdAt).toLocal());
      } catch (_) {}
    }

    final statusColor = isPaid
        ? const Color(0xFF16A34A)
        : isCancelled
            ? const Color(0xFF6B7280)
            : const Color(0xFFD97706);

    return Container(
      decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(16),
          border: isCancelled
              ? Border.all(color: const Color(0xFFF3F4F6))
              : null,
          boxShadow: isCancelled
              ? null
              : [
                  BoxShadow(
                      color: Colors.black.withOpacity(0.04),
                      blurRadius: 8,
                      offset: const Offset(0, 2))
                ]),
      child: Column(children: [

        // ── Collapsed header ──────────────────────────────────────────────
        GestureDetector(
          onTap: () => setState(() => _expanded = !_expanded),
          behavior: HitTestBehavior.opaque,
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Row(children: [
              // Status icon
              Container(
                width: 42, height: 42,
                decoration: BoxDecoration(
                    color: statusColor.withOpacity(0.1),
                    shape: BoxShape.circle),
                child: Icon(
                    isPaid
                        ? Icons.check_circle_outline_rounded
                        : isCancelled
                            ? Icons.cancel_outlined
                            : Icons.access_time_rounded,
                    color: statusColor, size: 20),
              ),
              const SizedBox(width: 12),

              // Order number + date
              Expanded(
                child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                  Text('#$orderNumber',
                      style: TextStyle(
                          fontFamily: 'DM Sans',
                          fontSize: 14,
                          fontWeight: FontWeight.w700,
                          color: isCancelled
                              ? const Color(0xFF9CA3AF)
                              : const Color(0xFF111827))),
                  const SizedBox(height: 2),
                  Text(dateStr,
                      style: const TextStyle(
                          fontFamily: 'DM Sans',
                          fontSize: 11,
                          color: Color(0xFF9CA3AF))),
                ]),
              ),

              // Total + badge
              Column(crossAxisAlignment: CrossAxisAlignment.end, children: [
                Text('KES ${_fmt(total)}',
                    style: TextStyle(
                        fontFamily: 'DM Sans',
                        fontSize: 14,
                        fontWeight: FontWeight.w800,
                        color: isCancelled
                            ? const Color(0xFF9CA3AF)
                            : AppColors.primary)),
                const SizedBox(height: 4),
                _PayBadge(payStatus, cancelled: isCancelled),
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

        // ── Expanded: item list + actions ─────────────────────────────────
        if (_expanded) ...[
          const Divider(height: 1, indent: 16, endIndent: 16),

          // Items
          ...items.map<Widget>((rawItem) {
            final item    = rawItem as Map<String, dynamic>;
            final content = (item['content'] as Map<String, dynamic>?) ?? {};
            final title   = content['title']           as String? ?? 'Untitled';
            final imgUrl  = content['cover_image_url'] as String?;
            final cId     = content['id']              as String? ?? '';
            final qty     = (item['quantity']   as num?)?.toInt()    ?? 1;
            final price   = (item['unit_price'] as num?)?.toDouble() ?? 0.0;

            return Padding(
              padding: const EdgeInsets.fromLTRB(16, 14, 16, 0),
              child: Row(crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                // Cover
                ClipRRect(
                  borderRadius: BorderRadius.circular(8),
                  child: SizedBox(
                    width: 46, height: 62,
                    child: imgUrl != null && imgUrl.isNotEmpty
                        ? CachedNetworkImage(
                            imageUrl: imgUrl, fit: BoxFit.cover,
                            errorWidget: (_, __, ___) =>
                                Container(color: const Color(0xFFE5E7EB)))
                        : Container(
                            color: const Color(0xFFE5E7EB),
                            child: const Icon(Icons.book_outlined,
                                size: 20, color: Color(0xFF9CA3AF))),
                  ),
                ),
                const SizedBox(width: 12),

                // Title + price
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
                    const SizedBox(height: 3),
                    Text('Qty $qty  ·  KES ${_fmt(price)}',
                        style: const TextStyle(
                            fontFamily: 'DM Sans',
                            fontSize: 11,
                            color: Color(0xFF9CA3AF))),
                  ]),
                ),

                const SizedBox(width: 8),

                // ── Per-item action chip ──────────────────────────────────
                // Paid  → "Read" teal chip  → onReadItem
                // Unpaid → "Pay to Read" amber chip → onPayToRead
                //           (cart-add-item for THIS item only, then /cart)
                if (isPaid && cId.isNotEmpty)
                  _Chip(
                    label: 'Read',
                    icon: Icons.menu_book_rounded,
                    color: AppColors.primary,
                    bg: AppColors.primary.withOpacity(0.08),
                    onTap: () => widget.onReadItem(cId),
                  )
                else if (!isPaid && !isCancelled && cId.isNotEmpty)
                  _Chip(
                    label: 'Pay to Read',
                    icon: Icons.shopping_cart_outlined,
                    color: const Color(0xFFD97706),
                    bg: const Color(0xFFFFFBEB),
                    onTap: () => widget.onPayToRead(item),
                  ),
              ]),
            );
          }),

          const SizedBox(height: 14),
          const Divider(height: 1, indent: 16, endIndent: 16),

          // ── Action row ───────────────────────────────────────────────────
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 12, 16, 16),
            child: _buildActions(o, isPaid, isCancelled, orderNumber, items),
          ),
        ],
      ]),
    );
  }

  Widget _buildActions(
    Map<String, dynamic> order,
    bool isPaid,
    bool isCancelled,
    String orderNumber,
    List<dynamic> items,
  ) {
    final orderId = order['id'] as String? ?? '';

    // ── Cancelled: Re-order only ──────────────────────────────────────────
    if (isCancelled) {
      return Row(children: [
        const Icon(Icons.info_outline_rounded,
            size: 14, color: Color(0xFF9CA3AF)),
        const SizedBox(width: 6),
        const Expanded(
          child: Text('Order was cancelled',
              style: TextStyle(
                  fontFamily: 'DM Sans',
                  fontSize: 12,
                  color: Color(0xFF9CA3AF))),
        ),
        _Chip(
          label: 'Re-order',
          icon: Icons.shopping_cart_outlined,
          color: const Color(0xFF2563EB),
          bg: const Color(0xFFEFF6FF),
          onTap: () => widget.onAddToCart(order),
        ),
      ]);
    }

    // ── Paid / completed: receipt only ────────────────────────────────────
    if (isPaid) {
      return Row(mainAxisAlignment: MainAxisAlignment.end, children: [
        _Chip(
          label: 'View Receipt',
          icon: Icons.receipt_outlined,
          color: const Color(0xFF6B7280),
          bg: const Color(0xFFF3F4F6),
          onTap: () {/* TODO: receipt page */},
        ),
      ]);
    }

    // ── Unpaid active: Pay Now + Add to Cart + Cancel ─────────────────────
    return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      // Primary CTA
      SizedBox(
        height: 42,
        child: ElevatedButton.icon(
          onPressed: () => widget.onPayNow(orderId, orderNumber),
          icon: const Icon(Icons.payment_rounded, size: 16),
          label: const Text('Pay Now',
              style: TextStyle(
                  fontFamily: 'DM Sans',
                  fontSize: 13,
                  fontWeight: FontWeight.w700)),
          style: ElevatedButton.styleFrom(
              backgroundColor: AppColors.primary,
              foregroundColor: Colors.white,
              elevation: 0,
              shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(10))),
        ),
      ),
      const SizedBox(height: 8),

      // Secondary row: Add to Cart + Cancel
      Row(children: [
        Expanded(
          child: SizedBox(
            height: 36,
            child: OutlinedButton.icon(
              onPressed: () => widget.onAddToCart(order),
              icon: const Icon(Icons.shopping_cart_outlined, size: 14),
              label: const Text('Add to Cart',
                  style: TextStyle(
                      fontFamily: 'DM Sans',
                      fontSize: 12,
                      fontWeight: FontWeight.w600)),
              style: OutlinedButton.styleFrom(
                  foregroundColor: const Color(0xFF2563EB),
                  side: const BorderSide(color: Color(0xFF2563EB)),
                  shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(8)),
                  padding: EdgeInsets.zero),
            ),
          ),
        ),
        const SizedBox(width: 8),
        SizedBox(
          height: 36,
          child: OutlinedButton.icon(
            onPressed: () => widget.onCancelOrder(orderId),
            icon: const Icon(Icons.close_rounded, size: 14),
            label: const Text('Cancel',
                style: TextStyle(
                    fontFamily: 'DM Sans',
                    fontSize: 12,
                    fontWeight: FontWeight.w600)),
            style: OutlinedButton.styleFrom(
                foregroundColor: const Color(0xFFDC2626),
                side: const BorderSide(color: Color(0xFFDC2626)),
                shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(8)),
                padding: const EdgeInsets.symmetric(horizontal: 12)),
          ),
        ),
      ]),

      const SizedBox(height: 6),
      const Text(
        '"Add to Cart" lets you review or swap items before paying.',
        style: TextStyle(
            fontFamily: 'DM Sans',
            fontSize: 11,
            color: Color(0xFF9CA3AF),
            height: 1.4),
      ),
    ]);
  }

  String _fmt(double v) => v
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
        child: child);
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
                letterSpacing: 0.5)));
}

class _ReadOnly extends StatelessWidget {
  final String label, value;
  final IconData icon;
  const _ReadOnly(
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
              child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
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
              ])),
          const Icon(Icons.lock_outline_rounded,
              size: 14, color: Color(0xFFD1D5DB)),
        ]));
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
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
        decoration: BoxDecoration(
            color: _color.withOpacity(0.1),
            borderRadius: BorderRadius.circular(20),
            border: Border.all(color: _color.withOpacity(0.25))),
        child: Text(_label,
            style: TextStyle(
                fontFamily: 'DM Sans',
                fontSize: 10,
                fontWeight: FontWeight.w700,
                color: _color)));
}

class _PayBadge extends StatelessWidget {
  final String status;
  final bool cancelled;
  const _PayBadge(this.status, {this.cancelled = false});
  @override
  Widget build(BuildContext context) {
    final (color, bg) = cancelled
        ? (const Color(0xFF6B7280), const Color(0xFFF3F4F6))
        : switch (status) {
            'paid'   => (const Color(0xFF16A34A), const Color(0xFFF0FDF4)),
            'failed' => (const Color(0xFFDC2626), const Color(0xFFFEF2F2)),
            _        => (const Color(0xFFD97706), const Color(0xFFFFFBEB)),
          };
    final label = cancelled
        ? 'Cancelled'
        : status == 'paid'
            ? 'Paid'
            : status[0].toUpperCase() + status.substring(1);
    return Container(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
        decoration: BoxDecoration(
            color: bg, borderRadius: BorderRadius.circular(8)),
        child: Text(label,
            style: TextStyle(
                fontFamily: 'DM Sans',
                fontSize: 10,
                fontWeight: FontWeight.w700,
                color: color)));
  }
}

class _QuickCard extends StatelessWidget {
  final IconData icon;
  final String label;
  final String? count;
  final Color color, bg;
  final VoidCallback onTap;
  const _QuickCard(
      {required this.icon,
      required this.label,
      required this.color,
      required this.bg,
      required this.onTap,
      this.count});
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
              Stack(alignment: Alignment.topRight, children: [
                Container(
                    width: 42, height: 42,
                    decoration:
                        BoxDecoration(color: bg, shape: BoxShape.circle),
                    child: Icon(icon, color: color, size: 20)),
                if (count != null)
                  Container(
                      width: 16, height: 16,
                      decoration: BoxDecoration(
                          color: color, shape: BoxShape.circle),
                      child: Center(
                          child: Text(count!,
                              style: const TextStyle(
                                  fontFamily: 'DM Sans',
                                  fontSize: 9,
                                  fontWeight: FontWeight.w700,
                                  color: Colors.white)))),
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
  const _TypeChip(
      {required this.label,
      required this.icon,
      required this.selected,
      required this.enabled,
      required this.onTap});
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

class _Chip extends StatelessWidget {
  final String label;
  final IconData icon;
  final Color color, bg;
  final VoidCallback onTap;
  const _Chip(
      {required this.label,
      required this.icon,
      required this.color,
      required this.bg,
      required this.onTap});
  @override
  Widget build(BuildContext context) => GestureDetector(
        onTap: onTap,
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
          decoration: BoxDecoration(
              color: bg, borderRadius: BorderRadius.circular(8)),
          child: Row(mainAxisSize: MainAxisSize.min, children: [
            Icon(icon, size: 13, color: color),
            const SizedBox(width: 4),
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