import 'package:flutter/foundation.dart';

import 'abs_client.dart';

/// The audiobook data layer.
///
/// Like [AppState], this holds no server connection of its own — the backend
/// stores the Audiobookshelf connector per account. This just binds an
/// [AudiobookshelfClient] to the active account's backend URL + token (driven
/// by [AutomationState]) and tracks whether that account actually has ABS set
/// up. Nothing is persisted on the device, so switching accounts switches
/// audiobook libraries with no stale credentials left behind.
class AbsState extends ChangeNotifier {
  AudiobookshelfClient? _client;
  String? _libraryId;
  bool _connected = false;

  AudiobookshelfClient? get client => _client;
  String? get libraryId => _libraryId;

  /// True when the active account has a working ABS connector and a library to
  /// browse — i.e. the audiobook sections will return data.
  bool get isConnected => _client != null && _connected && _libraryId != null;

  /// Bind (or clear) the audiobook client for the active account. Called by
  /// [AutomationState] whenever the active account changes.
  void bind(String? base, String? token) {
    _client?.dispose();
    _libraryId = null;
    _connected = false;
    if (base == null || token == null) {
      _client = null;
      notifyListeners();
      return;
    }
    _client = AudiobookshelfClient(base, token);
    notifyListeners();
    // Confirm the connector in the background.
    refresh();
  }

  /// Re-check whether the backend has a working ABS connector for this account.
  Future<void> refresh() async {
    final c = _client;
    if (c == null) return;
    var connected = false;
    String? library;
    try {
      final s = await c.status();
      connected = s.connected;
      library = s.libraryId;
    } catch (_) {
      connected = false;
      library = null;
    }
    if (c != _client) return; // the account switched while we were asking
    if (connected != _connected || library != _libraryId) {
      _connected = connected;
      _libraryId = library;
      notifyListeners();
    }
  }
}

/// Single app-wide instance.
final absState = AbsState();
