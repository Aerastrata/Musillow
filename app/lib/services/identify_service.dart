import 'dart:async';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:path_provider/path_provider.dart';
import 'package:record/record.dart';

import 'automation_client.dart';
import 'automation_state.dart';

/// How a recognition attempt ended.
enum IdentifyStage { idle, listening, matching, done, failed }

/// Records a few seconds of audio and asks the backend what's playing.
///
/// The fingerprinting happens server-side (the phone only ships the clip), so
/// this needs no API key and nothing to configure — recording permission is the
/// only thing the user is ever asked for.
class IdentifyService extends ChangeNotifier {
  /// Shazam matches comfortably on this much audio; longer just delays the
  /// answer and makes the upload bigger.
  static const clipDuration = Duration(seconds: 7);

  final AudioRecorder _recorder = AudioRecorder();

  IdentifyStage _stage = IdentifyStage.idle;
  String? _error;
  CatalogResult? _match;
  List<CatalogResult> _results = const [];

  IdentifyStage get stage => _stage;
  String? get error => _error;
  CatalogResult? get match => _match;
  List<CatalogResult> get results => _results;
  bool get isBusy =>
      _stage == IdentifyStage.listening || _stage == IdentifyStage.matching;

  void _set(IdentifyStage s, {String? error}) {
    _stage = s;
    _error = error;
    notifyListeners();
  }

  /// Clear the last result so the sheet opens fresh next time.
  void reset() {
    if (isBusy) return;
    _match = null;
    _results = const [];
    _set(IdentifyStage.idle);
  }

  /// Record a clip and identify it. Safe to call again after a failure.
  Future<void> run() async {
    if (isBusy) return;
    _match = null;
    _results = const [];

    final client = automationState.client;
    if (client == null) {
      _set(IdentifyStage.failed, error: 'Sign in to identify songs.');
      return;
    }
    if (!await _recorder.hasPermission()) {
      _set(
        IdentifyStage.failed,
        error: 'Microphone access is needed to identify what\'s playing.',
      );
      return;
    }

    String? path;
    try {
      _set(IdentifyStage.listening);
      path = await _record();
      _set(IdentifyStage.matching);
      final out = await client.identify(path);
      _match = out.match;
      _results = out.results;
      _set(out.match == null ? IdentifyStage.failed : IdentifyStage.done,
          error: out.match == null ? 'Couldn\'t recognise that one.' : null);
    } on AutomationException catch (e) {
      _set(IdentifyStage.failed, error: e.message);
    } catch (_) {
      _set(IdentifyStage.failed, error: 'Couldn\'t listen right now.');
    } finally {
      if (path != null) unawaited(_cleanUp(path));
    }
  }

  /// Capture [clipDuration] of audio to a temp file and return its path.
  Future<String> _record() async {
    final dir = await getTemporaryDirectory();
    final path =
        '${dir.path}/musillow_identify_${DateTime.now().millisecondsSinceEpoch}.m4a';
    await _recorder.start(
      // AAC in an m4a container: small enough to upload quickly, and a format
      // the server's ffmpeg decodes without fuss.
      const RecordConfig(encoder: AudioEncoder.aacLc, numChannels: 1),
      path: path,
    );
    await Future<void>.delayed(clipDuration);
    final out = await _recorder.stop();
    return out ?? path;
  }

  Future<void> _cleanUp(String path) async {
    try {
      final f = File(path);
      if (await f.exists()) await f.delete();
    } catch (_) {
      // A stray temp file isn't worth surfacing.
    }
  }

  @override
  void dispose() {
    _recorder.dispose();
    super.dispose();
  }
}

/// Single app-wide instance.
final identifyService = IdentifyService();
