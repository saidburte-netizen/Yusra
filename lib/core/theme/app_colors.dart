import 'package:flutter/material.dart';

/// Yusra brand tokens. Single source of truth for colour across the app.
abstract final class AppColors {
  // Structural plum/burgundy palette.
  static const Color plum900 = Color(0xFF2D0A1E); // darkest
  static const Color plum800 = Color(0xFF4A1230); // primary dark
  static const Color plum600 = Color(0xFF7A1E4D); // mid

  // Accent pink.
  static const Color pink600 = Color(0xFFD63384);
  static const Color pink700 = Color(0xFFB82B6F);
  static const Color pink300 = Color(0xFFF0A6C8);
  static const Color pink50 = Color(0xFFFCE8F1);

  // Gold highlights.
  static const Color gold500 = Color(0xFFC9A227);
  static const Color gold300 = Color(0xFFE8D48B);
  static const Color gold700 = Color(0xFF9A7B1A);
  static const Color gold100 = Color(0xFFF7F0D4);

  // Surfaces and text.
  static const Color white = Color(0xFFFFFFFF);
  static const Color blush = Color(0xFFFFF7FA);
  static const Color blushDeep = Color(0xFFF8EAF0);
  static const Color surface = Color(0xFFFFFCFD);
  static const Color ink = Color(0xFF2D0A1E); // dark plum text
  static const Color muted = Color(0xFF6E4A5A);
  static const Color onDark = Color(0xFFFFFFFF);
  static const Color onDarkMuted = Color(0xFFF2D7E3);

  static const Color success = Color(0xFF1F8A5B);
  static const Color warning = Color(0xFFD97706);
  static const Color danger = Color(0xFFDC2626);

  static const double radius = 14;

  static const LinearGradient pageGradient = LinearGradient(
    begin: Alignment.topCenter,
    end: Alignment.bottomCenter,
    colors: [Color(0xFFFFF7FA), Color(0xFFF6E7EE), Color(0xFFFFFBFC)],
    stops: [0.0, 0.55, 1.0],
  );

  // Dark theme tokens
  static const Color darkBase = Color(0xFF1A0712);
  static const Color darkSurface = Color(0xFF2D0A1E);
  static const Color darkElevated = Color(0xFF4A1230);
  static const Color darkCard = Color(0xFF351026);
  static const Color darkPink = Color(0xFFE85BA3);
  static const Color darkGold = Color(0xFFD9B13B);
  static const Color darkText = Color(0xFFF7EDF2);
  static const Color darkMuted = Color(0xFFD8B9C7);
  static const Color darkBorder = Color(0xFF6A2A48);

  static const LinearGradient darkPageGradient = LinearGradient(
    begin: Alignment.topCenter,
    end: Alignment.bottomCenter,
    colors: [Color(0xFF1A0712), Color(0xFF240918), Color(0xFF1A0712)],
    stops: [0.0, 0.55, 1.0],
  );

  static const LinearGradient primaryGradient = LinearGradient(
    begin: Alignment.topLeft,
    end: Alignment.bottomRight,
    colors: [pink600, plum600],
  );

  static const LinearGradient darkGradient = LinearGradient(
    begin: Alignment.topLeft,
    end: Alignment.bottomRight,
    colors: [plum800, plum900],
  );

  static const BoxShadow cardShadow = BoxShadow(
    color: Color(0x1A4A1230),
    blurRadius: 20,
    offset: Offset(0, 8),
  );

  static const BoxShadow softPinkShadow = BoxShadow(
    color: Color(0x26D63384),
    blurRadius: 18,
    offset: Offset(0, 6),
  );

  static const BoxShadow goldShadow = BoxShadow(
    color: Color(0x26C9A227),
    blurRadius: 14,
    offset: Offset(0, 4),
  );

  static ColorScheme get colorScheme => const ColorScheme.light(
        primary: pink600,
        onPrimary: white,
        primaryContainer: pink50,
        onPrimaryContainer: plum900,
        secondary: gold500,
        onSecondary: plum900,
        secondaryContainer: gold100,
        onSecondaryContainer: plum900,
        tertiary: plum600,
        onTertiary: white,
        surface: surface,
        onSurface: ink,
        surfaceContainerHighest: blushDeep,
        // ignore: deprecated_member_use
        background: blush,
        // ignore: deprecated_member_use
        onBackground: ink,
        error: danger,
        onError: white,
        outline: gold300,
        outlineVariant: Color(0xFFE7CED8),
      );
}
