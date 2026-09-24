import 'dart:async';

import 'package:flutter/material.dart' hide RepeatMode;
import 'package:solar_icons/solar_icons.dart';

import '../models/track.dart';
import '../services/app_state.dart';
import '../services/player_service.dart';
import '../theme.dart';
import '../widgets/cover_art.dart';
import '../widgets/playlist_actions.dart';
import '../services/icon_registry.dart';
import '../widgets/app_icon.dart';

/// Accent colors for the per-track action buttons.
const _kLike = Color(0xFFFF5A7A); // the 'liked' tint

/// Horizontal inset shared by the seek bar's track and its timestamp row, so
/// the times sit flush under the ends of the track.
const double _kSeekInset = 14;

/// Per-cover horizontal inset in the full-bleed cover rail. The cover sits this
/// far from the screen edge at rest; the gap between two covers mid-swipe is 2×
/// this (they each contribute their inset).
const double _kCoverMargin = 30;

/// Full-screen now-playing view: art up top, per-track actions, seek scrubber,
/// transport controls, and the Up Next / Lyrics / Related tabs. Pushed as a
/// bottom-up route from the mini-player.
class NowPlayingScreen extends StatelessWidget {
  const NowPlayingScreen({super.key});

  static Route<void> route() => PageRouteBuilder(
    opaque: true,
    transitionDuration: const Duration(milliseconds: 320),
    reverseTransitionDuration: const Duration(milliseconds: 260),
    pageBuilder: (_, _, _) => const NowPlayingScreen(),
    transitionsBuilder: (_, animation, _, child) => SlideTransition(
      position: Tween(
        begin: const Offset(0, 1),
        end: Offset.zero,
      ).animate(CurvedAnimation(parent: animation, curve: Curves.easeOutCubic)),
      child: child,
    ),
  );

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: playerService,
      builder: (context, _) {
        final track = playerService.current;
        if (track == null) {
          // Nothing playing (e.g. queue stopped) — close.
          WidgetsBinding.instance.addPostFrameCallback((_) {
            if (Navigator.of(context).canPop()) Navigator.of(context).pop();
          });
          return const SizedBox.shrink();
        }

        final hue = (track.id.hashCode % 360).abs().toDouble();
        final tint = HSLColor.fromAHSL(1, hue, 0.45, 0.22).toColor();

        return Scaffold(
          body: GestureDetector(
            behavior: HitTestBehavior.opaque,
            // Swipe down collapses back to the mini player.
            onVerticalDragEnd: (d) {
              if ((d.primaryVelocity ?? 0) > 250) {
                Navigator.of(context).maybePop();
              }
            },
            child: Container(
            decoration: BoxDecoration(
              gradient: LinearGradient(
                begin: Alignment.topCenter,
                end: Alignment.bottomCenter,
                colors: [tint, AppColors.background, AppColors.background],
                stops: const [0.0, 0.5, 1.0],
              ),
            ),
            child: SafeArea(
              // The 24px side padding is applied per-child rather than to the
              // whole column, so the cover rail can run full-bleed and manage its
              // own margins — see below.
              child: Column(
                  children: [
                    const Padding(
                      padding: EdgeInsets.symmetric(horizontal: 24),
                      child: _TopBar(),
                    ),
                    // Gap below the header; nudges the whole cluster down a touch
                    // while the tabs stay anchored to the bottom.
                    const SizedBox(height: 40),
                    // Swipeable cover rail — swipe left → next, right → previous.
                    // The PageView runs full-bleed (edge to edge) so a neighbour
                    // sits just off the screen and slides in from the real screen
                    // edge, as if it had always been there. All the margin lives
                    // in each cover's own inset (_kCoverMargin), giving a resting
                    // side gap of _kCoverMargin and a between-covers gap of 2×.
                    LayoutBuilder(
                      builder: (context, c) => SizedBox(
                        height: c.maxWidth - 2 * _kCoverMargin,
                        child: const _CoverRail(),
                      ),
                    ),
                    const SizedBox(height: 48),
                    Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 24),
                      child: _TitleRow(track: track),
                    ),
                    const SizedBox(height: 32),
                    const Padding(
                      padding: EdgeInsets.symmetric(horizontal: 24),
                      child: _Scrubber(),
                    ),
                    const SizedBox(height: 36),
                    const Padding(
                      padding: EdgeInsets.symmetric(horizontal: 24),
                      child: _Controls(),
                    ),
                    // All remaining space drops here, pushing the tabs down to
                    // the bottom so the layout fills the screen top-to-bottom.
                    const Spacer(),
                    const Padding(
                      padding: EdgeInsets.symmetric(horizontal: 24),
                      child: _BottomTabs(),
                    ),
                    const SizedBox(height: 8),
                  ],
                ),
              ),
            ),
          ),
        );
      },
    );
  }
}

class _TopBar extends StatelessWidget {
  const _TopBar();

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        IconButton(
          onPressed: () => Navigator.of(context).maybePop(),
          icon: const AppIcon(
            IconSlot.collapse,
            color: AppColors.textPrimary,
            size: 32,
          ),
        ),
        const Spacer(),
        ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 220),
          child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Text(
              'NOW PLAYING',
              style: TextStyle(
                color: AppColors.textMuted,
                fontSize: 12,
                fontWeight: FontWeight.w700,
                letterSpacing: 1.6,
              ),
            ),
            // Source of the current queue (playlist / album / mix), like the
            // reference's subtitle under the header.
            if (playerService.contextLabel != null) ...[
              const SizedBox(height: 3),
              Text(
                playerService.contextLabel!,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(
                  color: AppColors.textPrimary,
                  fontSize: 15,
                  fontWeight: FontWeight.w700,
                ),
              ),
            ],
          ],
          ),
        ),
        const Spacer(),
        _OverflowMenu(),
      ],
    );
  }
}

/// Three-dots overflow menu (top-right corner).
class _OverflowMenu extends StatelessWidget {
  void _snack(BuildContext context, String msg) => ScaffoldMessenger.of(
    context,
  ).showSnackBar(SnackBar(content: Text(msg), duration: const Duration(seconds: 1)));

  @override
  Widget build(BuildContext context) {
    return PopupMenuButton<String>(
      icon: const AppIcon(IconSlot.more, color: AppColors.textPrimary),
      color: AppColors.surfaceAlt,
      shape: RoundedRectangleBorder(borderRadius: AppRadius.all(16)),
      onSelected: (v) {
        if (v == 'Add to playlist') {
          final track = playerService.current;
          if (track != null) {
            showAddToPlaylistSheet(context, songIds: [track.id]);
          }
        } else {
          _snack(context, '$v — coming soon');
        }
      },
      itemBuilder: (_) => const [
        PopupMenuItem(value: 'Go to album', child: _MenuRow(SolarIconsOutline.vinylRecord, 'Go to album')),
        PopupMenuItem(value: 'Go to artist', child: _MenuRow(SolarIconsOutline.user, 'Go to artist')),
        PopupMenuItem(value: 'Add to playlist', child: _MenuRow(SolarIconsOutline.playlist, 'Add to playlist')),
        PopupMenuItem(value: 'Song info', child: _MenuRow(SolarIconsOutline.infoCircle, 'Song info')),
      ],
    );
  }
}

class _MenuRow extends StatelessWidget {
  final IconData icon;
  final String label;
  const _MenuRow(this.icon, this.label);

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Icon(icon, color: AppColors.textPrimary, size: 20),
        const SizedBox(width: 12),
        Text(label, style: const TextStyle(color: AppColors.textPrimary)),
      ],
    );
  }
}

/// A horizontal rail of the queue's covers. Swiping between them changes the
/// track (left → next, right → previous) with neighbours peeking in. External
/// track changes (buttons / auto-advance) animate the rail to stay in sync.
class _CoverRail extends StatefulWidget {
  const _CoverRail();

  @override
  State<_CoverRail> createState() => _CoverRailState();
}

class _CoverRailState extends State<_CoverRail> {
  late final PageController _controller;
  int _lastIndex = 0;

  @override
  void initState() {
    super.initState();
    _lastIndex = playerService.index;
    // Full-width pages: only the current cover shows at rest; the neighbours
    // slide in while you actually swipe.
    _controller = PageController(initialPage: _lastIndex);
    playerService.addListener(_syncToPlayer);
  }

  @override
  void dispose() {
    playerService.removeListener(_syncToPlayer);
    _controller.dispose();
    super.dispose();
  }

  void _syncToPlayer() {
    final i = playerService.index;
    if (i == _lastIndex) return;
    _lastIndex = i;
    if (_controller.hasClients) {
      _controller.animateToPage(
        i,
        duration: const Duration(milliseconds: 300),
        curve: Curves.easeOut,
      );
    }
  }

  Widget _cover(Track t) => Padding(
    // Inset each page so neighbours stay off-screen at rest and there's a real
    // gap between covers as they slide in during a swipe. Matches the rail's
    // outer inset so all the gaps are equal (see _kCoverMargin).
    padding: const EdgeInsets.symmetric(horizontal: _kCoverMargin),
    child: Center(
      child: LayoutBuilder(
        builder: (context, c) {
          final s = c.maxWidth < c.maxHeight ? c.maxWidth : c.maxHeight;
          return CoverArt(track: t, size: s, radius: 28);
        },
      ),
    ),
  );

  @override
  Widget build(BuildContext context) {
    final queue = playerService.queue;
    if (queue.length <= 1) {
      final t = playerService.current;
      return t == null ? const SizedBox.shrink() : _cover(t);
    }
    return PageView.builder(
      controller: _controller,
      // Standard direction: swipe left → next (the next cover slides in from
      // the right), swipe right → previous.
      itemCount: queue.length,
      onPageChanged: (i) {
        if (i != playerService.index) {
          _lastIndex = i;
          playerService.jumpTo(i);
        }
      },
      itemBuilder: (context, i) => _cover(queue[i]),
    );
  }
}

/// Title + artist on the left, with the Save (+) and Like (heart) buttons on
/// the right — the way Spotify lays out the now-playing header.
class _TitleRow extends StatelessWidget {
  final Track track;
  const _TitleRow({required this.track});

  @override
  Widget build(BuildContext context) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.center,
      children: [
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                track.title,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(
                  color: AppColors.textPrimary,
                  fontSize: 26,
                  fontWeight: FontWeight.w800,
                ),
              ),
              const SizedBox(height: 4),
              Text(
                track.artist,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(color: AppColors.textMuted, fontSize: 16),
              ),
            ],
          ),
        ),
        const SizedBox(width: 8),
        _AddToPlaylistButton(track: track),
        const SizedBox(width: 6),
        _LikeButton(track: track),
      ],
    );
  }
}

/// Circular "+" that opens the add-to-playlist sheet for the current track.
class _AddToPlaylistButton extends StatelessWidget {
  final Track track;
  const _AddToPlaylistButton({required this.track});

  @override
  Widget build(BuildContext context) {
    return IconButton(
      onPressed: () => showAddToPlaylistSheet(context, songIds: [track.id]),
      tooltip: 'Add to playlist',
      iconSize: 30,
      icon: const AppIcon(
        IconSlot.save,
        color: AppColors.textPrimary,
      ),
    );
  }
}

/// The like mark — outline until liked, then filled (and mirrored to the
/// server). Which mark it is comes from Settings > Appearance.
class _LikeButton extends StatelessWidget {
  final Track track;
  const _LikeButton({required this.track});

  @override
  Widget build(BuildContext context) {
    final liked = playerService.isLiked(track);
    return IconButton(
      onPressed: () => playerService.toggleLike(track),
      tooltip: liked ? 'Liked' : 'Like',
      iconSize: 30,
      icon: AnimatedScale(
        scale: liked ? 1.15 : 1.0,
        duration: const Duration(milliseconds: 180),
        curve: Curves.easeOutBack,
        child: AppIcon(
          liked ? IconSlot.likeFilled : IconSlot.like,
          color: liked ? _kLike : AppColors.textPrimary,
        ),
      ),
    );
  }
}

/// Seek bar: a plain slider showing position within the current track. Wraps a
/// [Slider] so thumb, drag, and tap-to-seek behaviour come for free.
class _Scrubber extends StatelessWidget {
  const _Scrubber();

  String _fmt(Duration d) {
    final m = d.inMinutes;
    final s = (d.inSeconds % 60).toString().padLeft(2, '0');
    return '$m:$s';
  }

  @override
  Widget build(BuildContext context) {
    // Listen to the duration stream so the total (and thus the scrubber range)
    // updates as soon as it's known — reading it once at build time often
    // catches it still null, leaving the bar stuck at 0:00.
    return StreamBuilder<Duration?>(
      stream: playerService.durationStream,
      builder: (context, dSnap) {
        final total = dSnap.data ?? playerService.duration ?? Duration.zero;
        return StreamBuilder<Duration>(
          stream: playerService.positionStream,
          builder: (context, snap) {
            var pos = snap.data ?? Duration.zero;
            if (pos > total) pos = total;
            final maxMs = total.inMilliseconds.toDouble();
            return Column(
              children: [
                SliderTheme(
                  data: SliderThemeData(
                    trackHeight: 3,
                    activeTrackColor: AppColors.accent,
                    inactiveTrackColor: AppColors.border,
                    thumbColor: AppColors.textPrimary,
                    overlayShape: const RoundSliderOverlayShape(
                      overlayRadius: 14,
                    ),
                    thumbShape: const RoundSliderThumbShape(
                      enabledThumbRadius: 6,
                    ),
                  ),
                  child: Slider(
                    // Fixed, known horizontal inset so the track has real side
                    // margins (not stretched edge-to-edge) and the timestamp row
                    // below can line up under its ends using the same inset.
                    padding: const EdgeInsets.symmetric(horizontal: _kSeekInset),
                    min: 0,
                    max: maxMs <= 0 ? 1 : maxMs,
                    value: maxMs <= 0
                        ? 0
                        : pos.inMilliseconds.toDouble().clamp(0, maxMs),
                    onChanged: maxMs <= 0
                        ? null
                        : (v) => playerService.seek(
                            Duration(milliseconds: v.round()),
                          ),
                  ),
                ),
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: _kSeekInset),
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Text(
                        _fmt(pos),
                        style: const TextStyle(
                          color: AppColors.textFaint,
                          fontSize: 12,
                        ),
                      ),
                      Text(
                        _fmt(total),
                        style: const TextStyle(
                          color: AppColors.textFaint,
                          fontSize: 12,
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            );
          },
        );
      },
    );
  }
}

/// Transport row: shuffle · previous · play/pause · next · repeat.
class _Controls extends StatelessWidget {
  const _Controls();

  @override
  Widget build(BuildContext context) {
    // Subscribe here so the play/pause icon and shuffle/repeat states update
    // even though this is a `const` widget (which the parent would otherwise
    // skip rebuilding).
    return ListenableBuilder(
      listenable: playerService,
      builder: (context, _) => _buildRow(),
    );
  }

  Widget _buildRow() {
    final repeat = playerService.repeat;
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: [
        _ToggleIcon(
          icon: IconSlot.shuffle,
          active: playerService.shuffle,
          onTap: playerService.toggleShuffle,
        ),
        _RoundIcon(
          icon: IconSlot.previous,
          size: 44,
          onTap: playerService.previous,
        ),
        // Big play/pause.
        GestureDetector(
          onTap: playerService.toggle,
          child: Container(
            width: 74,
            height: 74,
            decoration: BoxDecoration(
              color: AppColors.accent,
              shape: BoxShape.circle,
              boxShadow: AppShadow.glow(
                AppColors.accent,
                blur: 24,
                dy: 8,
                opacity: 0.45,
              ),
            ),
            child: AnimatedSwitcher(
              duration: const Duration(milliseconds: 160),
              child: AppIcon(
                playerService.isPlaying ? IconSlot.pause : IconSlot.play,
                key: ValueKey(playerService.isPlaying),
                color: Colors.white,
                size: 40,
              ),
            ),
          ),
        ),
        _RoundIcon(
          icon: IconSlot.next,
          size: 44,
          onTap: playerService.hasNext ? playerService.next : null,
        ),
        _ToggleIcon(
          icon: repeat == RepeatMode.one
              ? IconSlot.repeatOne
              : IconSlot.repeat,
          active: repeat != RepeatMode.off,
          onTap: playerService.cycleRepeat,
        ),
      ],
    );
  }
}

/// A small icon that tints to the accent color when [active] (shuffle/repeat).
class _ToggleIcon extends StatelessWidget {
  final IconSlot icon;
  final bool active;
  final VoidCallback onTap;
  const _ToggleIcon({
    required this.icon,
    required this.active,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return IconButton(
      onPressed: onTap,
      iconSize: 27,
      icon: AppIcon(icon, size: 27,
          color: active ? AppColors.accent : AppColors.textMuted),
    );
  }
}

class _RoundIcon extends StatelessWidget {
  final IconSlot icon;
  final double size;
  final VoidCallback? onTap;
  const _RoundIcon({required this.icon, required this.size, this.onTap});

  @override
  Widget build(BuildContext context) {
    return IconButton(
      onPressed: onTap,
      iconSize: size,
      color: AppColors.textPrimary,
      disabledColor: AppColors.textFaint,
      icon: AppIcon(icon, size: size,
          color: onTap == null ? AppColors.textFaint : AppColors.textPrimary),
    );
  }
}

/// Up Next / Lyrics / Related. Up Next opens the live queue; the others open a
/// placeholder sheet for now.
class _BottomTabs extends StatelessWidget {
  const _BottomTabs();

  void _openSheet(BuildContext context, Widget child) {
    showModalBottomSheet<void>(
      context: context,
      backgroundColor: AppColors.surface,
      isScrollControlled: true,
      shape: RoundedRectangleBorder(
        borderRadius: AppRadius.top(24),
      ),
      builder: (_) => child,
    );
  }

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        _Tab(
          label: 'Up Next',
          onTap: () => _openSheet(context, const _UpNextSheet()),
        ),
        _Tab(
          label: 'Lyrics',
          onTap: () => _openSheet(context, const _LyricsSheet()),
        ),
        _Tab(
          label: 'Related',
          onTap: () => _openSheet(context, const _RelatedSheet()),
        ),
      ],
    );
  }
}

class _Tab extends StatelessWidget {
  final String label;
  final VoidCallback onTap;
  const _Tab({required this.label, required this.onTap});

  @override
  Widget build(BuildContext context) {
    return Expanded(
      child: TextButton(
        onPressed: onTap,
        style: TextButton.styleFrom(
          foregroundColor: AppColors.textMuted,
          padding: const EdgeInsets.symmetric(vertical: 12),
        ),
        child: Text(
          label,
          style: const TextStyle(
            fontSize: 13,
            fontWeight: FontWeight.w700,
            letterSpacing: 0.4,
          ),
        ),
      ),
    );
  }
}

/// The live play queue, highlighting the current track.
class _UpNextSheet extends StatelessWidget {
  const _UpNextSheet();

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: playerService,
      builder: (context, _) {
        final queue = playerService.queue;
        final current = playerService.index;
        return DraggableScrollableSheet(
          expand: false,
          initialChildSize: 0.6,
          maxChildSize: 0.9,
          builder: (context, controller) => Column(
            children: [
              const _SheetHandle(),
              const Padding(
                padding: EdgeInsets.fromLTRB(20, 4, 20, 12),
                child: Align(
                  alignment: Alignment.centerLeft,
                  child: Text(
                    'Up Next',
                    style: TextStyle(
                      color: AppColors.textPrimary,
                      fontSize: 18,
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                ),
              ),
              Expanded(
                child: ReorderableListView.builder(
                  scrollController: controller,
                  itemCount: queue.length,
                  // onReorderItem hands back newIndex already adjusted for the
                  // removed item, so it maps straight onto moveInQueue.
                  onReorderItem: (oldIndex, newIndex) =>
                      playerService.moveInQueue(oldIndex, newIndex),
                  itemBuilder: (context, i) {
                    final t = queue[i];
                    final isCurrent = i == current;
                    // ObjectKey ties the key to the track instance, so it stays
                    // stable across reorders (and survives duplicate ids).
                    return Dismissible(
                      key: ObjectKey(t),
                      direction: DismissDirection.endToStart,
                      background: Container(
                        alignment: Alignment.centerRight,
                        padding: const EdgeInsets.only(right: 24),
                        color: _kLike.withValues(alpha: 0.18),
                        child: const Icon(
                          SolarIconsOutline.trashBinMinimalistic,
                          color: _kLike,
                        ),
                      ),
                      onDismissed: (_) => playerService.removeFromQueue(i),
                      child: ListTile(
                        leading: CoverArt(track: t, size: 44, radius: 8),
                        title: Text(
                          t.title,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(
                            color: isCurrent
                                ? AppColors.accent
                                : AppColors.textPrimary,
                            fontWeight: isCurrent
                                ? FontWeight.w700
                                : FontWeight.w500,
                          ),
                        ),
                        subtitle: Text(
                          t.artist,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(color: AppColors.textMuted),
                        ),
                        trailing: ReorderableDragStartListener(
                          index: i,
                          child: AppIcon(
                            isCurrent
                                ? IconSlot.musicNote
                                : IconSlot.queue,
                            color: isCurrent
                                ? AppColors.accent
                                : AppColors.textMuted,
                            size: 20,
                          ),
                        ),
                        onTap: () {
                          playerService.jumpTo(i);
                          Navigator.of(context).pop();
                        },
                      ),
                    );
                  },
                ),
              ),
            ],
          ),
        );
      },
    );
  }
}

/// Section title used at the top of the sheets.
class _SheetTitle extends StatelessWidget {
  final String text;
  const _SheetTitle(this.text);
  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 4, 20, 12),
      child: Align(
        alignment: Alignment.centerLeft,
        child: Text(
          text,
          style: const TextStyle(
            color: AppColors.textPrimary,
            fontSize: 18,
            fontWeight: FontWeight.w800,
          ),
        ),
      ),
    );
  }
}

/// Centered "empty state" body (icon + message) for the sheets.
class _SheetEmpty extends StatelessWidget {
  final String message;
  final IconData icon;
  const _SheetEmpty({required this.message, required this.icon});
  @override
  Widget build(BuildContext context) {
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, color: AppColors.textFaint, size: 40),
          const SizedBox(height: 12),
          Text(
            message,
            textAlign: TextAlign.center,
            style: const TextStyle(
              color: AppColors.textMuted,
              fontSize: 15,
              fontWeight: FontWeight.w600,
            ),
          ),
        ],
      ),
    );
  }
}

/// Lyrics for the current track. Synced lyrics highlight the active line and
/// scroll to follow playback; tapping a synced line seeks to it.
class _LyricsSheet extends StatefulWidget {
  const _LyricsSheet();
  @override
  State<_LyricsSheet> createState() => _LyricsSheetState();
}

class _LyricsSheetState extends State<_LyricsSheet> {
  final ScrollController _scroll = ScrollController();
  late final Future<Lyrics> _future;
  List<GlobalKey> _keys = const [];
  Lyrics? _lyrics;
  StreamSubscription<Duration>? _posSub;
  int _active = -1;

  @override
  void initState() {
    super.initState();
    final client = appState.client;
    final track = playerService.current;
    if (client == null || track == null) {
      _future = Future.value(const Lyrics(synced: false, lines: []));
    } else {
      _future = client.lyrics(track.id);
      _future.then((l) {
        if (!mounted) return;
        _lyrics = l;
        _keys = List.generate(l.lines.length, (_) => GlobalKey());
        if (l.synced) {
          _posSub = playerService.positionStream.listen(_onPosition);
        }
      }).catchError((_) {});
    }
  }

  void _onPosition(Duration pos) {
    final lines = _lyrics?.lines;
    if (lines == null || lines.isEmpty) return;
    final ms = pos.inMilliseconds;
    int idx = -1;
    for (var i = 0; i < lines.length; i++) {
      final s = lines[i].start;
      if (s == null) continue;
      if (s <= ms) {
        idx = i;
      } else {
        break;
      }
    }
    if (idx != _active) {
      setState(() => _active = idx);
      _scrollToActive(idx);
    }
  }

  void _scrollToActive(int idx) {
    if (idx < 0 || idx >= _keys.length) return;
    final ctx = _keys[idx].currentContext;
    if (ctx == null) return;
    Scrollable.ensureVisible(
      ctx,
      alignment: 0.4,
      duration: const Duration(milliseconds: 350),
      curve: Curves.easeInOut,
    );
  }

  @override
  void dispose() {
    _posSub?.cancel();
    _scroll.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final height = MediaQuery.of(context).size.height * 0.85;
    return SizedBox(
      height: height,
      child: Column(
        children: [
          const _SheetHandle(),
          const _SheetTitle('Lyrics'),
          Expanded(
            child: FutureBuilder<Lyrics>(
              future: _future,
              builder: (context, snap) {
                if (snap.connectionState != ConnectionState.done) {
                  return Center(
                    child: CircularProgressIndicator(color: AppColors.accent),
                  );
                }
                if (snap.hasError) {
                  return const _SheetEmpty(
                    message: "Couldn't load lyrics",
                    icon: SolarIconsOutline.dangerTriangle,
                  );
                }
                final lyrics = snap.data;
                if (lyrics == null || lyrics.isEmpty) {
                  return const _SheetEmpty(
                    message: 'No lyrics found for this track',
                    icon: SolarIconsOutline.notes,
                  );
                }
                return ListView.builder(
                  controller: _scroll,
                  padding: const EdgeInsets.fromLTRB(24, 8, 24, 48),
                  itemCount: lyrics.lines.length,
                  itemBuilder: (context, i) {
                    final line = lyrics.lines[i];
                    final isActive = lyrics.synced && i == _active;
                    final canSeek = lyrics.synced && line.start != null;
                    return Padding(
                      key: i < _keys.length ? _keys[i] : null,
                      padding: const EdgeInsets.symmetric(vertical: 8),
                      child: GestureDetector(
                        behavior: HitTestBehavior.opaque,
                        onTap: canSeek
                            ? () => playerService.seek(
                                Duration(milliseconds: line.start!),
                              )
                            : null,
                        child: Text(
                          line.text.isEmpty ? '♪' : line.text,
                          style: TextStyle(
                            fontSize: 18,
                            height: 1.35,
                            fontWeight: isActive
                                ? FontWeight.w800
                                : FontWeight.w600,
                            color: isActive
                                ? AppColors.textPrimary
                                : (lyrics.synced
                                      ? AppColors.textFaint
                                      : AppColors.textMuted),
                          ),
                        ),
                      ),
                    );
                  },
                );
              },
            ),
          ),
        ],
      ),
    );
  }
}

/// Songs Navidrome considers similar to the current track. Tapping one starts
/// it as a fresh queue seeded from the related list.
class _RelatedSheet extends StatefulWidget {
  const _RelatedSheet();
  @override
  State<_RelatedSheet> createState() => _RelatedSheetState();
}

class _RelatedSheetState extends State<_RelatedSheet> {
  late final Future<List<Track>> _future;

  @override
  void initState() {
    super.initState();
    final client = appState.client;
    final track = playerService.current;
    _future = (client == null || track == null)
        ? Future.value(const <Track>[])
        : client.similarSongs(track.id);
  }

  void _play(List<Track> tracks, int index) {
    final client = appState.client;
    if (client == null) return;
    playerService.playQueue(
      tracks,
      index,
      client: client,
      contextLabel: 'Related',
    );
    Navigator.of(context).pop();
  }

  @override
  Widget build(BuildContext context) {
    return DraggableScrollableSheet(
      expand: false,
      initialChildSize: 0.6,
      maxChildSize: 0.9,
      builder: (context, controller) => Column(
        children: [
          const _SheetHandle(),
          const _SheetTitle('Related'),
          Expanded(
            child: FutureBuilder<List<Track>>(
              future: _future,
              builder: (context, snap) {
                if (snap.connectionState != ConnectionState.done) {
                  return Center(
                    child: CircularProgressIndicator(color: AppColors.accent),
                  );
                }
                final tracks = snap.data ?? const <Track>[];
                if (snap.hasError) {
                  return const _SheetEmpty(
                    message: "Couldn't load related songs",
                    icon: SolarIconsOutline.dangerTriangle,
                  );
                }
                if (tracks.isEmpty) {
                  return const _SheetEmpty(
                    message: 'No related songs found',
                    icon: SolarIconsOutline.stars,
                  );
                }
                return ListView.builder(
                  controller: controller,
                  itemCount: tracks.length,
                  itemBuilder: (context, i) {
                    final t = tracks[i];
                    return ListTile(
                      leading: CoverArt(track: t, size: 44, radius: 8),
                      title: Text(
                        t.title,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                          color: AppColors.textPrimary,
                          fontWeight: FontWeight.w500,
                        ),
                      ),
                      subtitle: Text(
                        t.artist,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(color: AppColors.textMuted),
                      ),
                      trailing: const Icon(
                        SolarIconsOutline.play,
                        color: AppColors.textMuted,
                        size: 18,
                      ),
                      onTap: () => _play(tracks, i),
                    );
                  },
                );
              },
            ),
          ),
        ],
      ),
    );
  }
}

class _SheetHandle extends StatelessWidget {
  const _SheetHandle();
  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.only(top: 10, bottom: 6),
      width: 40,
      height: 4,
      decoration: BoxDecoration(
        color: AppColors.border,
        borderRadius: AppRadius.all(2),
      ),
    );
  }
}
