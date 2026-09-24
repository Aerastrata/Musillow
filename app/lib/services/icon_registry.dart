import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../generated/solar_catalog.g.dart';

/// Which of a glyph's two cuts to draw.
enum IconStyle { outline, bold }

/// A named icon position in the app.
///
/// Every icon the user can retheme has a slot. Widgets ask for the slot, not a
/// glyph, so remapping one here changes it everywhere it appears without
/// touching a single call site.
enum IconSlot {
  // Navigation
  navHome('Home tab', 'home', IconStyle.outline, 'Navigation'),
  navHomeActive('Home tab (selected)', 'home', IconStyle.bold, 'Navigation'),
  navExplore('Explore tab', 'compass', IconStyle.outline, 'Navigation'),
  navExploreActive(
    'Explore tab (selected)',
    'compass',
    IconStyle.bold,
    'Navigation',
  ),
  navLibrary('Library tab', 'musicLibrary2', IconStyle.bold, 'Navigation'),
  navLibraryActive(
    'Library tab (selected)',
    'musicLibrary2',
    IconStyle.bold,
    'Navigation',
  ),
  account('Account', 'userCircle', IconStyle.outline, 'Navigation'),

  // Transport
  play('Play', 'play', IconStyle.bold, 'Player'),
  pause('Pause', 'pause', IconStyle.bold, 'Player'),
  next('Next track', 'skipNext', IconStyle.bold, 'Player'),
  previous('Previous track', 'skipPrevious', IconStyle.bold, 'Player'),
  shuffle('Shuffle', 'shuffle', IconStyle.outline, 'Player'),
  repeat('Repeat', 'repeat', IconStyle.outline, 'Player'),
  repeatOne('Repeat one', 'repeatOne', IconStyle.outline, 'Player'),
  like('Like', 'heart', IconStyle.outline, 'Player'),
  likeFilled('Liked', 'heart', IconStyle.bold, 'Player'),
  save('Save to playlist', 'addCircle', IconStyle.outline, 'Player'),
  queue('Queue', 'hamburgerMenu', IconStyle.outline, 'Player'),
  lyrics('Lyrics', 'notes', IconStyle.outline, 'Player'),
  trackInfo('Track info', 'infoCircle', IconStyle.outline, 'Player'),
  more('More actions', 'menuDots', IconStyle.outline, 'Player'),
  collapse('Collapse player', 'altArrowDown', IconStyle.outline, 'Player'),
  miniPlay('Mini player play', 'playCircle', IconStyle.bold, 'Player'),
  miniPause('Mini player pause', 'pauseCircle', IconStyle.bold, 'Player'),
  miniClose('Mini player close', 'closeCircle', IconStyle.outline, 'Player'),

  // Explore
  search('Search', 'magnifier', IconStyle.outline, 'Explore'),
  identify("What's playing", 'microphone', IconStyle.bold, 'Explore'),
  download('Request download', 'downloadMinimalistic', IconStyle.outline, 'Explore'),
  downloadDone('Downloaded', 'checkCircle', IconStyle.bold, 'Explore'),
  retry('Retry', 'refresh', IconStyle.outline, 'Explore'),
  clear('Clear', 'closeCircle', IconStyle.outline, 'Explore'),

  // Library
  libSongs('Songs', 'musicNotes', IconStyle.bold, 'Library'),
  libPlaylists('Playlists', 'playlist', IconStyle.bold, 'Library'),
  libAlbums('Albums', 'vinylRecord', IconStyle.bold, 'Library'),
  libArtists('Artists', 'user', IconStyle.bold, 'Library'),
  libGenres('Genres', 'musicLibrary2', IconStyle.bold, 'Library'),
  libRadio('Radio', 'radio', IconStyle.bold, 'Library'),
  libBooks('Audiobooks', 'headphonesRoundSound', IconStyle.bold, 'Library'),
  libAuthors('Authors', 'pen', IconStyle.bold, 'Library'),

  // Shared
  musicNote('Music note', 'musicNote', IconStyle.bold, 'General'),
  offline('Offline', 'cloudCross', IconStyle.outline, 'General'),
  empty('Nothing here', 'musicLibrary', IconStyle.outline, 'General'),
  warning('Warning', 'dangerTriangle', IconStyle.outline, 'General'),
  delete('Delete', 'trashBinMinimalistic', IconStyle.outline, 'General');

  const IconSlot(this.label, this.defaultGlyph, this.defaultStyle, this.group);

  /// Human name, shown in the icon editor.
  final String label;

  /// The glyph this slot uses when the user hasn't changed it.
  final String defaultGlyph;
  final IconStyle defaultStyle;

  /// Which section of the editor this slot is listed under.
  final String group;
}

/// What a slot currently resolves to: a Solar glyph, or an image file the user
/// supplied.
class IconSpec {
  /// Name from the Solar catalogue; null when [imagePath] is set.
  final String? glyph;
  final IconStyle style;

  /// Absolute path to a user-supplied image, copied into app storage.
  final String? imagePath;

  const IconSpec({this.glyph, this.style = IconStyle.outline, this.imagePath});

  bool get isCustom => imagePath != null;

  IconData? get iconData {
    final g = solarByName[glyph];
    if (g == null) return null;
    return style == IconStyle.bold ? g.bold : g.outline;
  }

  Map<String, dynamic> toJson() => {
    if (glyph != null) 'glyph': glyph,
    'style': style.name,
    if (imagePath != null) 'image': imagePath,
  };

  static IconSpec fromJson(Map<String, dynamic> j) => IconSpec(
    glyph: j['glyph']?.toString(),
    style: j['style'] == 'bold' ? IconStyle.bold : IconStyle.outline,
    imagePath: j['image']?.toString(),
  );
}

/// Holds every slot's current icon, and the user's overrides.
class IconRegistry extends ChangeNotifier {
  static const _kOverrides = 'icon_overrides_v1';

  final Map<IconSlot, IconSpec> _overrides = {};

  /// Slots the user has changed — the editor marks these so they can be reset.
  bool isOverridden(IconSlot slot) => _overrides.containsKey(slot);
  int get overrideCount => _overrides.length;

  /// What [slot] currently draws.
  IconSpec specFor(IconSlot slot) =>
      _overrides[slot] ??
      IconSpec(glyph: slot.defaultGlyph, style: slot.defaultStyle);

  Future<void> load() async {
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getString(_kOverrides);
    if (raw == null) return;
    try {
      final map = jsonDecode(raw) as Map<String, dynamic>;
      _overrides.clear();
      for (final slot in IconSlot.values) {
        final v = map[slot.name];
        if (v is Map<String, dynamic>) {
          final spec = IconSpec.fromJson(v);
          // Drop an override whose custom image has since been deleted, rather
          // than rendering a permanent blank.
          if (spec.isCustom && !File(spec.imagePath!).existsSync()) continue;
          if (!spec.isCustom && spec.iconData == null) continue;
          _overrides[slot] = spec;
        }
      }
    } catch (_) {
      // Unreadable overrides: fall back to the shipped icons.
    }
    notifyListeners();
  }

  Future<void> _persist() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(
      _kOverrides,
      jsonEncode({
        for (final e in _overrides.entries) e.key.name: e.value.toJson(),
      }),
    );
  }

  Future<void> set(IconSlot slot, IconSpec spec) async {
    _overrides[slot] = spec;
    notifyListeners();
    await _persist();
  }

  Future<void> clear(IconSlot slot) async {
    _overrides.remove(slot);
    notifyListeners();
    await _persist();
  }

  Future<void> clearAll() async {
    _overrides.clear();
    notifyListeners();
    await _persist();
  }

  /// Snapshot for saving into a template.
  Map<String, dynamic> export() => {
    for (final e in _overrides.entries) e.key.name: e.value.toJson(),
  };

  /// Restore from a template snapshot.
  Future<void> import(Map<String, dynamic> data) async {
    _overrides.clear();
    for (final slot in IconSlot.values) {
      final v = data[slot.name];
      if (v is Map<String, dynamic>) _overrides[slot] = IconSpec.fromJson(v);
    }
    notifyListeners();
    await _persist();
  }
}

/// Single app-wide instance.
final iconRegistry = IconRegistry();
