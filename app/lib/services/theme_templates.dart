import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'appearance_state.dart';
import 'home_layout.dart';
import 'icon_registry.dart';

/// A saved look: colours, type, shape, every icon override, and the Home
/// arrangement — everything the Studio can change, in one bundle.
///
/// Templates are plain JSON so they can be written to a file and handed to
/// someone else. Custom fonts and icon images are referenced by path, which
/// doesn't travel; [Template.portable] says whether a template depends on
/// local files.
class Template {
  final String name;
  final Map<String, dynamic> data;

  const Template({required this.name, required this.data});

  /// False when the template points at files that only exist on this device,
  /// so the UI can warn before someone shares it expecting it to work.
  bool get portable {
    final icons = data['icons'];
    if (icons is Map && icons.values.any((v) => v is Map && v['image'] != null)) {
      return false;
    }
    return data['customFontFamily'] == null;
  }

  Map<String, dynamic> toJson() => {'name': name, 'data': data};

  static Template fromJson(Map<String, dynamic> j) => Template(
    name: j['name']?.toString() ?? 'Untitled',
    data: (j['data'] as Map?)?.cast<String, dynamic>() ?? const {},
  );
}

/// Saves, applies, and shares Studio looks.
class TemplateStore extends ChangeNotifier {
  static const _kTemplates = 'theme_templates_v1';

  /// The version stamped into exported files, so a future format change can be
  /// detected rather than silently misread.
  static const formatVersion = 1;

  final List<Template> _saved = [];
  List<Template> get saved => List.unmodifiable(_saved);

  Future<void> load() async {
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getString(_kTemplates);
    if (raw == null) return;
    try {
      _saved
        ..clear()
        ..addAll(
          (jsonDecode(raw) as List)
              .map((e) => Template.fromJson(e as Map<String, dynamic>)),
        );
    } catch (_) {
      // Unreadable store: start empty rather than fail the launch.
    }
    notifyListeners();
  }

  Future<void> _persist() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(
      _kTemplates,
      jsonEncode(_saved.map((t) => t.toJson()).toList()),
    );
  }

  /// Everything the Studio currently has applied.
  static Map<String, dynamic> snapshot() {
    final a = appearanceState;
    return {
      'version': formatVersion,
      'accent': a.accent.name,
      'customAccent': a.customAccent?.toARGB32(),
      'font': a.font.name,
      'fontFamily': a.fontFamily,
      // Recorded so a template that relies on a user font can say so.
      'customFontFamily': a.isCustomFamily(a.fontFamily) ? a.fontFamily : null,
      'corners': a.corners.name,
      'shadow': a.shadow.name,
      'likeIcon': a.likeIcon.name,
      'icons': iconRegistry.export(),
      'home': homeLayout.modules.map((m) => m.toJson()).toList(),
    };
  }

  /// Apply a saved look. Anything the template doesn't mention is left alone.
  static Future<void> apply(Map<String, dynamic> data) async {
    final a = appearanceState;

    for (final v in AccentChoice.values) {
      if (v.name == data['accent']) await a.setAccent(v);
    }
    final custom = data['customAccent'];
    if (custom is int) await a.setCustomAccent(Color(custom));

    for (final v in AppFont.values) {
      if (v.name == data['font']) await a.setFont(v);
    }
    // A custom family only applies if that font is actually installed here.
    final family = data['fontFamily']?.toString();
    if (family != null &&
        (a.isCustomFamily(family) ||
            AppFont.values.any((f) => f.family == family))) {
      await a.useFamily(family);
    }

    for (final v in CornerStyle.values) {
      if (v.name == data['corners']) await a.setCorners(v);
    }
    for (final v in ShadowDepth.values) {
      if (v.name == data['shadow']) await a.setShadow(v);
    }
    for (final v in LikeIcon.values) {
      if (v.name == data['likeIcon']) await a.setLikeIcon(v);
    }

    final icons = data['icons'];
    if (icons is Map) await iconRegistry.import(icons.cast<String, dynamic>());

    final home = data['home'];
    if (home is List) await homeLayout.importModules(home);
  }

  /// Back to how the app shipped — the "Musillow" look.
  static Future<void> applyDefault() async {
    await appearanceState.reset();
    await iconRegistry.clearAll();
    await homeLayout.reset();
  }

  Future<void> save(String name) async {
    final template = Template(name: name.trim(), data: snapshot());
    final i = _saved.indexWhere((t) => t.name == template.name);
    if (i >= 0) {
      _saved[i] = template;
    } else {
      _saved.add(template);
    }
    notifyListeners();
    await _persist();
  }

  Future<void> delete(String name) async {
    _saved.removeWhere((t) => t.name == name);
    notifyListeners();
    await _persist();
  }

  /// Pretty JSON, for writing to a file the user can pass around.
  static String encode(Template t) =>
      const JsonEncoder.withIndent('  ').convert(t.toJson());

  /// Read a template file. Returns null when the text isn't one.
  static Template? decode(String text) {
    try {
      final j = jsonDecode(text);
      if (j is! Map<String, dynamic>) return null;
      final data = j['data'];
      if (data is! Map) return null;
      return Template.fromJson(j);
    } catch (_) {
      return null;
    }
  }

  Future<void> add(Template t) async {
    // Imported names can collide; keep both rather than overwrite silently.
    var name = t.name;
    var n = 2;
    while (_saved.any((s) => s.name == name)) {
      name = '${t.name} ($n)';
      n++;
    }
    _saved.add(Template(name: name, data: t.data));
    notifyListeners();
    await _persist();
  }
}

/// Single app-wide instance.
final templateStore = TemplateStore();
