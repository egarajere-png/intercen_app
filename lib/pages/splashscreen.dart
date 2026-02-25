import 'dart:async';
import 'package:flutter/material.dart';

class OnboardingPage extends StatefulWidget {
  const OnboardingPage({super.key});

  @override
  State<OnboardingPage> createState() => _OnboardingPageState();
}

class _OnboardingPageState extends State<OnboardingPage> {
  final ScrollController _topController = ScrollController();
  final ScrollController _midController = ScrollController();

  late Timer _timer;

  // ✅ Fetch slider images from assets folder
  final List<String> books = [
    "lib/assets/test.png",
    "lib/assets/image.png",
    "lib/assets/mourning.png",
    "lib/assets/whispers.png",
    "lib/assets/hitlers.png",
    "lib/assets/maangavu.png",
    "lib/assets/pandemic.png",

  ];

  @override
  void initState() {
    super.initState();

    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (_midController.hasClients) {
        _midController.jumpTo(_midController.position.maxScrollExtent);
      }
    });

    _timer = Timer.periodic(const Duration(milliseconds: 16), (_) {
      // Top row → moves left
      if (_topController.hasClients) {
        double next = _topController.offset + 1;
        if (next >= _topController.position.maxScrollExtent) {
          next = 0;
        }
        _topController.jumpTo(next);
      }

      // Middle row → moves right
      if (_midController.hasClients) {
        double next = _midController.offset - 1;
        if (next <= 0) {
          next = _midController.position.maxScrollExtent;
        }
        _midController.jumpTo(next);
      }
    });
  }

  @override
  void dispose() {
    _timer.cancel();
    _topController.dispose();
    _midController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFF9F5EF),
      body: Column(
        children: [
          const SizedBox(height: 60),

          _scrollRow(_topController),
          const SizedBox(height: 12),
          _scrollRow(_midController),

          const SizedBox(height: 40),

          SizedBox(
            height: 50,
            child: Image.asset("lib/assets/intercenlogo.png"),
          ),

          const SizedBox(height: 30),

          const Text(
            "Learn more in less time",
            style: TextStyle(
              fontSize: 30,
              fontWeight: FontWeight.bold,
              color: Colors.black,
            ),
            textAlign: TextAlign.center,
          ),

          const SizedBox(height: 12),

          const Padding(
            padding: EdgeInsets.symmetric(horizontal: 40),
            child: Text(
              "Enjoy quick insights, simple takeaways, and smarter reading made easy.",
              textAlign: TextAlign.center,
              style: TextStyle(fontSize: 16, color: Colors.black),
            ),
          ),

          const Spacer(),

          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 24),
            child: SizedBox(
              width: double.infinity,
              height: 56,
              child: ElevatedButton(
                style: ElevatedButton.styleFrom(
                  backgroundColor: const Color(0xFFB11226),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(14),
                  ),
                ),
                onPressed: () {
                  Navigator.pushReplacementNamed(context, "/login");
                },
                child: const Text(
                  "Get Started",
                  style: TextStyle(
                    fontSize: 18,
                    fontWeight: FontWeight.bold,
                    color: Colors.white,
                  ),
                ),
              ),
            ),
          ),

          const SizedBox(height: 16),

          TextButton(
            style: TextButton.styleFrom(
              foregroundColor: Colors.black,
            ),
            onPressed: () {
              Navigator.pushReplacementNamed(context, "/login");
            },
            child: const Text(
              "I already have an account",
              style: TextStyle(fontSize: 14),
            ),
          ),

          const SizedBox(height: 24),
        ],
      ),
    );
  }

  Widget _scrollRow(ScrollController controller) {
    return SizedBox(
      height: 170,
      child: ListView.builder(
        controller: controller,
        scrollDirection: Axis.horizontal,
        physics: const NeverScrollableScrollPhysics(),
        itemCount: books.length * 6, // Increased for smoother infinite loop
        itemBuilder: (_, i) {
          return Container(
            margin: const EdgeInsets.symmetric(horizontal: 6),
            width: 110,
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(12),
              boxShadow: [
                BoxShadow(
                  color: Colors.black.withOpacity(0.08),
                  blurRadius: 8,
                ),
              ],
            ),
            child: ClipRRect(
              borderRadius: BorderRadius.circular(12),
              child: Image.asset(
                books[i % books.length],
                fit: BoxFit.cover,
              ),
            ),
          );
        },
      ),
    );
  }
}
