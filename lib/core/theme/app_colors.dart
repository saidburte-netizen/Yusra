import 'package:flutter/material.dart';

/// Yusra brand tokens. Single source of truth for colour across the app.
abstract final class AppColors {
  static const Color white = Color(0xFFFFFFFF);
  static const Color blush = Color(0xFFFFF5F8);
  static const Color pink50 = Color(0xFFFFE4EC);
  static const Color pink300 = Color(0xFFF5A3C4);
  static const Color pink600 = Color(0xFFD63384); // primary
  static const Color pink700 = Color(0xFFB82B6F); // hover / pressed
  static const Color gold300 = Color(0xFFF6E7B4);
  static const Color gold500 = Color(0xFFD4AF37); // accent
  static const Color gold700 = Color(0xFFA8841F);
  static const Color ink = Color(0xFF3B1F2B); // text
  static const Color muted = Color(0xFF7A6670);
  static const Color success = Color(0xFF2E9E6B);
  static const Color warning = Color(0xFFE8A317);
  static const Color danger = Color(0xFFD64545);

  static const double radius = 12;

  static const BoxShadow softPinkShadow = BoxShadow(
    color: Color(0x1AD63384),
    blurRadius: 18,
    offset: Offset(0, 6),
  );

  static const BoxShadow goldShadow = BoxShadow(
    color: Color(0x1AD4AF37),
    blurRadius: 12,
    offset: Offset(0, 4),
  );

  static ColorScheme get colorScheme => const ColorScheme.light(
        primary: pink600,
        onPrimary: white,
        primaryContainer: pink50,
        onPrimaryContainer: ink,
        secondary: gold500,
        onSecondary: ink,
        secondaryContainer: gold300,
        onSecondaryContainer: ink,
        surface: white,
        onSurface: ink,
        surfaceContainerHighest: blush,
        // ignore: deprecated_member_use
        background: blush,
        // ignore: deprecated_member_use
        onBackground: ink,
        error: danger,
        onError: white,
        outline: gold500,
        outlineVariant: gold300,
      );
}
