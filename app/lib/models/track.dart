/// A single playable track. Mirrors the core fields the app receives from
/// Navidrome's Subsonic API.
class Track {
  final String id;
  final String title;
  final String artist;
  final String? album;

  /// Subsonic cover-art id (used to build a getCoverArt URL). Distinct from the
  /// resolved [coverArtUrl] so the client can attach auth params when needed.
  final String? coverArtId;
  final String? coverArtUrl;

  /// Track length in seconds, when known.
  final int? durationSeconds;

  /// A fully-resolved stream URL. When set, the player uses it directly instead
  /// of building a Subsonic stream URL from [id] — used for Audiobookshelf,
  /// whose audio comes from a different server.
  final String? streamUrl;

  const Track({
    required this.id,
    required this.title,
    required this.artist,
    this.album,
    this.coverArtId,
    this.coverArtUrl,
    this.durationSeconds,
    this.streamUrl,
  });

  Track copyWith({String? coverArtUrl}) => Track(
    id: id,
    title: title,
    artist: artist,
    album: album,
    coverArtId: coverArtId,
    coverArtUrl: coverArtUrl ?? this.coverArtUrl,
    durationSeconds: durationSeconds,
    streamUrl: streamUrl,
  );

  /// Serialize for local persistence (resume-last-session).
  Map<String, dynamic> toJson() => {
    'id': id,
    'title': title,
    'artist': artist,
    'album': album,
    'coverArtId': coverArtId,
    'coverArtUrl': coverArtUrl,
    'durationSeconds': durationSeconds,
    'streamUrl': streamUrl,
  };

  /// Inverse of [toJson].
  factory Track.fromJson(Map<String, dynamic> j) => Track(
    id: j['id'].toString(),
    title: (j['title'] ?? 'Unknown').toString(),
    artist: (j['artist'] ?? 'Unknown artist').toString(),
    album: j['album'] as String?,
    coverArtId: j['coverArtId'] as String?,
    coverArtUrl: j['coverArtUrl'] as String?,
    durationSeconds: j['durationSeconds'] as int?,
    streamUrl: j['streamUrl'] as String?,
  );

  /// Parse a Subsonic `song`/`entry`/`child` JSON object.
  factory Track.fromSubsonic(Map<String, dynamic> json) => Track(
    id: json['id'].toString(),
    title: (json['title'] ?? 'Unknown').toString(),
    artist: (json['artist'] ?? 'Unknown artist').toString(),
    album: json['album']?.toString(),
    coverArtId: json['coverArt']?.toString(),
    durationSeconds: json['duration'] is int ? json['duration'] as int : null,
  );
}

/// One line of a song's lyrics. [start] is the millisecond offset into the
/// track when synced lyrics are available, otherwise null.
class LyricLine {
  final int? start;
  final String text;
  const LyricLine({this.start, required this.text});

  factory LyricLine.fromJson(Map<String, dynamic> j) => LyricLine(
    start: j['start'] is int ? j['start'] as int : null,
    text: (j['text'] ?? '').toString(),
  );
}

/// A song's lyrics. [synced] is true when every line carries a [LyricLine.start]
/// offset, letting the UI highlight and seek line-by-line.
class Lyrics {
  final bool synced;
  final List<LyricLine> lines;
  const Lyrics({required this.synced, required this.lines});

  bool get isEmpty => lines.isEmpty;

  factory Lyrics.fromJson(Map<String, dynamic> j) => Lyrics(
    synced: j['synced'] == true,
    lines: ((j['lines'] as List?) ?? const [])
        .map((l) => LyricLine.fromJson(l as Map<String, dynamic>))
        .toList(),
  );
}

/// A Subsonic album (metadata only; fetch its tracks separately).
class Album {
  final String id;
  final String name;
  final String artist;
  final String? coverArtUrl;
  final int? songCount;

  const Album({
    required this.id,
    required this.name,
    required this.artist,
    this.coverArtUrl,
    this.songCount,
  });
}

/// A Subsonic artist (metadata only).
class Artist {
  final String id;
  final String name;
  final String? coverArtUrl;
  final int? albumCount;

  const Artist({
    required this.id,
    required this.name,
    this.coverArtUrl,
    this.albumCount,
  });
}

/// A named collection of tracks (a Navidrome playlist, a shuffle, etc.).
class Playlist {
  final String id;
  final String name;
  final String subtitle;
  final List<Track> tracks;

  /// Resolved cover image URL (a custom cover, or Navidrome's auto mosaic).
  /// Null when the playlist has no art and should fall back to an icon.
  final String? coverArtUrl;

  const Playlist({
    required this.id,
    required this.name,
    required this.subtitle,
    this.tracks = const [],
    this.coverArtUrl,
  });
}
