import 'dart:convert';

import 'package:http/http.dart' as http;

import '../models/track.dart';

/// An Audiobookshelf audiobook (list metadata).
class Audiobook {
  final String id;
  final String title;
  final String author;
  final String? seriesName;
  final String coverUrl;
  const Audiobook({
    required this.id,
    required this.title,
    required this.author,
    required this.coverUrl,
    this.seriesName,
  });
}

class AbsAuthor {
  final String id;
  final String name;
  final String? coverUrl;
  final int? numBooks;
  const AbsAuthor({
    required this.id,
    required this.name,
    this.coverUrl,
    this.numBooks,
  });
}

class AbsSeries {
  final String id;
  final String name;
  final List<Audiobook> books;
  const AbsSeries({required this.id, required this.name, required this.books});
}

class AbsLibrary {
  final String id;
  final String name;
  final String mediaType;
  const AbsLibrary({
    required this.id,
    required this.name,
    required this.mediaType,
  });
}

/// Listening stats, as reported by the backend from ABS.
class AbsStats {
  final double totalHours;
  final int itemsFinished;
  final int daysListened;
  const AbsStats({
    required this.totalHours,
    required this.itemsFinished,
    required this.daysListened,
  });
}

class AbsException implements Exception {
  final String message;
  AbsException(this.message);
  @override
  String toString() => message;
}

/// The app's audiobook data client.
///
/// Like [SubsonicClient], this speaks only to the Musillow backend: the backend
/// holds the Audiobookshelf connector and proxies metadata, progress, cover art
/// and audio. The phone knows one address (the backend) and one credential (the
/// account JWT), so the audiobook library follows whichever account is active.
class AudiobookshelfClient {
  /// Backend base URL (no trailing slash).
  final String base;

  /// The active account's JWT.
  final String token;

  final http.Client _http;

  AudiobookshelfClient(this.base, this.token, {http.Client? httpClient})
    : _http = httpClient ?? http.Client();

  Map<String, String> get _headers => {'Authorization': 'Bearer $token'};

  Uri _u(String path, [Map<String, String> q = const {}]) =>
      Uri.parse('$base$path').replace(queryParameters: q.isEmpty ? null : q);

  Future<Map<String, dynamic>> _get(
    String path, [
    Map<String, String> q = const {},
  ]) async {
    final res = await _http.get(_u(path, q), headers: _headers);
    if (res.statusCode != 200) {
      throw AbsException(_detail(res, 'Audiobookshelf request failed'));
    }
    return jsonDecode(res.body) as Map<String, dynamic>;
  }

  static String _detail(http.Response r, String fallback) {
    try {
      final body = jsonDecode(r.body);
      if (body is Map && body['detail'] != null) {
        return body['detail'].toString();
      }
    } catch (_) {}
    return '$fallback (HTTP ${r.statusCode})';
  }

  // ---- Media URLs (token in the query so image/audio loaders can fetch) ----

  // Request a large cover so the full-screen player art isn't upscaled; ABS
  // caps at the original size, so this never upscales.
  String coverUrl(String itemId, {int width = 1024}) =>
      _u('/abs/cover/$itemId', {'token': token, 'width': '$width'}).toString();

  String authorImageUrl(String authorId, {int width = 400}) =>
      _u('/abs/author-image/$authorId', {
        'token': token,
        'width': '$width',
      }).toString();

  String audioUrl(String itemId, String ino) =>
      _u('/abs/audio/$itemId/$ino', {'token': token}).toString();

  // ---- Metadata -----------------------------------------------------------

  /// Whether the backend has a working ABS connector for this account, and the
  /// library to browse by default.
  Future<({bool connected, String? libraryId})> status() async {
    final b = await _get('/abs/status');
    return (
      connected: b['connected'] == true,
      libraryId: b['libraryId']?.toString(),
    );
  }

  Future<List<AbsLibrary>> libraries() async {
    final b = await _get('/abs/libraries');
    return ((b['libraries'] as List?) ?? const [])
        .map(
          (l) => AbsLibrary(
            id: l['id'].toString(),
            name: (l['name'] ?? '').toString(),
            mediaType: (l['mediaType'] ?? 'book').toString(),
          ),
        )
        .toList();
  }

  Audiobook _bookFrom(Map j) {
    final id = j['id'].toString();
    return Audiobook(
      id: id,
      title: (j['title'] ?? 'Untitled').toString(),
      author: (j['author'] ?? '').toString(),
      seriesName: j['seriesName']?.toString(),
      coverUrl: coverUrl(id),
    );
  }

  Future<List<Audiobook>> books(String libraryId) async {
    final b = await _get('/abs/libraries/$libraryId/books');
    return ((b['books'] as List?) ?? const [])
        .map((e) => _bookFrom(e as Map))
        .toList();
  }

  Future<List<AbsAuthor>> authors(String libraryId) async {
    final b = await _get('/abs/libraries/$libraryId/authors');
    return ((b['authors'] as List?) ?? const []).map((e) {
      final a = e as Map;
      final id = a['id'].toString();
      return AbsAuthor(
        id: id,
        name: (a['name'] ?? '').toString(),
        coverUrl: authorImageUrl(id),
        numBooks: a['numBooks'] is int ? a['numBooks'] as int : null,
      );
    }).toList();
  }

  Future<List<AbsSeries>> series(String libraryId) async {
    final b = await _get('/abs/libraries/$libraryId/series');
    return ((b['series'] as List?) ?? const []).map((e) {
      final s = e as Map;
      return AbsSeries(
        id: s['id'].toString(),
        name: (s['name'] ?? '').toString(),
        books: ((s['books'] as List?) ?? const [])
            .map((x) => _bookFrom(x as Map))
            .toList(),
      );
    }).toList();
  }

  Future<List<Audiobook>> authorBooks(String authorId) async {
    final b = await _get('/abs/authors/$authorId/books');
    return ((b['books'] as List?) ?? const [])
        .map((e) => _bookFrom(e as Map))
        .toList();
  }

  /// The playable audio files of a book, as [Track]s with backend stream URLs.
  Future<List<Track>> bookTracks(String itemId) async {
    final b = await _get('/abs/items/$itemId/tracks');
    final cover = coverUrl(itemId);
    return ((b['tracks'] as List?) ?? const []).map((e) {
      final t = e as Map;
      return Track(
        id: t['id'].toString(),
        title: (t['title'] ?? 'Audiobook').toString(),
        artist: (t['artist'] ?? '').toString(),
        coverArtUrl: cover,
        durationSeconds: t['duration'] is int ? t['duration'] as int : null,
        streamUrl: audioUrl(t['itemId'].toString(), t['ino'].toString()),
      );
    }).toList();
  }

  // ---- Progress -----------------------------------------------------------

  /// The saved playback position for a book, in seconds (0 if none).
  Future<double> progressSeconds(String itemId) async {
    try {
      final b = await _get('/abs/items/$itemId/progress');
      return (b['currentTime'] as num?)?.toDouble() ?? 0;
    } catch (_) {
      return 0;
    }
  }

  /// Saves the playback position back through the backend so it resumes across
  /// devices. Best-effort — never throws into the player.
  Future<void> updateProgress(
    String itemId, {
    required double currentTime,
    required double duration,
    bool isFinished = false,
  }) async {
    try {
      await _http.patch(
        _u('/abs/items/$itemId/progress'),
        headers: {..._headers, 'content-type': 'application/json'},
        body: jsonEncode({
          'currentTime': currentTime,
          'duration': duration,
          'isFinished': isFinished,
        }),
      );
    } catch (_) {}
  }

  /// Listening stats (null when the ABS server doesn't provide them).
  Future<AbsStats?> stats() async {
    try {
      final b = await _get('/abs/stats');
      final s = b['stats'];
      if (s is! Map) return null;
      return AbsStats(
        totalHours: (s['totalHours'] as num?)?.toDouble() ?? 0,
        itemsFinished: (s['itemsFinished'] as num?)?.toInt() ?? 0,
        daysListened: (s['daysListened'] as num?)?.toInt() ?? 0,
      );
    } catch (_) {
      return null;
    }
  }

  void dispose() => _http.close();
}
