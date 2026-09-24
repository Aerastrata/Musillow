import 'abs_client.dart';
import 'player_service.dart';

/// Reports playback position of an Audiobookshelf book back to the server so
/// the "resume where you left off" position stays in sync (across devices too).
///
/// A book plays as a queue of its audio files; ABS tracks a single cumulative
/// position for the whole book, so we add the current file's start [offset] to
/// the position within that file.
class AbsProgressReporter implements PlaybackReporter {
  final AudiobookshelfClient client;
  final String itemId;
  final List<double> offsets; // cumulative start (seconds) per file index
  final double total;
  DateTime _last = DateTime.fromMillisecondsSinceEpoch(0);

  AbsProgressReporter({
    required this.client,
    required this.itemId,
    required this.offsets,
    required this.total,
  });

  @override
  void report(int index, Duration position, {required bool finished}) {
    final base = (index >= 0 && index < offsets.length) ? offsets[index] : 0.0;
    final current = base + position.inMilliseconds / 1000.0;
    final now = DateTime.now();
    // Throttle periodic saves; always flush on finish.
    if (!finished && now.difference(_last).inSeconds < 10) return;
    _last = now;
    client
        .updateProgress(
          itemId,
          currentTime: current,
          duration: total,
          isFinished: finished,
        )
        .ignore();
  }
}
