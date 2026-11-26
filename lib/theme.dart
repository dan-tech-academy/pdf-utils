import 'package:flutter/material.dart';

/// App-wide look: deep navy and silver on flat surfaces with hairline
/// borders, set in Be Vietnam Pro. Screens take colours from
/// `Theme.of(context).colorScheme` instead of hard-coding them.
abstract final class AppTheme {
  static const fontFamily = 'BeVietnamPro';

  static final ThemeData light = _build(_lightScheme);
  static final ThemeData dark = _build(_darkScheme);

  static const _lightScheme = ColorScheme(
    brightness: Brightness.light,
    primary: Color(0xFF14213D),
    onPrimary: Color(0xFFFFFFFF),
    primaryContainer: Color(0xFFE5EAF2),
    onPrimaryContainer: Color(0xFF14213D),
    secondary: Color(0xFF5A6577),
    onSecondary: Color(0xFFFFFFFF),
    secondaryContainer: Color(0xFFE6E9EF),
    onSecondaryContainer: Color(0xFF1B2638),
    tertiary: Color(0xFF6C7A8F),
    onTertiary: Color(0xFFFFFFFF),
    tertiaryContainer: Color(0xFFE9ECF1),
    onTertiaryContainer: Color(0xFF1B2638),
    error: Color(0xFFA3302A),
    onError: Color(0xFFFFFFFF),
    errorContainer: Color(0xFFF8E7E5),
    onErrorContainer: Color(0xFF5E1611),
    surface: Color(0xFFF5F6F8),
    onSurface: Color(0xFF141A24),
    onSurfaceVariant: Color(0xFF5C6575),
    surfaceDim: Color(0xFFDADDE3),
    surfaceBright: Color(0xFFFBFBFC),
    surfaceContainerLowest: Color(0xFFFFFFFF),
    surfaceContainerLow: Color(0xFFFAFBFC),
    surfaceContainer: Color(0xFFF0F2F5),
    surfaceContainerHigh: Color(0xFFEAEDF1),
    surfaceContainerHighest: Color(0xFFE4E7EC),
    // Inputs use `outline` as their only boundary, so it keeps ≥3:1
    // contrast against both the page (3.1:1) and their white fill (3.4:1).
    outline: Color(0xFF838C9C),
    outlineVariant: Color(0xFFDFE3E9),
    shadow: Color(0xFF000000),
    scrim: Color(0xFF000000),
    inverseSurface: Color(0xFF232A36),
    onInverseSurface: Color(0xFFF1F3F6),
    inversePrimary: Color(0xFFAFC0DD),
  );

  static const _darkScheme = ColorScheme(
    brightness: Brightness.dark,
    primary: Color(0xFFC9D4E8),
    onPrimary: Color(0xFF0F1A2E),
    primaryContainer: Color(0xFF1F2C45),
    onPrimaryContainer: Color(0xFFD9E1EF),
    secondary: Color(0xFFA4AEBE),
    onSecondary: Color(0xFF1A2231),
    secondaryContainer: Color(0xFF252F41),
    onSecondaryContainer: Color(0xFFD9E1EF),
    tertiary: Color(0xFFAEB8C8),
    onTertiary: Color(0xFF1A2231),
    tertiaryContainer: Color(0xFF2A3446),
    onTertiaryContainer: Color(0xFFDCE3EF),
    error: Color(0xFFF0A9A3),
    onError: Color(0xFF4A0E0A),
    errorContainer: Color(0xFF3F1A1A),
    onErrorContainer: Color(0xFFF9DEDB),
    surface: Color(0xFF0C121D),
    onSurface: Color(0xFFE5E8EE),
    onSurfaceVariant: Color(0xFF9AA3B2),
    surfaceDim: Color(0xFF0C121D),
    surfaceBright: Color(0xFF2B3342),
    surfaceContainerLowest: Color(0xFF080D16),
    surfaceContainerLow: Color(0xFF121A27),
    surfaceContainer: Color(0xFF161E2C),
    surfaceContainerHigh: Color(0xFF1B2433),
    surfaceContainerHighest: Color(0xFF212B3B),
    outline: Color(0xFF6B7586),
    outlineVariant: Color(0xFF263043),
    shadow: Color(0xFF000000),
    scrim: Color(0xFF000000),
    inverseSurface: Color(0xFFE5E8EE),
    onInverseSurface: Color(0xFF1A2130),
    inversePrimary: Color(0xFF2E4166),
  );

  // Tighter tracking than the Material defaults: Be Vietnam Pro is wide,
  // and the generous line heights leave room for stacked diacritics.
  static const _textTheme = TextTheme(
    displayLarge: TextStyle(fontSize: 56, height: 1.12, letterSpacing: -1),
    displayMedium: TextStyle(fontSize: 44, height: 1.16, letterSpacing: -0.8),
    displaySmall: TextStyle(fontSize: 36, height: 1.2, letterSpacing: -0.6),
    headlineLarge: TextStyle(
      fontSize: 32,
      fontWeight: FontWeight.w600,
      height: 1.25,
      letterSpacing: -0.6,
    ),
    headlineMedium: TextStyle(
      fontSize: 28,
      fontWeight: FontWeight.w600,
      height: 1.28,
      letterSpacing: -0.5,
    ),
    headlineSmall: TextStyle(
      fontSize: 24,
      fontWeight: FontWeight.w600,
      height: 1.32,
      letterSpacing: -0.4,
    ),
    titleLarge: TextStyle(
      fontSize: 20,
      fontWeight: FontWeight.w600,
      height: 1.35,
      letterSpacing: -0.2,
    ),
    titleMedium: TextStyle(
      fontSize: 16,
      fontWeight: FontWeight.w500,
      height: 1.4,
      letterSpacing: -0.1,
    ),
    titleSmall: TextStyle(
      fontSize: 14,
      fontWeight: FontWeight.w500,
      height: 1.4,
      letterSpacing: 0,
    ),
    bodyLarge: TextStyle(fontSize: 16, height: 1.5, letterSpacing: 0),
    bodyMedium: TextStyle(fontSize: 14, height: 1.5, letterSpacing: 0.1),
    bodySmall: TextStyle(fontSize: 12.5, height: 1.45, letterSpacing: 0.1),
    labelLarge: TextStyle(
      fontSize: 14,
      fontWeight: FontWeight.w600,
      height: 1.4,
      letterSpacing: 0.1,
    ),
    labelMedium: TextStyle(
      fontSize: 12,
      fontWeight: FontWeight.w500,
      height: 1.35,
      letterSpacing: 0.2,
    ),
    labelSmall: TextStyle(
      fontSize: 11,
      fontWeight: FontWeight.w500,
      height: 1.35,
      letterSpacing: 0.3,
    ),
  );

  static ThemeData _build(ColorScheme scheme) {
    final isDark = scheme.brightness == Brightness.dark;
    final cardColor = isDark
        ? scheme.surfaceContainerLow
        : scheme.surfaceContainerLowest;
    // Hairline for controls that also carry a label, so the border is not
    // their only cue.
    final softSide = BorderSide(color: scheme.outline.withValues(alpha: 0.5));

    RoundedRectangleBorder rounded(
      double radius, [
      BorderSide side = BorderSide.none,
    ]) => RoundedRectangleBorder(
      borderRadius: BorderRadius.circular(radius),
      side: side,
    );

    OutlineInputBorder inputBorder(Color color, [double width = 1]) =>
        OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: BorderSide(color: color, width: width),
        );

    return ThemeData(
      useMaterial3: true,
      colorScheme: scheme,
      fontFamily: fontFamily,
      textTheme: _textTheme,
      splashFactory: InkRipple.splashFactory,
      appBarTheme: AppBarThemeData(
        backgroundColor: scheme.surface,
        foregroundColor: scheme.onSurface,
        elevation: 0,
        scrolledUnderElevation: 1,
        shadowColor: scheme.shadow.withValues(alpha: isDark ? 0.5 : 0.12),
        surfaceTintColor: Colors.transparent,
        centerTitle: false,
      ),
      cardTheme: CardThemeData(
        color: cardColor,
        elevation: 0,
        surfaceTintColor: Colors.transparent,
        margin: const EdgeInsets.symmetric(vertical: 4),
        clipBehavior: Clip.antiAlias,
        shape: rounded(16, BorderSide(color: scheme.outlineVariant)),
      ),
      dividerTheme: DividerThemeData(
        color: scheme.outlineVariant,
        thickness: 1,
        space: 1,
      ),
      filledButtonTheme: FilledButtonThemeData(
        style: FilledButton.styleFrom(
          minimumSize: const Size(64, 48),
          padding: const EdgeInsets.symmetric(horizontal: 20),
          shape: rounded(12),
        ),
      ),
      outlinedButtonTheme: OutlinedButtonThemeData(
        style: OutlinedButton.styleFrom(
          minimumSize: const Size(64, 48),
          padding: const EdgeInsets.symmetric(horizontal: 20),
          foregroundColor: scheme.onSurface,
          side: softSide,
          shape: rounded(12),
        ),
      ),
      textButtonTheme: TextButtonThemeData(
        style: TextButton.styleFrom(shape: rounded(10)),
      ),
      segmentedButtonTheme: SegmentedButtonThemeData(
        style: SegmentedButton.styleFrom(side: softSide, shape: rounded(12)),
      ),
      chipTheme: ChipThemeData(
        side: softSide,
        shape: rounded(10),
        selectedColor: scheme.secondaryContainer,
      ),
      sliderTheme: SliderThemeData(
        trackHeight: 3,
        activeTrackColor: scheme.primary,
        inactiveTrackColor: scheme.primary.withValues(
          alpha: isDark ? 0.24 : 0.14,
        ),
        thumbColor: scheme.primary,
        overlayColor: scheme.primary.withValues(alpha: 0.08),
        // Sliders with many divisions would otherwise draw a row of dots.
        activeTickMarkColor: Colors.transparent,
        inactiveTickMarkColor: Colors.transparent,
      ),
      inputDecorationTheme: InputDecorationThemeData(
        filled: true,
        fillColor: cardColor,
        contentPadding: const EdgeInsets.symmetric(
          horizontal: 16,
          vertical: 14,
        ),
        border: inputBorder(scheme.outline),
        enabledBorder: inputBorder(scheme.outline),
        focusedBorder: inputBorder(scheme.primary, 1.5),
        errorBorder: inputBorder(scheme.error),
        focusedErrorBorder: inputBorder(scheme.error, 1.5),
        disabledBorder: inputBorder(scheme.outlineVariant),
      ),
    );
  }
}
