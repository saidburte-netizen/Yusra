import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

import 'app_colors.dart';

/// Material 3 light theme built from the Yusra brand tokens.
abstract final class AppTheme {
  static ThemeData get light {
    final colorScheme = AppColors.colorScheme;

    final heading = GoogleFonts.playfairDisplay(
      color: AppColors.ink,
      fontWeight: FontWeight.w600,
    );
    final body = GoogleFonts.inter(color: AppColors.ink, fontSize: 14);

    return ThemeData(
      useMaterial3: true,
      colorScheme: colorScheme,
      scaffoldBackgroundColor: AppColors.blush,
      fontFamily: body.fontFamily,
      textTheme: TextTheme(
        displayLarge: heading.copyWith(fontSize: 34),
        displayMedium: heading.copyWith(fontSize: 28),
        displaySmall: heading.copyWith(fontSize: 24),
        headlineLarge: heading.copyWith(fontSize: 26),
        headlineMedium: heading.copyWith(fontSize: 22),
        headlineSmall: heading.copyWith(fontSize: 19),
        titleLarge: heading.copyWith(fontSize: 20, fontWeight: FontWeight.w700),
        titleMedium: GoogleFonts.inter(
            color: AppColors.ink, fontSize: 16, fontWeight: FontWeight.w600),
        titleSmall: GoogleFonts.inter(
            color: AppColors.ink, fontSize: 14, fontWeight: FontWeight.w600),
        bodyLarge: body.copyWith(fontSize: 16),
        bodyMedium: body,
        bodySmall: GoogleFonts.inter(color: AppColors.muted, fontSize: 12),
        labelLarge: GoogleFonts.inter(
            color: AppColors.ink, fontSize: 14, fontWeight: FontWeight.w600),
        labelSmall: GoogleFonts.inter(color: AppColors.muted, fontSize: 11),
      ),
      appBarTheme: AppBarTheme(
        backgroundColor: AppColors.white,
        foregroundColor: AppColors.ink,
        surfaceTintColor: AppColors.white,
        elevation: 0,
        centerTitle: false,
        titleTextStyle: heading.copyWith(fontSize: 20),
      ),
      cardTheme: CardTheme(
        color: AppColors.white,
        elevation: 0,
        margin: EdgeInsets.zero,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(AppColors.radius),
          side: const BorderSide(color: AppColors.gold300, width: 0.8),
        ),
      ),
      elevatedButtonTheme: ElevatedButtonThemeData(
        style: ElevatedButton.styleFrom(
          backgroundColor: AppColors.pink600,
          foregroundColor: AppColors.white,
          minimumSize: const Size.fromHeight(48),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(AppColors.radius),
          ),
          textStyle: GoogleFonts.inter(
              fontSize: 14, fontWeight: FontWeight.w600),
        ),
      ),
      outlinedButtonTheme: OutlinedButtonThemeData(
        style: OutlinedButton.styleFrom(
          foregroundColor: AppColors.pink600,
          minimumSize: const Size.fromHeight(48),
          side: const BorderSide(color: AppColors.gold500),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(AppColors.radius),
          ),
        ),
      ),
      inputDecorationTheme: InputDecorationTheme(
        filled: true,
        fillColor: AppColors.white,
        contentPadding:
            const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(AppColors.radius),
          borderSide: const BorderSide(color: AppColors.gold300),
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(AppColors.radius),
          borderSide: const BorderSide(color: AppColors.gold300),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(AppColors.radius),
          borderSide: const BorderSide(color: AppColors.pink600, width: 1.6),
        ),
        errorBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(AppColors.radius),
          borderSide: const BorderSide(color: AppColors.danger),
        ),
      ),
      navigationBarTheme: NavigationBarThemeData(
        backgroundColor: AppColors.white,
        indicatorColor: AppColors.pink50,
        iconTheme: WidgetStateProperty.resolveWith((states) => IconThemeData(
              color: states.contains(WidgetState.selected)
                  ? AppColors.pink600
                  : AppColors.muted,
            )),
        labelTextStyle: WidgetStateProperty.resolveWith((states) =>
            GoogleFonts.inter(
              fontSize: 11,
              color: states.contains(WidgetState.selected)
                  ? AppColors.pink600
                  : AppColors.muted,
              fontWeight: states.contains(WidgetState.selected)
                  ? FontWeight.w700
                  : FontWeight.w500,
            )),
      ),
      navigationRailTheme: NavigationRailThemeData(
        backgroundColor: AppColors.white,
        selectedIconTheme: const IconThemeData(color: AppColors.pink600),
        unselectedIconTheme: const IconThemeData(color: AppColors.muted),
        selectedLabelTextStyle: GoogleFonts.inter(
            color: AppColors.pink600, fontWeight: FontWeight.w700),
      ),
      dividerTheme: const DividerThemeData(
        color: AppColors.gold300,
        space: 1,
        thickness: 1,
      ),
      chipTheme: ChipThemeData(
        backgroundColor: AppColors.pink50,
        selectedColor: AppColors.pink600,
        labelStyle: GoogleFonts.inter(fontSize: 12, color: AppColors.ink),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(20),
          side: const BorderSide(color: AppColors.gold300),
        ),
      ),
      progressIndicatorTheme:
          const ProgressIndicatorThemeData(color: AppColors.pink600),
      pageTransitionsTheme: const PageTransitionsTheme(
        builders: {
          TargetPlatform.android: ZoomPageTransitionsBuilder(),
          TargetPlatform.iOS: CupertinoPageTransitionsBuilder(),
        },
      ),
    );
  }
}
