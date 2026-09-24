import 'package:flutter/material.dart';
import 'package:solar_icons/solar_icons.dart';

import '../models/track.dart';
import '../services/app_state.dart';
import '../services/appearance_state.dart';
import '../services/player_service.dart';
import '../theme.dart';
import '../widgets/playlist_actions.dart';
import 'now_playing_screen.dart';
import 'playlist_detail.dart';

/// Square (or circular) network cover with a graceful placeholder.
class _Cover extends StatelessWidget {
  final String? url;
  final double size;
  final double radius;
  final bool circle;
  const _Cover(this.url, {this.size = 52, this.radius = 8, this.circle = false});

  @override
  Widget build(BuildContext context) {
    final borderRadius = BorderRadius.circular(circle ? size : radius);
    return ClipRRect(
      borderRadius: borderRadius,
      child: SizedBox(
        width: size,
        height: size,
        child: url != null
            ? Image.network(
                url!,
                fit: BoxFit.cover,
                gaplessPlayback: true,
                errorBuilder: (_, _, _) => _placeholder(),
                loadingBuilder: (c, child, p) =>
                    p == null ? child : _placeholder(),
              )
            : _placeholder(),
      ),
    );
  }

  Widget _placeholder() => Container(
    color: AppColors.surfaceAlt,
    child: const Icon(
      SolarIconsBold.musicNote,
      color: AppColors.textFaint,
      size: 20,
    ),
  );
}

/// Shared scaffold for the library detail screens.
class _DetailScaffold extends StatelessWidget {
  final String title;
  final Widget child;
  final Widget? action;
  const _DetailScaffold({required this.title, required this.child, this.action});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text(title),
        titleTextStyle: const TextStyle(
          color: AppColors.textPrimary,
          fontSize: 20,
          fontWeight: FontWeight.w800,
        ),
        leading: IconButton(
          icon: const Icon(SolarIconsOutline.altArrowLeft),
          onPressed: () => Navigator.of(context).maybePop(),
        ),
        actions: action != null ? [action!] : null,
      ),
      body: child,
    );
  }
}

/// A rounded search field used to filter a library category.
class _SearchField extends StatelessWidget {
  final String hint;
  final ValueChanged<String> onChanged;
  const _SearchField({required this.hint, required this.onChanged});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 8, 16, 8),
      child: TextField(
        onChanged: onChanged,
        onSubmitted: (_) => FocusScope.of(context).unfocus(),
        textInputAction: TextInputAction.search,
        style: const TextStyle(color: AppColors.textPrimary),
        cursorColor: AppColors.accent,
        decoration: InputDecoration(
          isDense: true,
          hintText: hint,
          hintStyle: const TextStyle(color: AppColors.textFaint),
          prefixIcon: const Icon(
            SolarIconsOutline.magnifier,
            color: AppColors.textMuted,
            size: 20,
          ),
          filled: true,
          fillColor: AppColors.surface,
          contentPadding: const EdgeInsets.symmetric(vertical: 12),
          border: OutlineInputBorder(
            borderRadius: AppRadius.all(14),
            borderSide: BorderSide.none,
          ),
        ),
      ),
    );
  }
}

Widget _centerText(String t) => Padding(
  padding: const EdgeInsets.all(32),
  child: Center(
    child: Text(
      t,
      textAlign: TextAlign.center,
      style: const TextStyle(color: AppColors.textFaint),
    ),
  ),
);

/// A search field on top of an async list, filtering by [matches] as you type.
/// [builder] receives the already-filtered items and returns the scrollable.
class _SearchableList<T> extends StatefulWidget {
  final Future<List<T>> future;
  final String hint;
  final String emptyLabel;
  final bool Function(T item, String query) matches;
  final Widget Function(BuildContext context, List<T> items) builder;
  const _SearchableList({
    required this.future,
    required this.hint,
    required this.emptyLabel,
    required this.matches,
    required this.builder,
  });

  @override
  State<_SearchableList<T>> createState() => _SearchableListState<T>();
}

class _SearchableListState<T> extends State<_SearchableList<T>> {
  String _query = '';

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        _SearchField(
          hint: widget.hint,
          onChanged: (v) => setState(() => _query = v.trim().toLowerCase()),
        ),
        Expanded(
          child: FutureBuilder<List<T>>(
            future: widget.future,
            builder: (context, snap) {
              if (snap.connectionState == ConnectionState.waiting) {
                return Center(
                  child: CircularProgressIndicator(color: AppColors.accent),
                );
              }
              if (snap.hasError) return _centerText("Couldn't load.");
              final all = snap.data ?? const [];
              if (all.isEmpty) return _centerText(widget.emptyLabel);
              final items = _query.isEmpty
                  ? all
                  : all.where((e) => widget.matches(e, _query)).toList();
              if (items.isEmpty) return _centerText('No matches for "$_query".');
              return widget.builder(context, items);
            },
          ),
        ),
      ],
    );
  }
}

/// A flat list of tracks that plays the (filtered) list as a queue on tap and
/// opens the full-screen player. Reused for Songs, an album, and a playlist.
class TrackListScreen extends StatelessWidget {
  final String title;
  final Future<List<Track>> future;
  const TrackListScreen({super.key, required this.title, required this.future});

  @override
  Widget build(BuildContext context) {
    return _DetailScaffold(
      title: title,
      child: _SearchableList<Track>(
        future: future,
        hint: 'Search $title',
        emptyLabel: 'No tracks here yet.',
        matches: (t, q) =>
            t.title.toLowerCase().contains(q) ||
            t.artist.toLowerCase().contains(q),
        builder: (context, tracks) => ListView.builder(
          padding: const EdgeInsets.only(bottom: 140),
          itemCount: tracks.length,
          itemBuilder: (context, i) {
            final t = tracks[i];
            return ListTile(
              leading: _Cover(t.coverArtUrl),
              title: Text(
                t.title,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(color: AppColors.textPrimary),
              ),
              subtitle: Text(
                t.artist,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(color: AppColors.textMuted),
              ),
              onTap: () {
                final client = appState.client;
                if (client == null) return;
                playerService.playQueue(
                  tracks,
                  i,
                  client: client,
                  contextLabel: title,
                );
                Navigator.of(context).push(NowPlayingScreen.route());
              },
            );
          },
        ),
      ),
    );
  }
}

/// A grid of albums. Reused for "all albums" and a single artist's albums.
class AlbumsScreen extends StatelessWidget {
  final String title;
  final Future<List<Album>> future;
  const AlbumsScreen({super.key, required this.title, required this.future});

  @override
  Widget build(BuildContext context) {
    return _DetailScaffold(
      title: title,
      child: _SearchableList<Album>(
        future: future,
        hint: 'Search $title',
        emptyLabel: 'No albums found.',
        matches: (a, q) =>
            a.name.toLowerCase().contains(q) ||
            a.artist.toLowerCase().contains(q),
        builder: (context, albums) => GridView.builder(
          padding: const EdgeInsets.fromLTRB(16, 8, 16, 140),
          gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
            crossAxisCount: 2,
            mainAxisSpacing: 18,
            crossAxisSpacing: 16,
            childAspectRatio: 0.72,
          ),
          itemCount: albums.length,
          itemBuilder: (context, i) {
            final a = albums[i];
            return GestureDetector(
              onTap: () => Navigator.of(context).push(
                MaterialPageRoute(
                  builder: (_) => TrackListScreen(
                    title: a.name,
                    future: appState.client!.albumTracks(a.id),
                  ),
                ),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  LayoutBuilder(
                    builder: (context, c) =>
                        _Cover(a.coverArtUrl, size: c.maxWidth, radius: 14),
                  ),
                  const SizedBox(height: 8),
                  Text(
                    a.name,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                      color: AppColors.textPrimary,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                  Text(
                    a.artist,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                      color: AppColors.textMuted,
                      fontSize: 12,
                    ),
                  ),
                ],
              ),
            );
          },
        ),
      ),
    );
  }
}

/// A list of artists → tap opens that artist's albums.
class ArtistsScreen extends StatelessWidget {
  const ArtistsScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return _DetailScaffold(
      title: 'Artists',
      child: _SearchableList<Artist>(
        future: appState.client!.artists(),
        hint: 'Search Artists',
        emptyLabel: 'No artists found.',
        matches: (a, q) => a.name.toLowerCase().contains(q),
        builder: (context, artists) => ListView.builder(
          padding: const EdgeInsets.only(bottom: 140),
          itemCount: artists.length,
          itemBuilder: (context, i) {
            final a = artists[i];
            return ListTile(
              leading: _Cover(a.coverArtUrl, circle: true),
              title: Text(
                a.name,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(color: AppColors.textPrimary),
              ),
              subtitle: a.albumCount != null
                  ? Text(
                      '${a.albumCount} albums',
                      style: const TextStyle(color: AppColors.textMuted),
                    )
                  : null,
              trailing: const Icon(
                SolarIconsOutline.altArrowRight,
                color: AppColors.textFaint,
              ),
              onTap: () => Navigator.of(context).push(
                MaterialPageRoute(
                  builder: (_) => AlbumsScreen(
                    title: a.name,
                    future: appState.client!.artistAlbums(a.id),
                  ),
                ),
              ),
            );
          },
        ),
      ),
    );
  }
}

/// The user's playlists, with three permanent collections shown prominently at
/// the top (Liked Songs, Liked Albums, Downloads). A search field filters the
/// regular playlists (the pinned rows hide while searching).
class PlaylistsScreen extends StatefulWidget {
  const PlaylistsScreen({super.key});

  @override
  State<PlaylistsScreen> createState() => _PlaylistsScreenState();
}

class _PlaylistsScreenState extends State<PlaylistsScreen> {
  String _query = '';

  void _push(Widget screen) => Navigator.of(
    context,
  ).push(MaterialPageRoute(builder: (_) => screen));

  Future<void> _createPlaylist() async {
    final id = await showCreatePlaylistDialog(context);
    if (id != null && mounted) setState(() {});
  }

  @override
  Widget build(BuildContext context) {
    final client = appState.client!;
    final searching = _query.isNotEmpty;
    return _DetailScaffold(
      title: 'Playlists',
      action: IconButton(
        icon: const Icon(SolarIconsOutline.addSquare),
        tooltip: 'New playlist',
        onPressed: _createPlaylist,
      ),
      child: Column(
        children: [
          _SearchField(
            hint: 'Search Playlists',
            onChanged: (v) => setState(() => _query = v.trim().toLowerCase()),
          ),
          Expanded(
            child: ListView(
              padding: const EdgeInsets.only(bottom: 140),
              children: [
                if (!searching) ...[
                  _PlaylistRow(
                    icon: appearanceState.likeIcon.filled,
                    color: const Color(0xFFFF5A7A),
                    title: 'Liked Songs',
                    subtitle: 'Playlist',
                    onTap: () => _push(
                      TrackListScreen(
                        title: 'Liked Songs',
                        future: client.starredSongs(),
                      ),
                    ),
                  ),
                  _PlaylistRow(
                    icon: appearanceState.likeIcon.outline,
                    color: AppColors.accent,
                    title: 'Liked Albums',
                    subtitle: 'Albums',
                    onTap: () => _push(
                      AlbumsScreen(
                        title: 'Liked Albums',
                        future: client.starredAlbums(),
                      ),
                    ),
                  ),
                  _PlaylistRow(
                    icon: SolarIconsBold.download,
                    color: AppColors.orange,
                    title: 'Downloads',
                    subtitle: 'Downloads',
                    onTap: () => ScaffoldMessenger.of(context).showSnackBar(
                      const SnackBar(
                        content: Text('Downloads — coming soon'),
                        duration: Duration(seconds: 1),
                      ),
                    ),
                  ),
                ],
                FutureBuilder<List<Playlist>>(
                  future: client.playlists(),
                  builder: (context, snap) {
                    final all = snap.data ?? const [];
                    final lists = searching
                        ? all
                              .where(
                                (p) => p.name.toLowerCase().contains(_query),
                              )
                              .toList()
                        : all;
                    if (searching && lists.isEmpty) {
                      return _centerText('No matches for "$_query".');
                    }
                    return Column(
                      children: [
                        for (final p in lists)
                          _PlaylistRow(
                            icon: SolarIconsBold.playlist,
                            color: AppColors.teal,
                            coverUrl: p.coverArtUrl,
                            title: p.name,
                            subtitle: p.subtitle,
                            onTap: () => _push(
                              PlaylistDetailScreen(
                                playlist: p,
                                onChanged: () {
                                  if (mounted) setState(() {});
                                },
                              ),
                            ),
                          ),
                      ],
                    );
                  },
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

/// A playlist-style row: a rounded, colored icon "cover", title, and subtitle.
class _PlaylistRow extends StatelessWidget {
  final IconData icon;
  final Color color;
  final String title;
  final String subtitle;
  final VoidCallback onTap;

  /// When set, the row shows this network cover instead of the colored icon.
  final String? coverUrl;

  const _PlaylistRow({
    required this.icon,
    required this.color,
    required this.title,
    required this.subtitle,
    required this.onTap,
    this.coverUrl,
  });

  @override
  Widget build(BuildContext context) {
    return ListTile(
      contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
      onTap: onTap,
      leading: coverUrl != null
          ? _Cover(coverUrl, size: 52, radius: 10)
          : Container(
              width: 52,
              height: 52,
              decoration: BoxDecoration(
                color: color.withValues(alpha: 0.9),
                borderRadius: AppRadius.all(10),
              ),
              child: Icon(icon, color: Colors.white, size: 26),
            ),
      title: Text(
        title,
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
        style: const TextStyle(
          color: AppColors.textPrimary,
          fontWeight: FontWeight.w700,
        ),
      ),
      subtitle: Text(
        subtitle,
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
        style: const TextStyle(color: AppColors.textMuted),
      ),
    );
  }
}

/// A searchable list of the library's genres; tapping opens that genre's songs.
class GenresScreen extends StatelessWidget {
  const GenresScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final client = appState.client!;
    return _DetailScaffold(
      title: 'Genres',
      child: _SearchableList<String>(
        future: client.genres(),
        hint: 'Search genres',
        emptyLabel: 'No genres found.',
        matches: (g, q) => g.toLowerCase().contains(q),
        builder: (context, genres) => ListView.builder(
          padding: const EdgeInsets.only(bottom: 140),
          itemCount: genres.length,
          itemBuilder: (context, i) {
            final g = genres[i];
            return ListTile(
              contentPadding:
                  const EdgeInsets.symmetric(horizontal: 16, vertical: 2),
              leading: Container(
                width: 44,
                height: 44,
                decoration: BoxDecoration(
                  color: AppColors.accent.withValues(alpha: 0.18),
                  borderRadius: AppRadius.all(10),
                ),
                child: Icon(
                  SolarIconsBold.musicNotes,
                  color: AppColors.accent,
                  size: 22,
                ),
              ),
              title: Text(
                g,
                style: const TextStyle(
                  color: AppColors.textPrimary,
                  fontWeight: FontWeight.w600,
                ),
              ),
              onTap: () => Navigator.of(context).push(
                MaterialPageRoute(
                  builder: (_) => TrackListScreen(
                    title: g,
                    future: client.songsByGenre(g),
                  ),
                ),
              ),
            );
          },
        ),
      ),
    );
  }
}

/// Navidrome internet-radio stations. Empty when none are configured.
class RadioScreen extends StatelessWidget {
  const RadioScreen({super.key});

  void _play(BuildContext context, Track station) {
    playerService.playQueue(
      [station],
      0,
      client: appState.client,
      contextLabel: 'Radio',
    );
    Navigator.of(context).push(NowPlayingScreen.route());
  }

  @override
  Widget build(BuildContext context) {
    final client = appState.client!;
    return _DetailScaffold(
      title: 'Radio',
      child: FutureBuilder<List<Track>>(
        future: client.internetRadioStations(),
        builder: (context, snap) {
          if (snap.connectionState == ConnectionState.waiting) {
            return Center(
              child: CircularProgressIndicator(color: AppColors.accent),
            );
          }
          final stations = snap.data ?? const <Track>[];
          if (stations.isEmpty) {
            return const Padding(
              padding: EdgeInsets.all(32),
              child: Center(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(SolarIconsOutline.radio,
                        size: 44, color: AppColors.textFaint),
                    SizedBox(height: 14),
                    Text(
                      'No radio stations yet',
                      style: TextStyle(
                        color: AppColors.textPrimary,
                        fontSize: 17,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                    SizedBox(height: 6),
                    Text(
                      'Add internet radio stations in Navidrome and they\'ll '
                      'show up here.',
                      textAlign: TextAlign.center,
                      style: TextStyle(color: AppColors.textMuted, fontSize: 14),
                    ),
                  ],
                ),
              ),
            );
          }
          return ListView.builder(
            padding: const EdgeInsets.only(top: 8, bottom: 140),
            itemCount: stations.length,
            itemBuilder: (context, i) {
              final s = stations[i];
              return ListTile(
                contentPadding:
                    const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
                leading: Container(
                  width: 48,
                  height: 48,
                  decoration: BoxDecoration(
                    color: const Color(0xFFFF5A7A).withValues(alpha: 0.18),
                    borderRadius: AppRadius.all(12),
                  ),
                  child: const Icon(SolarIconsBold.radio,
                      color: Color(0xFFFF5A7A), size: 24),
                ),
                title: Text(
                  s.title,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    color: AppColors.textPrimary,
                    fontWeight: FontWeight.w600,
                  ),
                ),
                subtitle: const Text(
                  'Live radio',
                  style: TextStyle(color: AppColors.textMuted),
                ),
                onTap: () => _play(context, s),
              );
            },
          );
        },
      ),
    );
  }
}
