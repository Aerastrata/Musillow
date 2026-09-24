import 'package:flutter/material.dart';

import 'services/appearance_state.dart';

/// App color palette, derived from the music-discovery-flow mockup.
///
/// The ground colours are fixed — the app is built around cover art sitting on
/// a near-black surface — but [accent] is whatever the user picked under
/// Settings > Appearance, so it is a getter rather than a constant. That is
/// also why expressions using it can't be `const`.
class AppColors {
  static const background = Color(0xFF0E0E12);
  static const surface = Color(0xFF16161F);
  static const surfaceAlt = Color(0xFF1E1E2A);
  static const border = Color(0xFF2A2A3A);

  static const textPrimary = Color(0xFFE8E8F0);
  static const textMuted = Color(0xFF8A8AA0);
  static const textFaint = Color(0xFF5A5A7A);

  /// The user's chosen accent — primary actions, selection, progress.
  static Color get accent => appearanceState.accentColor;

  static const teal = Color(0xFF40D0B0); // automation / discovery
  static const orange = Color(0xFFE08040); // storage / downloads

  /// Destructive actions.
  static const danger = Color(0xFFE0605A);
}

/// Corner radii, scaled by the user's chosen [CornerStyle].
///
/// Widgets ask for the radius the design calls for and this reshapes it, so
/// switching to square corners squares off the whole app — cards, covers,
/// chips, sheets — without any widget knowing the setting exists.
class AppRadius {
  /// Scale [base] by the current corner style.
  static double of(double base) => base * appearanceState.corners.scale;

  static BorderRadius all(double base) => BorderRadius.circular(of(base));

  /// A top-only radius, for bottom sheets and the nav panel.
  static BorderRadius top(double base) =>
      BorderRadius.vertical(top: Radius.circular(of(base)));

  static RoundedRectangleBorder shape(double base) =>
      RoundedRectangleBorder(borderRadius: all(base));
}

/// Drop shadows, scaled by the user's chosen [ShadowDepth].
///
/// The same idea as [AppRadius]: a widget asks for the lift the design calls
/// for and this scales it, so one setting re-lights every raised surface at
/// once. At [ShadowDepth.none] it returns an empty list rather than a
/// zero-blur shadow, so nothing is painted at all.
class AppShadow {
  /// A raised surface — cards, sheets, floating controls.
  ///
  /// [blur] and [dy] are the values at the default depth; [opacity] is how
  /// dark the shadow is there. Deeper settings spread and darken it together,
  /// because a shadow that only grows blurrier reads as blur, not height.
  static List<BoxShadow> lift({
    double blur = 16,
    double dy = 6,
    double opacity = 0.35,
  }) {
    final scale = appearanceState.shadow.scale;
    if (scale <= 0) return const [];
    return [
      BoxShadow(
        color: Colors.black.withValues(
          alpha: (opacity * (0.55 + 0.45 * scale)).clamp(0.0, 1.0),
        ),
        blurRadius: blur * scale,
        offset: Offset(0, dy * scale),
      ),
    ];
  }

  /// A coloured halo under a filled control — the play buttons.
  ///
  /// Separate from [lift] because it reads as light coming off the control
  /// rather than as a shadow cast by it, so it takes the control's own colour
  /// and stays centred rather than growing an offset as it deepens.
  static List<BoxShadow> glow(
    Color color, {
    double blur = 16,
    double dy = 4,
    double opacity = 0.5,
  }) {
    final scale = appearanceState.shadow.scale;
    if (scale <= 0) return const [];
    return [
      BoxShadow(
        color: color.withValues(alpha: (opacity * scale).clamp(0.0, 1.0)),
        blurRadius: blur * scale,
        offset: Offset(0, dy * scale),
      ),
    ];
  }
}

ThemeData buildAppTheme() {
  final accent = AppColors.accent;
  final scheme = ColorScheme.dark(
    surface: AppColors.background,
    primary: accent,
    secondary: AppColors.teal,
    onSurface: AppColors.textPrimary,
  );

  final base = ThemeData(
    useMaterial3: true,
    colorScheme: scheme,
    scaffoldBackgroundColor: AppColors.background,
    fontFamily: appearanceState.fontFamily,
  );

  return base.copyWith(
    appBarTheme: const AppBarTheme(
      backgroundColor: AppColors.background,
      elevation: 0,
      centerTitle: false,
      foregroundColor: AppColors.textPrimary,
    ),
    navigationBarTheme: NavigationBarThemeData(
      backgroundColor: AppColors.surface,
      indicatorColor: accent.withValues(alpha: 0.18),
      labelTextStyle: WidgetStateProperty.all(
        const TextStyle(fontSize: 11, color: AppColors.textMuted),
      ),
    ),
    cardTheme: const CardThemeData(
      color: AppColors.surface,
      surfaceTintColor: Colors.transparent,
    ),
  );
}
