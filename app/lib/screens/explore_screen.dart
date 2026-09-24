import 'dart:async';

import 'package:flutter/material.dart';
import 'package:solar_icons/solar_icons.dart';

import '../models/track.dart';
import '../services/app_state.dart';
import '../services/automation_client.dart';
import '../services/automation_state.dart';
import '../services/player_service.dart';
import '../services/identify_service.dart';
import '../services/preview_player.dart';
import '../widgets/identify_sheet.dart';
import '../theme.dart';
import 'now_playing_screen.dart';
import '../services/icon_registry.dart';
import '../widgets/app_icon.dart';

/// Explore = search the wider catalogue, preview a 30s clip to find the right
/// version, then request it (queued for SoulSync to download).
class ExploreScreen extends StatefulWidget {
  const ExploreScreen({super.key});

  @override
  State<ExploreScreen> createState() => _ExploreScreenState();
}

class _ExploreScreenState extends State<ExploreScreen> {
  final _controller = TextEditingController();
  Timer? _debounce;
  Timer? _poll;
  String _query = '';
  bool _loading = false;
  String? _error;
  List<CatalogResult> _results = const [];
  // Live download status keyed by artist|title.
  final Map<String, DownloadStatus> _statuses = {};

  // Explore landing page (shown when the search box is empty).
  ExploreHome? _home;
  bool _homeLoading = true;
  String? _homeError;

  @override
  void initState() {
    super.initState();
    _loadHome();
    _refreshStatuses();
  }

  Future<void> _loadHome() async {
    final client = automationState.client;
    final music = appState.client;
    if (client == null || music == null) {
      if (!mounted) return;
      setState(() {
        _homeLoading = false;
        _homeError = 'Connect a music library to explore.';
      });
      return;
    }
    setState(() {
      _homeLoading = _home == null;
      _homeError = null;
    });
    try {
      final h = await client.exploreHome(music);
      if (!mounted) return;
      setState(() {
        _home = h;
        _homeLoading = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _homeError = e.toString();
        _homeLoading = false;
      });
    }
  }

  @override
  void dispose() {
    _debounce?.cancel();
    _poll?.cancel();
    _controller.dispose();
    super.dispose();
  }

  Future<void> _refreshStatuses() async {
    final client = automationState.client;
    if (client == null) return;
    try {
      final list = await client.downloadStatuses();
      if (!mounted) return;
      setState(() {
        for (final s in list) {
          // A track can have several requests (e.g. an old failure + a later
          // success). Keep the most-resolved one so "already downloaded" wins
          // over an earlier failure.
          final existing = _statuses[s.key];
          if (existing == null || _prio(s) >= _prio(existing)) {
            _statuses[s.key] = s;
          }
        }
      });
    } catch (_) {}
    _ensurePolling();
  }

  static int _prio(DownloadStatus s) {
    if (s.done) return 3; // completed — you have it
    if (s.inFlight) return 2; // searching / downloading
    return 1; // failed / no_match
  }

  /// Poll while anything is still in flight, so downloading → done updates live.
  void _ensurePolling() {
    final active = _statuses.values.any((s) => s.inFlight);
    if (active) {
      _poll ??= Timer.periodic(
        const Duration(seconds: 4),
        (_) => _refreshStatuses(),
      );
    } else {
      _poll?.cancel();
      _poll = null;
    }
  }

  void _onChanged(String v) {
    _debounce?.cancel();
    _debounce = Timer(const Duration(milliseconds: 450), () => _search(v));
  }

  Future<void> _search(String q) async {
    q = q.trim();
    if (q == _query) return;
    _query = q;
    if (q.isEmpty) {
      setState(() {
        _results = const [];
        _error = null;
        _loading = false;
      });
      return;
    }
    final client = automationState.client;
    if (client == null) {
      setState(() => _error = 'Sign in to search.');
      return;
    }
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final r = await client.catalogSearch(q);
      if (!mounted || q != _query) return;
      setState(() {
        _results = r;
        _loading = false;
      });
      _refreshStatuses(); // reflect any already-requested/downloaded tracks
    } catch (e) {
      if (!mounted || q != _query) return;
      setState(() {
        _error = e.toString();
        _loading = false;
      });
    }
  }

  /// "What's playing?" — record a clip, identify it, and land the answer in
  /// search so it shares the preview / owned / request-download flow.
  Future<void> _identify() async {
    FocusScope.of(context).unfocus();
    identifyService.reset();
    final match = await showModalBottomSheet<CatalogResult>(
      context: context,
      backgroundColor: Colors.transparent,
      isScrollControlled: true,
      isDismissible: false,
      enableDrag: false,
      builder: (_) => const IdentifySheet(),
    );
    if (match == null || !mounted) return;
    final q = '${match.artist} ${match.title}';
    _debounce?.cancel();
    _controller.text = q;
    _query = q;
    setState(() {
      _results = identifyService.results;
      _error = null;
      _loading = false;
    });
    _refreshStatuses();
  }

  Future<void> _request(CatalogResult r) async {
    final client = automationState.client;
    if (client == null) return;
    final key = DownloadStatus.keyFor(r.artist, r.title);
    // Optimistic: show it as in-flight immediately, then poll for real status.
    setState(() => _statuses[key] = DownloadStatus(
      artist: r.artist,
      title: r.title,
      status: 'searching',
    ));
    try {
      await client.requestDownload(r);
      _ensurePolling();
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Finding "${r.title}"…'),
          duration: const Duration(seconds: 2),
        ),
      );
    } catch (e) {
      if (!mounted) return;
      setState(() => _statuses.remove(key));
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Request failed: $e')),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(20, 8, 20, 12),
          child: TextField(
            controller: _controller,
            onChanged: _onChanged,
            onSubmitted: (v) {
              FocusScope.of(context).unfocus(); // drop the keyboard on enter
              _search(v);
            },
            textInputAction: TextInputAction.search,
            style: const TextStyle(color: AppColors.textPrimary),
            decoration: InputDecoration(
              hintText: 'Search any song to add…',
              hintStyle: const TextStyle(color: AppColors.textFaint),
              prefixIcon: const Icon(
                SolarIconsOutline.magnifier,
                color: AppColors.textMuted,
              ),
              suffixIcon: _controller.text.isEmpty
                  ? IconButton(
                      tooltip: "What's playing?",
                      icon: AppIcon(
                        IconSlot.identify,
                        color: AppColors.accent,
                      ),
                      onPressed: _identify,
                    )
                  : IconButton(
                      icon: const Icon(
                        SolarIconsOutline.closeCircle,
                        color: AppColors.textMuted,
                      ),
                      onPressed: () {
                        _controller.clear();
                        _search('');
                      },
                    ),
              filled: true,
              fillColor: AppColors.surface,
              contentPadding: const EdgeInsets.symmetric(vertical: 4),
              border: OutlineInputBorder(
                borderRadius: AppRadius.all(16),
                borderSide: BorderSide.none,
              ),
            ),
          ),
        ),
        Expanded(child: _body()),
      ],
    );
  }

  Widget _body() {
    if (_loading) {
      return Center(
        child: CircularProgressIndicator(color: AppColors.accent),
      );
    }
    if (_error != null) {
      return _hint(SolarIconsOutline.dangerTriangle, _error!);
    }
    if (_query.isEmpty) {
      return _homeView();
    }
    if (_results.isEmpty) {
      return _hint(SolarIconsOutline.magnifier, 'No results for "$_query".');
    }
    return ListenableBuilder(
      listenable: previewPlayer,
      builder: (context, _) => ListView.builder(
        padding: const EdgeInsets.only(bottom: 140),
        itemCount: _results.length,
        itemBuilder: (context, i) {
          final r = _results[i];
          return _ResultRow(
            result: r,
            status: _statuses[DownloadStatus.keyFor(r.artist, r.title)],
            onRequest: () => _request(r),
          );
        },
      ),
    );
  }

  Widget _hint(IconData icon, String text) => Center(
    child: Padding(
      padding: const EdgeInsets.all(32),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, color: AppColors.textFaint, size: 40),
          const SizedBox(height: 12),
          Text(
            text,
            textAlign: TextAlign.center,
            style: const TextStyle(color: AppColors.textMuted, fontSize: 15),
          ),
        ],
      ),
    ),
  );

  // --- Explore landing page ---------------------------------------------

  static const _kGenres = [
    'Cinematic', 'Epic', 'Electronic', 'Pop', 'Hip-Hop', 'Rock',
    'Lo-fi', 'Classical', 'Metal', 'R&B', 'Ambient', 'Soundtrack',
  ];

  Widget _homeView() {
    if (_homeLoading) {
      return Center(
        child: CircularProgressIndicator(color: AppColors.accent),
      );
    }
    final h = _home;
    if (h == null) {
      return _hint(
        SolarIconsOutline.compass,
        _homeError ?? 'Nothing to explore yet.',
      );
    }
    return RefreshIndicator(
      onRefresh: _loadHome,
      color: AppColors.accent,
      backgroundColor: AppColors.surface,
      child: ListenableBuilder(
        listenable: previewPlayer,
        builder: (context, _) => ListView(
          padding: const EdgeInsets.only(top: 4, bottom: 150),
          children: [
            _genres(),
            if (h.australia.isNotEmpty) ...[
              _header('Top 20 in Australia'),
              _trackRail(h.australia),
            ],
            if (h.worldwide.isNotEmpty) ...[
              _header('Top 20 Worldwide'),
              _trackRail(h.worldwide),
            ],
            if (h.topArtists.isNotEmpty) ...[
              _header('Your Top Artists'),
              _artistRail(h.topArtists),
            ],
            if (h.worldArtists.isNotEmpty) ...[
              _header('Top Artists Worldwide'),
              _artistRail(h.worldArtists),
            ],
            if (h.newReleases.isNotEmpty) ...[
              _header('New Releases For You'),
              _releaseRail(h.newReleases),
            ],
          ],
        ),
      ),
    );
  }

  Widget _header(String t) => Padding(
    padding: const EdgeInsets.fromLTRB(20, 20, 20, 10),
    child: Text(
      t,
      style: const TextStyle(
        color: AppColors.textPrimary,
        fontSize: 19,
        fontWeight: FontWeight.w800,
      ),
    ),
  );

  Widget _genres() => Padding(
    padding: const EdgeInsets.fromLTRB(16, 6, 16, 4),
    child: Wrap(
      spacing: 8,
      runSpacing: 8,
      children: [
        for (final g in _kGenres)
          ActionChip(
            label: Text(g),
            onPressed: () {
              _controller.text = g;
              FocusScope.of(context).unfocus();
              _search(g);
            },
            backgroundColor: AppColors.surface,
            labelStyle: const TextStyle(
              color: AppColors.textPrimary,
              fontWeight: FontWeight.w600,
            ),
            side: BorderSide.none,
          ),
      ],
    ),
  );

  Widget _trackRail(List<CatalogResult> items) => SizedBox(
    height: 212,
    child: ListView.builder(
      scrollDirection: Axis.horizontal,
      padding: const EdgeInsets.symmetric(horizontal: 16),
      itemCount: items.length,
      itemBuilder: (context, i) => _trackCard(items[i]),
    ),
  );

  Widget _trackCard(CatalogResult r) {
    final st = _statuses[DownloadStatus.keyFor(r.artist, r.title)];
    return SizedBox(
      width: 138,
      child: Padding(
        padding: const EdgeInsets.only(right: 12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            GestureDetector(
              onTap: () => _playChart(r), // charts play the full track
              child: Stack(
                children: [
                  ClipRRect(
                    borderRadius: AppRadius.all(14),
                    child: SizedBox(
                      width: 138,
                      height: 138,
                      child: _art(r.artworkUrl),
                    ),
                  ),
                  if (r.owned)
                    const Positioned.fill(
                      child: Center(
                        child: Icon(
                          SolarIconsBold.playCircle,
                          color: Colors.white70,
                          size: 30,
                        ),
                      ),
                    ),
                  Positioned(top: 6, right: 6, child: _miniAction(r, st)),
                ],
              ),
            ),
            const SizedBox(height: 6),
            Text(
              r.title,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(
                color: AppColors.textPrimary,
                fontWeight: FontWeight.w600,
                fontSize: 13,
              ),
            ),
            Text(
              r.artist,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(color: AppColors.textMuted, fontSize: 12),
            ),
          ],
        ),
      ),
    );
  }

  Widget _miniAction(CatalogResult r, DownloadStatus? st) {
    // In the permanent library (kept, or just requested) → done.
    final done = r.kept || (st?.done ?? false);
    final busy = st?.inFlight ?? false;
    Widget inner;
    if (done) {
      inner = const Icon(SolarIconsBold.checkCircle, color: AppColors.teal, size: 22);
    } else if (busy) {
      inner = const SizedBox(
        width: 16,
        height: 16,
        child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white),
      );
    } else {
      inner = const Icon(SolarIconsBold.addCircle, color: Colors.white, size: 22);
    }
    return GestureDetector(
      onTap: (done || busy) ? null : () => _addChart(r),
      child: Container(
        padding: const EdgeInsets.all(4),
        decoration: BoxDecoration(
          color: Colors.black.withValues(alpha: 0.5),
          shape: BoxShape.circle,
        ),
        child: inner,
      ),
    );
  }

  /// "+" on a chart track = add it to the permanent library. If it's already
  /// downloaded in the rotating charts folder, keep it (an instant move);
  /// otherwise download it (with live status).
  Future<void> _addChart(CatalogResult r) async {
    final client = automationState.client;
    if (client == null) return;
    if (r.owned) {
      final key = DownloadStatus.keyFor(r.artist, r.title);
      setState(() => _statuses[key] = DownloadStatus(
        artist: r.artist,
        title: r.title,
        status: 'completed',
      ));
      await client.keepTrack(r.artist, r.title);
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Added "${r.title}" to your library'),
          duration: const Duration(seconds: 2),
        ),
      );
    } else {
      _request(r); // full download into the library, with live status
    }
  }

  /// Charts are pre-downloaded, so tapping plays the full track (no preview).
  Future<void> _playChart(CatalogResult r) async {
    final music = appState.client;
    if (music == null) return;
    if (!r.owned) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Still downloading — check back shortly'),
          duration: Duration(seconds: 2),
        ),
      );
      return;
    }
    try {
      final hits = await music.search3Songs('${r.artist} ${r.title}', count: 20);
      final match = _bestMatch(hits, r);
      if (match == null || !mounted) return;
      playerService.playQueue([match], 0, client: music, contextLabel: 'Charts');
      Navigator.of(context).push(NowPlayingScreen.route());
    } catch (_) {}
  }

  Set<String> _toks(String s) =>
      s.toLowerCase().split(RegExp(r'[^a-z0-9]+')).where((x) => x.isNotEmpty).toSet();

  Track? _bestMatch(List<Track> hits, CatalogResult r) {
    final rt = _toks(r.title);
    final ra = _toks(r.artist);
    for (final h in hits) {
      if (_toks(h.title).containsAll(rt) &&
          _toks(h.artist).intersection(ra).isNotEmpty) {
        return h;
      }
    }
    return hits.isNotEmpty ? hits.first : null;
  }

  Widget _artistRail(List<ArtistCard> items) => SizedBox(
    height: 152,
    child: ListView.builder(
      scrollDirection: Axis.horizontal,
      padding: const EdgeInsets.symmetric(horizontal: 16),
      itemCount: items.length,
      itemBuilder: (context, i) {
        final a = items[i];
        return GestureDetector(
          onTap: () {
            _controller.text = a.name;
            FocusScope.of(context).unfocus();
            _search(a.name);
          },
          child: SizedBox(
            width: 110,
            child: Padding(
              padding: const EdgeInsets.only(right: 12),
              child: Column(
                children: [
                  ClipOval(
                    child: SizedBox(
                      width: 98,
                      height: 98,
                      child: _art(a.coverArtUrl),
                    ),
                  ),
                  const SizedBox(height: 8),
                  Text(
                    a.name,
                    maxLines: 2,
                    textAlign: TextAlign.center,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                      color: AppColors.textPrimary,
                      fontSize: 12,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ],
              ),
            ),
          ),
        );
      },
    ),
  );

  Widget _releaseRail(List<ReleaseCard> items) => SizedBox(
    height: 204,
    child: ListView.builder(
      scrollDirection: Axis.horizontal,
      padding: const EdgeInsets.symmetric(horizontal: 16),
      itemCount: items.length,
      itemBuilder: (context, i) {
        final a = items[i];
        return GestureDetector(
          onTap: () {
            _controller.text = a.title;
            FocusScope.of(context).unfocus();
            _search(a.title);
          },
          child: SizedBox(
            width: 138,
            child: Padding(
              padding: const EdgeInsets.only(right: 12),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  ClipRRect(
                    borderRadius: AppRadius.all(14),
                    child: SizedBox(
                      width: 138,
                      height: 138,
                      child: _art(a.artworkUrl),
                    ),
                  ),
                  const SizedBox(height: 6),
                  Text(
                    a.title,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                      color: AppColors.textPrimary,
                      fontWeight: FontWeight.w600,
                      fontSize: 13,
                    ),
                  ),
                  Text(
                    [a.artist, if (a.year != null) a.year!].join(' · '),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                      color: AppColors.textMuted,
                      fontSize: 12,
                    ),
                  ),
                ],
              ),
            ),
          ),
        );
      },
    ),
  );

  Widget _art(String? url, {bool playing = false}) {
    final img = url != null
        ? Image.network(url, fit: BoxFit.cover, errorBuilder: (_, _, _) => _fallbackArt())
        : _fallbackArt();
    if (!playing) return img;
    return Stack(
      fit: StackFit.expand,
      children: [
        img,
        ColoredBox(color: Colors.black.withValues(alpha: 0.4)),
      ],
    );
  }

  Widget _fallbackArt() => const ColoredBox(
    color: AppColors.surfaceAlt,
    child: Icon(SolarIconsBold.musicNote, color: AppColors.textFaint, size: 24),
  );
}

const _kErr = Color(0xFFFF5A7A);

class _ResultRow extends StatelessWidget {
  final CatalogResult result;
  final DownloadStatus? status;
  final VoidCallback onRequest;
  const _ResultRow({
    required this.result,
    required this.status,
    required this.onRequest,
  });

  bool get _have => result.owned || (status?.done ?? false);

  /// A short status word appended to the subtitle for clarity.
  String? get _statusWord {
    if (_have) return 'In your library';
    final s = status;
    if (s == null) return null;
    if (s.inFlight) {
      return s.status == 'downloading' ? 'Downloading…' : 'Finding…';
    }
    if (s.status == 'no_match') return 'Not found';
    if (s.failed) return 'Failed';
    return null;
  }

  @override
  Widget build(BuildContext context) {
    final playing = previewPlayer.isCurrent(result.id);
    final word = _statusWord;
    final subtitle = [
      result.artist,
      if (result.album != null) result.album!,
    ].join(' · ');
    return ListTile(
      contentPadding: const EdgeInsets.symmetric(horizontal: 20, vertical: 4),
      leading: _Artwork(url: result.artworkUrl, playing: playing),
      title: Text(
        result.title,
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
        style: const TextStyle(
          color: AppColors.textPrimary,
          fontWeight: FontWeight.w600,
        ),
      ),
      subtitle: Row(
        children: [
          Flexible(
            child: Text(
              subtitle,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(color: AppColors.textMuted),
            ),
          ),
          if (word != null)
            Text(
              '  ·  $word',
              maxLines: 1,
              style: TextStyle(
                color: _have
                    ? AppColors.teal
                    : (status?.failed ?? false)
                    ? _kErr
                    : AppColors.accent,
                fontWeight: FontWeight.w600,
              ),
            ),
        ],
      ),
      onTap: () => previewPlayer.toggle(result),
      trailing: _trailing(),
    );
  }

  Widget _trailing() {
    final s = status;
    if (_have) {
      return const Padding(
        padding: EdgeInsets.all(12),
        child: Icon(SolarIconsBold.checkCircle, color: AppColors.teal),
      );
    }
    if (s != null && s.inFlight) {
      return Padding(
        padding: const EdgeInsets.all(14),
        child: SizedBox(
          width: 20,
          height: 20,
          child: CircularProgressIndicator(
            strokeWidth: 2.2,
            color: AppColors.accent,
          ),
        ),
      );
    }
    if (s != null && s.failed) {
      return IconButton(
        onPressed: onRequest,
        tooltip: 'Retry',
        icon: const Icon(SolarIconsOutline.refresh, color: _kErr),
      );
    }
    return IconButton(
      onPressed: onRequest,
      tooltip: 'Request download',
      icon: AppIcon(
        IconSlot.download,
        color: AppColors.accent,
      ),
    );
  }
}

/// Cover thumbnail that shows a play/pause overlay for previewing.
class _Artwork extends StatelessWidget {
  final String? url;
  final bool playing;
  const _Artwork({required this.url, required this.playing});

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: 52,
      height: 52,
      child: ClipRRect(
        borderRadius: AppRadius.all(10),
        child: Stack(
          fit: StackFit.expand,
          children: [
            if (url != null)
              Image.network(url!, fit: BoxFit.cover, errorBuilder: (_, _, _) => _fallback())
            else
              _fallback(),
            Container(color: Colors.black.withValues(alpha: playing ? 0.45 : 0.2)),
            Icon(
              playing ? SolarIconsBold.pause : SolarIconsBold.play,
              color: Colors.white,
              size: 22,
            ),
          ],
        ),
      ),
    );
  }

  Widget _fallback() => const ColoredBox(
    color: AppColors.surfaceAlt,
    child: Icon(SolarIconsBold.musicNote, color: AppColors.textFaint, size: 20),
  );
}
