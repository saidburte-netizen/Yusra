import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

import 'app_colors.dart';

/// Material 3 light theme built from the Yusra premium brand tokens.
abstract final class AppTheme {
  static ThemeData get light {
    final colorScheme = AppColors.colorScheme;
    TextStyle inter(double size, FontWeight weight, Color color,
            {double? height, double? letterSpacing, FontStyle? fontStyle}) =>
        GoogleFonts.inter(
          fontSize: size,
          fontWeight: weight,
          color: color,
          height: height,
          letterSpacing: letterSpacing,
          fontStyle: fontStyle,
        );

    final baseText = TextTheme(
      displayLarge: inter(34, FontWeight.w800, AppColors.ink),
      displayMedium: inter(30, FontWeight.w800, AppColors.ink),
      displaySmall: inter(26, FontWeight.w800, AppColors.ink),
      headlineLarge: inter(28, FontWeight.w800, AppColors.ink),
      headlineMedium: inter(24, FontWeight.w800, AppColors.ink),
      headlineSmall: inter(20, FontWeight.w800, AppColors.ink),
      titleLarge: inter(20, FontWeight.w800, AppColors.ink),
      titleMedium: inter(16, FontWeight.w700, AppColors.ink),
      titleSmall: inter(14, FontWeight.w700, AppColors.ink),
      bodyLarge: inter(16, FontWeight.w600, AppColors.ink, height: 1.45),
      bodyMedium: inter(14, FontWeight.w600, AppColors.ink, height: 1.45),
      bodySmall: inter(12, FontWeight.w600, AppColors.muted, height: 1.4),
      labelLarge: inter(14, FontWeight.w700, AppColors.ink),
      labelMedium: inter(12, FontWeight.w700, AppColors.muted),
      labelSmall: inter(11, FontWeight.w700, AppColors.muted),
    );

    return ThemeData(
      useMaterial3: true,
      colorScheme: colorScheme,
      scaffoldBackgroundColor: Colors.transparent,
      fontFamily: GoogleFonts.inter().fontFamily,
      textTheme: baseText,
      appBarTheme: AppBarTheme(
        backgroundColor: AppColors.plum800,
        foregroundColor: AppColors.onDark,
        surfaceTintColor: Colors.transparent,
        elevation: 0,
        scrolledUnderElevation: 0,
        centerTitle: false,
        iconTheme: const IconThemeData(color: AppColors.gold300),
        actionsIconTheme: const IconThemeData(color: AppColors.gold300),
        titleTextStyle: inter(20, FontWeight.w800, AppColors.onDark),
      ),
      cardTheme: CardTheme(
        color: AppColors.white,
        elevation: 0,
        margin: EdgeInsets.zero,
        shadowColor: AppColors.plum800.withOpacity(0.12),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(AppColors.radius),
          side: BorderSide(color: AppColors.gold300.withOpacity(0.55)),
        ),
      ),
      elevatedButtonTheme: ElevatedButtonThemeData(
        style: ButtonStyle(
          minimumSize: const WidgetStatePropertyAll(Size.fromHeight(48)),
          padding: const WidgetStatePropertyAll(
            EdgeInsets.symmetric(horizontal: 20, vertical: 14),
          ),
          shape: WidgetStatePropertyAll(
            RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(14),
            ),
          ),
          foregroundColor: const WidgetStatePropertyAll(AppColors.onDark),
          textStyle: WidgetStatePropertyAll(
            inter(14, FontWeight.w700, AppColors.onDark),
          ),
          elevation: WidgetStateProperty.resolveWith(
            (states) => states.contains(WidgetState.pressed) ? 1 : 4,
          ),
          shadowColor:
              WidgetStatePropertyAll(AppColors.plum800.withOpacity(0.28)),
          backgroundColor: WidgetStateProperty.resolveWith((states) {
            if (states.contains(WidgetState.disabled)) {
              return AppColors.plum600.withOpacity(0.35);
            }
            if (states.contains(WidgetState.pressed)) {
              return AppColors.plum800;
            }
            return AppColors.pink600;
          }),
        ),
      ),
      outlinedButtonTheme: OutlinedButtonThemeData(
        style: ButtonStyle(
          minimumSize: const WidgetStatePropertyAll(Size.fromHeight(48)),
          padding: const WidgetStatePropertyAll(
            EdgeInsets.symmetric(horizontal: 20, vertical: 14),
          ),
          shape: WidgetStatePropertyAll(
            RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
          ),
          foregroundColor: WidgetStateProperty.resolveWith((states) =>
              states.contains(WidgetState.pressed)
                  ? AppColors.gold700
                  : AppColors.plum800),
          side: WidgetStateProperty.resolveWith(
            (states) => BorderSide(
              color: states.contains(WidgetState.pressed)
                  ? AppColors.gold700
                  : AppColors.gold500,
              width: 1.4,
            ),
          ),
          textStyle: WidgetStatePropertyAll(
            inter(14, FontWeight.w700, AppColors.plum800),
          ),
        ),
      ),
      textButtonTheme: TextButtonThemeData(
        style: ButtonStyle(
          foregroundColor: const WidgetStatePropertyAll(AppColors.plum800),
          textStyle: WidgetStatePropertyAll(
            inter(14, FontWeight.w700, AppColors.plum800),
          ),
        ),
      ),
      inputDecorationTheme: InputDecorationTheme(
        filled: true,
        fillColor: AppColors.white,
        contentPadding:
            const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
        labelStyle: inter(13, FontWeight.w700, AppColors.muted),
        hintStyle: inter(13, FontWeight.w600, AppColors.muted),
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(14),
          borderSide: BorderSide(color: AppColors.gold300.withOpacity(0.7)),
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(14),
          borderSide: BorderSide(color: AppColors.gold300.withOpacity(0.7)),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(14),
          borderSide: const BorderSide(color: AppColors.pink600, width: 1.8),
        ),
        errorBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(14),
          borderSide: const BorderSide(color: AppColors.danger),
        ),
        focusedErrorBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(14),
          borderSide: const BorderSide(color: AppColors.danger, width: 1.6),
        ),
      ),
      navigationBarTheme: NavigationBarThemeData(
        backgroundColor: AppColors.plum800,
        indicatorColor: AppColors.gold500.withOpacity(0.22),
        height: 72,
        iconTheme: WidgetStateProperty.resolveWith(
          (states) => IconThemeData(
            color: states.contains(WidgetState.selected)
                ? AppColors.gold300
                : AppColors.onDarkMuted,
          ),
        ),
        labelTextStyle: WidgetStateProperty.resolveWith(
          (states) => inter(
            12,
            FontWeight.w700,
            states.contains(WidgetState.selected)
                ? AppColors.gold300
                : AppColors.onDarkMuted,
          ),
        ),
      ),
      navigationRailTheme: NavigationRailThemeData(
        backgroundColor: AppColors.plum800,
        indicatorColor: AppColors.gold500.withOpacity(0.22),
        selectedIconTheme: const IconThemeData(color: AppColors.gold300),
        unselectedIconTheme: const IconThemeData(color: AppColors.onDarkMuted),
        selectedLabelTextStyle: inter(13, FontWeight.w700, AppColors.gold300),
        unselectedLabelTextStyle:
            inter(13, FontWeight.w600, AppColors.onDarkMuted),
      ),
      drawerTheme: const DrawerThemeData(
        backgroundColor: AppColors.plum900,
        surfaceTintColor: Colors.transparent,
      ),
      dividerTheme: DividerThemeData(
        color: AppColors.gold500.withOpacity(0.35),
        space: 1,
        thickness: 1,
      ),
      chipTheme: ChipThemeData(
        backgroundColor: AppColors.white,
        selectedColor: AppColors.plum800,
        secondarySelectedColor: AppColors.plum800,
        labelStyle: inter(12, FontWeight.w700, AppColors.ink),
        secondaryLabelStyle: inter(12, FontWeight.w700, AppColors.onDark),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(20),
          side: BorderSide(color: AppColors.gold300.withOpacity(0.8)),
        ),
      ),
      listTileTheme: ListTileThemeData(
        iconColor: AppColors.plum800,
        textColor: AppColors.ink,
        titleTextStyle: inter(14, FontWeight.w700, AppColors.ink),
        subtitleTextStyle: inter(12, FontWeight.w600, AppColors.muted),
      ),
      dialogTheme: DialogTheme(
        backgroundColor: AppColors.white,
        surfaceTintColor: Colors.transparent,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(18),
          side: BorderSide(color: AppColors.gold300.withOpacity(0.5)),
        ),
        titleTextStyle: inter(20, FontWeight.w800, AppColors.ink),
      ),
      snackBarTheme: SnackBarThemeData(
        behavior: SnackBarBehavior.floating,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
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

  /// Wraps page content with the soft blush gradient background.
  static Widget pageBackground({required Widget child}) {
    return DecoratedBox(
      decoration: const BoxDecoration(gradient: AppColors.pageGradient),
      child: child,
    );
  }
}
