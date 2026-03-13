import 'package:flutter/material.dart';

/// Centralized color tokens matching the Intercen web design system.
/// Converted from HSL variables in index.css / tailwind.config.ts.
class AppColors {
  AppColors._();

  // ── Primary (Vibrant Red) ── HSL(0, 85%, 50%) ──
  static const Color primary = Color(0xFFEC1313);
  static const Color primaryForeground = Colors.white;
  static const Color primaryLight = Color(0xFFFDE8E8); // HSL(0, 85%, 95%)

  // ── Secondary (Lime Green) ── HSL(75, 70%, 45%) ──
  static const Color secondary = Color(0xFF7AC417);
  static const Color secondaryForeground = Colors.white;

  // ── Accent (Warm Orange/Gold) ── HSL(35, 95%, 55%) ──
  static const Color accent = Color(0xFFF5A623);
  static const Color accentForeground = Color(0xFF141414);

  // ── Additional InterCEN Brand Colors ──
  static const Color intercenYellow = Color(0xFFF9CE1F); // HSL(48, 95%, 55%)
  static const Color intercenBlue = Color(0xFF19A1E6);   // HSL(200, 80%, 50%)
  static const Color intercenBlack = Color(0xFF141414);


  // ── Crimson variants ──
  static const Color crimson = Color(0xFFEC1313);      // HSL(0, 85%, 50%)
  static const Color crimsonDark = Color(0xFFBD0F0F);  // HSL(0, 85%, 40%)

  // ── Gold variants ──
  static const Color gold = Color(0xFFF5A623);         // HSL(35, 95%, 55%)
  static const Color goldLight = Color(0xFFFFF8E1);    // HSL(45, 100%, 94%)
  static const Color goldDark = Color(0xFFC7851A);     // HSL(35, 95%, 40%)

  // ── Neutrals ──
  static const Color background = Colors.white;
  static const Color foreground = Color(0xFF141414);    // HSL(0, 0%, 8%)
  static const Color charcoal = Color(0xFF262626);      // HSL(0, 0%, 15%)
  static const Color muted = Color(0xFFF5F5F5);         // HSL(0, 0%, 96%)
  static const Color mutedForeground = Color(0xFF737373); // HSL(0, 0%, 45%)
  static const Color cream = Color(0xFFFCFCFA);         // HSL(0, 0%, 99%)

  // ── Warm gradient (Hero background) ──
  // gradient-warm: 180deg, hsl(48 100% 99%) → hsl(45 100% 96%)
  static const Color warmGradientStart = Color(0xFFFFFEF5); // HSL(48, 100%, 99%)
  static const Color warmGradientEnd = Color(0xFFFFF8E1);   // HSL(45, 100%, 96%)

  static const LinearGradient warmGradient = LinearGradient(
    begin: Alignment.topCenter,
    end: Alignment.bottomCenter,
    colors: [warmGradientStart, warmGradientEnd],
  );

  // ── Promo banner gradient (secondary → crimson-dark) ──
  static const LinearGradient promoBannerGradient = LinearGradient(
    begin: Alignment.centerLeft,
    end: Alignment.centerRight,
    colors: [secondary, crimsonDark],
  );
}
