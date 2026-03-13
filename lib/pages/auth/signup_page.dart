import 'package:flutter/material.dart';
import 'package:font_awesome_flutter/font_awesome_flutter.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'auth_widgets.dart';

class SignUpPage extends StatefulWidget {
  const SignUpPage({super.key});

  @override
  State<SignUpPage> createState() => _SignUpPageState();
}

class _SignUpPageState extends State<SignUpPage> {
  final emailController = TextEditingController();
  final passwordController = TextEditingController();
  final confirmPasswordController = TextEditingController();

  bool termsAccepted = false;
  bool isLoading = false;
  bool showPassword = false;
  bool showConfirmPassword = false;

  @override
  void dispose() {
    emailController.dispose();
    passwordController.dispose();
    confirmPasswordController.dispose();
    super.dispose();
  }

  Future<void> handleSignUp() async {
    final email = emailController.text.trim();
    final password = passwordController.text.trim();
    final confirmPassword = confirmPasswordController.text.trim();

    if (email.isEmpty || password.isEmpty || confirmPassword.isEmpty) {
      _showSnack('Please fill in all fields');
      return;
    }
    if (password.length < 8) {
      _showSnack('Password must be at least 8 characters');
      return;
    }
    if (password != confirmPassword) {
      _showSnack('Passwords do not match');
      return;
    }
    if (!termsAccepted) {
      _showSnack('Please accept the Terms and Conditions');
      return;
    }

    setState(() => isLoading = true);

    try {
      final response = await Supabase.instance.client.auth.signUp(
        email: email,
        password: password,
      );

      if (response.user != null && mounted) {
        _showSnack('Account created! Please check your email to verify.');
        Navigator.pushNamedAndRemoveUntil(
            context, '/login', (route) => false);
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
        shape:
            RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
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
            title: 'Join InterCEN Books',
            subtitle:
                'Create an account and start your\nreading journey today.',
          ),
          Expanded(
            child: SingleChildScrollView(
              padding:
                  const EdgeInsets.symmetric(horizontal: 28, vertical: 32),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text(
                    'Create account',
                    style: TextStyle(
                      fontSize: 28,
                      fontWeight: FontWeight.bold,
                      fontFamily: 'PlayfairDisplay',
                      color: Color(0xFF1A1A1A),
                    ),
                  ),
                  const SizedBox(height: 6),
                  const Text(
                    'Sign up to continue',
                    style:
                        TextStyle(color: Color(0xFF888888), fontSize: 14),
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
                    hint: 'Create password',
                    show: showPassword,
                    onToggle: () =>
                        setState(() => showPassword = !showPassword),
                  ),
                  const SizedBox(height: 6),
                  const Text(
                    'Must be at least 8 characters',
                    style:
                        TextStyle(color: Color(0xFFAAAAAA), fontSize: 12),
                  ),
                  const SizedBox(height: 20),

                  buildLabel('Confirm password'),
                  const SizedBox(height: 8),
                  buildPasswordField(
                    controller: confirmPasswordController,
                    hint: 'Re-enter password',
                    show: showConfirmPassword,
                    onToggle: () => setState(
                        () => showConfirmPassword = !showConfirmPassword),
                  ),
                  const SizedBox(height: 16),

                  Row(
                    crossAxisAlignment: CrossAxisAlignment.center,
                    children: [
                      Transform.scale(
                        scale: 0.9,
                        child: Checkbox(
                          value: termsAccepted,
                          activeColor: const Color(0xFFB11226),
                          shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(4)),
                          onChanged: (v) =>
                              setState(() => termsAccepted = v!),
                        ),
                      ),
                      Expanded(
                        child: RichText(
                          text: const TextSpan(
                            style: TextStyle(
                                fontSize: 13, color: Color(0xFF555555)),
                            children: [
                              TextSpan(text: 'I agree to the '),
                              TextSpan(
                                text: 'Terms of Service',
                                style: TextStyle(
                                  color: Color(0xFFB11226),
                                  fontWeight: FontWeight.w600,
                                ),
                              ),
                              TextSpan(text: ' and '),
                              TextSpan(
                                text: 'Privacy Policy',
                                style: TextStyle(
                                  color: Color(0xFFB11226),
                                  fontWeight: FontWeight.w600,
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 24),

                  buildPrimaryButton(
                    label: 'Create Account',
                    isLoading: isLoading,
                    onPressed: handleSignUp,
                  ),
                  const SizedBox(height: 28),

                  buildDivider('or sign up with'),
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
                      const Text('Already have an account? ',
                          style: TextStyle(
                              color: Color(0xFF666666), fontSize: 14)),
                      GestureDetector(
                        onTap: () => Navigator.pop(context),
                        child: const Text(
                          'Login',
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
