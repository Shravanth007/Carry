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
  // Toasts, in the app's own colours rather than Material's grey. Ink on
  // cream everywhere else, so a toast is cream on ink: the one surface that
  // is deliberately not part of the page, which is what makes it read as
  // temporary. Floating and inset, so it lines up with the 16pt gutter the
  // screens use instead of sitting on the bottom edge of the glass.
  snackBarTheme: SnackBarThemeData(
    behavior: SnackBarBehavior.floating,
    backgroundColor: CarryColors.ink,
    contentTextStyle: const TextStyle(
      color: CarryColors.ground,
      fontSize: 15,
      height: 1.3,
    ),
    // Only readable choice on ink, and it keeps an action from looking like
    // a second sentence.
    actionTextColor: CarryColors.ground,
    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
    insetPadding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
    elevation: 2,
  ),
);

/// The app's main button: dark pill, roomy label. Matches the record button.
///
/// The label starts from the theme's own type rather than a bare `TextStyle`:
/// a style that names no family leaves the engine to pick one, which is a
/// different font from the rest of the screen anywhere the default isn't
/// Roboto.
final carryButton = FilledButton.styleFrom(
  backgroundColor: CarryColors.ink,
  foregroundColor: CarryColors.ground,
  shape: const StadiumBorder(),
  textStyle: carryTheme.textTheme.titleMedium?.copyWith(
    fontWeight: FontWeight.w600,
    fontSize: 17,
  ),
);

/// Wraps a screen in the app theme for `flutter widget-preview start`.
Widget previewApp(Widget child) => MaterialApp(
  theme: carryTheme,
  debugShowCheckedModeBanner: false,
  home: child,
);
