import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'auth_widgets.dart';

class ResetPasswordPage extends StatefulWidget {
  const ResetPasswordPage({super.key});

  @override
  State<ResetPasswordPage> createState() => _ResetPasswordPageState();
}

class _ResetPasswordPageState extends State<ResetPasswordPage> {
  final emailController = TextEditingController();
  bool isLoading = false;
  bool emailSent = false; // controls which view to show

  @override
  void dispose() {
    emailController.dispose();
    super.dispose();
  }

  Future<void> handleResetPassword() async {
    final email = emailController.text.trim();

    if (email.isEmpty) {
      _showSnack('Please enter your email');
      return;
    }

    setState(() => isLoading = true);

    try {
      // Calls your auth-reset-password Edge Function
      await Supabase.instance.client.functions.invoke(
        'auth-reset-password',
        body: {'email': email},
      );

      // Always show success (your Edge Function does this too,
      // to prevent revealing whether an email exists)
      if (mounted) setState(() => emailSent = true);
    } catch (_) {
      // Even on error, show success for security
      if (mounted) setState(() => emailSent = true);
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
          // Dark header
          buildDarkHeader(
            title: 'Reset Your\nPassword',
            subtitle:
                'Enter your email and we\'ll send\nyou a password reset link.',
          ),

          Expanded(
            child: SingleChildScrollView(
              padding:
                  const EdgeInsets.symmetric(horizontal: 28, vertical: 32),
              child: emailSent ? _buildSuccessView() : _buildFormView(),
            ),
          ),
        ],
      ),
    );
  }

  // ── Form view (before sending email) ──
  Widget _buildFormView() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // Back button
        GestureDetector(
          onTap: () => Navigator.pop(context),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: const [
              Icon(Icons.arrow_back, size: 18, color: Color(0xFF888888)),
              SizedBox(width: 6),
              Text(
                'Back to Sign In',
                style: TextStyle(color: Color(0xFF888888), fontSize: 14),
              ),
            ],
          ),
        ),

        const SizedBox(height: 28),

        const Text(
          'Reset Password',
          style: TextStyle(
            fontSize: 28,
            fontWeight: FontWeight.bold,
            fontFamily: 'PlayfairDisplay',
            color: Color(0xFF1A1A1A),
          ),
        ),
        const SizedBox(height: 6),
        const Text(
          'Enter your email to receive a reset link',
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

        const SizedBox(height: 28),

        buildPrimaryButton(
          label: 'Send Reset Link',
          isLoading: isLoading,
          onPressed: handleResetPassword,
        ),
      ],
    );
  }

  // ── Success view (after sending email) ──
  Widget _buildSuccessView() {
    return Column(
      children: [
        const SizedBox(height: 32),

        // Green checkmark circle
        Container(
          width: 80,
          height: 80,
          decoration: BoxDecoration(
            color: const Color(0xFFEAF7EE),
            borderRadius: BorderRadius.circular(40),
          ),
          child: const Icon(
            Icons.mark_email_read_outlined,
            color: Color(0xFF2E7D32),
            size: 40,
          ),
        ),

        const SizedBox(height: 24),

        const Text(
          'Check Your Email',
          style: TextStyle(
            fontSize: 24,
            fontWeight: FontWeight.bold,
            fontFamily: 'PlayfairDisplay',
            color: Color(0xFF1A1A1A),
          ),
        ),

        const SizedBox(height: 12),

        const Text(
          'If an account exists for that email,\nwe\'ve sent a password reset link.\nCheck your inbox and spam folder.',
          textAlign: TextAlign.center,
          style: TextStyle(
            color: Color(0xFF666666),
            fontSize: 14,
            height: 1.6,
          ),
        ),

        const SizedBox(height: 16),

        // Info box
        Container(
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            color: const Color(0xFFFFF8E1),
            borderRadius: BorderRadius.circular(12),
            border: Border.all(color: const Color(0xFFFFE082)),
          ),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: const [
              Icon(Icons.info_outline, color: Color(0xFFF59E0B), size: 18),
              SizedBox(width: 10),
              Expanded(
                child: Text(
                  'The reset link expires in 1 hour. Click it and you\'ll be taken to set a new password.',
                  style: TextStyle(
                    color: Color(0xFF92400E),
                    fontSize: 13,
                    height: 1.5,
                  ),
                ),
              ),
            ],
          ),
        ),

        const SizedBox(height: 32),

        buildPrimaryButton(
          label: 'Back to Sign In',
          isLoading: false,
          onPressed: () => Navigator.pushNamedAndRemoveUntil(
            context,
            '/login',
            (route) => false,
          ),
        ),

        const SizedBox(height: 16),

        // Resend option
        TextButton(
          onPressed: () => setState(() => emailSent = false),
          child: const Text(
            'Didn\'t receive it? Try again',
            style: TextStyle(color: Color(0xFFB11226), fontSize: 14),
          ),
        ),
      ],
    );
  }
}