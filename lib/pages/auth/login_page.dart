import 'package:flutter/material.dart';
import 'package:font_awesome_flutter/font_awesome_flutter.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'auth_widgets.dart';

class LoginPage extends StatefulWidget {
  const LoginPage({super.key});

  @override
  State<LoginPage> createState() => _LoginPageState();
}

class _LoginPageState extends State<LoginPage> {
  final emailController = TextEditingController();
  final passwordController = TextEditingController();

  bool keepLoggedIn = false;
  bool isLoading = false;
  bool showPassword = false;

  @override
  void dispose() {
    emailController.dispose();
    passwordController.dispose();
    super.dispose();
  }

  Future<void> handleLogin() async {
    final email = emailController.text.trim();
    final password = passwordController.text.trim();

    if (email.isEmpty || password.isEmpty) {
      _showSnack('Please fill in all fields');
      return;
    }

    setState(() => isLoading = true);

    try {
      final response = await Supabase.instance.client.auth.signInWithPassword(
        email: email,
        password: password,
      );

      if (response.user != null && mounted) {
        Navigator.pushNamedAndRemoveUntil(
          context,
          '/home',
          (route) => false,
        );
      }
    } on AuthException catch (e) {
      _showSnack(e.message);
    } catch (_) {
      _showSnack('Something went wrong. Please try again.');
    } finally {
      if (mounted) setState(() => isLoading = false);
    }
  }

  void _showSnack(String msg) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(msg),
        backgroundColor: const Color(0xFF2D2D2D),
        behavior: SnackBarBehavior.floating,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFF9F5EF),
      body: Column(
        children: [
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
                  const Text(
                    'Welcome back',
                    style: TextStyle(
                      fontSize: 28,
                      fontWeight: FontWeight.bold,
                      fontFamily: 'PlayfairDisplay',
                      color: Color(0xFF1A1A1A),
                    ),
                  ),
                  const SizedBox(height: 6),
                  const Text(
                    'Sign in to your InterCEN Books account',
                    style: TextStyle(color: Color(0xFF888888), fontSize: 14),
                  ),
                  const SizedBox(height: 32),

                  buildLabel('Email'),
                  const SizedBox(height: 8),
                  buildTextField(
                    controller: emailController,
                    hint: 'you@example.com',
                    icon: Icons.email_outlined,
                    keyboardType: TextInputType.emailAddress,
                  ),
                  const SizedBox(height: 20),

                  buildLabel('Password'),
                  const SizedBox(height: 8),
                  buildPasswordField(
                    controller: passwordController,
                    hint: 'Enter password',
                    show: showPassword,
                    onToggle: () =>
                        setState(() => showPassword = !showPassword),
                  ),
                  const SizedBox(height: 12),

                  Row(
                    children: [
                      Transform.scale(
                        scale: 0.9,
                        child: Checkbox(
                          value: keepLoggedIn,
                          activeColor: const Color(0xFFB11226),
                          shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(4)),
                          onChanged: (v) =>
                              setState(() => keepLoggedIn = v!),
                        ),
                      ),
                      const Text(
                        'Keep me logged in',
                        style: TextStyle(
                            fontSize: 13, color: Color(0xFF555555)),
                      ),
                      const Spacer(),
                      TextButton(
                        style: TextButton.styleFrom(
                          foregroundColor: const Color(0xFFB11226),
                          padding: EdgeInsets.zero,
                          minimumSize: Size.zero,
                          tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                        ),
                        onPressed: () => Navigator.pushNamed(
                            context, '/reset-password'),
                        child: const Text('Forgot password?',
                            style: TextStyle(fontSize: 13)),
                      ),
                    ],
                  ),
                  const SizedBox(height: 24),

                  buildPrimaryButton(
                    label: 'Sign In',
                    isLoading: isLoading,
                    onPressed: handleLogin,
                  ),
                  const SizedBox(height: 28),

                  buildDivider('Or continue with'),
                  const SizedBox(height: 20),

                  Row(
                    children: [
                      Expanded(
                        child: buildSocialButton(
                          icon: FontAwesomeIcons.google,
                          label: 'Google',
                          onPressed: () =>
                              _showSnack('Google Sign-In coming soon!'),
                        ),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: buildSocialButton(
                          icon: FontAwesomeIcons.apple,
                          label: 'Apple',
                          onPressed: () =>
                              _showSnack('Apple Sign-In coming soon!'),
                        ),
                      ),
                    ],
                  ),
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
                        child: const Text(
                          'Sign up',
                          style: TextStyle(
                            fontWeight: FontWeight.bold,
                            color: Color(0xFFB11226),
                            fontSize: 14,
                          ),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 16),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}