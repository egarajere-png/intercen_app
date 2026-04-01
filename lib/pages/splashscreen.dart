// lib/pages/onboarding_page.dart  (or lib/pages/splashscreen.dart — whichever your project uses)
// Place at the same path as your existing OnboardingPage file.

import 'dart:async';
import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../services/role_service.dart';

class OnboardingPage extends StatefulWidget {
  const OnboardingPage({super.key});
  @override
  State<OnboardingPage> createState() => _OnboardingPageState();
}

class _OnboardingPageState extends State<OnboardingPage> {
  final ScrollController _topCtrl = ScrollController();
  final ScrollController _midCtrl = ScrollController();
  late Timer _timer;
  bool _checking = true;

  final List<String> _books = [
    'lib/assets/test.png',
    'lib/assets/image.png',
    'lib/assets/mourning.png',
    'lib/assets/whispers.png',
    'lib/assets/hitlers.png',
    'lib/assets/maangavu.png',
    'lib/assets/pandemic.png',
  ];

  @override
  void initState() {
    super.initState();
    _checkExistingSession();

    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (_midCtrl.hasClients && _midCtrl.position.hasContentDimensions) {
        _midCtrl.jumpTo(_midCtrl.position.maxScrollExtent);
      }
    });

    _timer = Timer.periodic(const Duration(milliseconds: 16), (_) {
      if (_topCtrl.hasClients && _topCtrl.position.hasContentDimensions) {
        double n = _topCtrl.offset + 1;
        if (n >= _topCtrl.position.maxScrollExtent) n = 0;
        _topCtrl.jumpTo(n);
      }
      if (_midCtrl.hasClients && _midCtrl.position.hasContentDimensions) {
        double n = _midCtrl.offset - 1;
        if (n <= 0) n = _midCtrl.position.maxScrollExtent;
        _midCtrl.jumpTo(n);
      }
    });
  }

  @override
  void dispose() {
    _timer.cancel();
    _topCtrl.dispose();
    _midCtrl.dispose();
    super.dispose();
  }

  Future<void> _checkExistingSession() async {
    try {
      final session = Supabase.instance.client.auth.currentSession;
      if (session != null) {
        final role = await RoleService.instance.load();
        if (!mounted) return;
        Navigator.pushReplacementNamed(
            context, RoleService.dashboardForRole(role));
        return;
      }
    } catch (_) {}
    if (mounted) setState(() => _checking = false);
  }

  @override
  Widget build(BuildContext context) {
    if (_checking) {
      return const Scaffold(
        backgroundColor: Color(0xFFF9F5EF),
        body: Center(
          child: CircularProgressIndicator(
              valueColor: AlwaysStoppedAnimation(Color(0xFFB11226))),
        ),
      );
    }

    return Scaffold(
      backgroundColor: const Color(0xFFF9F5EF),
      body: SingleChildScrollView(
        child: Column(children: [
        const SizedBox(height: 60),
        _scrollRow(_topCtrl),
        const SizedBox(height: 12),
        _scrollRow(_midCtrl),
        const SizedBox(height: 40),

        SizedBox(
          height: 50,
          child: Image.asset(
            'lib/assets/intercenlogo.png',
            errorBuilder: (_, __, ___) => const Text(
              'InterCEN Books',
              style: TextStyle(
                  fontFamily: 'PlayfairDisplay',
                  fontSize: 22,
                  fontWeight: FontWeight.w800,
                  color: Color(0xFF111827)),
            ),
          ),
        ),
        const SizedBox(height: 30),

        const Text(
          'Learn more in less time',
          style: TextStyle(
              fontSize: 30,
              fontWeight: FontWeight.bold,
              fontFamily: 'PlayfairDisplay',
              color: Colors.black),
          textAlign: TextAlign.center,
        ),
        const SizedBox(height: 12),

        const Padding(
          padding: EdgeInsets.symmetric(horizontal: 40),
          child: Text(
            'Enjoy quick insights, simple takeaways, and smarter reading made easy.',
            textAlign: TextAlign.center,
            style: TextStyle(fontSize: 16, color: Colors.black),
          ),
        ),
        const SizedBox(height: 24),

        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 24),
          child: SizedBox(
            width: double.infinity,
            height: 56,
            child: ElevatedButton(
              style: ElevatedButton.styleFrom(
                  backgroundColor: const Color(0xFFB11226),
                  shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(14))),
              onPressed: () =>
                  Navigator.pushReplacementNamed(context, '/login'),
              child: const Text(
                'Get Started',
                style: TextStyle(
                    fontSize: 18,
                    fontWeight: FontWeight.bold,
                    color: Colors.white),
              ),
            ),
          ),
        ),
        const SizedBox(height: 16),

        TextButton(
          style: TextButton.styleFrom(foregroundColor: Colors.black),
          onPressed: () =>
              Navigator.pushReplacementNamed(context, '/login'),
          child: const Text(
            'I already have an account',
            style: TextStyle(fontSize: 14),
          ),
        ),
        const SizedBox(height: 24),
      ]),
      ),
    );
  }

  Widget _scrollRow(ScrollController ctrl) => SizedBox(
        height: 170,
        child: ListView.builder(
          controller: ctrl,
          scrollDirection: Axis.horizontal,
          physics: const NeverScrollableScrollPhysics(),
          itemCount: _books.length * 6,
          itemBuilder: (_, i) => Container(
            margin: const EdgeInsets.symmetric(horizontal: 6),
            width: 110,
            decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(12),
                boxShadow: [
                  BoxShadow(
                      color: Colors.black.withOpacity(0.08),
                      blurRadius: 8)
                ]),
            child: ClipRRect(
              borderRadius: BorderRadius.circular(12),
              child: Image.asset(
                _books[i % _books.length],
                fit: BoxFit.cover,
                errorBuilder: (_, __, ___) => Container(
                    color: const Color(0xFFE5E7EB)),
              ),
            ),
          ),
        ),
      );
}