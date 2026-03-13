import 'package:flutter/material.dart';
import 'auth_widgets.dart';

// NOTE: Your backend uses Supabase email links, not OTP codes.
// This page now acts as a "check your email" waiting screen
// that users land on after requesting a password reset.
// The actual password change happens in confirm_passpage.dart
// when the user clicks the email link.

class OtpPage extends StatelessWidget {
  const OtpPage({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFF9F5EF),
      body: Column(
        children: [
          buildDarkHeader(
            title: 'Check Your\nEmail',
            subtitle: 'We sent a secure link to\nyour email address.',
          ),
          Expanded(
            child: SingleChildScrollView(
              padding:
                  const EdgeInsets.symmetric(horizontal: 28, vertical: 40),
              child: Column(
                children: [
                  const SizedBox(height: 16),

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
                    'Email Sent!',
                    style: TextStyle(
                      fontSize: 26,
                      fontWeight: FontWeight.bold,
                      fontFamily: 'PlayfairDisplay',
                      color: Color(0xFF1A1A1A),
                    ),
                  ),

                  const SizedBox(height: 12),

                  const Text(
                    'Click the link in your email to\nreset your password.',
                    textAlign: TextAlign.center,
                    style: TextStyle(
                      color: Color(0xFF666666),
                      fontSize: 14,
                      height: 1.6,
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

                  TextButton(
                    onPressed: () => Navigator.pushNamed(
                        context, '/reset-password'),
                    child: const Text(
                      'Didn\'t receive it? Resend',
                      style: TextStyle(
                          color: Color(0xFFB11226), fontSize: 14),
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