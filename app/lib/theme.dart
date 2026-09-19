import 'package:flutter/material.dart';

abstract final class CarryColors {
  static const ground = Color(0xFFFAF7E8);

  /// Panels and cards sitting on [ground].
  static const surface = Color(0xFFFFFDF5);
  static const ink = Color(0xFF17201B);
  static const muted = Color(0xFF5B645E);
  static const accent = Color(0xFF3D55CC);
  static const error = Color(0xFFB3261E);
}

final carryTheme = ThemeData(
  colorScheme: ColorScheme.fromSeed(
    seedColor: CarryColors.accent,
    primary: CarryColors.accent,
    surface: CarryColors.ground,
    onSurface: CarryColors.ink,
    error: CarryColors.error,
  ),
  scaffoldBackgroundColor: CarryColors.ground,
  appBarTheme: const AppBarTheme(
    backgroundColor: CarryColors.ground,
    foregroundColor: CarryColors.ink,
    scrolledUnderElevation: 0,
  ),
);

/// The app's main button: dark pill, roomy label. Matches the record button.
final carryButton = FilledButton.styleFrom(
  backgroundColor: CarryColors.ink,
  foregroundColor: CarryColors.ground,
  shape: const StadiumBorder(),
  textStyle: const TextStyle(fontWeight: FontWeight.w600, fontSize: 17),
);

/// Wraps a screen in the app theme for `flutter widget-preview start`.
Widget previewApp(Widget child) => MaterialApp(
  theme: carryTheme,
  debugShowCheckedModeBanner: false,
  home: child,
);
