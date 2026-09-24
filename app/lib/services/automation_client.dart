import 'dart:convert';

import 'package:http/http.dart' as http;

import '../models/track.dart';
import 'abs_client.dart';
import 'image_upload.dart';
import 'subsonic_client.dart';

/// One row of the Quick Picks grid (Replay Mix / Liked but Forgotten / Wildcard).
class QuickPickRow {
  final String source;
  final List<Track> tracks;
  const QuickPickRow(this.source, this.tracks);
}

/// A catalog search hit (external — not necessarily in the library). Carries a
/// 30-second [previewUrl] to confirm the track before requesting a download.
class CatalogResult {
  final String id;
  final String title;
  final String artist;
  final String? album;
  final String? artworkUrl;
  final String? previewUrl;
  final String? year;

  /// True when this track's full audio is available (in the library or the
  /// rotating charts folder).
  final bool owned;

  /// True when it's been kept in the permanent library (survives chart rotation).
  final bool kept;

  const CatalogResult({
    required this.id,
    required this.title,
    required this.artist,
    this.album,
    this.artworkUrl,
    this.previewUrl,
    this.year,
    this.owned = false,
    this.kept = false,
  });

  factory CatalogResult.fromJson(Map<String, dynamic> j) => CatalogResult(
    id: (j['id'] ?? '').toString(),
    title: (j['title'] ?? 'Unknown').toString(),
    artist: (j['artist'] ?? 'Unknown artist').toString(),
    album: j['album'] as String?,
    artworkUrl: j['artworkUrl'] as String?,
    previewUrl: j['previewUrl'] as String?,
    year: j['year']?.toString(),
    owned: j['owned'] == true,
    kept: j['kept'] == true,
  );
}

/// Live status of a download request (from the server's /requests).
class DownloadStatus {
  final String artist;
  final String title;
  final String status; // pending|searching|downloading|completed|no_match|failed

  const DownloadStatus({
    required this.artist,
    required this.title,
    required this.status,
  });

  /// Key used to match a request back to a search result.
  static String keyFor(String artist, String title) =>
      '${artist.toLowerCase().trim()}|${title.toLowerCase().trim()}';
  String get key => keyFor(artist, title);

  bool get inFlight =>
      status == 'pending' || status == 'searching' || status == 'downloading';
  bool get done => status == 'completed';
  bool get failed => status == 'no_match' || status == 'failed';

  factory DownloadStatus.fromJson(Map<String, dynamic> j) => DownloadStatus(
    artist: (j['artist'] ?? '').toString(),
    title: (j['title'] ?? '').toString(),
    status: (j['status'] ?? '').toString(),
  );
}

/// A top-artist card for the Explore home.
class ArtistCard {
  final String name;
  final String? coverArtUrl;
  const ArtistCard({required this.name, this.coverArtUrl});
}

/// A recent-release (album) card for the Explore home.
class ReleaseCard {
  final String title;
  final String artist;
  final String? artworkUrl;
  final String? year;
  const ReleaseCard({
    required this.title,
    required this.artist,
    this.artworkUrl,
    this.year,
  });
  factory ReleaseCard.fromJson(Map<String, dynamic> j) => ReleaseCard(
    title: (j['title'] ?? '').toString(),
    artist: (j['artist'] ?? '').toString(),
    artworkUrl: j['artworkUrl'] as String?,
    year: j['year']?.toString(),
  );
}

/// Everything the Explore landing page shows.
class ExploreHome {
  final List<CatalogResult> australia;
  final List<CatalogResult> worldwide;
  final List<ArtistCard> topArtists; // the user's own
  final List<ArtistCard> worldArtists; // charting worldwide
  final List<ReleaseCard> newReleases;
  const ExploreHome({
    required this.australia,
    required this.worldwide,
    required this.topArtists,
    required this.worldArtists,
    required this.newReleases,
  });
}


/// A part-finished audiobook for the home screen's Continue listening row.
class ContinueBook {
  final String id;
  final String title;
  final String author;
  final String coverUrl;

  /// 0–1 through the book.
  final double progress;
  const ContinueBook({
    required this.id,
    required this.title,
    required this.author,
    required this.coverUrl,
    required this.progress,
  });
}

/// One card in a mood row. Rows deliberately mix kinds — a genre is somewhere
/// you browse, so a "Classical" row carries a classical mix, whole classical
/// playlists, and classical albums side by side.
class MoodItem {
  /// `mix` | `playlist` | `album`
  final String type;
  final String id;
  final String title;
  final String subtitle;
  final String? coverUrl;

  /// Populated for `mix` items, which play straight from the card.
  final List<Track> tracks;

  const MoodItem({
    required this.type,
    required this.id,
    required this.title,
    required this.subtitle,
    this.coverUrl,
    this.tracks = const [],
  });
}

/// A genre-led row of mixed cards.
class MoodRow {
  final String title;
  final List<MoodItem> items;
  const MoodRow({required this.title, required this.items});
}

/// An upcoming or recent release by an artist the user follows.
class NewRelease {
  final String title;
  final String artist;
  final String? artworkUrl;
  final String? year;
  const NewRelease({
    required this.title,
    required this.artist,
    this.artworkUrl,
    this.year,
  });
}

/// Everything the home screen shows, composed by the backend in one response.
class HomeData {
  final String greetingName;

  /// The spotlight playlist. The banner slides through these one at a time.
  final Playlist? featured;
  final List<Track> quickPicks;
  final List<Playlist> mixes;
  final List<Album> albumsForYou;
  final List<MoodRow> moodRows;
  final List<Track> forgottenFaves;
  final List<NewRelease> newReleases;
  final List<Album> jumpBackIn;
  final List<Artist> artists;
  final List<ContinueBook> continueListening;
  final List<Playlist> playlists;

  const HomeData({
    required this.greetingName,
    required this.featured,
    required this.quickPicks,
    required this.mixes,
    required this.albumsForYou,
    required this.moodRows,
    required this.forgottenFaves,
    required this.newReleases,
    required this.jumpBackIn,
    required this.artists,
    required this.continueListening,
    required this.playlists,
  });

  bool get isEmpty =>
      featured == null &&
      quickPicks.isEmpty &&
      mixes.isEmpty &&
      albumsForYou.isEmpty &&
      moodRows.isEmpty &&
      forgottenFaves.isEmpty &&
      newReleases.isEmpty &&
      jumpBackIn.isEmpty &&
      artists.isEmpty &&
      continueListening.isEmpty &&
      playlists.isEmpty;
}

class AutomationException implements Exception {
  final String message;
  AutomationException(this.message);
  @override
  String toString() => message;
}

String _errorDetail(http.Response r, String fallback) {
  try {
    final body = jsonDecode(r.body);
    if (body is Map && body['detail'] != null) return body['detail'].toString();
  } catch (_) {}
  return '$fallback (HTTP ${r.statusCode})';
}

/// Client for the Musillow backend (JWT accounts, per-user recs + signals).
///
/// The backend returns Navidrome song objects (ids + coverArt ids), so covers
/// and playback resolve through the app's own [SubsonicClient].
class AutomationClient {
  final String base; // normalized, no trailing slash
  final String? token; // JWT bearer
  final http.Client _http;

  AutomationClient(this.base, {this.token, http.Client? httpClient})
    : _http = httpClient ?? http.Client();

  static String normalize(String url) {
    var b = url.trim();
    if (b.endsWith('/')) b = b.substring(0, b.length - 1);
    return b;
  }

  Map<String, String> get _headers =>
      token != null ? {'Authorization': 'Bearer $token'} : const {};

  // --- Auth (static: no token yet) --------------------------------------

  static Future<String> _auth(
    String base,
    String path,
    Map<String, dynamic> body,
    String fallback, {
    http.Client? httpClient,
  }) async {
    final client = httpClient ?? http.Client();
    try {
      final r = await client
          .post(
            Uri.parse('$base$path'),
            headers: {'content-type': 'application/json'},
            body: jsonEncode(body),
          )
          .timeout(const Duration(seconds: 15));
      if (r.statusCode != 200) throw AutomationException(_errorDetail(r, fallback));
      return (jsonDecode(r.body)['access_token']).toString();
    } finally {
      if (httpClient == null) client.close();
    }
  }

  static Future<String> login(String base, String username, String password) =>
      _auth(base, '/auth/login', {
        'username': username,
        'password': password,
      }, 'Login failed');

  static Future<String> register(
    String base,
    String username,
    String password,
  ) => _auth(base, '/auth/register', {
    'username': username,
    'password': password,
  }, 'Registration failed');

  // --- Authed calls -----------------------------------------------------

  /// Push a service's credentials so the server can reach it on this account's
  /// behalf. [kind] is `navidrome` or `abs`; the server validates the login
  /// before storing it, so a bad credential fails here rather than silently.
  Future<void> putConnector(
    String kind,
    String baseUrl,
    String username,
    String password,
  ) async {
    final r = await _http.put(
      Uri.parse('$base/me/connectors'),
      headers: {..._headers, 'content-type': 'application/json'},
      body: jsonEncode({
        'kind': kind,
        'baseUrl': baseUrl,
        'username': username,
        'secret': password,
      }),
    );
    if (r.statusCode != 200) {
      throw AutomationException(_errorDetail(r, 'Could not save connector'));
    }
  }

  Future<void> putNavidromeConnector(
    String baseUrl,
    String username,
    String password,
  ) => putConnector('navidrome', baseUrl, username, password);

  Future<void> putAbsConnector(
    String baseUrl,
    String username,
    String password,
  ) => putConnector('abs', baseUrl, username, password);

  /// Forget a stored connector (`navidrome` | `abs`) for this account.
  Future<void> deleteConnector(String kind) async {
    final r = await _http.delete(
      Uri.parse('$base/me/connectors/$kind'),
      headers: _headers,
    );
    if (r.statusCode != 200) {
      throw AutomationException(_errorDetail(r, 'Could not remove connector'));
    }
  }

  /// The connectors configured for this account, keyed by kind.
  Future<Map<String, ({String baseUrl, String username})>> connectors() async {
    final r = await _http.get(
      Uri.parse('$base/me/connectors'),
      headers: _headers,
    );
    if (r.statusCode != 200) {
      throw AutomationException(_errorDetail(r, 'Could not load connectors'));
    }
    final list = jsonDecode(r.body) as List;
    return {
      for (final e in list.cast<Map<String, dynamic>>())
        (e['kind'] ?? '').toString(): (
          baseUrl: (e['baseUrl'] ?? '').toString(),
          username: (e['username'] ?? '').toString(),
        ),
    };
  }

  Future<Map<String, dynamic>> me() async {
    final r = await _http.get(Uri.parse('$base/auth/me'), headers: _headers);
    if (r.statusCode != 200) {
      throw AutomationException(_errorDetail(r, 'Could not load profile'));
    }
    return jsonDecode(r.body) as Map<String, dynamic>;
  }

  Future<Map<String, dynamic>> updateMe({
    String? username,
    String? email,
    String? password,
  }) async {
    final body = <String, dynamic>{};
    if (username != null) body['username'] = username;
    if (email != null) body['email'] = email;
    if (password != null && password.isNotEmpty) body['password'] = password;
    final r = await _http.patch(
      Uri.parse('$base/auth/me'),
      headers: {..._headers, 'content-type': 'application/json'},
      body: jsonEncode(body),
    );
    if (r.statusCode != 200) {
      throw AutomationException(_errorDetail(r, 'Update failed'));
    }
    return jsonDecode(r.body) as Map<String, dynamic>;
  }

  // --- Profile picture ---------------------------------------------------

  /// URL of a profile picture, for any account with a [base] and [token] —
  /// the token identifies whose picture is served, so this works for accounts
  /// that aren't the active one without standing up a client for each. The
  /// token rides in the query so `Image.network` can fetch it without headers;
  /// [v] is the picture's version, which changes on every replacement so a new
  /// one isn't masked by a cached copy of the old.
  static Uri avatarUriFor(String base, String token, {int v = 0}) =>
      Uri.parse('$base/auth/me/avatar').replace(
        queryParameters: {'token': token, if (v > 0) 'v': '$v'},
      );

  /// This client's account's profile-picture URL.
  Uri avatarUrl({int v = 0}) => avatarUriFor(base, token ?? '', v: v);

  /// Upload a local image file as the account's profile picture. Returns the
  /// updated profile (including the new avatar version).
  Future<Map<String, dynamic>> uploadAvatar(String filePath) async {
    final req = http.MultipartRequest('PUT', Uri.parse('$base/auth/me/avatar'))
      ..headers.addAll(_headers)
      ..files.add(
        await http.MultipartFile.fromPath(
          'file',
          filePath,
          contentType: imageMediaType(filePath),
        ),
      );
    final r = await http.Response.fromStream(await _http.send(req));
    if (r.statusCode != 200) {
      throw AutomationException(_errorDetail(r, 'Could not upload picture'));
    }
    return jsonDecode(r.body) as Map<String, dynamic>;
  }

  /// Drop the profile picture; the coloured initial takes over again.
  Future<Map<String, dynamic>> deleteAvatar() async {
    final r = await _http.delete(
      Uri.parse('$base/auth/me/avatar'),
      headers: _headers,
    );
    if (r.statusCode != 200) {
      throw AutomationException(_errorDetail(r, 'Could not remove picture'));
    }
    return jsonDecode(r.body) as Map<String, dynamic>;
  }

  Track _track(Map<String, dynamic> m, SubsonicClient music) {
    final t = Track.fromSubsonic(m);
    final cover = m['coverArt']?.toString();
    return cover != null
        ? t.copyWith(coverArtUrl: music.coverArtUrl(cover).toString())
        : t;
  }

  /// The whole home screen in one request.
  ///
  /// Everything arrives pre-composed by the backend, including the rotating
  /// mixes and the spotlight; covers are resolved here because only the client
  /// knows its own media URLs. [books] is optional — audiobook rows are skipped
  /// when the account has no Audiobookshelf connector.
  Future<HomeData> home(SubsonicClient music, {AudiobookshelfClient? books}) async {
    final r = await _http.get(Uri.parse('$base/home'), headers: _headers);
    if (r.statusCode != 200) {
      throw AutomationException(_errorDetail(r, 'Could not load home'));
    }
    final b = jsonDecode(r.body) as Map<String, dynamic>;

    String? cover(dynamic id) =>
        id == null ? null : music.coverArtUrl(id.toString()).toString();

    List<Track> tracksOf(dynamic list) => ((list as List?) ?? const [])
        .map((e) => _track(e as Map<String, dynamic>, music))
        .toList();

    Playlist? playlistOf(dynamic m) {
      if (m is! Map<String, dynamic>) return null;
      final tracks = tracksOf(m['tracks']);
      if (tracks.isEmpty) return null;
      return Playlist(
        id: (m['key'] ?? m['id'] ?? '').toString(),
        name: (m['title'] ?? m['name'] ?? 'Playlist').toString(),
        subtitle: (m['subtitle'] ?? '').toString(),
        tracks: tracks,
      );
    }

    List<Album> albumsOf(String key) =>
        ((b[key] as List?) ?? const []).map((e) {
          final m = e as Map<String, dynamic>;
          return Album(
            id: (m['id'] ?? '').toString(),
            name: (m['name'] ?? 'Album').toString(),
            artist: (m['artist'] ?? '').toString(),
            coverArtUrl: cover(m['coverArt']),
            songCount: m['songCount'] is int ? m['songCount'] as int : null,
          );
        }).toList();

    return HomeData(
      greetingName: (b['greetingName'] ?? '').toString(),
      featured: playlistOf(b['featured']),
      quickPicks: ((b['quickPicks'] as List?) ?? const [])
          .expand((row) => tracksOf((row as Map<String, dynamic>)['tracks']))
          .toList(),
      mixes: ((b['mixes'] as List?) ?? const [])
          .map(playlistOf)
          .whereType<Playlist>()
          .toList(),
      albumsForYou: albumsOf('albumsForYou'),
      moodRows: ((b['moodRows'] as List?) ?? const []).map((e) {
        final m = e as Map<String, dynamic>;
        return MoodRow(
          title: (m['title'] ?? '').toString(),
          items: ((m['items'] as List?) ?? const []).map((x) {
            final i = x as Map<String, dynamic>;
            return MoodItem(
              type: (i['type'] ?? 'album').toString(),
              id: (i['id'] ?? '').toString(),
              title: (i['title'] ?? '').toString(),
              subtitle: (i['subtitle'] ?? '').toString(),
              coverUrl: cover(i['coverArt']),
              tracks: tracksOf(i['tracks']),
            );
          }).toList(),
        );
      }).toList(),
      forgottenFaves: tracksOf(b['forgottenFaves']),
      newReleases: ((b['newReleases'] as List?) ?? const []).map((e) {
        final m = e as Map<String, dynamic>;
        return NewRelease(
          title: (m['title'] ?? '').toString(),
          artist: (m['artist'] ?? '').toString(),
          artworkUrl: m['artworkUrl'] as String?,
          year: m['year']?.toString(),
        );
      }).toList(),
      jumpBackIn: albumsOf('jumpBackIn'),
      artists: ((b['artists'] as List?) ?? const []).map((e) {
        final m = e as Map<String, dynamic>;
        return Artist(
          id: (m['name'] ?? '').toString(),
          name: (m['name'] ?? '').toString(),
          coverArtUrl: cover(m['coverArt']),
        );
      }).toList(),
      continueListening: books == null
          ? const []
          : ((b['continueListening'] as List?) ?? const []).map((e) {
              final m = e as Map<String, dynamic>;
              final id = (m['id'] ?? '').toString();
              return ContinueBook(
                id: id,
                title: (m['title'] ?? 'Audiobook').toString(),
                author: (m['author'] ?? '').toString(),
                coverUrl: books.coverUrl(id),
                progress: (m['progress'] as num?)?.toDouble() ?? 0,
              );
            }).toList(),
      playlists: ((b['playlists'] as List?) ?? const []).map((e) {
        final m = e as Map<String, dynamic>;
        final id = (m['id'] ?? '').toString();
        return Playlist(
          id: id,
          name: (m['name'] ?? 'Playlist').toString(),
          subtitle: m['songCount'] != null ? '${m['songCount']} songs' : '',
          coverArtUrl: m['hasCustomCover'] == true
              ? music.playlistCoverUrl(id).toString()
              : cover(m['coverArt']),
        );
      }).toList(),
    );
  }

  Future<List<QuickPickRow>> quickPicks(SubsonicClient music) async {
    final r = await _http.get(
      Uri.parse('$base/quick-picks'),
      headers: _headers,
    );
    if (r.statusCode != 200) {
      throw AutomationException(_errorDetail(r, 'Quick picks failed'));
    }
    final body = jsonDecode(r.body) as Map<String, dynamic>;
    final rows = (body['rows'] as List?) ?? const [];
    return rows.map((row) {
      final m = row as Map<String, dynamic>;
      final tracks = ((m['tracks'] as List?) ?? const [])
          .map((e) => _track(e as Map<String, dynamic>, music))
          .toList();
      return QuickPickRow((m['source'] ?? '').toString(), tracks);
    }).toList();
  }

  /// Library-backed "made for you" playlists for the home screen (Daily Mix,
  /// On Repeat, Weekly Jams, Forgotten Faves). Covers resolve via [music].
  Future<List<Playlist>> discoverPlaylists(SubsonicClient music) async {
    final r = await _http.get(
      Uri.parse('$base/discover/playlists'),
      headers: _headers,
    );
    if (r.statusCode != 200) {
      throw AutomationException(_errorDetail(r, 'Playlists failed'));
    }
    final body = jsonDecode(r.body) as Map<String, dynamic>;
    return ((body['playlists'] as List?) ?? const []).map((e) {
      final m = e as Map<String, dynamic>;
      final tracks = ((m['tracks'] as List?) ?? const [])
          .map((t) => _track(t as Map<String, dynamic>, music))
          .toList();
      return Playlist(
        id: (m['key'] ?? '').toString(),
        name: (m['title'] ?? 'Playlist').toString(),
        subtitle: (m['subtitle'] ?? '').toString(),
        tracks: tracks,
      );
    }).toList();
  }

  Future<List<Track>> playlist(
    String type,
    SubsonicClient music, {
    int size = 50,
  }) async {
    final r = await _http.get(
      Uri.parse('$base/playlists/$type?size=$size'),
      headers: _headers,
    );
    if (r.statusCode != 200) {
      throw AutomationException(_errorDetail(r, 'Playlist failed'));
    }
    final body = jsonDecode(r.body) as Map<String, dynamic>;
    return ((body['tracks'] as List?) ?? const [])
        .map((e) => _track(e as Map<String, dynamic>, music))
        .toList();
  }

  /// Search the external catalog for candidates (with 30s previews) to confirm
  /// and then request a download.
  Future<List<CatalogResult>> catalogSearch(String query) async {
    final r = await _http.get(
      Uri.parse('$base/catalog/search?q=${Uri.encodeQueryComponent(query)}'),
      headers: _headers,
    );
    if (r.statusCode != 200) {
      throw AutomationException(_errorDetail(r, 'Search failed'));
    }
    final body = jsonDecode(r.body) as Map<String, dynamic>;
    return ((body['results'] as List?) ?? const [])
        .map((e) => CatalogResult.fromJson(e as Map<String, dynamic>))
        .toList();
  }

  /// Identify a song from a recorded audio clip ("what's playing?").
  ///
  /// The backend fingerprints the clip and hands back the match plus ordinary
  /// catalogue candidates for it, so the result drops straight into the same
  /// preview / owned / request-download flow as a typed search.
  Future<({CatalogResult? match, List<CatalogResult> results})> identify(
    String filePath,
  ) async {
    final req = http.MultipartRequest('POST', Uri.parse('$base/identify'))
      ..headers.addAll(_headers)
      ..files.add(await http.MultipartFile.fromPath('file', filePath));
    final r = await http.Response.fromStream(await _http.send(req));
    if (r.statusCode != 200) {
      throw AutomationException(_errorDetail(r, 'Could not identify'));
    }
    final body = jsonDecode(r.body) as Map<String, dynamic>;
    final m = body['match'];
    return (
      match: m is Map<String, dynamic> ? CatalogResult.fromJson(m) : null,
      results: ((body['results'] as List?) ?? const [])
          .map((e) => CatalogResult.fromJson(e as Map<String, dynamic>))
          .toList(),
    );
  }

  /// Keep a downloaded chart track — moves it into the permanent library so it
  /// survives chart rotation. Never throws (best-effort).
  Future<void> keepTrack(String artist, String title) async {
    try {
      await _http.post(
        Uri.parse('$base/explore/keep'),
        headers: {..._headers, 'content-type': 'application/json'},
        body: jsonEncode({'artist': artist, 'title': title}),
      );
    } catch (_) {}
  }

  /// Request a track download (forwarded to SoulSync server-side). Returns the
  /// server's status message.
  Future<String> requestDownload(CatalogResult r) async {
    final resp = await _http.post(
      Uri.parse('$base/catalog/request'),
      headers: {..._headers, 'content-type': 'application/json'},
      body: jsonEncode({
        'title': r.title,
        'artist': r.artist,
        'album': r.album,
      }),
    );
    if (resp.statusCode != 200) {
      throw AutomationException(_errorDetail(resp, 'Request failed'));
    }
    final body = jsonDecode(resp.body) as Map<String, dynamic>;
    return (body['status'] ?? 'requested').toString();
  }

  /// Explore landing page: charts, top artists, new releases. Artist covers are
  /// resolved through the [music] client (Subsonic cover-art ids).
  Future<ExploreHome> exploreHome(SubsonicClient music) async {
    final r = await _http.get(
      Uri.parse('$base/explore/home'),
      headers: _headers,
    );
    if (r.statusCode != 200) {
      throw AutomationException(_errorDetail(r, 'Explore failed'));
    }
    final b = jsonDecode(r.body) as Map<String, dynamic>;
    List<CatalogResult> tracks(String k) => ((b[k] as List?) ?? const [])
        .map((e) => CatalogResult.fromJson(e as Map<String, dynamic>))
        .toList();
    final artists = ((b['topArtists'] as List?) ?? const []).map((e) {
      final m = e as Map<String, dynamic>;
      final ca = m['coverArt']?.toString();
      return ArtistCard(
        name: (m['name'] ?? '').toString(),
        coverArtUrl: ca != null ? music.coverArtUrl(ca).toString() : null,
      );
    }).toList();
    final worldArtists = ((b['worldArtists'] as List?) ?? const []).map((e) {
      final m = e as Map<String, dynamic>;
      return ArtistCard(
        name: (m['name'] ?? '').toString(),
        coverArtUrl: m['artworkUrl'] as String?,
      );
    }).toList();
    final releases = ((b['newReleases'] as List?) ?? const [])
        .map((e) => ReleaseCard.fromJson(e as Map<String, dynamic>))
        .toList();
    return ExploreHome(
      australia: tracks('australia'),
      worldwide: tracks('worldwide'),
      topArtists: artists,
      worldArtists: worldArtists,
      newReleases: releases,
    );
  }

  /// Live status of the user's download requests (to show downloading/done).
  Future<List<DownloadStatus>> downloadStatuses() async {
    final r = await _http.get(
      Uri.parse('$base/requests'),
      headers: _headers,
    );
    if (r.statusCode != 200) {
      throw AutomationException(_errorDetail(r, 'Could not load requests'));
    }
    final body = jsonDecode(r.body) as Map<String, dynamic>;
    return ((body['requests'] as List?) ?? const [])
        .map((e) => DownloadStatus.fromJson(e as Map<String, dynamic>))
        .toList();
  }

  /// Fire-and-forget taste signal. Never throws.
  Future<void> sendSignal(String type, String trackId) async {
    try {
      await _http.post(
        Uri.parse('$base/signals'),
        headers: {..._headers, 'content-type': 'application/json'},
        body: jsonEncode({'type': type, 'trackId': trackId}),
      );
    } catch (_) {
      // Best-effort; ignore transport errors.
    }
  }

  void dispose() => _http.close();
}
