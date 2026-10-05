// ─────────────────────────────────────────────────────────────────────────────
// app_theme.dart
//
// Single source of truth for Iqtadi's emerald and ivory visual language:
// spacing scale, corner radii and the Material 3 light theme built from them.
//
// Screens must not hard-code colors or paddings — they read tokens from here
// (or the small widget kit in `ui_kit.dart`) so every screen stays visually
// consistent. The accent is the same green the AR skeleton uses, which keeps
// the camera layer and the chrome around it reading as one product.
// ─────────────────────────────────────────────────────────────────────────────

import 'package:flutter/material.dart';

/// Semantic colors. Use these instead of raw [Colors] constants.
abstract final class AppColors {
  /// Primary action / "ready" state. Matches the skeleton overlay green.
  static const Color emerald = Color(0xFF073E30);
  static const Color gold = Color(0xFFC5A264);
  static const Color accent = Color(0xFF126B4D);

  /// Text and icons drawn on top of [accent].
  static const Color onAccent = Color(0xFFFFF8E9);

  /// Needs attention, but the session is still usable.
  static const Color warning = Color(0xFF956C23);

  /// Blocking problem: bad address, no reference, failed source.
  static const Color danger = Color(0xFFB54236);

  /// Neutral information and guidance.
  static const Color info = Color(0xFF39777B);

  /// Warm ivory canvas, shared by phone and web layouts.
  static const Color canvas = Color(0xFFF6F0E5);

  /// Default card / panel fill.
  static const Color surface = Color(0xFFFFFCF6);

  /// Raised fill (chips, progress tracks, snackbars).
  static const Color surfaceHigh = Color(0xFFF0E8D9);

  /// Highest fill (pressed/disabled states, tracks).
  static const Color surfaceHigher = Color(0xFFE4DAC7);

  /// Hairline borders.
  static const Color border = Color(0xFFE6DCCB);

  static const Color textPrimary = Color(0xFF142E26);
  static const Color textSecondary = Color(0xFF65756B);
}

/// 4-pt spacing scale. Every gap in the app picks a step from here.
abstract final class AppSpacing {
  static const double xs = 4;
  static const double sm = 8;
  static const double md = 12;
  static const double lg = 16;
  static const double xl = 24;
  static const double xxl = 32;
}

/// Corner radii. Cards and panels use [card]; tags and progress bars [pill].
abstract final class AppRadius {
  static const double sm = 12;
  static const double md = 22;

  static const BorderRadius card = BorderRadius.all(Radius.circular(md));
  static const BorderRadius small = BorderRadius.all(Radius.circular(sm));
  static const BorderRadius pill = BorderRadius.all(Radius.circular(999));
}

TextStyle _text(
  double size,
  FontWeight weight, {
  double height = 1.5,
  Color color = AppColors.textPrimary,
}) =>
    TextStyle(
        fontFamily: 'IqtadiArabic',
        fontSize: size,
        fontWeight: weight,
        height: height,
        color: color);

/// Builds the app-wide ivory theme. Arabic copy needs a taller line height than
/// the Material default, so every text role sets it explicitly.
ThemeData buildAppTheme() {
  final scheme = ColorScheme.fromSeed(
    seedColor: AppColors.accent,
    brightness: Brightness.light,
  ).copyWith(
    primary: AppColors.accent,
    onPrimary: AppColors.onAccent,
    secondary: AppColors.accent,
    surface: AppColors.canvas,
    onSurface: AppColors.textPrimary,
    surfaceContainerLow: AppColors.surface,
    surfaceContainer: AppColors.surfaceHigh,
    surfaceContainerHigh: AppColors.surfaceHigher,
    onSurfaceVariant: AppColors.textSecondary,
    outline: AppColors.border,
    outlineVariant: AppColors.border,
    error: AppColors.danger,
  );

  final base = ThemeData(
      useMaterial3: true, colorScheme: scheme, fontFamily: 'IqtadiArabic');
  final text = base.textTheme
      .copyWith(
        headlineSmall: _text(23, FontWeight.w700, height: 1.35),
        titleLarge: _text(19, FontWeight.w700, height: 1.4),
        titleMedium: _text(16.5, FontWeight.w600, height: 1.45),
        titleSmall: _text(13.5, FontWeight.w600,
            height: 1.4, color: AppColors.textSecondary),
        bodyLarge: _text(16, FontWeight.w400, height: 1.65),
        bodyMedium: _text(14.5, FontWeight.w400, height: 1.65),
        bodySmall: _text(12.5, FontWeight.w400,
            height: 1.6, color: AppColors.textSecondary),
        labelLarge: _text(15.5, FontWeight.w600, height: 1.3),
      )
      .apply(fontFamily: 'IqtadiArabic');

  const buttonShape = RoundedRectangleBorder(borderRadius: AppRadius.card);
  const buttonPadding =
      EdgeInsets.symmetric(horizontal: AppSpacing.xl, vertical: 14);
  const buttonSize = Size.fromHeight(52);

  return base.copyWith(
    scaffoldBackgroundColor: AppColors.canvas,
    textTheme: text,
    iconTheme: const IconThemeData(color: AppColors.textSecondary, size: 22),
    appBarTheme: AppBarThemeData(
      backgroundColor: AppColors.canvas,
      surfaceTintColor: Colors.transparent,
      foregroundColor: AppColors.textPrimary,
      elevation: 0,
      scrolledUnderElevation: 0,
      centerTitle: true,
      titleTextStyle: _text(20, FontWeight.w700, height: 1.3),
      iconTheme: const IconThemeData(color: AppColors.textPrimary, size: 22),
    ),
    dividerTheme: const DividerThemeData(
      color: AppColors.border,
      thickness: 1,
      space: 1,
    ),
    cardTheme: const CardThemeData(
      color: AppColors.surface,
      surfaceTintColor: Colors.transparent,
      elevation: 0,
      margin: EdgeInsets.zero,
      shape: RoundedRectangleBorder(
        borderRadius: AppRadius.card,
        side: BorderSide(color: AppColors.border),
      ),
    ),
    filledButtonTheme: FilledButtonThemeData(
      style: FilledButton.styleFrom(
        backgroundColor: AppColors.accent,
        foregroundColor: AppColors.onAccent,
        disabledBackgroundColor: AppColors.surfaceHigher,
        disabledForegroundColor: AppColors.textSecondary,
        minimumSize: buttonSize,
        padding: buttonPadding,
        shape: buttonShape,
        textStyle: text.labelLarge,
        elevation: 0,
      ),
    ),
    outlinedButtonTheme: OutlinedButtonThemeData(
      style: OutlinedButton.styleFrom(
        foregroundColor: AppColors.accent,
        disabledForegroundColor: AppColors.textSecondary,
        disabledBackgroundColor: Colors.transparent,
        backgroundColor: AppColors.accent.withValues(alpha: .06),
        side: BorderSide(color: AppColors.accent.withValues(alpha: .55)),
        minimumSize: buttonSize,
        padding: buttonPadding,
        shape: buttonShape,
        textStyle: text.labelLarge,
      ),
    ),
    textButtonTheme: TextButtonThemeData(
      style: TextButton.styleFrom(
        foregroundColor: AppColors.accent,
        disabledForegroundColor: AppColors.textSecondary,
        padding: const EdgeInsets.symmetric(
            horizontal: AppSpacing.md, vertical: AppSpacing.sm),
        textStyle: text.labelLarge,
      ),
    ),
    inputDecorationTheme: InputDecorationThemeData(
      filled: true,
      fillColor: AppColors.surfaceHigh,
      contentPadding: const EdgeInsets.symmetric(
          horizontal: AppSpacing.lg, vertical: AppSpacing.lg),
      labelStyle: text.bodyMedium?.copyWith(color: AppColors.textSecondary),
      floatingLabelStyle: text.bodyMedium?.copyWith(color: AppColors.accent),
      helperStyle: text.bodySmall,
      helperMaxLines: 2,
      prefixIconColor: AppColors.textSecondary,
      border: const OutlineInputBorder(
        borderRadius: AppRadius.small,
        borderSide: BorderSide(color: AppColors.border),
      ),
      enabledBorder: const OutlineInputBorder(
        borderRadius: AppRadius.small,
        borderSide: BorderSide(color: AppColors.border),
      ),
      focusedBorder: const OutlineInputBorder(
        borderRadius: AppRadius.small,
        borderSide: BorderSide(color: AppColors.accent, width: 1.6),
      ),
      disabledBorder: OutlineInputBorder(
        borderRadius: AppRadius.small,
        borderSide: BorderSide(color: AppColors.border.withValues(alpha: .5)),
      ),
      errorBorder: const OutlineInputBorder(
        borderRadius: AppRadius.small,
        borderSide: BorderSide(color: AppColors.danger),
      ),
      focusedErrorBorder: const OutlineInputBorder(
        borderRadius: AppRadius.small,
        borderSide: BorderSide(color: AppColors.danger, width: 1.6),
      ),
    ),
    progressIndicatorTheme: const ProgressIndicatorThemeData(
      color: AppColors.accent,
      linearTrackColor: AppColors.surfaceHigher,
      linearMinHeight: 8,
      borderRadius: AppRadius.pill,
    ),
    snackBarTheme: SnackBarThemeData(
      behavior: SnackBarBehavior.floating,
      backgroundColor: AppColors.surfaceHigher,
      contentTextStyle: _text(14.5, FontWeight.w500),
      shape: const RoundedRectangleBorder(borderRadius: AppRadius.small),
      insetPadding: const EdgeInsets.all(AppSpacing.lg),
    ),
  );
}
