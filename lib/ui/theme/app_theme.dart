import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

/// Impactful yet soft gray-toned color palette.
///
/// Based on a cool-gray scale with cyan-tinted accent for scientific feel.
class AppColors {
  AppColors._();

  // ── Base grays ──
  static const Color gray950 = Color(0xFF0A0A0F);
  static const Color gray900 = Color(0xFF131318);
  static const Color gray850 = Color(0xFF1A1A22);
  static const Color gray800 = Color(0xFF22222D);
  static const Color gray750 = Color(0xFF2A2A38);
  static const Color gray700 = Color(0xFF33334A);
  static const Color gray600 = Color(0xFF4A4A65);
  static const Color gray500 = Color(0xFF6B6B88);
  static const Color gray400 = Color(0xFF8E8EA8);
  static const Color gray300 = Color(0xFFAFAFC4);
  static const Color gray200 = Color(0xFFCFCFDB);
  static const Color gray100 = Color(0xFFE8E8F0);
  static const Color gray50 = Color(0xFFF4F4F8);

  // ── Accent: Soft cyan ──
  static const Color accent = Color(0xFF5EC4D4);
  static const Color accentLight = Color(0xFF8DD8E4);
  static const Color accentDark = Color(0xFF3AA8B8);
  static const Color accentSubtle = Color(0xFF1E3A3F);

  // ── Semantic ──
  static const Color success = Color(0xFF4ADE80);
  static const Color successSubtle = Color(0xFF1A3A28);
  static const Color warning = Color(0xFFFBBF24);
  static const Color warningSubtle = Color(0xFF3A3318);
  static const Color error = Color(0xFFF87171);
  static const Color errorSubtle = Color(0xFF3A1A1A);
  static const Color info = Color(0xFF60A5FA);

  // ── Charts ──
  static const List<Color> chartPalette = [
    Color(0xFF5EC4D4), // cyan
    Color(0xFFA78BFA), // violet
    Color(0xFF4ADE80), // green
    Color(0xFFFBBF24), // amber
    Color(0xFFF87171), // red
    Color(0xFF60A5FA), // blue
    Color(0xFFF9A8D4), // pink
    Color(0xFF34D399), // emerald
  ];

  // ── Surface ──
  static const Color surface = gray850;
  static const Color surfaceVariant = gray800;
  static const Color surfaceElevated = gray750;
  static const Color background = gray900;
  static const Color backgroundDeep = gray950;

  // ── Text ──
  static const Color textPrimary = gray100;
  static const Color textSecondary = gray400;
  static const Color textTertiary = gray500;
  static const Color textOnAccent = gray950;
}

/// App theme builder.
class AppTheme {
  AppTheme._();

  static ThemeData get dark {
    final textTheme = GoogleFonts.interTextTheme().apply(
      bodyColor: AppColors.textPrimary,
      displayColor: AppColors.textPrimary,
    );

    return ThemeData(
      useMaterial3: true,
      brightness: Brightness.dark,
      scaffoldBackgroundColor: AppColors.background,
      textTheme: textTheme,
      colorScheme: const ColorScheme.dark(
        primary: AppColors.accent,
        onPrimary: AppColors.textOnAccent,
        secondary: AppColors.accentLight,
        onSecondary: AppColors.textOnAccent,
        surface: AppColors.surface,
        onSurface: AppColors.textPrimary,
        error: AppColors.error,
        onError: AppColors.textPrimary,
        outline: AppColors.gray700,
        outlineVariant: AppColors.gray750,
      ),
      appBarTheme: AppBarTheme(
        backgroundColor: AppColors.backgroundDeep,
        foregroundColor: AppColors.textPrimary,
        elevation: 0,
        centerTitle: false,
        titleTextStyle: GoogleFonts.inter(
          fontSize: 18,
          fontWeight: FontWeight.w600,
          color: AppColors.textPrimary,
        ),
      ),
      cardTheme: CardThemeData(
        color: AppColors.surface,
        elevation: 0,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(12),
          side: const BorderSide(color: AppColors.gray750, width: 1),
        ),
        margin: const EdgeInsets.all(0),
      ),
      elevatedButtonTheme: ElevatedButtonThemeData(
        style: ElevatedButton.styleFrom(
          backgroundColor: AppColors.accent,
          foregroundColor: AppColors.textOnAccent,
          elevation: 0,
          padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 14),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(10),
          ),
          textStyle: GoogleFonts.inter(
            fontSize: 14,
            fontWeight: FontWeight.w600,
          ),
        ),
      ),
      outlinedButtonTheme: OutlinedButtonThemeData(
        style: OutlinedButton.styleFrom(
          foregroundColor: AppColors.accent,
          side: const BorderSide(color: AppColors.gray600),
          padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 14),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(10),
          ),
        ),
      ),
      textButtonTheme: TextButtonThemeData(
        style: TextButton.styleFrom(
          foregroundColor: AppColors.accent,
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
        ),
      ),
      inputDecorationTheme: InputDecorationTheme(
        filled: true,
        fillColor: AppColors.surfaceVariant,
        contentPadding: const EdgeInsets.symmetric(
          horizontal: 16,
          vertical: 14,
        ),
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(10),
          borderSide: const BorderSide(color: AppColors.gray700),
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(10),
          borderSide: const BorderSide(color: AppColors.gray700),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(10),
          borderSide: const BorderSide(color: AppColors.accent, width: 1.5),
        ),
        labelStyle: const TextStyle(color: AppColors.textSecondary),
        hintStyle: const TextStyle(color: AppColors.textTertiary),
      ),
      dividerTheme: const DividerThemeData(
        color: AppColors.gray750,
        thickness: 1,
        space: 1,
      ),
      chipTheme: ChipThemeData(
        backgroundColor: AppColors.surfaceVariant,
        labelStyle: GoogleFonts.inter(
          fontSize: 12,
          color: AppColors.textSecondary,
        ),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(8),
          side: const BorderSide(color: AppColors.gray700),
        ),
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      ),
      sliderTheme: SliderThemeData(
        activeTrackColor: AppColors.accent,
        inactiveTrackColor: AppColors.gray700,
        thumbColor: AppColors.accent,
        overlayColor: AppColors.accent.withValues(alpha: 0.12),
        trackHeight: 4,
      ),
      switchTheme: SwitchThemeData(
        thumbColor: WidgetStateProperty.resolveWith((states) {
          if (states.contains(WidgetState.selected)) return AppColors.accent;
          return AppColors.gray500;
        }),
        trackColor: WidgetStateProperty.resolveWith((states) {
          if (states.contains(WidgetState.selected)) {
            return AppColors.accentSubtle;
          }
          return AppColors.gray750;
        }),
      ),
      progressIndicatorTheme: const ProgressIndicatorThemeData(
        color: AppColors.accent,
        linearTrackColor: AppColors.gray750,
      ),
      tooltipTheme: TooltipThemeData(
        decoration: BoxDecoration(
          color: AppColors.surfaceElevated,
          borderRadius: BorderRadius.circular(8),
          border: Border.all(color: AppColors.gray700),
        ),
        textStyle: GoogleFonts.inter(
          fontSize: 12,
          color: AppColors.textPrimary,
        ),
      ),
      navigationRailTheme: NavigationRailThemeData(
        backgroundColor: AppColors.backgroundDeep,
        selectedIconTheme: const IconThemeData(
          color: AppColors.accent,
          size: 22,
        ),
        unselectedIconTheme: const IconThemeData(
          color: AppColors.gray500,
          size: 22,
        ),
        selectedLabelTextStyle: GoogleFonts.inter(
          fontSize: 11,
          fontWeight: FontWeight.w600,
          color: AppColors.accent,
        ),
        unselectedLabelTextStyle: GoogleFonts.inter(
          fontSize: 11,
          color: AppColors.gray500,
        ),
        indicatorColor: AppColors.accentSubtle,
      ),
      bottomNavigationBarTheme: BottomNavigationBarThemeData(
        backgroundColor: AppColors.backgroundDeep,
        selectedItemColor: AppColors.accent,
        unselectedItemColor: AppColors.gray500,
        selectedLabelStyle: GoogleFonts.inter(
          fontSize: 11,
          fontWeight: FontWeight.w600,
        ),
        unselectedLabelStyle: GoogleFonts.inter(fontSize: 11),
        type: BottomNavigationBarType.fixed,
      ),
      snackBarTheme: SnackBarThemeData(
        backgroundColor: AppColors.surfaceElevated,
        contentTextStyle: GoogleFonts.inter(color: AppColors.textPrimary),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
        behavior: SnackBarBehavior.floating,
      ),
    );
  }
}
