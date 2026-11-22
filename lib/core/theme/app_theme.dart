import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

import 'app_colors.dart';

/// Material 3 themes built from the Yusra premium brand tokens.
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
      brightness: Brightness.light,
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

  static ThemeData get dark {
    const scheme = ColorScheme.dark(
      primary: AppColors.darkPink,
      onPrimary: Color(0xFF1A0712),
      primaryContainer: AppColors.darkElevated,
      onPrimaryContainer: AppColors.darkText,
      secondary: AppColors.darkGold,
      onSecondary: Color(0xFF1A0712),
      secondaryContainer: Color(0xFF4A3510),
      onSecondaryContainer: AppColors.darkText,
      tertiary: AppColors.plum600,
      onTertiary: Colors.white,
      surface: AppColors.darkSurface,
      onSurface: AppColors.darkText,
      surfaceContainerHighest: AppColors.darkCard,
      error: Color(0xFFF87171),
      onError: Color(0xFF1A0712),
      outline: AppColors.darkBorder,
      outlineVariant: Color(0xFF5A2340),
    );

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
      displayLarge: inter(34, FontWeight.w800, AppColors.darkText),
      displayMedium: inter(30, FontWeight.w800, AppColors.darkText),
      displaySmall: inter(26, FontWeight.w800, AppColors.darkText),
      headlineLarge: inter(28, FontWeight.w800, AppColors.darkText),
      headlineMedium: inter(24, FontWeight.w800, AppColors.darkText),
      headlineSmall: inter(20, FontWeight.w800, AppColors.darkText),
      titleLarge: inter(20, FontWeight.w800, AppColors.darkText),
      titleMedium: inter(16, FontWeight.w700, AppColors.darkText),
      titleSmall: inter(14, FontWeight.w700, AppColors.darkText),
      bodyLarge: inter(16, FontWeight.w600, AppColors.darkText, height: 1.45),
      bodyMedium: inter(14, FontWeight.w600, AppColors.darkText, height: 1.45),
      bodySmall: inter(12, FontWeight.w600, AppColors.darkMuted, height: 1.4),
      labelLarge: inter(14, FontWeight.w700, AppColors.darkText),
      labelMedium: inter(12, FontWeight.w700, AppColors.darkMuted),
      labelSmall: inter(11, FontWeight.w700, AppColors.darkMuted),
    );

    return ThemeData(
      useMaterial3: true,
      brightness: Brightness.dark,
      colorScheme: scheme,
      scaffoldBackgroundColor: Colors.transparent,
      fontFamily: GoogleFonts.inter().fontFamily,
      textTheme: baseText,
      appBarTheme: AppBarTheme(
        backgroundColor: AppColors.darkSurface,
        foregroundColor: AppColors.darkText,
        surfaceTintColor: Colors.transparent,
        elevation: 0,
        scrolledUnderElevation: 0,
        centerTitle: false,
        iconTheme: const IconThemeData(color: AppColors.darkGold),
        actionsIconTheme: const IconThemeData(color: AppColors.darkGold),
        titleTextStyle: inter(20, FontWeight.w800, AppColors.darkText),
      ),
      cardTheme: CardTheme(
        color: AppColors.darkCard,
        elevation: 0,
        margin: EdgeInsets.zero,
        shadowColor: Colors.black.withOpacity(0.3),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(AppColors.radius),
          side: const BorderSide(color: AppColors.darkBorder),
        ),
      ),
      elevatedButtonTheme: ElevatedButtonThemeData(
        style: ButtonStyle(
          minimumSize: const WidgetStatePropertyAll(Size.fromHeight(48)),
          padding: const WidgetStatePropertyAll(
            EdgeInsets.symmetric(horizontal: 20, vertical: 14),
          ),
          shape: WidgetStatePropertyAll(
            RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
          ),
          foregroundColor: const WidgetStatePropertyAll(Color(0xFF1A0712)),
          textStyle: WidgetStatePropertyAll(
            inter(14, FontWeight.w700, const Color(0xFF1A0712)),
          ),
          backgroundColor: WidgetStateProperty.resolveWith((states) {
            if (states.contains(WidgetState.disabled)) {
              return AppColors.darkElevated.withOpacity(0.5);
            }
            if (states.contains(WidgetState.pressed)) {
              return AppColors.darkGold;
            }
            return AppColors.darkPink;
          }),
        ),
      ),
      outlinedButtonTheme: OutlinedButtonThemeData(
        style: ButtonStyle(
          minimumSize: const WidgetStatePropertyAll(Size.fromHeight(48)),
          shape: WidgetStatePropertyAll(
            RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
          ),
          foregroundColor: const WidgetStatePropertyAll(AppColors.darkGold),
          side: const WidgetStatePropertyAll(
            BorderSide(color: AppColors.darkGold, width: 1.4),
          ),
          textStyle: WidgetStatePropertyAll(
            inter(14, FontWeight.w700, AppColors.darkGold),
          ),
        ),
      ),
      textButtonTheme: TextButtonThemeData(
        style: ButtonStyle(
          foregroundColor: const WidgetStatePropertyAll(AppColors.darkPink),
          textStyle: WidgetStatePropertyAll(
            inter(14, FontWeight.w700, AppColors.darkPink),
          ),
        ),
      ),
      inputDecorationTheme: InputDecorationTheme(
        filled: true,
        fillColor: AppColors.darkSurface,
        contentPadding:
            const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
        labelStyle: inter(13, FontWeight.w700, AppColors.darkMuted),
        hintStyle: inter(13, FontWeight.w600, AppColors.darkMuted),
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(14),
          borderSide: const BorderSide(color: AppColors.darkBorder),
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(14),
          borderSide: const BorderSide(color: AppColors.darkBorder),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(14),
          borderSide: const BorderSide(color: AppColors.darkPink, width: 1.8),
        ),
      ),
      navigationBarTheme: NavigationBarThemeData(
        backgroundColor: AppColors.darkSurface,
        indicatorColor: AppColors.darkGold.withOpacity(0.22),
        height: 72,
        iconTheme: WidgetStateProperty.resolveWith(
          (states) => IconThemeData(
            color: states.contains(WidgetState.selected)
                ? AppColors.darkGold
                : AppColors.darkMuted,
          ),
        ),
        labelTextStyle: WidgetStateProperty.resolveWith(
          (states) => inter(
            12,
            FontWeight.w700,
            states.contains(WidgetState.selected)
                ? AppColors.darkGold
                : AppColors.darkMuted,
          ),
        ),
      ),
      navigationRailTheme: NavigationRailThemeData(
        backgroundColor: AppColors.darkSurface,
        indicatorColor: AppColors.darkGold.withOpacity(0.22),
        selectedIconTheme: const IconThemeData(color: AppColors.darkGold),
        unselectedIconTheme: const IconThemeData(color: AppColors.darkMuted),
        selectedLabelTextStyle: inter(13, FontWeight.w700, AppColors.darkGold),
        unselectedLabelTextStyle:
            inter(13, FontWeight.w600, AppColors.darkMuted),
      ),
      drawerTheme: const DrawerThemeData(
        backgroundColor: AppColors.darkBase,
        surfaceTintColor: Colors.transparent,
      ),
      dividerTheme: DividerThemeData(
        color: AppColors.darkGold.withOpacity(0.25),
        space: 1,
        thickness: 1,
      ),
      chipTheme: ChipThemeData(
        backgroundColor: AppColors.darkSurface,
        selectedColor: AppColors.darkElevated,
        labelStyle: inter(12, FontWeight.w700, AppColors.darkText),
        secondaryLabelStyle: inter(12, FontWeight.w700, AppColors.darkText),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(20),
          side: const BorderSide(color: AppColors.darkBorder),
        ),
      ),
      listTileTheme: ListTileThemeData(
        iconColor: AppColors.darkGold,
        textColor: AppColors.darkText,
        titleTextStyle: inter(14, FontWeight.w700, AppColors.darkText),
        subtitleTextStyle: inter(12, FontWeight.w600, AppColors.darkMuted),
      ),
      dialogTheme: DialogTheme(
        backgroundColor: AppColors.darkCard,
        surfaceTintColor: Colors.transparent,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(18),
          side: const BorderSide(color: AppColors.darkBorder),
        ),
        titleTextStyle: inter(20, FontWeight.w800, AppColors.darkText),
      ),
      snackBarTheme: SnackBarThemeData(
        behavior: SnackBarBehavior.floating,
        backgroundColor: AppColors.darkElevated,
        contentTextStyle: inter(13, FontWeight.w600, AppColors.darkText),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      ),
      progressIndicatorTheme:
          const ProgressIndicatorThemeData(color: AppColors.darkPink),
      pageTransitionsTheme: const PageTransitionsTheme(
        builders: {
          TargetPlatform.android: ZoomPageTransitionsBuilder(),
          TargetPlatform.iOS: CupertinoPageTransitionsBuilder(),
        },
      ),
    );
  }

  /// Wraps page content with the themed background gradient.
  static Widget pageBackground({
    required BuildContext context,
    required Widget child,
  }) {
    final dark = Theme.of(context).brightness == Brightness.dark;
    return DecoratedBox(
      decoration: BoxDecoration(
        gradient: dark ? AppColors.darkPageGradient : AppColors.pageGradient,
      ),
      child: child,
    );
  }
}
