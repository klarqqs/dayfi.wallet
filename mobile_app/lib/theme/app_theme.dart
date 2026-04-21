// lib/theme/app_theme.dart
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:google_fonts/google_fonts.dart';

class DayFiColors {
  // Dark theme (default)
  static const background = Color(0xFF000000);
  static const surface = Color(0xFF0A0A0A);
  static const card = Color(0xFF111111);
  static const border = Color(0xFF1E1E1E);
  static const textPrimary = Color(0xFFFFFFFF);
  static const textSecondary = Color(0xFF888888);
  static const textMuted = Color(0xFF444444);

  // Accent
  static const green = Color(0xFF00E676);
  static const greenDim = Color(0xFF1A3326);
  static const red = Color(0xFFFF4444);
  static const redDim = Color(0xFF3D1515);

  // Light theme
  static const lightBackground = Color(0xFFF5F5F5);
  static const lightSurface = Color(0xFFFFFFFF);
  static const lightCard = Color(0xFFF0F0F0);
  static const lightBorder = Color(0xFFE0E0E0);
  static const lightTextPrimary = Color(0xFF000000);
  static const lightTextSecondary = Color(0xFF666666);
}

// schibstedGrotesk
// medievalSharp

class AppTheme {
  static TextTheme _buildTextTheme(Color primary, Color secondary) {
    final base = GoogleFonts.bricolageGrotesqueTextTheme();
    return base.copyWith(
      displayLarge: GoogleFonts.bricolageGrotesque(
        fontSize: 44,
        fontWeight: FontWeight.w400,
        color: primary,
        letterSpacing: -2,
      ),
      displayMedium: GoogleFonts.bricolageGrotesque(
        fontSize: 36,
        fontWeight: FontWeight.w400,
        color: primary,
        letterSpacing: -1.5,
      ),
      displaySmall: GoogleFonts.bricolageGrotesque(
        fontSize: 28,
        fontWeight: FontWeight.w400,
        color: primary,
        letterSpacing: -1,
      ),
      headlineMedium: GoogleFonts.bricolageGrotesque(
        fontSize: 22,
        fontWeight: FontWeight.w600,
        color: primary,
        letterSpacing: -0.5,
      ),
      titleLarge: GoogleFonts.bricolageGrotesque(
        fontSize: 18,
        fontWeight: FontWeight.w600,
        color: primary,
      ),
      titleMedium: GoogleFonts.bricolageGrotesque(
        fontSize: 16,
        fontWeight: FontWeight.w600,
        color: primary,
      ),
      bodyLarge: GoogleFonts.bricolageGrotesque(
        fontSize: 16,
        fontWeight: FontWeight.w600,
        color: primary,
      ),
      bodyMedium: GoogleFonts.bricolageGrotesque(
        fontSize: 14,
        fontWeight: FontWeight.w400,
        color: secondary,
      ),
      bodySmall: GoogleFonts.bricolageGrotesque(
        fontSize: 12,
        fontWeight: FontWeight.w400,
        color: secondary,
      ),
      labelLarge: GoogleFonts.bricolageGrotesque(
        fontSize: 16,
        fontWeight: FontWeight.w500,
        color: primary,
      ),
    );
  }

  static ThemeData dark() {
    return ThemeData(
      brightness: Brightness.dark,
      scaffoldBackgroundColor: DayFiColors.background,
      colorScheme: const ColorScheme.dark(
        background: DayFiColors.background,
        surface: DayFiColors.surface,
        primary: DayFiColors.textPrimary,
        secondary: DayFiColors.green,
        error: DayFiColors.red,
        onBackground: DayFiColors.textPrimary,
        onSurface: DayFiColors.textPrimary,
      ),
      textTheme: _buildTextTheme(
        DayFiColors.textPrimary,
        DayFiColors.textSecondary,
      ),
      appBarTheme: AppBarTheme(
        backgroundColor: DayFiColors.background,
        elevation: 0,
        centerTitle: true,
        systemOverlayStyle: SystemUiOverlayStyle.light,
        titleTextStyle: GoogleFonts.bricolageGrotesque(
          fontSize: 16,
          fontWeight: FontWeight.w500,
          color: DayFiColors.textPrimary,
        ),
        iconTheme: const IconThemeData(color: DayFiColors.textPrimary),
      ),
      inputDecorationTheme: InputDecorationTheme(
        filled: true,
        fillColor: DayFiColors.card,
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(14),
          borderSide: const BorderSide(color: DayFiColors.border),
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(14),
          borderSide: const BorderSide(color: DayFiColors.border),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(14),
          borderSide: const BorderSide(
            color: DayFiColors.textPrimary,
            width: 1.5,
          ),
        ),
        errorBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(14),
          borderSide: const BorderSide(color: DayFiColors.red),
        ),
        contentPadding: const EdgeInsets.symmetric(
          horizontal: 18,
          vertical: 18,
        ),
        hintStyle: GoogleFonts.bricolageGrotesque(
          color: DayFiColors.textMuted,
          fontSize: 16,
        ),
        labelStyle: GoogleFonts.bricolageGrotesque(color: DayFiColors.textSecondary),
      ),
      elevatedButtonTheme: ElevatedButtonThemeData(
        style: ElevatedButton.styleFrom(
          backgroundColor: DayFiColors.textPrimary,
          foregroundColor: DayFiColors.background,
          minimumSize: const Size(double.infinity, 56),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(16),
          ),
          textStyle: GoogleFonts.bricolageGrotesque(
            fontSize: 16,
            fontWeight: FontWeight.w500,
          ),
          elevation: 0,
        ),
      ),
      outlinedButtonTheme: OutlinedButtonThemeData(
        style: OutlinedButton.styleFrom(
          foregroundColor: DayFiColors.textPrimary,
          minimumSize: const Size(double.infinity, 56),
          side: const BorderSide(color: DayFiColors.border, width: 1.5),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(16),
          ),
          textStyle: GoogleFonts.bricolageGrotesque(
            fontSize: 16,
            fontWeight: FontWeight.w500,
          ),
        ),
      ),
      textButtonTheme: TextButtonThemeData(
        style: TextButton.styleFrom(
          foregroundColor: DayFiColors.textSecondary,
          textStyle: GoogleFonts.bricolageGrotesque(
            fontSize: 14,
            fontWeight: FontWeight.w400,
          ),
        ),
      ),
      dividerTheme: const DividerThemeData(
        color: DayFiColors.border,
        thickness: 1,
      ),
      cardTheme: CardThemeData(
        color: DayFiColors.card,
        elevation: 0,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(16),
          side: const BorderSide(color: DayFiColors.border),
        ),
      ),
    );
  }

  static ThemeData light() {
    return ThemeData(
      brightness: Brightness.light,
      scaffoldBackgroundColor: DayFiColors.lightBackground,
      colorScheme: const ColorScheme.light(
        background: DayFiColors.lightBackground,
        surface: DayFiColors.lightSurface,
        primary: DayFiColors.lightTextPrimary,
        secondary: Color(0xFF00B459),
        error: DayFiColors.red,
      ),
      textTheme: _buildTextTheme(
        DayFiColors.lightTextPrimary,
        DayFiColors.lightTextSecondary,
      ),
      appBarTheme: AppBarTheme(
        backgroundColor: DayFiColors.lightBackground,
        elevation: 0,
        centerTitle: true,
        systemOverlayStyle: SystemUiOverlayStyle.dark,
        titleTextStyle: GoogleFonts.bricolageGrotesque(
          fontSize: 16,
          fontWeight: FontWeight.w500,
          color: DayFiColors.lightTextPrimary,
        ),
        iconTheme: const IconThemeData(color: DayFiColors.lightTextPrimary),
      ),
      inputDecorationTheme: InputDecorationTheme(
        filled: true,
        fillColor: DayFiColors.lightSurface,
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(14),
          borderSide: const BorderSide(color: DayFiColors.lightBorder),
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(14),
          borderSide: const BorderSide(color: DayFiColors.lightBorder),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(14),
          borderSide: const BorderSide(
            color: DayFiColors.lightTextPrimary,
            width: 1.5,
          ),
        ),
        contentPadding: const EdgeInsets.symmetric(
          horizontal: 18,
          vertical: 18,
        ),
        hintStyle: GoogleFonts.bricolageGrotesque(
          color: DayFiColors.lightTextSecondary,
          fontSize: 16,
        ),
      ),
      elevatedButtonTheme: ElevatedButtonThemeData(
        style: ElevatedButton.styleFrom(
          backgroundColor: DayFiColors.lightTextPrimary,
          foregroundColor: DayFiColors.lightBackground,
          minimumSize: const Size(double.infinity, 56),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(16),
          ),
          textStyle: GoogleFonts.bricolageGrotesque(
            fontSize: 16,
            fontWeight: FontWeight.w500,
          ),
          elevation: 0,
        ),
      ),
      cardTheme: CardThemeData(
        color: DayFiColors.lightSurface,
        elevation: 0,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(16),
          side: const BorderSide(color: DayFiColors.lightBorder),
        ),
      ),
    );
  }
}
