import 'package:flutter/material.dart';

// Main pages
import 'pages/homepage.dart';
import 'pages/books.dart';
import 'pages/book_detail_page.dart';
import 'pages/splashscreen.dart';


// Auth pages
import 'pages/auth/login_page.dart';
import 'pages/auth/signup_page.dart';
import 'pages/auth/reset_passwordpage.dart';
import 'pages/auth/otp_page.dart';
import 'pages/auth/confirm_passpage.dart';

void main() {
  runApp(const IntercenApp());
}

class IntercenApp extends StatelessWidget {
  const IntercenApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      debugShowCheckedModeBanner: false,
      title: 'Intercen Book Store',
      theme: ThemeData(
        useMaterial3: true,
        fontFamily: 'PlayfairDisplay',
        scaffoldBackgroundColor: const Color(0xFFF9F5EF),
        colorScheme: ColorScheme.fromSeed(
          seedColor: const Color(0xFFB11226),
        ),
        elevatedButtonTheme: ElevatedButtonThemeData(
          style: ElevatedButton.styleFrom(
            backgroundColor: const Color(0xFFB11226),
            foregroundColor: Colors.white,
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
            textStyle: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
          ),
        ),
        textTheme: ThemeData.light().textTheme.apply(
              bodyColor: Colors.black,
              displayColor: Colors.black,
            ),
      ),
      initialRoute: "/onboarding",
      routes: {
        "/onboarding": (_) => const OnboardingPage(),
        "/login": (_) => const LoginPage(),
        "/signup": (_) => const SignUpPage(),
        "/reset-password": (_) => const ResetPasswordPage(),
        "/otp": (_) => const OtpPage(),
        "/confirm-password": (_) => const ConfirmPasswordPage(),
        "/home": (_) => const Shell(),
        "/books": (_) => const BooksPage(),
        "/book-detail": (_) => const BookDetailPage(),
        "/cart": (_) => const Placeholder(),
        // "/publish": (_) => const PublishPage(),
        // "/community": (_) => const CommunityPage(),
        // "/profile": (_) => const ProfilePage(),
      },
    );
  }
}

// =========================
// MAIN APP SHELL
// =========================

class Shell extends StatefulWidget {
  const Shell({super.key});

  @override
  State<Shell> createState() => _ShellState();
}

class _ShellState extends State<Shell> {
  int index = 0;

  final pages = const [
    HomePage(),
    BooksPage(),
    Placeholder(), // Cart (coming next)
  ];

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: SafeArea(child: pages[index]),
      // bottomNavigationBar removed to avoid duplicates
    );
  }
}
