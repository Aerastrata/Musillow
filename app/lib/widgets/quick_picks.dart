import 'package:flutter/material.dart';

import '../models/track.dart';
import '../services/app_state.dart';
import '../services/automation_client.dart';
import '../services/automation_state.dart';
import '../services/player_service.dart';
import '../theme.dart';
import 'cover_art.dart';

/// Home Quick Picks: a single 2×3 grid of six shortcut tiles. The six are drawn
/// evenly across the three sources (Replay Mix / Liked but Forgotten / Wildcard)
/// round-robin, backfilling from the others so it's *always* six even when a
/// source is thin. Hidden unless the automation service is connected.
class QuickPicksSection extends StatefulWidget {
  /// Picks supplied by the caller (the /home aggregate already contains them).
  /// When null, this section fetches its own — kept so it still works standalone.
  final List<Track>? picks;

  const QuickPicksSection({super.key, this.picks});

  @override
  State<QuickPicksSection> createState() => _QuickPicksSectionState();
}

class _QuickPicksSectionState extends State<QuickPicksSection> {
  Future<List<QuickPickRow>>? _future;

  @override
  void initState() {
    super.initState();
    // Picks supplied by the caller need no fetch and no listener.
    if (widget.picks != null) {
      return;
    }
    automationState.addListener(_onAuto);
    _load();
  }

  @override
  void dispose() {
    if (widget.picks == null) automationState.removeListener(_onAuto);
    super.dispose();
  }

  void _onAuto() {
    if (mounted) setState(_load);
  }

  void _load() {
    final auto = automationState.client;
    final music = appState.client;
    _future = (auto != null && music != null) ? auto.quickPicks(music) : null;
  }

  /// Six picks, spread across the sources round-robin (≈2 from each) and
  /// backfilled so we always return six when there are enough tracks at all.
  List<Track> _sixPicks(List<QuickPickRow> rows) {
    final cats = rows
        .where((r) => r.tracks.isNotEmpty)
        .map((r) => List<Track>.of(r.tracks))
        .toList();
    final picks = <Track>[];
    final seen = <String>{};
    var guard = 0;
    while (picks.length < 6 && cats.any((c) => c.isNotEmpty) && guard++ < 200) {
      for (final cat in cats) {
        if (cat.isEmpty) continue;
        final t = cat.removeAt(0);
        if (seen.add(t.id)) picks.add(t);
        if (picks.length >= 6) break;
      }
    }
    return picks;
  }

  void _play(List<Track> picks, int index) {
    playerService.playQueue(
      picks,
      index,
      client: appState.client,
      contextLabel: 'Quick Picks',
    );
  }

  @override
  Widget build(BuildContext context) {
    final supplied = widget.picks;
    if (supplied != null) return _grid(supplied.take(6).toList());
    if (_future == null) return const SizedBox.shrink();
    return FutureBuilder<List<QuickPickRow>>(
      future: _future,
      builder: (context, snap) {
        if (snap.connectionState == ConnectionState.waiting) {
          return const SizedBox.shrink();
        }
        return _grid(_sixPicks(snap.data ?? const []));
      },
    );
  }

  Widget _grid(List<Track> picks) {
    if (picks.isEmpty) return const SizedBox.shrink();
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 4, 16, 12),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Padding(
            padding: EdgeInsets.only(left: 4, bottom: 10),
            child: Text(
              'Quick Picks',
              style: TextStyle(
                fontSize: 20,
                fontWeight: FontWeight.w800,
                color: AppColors.textPrimary,
              ),
            ),
          ),
          // Explicit 2-column grid of fixed-height rows. (A GridView with a
          // fixed cross-axis delegate reserved far more vertical space than
          // its 64px tiles, leaving a large gap below — this sizes exactly.)
          for (var i = 0; i < picks.length; i += 2) ...[
            if (i > 0) const SizedBox(height: 10),
            SizedBox(
              height: 64,
              child: Row(
                children: [
                  Expanded(
                    child: _Shortcut(
                      track: picks[i],
                      onTap: () => _play(picks, i),
                    ),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: i + 1 < picks.length
                        ? _Shortcut(
                            track: picks[i + 1],
                            onTap: () => _play(picks, i + 1),
                          )
                        : const SizedBox.shrink(),
                  ),
                ],
              ),
            ),
          ],
        ],
      ),
    );
  }
}

/// A compact horizontal tile: square cover flush-left, title filling the rest.
class _Shortcut extends StatelessWidget {
  final Track track;
  final VoidCallback onTap;
  const _Shortcut({required this.track, required this.onTap});

  @override
  Widget build(BuildContext context) {
    return Material(
      color: AppColors.surface,
      borderRadius: AppRadius.all(10),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: onTap,
        child: Row(
          children: [
            CoverArt(track: track, size: 64, radius: 0),
            Expanded(
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 10),
                child: Text(
                  track.title,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    color: AppColors.textPrimary,
                    fontSize: 13,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
