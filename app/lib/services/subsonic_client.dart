import 'dart:convert';

import 'package:http/http.dart' as http;

import '../models/track.dart';
import 'image_upload.dart';
import 'settings_state.dart';

/// Thrown when the backend responds but reports an error.
class SubsonicException implements Exception {
  final String message;
  SubsonicException(this.message);
  @override
  String toString() => 'SubsonicException: $message';
}

/// The app's music data client.
///
/// Despite the historical name, this no longer speaks to Navidrome directly:
/// it talks only to the Musillow backend, which holds the Navidrome connector
/// and proxies every bit of metadata, audio, and cover art. The phone needs
/// exactly one address — the backend — and one credential — the account JWT.
class SubsonicClient {
  /// Backend base URL (no trailing slash), e.g. https://musillow.netbird:8080.
  final String base;

  /// The active account's JWT, sent as a bearer token (and, for media URLs the
  /// player/image loaders fetch, as a `token` query param).
  final String token;

  final http.Client _http;

  SubsonicClient(this.base, this.token, {http.Client? httpClient})
    : _http = httpClient ?? http.Client();

  Map<String, String> get _headers => {'Authorization': 'Bearer $token'};

  Uri _u(String path, [Map<String, String> q = const {}]) =>
      Uri.parse('$base$path').replace(
        queryParameters: q.isEmpty ? null : q,
      );

  /// Audio stream URL for [songId], proxied through the backend. Carries the
  /// token as a query param so the audio player can fetch it without headers,
  /// and the chosen streaming quality so the backend can transcode down.
  Uri streamUrl(String songId) => _u('/stream/$songId', {
    'token': token,
    if (settingsState.quality.kbps > 0)
      'bitrate': '${settingsState.quality.kbps}',
  });

  /// Cover-art URL, proxied through the backend (token in the query so image
  /// loaders can fetch it without custom headers).
  Uri coverArtUrl(String coverArtId, {int size = 512}) =>
      _u('/cover/$coverArtId', {'size': '$size', 'token': token});

  /// URL of a playlist's custom cover (only valid when one has been set). [v]
  /// is an optional cache-buster so a freshly-changed cover reloads.
  Uri playlistCoverUrl(String playlistId, {int? v}) => _u(
    '/library/playlist-cover/$playlistId',
    {'token': token, if (v != null) 'v': '$v'},
  );

  Future<Map<String, dynamic>> _get(String path, [Map<String, String> q = const {}]) async {
    final res = await _http.get(_u(path, q), headers: _headers);
    if (res.statusCode != 200) {
      String msg = 'HTTP ${res.statusCode}';
      try {
        final b = jsonDecode(res.body);
        if (b is Map && b['detail'] != null) msg = b['detail'].toString();
      } catch (_) {}
      throw SubsonicException(msg);
    }
    return jsonDecode(res.body) as Map<String, dynamic>;
  }

  Future<void> _post(String path) async {
    final res = await _http.post(_u(path), headers: _headers);
    if (res.statusCode != 200) throw SubsonicException('HTTP ${res.statusCode}');
  }

  Map<String, String> get _jsonHeaders =>
      {..._headers, 'Content-Type': 'application/json'};

  Future<Map<String, dynamic>> _postJson(String path, Object body) async {
    final res = await _http.post(
      _u(path),
      headers: _jsonHeaders,
      body: jsonEncode(body),
    );
    if (res.statusCode != 200) throw SubsonicException('HTTP ${res.statusCode}');
    return res.body.isEmpty
        ? const {}
        : jsonDecode(res.body) as Map<String, dynamic>;
  }

  Future<void> _putJson(String path, Object body) async {
    final res = await _http.put(
      _u(path),
      headers: _jsonHeaders,
      body: jsonEncode(body),
    );
    if (res.statusCode != 200) throw SubsonicException('HTTP ${res.statusCode}');
  }

  Future<void> _put(String path) async {
    final res = await _http.put(_u(path), headers: _headers);
    if (res.statusCode != 200) throw SubsonicException('HTTP ${res.statusCode}');
  }

  Future<void> _delete(String path) async {
    final res = await _http.delete(_u(path), headers: _headers);
    if (res.statusCode != 200) throw SubsonicException('HTTP ${res.statusCode}');
  }

  /// Attach a resolved (backend) cover-art URL to a track, if it has cover art.
  Track _withCover(Track t) => t.coverArtId == null
      ? t
      : t.copyWith(coverArtUrl: coverArtUrl(t.coverArtId!).toString());

  List<Track> _songs(dynamic list) => ((list as List?) ?? const [])
      .map((s) => _withCover(Track.fromSubsonic(s as Map<String, dynamic>)))
      .toList();

  /// Verify the backend is reachable and a Navidrome connector is configured.
  Future<void> ping() async {
    final res = await _http.get(_u('/me/connectors'), headers: _headers);
    if (res.statusCode != 200) {
      throw SubsonicException('HTTP ${res.statusCode}');
    }
    final list = jsonDecode(res.body);
    final has = list is List &&
        list.any((c) => (c is Map) && c['kind'] == 'navidrome');
    if (!has) throw SubsonicException('No Navidrome connector configured');
  }

  Future<void> star(String songId) => _post('/library/star/$songId');
  Future<void> unstar(String songId) => _post('/library/unstar/$songId');

  /// Lyrics for [songId] (synced with millisecond offsets when available).
  Future<Lyrics> lyrics(String songId) async {
    final b = await _get('/library/lyrics/$songId');
    return Lyrics.fromJson(b);
  }

  /// Songs Navidrome considers similar to [songId].
  Future<List<Track>> similarSongs(String songId, {int count = 30}) async {
    final b = await _get('/library/similar/$songId', {'count': '$count'});
    return _songs(b['songs']);
  }

  Future<List<Track>> randomSongs({int size = 20}) async {
    final b = await _get('/library/random-songs', {'size': '$size'});
    return _songs(b['songs']);
  }

  Future<List<Track>> search3Songs(String query, {int count = 20}) async {
    final b = await _get('/library/search', {'q': query, 'count': '$count'});
    return _songs(b['songs']);
  }

  Album _albumFrom(Map<String, dynamic> m) => Album(
    id: m['id'].toString(),
    name: (m['name'] ?? m['album'] ?? 'Album').toString(),
    artist: (m['artist'] ?? '').toString(),
    coverArtUrl: m['coverArt'] != null
        ? coverArtUrl(m['coverArt'].toString()).toString()
        : null,
    songCount: m['songCount'] is int ? m['songCount'] as int : null,
  );

  /// Navidrome-configured internet radio stations, as playable [Track]s (their
  /// stream URL plays directly — it's an external station, not backend audio).
  Future<List<Track>> internetRadioStations() async {
    final b = await _get('/library/radio');
    return ((b['stations'] as List?) ?? const [])
        .map((s) {
          final m = s as Map<String, dynamic>;
          return Track(
            id: m['id'].toString(),
            title: (m['name'] ?? 'Station').toString(),
            artist: 'Radio',
            streamUrl: m['streamUrl']?.toString(),
          );
        })
        .where((t) => t.streamUrl != null)
        .toList();
  }

  Future<List<String>> genres() async {
    final b = await _get('/library/genres');
    return ((b['genres'] as List?) ?? const [])
        .map((g) => g.toString())
        .where((s) => s.isNotEmpty)
        .toList();
  }

  Future<List<Track>> songsByGenre(String genre, {int count = 200}) async {
    final b = await _get('/library/genres/${Uri.encodeComponent(genre)}', {
      'count': '$count',
    });
    return _songs(b['songs']);
  }

  /// Resolve a playlist's cover URL: a custom cover when one is set, else
  /// Navidrome's auto-generated art, else null (caller shows a fallback icon).
  String? _playlistCover(Map<String, dynamic> m) {
    if (m['hasCustomCover'] == true) {
      return playlistCoverUrl(m['id'].toString()).toString();
    }
    final art = m['coverArt'];
    return art != null ? coverArtUrl(art.toString()).toString() : null;
  }

  /// The user's playlists as [Playlist]s with metadata but no tracks.
  Future<List<Playlist>> playlists() async {
    final b = await _get('/library/playlists');
    return ((b['playlists'] as List?) ?? const []).map((p) {
      final m = p as Map<String, dynamic>;
      final count = m['songCount'] ?? 0;
      return Playlist(
        id: m['id'].toString(),
        name: (m['name'] ?? 'Playlist').toString(),
        subtitle: '$count tracks',
        coverArtUrl: _playlistCover(m),
      );
    }).toList();
  }

  Future<List<Track>> playlistTracks(String id) async {
    final b = await _get('/library/playlists/$id');
    return _songs(b['songs']);
  }

  /// Create a playlist (optionally seeded with [songIds]); returns its id.
  Future<String> createPlaylist(String name, {List<String> songIds = const []}) async {
    final b = await _postJson('/library/playlists', {
      'name': name,
      'songIds': songIds,
    });
    return b['id'].toString();
  }

  /// Rename and/or replace a playlist's full ordered song list. Passing
  /// [songIds] persists reorders and removals in one call.
  Future<void> updatePlaylist(
    String id, {
    String? name,
    List<String>? songIds,
  }) => _putJson('/library/playlists/$id', {
    'name': ?name,
    'songIds': ?songIds,
  });

  Future<void> addToPlaylist(String id, List<String> songIds) =>
      _postJson('/library/playlists/$id/songs', {'songIds': songIds});

  Future<void> deletePlaylist(String id) =>
      _delete('/library/playlists/$id');

  /// Upload a local image file as the playlist's custom cover.
  Future<void> uploadPlaylistCover(String id, String filePath) async {
    final req = http.MultipartRequest(
      'PUT',
      _u('/library/playlists/$id/cover'),
    )
      ..headers.addAll(_headers)
      ..files.add(
        await http.MultipartFile.fromPath(
          'file',
          filePath,
          contentType: imageMediaType(filePath),
        ),
      );
    final res = await http.Response.fromStream(await _http.send(req));
    if (res.statusCode != 200) {
      throw SubsonicException('HTTP ${res.statusCode}');
    }
  }

  /// Use a song's cover art as the playlist's custom cover.
  Future<void> setPlaylistCoverFromSong(String id, String songId) =>
      _put('/library/playlists/$id/cover-from-song/$songId');

  Future<void> clearPlaylistCover(String id) =>
      _delete('/library/playlists/$id/cover');

  Future<List<Album>> albums({
    String type = 'alphabeticalByName',
    int size = 100,
  }) async {
    final b = await _get('/library/albums', {'type': type, 'size': '$size'});
    return ((b['albums'] as List?) ?? const [])
        .map((a) => _albumFrom(a as Map<String, dynamic>))
        .toList();
  }

  Future<List<Track>> albumTracks(String id) async {
    final b = await _get('/library/albums/$id');
    return _songs(b['songs']);
  }

  Future<List<Artist>> artists() async {
    final b = await _get('/library/artists');
    return ((b['artists'] as List?) ?? const []).map((a) {
      final m = a as Map<String, dynamic>;
      return Artist(
        id: m['id'].toString(),
        name: (m['name'] ?? '').toString(),
        coverArtUrl: m['coverArt'] != null
            ? coverArtUrl(m['coverArt'].toString()).toString()
            : null,
        albumCount: m['albumCount'] is int ? m['albumCount'] as int : null,
      );
    }).toList();
  }

  Future<List<Album>> artistAlbums(String id) async {
    final b = await _get('/library/artists/$id');
    return ((b['albums'] as List?) ?? const [])
        .map((a) => _albumFrom(a as Map<String, dynamic>))
        .toList();
  }

  Future<List<Track>> starredSongs() async {
    final b = await _get('/library/starred');
    return _songs(b['songs']);
  }

  Future<List<Album>> starredAlbums() async {
    final b = await _get('/library/starred');
    return ((b['albums'] as List?) ?? const [])
        .map((a) => _albumFrom(a as Map<String, dynamic>))
        .toList();
  }

  void dispose() => _http.close();
}
