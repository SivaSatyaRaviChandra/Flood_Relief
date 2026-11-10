/// FloodRelief Material 3 theme.
///
/// A single source of theme decisions: deep water-blue seed, high contrast
/// for outdoor use, and consistent danger/success signalling.
library;

import 'package:flutter/material.dart';

/// The app's canonical colour seed (deep water blue).
const Color kSeedColor = Color(0xFF075E8C);

ThemeData buildFloodReliefTheme(Brightness brightness) {
  final scheme = ColorScheme.fromSeed(
    seedColor: kSeedColor,
    brightness: brightness,
  );
  return ThemeData(
    useMaterial3: true,
    colorScheme: scheme,
    scaffoldBackgroundColor:
        brightness == Brightness.dark ? scheme.surface : const Color(0xFFF4F7FA),
    appBarTheme: AppBarTheme(
      backgroundColor: scheme.surface,
      foregroundColor: scheme.onSurface,
      centerTitle: false,
      elevation: 0,
    ),
    cardTheme: CardThemeData(
      elevation: 1,
      margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
    ),
    filledButtonTheme: FilledButtonThemeData(
      style: FilledButton.styleFrom(
        minimumSize: const Size.fromHeight(52),
        textStyle: const TextStyle(fontSize: 17, fontWeight: FontWeight.w600),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(14),
        ),
      ),
    ),
    outlinedButtonTheme: OutlinedButtonThemeData(
      style: OutlinedButton.styleFrom(
        // A finite width minimum: `Size.fromHeight(48)` produces an infinite
        // width constraint that crashes with "BoxConstraints forces an
        // infinite width" whenever an outlined button is laid out in an
        // unbounded context (e.g. a non-flex child of a `Row`).
        minimumSize: const Size(64, 48),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(14),
        ),
      ),
    ),
    chipTheme: const ChipThemeData(
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.all(Radius.circular(8)),
      ),
    ),
    inputDecorationTheme: InputDecorationTheme(
      border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
      contentPadding:
          const EdgeInsets.symmetric(horizontal: 14, vertical: 14),
    ),
    snackBarTheme: SnackBarThemeData(
      behavior: SnackBarBehavior.floating,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
    ),
  );
}

/// Danger red used for the big SEND SOS action regardless of scheme.
const Color kDangerColor = Color(0xFFD32F2F);
const Color kDangerColorDark = Color(0xFFFF6659);