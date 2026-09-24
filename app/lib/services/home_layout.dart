import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:solar_icons/solar_icons.dart';

/// The kinds of block the Home page can be built from.
///
/// Each value is one *module*: a self-contained row or banner that Home knows
/// how to render. The page is not a hard-coded sequence of these — it's
/// whatever list of [HomeModule]s the user has arranged, so a module can be
/// removed, reordered, or placed more than once.
enum HomeModuleType {
  greeting(
    'Greeting',
    'The time-of-day hello at the top of the page.',
    SolarIconsOutline.sun,
  ),
  spotlight(
    'Spotlight banner',
    'A large rotating banner of featured tracks.',
    SolarIconsOutline.gallery,
  ),
  quickPicks(
    'Quick picks',
    'A compact grid of tracks to start from.',
    SolarIconsOutline.widget,
  ),
  mixes(
    'Your mixes',
    'The daily and weekly generated mixes.',
    SolarIconsOutline.musicLibrary2,
  ),
  continueListening(
    'Continue listening',
    'Part-finished audiobooks, with progress.',
    SolarIconsOutline.headphonesRound,
  ),
  albumsForYou(
    'Albums for you',
    'Album recommendations from your listening.',
    SolarIconsOutline.vinylRecord,
  ),
  moodRows(
    'Mood rows',
    'Genre-led rows mixing mixes, playlists and albums.',
    SolarIconsOutline.magicStick,
  ),
  forgottenFaves(
    'Forgotten faves',
    'Tracks you liked and stopped playing.',
    SolarIconsOutline.clockCircle,
  ),
  newReleases(
    'New releases',
    'Recent releases from artists you follow.',
    SolarIconsOutline.stars,
  ),
  jumpBackIn(
    'Jump back in',
    'Albums you were recently in the middle of.',
    SolarIconsOutline.history,
  ),
  artists(
    'Artists',
    'Round artist portraits.',
    SolarIconsOutline.usersGroupRounded,
  ),
  playlists(
    'Your playlists',
    'Your own playlists as cover cards.',
    SolarIconsOutline.playlist,
  ),
  custom(
    'Custom block',
    'Your own: pick a shape, a name, and what goes in it.',
    SolarIconsOutline.tuning_4,
  );

  const HomeModuleType(this.label, this.blurb, this.icon);
  final String label;
  final String blurb;
  final IconData icon;

  /// Whether more than one of these on a page makes sense. A second spotlight
  /// showing different featured tracks is useful; two greetings is not.
  bool get repeatable => switch (this) {
    HomeModuleType.greeting => false,
    HomeModuleType.spotlight => true,
    _ => true,
  };
}

/// The shape a custom module is drawn in.
///
/// Deliberately independent of what's *in* it: any source can be shown as any
/// of these, which is the whole point of building your own block rather than
/// picking a fixed one.
enum HomeModuleLayout {
  row('Row', 'Square cards, scrolling sideways.', SolarIconsOutline.gallery),
  grid('Grid', 'A two-column block.', SolarIconsOutline.widget),
  list('List', 'Full-width rows, one under another.', SolarIconsOutline.list),
  banner(
    'Banner',
    'One large panel at a time.',
    SolarIconsOutline.sliderHorizontal,
  );

  const HomeModuleLayout(this.label, this.blurb, this.icon);
  final String label;
  final String blurb;
  final IconData icon;
}

/// Where a custom module gets its contents.
///
/// Every one of these is already in the home payload, so a custom block costs
/// nothing extra to fill — it's a different view of data the page has fetched.
enum HomeModuleSource {
  albumsForYou('Albums for you', SolarIconsOutline.vinylRecord),
  jumpBackIn('Recently played albums', SolarIconsOutline.history),
  mixes('Your mixes', SolarIconsOutline.musicLibrary2),
  playlists('Your playlists', SolarIconsOutline.playlist),
  quickPicks('Quick picks', SolarIconsOutline.widget),
  forgottenFaves('Forgotten faves', SolarIconsOutline.clockCircle),
  featured('Featured tracks', SolarIconsOutline.stars),
  newReleases('New releases', SolarIconsOutline.rocket),
  artists('Artists', SolarIconsOutline.usersGroupRounded);

  const HomeModuleSource(this.label, this.icon);
  final String label;
  final IconData icon;
}

/// One placed instance of a module.
///
/// [uid] distinguishes two instances of the same type, so the layout editor can
/// reorder and remove them independently.
class HomeModule {
  final String uid;
  final HomeModuleType type;
  bool enabled;

  /// Set only on [HomeModuleType.custom] blocks: the heading the user typed,
  /// the shape they chose, and what they pointed it at. Null everywhere else,
  /// because a built-in module's title and contents are its identity.
  String? name;
  HomeModuleLayout? layout;
  HomeModuleSource? source;

  HomeModule({
    required this.uid,
    required this.type,
    this.enabled = true,
    this.name,
    this.layout,
    this.source,
  });

  /// What to show as this module's heading.
  String get title => type == HomeModuleType.custom
      ? (name?.trim().isNotEmpty == true ? name!.trim() : 'Untitled block')
      : type.label;

  /// The line under the heading in the layout editor. A custom block describes
  /// itself by what it is rather than by a fixed blurb.
  String get subtitle => type == HomeModuleType.custom
      ? '${layout?.label ?? 'Row'} · ${source?.label ?? 'Nothing yet'}'
      : type.blurb;

  Map<String, dynamic> toJson() => {
    'uid': uid,
    'type': type.name,
    'enabled': enabled,
    if (name != null) 'name': name,
    if (layout != null) 'layout': layout!.name,
    if (source != null) 'source': source!.name,
  };

  static T? _enum<T extends Enum>(List<T> values, Object? name) {
    for (final v in values) {
      if (v.name == name) return v;
    }
    return null;
  }

  static HomeModule? fromJson(Map<String, dynamic> j) {
    final type = _enum(HomeModuleType.values, j['type']?.toString());
    // A module removed from a newer build: drop it rather than fail the load.
    if (type == null) return null;
    final module = HomeModule(
      uid: j['uid']?.toString() ?? '${type.name}-0',
      type: type,
      enabled: j['enabled'] != false,
      name: j['name']?.toString(),
      layout: _enum(HomeModuleLayout.values, j['layout']?.toString()),
      source: _enum(HomeModuleSource.values, j['source']?.toString()),
    );
    // A custom block with no shape or source can't be drawn; it would be an
    // invisible row the user couldn't diagnose, so it doesn't load.
    if (type == HomeModuleType.custom &&
        (module.layout == null || module.source == null)) {
      return null;
    }
    return module;
  }
}

/// The user's Home page arrangement.
///
/// Persisted as an ordered list, so the page is data rather than markup — Home
/// walks this and renders whatever it finds.
class HomeLayoutState extends ChangeNotifier {
  static const _kLayout = 'home_layout_v1';

  List<HomeModule> _modules = _defaults();
  int _seq = 0;

  List<HomeModule> get modules => List.unmodifiable(_modules);

  /// Just the modules Home should actually draw, in order.
  List<HomeModule> get visible =>
      _modules.where((m) => m.enabled).toList(growable: false);

  /// The shipped arrangement — the order the page had before any of this was
  /// configurable.
  static List<HomeModule> _defaults() => [
    for (final t in [
      HomeModuleType.greeting,
      HomeModuleType.spotlight,
      HomeModuleType.quickPicks,
      HomeModuleType.mixes,
      HomeModuleType.continueListening,
      HomeModuleType.albumsForYou,
      HomeModuleType.moodRows,
      HomeModuleType.forgottenFaves,
      HomeModuleType.newReleases,
      HomeModuleType.jumpBackIn,
      HomeModuleType.artists,
      HomeModuleType.playlists,
    ])
      HomeModule(uid: '${t.name}-0', type: t),
  ];

  Future<void> load() async {
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getString(_kLayout);
    if (raw != null) {
      try {
        final list = (jsonDecode(raw) as List)
            .map((e) => HomeModule.fromJson(e as Map<String, dynamic>))
            .whereType<HomeModule>()
            .toList();
        if (list.isNotEmpty) _modules = list;
      } catch (_) {
        // Corrupt layout: fall back to the shipped one rather than an empty page.
      }
    }
    _appendNewBuiltIns();
    notifyListeners();
  }

  /// Modules added in a newer build aren't in a saved layout. Append them
  /// disabled, so an upgrade never silently changes a page the user arranged
  /// but the new block is still there to switch on.
  ///
  /// Custom blocks are skipped: there is no such thing as "the" custom module
  /// to add, only the ones the user built.
  void _appendNewBuiltIns() {
    for (final t in HomeModuleType.values) {
      if (t == HomeModuleType.custom) continue;
      if (!_modules.any((m) => m.type == t)) {
        _modules.add(HomeModule(uid: _uid(t), type: t, enabled: false));
      }
    }
  }

  String _uid(HomeModuleType t) => '${t.name}-${_seq++}-${DateTime.now().microsecondsSinceEpoch}';

  Future<void> _persist() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(
      _kLayout,
      jsonEncode(_modules.map((m) => m.toJson()).toList()),
    );
  }

  Future<void> _commit() async {
    notifyListeners();
    await _persist();
  }

  Future<void> setEnabled(String uid, bool enabled) async {
    for (final m in _modules) {
      if (m.uid == uid) m.enabled = enabled;
    }
    await _commit();
  }

  Future<void> move(int from, int to) async {
    if (from < 0 || from >= _modules.length) return;
    final m = _modules.removeAt(from);
    _modules.insert(to.clamp(0, _modules.length), m);
    await _commit();
  }

  /// Place another instance of [type] at the end of the page.
  Future<void> add(HomeModuleType type) async {
    _modules.add(HomeModule(uid: _uid(type), type: type));
    await _commit();
  }

  /// Place a block the user designed at the end of the page.
  Future<void> addCustom({
    required String name,
    required HomeModuleLayout layout,
    required HomeModuleSource source,
  }) async {
    _modules.add(
      HomeModule(
        uid: _uid(HomeModuleType.custom),
        type: HomeModuleType.custom,
        name: name,
        layout: layout,
        source: source,
      ),
    );
    await _commit();
  }

  /// Rewrite a custom block in place, keeping its position on the page.
  Future<void> editCustom(
    String uid, {
    required String name,
    required HomeModuleLayout layout,
    required HomeModuleSource source,
  }) async {
    for (final m in _modules) {
      if (m.uid != uid || m.type != HomeModuleType.custom) continue;
      m.name = name;
      m.layout = layout;
      m.source = source;
    }
    await _commit();
  }

  /// Add a second (or third) copy of an existing module, right below it.
  Future<void> duplicate(String uid) async {
    final i = _modules.indexWhere((m) => m.uid == uid);
    if (i < 0 || !_modules[i].type.repeatable) return;
    final m = _modules[i];
    _modules.insert(
      i + 1,
      HomeModule(
        uid: _uid(m.type),
        type: m.type,
        name: m.name,
        layout: m.layout,
        source: m.source,
      ),
    );
    await _commit();
  }

  Future<void> remove(String uid) async {
    _modules.removeWhere((m) => m.uid == uid);
    await _commit();
  }

  Future<void> reset() async {
    _modules = _defaults();
    await _commit();
  }

  /// Replace the arrangement wholesale, from a template.
  Future<void> importModules(List<dynamic> raw) async {
    final list = raw
        .whereType<Map>()
        .map((e) => HomeModule.fromJson(e.cast<String, dynamic>()))
        .whereType<HomeModule>()
        .toList();
    if (list.isEmpty) return;
    _modules = list;
    // A template written against an older build won't mention newer modules;
    // append them switched off rather than losing access to them.
    _appendNewBuiltIns();
    await _commit();
  }

  /// How many placed instances of [type] there are — the layout editor shows
  /// this so a duplicated module is distinguishable.
  int countOf(HomeModuleType type) =>
      _modules.where((m) => m.type == type).length;

  /// Which copy this is, among instances of the same type (0-based). Home uses
  /// it to give a second spotlight different content from the first.
  int instanceIndex(HomeModule module) {
    var n = 0;
    for (final m in _modules) {
      if (m.uid == module.uid) return n;
      if (m.type == module.type) n++;
    }
    return 0;
  }
}

/// Single app-wide instance.
final homeLayout = HomeLayoutState();
