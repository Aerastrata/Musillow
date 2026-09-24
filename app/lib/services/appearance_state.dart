import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:solar_icons/solar_icons.dart';

/// The app's accent — the colour used for the primary action, the active nav
/// destination, progress, and selection throughout.
enum AccentChoice {
  violet('Violet', Color(0xFF9090FF)),
  green('Green', Color(0xFF4FD07A)),
  teal('Teal', Color(0xFF40D0B0)),
  blue('Blue', Color(0xFF5B9CFF)),
  amber('Amber', Color(0xFFF5A623)),
  orange('Orange', Color(0xFFE08040)),
  pink('Pink', Color(0xFFFF5A7A)),
  lilac('Lilac', Color(0xFFB57BFF));

  const AccentChoice(this.label, this.color);
  final String label;
  final Color color;
}

/// A bundled type family. Every entry here must also be registered under
/// `fonts:` in pubspec.yaml.
enum AppFont {
  nunito('Nunito', 'Nunito', 'Rounded and friendly'),
  openSans('Open Sans', 'Open Sans', 'Neutral and highly legible'),
  robotoSlab('Roboto Slab', 'Roboto Slab', 'Slab serif, editorial'),
  inter('Inter', 'Inter', 'Clean and modern');

  const AppFont(this.label, this.family, this.detail);
  final String label;

  /// The family name as declared in pubspec.yaml.
  final String family;
  final String detail;
}

/// How rounded every card, cover, and control is.
///
/// [scale] multiplies the radius each widget asks for, so one setting reshapes
/// the whole app without any widget hard-coding a number.
enum CornerStyle {
  square('Square', 0.0),
  soft('Soft', 0.45),
  round('Round', 1.0),
  pill('Pill', 1.6);

  const CornerStyle(this.label, this.scale);
  final String label;
  final double scale;
}

/// How much every raised surface lifts off the background.
///
/// [scale] multiplies the blur and offset each shadow asks for, the same way
/// [CornerStyle.scale] multiplies radii, so one setting re-lights the whole app
/// without any widget hard-coding a shadow.
enum ShadowDepth {
  none('None', 0.0),
  flat('Flat', 0.5),
  soft('Soft', 1.0),
  lifted('Lifted', 1.7),
  deep('Deep', 2.6);

  const ShadowDepth(this.label, this.scale);
  final String label;
  final double scale;
}

/// The mark used for "I like this track", on the now-playing screen, the track
/// menus, and the notification.
enum LikeIcon {
  heart('Heart', SolarIconsOutline.heart, SolarIconsBold.heart),
  thumbsUp('Thumbs up', SolarIconsOutline.like, SolarIconsBold.like),
  star('Star', SolarIconsOutline.star, SolarIconsBold.star),
  bookmark('Bookmark', SolarIconsOutline.bookmark, SolarIconsBold.bookmark);

  const LikeIcon(this.label, this.outline, this.filled);
  final String label;
  final IconData outline;
  final IconData filled;
}

/// Everything about how the app looks, in one place.
///
/// Widgets read this at build time through [AppColors] / [AppRadius] in
/// theme.dart rather than importing it directly, so a change here repaints the
/// whole app without any widget knowing a setting exists.
class AppearanceState extends ChangeNotifier {
  static const _kAccent = 'appearance_accent';
  static const _kFont = 'appearance_font';
  static const _kCorners = 'appearance_corners';
  static const _kShadow = 'appearance_shadow';
  static const _kLike = 'appearance_like_icon';
  static const _kCustomAccent = 'appearance_custom_accent';
  static const _kCustomFonts = 'appearance_custom_fonts';
  static const _kActiveFontFamily = 'appearance_active_font_family';

  AccentChoice _accent = AccentChoice.violet;
  AppFont _font = AppFont.nunito;
  CornerStyle _corners = CornerStyle.round;
  ShadowDepth _shadow = ShadowDepth.soft;
  LikeIcon _likeIcon = LikeIcon.heart;

  /// An arbitrary colour picked from the wheel. Takes precedence over
  /// [_accent] when set, so the eight swatches stay as quick presets rather
  /// than a limit.
  Color? _customAccent;

  /// Font families loaded from the user's own .ttf/.otf files, as
  /// {family: file path}. Registered with Flutter at startup.
  final Map<String, String> _customFonts = {};

  /// The family actually in use. Either an [AppFont]'s family or one of
  /// [_customFonts]' keys.
  String? _activeFamily;

  AccentChoice get accent => _accent;
  AppFont get font => _font;
  CornerStyle get corners => _corners;
  ShadowDepth get shadow => _shadow;
  LikeIcon get likeIcon => _likeIcon;
  Color? get customAccent => _customAccent;
  Map<String, String> get customFonts => Map.unmodifiable(_customFonts);

  /// The colour everything accent-tinted actually uses.
  Color get accentColor => _customAccent ?? _accent.color;

  /// The family every bit of text actually uses.
  String get fontFamily => _activeFamily ?? _font.family;

  /// A value that changes whenever anything visual here does.
  ///
  /// The Studio's screen previews are built largely from `const` widgets, which
  /// Flutter reuses wholesale on rebuild rather than calling build on again —
  /// so a preview that reads [AppRadius] or [AppColors] inside one keeps
  /// whatever it was first drawn with. Keying the preview on this replaces its
  /// element instead of updating it, which is what makes a corner, accent or
  /// shadow change actually repaint in there.
  String get stamp =>
      '${accentColor.toARGB32()}|$fontFamily|${_corners.name}|${_shadow.name}'
      '|${_likeIcon.name}';

  /// Whether [family] is one the user supplied rather than one that ships.
  bool isCustomFamily(String family) => _customFonts.containsKey(family);

  Future<void> load() async {
    final prefs = await SharedPreferences.getInstance();
    _accent = _read(prefs, _kAccent, AccentChoice.values, _accent);
    _font = _read(prefs, _kFont, AppFont.values, _font);
    _corners = _read(prefs, _kCorners, CornerStyle.values, _corners);
    _shadow = _read(prefs, _kShadow, ShadowDepth.values, _shadow);
    _likeIcon = _read(prefs, _kLike, LikeIcon.values, _likeIcon);

    final argb = prefs.getInt(_kCustomAccent);
    _customAccent = argb == null ? null : Color(argb);

    // Re-register the user's own fonts before the first frame, so text doesn't
    // fall back to the default and then jump.
    final saved = prefs.getStringList(_kCustomFonts) ?? const [];
    for (final entry in saved) {
      final i = entry.indexOf('|');
      if (i <= 0) continue;
      final family = entry.substring(0, i);
      final path = entry.substring(i + 1);
      if (await _registerFont(family, path)) _customFonts[family] = path;
    }
    final active = prefs.getString(_kActiveFontFamily);
    // Only honour a saved family that still resolves to something loadable.
    if (active != null &&
        (_customFonts.containsKey(active) ||
            AppFont.values.any((f) => f.family == active))) {
      _activeFamily = active;
    }
    notifyListeners();
  }

  /// Load a font file into the engine under [family]. Returns false if the file
  /// is gone or unreadable, so a stale entry is dropped rather than kept.
  static Future<bool> _registerFont(String family, String path) async {
    try {
      final file = File(path);
      if (!await file.exists()) return false;
      final loader = FontLoader(family)
        ..addFont(file.readAsBytes().then((b) => b.buffer.asByteData()));
      await loader.load();
      return true;
    } catch (_) {
      return false;
    }
  }

  /// Enums are stored by name, so reordering or inserting a value later can't
  /// silently reinterpret a saved choice as a different one.
  static T _read<T extends Enum>(
    SharedPreferences prefs,
    String key,
    List<T> values,
    T fallback,
  ) {
    final name = prefs.getString(key);
    if (name == null) return fallback;
    for (final v in values) {
      if (v.name == name) return v;
    }
    return fallback;
  }

  Future<void> _write(String key, Enum value) async =>
      (await SharedPreferences.getInstance()).setString(key, value.name);

  Future<void> setAccent(AccentChoice v) async {
    _accent = v;
    // Choosing a preset clears any wheel colour, so the selection is unambiguous.
    _customAccent = null;
    notifyListeners();
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_kAccent, v.name);
    await prefs.remove(_kCustomAccent);
  }

  Future<void> setFont(AppFont v) async {
    _font = v;
    _activeFamily = v.family;
    notifyListeners();
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_kFont, v.name);
    await prefs.setString(_kActiveFontFamily, v.family);
  }

  /// Adopt a font the user supplied. [path] must already be inside app storage.
  Future<bool> addCustomFont(String family, String path) async {
    if (!await _registerFont(family, path)) return false;
    _customFonts[family] = path;
    _activeFamily = family;
    notifyListeners();
    await _persistFonts();
    return true;
  }

  Future<void> useFamily(String family) async {
    _activeFamily = family;
    notifyListeners();
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_kActiveFontFamily, family);
  }

  Future<void> removeCustomFont(String family) async {
    final path = _customFonts.remove(family);
    if (path != null) {
      try {
        await File(path).delete();
      } catch (_) {}
    }
    // The engine can't unload a family, but nothing will ask for it again.
    if (_activeFamily == family) _activeFamily = _font.family;
    notifyListeners();
    await _persistFonts();
  }

  Future<void> _persistFonts() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setStringList(
      _kCustomFonts,
      [for (final e in _customFonts.entries) '${e.key}|${e.value}'],
    );
    await prefs.setString(_kActiveFontFamily, fontFamily);
  }

  /// Set an exact accent colour (from the wheel). Null returns to the preset.
  ///
  /// [persist] is false while a finger is still moving on the wheel: the app
  /// re-tints on every frame of the drag, but only the colour it lands on is
  /// written to disk, rather than a few hundred of them.
  Future<void> setCustomAccent(Color? c, {bool persist = true}) async {
    _customAccent = c;
    notifyListeners();
    if (!persist) return;
    final prefs = await SharedPreferences.getInstance();
    if (c == null) {
      await prefs.remove(_kCustomAccent);
    } else {
      await prefs.setInt(_kCustomAccent, c.toARGB32());
    }
  }

  Future<void> setCorners(CornerStyle v) async {
    _corners = v;
    notifyListeners();
    await _write(_kCorners, v);
  }

  Future<void> setShadow(ShadowDepth v) async {
    _shadow = v;
    notifyListeners();
    await _write(_kShadow, v);
  }

  Future<void> setLikeIcon(LikeIcon v) async {
    _likeIcon = v;
    notifyListeners();
    await _write(_kLike, v);
  }

  /// Back to the shipped look.
  Future<void> reset() async {
    _accent = AccentChoice.violet;
    _font = AppFont.nunito;
    _corners = CornerStyle.round;
    _shadow = ShadowDepth.soft;
    _likeIcon = LikeIcon.heart;
    _customAccent = null;
    _activeFamily = AppFont.nunito.family;
    notifyListeners();
    final prefs = await SharedPreferences.getInstance();
    await Future.wait([
      prefs.remove(_kAccent),
      prefs.remove(_kFont),
      prefs.remove(_kCorners),
      prefs.remove(_kShadow),
      prefs.remove(_kLike),
      prefs.remove(_kCustomAccent),
      prefs.remove(_kActiveFontFamily),
    ]);
  }
}

/// Single app-wide instance.
final appearanceState = AppearanceState();
