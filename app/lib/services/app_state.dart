import 'package:flutter/foundation.dart';

import 'subsonic_client.dart';

/// The music data layer. It no longer holds a Navidrome connection of its own —
/// the backend does. This just binds a [SubsonicClient] to the active account's
/// backend URL + token (driven by [AutomationState]); all library data, audio,
/// and cover art is proxied through that one backend.
class AppState extends ChangeNotifier {
  SubsonicClient? _client;
  bool _navidromeReady = false;

  SubsonicClient? get client => _client;

  /// True once we have a backend client. (Whether Navidrome itself is wired up
  /// on the backend is tracked separately by [navidromeReady].)
  bool get isConnected => _client != null;

  /// True when the backend reports a configured Navidrome connector, i.e. the
  /// library endpoints will actually return data.
  bool get navidromeReady => _navidromeReady;

  /// Bind (or clear) the backend music client for the active account. Called by
  /// [AutomationState] whenever the active account changes.
  void bind(String? base, String? token) {
    _client?.dispose();
    if (base == null || token == null) {
      _client = null;
      _navidromeReady = false;
      notifyListeners();
      return;
    }
    _client = SubsonicClient(base, token);
    _navidromeReady = false;
    notifyListeners();
    // Confirm Navidrome is configured, in the background.
    refreshConnector();
  }

  /// Re-check whether the backend has a working Navidrome connector.
  Future<void> refreshConnector() async {
    final c = _client;
    if (c == null) return;
    var ready = false;
    try {
      await c.ping();
      ready = true;
    } catch (_) {
      ready = false;
    }
    if (ready != _navidromeReady) {
      _navidromeReady = ready;
      notifyListeners();
    }
  }
}

/// Single app-wide instance.
final appState = AppState();
