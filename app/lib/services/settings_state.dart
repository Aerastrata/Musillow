import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Streaming quality: the ceiling the backend transcodes down to before the
/// audio reaches the phone. [StreamQuality.original] streams the library file
/// untouched — the right default on a LAN or a fast overlay network.
enum StreamQuality {
  original(0, 'Original', 'Untranscoded library file'),
  high(320, 'High', '320 kbps'),
  medium(192, 'Medium', '192 kbps'),
  low(128, 'Data saver', '128 kbps');

  const StreamQuality(this.kbps, this.label, this.detail);

  /// Max bitrate in kbps; 0 means "don't transcode".
  final int kbps;
  final String label;
  final String detail;
}

/// App preferences that aren't tied to an account: playback behaviour, on-disk
/// caching, and presentation.
///
/// These are device settings, so they live in [SharedPreferences] rather than
/// on the backend — switching accounts doesn't reset them. Everything here is
/// wired to something real; nothing is stored just to be displayed.
class SettingsState extends ChangeNotifier {
  static const _kQuality = 'settings_stream_quality';
  static const _kSkipSilence = 'settings_skip_silence';
  static const _kSpeed = 'settings_playback_speed';
  static const _kResume = 'settings_resume_on_launch';
  static const _kImageCacheMb = 'settings_image_cache_mb';
  static const _kTextScale = 'settings_text_scale';
  static const _kReduceMotion = 'settings_reduce_motion';

  StreamQuality _quality = StreamQuality.original;
  bool _skipSilence = false;
  double _playbackSpeed = 1.0;
  bool _resumeOnLaunch = true;
  int _imageCacheMb = 100;
  double _textScale = 1.0;
  bool _reduceMotion = false;

  StreamQuality get quality => _quality;
  bool get skipSilence => _skipSilence;
  double get playbackSpeed => _playbackSpeed;
  bool get resumeOnLaunch => _resumeOnLaunch;
  int get imageCacheMb => _imageCacheMb;
  double get textScale => _textScale;
  bool get reduceMotion => _reduceMotion;

  Future<void> load() async {
    final prefs = await SharedPreferences.getInstance();
    final q = prefs.getInt(_kQuality);
    if (q != null && q >= 0 && q < StreamQuality.values.length) {
      _quality = StreamQuality.values[q];
    }
    _skipSilence = prefs.getBool(_kSkipSilence) ?? _skipSilence;
    _playbackSpeed = prefs.getDouble(_kSpeed) ?? _playbackSpeed;
    _resumeOnLaunch = prefs.getBool(_kResume) ?? _resumeOnLaunch;
    _imageCacheMb = prefs.getInt(_kImageCacheMb) ?? _imageCacheMb;
    _textScale = prefs.getDouble(_kTextScale) ?? _textScale;
    _reduceMotion = prefs.getBool(_kReduceMotion) ?? _reduceMotion;
    _applyImageCache();
    notifyListeners();
  }

  /// Flutter's in-memory decoded-image cache. Raising this keeps more cover art
  /// resident (smoother scrolling, more RAM); lowering it frees memory.
  void _applyImageCache() {
    PaintingBinding.instance.imageCache.maximumSizeBytes =
        _imageCacheMb * 1024 * 1024;
  }

  Future<void> _setInt(String key, int value) async =>
      (await SharedPreferences.getInstance()).setInt(key, value);
  Future<void> _setBool(String key, bool value) async =>
      (await SharedPreferences.getInstance()).setBool(key, value);
  Future<void> _setDouble(String key, double value) async =>
      (await SharedPreferences.getInstance()).setDouble(key, value);

  Future<void> setQuality(StreamQuality v) async {
    _quality = v;
    notifyListeners();
    await _setInt(_kQuality, v.index);
  }

  Future<void> setSkipSilence(bool v) async {
    _skipSilence = v;
    notifyListeners();
    await _setBool(_kSkipSilence, v);
  }

  Future<void> setPlaybackSpeed(double v) async {
    _playbackSpeed = v;
    notifyListeners();
    await _setDouble(_kSpeed, v);
  }

  Future<void> setResumeOnLaunch(bool v) async {
    _resumeOnLaunch = v;
    notifyListeners();
    await _setBool(_kResume, v);
  }

  Future<void> setImageCacheMb(int v) async {
    _imageCacheMb = v;
    _applyImageCache();
    notifyListeners();
    await _setInt(_kImageCacheMb, v);
  }

  Future<void> setTextScale(double v) async {
    _textScale = v;
    notifyListeners();
    await _setDouble(_kTextScale, v);
  }

  Future<void> setReduceMotion(bool v) async {
    _reduceMotion = v;
    notifyListeners();
    await _setBool(_kReduceMotion, v);
  }
}

/// Single app-wide instance.
final settingsState = SettingsState();
