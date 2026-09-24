import 'package:flutter/material.dart';
import 'package:solar_icons/solar_icons.dart';

import '../models/track.dart';
import '../services/abs_state.dart';
import '../services/app_state.dart';
import '../services/automation_client.dart';
import '../services/automation_state.dart';
import '../services/home_layout.dart';
import '../services/player_service.dart';
import '../theme.dart';
import '../widgets/custom_block.dart';
import '../widgets/home_sections.dart';
import '../widgets/quick_picks.dart';
import 'audiobooks_detail.dart';
import 'explore_screen.dart';
import 'library_detail.dart';
import 'playlist_detail.dart';

class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key});

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  late Future<HomeData?> _data;

  @override
  void initState() {
    super.initState();
    _data = _load();
  }

  /// One request for the whole page. The backend composes every section — mixes
  /// included — so this no longer fans out into a dozen library calls.
  Future<HomeData?> _load() async {
    final music = appState.client;
    final auto = automationState.client;
    if (music == null || auto == null) return null;
    return auto.home(music, books: absState.isConnected ? absState.client : null);
  }

  Future<void> _refresh() async {
    setState(() => _data = _load());
    await _data;
  }

  /// A greeting that matches the time of day, the way every music app opens.
  String get _greeting {
    final hour = DateTime.now().hour;
    if (hour < 12) return 'Good morning';
    if (hour < 18) return 'Good afternoon';
    return 'Good evening';
  }

  void _openAlbum(Album album) {
    final client = appState.client;
    if (client == null) return;
    Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => TrackListScreen(
          title: album.name,
          future: client.albumTracks(album.id),
        ),
      ),
    );
  }

  void _openPlaylistDetail(Playlist p) {
    Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => PlaylistDetailScreen(
          playlist: p,
          onChanged: () {
            if (mounted) setState(() => _data = _load());
          },
        ),
      ),
    );
  }

  void _openBook(ContinueBook b) => playBook(context, b.id);

  void _openTracks(String title, List<Track> tracks) {
    Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) =>
            TrackListScreen(title: title, future: Future.value(tracks)),
      ),
    );
  }

  /// Mood cards mix kinds, so where a tap lands depends on what was tapped.
  void _openMoodItem(MoodItem item) {
    final client = appState.client;
    switch (item.type) {
      case 'mix':
        _openTracks(item.title, item.tracks);
      case 'album':
        if (client != null) {
          Navigator.of(context).push(
            MaterialPageRoute(
              builder: (_) => TrackListScreen(
                title: item.title,
                future: client.albumTracks(item.id),
              ),
            ),
          );
        }
      case 'playlist':
        _openPlaylistDetail(
          Playlist(id: item.id, name: item.title, subtitle: item.subtitle),
        );
    }
  }

  /// A new release isn't necessarily in the library — hand it to Explore's
  /// search, which already knows how to preview and request a download.
  void _openRelease(NewRelease r) {
    ScaffoldMessenger.of(context)
      ..clearSnackBars()
      ..showSnackBar(
        SnackBar(
          behavior: SnackBarBehavior.floating,
          content: Text('${r.title} — ${r.artist}'),
          action: SnackBarAction(
            label: 'Find it',
            onPressed: () => Navigator.of(context).push(
              MaterialPageRoute(builder: (_) => const ExploreScreen()),
            ),
          ),
        ),
      );
  }

  void _play(Playlist playlist, int index) {
    final client = appState.client;
    if (client != null) {
      playerService.playQueue(
        playlist.tracks,
        index,
        client: client,
        contextLabel: playlist.name,
      );
    }
  }

  /// Open a generated playlist as a full, scrollable track list.
  void _openPlaylist(Playlist p) {
    Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => TrackListScreen(
          title: p.name,
          future: Future.value(p.tracks),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    // Rebuilt when the arrangement changes, so edits in the layout editor show
    // up on Home the moment you back out of it.
    return ListenableBuilder(
      listenable: homeLayout,
      builder: (context, _) => _page(),
    );
  }

  Widget _page() {
    return RefreshIndicator(
      onRefresh: _refresh,
      color: AppColors.accent,
      backgroundColor: AppColors.surface,
      child: FutureBuilder<HomeData?>(
        future: _data,
        builder: (context, snap) {
          final loading = snap.connectionState == ConnectionState.waiting;
          // Cross-fade the skeleton into the real page so content settles in
          // rather than replacing a spinner all at once.
          return AnimatedSwitcher(
            duration: const Duration(milliseconds: 380),
            switchInCurve: Curves.easeOut,
            child: loading
                ? const _LoadingView(key: ValueKey('loading'))
                : KeyedSubtree(
                    key: const ValueKey('content'),
                    child: _content(snap),
                  ),
          );
        },
      ),
    );
  }

  Widget _content(AsyncSnapshot<HomeData?> snap) {
    final data = snap.data;
    return CustomScrollView(
      physics: const AlwaysScrollableScrollPhysics(),
      slivers: [
        if (snap.hasError)
          SliverFillRemaining(
            hasScrollBody: false,
            child: _Message(
              icon: SolarIconsOutline.cloudCross,
              text: "Couldn't load your library.\n${snap.error}",
            ),
          )
        else if (data == null || data.isEmpty)
          const SliverFillRemaining(
            hasScrollBody: false,
            child: _Message(
              icon: SolarIconsOutline.musicLibrary,
              text: 'No music found yet.\nPull down to refresh.',
            ),
          )
        else ...[
          // The page is whatever the user arranged in the Studio: each enabled
          // module renders itself, in order, and a module with no data to show
          // contributes nothing.
          for (final module in homeLayout.visible)
            if (_widgetFor(module, data) case final w?)
              SliverToBoxAdapter(child: w),
          const SliverToBoxAdapter(child: SizedBox(height: 120)),
        ],
      ],
    );
  }

  /// Render one placed module, or null when it has nothing to show — an empty
  /// row then contributes no gap at all.
  Widget? _widgetFor(HomeModule module, HomeData data) {
    final copy = homeLayout.instanceIndex(module);
    switch (module.type) {
      case HomeModuleType.greeting:
        return _Greeting(text: _greeting, name: data.greetingName);

      case HomeModuleType.spotlight:
        final featured = data.featured;
        if (featured == null || featured.tracks.isEmpty) return null;
        // A second spotlight opens on a different track, so duplicating the
        // module gives you two banners rather than the same one twice.
        return FeaturedSpotlight(
          playlist: featured,
          startIndex: copy,
          onPlay: (i) => _play(featured, i),
        );

      case HomeModuleType.quickPicks:
        if (data.quickPicks.isEmpty) return null;
        return QuickPicksSection(picks: data.quickPicks);

      case HomeModuleType.mixes:
        if (data.mixes.isEmpty) return null;
        return MixRow(playlists: data.mixes, onTap: _openPlaylist);

      case HomeModuleType.continueListening:
        if (data.continueListening.isEmpty) return null;
        return ContinueListeningRow(
          books: data.continueListening,
          onTap: _openBook,
        );

      case HomeModuleType.albumsForYou:
        if (data.albumsForYou.isEmpty) return null;
        return AlbumRow(
          title: 'Albums for you',
          albums: data.albumsForYou,
          onTap: _openAlbum,
        );

      case HomeModuleType.moodRows:
        if (data.moodRows.isEmpty) return null;
        return Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            for (final row in data.moodRows)
              MoodRowSection(row: row, onTap: _openMoodItem),
          ],
        );

      case HomeModuleType.forgottenFaves:
        if (data.forgottenFaves.isEmpty) return null;
        return WideTrackRow(
          title: 'Forgotten faves',
          tracks: data.forgottenFaves,
          onTap: (i) => playerService.playQueue(
            data.forgottenFaves,
            i,
            client: appState.client,
            contextLabel: 'Forgotten faves',
          ),
        );

      case HomeModuleType.newReleases:
        if (data.newReleases.isEmpty) return null;
        return NewReleaseRow(releases: data.newReleases, onTap: _openRelease);

      case HomeModuleType.jumpBackIn:
        if (data.jumpBackIn.isEmpty) return null;
        return AlbumRow(
          title: 'Jump back in',
          albums: data.jumpBackIn,
          onTap: _openAlbum,
        );

      case HomeModuleType.artists:
        if (data.artists.isEmpty) return null;
        return ArtistCircleRow(artists: data.artists);

      case HomeModuleType.playlists:
        if (data.playlists.isEmpty) return null;
        return PlaylistCardRow(
          playlists: data.playlists,
          onTap: _openPlaylistDetail,
        );

      case HomeModuleType.custom:
        final layout = module.layout;
        final source = module.source;
        if (layout == null || source == null) return null;
        final items = _blockItems(source, data);
        if (items.isEmpty) return null;
        return CustomBlock(
          title: module.title,
          layout: layout,
          items: items,
          copy: copy,
        );
    }
  }

  /// Flatten one source into the neutral items a custom block draws.
  ///
  /// Everything here is already in [data] — a custom block is a different view
  /// of the page's existing payload, not another request.
  List<BlockItem> _blockItems(HomeModuleSource source, HomeData data) {
    List<BlockItem> fromAlbums(List<Album> albums) => [
      for (final a in albums)
        BlockItem(
          id: a.id,
          title: a.name,
          subtitle: a.artist,
          artworkUrl: a.coverArtUrl,
          onTap: () => _openAlbum(a),
        ),
    ];
    List<BlockItem> fromPlaylists(List<Playlist> playlists, {bool play = false}) => [
      for (final p in playlists)
        BlockItem(
          id: p.id,
          title: p.name,
          subtitle: p.subtitle,
          // Generated mixes have no cover of their own, so they borrow the
          // first track's — the same fallback the shipped mix row uses.
          artworkUrl: p.coverArtUrl ??
              (p.tracks.isNotEmpty ? p.tracks.first.coverArtUrl : null),
          onTap: () => play ? _openPlaylist(p) : _openPlaylistDetail(p),
        ),
    ];
    List<BlockItem> fromTracks(List<Track> tracks, String label) => [
      for (var i = 0; i < tracks.length; i++)
        BlockItem(
          id: tracks[i].id,
          title: tracks[i].title,
          subtitle: tracks[i].artist,
          artworkUrl: tracks[i].coverArtUrl,
          onTap: () => playerService.playQueue(
            tracks,
            i,
            client: appState.client,
            contextLabel: label,
          ),
        ),
    ];

    return switch (source) {
      HomeModuleSource.albumsForYou => fromAlbums(data.albumsForYou),
      HomeModuleSource.jumpBackIn => fromAlbums(data.jumpBackIn),
      HomeModuleSource.mixes => fromPlaylists(data.mixes, play: true),
      HomeModuleSource.playlists => fromPlaylists(data.playlists),
      HomeModuleSource.quickPicks => fromTracks(data.quickPicks, 'Quick picks'),
      HomeModuleSource.forgottenFaves =>
        fromTracks(data.forgottenFaves, 'Forgotten faves'),
      HomeModuleSource.featured =>
        fromTracks(data.featured?.tracks ?? const [], 'Featured'),
      HomeModuleSource.newReleases => [
        for (final r in data.newReleases)
          BlockItem(
            id: '${r.artist}-${r.title}',
            title: r.title,
            subtitle: [r.artist, if (r.year != null) r.year!].join(' · '),
            artworkUrl: r.artworkUrl,
            onTap: () => _openRelease(r),
          ),
      ],
      HomeModuleSource.artists => [
        for (final a in data.artists)
          BlockItem(
            id: a.name,
            title: a.name,
            subtitle: '',
            artworkUrl: a.coverArtUrl,
            circular: true,
            onTap: () {},
          ),
      ],
    };
  }
}

/// The loading page: the greeting (which needs no data) over a skeleton of the
/// rows to come.
class _LoadingView extends StatelessWidget {
  const _LoadingView({super.key});

  @override
  Widget build(BuildContext context) {
    final hour = DateTime.now().hour;
    final greeting = hour < 12
        ? 'Good morning'
        : hour < 18
        ? 'Good afternoon'
        : 'Good evening';
    return CustomScrollView(
      physics: const AlwaysScrollableScrollPhysics(),
      slivers: [
        SliverToBoxAdapter(
          child: _Greeting(
            text: greeting,
            // Known before the request returns, so the header never pops.
            name: automationState.username ?? '',
          ),
        ),
        const SliverToBoxAdapter(child: HomeSkeleton()),
      ],
    );
  }
}

/// The time-of-day greeting that opens the page.
class _Greeting extends StatelessWidget {
  final String text;
  final String name;
  const _Greeting({required this.text, required this.name});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 8, 20, 2),
      child: Text(
        name.isEmpty ? text : '$text, $name',
        style: const TextStyle(
          fontSize: 24,
          fontWeight: FontWeight.w800,
          color: AppColors.textPrimary,
        ),
      ),
    );
  }
}

class _Message extends StatelessWidget {
  final IconData icon;
  final String text;
  const _Message({required this.icon, required this.text});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.all(32),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(icon, size: 44, color: AppColors.textFaint),
          const SizedBox(height: 12),
          Text(
            text,
            textAlign: TextAlign.center,
            style: const TextStyle(color: AppColors.textFaint),
          ),
        ],
      ),
    );
  }
}
