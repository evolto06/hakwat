import 'package:flutter/material.dart';

/// Colors sampled from the mockup screenshots.
abstract final class AppColors {
  static const background = Color(0xFF000000);
  static const card = Color(0xFF192221);
  static const bar = Color(0xFF161F1E);
  static const accent = Color(0xFF53D9E5);
  static const navPill = Color(0xFF324B4F);
  static const textPrimary = Color(0xFFE7F0EF);
  static const textSecondary = Color(0xFFCBD0D3);
  static const onAccent = Color(0xFF00363B);
  static const danger = Color(0xFFFFB4AB);
}

/// Keeps the last list rows clear of the Start/Resume button.
const listBottomPadding = 88.0;

ThemeData buildTheme() {
  const scheme = ColorScheme.dark(
    primary: AppColors.accent,
    onPrimary: AppColors.onAccent,
    primaryContainer: AppColors.accent,
    onPrimaryContainer: AppColors.onAccent,
    secondary: AppColors.accent,
    onSecondary: AppColors.onAccent,
    secondaryContainer: AppColors.navPill,
    onSecondaryContainer: AppColors.textPrimary,
    surface: AppColors.background,
    onSurface: AppColors.textPrimary,
    onSurfaceVariant: AppColors.textSecondary,
    surfaceContainerLowest: AppColors.background,
    surfaceContainerLow: AppColors.card,
    surfaceContainer: AppColors.card,
    surfaceContainerHigh: AppColors.card,
    surfaceContainerHighest: AppColors.navPill,
    outline: Color(0xFF6F7B7A),
    outlineVariant: AppColors.navPill,
    error: AppColors.danger,
    onError: Color(0xFF690005),
  );

  return ThemeData(
    useMaterial3: true,
    colorScheme: scheme,
    scaffoldBackgroundColor: AppColors.background,
    appBarTheme: AppBarTheme(
      backgroundColor: WidgetStateColor.resolveWith(
        (states) => states.contains(WidgetState.scrolledUnder)
            ? AppColors.bar
            : AppColors.background,
      ),
      foregroundColor: AppColors.textPrimary,
      iconTheme: const IconThemeData(color: AppColors.accent),
      actionsIconTheme: const IconThemeData(color: AppColors.accent),
      surfaceTintColor: Colors.transparent,
      scrolledUnderElevation: 0,
      titleSpacing: 8,
      titleTextStyle: const TextStyle(
        color: AppColors.textPrimary,
        fontSize: 22,
        fontWeight: FontWeight.w400,
      ),
    ),
    navigationBarTheme: NavigationBarThemeData(
      backgroundColor: AppColors.bar,
      indicatorColor: AppColors.navPill,
      surfaceTintColor: Colors.transparent,
      elevation: 0,
      labelTextStyle: WidgetStateProperty.all(
        const TextStyle(
          color: AppColors.textSecondary,
          fontSize: 12,
          fontWeight: FontWeight.w500,
        ),
      ),
      iconTheme: WidgetStateProperty.all(
        const IconThemeData(color: AppColors.textSecondary),
      ),
    ),
    floatingActionButtonTheme: const FloatingActionButtonThemeData(
      backgroundColor: AppColors.accent,
      foregroundColor: AppColors.onAccent,
      elevation: 2,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.all(Radius.circular(18)),
      ),
    ),
    drawerTheme: const DrawerThemeData(
      backgroundColor: AppColors.bar,
      surfaceTintColor: Colors.transparent,
    ),
    dialogTheme: const DialogThemeData(
      backgroundColor: AppColors.card,
      surfaceTintColor: Colors.transparent,
    ),
    bottomSheetTheme: const BottomSheetThemeData(
      backgroundColor: AppColors.bar,
      surfaceTintColor: Colors.transparent,
    ),
    popupMenuTheme: const PopupMenuThemeData(
      color: AppColors.navPill,
      surfaceTintColor: Colors.transparent,
    ),
    snackBarTheme: const SnackBarThemeData(behavior: SnackBarBehavior.floating),
    inputDecorationTheme: const InputDecorationTheme(
      hintStyle: TextStyle(color: Color(0xFF7D8887)),
    ),
  );
}
