import 'dart:io';
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:image_picker/image_picker.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../theme/app_colors.dart';

// ─────────────────────────────────────────────────────────────────────────────
// PROFILE SETUP PAGE
// Shown immediately after sign-up. User cannot skip — they must complete
// at least their full name before continuing. Three visual steps guide them
// through: Identity → Contact → About You.
// ─────────────────────────────────────────────────────────────────────────────

class ProfileSetupPage extends StatefulWidget {
  const ProfileSetupPage({super.key});

  @override
  State<ProfileSetupPage> createState() => _ProfileSetupPageState();
}

class _ProfileSetupPageState extends State<ProfileSetupPage>
    with TickerProviderStateMixin {
  final _sb = Supabase.instance.client;
  final _picker = ImagePicker();

  // ── Step management ──────────────────────────────────────────────────────
  final _pageCtrl = PageController();
  int _step = 0; // 0 = Identity, 1 = Contact, 2 = About You
  static const _totalSteps = 3;

  // ── Form controllers ─────────────────────────────────────────────────────
  final _fullNameCtrl    = TextEditingController();
  final _phoneCtrl       = TextEditingController();
  final _addressCtrl     = TextEditingController();
  final _orgCtrl         = TextEditingController();
  final _departmentCtrl  = TextEditingController();
  final _bioCtrl         = TextEditingController();

  // ── Form keys ────────────────────────────────────────────────────────────
  final _step0Key = GlobalKey<FormState>();
  final _step1Key = GlobalKey<FormState>();

  // ── Selects ──────────────────────────────────────────────────────────────
  String _accountType = 'personal';

  // ── Avatar ───────────────────────────────────────────────────────────────
  File?   _avatarFile;
  String? _avatarBase64;

  // ── State ────────────────────────────────────────────────────────────────
  bool    _saving       = false;
  bool    _showWelcome  = false;
  String? _error;

  // ── Animation ────────────────────────────────────────────────────────────
  late final AnimationController _welcomeCtrl;
  late final Animation<double>   _welcomeScale;
  late final Animation<double>   _welcomeFade;

  @override
  void initState() {
    super.initState();
    _welcomeCtrl = AnimationController(
        vsync: this, duration: const Duration(milliseconds: 700));
    _welcomeScale = CurvedAnimation(
        parent: _welcomeCtrl, curve: Curves.elasticOut);
    _welcomeFade  = CurvedAnimation(
        parent: _welcomeCtrl, curve: Curves.easeOut);
  }

  @override
  void dispose() {
    _pageCtrl.dispose();
    _fullNameCtrl.dispose();
    _phoneCtrl.dispose();
    _addressCtrl.dispose();
    _orgCtrl.dispose();
    _departmentCtrl.dispose();
    _bioCtrl.dispose();
    _welcomeCtrl.dispose();
    super.dispose();
  }

  // ── Avatar picker ─────────────────────────────────────────────────────────
  Future<void> _pickAvatar() async {
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
    });
  }

  // ── Step navigation ───────────────────────────────────────────────────────
  void _nextStep() {
    if (_step == 0 && !(_step0Key.currentState?.validate() ?? false)) return;
    if (_step == 1 && !(_step1Key.currentState?.validate() ?? false)) return;

    if (_step < _totalSteps - 1) {
      setState(() => _step++);
      _pageCtrl.animateToPage(_step,
          duration: const Duration(milliseconds: 350),
          curve: Curves.easeInOut);
    } else {
      _submit();
    }
  }

  void _prevStep() {
    if (_step > 0) {
      setState(() => _step--);
      _pageCtrl.animateToPage(_step,
          duration: const Duration(milliseconds: 350),
          curve: Curves.easeInOut);
    }
  }

  // ── Submit ────────────────────────────────────────────────────────────────
  Future<void> _submit() async {
    setState(() { _saving = true; _error = null; });
    try {
      final session = _sb.auth.currentSession;
      if (session == null) throw Exception('Session expired. Please sign in again.');

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
        'profile-update',
        body: payload,
        headers: {'Authorization': 'Bearer ${session.accessToken}'},
      );
      if (r.status != 200) {
        throw Exception((r.data as Map?)?['error'] ?? 'Failed to save profile');
      }

      setState(() => _showWelcome = true);
      _welcomeCtrl.forward();
    } catch (e) {
      setState(() => _error = e.toString().replaceFirst('Exception: ', ''));
      _showSnack(_error!);
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  void _showSnack(String msg) {
    ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(msg), backgroundColor: AppColors.primary));
  }

  // ── Theme helpers ─────────────────────────────────────────────────────────
  InputDecoration _fieldDecoration(String label, {String? hint, IconData? icon}) =>
      InputDecoration(
        labelText: label,
        hintText: hint,
        prefixIcon: icon != null ? Icon(icon, size: 20, color: const Color(0xFF9CA3AF)) : null,
        labelStyle: const TextStyle(
            fontFamily: 'DM Sans', fontSize: 13, color: Color(0xFF6B7280)),
        hintStyle: const TextStyle(
            fontFamily: 'DM Sans', fontSize: 13, color: Color(0xFFD1D5DB)),
        filled: true,
        fillColor: Colors.white,
        contentPadding:
            const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
        border: OutlineInputBorder(
            borderRadius: BorderRadius.circular(12),
            borderSide: const BorderSide(color: Color(0xFFE5E7EB))),
        enabledBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(12),
            borderSide: const BorderSide(color: Color(0xFFE5E7EB))),
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

  // ── Step 0: Identity ──────────────────────────────────────────────────────
  Widget _buildStep0() => Form(
        key: _step0Key,
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          _StepHeader(
            icon: Icons.person_outline_rounded,
            title: 'Who are you?',
            subtitle: 'Tell us your name and add a photo.',
          ),
          const SizedBox(height: 28),

          // Avatar picker
          Center(
            child: GestureDetector(
              onTap: _pickAvatar,
              child: Stack(children: [
                Container(
                  width: 96, height: 96,
                  decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      color: const Color(0xFFF3F4F6),
                      border: Border.all(
                          color: AppColors.primary.withOpacity(0.3), width: 2),
                      image: _avatarFile != null
                          ? DecorationImage(
                              image: FileImage(_avatarFile!),
                              fit: BoxFit.cover)
                          : null),
                  child: _avatarFile == null
                      ? Icon(Icons.person_rounded,
                          size: 48, color: const Color(0xFFD1D5DB))
                      : null,
                ),
                Positioned(
                  bottom: 0, right: 0,
                  child: Container(
                    width: 30, height: 30,
                    decoration: BoxDecoration(
                        color: AppColors.primary,
                        shape: BoxShape.circle,
                        border: Border.all(color: Colors.white, width: 2)),
                    child: const Icon(Icons.camera_alt_rounded,
                        size: 14, color: Colors.white),
                  ),
                ),
              ]),
            ),
          ),
          const SizedBox(height: 6),
          const Center(
            child: Text('Tap to add a photo',
                style: TextStyle(
                    fontFamily: 'DM Sans',
                    fontSize: 12,
                    color: Color(0xFF9CA3AF))),
          ),
          const SizedBox(height: 24),

          TextFormField(
            controller: _fullNameCtrl,
            decoration: _fieldDecoration('Full Name *',
                hint: 'Mwangi Kamau',
                icon: Icons.badge_outlined),
            textCapitalization: TextCapitalization.words,
            maxLength: 100,
            style: const TextStyle(fontFamily: 'DM Sans', fontSize: 14),
            validator: (v) =>
                (v == null || v.trim().isEmpty) ? 'Full name is required' : null,
          ),
          const SizedBox(height: 16),

          // Account type
          const Text('Account Type',
              style: TextStyle(
                  fontFamily: 'DM Sans',
                  fontSize: 13,
                  fontWeight: FontWeight.w600,
                  color: Color(0xFF374151))),
          const SizedBox(height: 8),
          Row(children: [
            _AccountTypeChip(
              label: 'Personal',
              icon: Icons.person_rounded,
              selected: _accountType == 'personal',
              onTap: () => setState(() => _accountType = 'personal'),
            ),
            const SizedBox(width: 8),
            _AccountTypeChip(
              label: 'Corporate',
              icon: Icons.business_rounded,
              selected: _accountType == 'corporate',
              onTap: () => setState(() => _accountType = 'corporate'),
            ),
            const SizedBox(width: 8),
            _AccountTypeChip(
              label: 'Institution',
              icon: Icons.school_rounded,
              selected: _accountType == 'institutional',
              onTap: () => setState(() => _accountType = 'institutional'),
            ),
          ]),

          if (_accountType != 'personal') ...[
            const SizedBox(height: 20),
            TextFormField(
              controller: _orgCtrl,
              decoration: _fieldDecoration(
                  _accountType == 'corporate'
                      ? 'Company / Organization'
                      : 'Institution / University',
                  hint: _accountType == 'corporate'
                      ? 'Acme Corp Ltd'
                      : 'University of Nairobi',
                  icon: Icons.domain_rounded),
              style: const TextStyle(fontFamily: 'DM Sans', fontSize: 14),
            ),
            const SizedBox(height: 16),
            TextFormField(
              controller: _departmentCtrl,
              decoration: _fieldDecoration('Department / Faculty',
                  hint: 'Engineering / Research',
                  icon: Icons.account_tree_outlined),
              style: const TextStyle(fontFamily: 'DM Sans', fontSize: 14),
            ),
          ],
        ]),
      );

  // ── Step 1: Contact ───────────────────────────────────────────────────────
  Widget _buildStep1() => Form(
        key: _step1Key,
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          _StepHeader(
            icon: Icons.location_on_outlined,
            title: 'How to reach you?',
            subtitle: 'Your contact and delivery details.',
          ),
          const SizedBox(height: 28),

          TextFormField(
            controller: _phoneCtrl,
            decoration: _fieldDecoration('Phone Number',
                hint: '+254 712 345 678',
                icon: Icons.phone_outlined),
            keyboardType: TextInputType.phone,
            maxLength: 20,
            inputFormatters: [FilteringTextInputFormatter.allow(RegExp(r'[+\d\s\-()]'))],
            style: const TextStyle(fontFamily: 'DM Sans', fontSize: 14),
          ),
          const SizedBox(height: 16),

          TextFormField(
            controller: _addressCtrl,
            decoration: _fieldDecoration('Delivery Address',
                hint: 'P.O. Box 12345-00100, Nairobi',
                icon: Icons.home_outlined),
            maxLines: 3,
            style: const TextStyle(fontFamily: 'DM Sans', fontSize: 14),
          ),
          const SizedBox(height: 16),

          Container(
            padding: const EdgeInsets.all(14),
            decoration: BoxDecoration(
                color: const Color(0xFFF0F9FF),
                border: Border.all(color: const Color(0xFFBAE6FD)),
                borderRadius: BorderRadius.circular(12)),
            child: Row(children: [
              const Icon(Icons.info_outline_rounded,
                  color: Color(0xFF0284C7), size: 18),
              const SizedBox(width: 10),
              const Expanded(
                child: Text(
                  'Your address is used for physical book deliveries. You can update it later from your profile.',
                  style: TextStyle(
                      fontFamily: 'DM Sans',
                      fontSize: 12,
                      color: Color(0xFF0369A1),
                      height: 1.5),
                ),
              ),
            ]),
          ),
        ]),
      );

  // ── Step 2: About You ─────────────────────────────────────────────────────
  Widget _buildStep2() => Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _StepHeader(
            icon: Icons.auto_stories_outlined,
            title: 'Your reading story',
            subtitle: 'Optional — helps us personalise your experience.',
          ),
          const SizedBox(height: 28),

          TextFormField(
            controller: _bioCtrl,
            decoration: _fieldDecoration('Bio / About You',
                hint:
                    'Passionate about history, technology and African literature…'),
            maxLines: 5,
            maxLength: 500,
            style: const TextStyle(fontFamily: 'DM Sans', fontSize: 14),
          ),
          const SizedBox(height: 16),

          Container(
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
                color: const Color(0xFFFFF7ED),
                border: Border.all(color: const Color(0xFFFED7AA)),
                borderRadius: BorderRadius.circular(12)),
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              const Text('🎉 Almost done!',
                  style: TextStyle(
                      fontFamily: 'PlayfairDisplay',
                      fontSize: 15,
                      fontWeight: FontWeight.w700,
                      color: Color(0xFF92400E))),
              const SizedBox(height: 6),
              const Text(
                "You're one tap away from exploring thousands of books. Your bio is optional — you can always add it later.",
                style: TextStyle(
                    fontFamily: 'DM Sans',
                    fontSize: 13,
                    color: Color(0xFFB45309),
                    height: 1.55),
              ),
            ]),
          ),
        ],
      );

  // ── Welcome overlay ───────────────────────────────────────────────────────
  Widget _buildWelcomeOverlay() => AnimatedOpacity(
        opacity: _showWelcome ? 1.0 : 0.0,
        duration: const Duration(milliseconds: 300),
        child: Container(
          color: Colors.black54,
          alignment: Alignment.center,
          child: FadeTransition(
            opacity: _welcomeFade,
            child: ScaleTransition(
              scale: _welcomeScale,
              child: Container(
                margin: const EdgeInsets.all(32),
                padding: const EdgeInsets.all(32),
                decoration: BoxDecoration(
                    color: Colors.white,
                    borderRadius: BorderRadius.circular(24),
                    boxShadow: [
                      BoxShadow(
                          color: Colors.black.withOpacity(0.18),
                          blurRadius: 40,
                          offset: const Offset(0, 16))
                    ]),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    TweenAnimationBuilder<double>(
                      tween: Tween(begin: 0, end: 1),
                      duration: const Duration(milliseconds: 800),
                      curve: Curves.elasticOut,
                      builder: (_, v, child) =>
                          Transform.scale(scale: v, child: child),
                      child: Container(
                        width: 80, height: 80,
                        decoration: const BoxDecoration(
                            color: Color(0xFFF0FDF4),
                            shape: BoxShape.circle),
                        child: const Icon(Icons.auto_stories_rounded,
                            size: 44, color: Color(0xFF16A34A)),
                      ),
                    ),
                    const SizedBox(height: 20),
                    Text(
                      'Welcome, ${_fullNameCtrl.text.trim().split(' ').first}!',
                      textAlign: TextAlign.center,
                      style: const TextStyle(
                          fontFamily: 'PlayfairDisplay',
                          fontSize: 24,
                          fontWeight: FontWeight.w800,
                          color: Color(0xFF111827)),
                    ),
                    const SizedBox(height: 12),
                    const Text(
                      'Your profile is all set.\nYou\'re ready to explore Intercen Books.',
                      textAlign: TextAlign.center,
                      style: TextStyle(
                          fontFamily: 'DM Sans',
                          fontSize: 14,
                          color: Color(0xFF6B7280),
                          height: 1.6),
                    ),
                    const SizedBox(height: 28),
                    SizedBox(
                      width: double.infinity,
                      height: 50,
                      child: ElevatedButton(
                        onPressed: () => Navigator.pushNamedAndRemoveUntil(
                            context, '/home', (_) => false),
                        style: ElevatedButton.styleFrom(
                            backgroundColor: AppColors.primary,
                            foregroundColor: Colors.white,
                            shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(14))),
                        child: const Text('Start Exploring',
                            style: TextStyle(
                                fontFamily: 'DM Sans',
                                fontSize: 16,
                                fontWeight: FontWeight.w700)),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      );

  // ── Build ─────────────────────────────────────────────────────────────────
  @override
  Widget build(BuildContext context) {
    return PopScope(
      canPop: _step == 0,
      onPopInvoked: (didPop) {
        if (!didPop && _step > 0) _prevStep();
      },
      child: Scaffold(
        backgroundColor: const Color(0xFFF9F5EF),
        body: Stack(children: [
          SafeArea(
            child: Column(children: [
              // ── Header ───────────────────────────────────────────────────
              Padding(
                padding: const EdgeInsets.fromLTRB(24, 20, 24, 0),
                child: Column(children: [
                  Row(
                    children: [
                      if (_step > 0)
                        GestureDetector(
                          onTap: _prevStep,
                          child: Container(
                            width: 36, height: 36,
                            decoration: BoxDecoration(
                                color: Colors.white,
                                shape: BoxShape.circle,
                                boxShadow: [
                                  BoxShadow(
                                      color: Colors.black.withOpacity(0.06),
                                      blurRadius: 8)
                                ]),
                            child: Icon(Icons.arrow_back_ios_new_rounded,
                                size: 16, color: AppColors.primary),
                          ),
                        )
                      else
                        const SizedBox(width: 36),
                      const Spacer(),
                      Text(
                        'Step ${_step + 1} of $_totalSteps',
                        style: const TextStyle(
                            fontFamily: 'DM Sans',
                            fontSize: 12,
                            color: Color(0xFF9CA3AF)),
                      ),
                    ],
                  ),
                  const SizedBox(height: 16),

                  // Progress bar
                  ClipRRect(
                    borderRadius: BorderRadius.circular(4),
                    child: LinearProgressIndicator(
                      value: (_step + 1) / _totalSteps,
                      minHeight: 4,
                      backgroundColor: const Color(0xFFE5E7EB),
                      valueColor:
                          AlwaysStoppedAnimation(AppColors.primary),
                    ),
                  ),
                  const SizedBox(height: 6),

                  // Step dots
                  Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: List.generate(_totalSteps, (i) => Container(
                      margin: const EdgeInsets.symmetric(horizontal: 3),
                      width: i == _step ? 20 : 6,
                      height: 6,
                      decoration: BoxDecoration(
                          color: i <= _step
                              ? AppColors.primary
                              : const Color(0xFFE5E7EB),
                          borderRadius: BorderRadius.circular(3)),
                    )),
                  ),
                ]),
              ),

              // ── Page content ──────────────────────────────────────────────
              Expanded(
                child: PageView(
                  controller: _pageCtrl,
                  physics: const NeverScrollableScrollPhysics(),
                  children: [
                    _scrolled(_buildStep0()),
                    _scrolled(_buildStep1()),
                    _scrolled(_buildStep2()),
                  ],
                ),
              ),

              // ── Bottom CTA ────────────────────────────────────────────────
              Container(
                color: const Color(0xFFF9F5EF),
                padding: EdgeInsets.fromLTRB(
                    24, 12, 24, 12 + MediaQuery.of(context).padding.bottom),
                child: Column(mainAxisSize: MainAxisSize.min, children: [
                  if (_error != null) ...[
                    Container(
                      padding: const EdgeInsets.all(12),
                      margin: const EdgeInsets.only(bottom: 10),
                      decoration: BoxDecoration(
                          color: const Color(0xFFFEF2F2),
                          border: Border.all(color: const Color(0xFFFECACA)),
                          borderRadius: BorderRadius.circular(10)),
                      child: Row(children: [
                        const Icon(Icons.error_outline,
                            color: Color(0xFFDC2626), size: 16),
                        const SizedBox(width: 8),
                        Expanded(
                            child: Text(_error!,
                                style: const TextStyle(
                                    fontFamily: 'DM Sans',
                                    fontSize: 12,
                                    color: Color(0xFF991B1B)))),
                      ]),
                    ),
                  ],
                  SizedBox(
                    width: double.infinity,
                    height: 52,
                    child: ElevatedButton(
                      onPressed: _saving ? null : _nextStep,
                      style: ElevatedButton.styleFrom(
                          backgroundColor: AppColors.primary,
                          foregroundColor: Colors.white,
                          elevation: 2,
                          shadowColor: AppColors.primary.withOpacity(0.35),
                          shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(14))),
                      child: _saving
                          ? const SizedBox(
                              width: 22, height: 22,
                              child: CircularProgressIndicator(
                                  strokeWidth: 2.5,
                                  valueColor: AlwaysStoppedAnimation(
                                      Colors.white)))
                          : Text(
                              _step == _totalSteps - 1
                                  ? 'Complete Setup'
                                  : 'Continue',
                              style: const TextStyle(
                                  fontFamily: 'DM Sans',
                                  fontSize: 16,
                                  fontWeight: FontWeight.w700)),
                    ),
                  ),
                  if (_step == _totalSteps - 1) ...[
                    const SizedBox(height: 10),
                    TextButton(
                      onPressed: _saving ? null : _submit,
                      child: const Text('Skip bio for now',
                          style: TextStyle(
                              fontFamily: 'DM Sans',
                              fontSize: 13,
                              color: Color(0xFF9CA3AF))),
                    ),
                  ],
                ]),
              ),
            ]),
          ),

          // ── Welcome overlay (above everything) ────────────────────────────
          if (_showWelcome) _buildWelcomeOverlay(),
        ]),
      ),
    );
  }

  Widget _scrolled(Widget child) => SingleChildScrollView(
        padding: const EdgeInsets.fromLTRB(24, 20, 24, 24),
        child: child,
      );
}

// ── Sub-widgets ───────────────────────────────────────────────────────────────

class _StepHeader extends StatelessWidget {
  final IconData icon;
  final String title, subtitle;
  const _StepHeader(
      {required this.icon, required this.title, required this.subtitle});

  @override
  Widget build(BuildContext context) => Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            width: 44, height: 44,
            decoration: BoxDecoration(
                color: AppColors.primary.withOpacity(0.1),
                borderRadius: BorderRadius.circular(12)),
            child: Icon(icon, color: AppColors.primary, size: 22),
          ),
          const SizedBox(height: 14),
          Text(title,
              style: const TextStyle(
                  fontFamily: 'PlayfairDisplay',
                  fontSize: 22,
                  fontWeight: FontWeight.w800,
                  color: Color(0xFF111827))),
          const SizedBox(height: 4),
          Text(subtitle,
              style: const TextStyle(
                  fontFamily: 'DM Sans',
                  fontSize: 13,
                  color: Color(0xFF6B7280),
                  height: 1.5)),
        ],
      );
}

class _AccountTypeChip extends StatelessWidget {
  final String label;
  final IconData icon;
  final bool selected;
  final VoidCallback onTap;
  const _AccountTypeChip(
      {required this.label,
      required this.icon,
      required this.selected,
      required this.onTap});

  @override
  Widget build(BuildContext context) => Expanded(
        child: GestureDetector(
          onTap: onTap,
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 200),
            padding: const EdgeInsets.symmetric(vertical: 10),
            decoration: BoxDecoration(
                color: selected
                    ? AppColors.primary.withOpacity(0.08)
                    : Colors.white,
                border: Border.all(
                    color: selected
                        ? AppColors.primary
                        : const Color(0xFFE5E7EB),
                    width: selected ? 2 : 1),
                borderRadius: BorderRadius.circular(10)),
            child: Column(mainAxisSize: MainAxisSize.min, children: [
              Icon(icon,
                  size: 20,
                  color: selected
                      ? AppColors.primary
                      : const Color(0xFF9CA3AF)),
              const SizedBox(height: 4),
              Text(label,
                  style: TextStyle(
                      fontFamily: 'DM Sans',
                      fontSize: 11,
                      fontWeight: FontWeight.w600,
                      color: selected
                          ? AppColors.primary
                          : const Color(0xFF6B7280))),
            ]),
          ),
        ),
      );
}