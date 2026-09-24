import 'package:audioplayers/audioplayers.dart';
import 'package:flutter/foundation.dart';

import 'automation_client.dart';
import 'player_service.dart';

/// Plays 30-second catalogue previews on their own audio pipeline. It uses the
/// `audioplayers` package rather than just_audio because just_audio_background
/// permits only a single just_audio instance (the main queue). Starting a
/// preview pauses the main player so the two never overlap.
class PreviewPlayer extends ChangeNotifier {
  final AudioPlayer _player = AudioPlayer();
  String? _currentId; // id of the CatalogResult currently previewing
  bool _playing = false;

  String? get currentId => _currentId;

  PreviewPlayer() {
    _player.onPlayerStateChanged.listen((state) {
      _playing = state == PlayerState.playing;
      if (state == PlayerState.completed) {
        _currentId = null;
        _playing = false;
      }
      notifyListeners();
    });
  }

  bool isCurrent(String id) => _currentId == id && _playing;

  Future<void> toggle(CatalogResult r) async {
    if (r.previewUrl == null) return;
    if (_currentId == r.id && _playing) {
      await _player.pause();
      return;
    }
    // Don't talk over the main queue.
    if (playerService.isPlaying) await playerService.toggle();
    _currentId = r.id;
    notifyListeners();
    try {
      await _player.stop();
      await _player.play(UrlSource(r.previewUrl!));
    } catch (e) {
      debugPrint('preview failed: $e');
      _currentId = null;
      _playing = false;
      notifyListeners();
    }
  }

  Future<void> stop() async {
    _currentId = null;
    _playing = false;
    await _player.stop();
    notifyListeners();
  }

  @override
  void dispose() {
    _player.dispose();
    super.dispose();
  }
}

/// App-wide preview player.
final previewPlayer = PreviewPlayer();
