// lib/pages/auth/login_page.dart

import 'package:flutter/material.dart';
import 'package:font_awesome_flutter/font_awesome_flutter.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../services/role_service.dart';
import 'auth_widgets.dart';

class LoginPage extends StatefulWidget {
  const LoginPage({super.key});
  @override
  State<LoginPage> createState() => _LoginPageState();
}

class _LoginPageState extends State<LoginPage> {
  final _emailCtrl    = TextEditingController();
  final _passwordCtrl = TextEditingController();

  bool _keepLoggedIn = false;
  bool _isLoading    = false;
  bool _showPassword = false;

  @override
  void dispose() {
    _emailCtrl.dispose();
    _passwordCtrl.dispose();
    super.dispose();
  }

  Future<void> _handleLogin() async {
    final email    = _emailCtrl.text.trim();
    final password = _passwordCtrl.text.trim();

    if (email.isEmpty || password.isEmpty) {
      _snack('Please fill in all fields');
      return;
    }

    setState(() => _isLoading = true);
    try {
      final res = await Supabase.instance.client.auth
          .signInWithPassword(email: email, password: password);

      if (res.user == null) throw Exception('Sign in failed');

      // Load and cache the role — still needed by the rest of the app
      // (SettingsPage, dashboards, etc.) but no longer used for routing.
      await RoleService.instance.load();

      // Check if profile setup is complete
      final profile = await Supabase.instance.client
          .from('profiles')
          .select('full_name, onboarded')
          .eq('id', res.user!.id)
          .maybeSingle();

      if (!mounted) return;

      final isOnboarded = profile?['onboarded'] == true ||
          (profile?['full_name'] != null &&
              (profile!['full_name'] as String).isNotEmpty);

      if (!isOnboarded) {
        // First-time user — complete their profile first
        Navigator.pushReplacementNamed(context, '/profile-setup');
      } else {
        // ✅ FIX: Always go to /home (Shell with correct navbar).
        //    Previously this called _dashboardRoute(role) which pushed
        //    /dashboard/author, /dashboard/admin, or /dashboard/reader —
        //    pages that each have their own Scaffold + wrong navbar.
        //    Now every user lands on the same root page with the
        //    consistent Home / Books / Cart / Profile bottom nav.
        //    Dashboards are reachable from Settings → "My Dashboard".
        Navigator.pushReplacementNamed(context, '/home');
      }
    } on AuthException catch (e) {
      _snack(e.message);
    } catch (e) {
      _snack('Something went wrong. Please try again.');
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  void _snack(String msg) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(
      content: Text(msg, style: const TextStyle(fontFamily: 'DM Sans')),
      backgroundColor: const Color(0xFF2D2D2D),
      behavior: SnackBarBehavior.floating,
      shape:
          RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
    ));
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFF9F5EF),
      body: Column(children: [
        buildDarkHeader(
          title: 'Welcome to\nInterCEN Books',
          subtitle:
              'Sign in to access your orders, wishlist,\nand exclusive member benefits.',
        ),
        Expanded(
          child: SingleChildScrollView(
            padding:
                const EdgeInsets.symmetric(horizontal: 28, vertical: 32),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text('Welcome back',
                    style: TextStyle(
                        fontSize: 28,
                        fontWeight: FontWeight.bold,
                        fontFamily: 'PlayfairDisplay',
                        color: Color(0xFF1A1A1A))),
                const SizedBox(height: 6),
                const Text('Sign in to your InterCEN Books account',
                    style: TextStyle(
                        color: Color(0xFF888888), fontSize: 14)),
                const SizedBox(height: 32),

                buildLabel('Email'),
                const SizedBox(height: 8),
                buildTextField(
                  controller: _emailCtrl,
                  hint: 'you@example.com',
                  icon: Icons.email_outlined,
                  keyboardType: TextInputType.emailAddress,
                ),
                const SizedBox(height: 20),

                buildLabel('Password'),
                const SizedBox(height: 8),
                buildPasswordField(
                  controller: _passwordCtrl,
                  hint: 'Enter password',
                  show: _showPassword,
                  onToggle: () =>
                      setState(() => _showPassword = !_showPassword),
                ),
                const SizedBox(height: 12),

                Row(children: [
                  Transform.scale(
                    scale: 0.9,
                    child: Checkbox(
                      value: _keepLoggedIn,
                      activeColor: const Color(0xFFB11226),
                      shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(4)),
                      onChanged: (v) =>
                          setState(() => _keepLoggedIn = v!),
                    ),
                  ),
                  const Text('Keep me logged in',
                      style: TextStyle(
                          fontSize: 13, color: Color(0xFF555555))),
                  const Spacer(),
                  TextButton(
                    style: TextButton.styleFrom(
                        foregroundColor: const Color(0xFFB11226),
                        padding: EdgeInsets.zero,
                        minimumSize: Size.zero,
                        tapTargetSize: MaterialTapTargetSize.shrinkWrap),
                    onPressed: () =>
                        Navigator.pushNamed(context, '/reset-password'),
                    child: const Text('Forgot password?',
                        style: TextStyle(fontSize: 13)),
                  ),
                ]),
                const SizedBox(height: 24),

                buildPrimaryButton(
                  label: 'Sign In',
                  isLoading: _isLoading,
                  onPressed: _handleLogin,
                ),
                const SizedBox(height: 28),

                buildDivider('Or continue with'),
                const SizedBox(height: 20),

                Row(children: [
                  Expanded(
                    child: buildSocialButton(
                      icon: FontAwesomeIcons.google,
                      label: 'Google',
                      onPressed: () =>
                          _snack('Google Sign-In coming soon!'),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: buildSocialButton(
                      icon: FontAwesomeIcons.apple,
                      label: 'Apple',
                      onPressed: () =>
                          _snack('Apple Sign-In coming soon!'),
                    ),
                  ),
                ]),
                const SizedBox(height: 32),

                Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                  const Text("Don't have an account? ",
                      style: TextStyle(
                          color: Color(0xFF666666), fontSize: 14)),
                  GestureDetector(
                    onTap: () =>
                        Navigator.pushNamed(context, '/signup'),
                    child: const Text('Sign up',
                        style: TextStyle(
                            fontWeight: FontWeight.bold,
                            color: Color(0xFFB11226),
                            fontSize: 14)),
                  ),
                ]),
                const SizedBox(height: 16),
              ],
            ),
          ),
        ),
      ]),
    );
  }
}