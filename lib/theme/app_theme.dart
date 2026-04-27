import 'package:flutter/material.dart';
import 'tokens.dart';

class DiogelTheme {
  static ThemeData get darkTheme {
    return ThemeData(
      useMaterial3: true,
      brightness: Brightness.dark,
      scaffoldBackgroundColor: DiogelColors.surfaceBackground,
      colorScheme: const ColorScheme.dark(
        primary: DiogelColors.actionPrimary,
        onPrimary: DiogelColors.textInverse,
        secondary: DiogelColors.actionSecondary,
        onSecondary: DiogelColors.textPrimary,
        surface: DiogelColors.surfaceBase,
        onSurface: DiogelColors.textPrimary,
        error: DiogelColors.stateError,
        onError: DiogelColors.textInverse,
        outline: DiogelColors.borderStrong,
        surfaceVariant: DiogelColors.surfaceContainer,
      ),
      textTheme: const TextTheme(
        displayLarge: TextStyle(
          fontSize: 32,
          height: 40 / 32,
          fontWeight: FontWeight.w600,
          color: DiogelColors.textPrimary,
        ),
        displayMedium: TextStyle(
          fontSize: 28,
          height: 36 / 28,
          fontWeight: FontWeight.w600,
          color: DiogelColors.textPrimary,
        ),
        headlineLarge: TextStyle(
          fontSize: 24,
          height: 32 / 24,
          fontWeight: FontWeight.w600,
          color: DiogelColors.textPrimary,
        ),
        headlineMedium: TextStyle(
          fontSize: 20,
          height: 28 / 20,
          fontWeight: FontWeight.w600,
          color: DiogelColors.textPrimary,
        ),
        titleLarge: TextStyle(
          fontSize: 18,
          height: 24 / 18,
          fontWeight: FontWeight.w600,
          color: DiogelColors.textPrimary,
        ),
        titleMedium: TextStyle(
          fontSize: 16,
          height: 22 / 16,
          fontWeight: FontWeight.w600,
          color: DiogelColors.textPrimary,
        ),
        bodyLarge: TextStyle(
          fontSize: 16,
          height: 24 / 16,
          fontWeight: FontWeight.normal,
          color: DiogelColors.textPrimary,
        ),
        bodyMedium: TextStyle(
          fontSize: 14,
          height: 22 / 14,
          fontWeight: FontWeight.normal,
          color: DiogelColors.textPrimary,
        ),
        bodySmall: TextStyle(
          fontSize: 13,
          height: 20 / 13,
          fontWeight: FontWeight.normal,
          color: DiogelColors.textSecondary,
        ),
        labelLarge: TextStyle(
          fontSize: 14,
          height: 20 / 14,
          fontWeight: FontWeight.w500,
          color: DiogelColors.textPrimary,
        ),
        labelMedium: TextStyle(
          fontSize: 12,
          height: 16 / 12,
          fontWeight: FontWeight.w500,
          color: DiogelColors.textSecondary,
        ),
        labelSmall: TextStyle(
          fontSize: 11,
          height: 16 / 11,
          fontWeight: FontWeight.w500,
          color: DiogelColors.textSecondary,
        ),
      ),
      appBarTheme: const AppBarTheme(
        backgroundColor: DiogelColors.surfaceBackground,
        foregroundColor: DiogelColors.textPrimary,
        elevation: 0,
        centerTitle: false,
        titleTextStyle: TextStyle(
          fontSize: 18,
          height: 24 / 18,
          fontWeight: FontWeight.w600,
          color: DiogelColors.textPrimary,
        ),
      ),
      filledButtonTheme: FilledButtonThemeData(
        style: FilledButton.styleFrom(
          backgroundColor: DiogelColors.actionPrimary,
          foregroundColor: DiogelColors.textInverse,
          padding: const EdgeInsets.symmetric(
            vertical: DiogelSpacing.space4,
            horizontal: DiogelSpacing.space6,
          ),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(DiogelRadius.large),
          ),
          textStyle: const TextStyle(
            fontSize: 18,
            height: 24 / 18,
            fontWeight: FontWeight.w600,
          ),
        ),
      ),
      navigationBarTheme: NavigationBarThemeData(
        backgroundColor: DiogelColors.surfaceBase,
        indicatorColor: DiogelColors.actionSecondary,
        labelTextStyle: WidgetStateProperty.resolveWith((states) {
          if (states.contains(WidgetState.selected)) {
            return const TextStyle(
              fontSize: 12,
              fontWeight: FontWeight.w500,
              color: DiogelColors.actionPrimary,
            );
          }
          return const TextStyle(
            fontSize: 12,
            fontWeight: FontWeight.w500,
            color: DiogelColors.textSecondary,
          );
        }),
        iconTheme: WidgetStateProperty.resolveWith((states) {
          if (states.contains(WidgetState.selected)) {
            return const IconThemeData(color: DiogelColors.actionPrimary);
          }
          return const IconThemeData(color: DiogelColors.textSecondary);
        }),
      ),
      cardTheme: CardThemeData(
        color: DiogelColors.surfaceContainer,
        elevation: 1,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(DiogelRadius.medium),
        ),
      ),
      inputDecorationTheme: InputDecorationTheme(
        filled: true,
        fillColor: DiogelColors.surfaceContainer,
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(DiogelRadius.medium),
          borderSide: BorderSide.none,
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(DiogelRadius.medium),
          borderSide: const BorderSide(color: DiogelColors.borderSubtle),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(DiogelRadius.medium),
          borderSide: const BorderSide(color: DiogelColors.stateFocus),
        ),
        errorBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(DiogelRadius.medium),
          borderSide: const BorderSide(color: DiogelColors.stateError),
        ),
        labelStyle: const TextStyle(color: DiogelColors.textSecondary),
        hintStyle: const TextStyle(color: DiogelColors.textTertiary),
      ),
    );
  }
}
