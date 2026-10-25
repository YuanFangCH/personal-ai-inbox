import 'package:flutter/material.dart';

import 'app_design_tokens.dart';

class AppTheme {
  const AppTheme._();

  static ThemeData light() {
    final scheme = ColorScheme.fromSeed(
      seedColor: AppDesignTokens.primary,
      brightness: Brightness.light,
      primary: AppDesignTokens.primary,
      secondary: const Color(0xFF53658F),
      surface: AppDesignTokens.lightBackground,
      onSurface: AppDesignTokens.lightText,
    );
    return _base(scheme);
  }

  static ThemeData dark() {
    final scheme = ColorScheme.fromSeed(
      seedColor: AppDesignTokens.primaryDark,
      brightness: Brightness.dark,
      primary: AppDesignTokens.primaryDark,
      secondary: const Color(0xFFB1BEDF),
      surface: AppDesignTokens.darkBackground,
      onSurface: AppDesignTokens.darkText,
    );
    return _base(scheme);
  }

  static ThemeData _base(ColorScheme scheme) {
    final isDark = scheme.brightness == Brightness.dark;
    final border = isDark
        ? AppDesignTokens.darkBorder
        : AppDesignTokens.lightBorder;
    final sidebar = isDark
        ? AppDesignTokens.darkSidebar
        : AppDesignTokens.lightSidebar;
    final input = isDark
        ? AppDesignTokens.darkInput
        : AppDesignTokens.lightInput;
    final baseTextTheme = ThemeData(useMaterial3: true).textTheme
        .apply(bodyColor: scheme.onSurface, displayColor: scheme.onSurface);

    return ThemeData(
      useMaterial3: true,
      colorScheme: scheme,
      scaffoldBackgroundColor: scheme.surface,
      visualDensity: VisualDensity.standard,
      splashFactory: InkSparkle.splashFactory,
      textTheme: baseTextTheme.copyWith(
        bodyLarge: baseTextTheme.bodyLarge?.copyWith(
          fontSize: 16,
          height: 1.6,
          fontWeight: FontWeight.w400,
        ),
        bodyMedium: baseTextTheme.bodyMedium?.copyWith(
          fontSize: 15,
          height: 1.55,
          fontWeight: FontWeight.w400,
        ),
        bodySmall: baseTextTheme.bodySmall?.copyWith(fontSize: 13, height: 1.4),
        titleLarge: baseTextTheme.titleLarge?.copyWith(
          fontWeight: FontWeight.w600,
        ),
        titleMedium: baseTextTheme.titleMedium?.copyWith(
          fontWeight: FontWeight.w600,
        ),
        headlineSmall: baseTextTheme.headlineSmall?.copyWith(
          fontWeight: FontWeight.w600,
        ),
      ),
      cardTheme: CardThemeData(
        color: isDark ? AppDesignTokens.darkSidebar : Colors.white,
        elevation: 0,
        margin: EdgeInsets.zero,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(AppDesignTokens.panelRadius),
          side: BorderSide(color: border),
        ),
      ),
      dividerTheme: DividerThemeData(color: border, thickness: 1, space: 1),
      inputDecorationTheme: InputDecorationTheme(
        filled: true,
        fillColor: input,
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(AppDesignTokens.inputRadius),
          borderSide: BorderSide(color: border),
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(AppDesignTokens.inputRadius),
          borderSide: BorderSide(color: border),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(AppDesignTokens.inputRadius),
          borderSide: BorderSide(color: scheme.primary, width: 1.5),
        ),
        contentPadding: const EdgeInsets.symmetric(
          horizontal: 16,
          vertical: 14,
        ),
      ),
      navigationBarTheme: NavigationBarThemeData(
        height: 68,
        backgroundColor: sidebar,
        indicatorColor: scheme.primaryContainer,
        labelTextStyle: WidgetStateProperty.resolveWith(
          (states) => TextStyle(
            fontSize: 12,
            fontWeight: states.contains(WidgetState.selected)
                ? FontWeight.w600
                : FontWeight.w400,
          ),
        ),
      ),
      navigationRailTheme: NavigationRailThemeData(
        backgroundColor: sidebar,
        indicatorColor: scheme.primaryContainer,
        selectedIconTheme: IconThemeData(color: scheme.onPrimaryContainer),
        selectedLabelTextStyle: TextStyle(
          color: scheme.primary,
          fontWeight: FontWeight.w600,
        ),
      ),
      appBarTheme: AppBarTheme(
        elevation: 0,
        scrolledUnderElevation: 0,
        backgroundColor: scheme.surface,
        surfaceTintColor: Colors.transparent,
        titleTextStyle: baseTextTheme.titleLarge?.copyWith(
          fontWeight: FontWeight.w600,
          color: scheme.onSurface,
        ),
      ),
      chipTheme: ChipThemeData(
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(18),
          side: BorderSide(color: border),
        ),
        side: BorderSide(color: border),
        labelStyle: TextStyle(
          color: isDark
              ? AppDesignTokens.darkSecondaryText
              : AppDesignTokens.lightSecondaryText,
          fontWeight: FontWeight.w500,
        ),
      ),
      filledButtonTheme: FilledButtonThemeData(
        style: FilledButton.styleFrom(
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(AppDesignTokens.controlRadius),
          ),
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
        ),
      ),
      outlinedButtonTheme: OutlinedButtonThemeData(
        style: OutlinedButton.styleFrom(
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(AppDesignTokens.controlRadius),
          ),
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
        ),
      ),
    );
  }
}
