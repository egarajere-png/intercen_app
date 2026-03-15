// lib/pages/profile_page.dart
//
// Reusable profile editor. Used embedded inside all three dashboards
// (via embeddedMode: true) so each role's dashboard can include it as a tab
// without its own Scaffold/AppBar.

import 'dart:io';
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:image_picker/image_picker.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:cached_network_image/cached_network_image.dart';

import '../services/role_service.dart';

class ProfilePage extends StatefulWidget {
  /// When true, renders without its own Scaffold (used as a tab inside dashboards).
  final bool embeddedMode;
  const ProfilePage({super.key, this.embeddedMode = false});
  @override
  State<ProfilePage> createState() => _ProfilePageState();
}

class _ProfilePageState extends State<ProfilePage> {
  final _sb     = Supabase.instance.client;
  final _picker = ImagePicker();
  final _formKey = GlobalKey<FormState>();

  Map<String, dynamic>? _profile;
  bool _loading  = true;
  bool _saving   = false;
  bool _editing  = false;
  bool _hasChange = false;
  String? _error;

  final _nameCtrl   = TextEditingController();
  final _phoneCtrl  = TextEditingController();
  final _addrCtrl   = TextEditingController();
  final _orgCtrl    = TextEditingController();
  final _deptCtrl   = TextEditingController();
  final _bioCtrl    = TextEditingController();
  String _acctType  = 'personal';

  File?   _avatarFile;
  String? _avatarB64;
  String? _avatarUrl;

  @override
  void initState() { super.initState(); _load(); }

  @override
  void dispose() {
    for (final c in [_nameCtrl, _phoneCtrl, _addrCtrl,
                     _orgCtrl, _deptCtrl, _bioCtrl]) c.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    setState(() { _loading = true; _error = null; });
    try {
      final uid = _sb.auth.currentUser?.id ?? RoleService.instance.userId;
      if (uid.isEmpty) { setState(() => _error = 'Not signed in.'); return; }

      final data = await _sb.from('profiles').select('*')
          .eq('id', uid).maybeSingle();
      if (data == null) { setState(() => _error = 'Profile not found.'); return; }

      _profile = data;
      _fill(data);
    } catch (e) {
      setState(() => _error = e.toString().replaceFirst('Exception: ', ''));
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  void _fill(Map<String, dynamic> p) {
    _nameCtrl.text  = p['full_name']    as String? ?? '';
    _phoneCtrl.text = p['phone']        as String? ?? '';
    _addrCtrl.text  = p['address']      as String? ?? '';
    _orgCtrl.text   = p['organization'] as String? ?? '';
    _deptCtrl.text  = p['department']   as String? ?? '';
    _bioCtrl.text   = p['bio']          as String? ?? '';
    _acctType       = p['account_type'] as String? ?? 'personal';
    _avatarUrl      = p['avatar_url']   as String?;

    for (final c in [_nameCtrl, _phoneCtrl, _addrCtrl,
                     _orgCtrl, _deptCtrl, _bioCtrl]) {
      c.removeListener(_onChange);
      c.addListener(_onChange);
    }
  }

  void _onChange() {
    if (_profile == null) return;
    final p = _profile!;
    setState(() {
      _hasChange =
          _nameCtrl.text  != (p['full_name']    ?? '') ||
          _phoneCtrl.text != (p['phone']        ?? '') ||
          _addrCtrl.text  != (p['address']      ?? '') ||
          _orgCtrl.text   != (p['organization'] ?? '') ||
          _deptCtrl.text  != (p['department']   ?? '') ||
          _bioCtrl.text   != (p['bio']          ?? '') ||
          _acctType       != (p['account_type'] ?? 'personal') ||
          _avatarB64 != null;
    });
  }

  Future<void> _pickAvatar() async {
    if (!_editing) return;
    final f = await _picker.pickImage(
        source: ImageSource.gallery, imageQuality: 80, maxWidth: 512);
    if (f == null) return;
    final bytes = await File(f.path).readAsBytes();
    if (bytes.lengthInBytes > 5 * 1024 * 1024) {
      _snack('Image must be under 5 MB'); return;
    }
    setState(() {
      _avatarFile = File(f.path);
      _avatarB64  = 'data:image/jpeg;base64,${base64Encode(bytes)}';
      _hasChange  = true;
    });
  }

  Future<void> _save() async {
    if (!(_formKey.currentState?.validate() ?? false)) return;
    if (!_hasChange) { _snack('No changes to save'); return; }
    setState(() => _saving = true);
    try {
      final session = _sb.auth.currentSession;
      if (session == null) throw Exception('Session expired.');

      final res = await _sb.functions.invoke(
        'profile-info-edit',
        body: {
          'full_name':    _nameCtrl.text.trim(),
          'phone':        _e(_phoneCtrl.text),
          'address':      _e(_addrCtrl.text),
          'organization': _e(_orgCtrl.text),
          'department':   _e(_deptCtrl.text),
          'bio':          _e(_bioCtrl.text),
          'account_type': _acctType,
          if (_avatarB64 != null) 'avatar_base64': _avatarB64,
        },
        headers: {'Authorization': 'Bearer ${session.accessToken}'},
      );
      if (res.status != 200) {
        throw Exception((res.data as Map?)?['error'] ?? 'Save failed');
      }

      final fresh = await _sb.from('profiles').select('*')
          .eq('id', session.user.id).single();
      setState(() {
        _profile   = fresh;
        _avatarUrl = fresh['avatar_url'] as String?;
        _avatarFile = null;
        _avatarB64  = null;
        _hasChange  = false;
        _editing    = false;
      });
      _snack('Profile updated ✓', success: true);
    } catch (e) {
      _snack(e.toString().replaceFirst('Exception: ', ''));
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  void _discard() {
    if (_profile != null) _fill(_profile!);
    setState(() {
      _editing    = false;
      _hasChange  = false;
      _avatarFile = null;
      _avatarB64  = null;
    });
  }

  String? _e(String s) => s.trim().isEmpty ? null : s.trim();

  void _snack(String msg, {bool success = false}) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(
      content: Text(msg, style: const TextStyle(fontFamily: 'DM Sans')),
      backgroundColor: success ? const Color(0xFF16A34A) : const Color(0xFFB11226),
      behavior: SnackBarBehavior.floating,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
    ));
  }

  // ── BUILD ────────────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    if (_loading) {
      return const Center(child: CircularProgressIndicator(
          color: Color(0xFFB11226)));
    }
    if (_error != null) {
      return Center(child: Column(mainAxisAlignment: MainAxisAlignment.center,
          children: [
        const Icon(Icons.error_outline_rounded,
            size: 48, color: Color(0xFFEF4444)),
        const SizedBox(height: 12),
        Text(_error!, style: const TextStyle(fontFamily: 'DM Sans',
            color: Color(0xFF6B7280))),
        const SizedBox(height: 16),
        ElevatedButton(onPressed: _load, child: const Text('Retry'),
            style: ElevatedButton.styleFrom(
                backgroundColor: const Color(0xFFB11226),
                foregroundColor: Colors.white)),
      ]));
    }

    final body = Stack(children: [
      Form(
        key: _formKey,
        child: ListView(
          padding: const EdgeInsets.fromLTRB(16, 16, 16, 120),
          children: [
            _avatarSection(),
            const SizedBox(height: 20),
            _Section('Personal Details'),
            const SizedBox(height: 10),
            _card(_personalFields()),
            const SizedBox(height: 20),
            _Section('Contact'),
            const SizedBox(height: 10),
            _card(_contactFields()),
            const SizedBox(height: 20),
            _Section('About You'),
            const SizedBox(height: 10),
            _card(_bioField()),
            const SizedBox(height: 20),
            _Section('Account Info'),
            const SizedBox(height: 10),
            _card(_accountInfo()),
          ],
        ),
      ),
      if (_editing) _saveBar(),
    ]);

    if (widget.embeddedMode) return body;

    return Scaffold(
      backgroundColor: const Color(0xFFF9F5EF),
      appBar: AppBar(
        backgroundColor: Colors.white,
        surfaceTintColor: Colors.transparent,
        elevation: 0,
        title: const Text('My Profile',
            style: TextStyle(
                fontFamily: 'PlayfairDisplay',
                fontWeight: FontWeight.w800,
                fontSize: 20,
                color: Color(0xFF111827))),
        actions: [
          if (!_editing)
            TextButton(
              onPressed: () => setState(() => _editing = true),
              child: const Text('Edit',
                  style: TextStyle(
                      fontFamily: 'DM Sans',
                      fontWeight: FontWeight.w700,
                      color: Color(0xFFB11226))),
            )
          else
            TextButton(
              onPressed: _discard,
              child: const Text('Cancel',
                  style: TextStyle(
                      fontFamily: 'DM Sans',
                      color: Color(0xFF6B7280))),
            ),
          const SizedBox(width: 8),
        ],
        bottom: const PreferredSize(
          preferredSize: Size.fromHeight(1),
          child: Divider(height: 1, color: Color(0xFFE5E7EB)),
        ),
      ),
      body: body,
    );
  }

  // ── Avatar ────────────────────────────────────────────────────────────────
  Widget _avatarSection() => Center(
        child: Column(children: [
          GestureDetector(
            onTap: _pickAvatar,
            child: Stack(alignment: Alignment.bottomRight, children: [
              Container(
                width: 80, height: 80,
                decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    border: Border.all(
                        color: const Color(0xFFB11226).withOpacity(0.25),
                        width: 3),
                    boxShadow: [BoxShadow(
                        color: Colors.black.withOpacity(0.08),
                        blurRadius: 12,
                        offset: const Offset(0, 4))]),
                child: ClipOval(
                  child: _avatarFile != null
                      ? Image.file(_avatarFile!, fit: BoxFit.cover)
                      : _avatarUrl != null && _avatarUrl!.isNotEmpty
                          ? CachedNetworkImage(imageUrl: _avatarUrl!,
                              fit: BoxFit.cover)
                          : Container(
                              color: const Color(0xFFF3F4F6),
                              child: Center(child: Text(
                                (_nameCtrl.text.isNotEmpty
                                    ? _nameCtrl.text : '?')[0].toUpperCase(),
                                style: const TextStyle(
                                    fontFamily: 'PlayfairDisplay',
                                    fontSize: 32,
                                    fontWeight: FontWeight.w800,
                                    color: Color(0xFF9CA3AF))))),
                ),
              ),
              if (_editing)
                Container(
                  width: 26, height: 26,
                  decoration: BoxDecoration(
                      color: const Color(0xFFB11226),
                      shape: BoxShape.circle,
                      border: Border.all(color: Colors.white, width: 2)),
                  child: const Icon(Icons.camera_alt_rounded,
                      size: 13, color: Colors.white),
                ),
            ]),
          ),
          const SizedBox(height: 10),
          Text(
            _nameCtrl.text.isNotEmpty ? _nameCtrl.text : 'Your Name',
            style: const TextStyle(
                fontFamily: 'PlayfairDisplay',
                fontSize: 20,
                fontWeight: FontWeight.w800,
                color: Color(0xFF111827)),
          ),
          const SizedBox(height: 4),
          Text(_sb.auth.currentUser?.email ?? '',
              style: const TextStyle(
                  fontFamily: 'DM Sans', fontSize: 13,
                  color: Color(0xFF9CA3AF))),
          const SizedBox(height: 6),
          _RoleBadge(RoleService.instance.role),
          if (!_editing) ...[
            const SizedBox(height: 12),
            OutlinedButton.icon(
              onPressed: () => setState(() => _editing = true),
              icon: const Icon(Icons.edit_outlined, size: 16),
              label: const Text('Edit Profile',
                  style: TextStyle(fontFamily: 'DM Sans', fontWeight: FontWeight.w600)),
              style: OutlinedButton.styleFrom(
                  foregroundColor: const Color(0xFFB11226),
                  side: BorderSide(
                      color: const Color(0xFFB11226).withOpacity(0.4)),
                  shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(10))),
            ),
          ],
        ]),
      );

  // ── Form fields ───────────────────────────────────────────────────────────
  Widget _personalFields() => Column(children: [
    // Read-only email
    _ReadOnly(label: 'Email', value: _sb.auth.currentUser?.email ?? '',
        icon: Icons.email_outlined),
    const SizedBox(height: 14),

    TextFormField(
      controller: _nameCtrl, enabled: _editing, maxLength: 100,
      decoration: _deco('Full Name', hint: 'Mwangi Kamau',
          icon: Icons.badge_outlined),
      validator: (v) => v == null || v.trim().isEmpty ? 'Required' : null,
      style: const TextStyle(fontFamily: 'DM Sans', fontSize: 14),
    ),
    const SizedBox(height: 14),

    // Account type chips
    const Align(alignment: Alignment.centerLeft,
      child: Text('Account Type', style: TextStyle(fontFamily: 'DM Sans',
          fontSize: 13, fontWeight: FontWeight.w600,
          color: Color(0xFF374151)))),
    const SizedBox(height: 8),
    Row(children: [
      _TypeChip('Personal',    Icons.person_rounded,   'personal'),
      const SizedBox(width: 8),
      _TypeChip('Corporate',   Icons.business_rounded, 'corporate'),
      const SizedBox(width: 8),
      _TypeChip('Institution', Icons.school_rounded,   'institutional'),
    ]),

    if (_acctType != 'personal') ...[
      const SizedBox(height: 14),
      TextFormField(
        controller: _orgCtrl, enabled: _editing,
        decoration: _deco(
            _acctType == 'corporate' ? 'Company / Organization' : 'Institution',
            icon: Icons.domain_rounded),
        style: const TextStyle(fontFamily: 'DM Sans', fontSize: 14),
      ),
      const SizedBox(height: 14),
      TextFormField(
        controller: _deptCtrl, enabled: _editing,
        decoration: _deco('Department / Faculty',
            icon: Icons.account_tree_outlined),
        style: const TextStyle(fontFamily: 'DM Sans', fontSize: 14),
      ),
    ],
  ]);

  Widget _contactFields() => Column(children: [
    TextFormField(
      controller: _phoneCtrl, enabled: _editing, maxLength: 20,
      keyboardType: TextInputType.phone,
      inputFormatters: [FilteringTextInputFormatter.allow(RegExp(r'[+\d\s\-()]'))],
      decoration: _deco('Phone Number',
          hint: '+254 712 345 678', icon: Icons.phone_outlined),
      style: const TextStyle(fontFamily: 'DM Sans', fontSize: 14),
    ),
    const SizedBox(height: 14),
    TextFormField(
      controller: _addrCtrl, enabled: _editing, maxLines: 3,
      decoration: _deco('Address',
          hint: 'P.O. Box 12345-00100, Nairobi', icon: Icons.home_outlined),
      style: const TextStyle(fontFamily: 'DM Sans', fontSize: 14),
    ),
  ]);

  Widget _bioField() => TextFormField(
        controller: _bioCtrl, enabled: _editing, maxLines: 5, maxLength: 500,
        decoration: _deco('Bio', hint: 'A few words about yourself…'),
        style: const TextStyle(fontFamily: 'DM Sans', fontSize: 14),
      );

  Widget _accountInfo() => Column(children: [
    _ReadOnly(label: 'Role',
        value: _cap(RoleService.instance.role),
        icon: Icons.verified_user_outlined),
    const SizedBox(height: 14),
    _ReadOnly(label: 'Member Since',
        value: _fmtDate(_profile?['created_at'] as String?),
        icon: Icons.calendar_today_outlined),
    if (RoleService.instance.role == 'reader') ...[
      const SizedBox(height: 12),
      Container(
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
            color: const Color(0xFFFFFBEB),
            borderRadius: BorderRadius.circular(10),
            border: Border.all(color: const Color(0xFFFED7AA))),
        child: Row(children: [
          const Icon(Icons.auto_stories_rounded,
              color: Color(0xFFD97706), size: 18),
          const SizedBox(width: 10),
          const Expanded(
            child: Text(
              'Want to publish? Contact the admin or submit a manuscript.',
              style: TextStyle(fontFamily: 'DM Sans', fontSize: 12,
                  color: Color(0xFF92400E)),
            ),
          ),
        ]),
      ),
    ],
  ]);

  // ── Save bar ──────────────────────────────────────────────────────────────
  Widget _saveBar() => Positioned(
        bottom: 0, left: 0, right: 0,
        child: Container(
          padding: EdgeInsets.fromLTRB(
              16, 12, 16, 12 + MediaQuery.of(context).padding.bottom),
          decoration: BoxDecoration(
            color: Colors.white,
            border: const Border(top: BorderSide(color: Color(0xFFE5E7EB))),
            boxShadow: [BoxShadow(
                color: Colors.black.withOpacity(0.06),
                blurRadius: 16, offset: const Offset(0, -4))],
          ),
          child: SizedBox(
            width: double.infinity, height: 52,
            child: ElevatedButton(
              onPressed: (_saving || !_hasChange) ? null : _save,
              style: ElevatedButton.styleFrom(
                  backgroundColor: _hasChange
                      ? const Color(0xFFB11226)
                      : const Color(0xFFE5E7EB),
                  foregroundColor: _hasChange ? Colors.white : const Color(0xFF9CA3AF),
                  elevation: _hasChange ? 2 : 0,
                  shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(14))),
              child: _saving
                  ? const SizedBox(width: 22, height: 22,
                      child: CircularProgressIndicator(strokeWidth: 2.5,
                          color: Colors.white))
                  : const Text('Save Changes',
                      style: TextStyle(fontFamily: 'DM Sans',
                          fontSize: 16, fontWeight: FontWeight.w700)),
            ),
          ),
        ),
      );

  // ── Helpers ───────────────────────────────────────────────────────────────
  Widget _card(Widget child) => Container(
        width: double.infinity, padding: const EdgeInsets.all(18),
        decoration: BoxDecoration(
            color: Colors.white, borderRadius: BorderRadius.circular(16),
            boxShadow: [BoxShadow(color: Colors.black.withOpacity(0.04),
                blurRadius: 8, offset: const Offset(0, 2))]),
        child: child);

  InputDecoration _deco(String label, {String? hint, IconData? icon}) =>
      InputDecoration(
        labelText: label, hintText: hint,
        prefixIcon: icon != null ? Icon(icon, size: 20, color: const Color(0xFF9CA3AF)) : null,
        labelStyle: const TextStyle(fontFamily: 'DM Sans', fontSize: 13, color: Color(0xFF6B7280)),
        hintStyle:  const TextStyle(fontFamily: 'DM Sans', fontSize: 13, color: Color(0xFFD1D5DB)),
        filled: true,
        fillColor: _editing ? Colors.white : const Color(0xFFF9FAFB),
        contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
        border:         OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: const BorderSide(color: Color(0xFFE5E7EB))),
        enabledBorder:  OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: const BorderSide(color: Color(0xFFE5E7EB))),
        disabledBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: const BorderSide(color: Color(0xFFF3F4F6))),
        focusedBorder:  OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: const BorderSide(color: Color(0xFFB11226), width: 2)),
      );

  Widget _TypeChip(String label, IconData icon, String value) => Expanded(
        child: GestureDetector(
          onTap: _editing ? () => setState(() { _acctType = value; _onChange(); }) : null,
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 180),
            padding: const EdgeInsets.symmetric(vertical: 8),
            decoration: BoxDecoration(
                color: _acctType == value
                    ? const Color(0xFFB11226).withOpacity(0.08)
                    : const Color(0xFFF9FAFB),
                border: Border.all(
                    color: _acctType == value
                        ? const Color(0xFFB11226)
                        : const Color(0xFFE5E7EB),
                    width: _acctType == value ? 2 : 1),
                borderRadius: BorderRadius.circular(10)),
            child: Column(mainAxisSize: MainAxisSize.min, children: [
              Icon(icon, size: 18,
                  color: _acctType == value
                      ? const Color(0xFFB11226)
                      : const Color(0xFFD1D5DB)),
              const SizedBox(height: 4),
              Text(label, style: TextStyle(
                  fontFamily: 'DM Sans', fontSize: 10,
                  fontWeight: FontWeight.w600,
                  color: _acctType == value
                      ? const Color(0xFFB11226)
                      : const Color(0xFF9CA3AF))),
            ]),
          ),
        ),
      );

  String _cap(String s) => s.isEmpty ? s : s[0].toUpperCase() + s.substring(1);
  String _fmtDate(String? iso) {
    if (iso == null) return '—';
    try {
      final d = DateTime.parse(iso).toLocal();
      const months = ['Jan','Feb','Mar','Apr','May','Jun',
                      'Jul','Aug','Sep','Oct','Nov','Dec'];
      return '${months[d.month - 1]} ${d.year}';
    } catch (_) { return iso; }
  }
}

// ── Sub-widgets ───────────────────────────────────────────────────────────────

class _Section extends StatelessWidget {
  final String text;
  const _Section(this.text);
  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.symmetric(horizontal: 4),
        child: Text(text,
            style: const TextStyle(
                fontFamily: 'PlayfairDisplay',
                fontSize: 13,
                fontWeight: FontWeight.w700,
                color: Color(0xFF6B7280),
                letterSpacing: 0.4)));
}

class _ReadOnly extends StatelessWidget {
  final String label, value;
  final IconData icon;
  const _ReadOnly({required this.label, required this.value, required this.icon});
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
              Text(label, style: const TextStyle(fontFamily: 'DM Sans',
                  fontSize: 11, color: Color(0xFF9CA3AF))),
              const SizedBox(height: 2),
              Text(value, style: const TextStyle(fontFamily: 'DM Sans',
                  fontSize: 14, fontWeight: FontWeight.w600,
                  color: Color(0xFF374151))),
            ]),
          ),
          const Icon(Icons.lock_outline_rounded, size: 14, color: Color(0xFFD1D5DB)),
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
            style: TextStyle(fontFamily: 'DM Sans', fontSize: 10,
                fontWeight: FontWeight.w700, color: _color)));
}