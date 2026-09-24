import 'dart:async';

import 'package:flutter/material.dart';
import 'package:solar_icons/solar_icons.dart';

import '../models/track.dart';
import '../services/automation_client.dart';
import '../theme.dart';
import 'fading_image.dart';
import '../services/icon_registry.dart';
import 'app_icon.dart';

/// Shared section heading so every home row lines up.
class SectionHeader extends StatelessWidget {
  final String title;
  const SectionHeader(this.title, {super.key});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 22, 20, 12),
      child: Text(
        title,
        style: const TextStyle(
          fontSize: 20,
          fontWeight: FontWeight.w800,
          color: AppColors.textPrimary,
        ),
      ),
    );
  }
}

/// A network cover with a muted fallback, used by every card here — and by
/// the custom blocks, so a block the user builds is made of the same parts
/// as the rows that ship.
class SectionCover extends StatelessWidget {
  final String? url;
  final double width;
  final double height;
  final double radius;
  final IconData icon;
  const SectionCover({
    super.key,
    required this.url,
    required this.width,
    required this.height,
    this.radius = 10,
    this.icon = SolarIconsBold.musicNote,
  });

  @override
  Widget build(BuildContext context) {
    return ClipRRect(
      borderRadius: BorderRadius.circular(radius),
      child: SizedBox(
        width: width,
        height: height,
        child: FadingImage(url: url, placeholder: _fallback()),
      ),
    );
  }

  Widget _fallback() => ColoredBox(
    color: AppColors.surfaceAlt,
    child: Icon(icon, color: AppColors.textFaint, size: height * 0.32),
  );
}

/// Two lines of label under a card.
///
/// Wrapped in [Expanded] by every caller and hard-limited to one line each, so
/// a large system font scale shortens the text instead of overflowing the row.
class _CardLabel extends StatelessWidget {
  final String title;
  final String subtitle;
  const _CardLabel({required this.title, required this.subtitle});

  @override
  Widget build(BuildContext context) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          title,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: const TextStyle(
            color: AppColors.textPrimary,
            fontSize: 14,
            fontWeight: FontWeight.w700,
          ),
        ),
        if (subtitle.isNotEmpty)
          Text(
            subtitle,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: const TextStyle(color: AppColors.textMuted, fontSize: 12),
          ),
      ],
    );
  }
}

/// Wraps a home row so an outsized system font can't blow its fixed height.
///
/// The cards are deliberately compact; letting text scale without limit is what
/// produced the RenderFlex overflow stripes.
class _RowScale extends StatelessWidget {
  final Widget child;
  const _RowScale({required this.child});

  @override
  Widget build(BuildContext context) =>
      MediaQuery.withClampedTextScaling(maxScaleFactor: 1.15, child: child);
}

/// A horizontal strip of uniform cards, sized so the label always fits.
class CardStrip extends StatelessWidget {
  final String title;
  final int count;
  final double cardWidth;
  final double coverHeight;
  final Widget Function(int index) coverBuilder;
  final Widget Function(int index) labelBuilder;
  final void Function(int index) onTap;

  const CardStrip({
    super.key,
    required this.title,
    required this.count,
    required this.cardWidth,
    required this.coverHeight,
    required this.coverBuilder,
    required this.labelBuilder,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    // Cover + gap + two comfortable text lines.
    final height = coverHeight + 8 + 44;
    return _RowScale(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SectionHeader(title),
          SizedBox(
            height: height,
            child: ListView.builder(
              scrollDirection: Axis.horizontal,
              padding: const EdgeInsets.symmetric(horizontal: 16),
              itemCount: count,
              itemBuilder: (context, i) => Padding(
                padding: const EdgeInsets.only(right: 12),
                child: GestureDetector(
                  onTap: () => onTap(i),
                  child: SizedBox(
                    width: cardWidth,
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        coverBuilder(i),
                        const SizedBox(height: 8),
                        Expanded(child: labelBuilder(i)),
                      ],
                    ),
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// The featured spotlight: one fixed banner whose *contents* slide across to
/// the next featured song on a timer.
///
/// The rounded frame and the play button live outside the pager, so only the
/// artwork and titles move — which is why the spotlight is backed by a playlist
/// rather than a single track. A real pager rather than a cross-fade gives it
/// proper page physics, and hand-swiping for free.
class FeaturedSpotlight extends StatefulWidget {
  final Playlist playlist;

  /// Play the spotlight starting from the track currently on screen.
  final void Function(int index) onPlay;

  /// Which track this banner opens on. Placing a second spotlight module hands
  /// it a different start, so two banners show different tracks rather than
  /// the same one twice.
  final int startIndex;

  const FeaturedSpotlight({
    super.key,
    required this.playlist,
    required this.onPlay,
    this.startIndex = 0,
  });

  @override
  State<FeaturedSpotlight> createState() => _FeaturedSpotlightState();
}

class _FeaturedSpotlightState extends State<FeaturedSpotlight> {
  static const _dwell = Duration(seconds: 7);

  late final PageController _controller;
  Timer? _timer;
  late int _index;

  @override
  void initState() {
    super.initState();
    final count = widget.playlist.tracks.length;
    _index = count == 0 ? 0 : widget.startIndex % count;
    _controller = PageController(initialPage: _index);
    _restartTimer();
  }

  void _restartTimer() {
    _timer?.cancel();
    if (widget.playlist.tracks.length < 2) return;
    _timer = Timer.periodic(_dwell, (_) {
      if (!mounted || !_controller.hasClients) return;
      _controller.animateToPage(
        (_index + 1) % widget.playlist.tracks.length,
        duration: const Duration(milliseconds: 620),
        curve: Curves.easeInOutCubic,
      );
    });
  }

  @override
  void dispose() {
    _timer?.cancel();
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final tracks = widget.playlist.tracks;
    if (tracks.isEmpty) return const SizedBox.shrink();
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const SizedBox(height: 12),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16),
          child: ClipRRect(
            borderRadius: AppRadius.all(20),
            child: SizedBox(
              height: 190,
              child: Stack(
                fit: StackFit.expand,
                children: [
                  PageView.builder(
                    controller: _controller,
                    itemCount: tracks.length,
                    onPageChanged: (i) {
                      setState(() => _index = i);
                      // A hand swipe earns a full dwell before the next
                      // automatic move.
                      _restartTimer();
                    },
                    itemBuilder: (context, i) => GestureDetector(
                      onTap: () => widget.onPlay(i),
                      child: _content(tracks[i]),
                    ),
                  ),
                  // Chrome sits outside the pager so it holds still while the
                  // content slides past behind it.
                  Positioned(
                    right: 16,
                    bottom: 16,
                    child: GestureDetector(
                      onTap: () => widget.onPlay(_index),
                      child: Container(
                        width: 52,
                        height: 52,
                        decoration: BoxDecoration(
                          color: AppColors.accent,
                          shape: BoxShape.circle,
                          boxShadow: AppShadow.glow(AppColors.accent),
                        ),
                        child: const AppIcon(
                          IconSlot.play,
                          color: Colors.white,
                          size: 26,
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
        const SizedBox(height: 10),
        _dots(tracks.length),
      ],
    );
  }

  Widget _content(Track track) {
    return Stack(
      fit: StackFit.expand,
      children: [
        FadingImage(url: track.coverArtUrl, placeholder: _gradient()),
        DecoratedBox(
          decoration: BoxDecoration(
            gradient: LinearGradient(
              begin: Alignment.bottomLeft,
              end: Alignment.topRight,
              colors: [
                Colors.black.withValues(alpha: 0.85),
                Colors.black.withValues(alpha: 0.15),
              ],
            ),
          ),
        ),
        Padding(
          padding: const EdgeInsets.fromLTRB(20, 20, 84, 20),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisAlignment: MainAxisAlignment.end,
            children: [
              // The backend's reason for this spotlight — "Because you
              // played <artist>" once there's listening to build on. It's a
              // property of the playlist, not the track, so it holds still
              // while the pages slide behind it.
              Text(
                (widget.playlist.subtitle.isEmpty
                        ? 'In the spotlight'
                        : widget.playlist.subtitle)
                    .toUpperCase(),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(
                  color: Colors.white70,
                  fontSize: 10.5,
                  fontWeight: FontWeight.w700,
                  letterSpacing: 1.6,
                ),
              ),
              const SizedBox(height: 6),
              Text(
                track.title,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(
                  color: Colors.white,
                  fontSize: 25,
                  fontWeight: FontWeight.w900,
                ),
              ),
              Text(
                track.artist,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(color: Colors.white70, fontSize: 14),
              ),
            ],
          ),
        ),
      ],
    );
  }

  Widget _dots(int count) {
    // Long spotlights would run off the edge; show a window around the current.
    const maxDots = 7;
    final start = count <= maxDots
        ? 0
        : (_index - maxDots ~/ 2).clamp(0, count - maxDots);
    final shown = count <= maxDots ? count : maxDots;
    return Center(
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          for (var i = start; i < start + shown; i++)
            AnimatedContainer(
              duration: const Duration(milliseconds: 250),
              margin: const EdgeInsets.symmetric(horizontal: 3),
              width: i == _index ? 18 : 6,
              height: 6,
              decoration: BoxDecoration(
                color: i == _index ? AppColors.accent : AppColors.border,
                borderRadius: AppRadius.all(3),
              ),
            ),
        ],
      ),
    );
  }

  Widget _gradient() => DecoratedBox(
    decoration: BoxDecoration(
      gradient: LinearGradient(
        begin: Alignment.topLeft,
        end: Alignment.bottomRight,
        colors: [AppColors.accent, AppColors.teal],
      ),
    ),
  );
}

/// "Continue listening" — part-finished audiobooks with a progress bar.
class ContinueListeningRow extends StatelessWidget {
  final List<ContinueBook> books;
  final void Function(ContinueBook) onTap;
  const ContinueListeningRow({
    super.key,
    required this.books,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return _RowScale(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const SectionHeader('Continue listening'),
          SizedBox(
            height: 116,
            child: ListView.builder(
              scrollDirection: Axis.horizontal,
              padding: const EdgeInsets.symmetric(horizontal: 16),
              itemCount: books.length,
              itemBuilder: (context, i) => _card(books[i]),
            ),
          ),
        ],
      ),
    );
  }

  Widget _card(ContinueBook book) {
    return Padding(
      padding: const EdgeInsets.only(right: 12),
      child: Material(
        color: AppColors.surface,
        borderRadius: AppRadius.all(18),
        clipBehavior: Clip.antiAlias,
        child: InkWell(
          onTap: () => onTap(book),
          child: SizedBox(
            width: 250,
            child: Row(
              children: [
                SectionCover(
                  url: book.coverUrl,
                  width: 84,
                  height: 116,
                  radius: 0,
                  icon: SolarIconsBold.headphonesRoundSound,
                ),
                Expanded(
                  child: Padding(
                    padding: const EdgeInsets.all(10),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Text(
                          book.title,
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(
                            color: AppColors.textPrimary,
                            fontSize: 13.5,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                        const SizedBox(height: 8),
                        ClipRRect(
                          borderRadius: AppRadius.all(3),
                          child: LinearProgressIndicator(
                            value: book.progress,
                            minHeight: 4,
                            backgroundColor: AppColors.surfaceAlt,
                            valueColor: const AlwaysStoppedAnimation(
                              Color(0xFFB57BFF),
                            ),
                          ),
                        ),
                        const SizedBox(height: 5),
                        Text(
                          '${(book.progress * 100).round()}% through',
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(
                            color: AppColors.textFaint,
                            fontSize: 11,
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// Wide 2:1 cards for a list of tracks — the shape used for Forgotten Faves.
class WideTrackRow extends StatelessWidget {
  final String title;
  final List<Track> tracks;
  final void Function(int index) onTap;
  const WideTrackRow({
    super.key,
    required this.title,
    required this.tracks,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return CardStrip(
      title: title,
      count: tracks.length,
      cardWidth: 220,
      coverHeight: 110,
      onTap: onTap,
      coverBuilder: (i) => SectionCover(
        url: tracks[i].coverArtUrl,
        width: 220,
        height: 110,
        radius: 18,
      ),
      labelBuilder: (i) =>
          _CardLabel(title: tracks[i].title, subtitle: tracks[i].artist),
    );
  }
}

/// Album cards — used for "Albums for you" and, lower down, "Jump back in".
class AlbumRow extends StatelessWidget {
  final String title;
  final List<Album> albums;
  final void Function(Album) onTap;

  /// Wide 2:1 art instead of square.
  final bool wide;

  const AlbumRow({
    super.key,
    required this.title,
    required this.albums,
    required this.onTap,
    this.wide = false,
  });

  @override
  Widget build(BuildContext context) {
    final w = wide ? 220.0 : 150.0;
    final h = wide ? 110.0 : 150.0;
    return CardStrip(
      title: title,
      count: albums.length,
      cardWidth: w,
      coverHeight: h,
      onTap: (i) => onTap(albums[i]),
      coverBuilder: (i) =>
          SectionCover(url: albums[i].coverArtUrl, width: w, height: h, radius: 18),
      labelBuilder: (i) =>
          _CardLabel(title: albums[i].name, subtitle: albums[i].artist),
    );
  }
}

/// New releases from artists the user follows. External artwork, and not
/// necessarily in the library — tapping searches for it.
class NewReleaseRow extends StatelessWidget {
  final List<NewRelease> releases;
  final void Function(NewRelease) onTap;
  const NewReleaseRow({
    super.key,
    required this.releases,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return CardStrip(
      title: 'New releases',
      count: releases.length,
      cardWidth: 150,
      coverHeight: 150,
      onTap: (i) => onTap(releases[i]),
      coverBuilder: (i) => SectionCover(
        url: releases[i].artworkUrl,
        width: 150,
        height: 150,
        radius: 18,
      ),
      labelBuilder: (i) => _CardLabel(
        title: releases[i].title,
        subtitle: [
          releases[i].artist,
          if (releases[i].year != null) releases[i].year!,
        ].join(' • '),
      ),
    );
  }
}

/// A genre-led row mixing a genre mix, matching playlists, and albums.
class MoodRowSection extends StatelessWidget {
  final MoodRow row;
  final void Function(MoodItem) onTap;
  const MoodRowSection({super.key, required this.row, required this.onTap});

  IconData _icon(String type) => switch (type) {
    'mix' => SolarIconsBold.musicNotes,
    'playlist' => SolarIconsBold.playlist,
    _ => SolarIconsBold.vinylRecord,
  };

  @override
  Widget build(BuildContext context) {
    return CardStrip(
      title: row.title,
      count: row.items.length,
      cardWidth: 150,
      coverHeight: 150,
      onTap: (i) => onTap(row.items[i]),
      coverBuilder: (i) {
        final item = row.items[i];
        return Stack(
          children: [
            SectionCover(
              url: item.coverUrl,
              width: 150,
              height: 150,
              radius: 18,
              icon: _icon(item.type),
            ),
            // A badge, because the row deliberately mixes kinds and the card
            // shape alone doesn't say which is which.
            Positioned(
              left: 8,
              top: 8,
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                decoration: BoxDecoration(
                  color: Colors.black.withValues(alpha: 0.62),
                  borderRadius: AppRadius.all(20),
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(_icon(item.type), size: 11, color: Colors.white),
                    const SizedBox(width: 4),
                    Text(
                      item.type == 'mix'
                          ? 'Mix'
                          : item.type == 'playlist'
                          ? 'Playlist'
                          : 'Album',
                      style: const TextStyle(
                        color: Colors.white,
                        fontSize: 10,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ],
        );
      },
      labelBuilder: (i) => _CardLabel(
        title: row.items[i].title,
        subtitle: row.items[i].subtitle,
      ),
    );
  }
}

/// Circular artist avatars — the only round shape on the page.
class ArtistCircleRow extends StatelessWidget {
  final List<Artist> artists;
  const ArtistCircleRow({super.key, required this.artists});

  @override
  Widget build(BuildContext context) {
    return _RowScale(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const SectionHeader('Your artists'),
          SizedBox(
            height: 148,
            child: ListView.builder(
              scrollDirection: Axis.horizontal,
              padding: const EdgeInsets.symmetric(horizontal: 16),
              itemCount: artists.length,
              itemBuilder: (context, i) => Padding(
                padding: const EdgeInsets.only(right: 14),
                child: SizedBox(
                  width: 96,
                  child: Column(
                    children: [
                      ClipOval(
                        child: SectionCover(
                          url: artists[i].coverArtUrl,
                          width: 96,
                          height: 96,
                          radius: 48,
                          icon: SolarIconsBold.user,
                        ),
                      ),
                      const SizedBox(height: 8),
                      Expanded(
                        child: Text(
                          artists[i].name,
                          maxLines: 2,
                          textAlign: TextAlign.center,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(
                            color: AppColors.textPrimary,
                            fontSize: 12.5,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// The user's own playlists as cover cards.
class PlaylistCardRow extends StatelessWidget {
  final List<Playlist> playlists;
  final void Function(Playlist) onTap;
  const PlaylistCardRow({
    super.key,
    required this.playlists,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return CardStrip(
      title: 'Your playlists',
      count: playlists.length,
      cardWidth: 140,
      coverHeight: 140,
      onTap: (i) => onTap(playlists[i]),
      coverBuilder: (i) => SectionCover(
        url: playlists[i].coverArtUrl,
        width: 140,
        height: 140,
        radius: 18,
        icon: SolarIconsBold.playlist,
      ),
      labelBuilder: (i) => _CardLabel(
        title: playlists[i].name,
        subtitle: playlists[i].subtitle,
      ),
    );
  }
}

/// Generated mixes (the daily ones plus the Weekly).
class MixRow extends StatelessWidget {
  final List<Playlist> playlists;
  final void Function(Playlist) onTap;
  const MixRow({super.key, required this.playlists, required this.onTap});

  @override
  Widget build(BuildContext context) {
    return CardStrip(
      title: 'Your mixes',
      count: playlists.length,
      cardWidth: 150,
      coverHeight: 150,
      onTap: (i) => onTap(playlists[i]),
      coverBuilder: (i) => SectionCover(
        url: playlists[i].tracks.isNotEmpty
            ? playlists[i].tracks.first.coverArtUrl
            : null,
        width: 150,
        height: 150,
        radius: 18,
      ),
      labelBuilder: (i) => _CardLabel(
        title: playlists[i].name,
        subtitle: playlists[i].subtitle,
      ),
    );
  }
}

/// A shimmering placeholder block.
///
/// One controller drives every block on the page via [HomeSkeleton], so the
/// sweep stays in phase across the whole screen rather than each tile
/// glimmering on its own clock.
class _Shimmer extends AnimatedWidget {
  final double width;
  final double height;
  final double radius;

  const _Shimmer({
    required Animation<double> animation,
    required this.width,
    required this.height,
    this.radius = 12,
  }) : super(listenable: animation);

  @override
  Widget build(BuildContext context) {
    final t = (listenable as Animation<double>).value;
    return Container(
      width: width,
      height: height,
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(radius),
        gradient: LinearGradient(
          // Sweep a soft highlight across a long gradient; the alignment
          // travels from off-screen left to off-screen right.
          begin: Alignment(-1.0 - 2.0 * (1 - t), 0),
          end: Alignment(1.0 + 2.0 * t, 0),
          colors: const [
            AppColors.surface,
            AppColors.surfaceAlt,
            AppColors.surface,
          ],
          stops: const [0.35, 0.5, 0.65],
        ),
      ),
    );
  }
}

/// The home screen's loading state.
///
/// Shaped like the real page — greeting, spotlight, quick-picks grid, card
/// strips — so content settles into place instead of a spinner vanishing and
/// everything appearing at once.
class HomeSkeleton extends StatefulWidget {
  const HomeSkeleton({super.key});

  @override
  State<HomeSkeleton> createState() => _HomeSkeletonState();
}

class _HomeSkeletonState extends State<HomeSkeleton>
    with SingleTickerProviderStateMixin {
  late final AnimationController _c = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 1300),
  )..repeat();

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return IgnorePointer(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const SizedBox(height: 12),
          // Spotlight banner.
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16),
            child: _Shimmer(
              animation: _c,
              width: double.infinity,
              height: 190,
              radius: 20,
            ),
          ),
          const SizedBox(height: 26),
          _heading(),
          const SizedBox(height: 12),
          // Quick-picks grid.
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16),
            child: Column(
              children: [
                for (var row = 0; row < 3; row++) ...[
                  if (row > 0) const SizedBox(height: 10),
                  Row(
                    children: [
                      Expanded(
                        child: _Shimmer(
                          animation: _c,
                          width: double.infinity,
                          height: 64,
                          radius: 10,
                        ),
                      ),
                      const SizedBox(width: 10),
                      Expanded(
                        child: _Shimmer(
                          animation: _c,
                          width: double.infinity,
                          height: 64,
                          radius: 10,
                        ),
                      ),
                    ],
                  ),
                ],
              ],
            ),
          ),
          for (var strip = 0; strip < 2; strip++) ...[
            const SizedBox(height: 26),
            _heading(),
            const SizedBox(height: 12),
            SizedBox(
              height: 198,
              child: ListView.builder(
                scrollDirection: Axis.horizontal,
                physics: const NeverScrollableScrollPhysics(),
                padding: const EdgeInsets.symmetric(horizontal: 16),
                itemCount: 4,
                itemBuilder: (context, i) => Padding(
                  padding: const EdgeInsets.only(right: 12),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      _Shimmer(
                        animation: _c,
                        width: 150,
                        height: 150,
                        radius: 14,
                      ),
                      const SizedBox(height: 10),
                      _Shimmer(animation: _c, width: 108, height: 12, radius: 6),
                      const SizedBox(height: 6),
                      _Shimmer(animation: _c, width: 68, height: 10, radius: 5),
                    ],
                  ),
                ),
              ),
            ),
          ],
          const SizedBox(height: 120),
        ],
      ),
    );
  }

  Widget _heading() => Padding(
    padding: const EdgeInsets.symmetric(horizontal: 20),
    child: _Shimmer(animation: _c, width: 148, height: 20, radius: 6),
  );
}
