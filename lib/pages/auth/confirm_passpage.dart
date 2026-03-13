import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'auth_widgets.dart';

class ConfirmPasswordPage extends StatefulWidget {
  const ConfirmPasswordPage({super.key});

  @override
  State<ConfirmPasswordPage> createState() => _ConfirmPasswordPageState();
}

class _ConfirmPasswordPageState extends State<ConfirmPasswordPage> {
  final passwordController = TextEditingController();
  final confirmPasswordController = TextEditingController();

  bool isLoading = false;
  bool showPassword = false;
  bool showConfirm = false;

  @override
  void dispose() {
    passwordController.dispose();
    confirmPasswordController.dispose();
    super.dispose();
  }

  Future<void> handleChangePassword() async {
    final password = passwordController.text.trim();
    final confirm = confirmPasswordController.text.trim();

    if (password.isEmpty || confirm.isEmpty) {
      _showSnack('Please fill in all fields');
      return;
    }
    if (password.length < 8) {
      _showSnack('Password must be at least 8 characters');
      return;
    }
    if (!RegExp(r'[A-Za-z]').hasMatch(password)) {
      _showSnack('Password must contain at least one letter');
      return;
    }
    if (!RegExp(r'\d').hasMatch(password)) {
      _showSnack('Password must contain at least one number');
      return;
    }
    if (password != confirm) {
      _showSnack('Passwords do not match');
      return;
    }

    setState(() => isLoading = true);

    try {
      // Update the user's password using the active Supabase session
      // (Supabase automatically sets the session from the reset link token)
      final response = await Supabase.instance.client.auth.updateUser(
        UserAttributes(password: password),
      );

      if (response.user != null && mounted) {
        _showSnack('Password changed successfully!');

        // Sign out so user logs in fresh with new password
        await Supabase.instance.client.auth.signOut();

        if (mounted) {
          Navigator.pushNamedAndRemoveUntil(
            context,
            '/login',
            (route) => false,
          );
        }
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
            title: 'Create a\nNew Password',
            subtitle:
                'Choose a strong password to\nkeep your account secure.',
          ),
          Expanded(
            child: SingleChildScrollView(
              padding:
                  const EdgeInsets.symmetric(horizontal: 28, vertical: 32),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text(
                    'Change Password',
                    style: TextStyle(
                      fontSize: 28,
                      fontWeight: FontWeight.bold,
                      fontFamily: 'PlayfairDisplay',
                      color: Color(0xFF1A1A1A),
                    ),
                  ),
                  const SizedBox(height: 6),
                  const Text(
                    'Enter your new password below',
                    style:
                        TextStyle(color: Color(0xFF888888), fontSize: 14),
                  ),

                  const SizedBox(height: 32),

                  buildLabel('New Password'),
                  const SizedBox(height: 8),
                  buildPasswordField(
                    controller: passwordController,
                    hint: '••••••••',
                    show: showPassword,
                    onToggle: () =>
                        setState(() => showPassword = !showPassword),
                  ),
                  const SizedBox(height: 6),
                  const Text(
                    'At least 8 characters with a letter and number',
                    style:
                        TextStyle(color: Color(0xFFAAAAAA), fontSize: 12),
                  ),

                  const SizedBox(height: 20),

                  buildLabel('Confirm New Password'),
                  const SizedBox(height: 8),
                  buildPasswordField(
                    controller: confirmPasswordController,
                    hint: '••••••••',
                    show: showConfirm,
                    onToggle: () =>
                        setState(() => showConfirm = !showConfirm),
                  ),

                  const SizedBox(height: 28),

                  buildPrimaryButton(
                    label: 'Change Password',
                    isLoading: isLoading,
                    onPressed: handleChangePassword,
                  ),

                  const SizedBox(height: 24),

                  // Password requirements box
                  Container(
                    padding: const EdgeInsets.all(16),
                    decoration: BoxDecoration(
                      color: Colors.white,
                      borderRadius: BorderRadius.circular(12),
                      border: Border.all(color: const Color(0xFFE0E0E0)),
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: const [
                        Text(
                          'Password Requirements:',
                          style: TextStyle(
                            fontWeight: FontWeight.w600,
                            fontSize: 13,
                            color: Color(0xFF333333),
                          ),
                        ),
                        SizedBox(height: 10),
                        _RequirementRow(text: 'At least 8 characters long'),
                        _RequirementRow(
                            text: 'Contains at least one letter (A-Z or a-z)'),
                        _RequirementRow(
                            text: 'Contains at least one number (0-9)'),
                        _RequirementRow(
                            text: 'Can include special characters'),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}

// Small helper widget for the requirements list
class _RequirementRow extends StatelessWidget {
  final String text;
  const _RequirementRow({required this.text});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 6),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Icon(Icons.check_circle_outline,
              size: 15, color: Color(0xFFB11226)),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              text,
              style: const TextStyle(
                  fontSize: 12, color: Color(0xFF666666), height: 1.4),
            ),
          ),
        ],
      ),
    );
  }
}