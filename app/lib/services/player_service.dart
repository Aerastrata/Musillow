import 'dart:async';
import 'dart:convert';
import 'dart:math';

import 'package:flutter/foundation.dart';
import 'package:just_audio/just_audio.dart';
import 'package:just_audio_background/just_audio_background.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../models/track.dart';
import 'automation_state.dart';
import 'settings_state.dart';
import 'subsonic_client.dart';

/// How the queue behaves when it reaches the end / repeats.
enum RepeatMode { off, all, one }

/// Hook for reporting playback position back to a server (e.g. Audiobookshelf
/// progress sync).
abstract class PlaybackReporter {
  /// Called periodically while playing, on pause, and on completion. [index] is
  /// the current queue index; [finished] is true when the queue has ended.
  void report(int index, Duration position, {required bool finished});
}

/// Owns the single audio player + the current play queue.
///
/// The whole queue is handed to ExoPlayer as a **native playlist**
/// ([ConcatenatingAudioSource]). This is deliberate: the previous design
/// advanced tracks in Dart (listen for "completed", then call `setAudioSource`
/// for the next track), which needed the Flutter isolate + a fresh network
/// request at every song boundary. When the screen is off, Android suspends the
/// Dart isolate under Doze, so that boundary work never ran — playback stalled
/// with a buffering spinner until the screen came back on. Letting ExoPlayer own
/// the queue means auto-advance, repeat, and error recovery all happen natively
/// inside the foreground service, which keeps running with the screen off.
class PlayerService extends ChangeNotifier {
  final AudioPlayer _player = AudioPlayer(
    // Keep a healthy rolling buffer so a brief network dip doesn't drain it, and
    // start with a real pre-roll (a too-early start on a cold pipeline made
    // ExoPlayer mis-detect the stream and crash on the first track).
    audioLoadConfiguration: const AudioLoadConfiguration(
      androidLoadControl: AndroidLoadControl(
        minBufferDuration: Duration(seconds: 20),
        maxBufferDuration: Duration(seconds: 50),
        bufferForPlaybackDuration: Duration(milliseconds: 2500),
        bufferForPlaybackAfterRebufferDuration: Duration(seconds: 5),
      ),
      darwinLoadControl: DarwinLoadControl(
        preferredForwardBufferDuration: Duration(seconds: 30),
      ),
    ),
  );

  ConcatenatingAudioSource? _source; // native playlist backing [_queue]
  List<Track> _queue = const [];
  // The queue's pristine, pre-shuffle order. Turning shuffle off restores it.
  List<Track> _original = const [];
  int _index = 0;
  Track? _lastTrack; // to detect real track changes vs. index shuffles
  bool _manualNav = false; // set by next/prev/jump so we don't log a "complete"

  SubsonicClient? _client;

  // Playback modes.
  bool _shuffle = false;
  RepeatMode _repeat = RepeatMode.off;
  final Random _rand = Random();

  // Per-track flags. `_liked` is mirrored to the server (star/unstar).
  final Set<String> _liked = {};
  final Set<String> _saved = {};
  final Set<String> _downloaded = {};

  // Periodic progress/persistence tick while playing.
  Timer? _keepAlive;
  PlaybackReporter? _reporter;

  // Where the current queue came from (playlist / album / mix name).
  String? _contextLabel;
  String? get contextLabel => _contextLabel;

  static const _kSessionPrefix = 'last_session';

  /// Namespace for the persisted resume-session. Each account gets its own, so
  /// switching accounts never resurrects another account's queue — the saved
  /// track URLs carry that account's token baked in.
  String _accountScope = '';
  String get _kLastSession =>
      _accountScope.isEmpty ? _kSessionPrefix : '${_kSessionPrefix}_$_accountScope';

  Track? get current =>
      (_index >= 0 && _index < _queue.length) ? _queue[_index] : null;

  bool get isPlaying => _player.playing;
  bool get hasNext => _player.hasNext;
  bool get hasPrevious => _player.hasPrevious;

  List<Track> get queue => _queue;
  int get index => _index;

  bool get shuffle => _shuffle;
  RepeatMode get repeat => _repeat;

  bool isLiked(Track t) => _liked.contains(t.id);
  bool isSaved(Track t) => _saved.contains(t.id);
  bool isDownloaded(Track t) => _downloaded.contains(t.id);

  Stream<Duration> get positionStream => _player.positionStream;
  Stream<Duration?> get durationStream => _player.durationStream;
  Duration? get duration => _player.duration;

  PlayerService() {
    // Native auto-advance: ExoPlayer moves to the next item itself, so the only
    // Dart-side work is keeping [_index] in sync and emitting taste signals.
    _player.currentIndexStream.listen((i) {
      if (i == null || _queue.isEmpty) return;
      _index = i.clamp(0, _queue.length - 1);
      final cur = current;
      if (!identical(cur, _lastTrack)) {
        final prev = _lastTrack;
        _lastTrack = cur;
        syncNotificationActions();
        final wasManual = _manualNav;
        _manualNav = false;
        // A natural advance (not a manual skip) means the previous track played
        // through — a strong positive signal.
        if (prev != null && !wasManual) _signal('play_complete', prev);
        if (cur != null) _signal('play', cur);
        unawaited(_persist());
      }
      notifyListeners();
    });

    _player.playerStateStream.listen((_) {
      _syncKeepAlive();
      if (!_player.playing) {
        _report(finished: false);
        unawaited(_persist());
      }
      notifyListeners();
    });

    // Only fires when the *whole* queue ends (no loop) — individual track
    // transitions are handled natively above.
    _player.processingStateStream.listen((state) {
      if (state == ProcessingState.completed) {
        _report(finished: true);
        unawaited(_clearPersisted());
        notifyListeners();
      }
    });

    // ExoPlayer recovers from transient network errors itself; just log.
    _player.playbackEventStream.listen(
      (_) {},
      onError: (Object e, StackTrace st) => debugPrint('Playback error: $e'),
    );
  }

  // --- Preferences -------------------------------------------------------

  /// Push the user's playback preferences (speed, silence trimming) at the
  /// player. Called once at startup, again whenever a queue is loaded, and by
  /// the settings screen the moment either changes.
  Future<void> applyAudioSettings() async {
    try {
      await _player.setSpeed(settingsState.playbackSpeed);
      await _player.setSkipSilenceEnabled(settingsState.skipSilence);
    } catch (e) {
      debugPrint('audio settings failed: $e');
    }
  }

  // --- Building the native playlist -------------------------------------

  LoopMode _loopFor(RepeatMode r) => switch (r) {
    RepeatMode.one => LoopMode.one,
    RepeatMode.all => LoopMode.all,
    RepeatMode.off => LoopMode.off,
  };

  /// A native audio source for [t], tagged so the lock-screen/notification and
  /// the background service can show it.
  AudioSource _sourceFor(Track t) {
    final uri = t.streamUrl != null
        ? Uri.parse(t.streamUrl!)
        : _client!.streamUrl(t.id);
    return AudioSource.uri(
      uri,
      tag: MediaItem(
        id: t.id,
        title: t.title,
        artist: t.artist,
        album: t.album,
        artUri: t.coverArtUrl != null ? Uri.tryParse(t.coverArtUrl!) : null,
      ),
    );
  }

  /// (Re)builds the native playlist from [_queue] and loads it at [_index].
  Future<void> _loadPlaylist({
    Duration? initialPosition,
    bool autoplay = true,
  }) async {
    _lastTrack = current;
    _source = ConcatenatingAudioSource(
      children: _queue.map(_sourceFor).toList(),
    );
    notifyListeners(); // update title/art immediately
    try {
      await _player.setLoopMode(_loopFor(_repeat));
      await _player.setAudioSource(
        _source!,
        initialIndex: _index,
        initialPosition: initialPosition ?? Duration.zero,
      );
      // A fresh source resets speed/skip-silence, so re-assert them here.
      await applyAudioSettings();
      if (autoplay) {
        await _player.play();
        _signal('play', current);
      }
    } catch (e) {
      debugPrint('setAudioSource failed: $e');
    }
    unawaited(_persist());
    notifyListeners();
  }

  /// Plays [tracks] as a queue, starting at [startIndex].
  Future<void> playQueue(
    List<Track> tracks,
    int startIndex, {
    SubsonicClient? client,
    PlaybackReporter? reporter,
    Duration? initialPosition,
    String? contextLabel,
  }) async {
    if (tracks.isEmpty) return;
    _contextLabel = contextLabel;
    _queue = List.of(tracks);
    _original = List.of(tracks);
    _index = startIndex.clamp(0, tracks.length - 1);
    _client = client;
    _reporter = reporter;
    if (_shuffle && _queue.length > 1) _shuffleQueue();
    await _loadPlaylist(initialPosition: initialPosition, autoplay: true);
  }

  // --- Transport --------------------------------------------------------

  Future<void> toggle() => _player.playing ? _player.pause() : _player.play();

  Future<void> next() async {
    if (!_player.hasNext) return;
    final d = _player.duration;
    if (d != null &&
        d.inMilliseconds > 0 &&
        _player.position.inMilliseconds < d.inMilliseconds * 0.25) {
      _signal('skip', current); // early skip — negative signal
    }
    _manualNav = true;
    await _player.seekToNext();
  }

  Future<void> previous() async {
    if (_player.position > const Duration(seconds: 4)) {
      await _player.seek(Duration.zero);
    } else {
      _manualNav = true;
      await _player.seekToPrevious();
    }
  }

  /// Jump directly to a queue position (used by the Up Next list).
  Future<void> jumpTo(int i) async {
    if (i < 0 || i >= _queue.length) return;
    _manualNav = true;
    await _player.seek(Duration.zero, index: i);
    await _player.play();
  }

  Future<void> seek(Duration position) => _player.seek(position);

  // --- Playback modes ---------------------------------------------------

  /// Toggles shuffle by reordering the queue (current track stays playing) and
  /// rebuilding the native playlist from where it is now.
  /// Hand the media notification's Like and Shuffle buttons to this player.
  ///
  /// The forked just_audio_background draws those two actions but deliberately
  /// knows nothing about what they mean — starring and queue order are ours.
  void bindNotificationActions() {
    JustAudioBackground.onLike = () async {
      final t = current;
      if (t != null) await toggleLike(t);
    };
    JustAudioBackground.onShuffle = toggleShuffle;
    syncNotificationActions();
  }

  /// Push like/shuffle state out so the notification's icons match the app.
  void syncNotificationActions() {
    final t = current;
    JustAudioBackground.liked = t != null && isLiked(t);
    JustAudioBackground.shuffleEnabled = _shuffle;
    JustAudioBackground.refreshControls();
  }

  Future<void> toggleShuffle() async {
    _shuffle = !_shuffle;
    if (_queue.length > 1) {
      final pos = _player.position;
      _shuffle ? _shuffleQueue() : _restoreOrder();
      await _loadPlaylist(initialPosition: pos, autoplay: _player.playing);
    }
    syncNotificationActions();
    notifyListeners();
  }

  void _shuffleQueue() {
    final playing = current;
    final rest = List<Track>.of(_queue)..removeAt(_index);
    rest.shuffle(_rand);
    _queue = [?playing, ...rest];
    _index = 0;
  }

  void _restoreOrder() {
    final playing = current;
    _queue = List.of(_original);
    final at = playing == null
        ? -1
        : _queue.indexWhere((t) => identical(t, playing));
    _index = at < 0 ? 0 : at;
  }

  /// Removes queue position [i] from both the list and the native playlist.
  /// ExoPlayer keeps playing and adjusts its current index itself.
  Future<void> removeFromQueue(int i) async {
    if (i < 0 || i >= _queue.length) return;
    final removed = _queue[i];
    _queue = List<Track>.of(_queue)..removeAt(i);
    _original = List<Track>.of(_original)
      ..removeWhere((t) => identical(t, removed));
    if (_queue.isEmpty) {
      await stop();
      return;
    }
    await _source?.removeAt(i);
    _syncIndexToPlayer(fallback: i < _index ? _index - 1 : _index);
    notifyListeners();
  }

  /// Reorders the queue and the native playlist in place.
  Future<void> moveInQueue(int from, int to) async {
    if (from < 0 || from >= _queue.length) return;
    if (to < 0 || to >= _queue.length || from == to) return;
    final playing = current;
    final next = List<Track>.of(_queue);
    next.insert(to, next.removeAt(from));
    _queue = next;
    if (!_shuffle) _original = List.of(next);
    await _source?.move(from, to);
    // Re-point _index at whatever is actually playing (title must match audio).
    final byTrack = playing == null
        ? _index
        : _queue.indexWhere((t) => identical(t, playing));
    _syncIndexToPlayer(fallback: byTrack < 0 ? _index : byTrack);
    notifyListeners();
  }

  /// After an in-place source edit, trust the native player's current index
  /// (which mirrors what's actually playing) and keep [_index] in lock-step, so
  /// the UI title can never drift from the audio. Falls back to [fallback] when
  /// the player hasn't reported an index yet.
  void _syncIndexToPlayer({required int fallback}) {
    final ni = _player.currentIndex;
    _index = (ni != null && ni >= 0 && ni < _queue.length) ? ni : fallback;
    _index = _index.clamp(0, _queue.isEmpty ? 0 : _queue.length - 1);
    _lastTrack = current;
  }

  /// Cycles off → all → one → off (native loop, so it works in the background).
  Future<void> cycleRepeat() async {
    _repeat = RepeatMode.values[(_repeat.index + 1) % RepeatMode.values.length];
    await _player.setLoopMode(_loopFor(_repeat));
    notifyListeners();
  }

  // --- Per-track actions ------------------------------------------------

  Future<void> toggleLike(Track t) async {
    final wasLiked = _liked.contains(t.id);
    wasLiked ? _liked.remove(t.id) : _liked.add(t.id);
    syncNotificationActions();
    notifyListeners();
    if (!wasLiked) _signal('like', t);
    try {
      wasLiked ? await _client?.unstar(t.id) : await _client?.star(t.id);
    } catch (e) {
      debugPrint('star toggle failed: $e');
      wasLiked ? _liked.add(t.id) : _liked.remove(t.id); // revert
      syncNotificationActions();
      notifyListeners();
    }
  }

  void toggleSave(Track t) {
    _saved.contains(t.id) ? _saved.remove(t.id) : _saved.add(t.id);
    notifyListeners();
  }

  void toggleDownload(Track t) {
    _downloaded.contains(t.id)
        ? _downloaded.remove(t.id)
        : _downloaded.add(t.id);
    notifyListeners();
  }

  // --- Signals + reporting ----------------------------------------------

  void _report({required bool finished}) =>
      _reporter?.report(_index, _player.position, finished: finished);

  /// Emit a taste signal — only for Navidrome tracks (ABS carries a streamUrl).
  void _signal(String type, Track? t) {
    if (t == null || t.streamUrl != null) return;
    automationState.client?.sendSignal(type, t.id);
  }

  // --- Resume-last-session ----------------------------------------------

  Future<void> _persist() async {
    if (_queue.isEmpty ||
        _client == null ||
        _queue.any((t) => t.streamUrl != null)) {
      return;
    }
    final data = <String, dynamic>{
      'index': _index,
      'positionMs': _player.position.inMilliseconds,
      'shuffle': _shuffle,
      'repeat': _repeat.index,
      'contextLabel': _contextLabel,
      'tracks': _queue.map((t) => t.toJson()).toList(),
    };
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString(_kLastSession, jsonEncode(data));
    } catch (e) {
      debugPrint('persist failed: $e');
    }
  }

  Future<void> _clearPersisted() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.remove(_kLastSession);
    } catch (_) {}
  }

  /// Restores the last saved music queue, loaded **paused** at the saved
  /// position so the mini-player is ready to resume on the next launch.
  Future<void> restoreLast(SubsonicClient? client) async {
    if (client == null || _queue.isNotEmpty) return;
    // "Resume where I left off" is opt-out: with it off the app opens with no
    // queue at all, though the saved session is kept for when it's turned back on.
    if (!settingsState.resumeOnLaunch) return;
    try {
      final prefs = await SharedPreferences.getInstance();
      final raw = prefs.getString(_kLastSession);
      if (raw == null) return;
      final data = jsonDecode(raw) as Map<String, dynamic>;
      final tracks = (data['tracks'] as List)
          .map((e) => Track.fromJson(e as Map<String, dynamic>))
          .toList();
      if (tracks.isEmpty) return;
      _queue = tracks;
      _original = List.of(tracks);
      _index = ((data['index'] as int?) ?? 0).clamp(0, tracks.length - 1);
      _shuffle = data['shuffle'] as bool? ?? false;
      _repeat = RepeatMode.values[(data['repeat'] as int?) ?? 0];
      _contextLabel = data['contextLabel'] as String?;
      _client = client;
      final posMs = (data['positionMs'] as int?) ?? 0;
      await _loadPlaylist(
        initialPosition: Duration(milliseconds: posMs),
        autoplay: false,
      );
    } catch (e) {
      debugPrint('restore failed: $e');
    }
  }

  Future<void> stop() async {
    unawaited(_clearPersisted());
    await _teardown();
  }

  /// Tear playback down without touching the saved resume point.
  Future<void> _teardown() async {
    _report(finished: false);
    await _player.stop();
    _queue = const [];
    _original = const [];
    _source = null;
    _lastTrack = null;
    _index = 0;
    _reporter = null;
    _contextLabel = null;
    _syncKeepAlive();
    notifyListeners();
  }

  /// Move playback to a different account.
  ///
  /// The outgoing account's queue is saved under its own scope, playback is
  /// torn down, and the incoming account's saved queue is restored in its
  /// place. Nothing — audio, artwork, or the tokens baked into their URLs —
  /// carries across the switch.
  Future<void> switchAccount(String? scope, SubsonicClient? client) async {
    final next = scope ?? '';
    if (next == _accountScope && (_queue.isNotEmpty || client == null)) return;
    await _persist();
    await _teardown();
    _accountScope = next;
    await restoreLast(client);
  }

  /// A light periodic tick while playing: reports progress + saves the resume
  /// point. (Playback continuity no longer depends on this — ExoPlayer owns the
  /// queue — so it's purely bookkeeping.)
  void _syncKeepAlive() {
    if (_player.playing && _client != null) {
      _keepAlive ??= Timer.periodic(const Duration(seconds: 20), (_) {
        _report(finished: false);
        unawaited(_persist());
      });
    } else {
      _keepAlive?.cancel();
      _keepAlive = null;
    }
  }

  @override
  void dispose() {
    _keepAlive?.cancel();
    _player.dispose();
    super.dispose();
  }
}

/// Single app-wide instance.
final playerService = PlayerService();
