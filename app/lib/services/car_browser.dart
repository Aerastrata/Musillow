import 'package:flutter/foundation.dart';
import 'package:just_audio_background/just_audio_background.dart';

import '../models/track.dart';
import 'app_state.dart';
import 'player_service.dart';

/// Supplies the Android Auto (and Wear/Assistant) browse tree, and turns a
/// tapped leaf item back into a queue on [playerService].
///
/// Scope: the Navidrome/Subsonic music library only — audiobooks use a
/// separate connector and aren't wired into the car UI yet.
///
/// Folder ids are plain strings ("playlists", "album:42", ...); leaf (track)
/// ids append the source track id after `>>>`, e.g. "playlist:7>>>913", so
/// picking a track can rebuild the whole surrounding queue rather than play a
/// single song in isolation.
const _leafSep = '>>>';

void bindCarBrowser() {
  JustAudioBackground.onGetChildren = _getChildren;
  JustAudioBackground.onPlayFromMediaId = _playFromMediaId;
}

MediaItem _albumItem(Album a) => MediaItem(
  id: 'album:${a.id}',
  title: a.name,
  artist: a.artist,
  artUri: a.coverArtUrl != null ? Uri.tryParse(a.coverArtUrl!) : null,
  playable: false,
);

MediaItem _trackItem(String parentId, Track t) => MediaItem(
  id: '$parentId$_leafSep${t.id}',
  title: t.title,
  artist: t.artist,
  album: t.album,
  duration: t.durationSeconds != null
      ? Duration(seconds: t.durationSeconds!)
      : null,
  artUri: t.coverArtUrl != null ? Uri.tryParse(t.coverArtUrl!) : null,
  playable: true,
);

Future<List<MediaItem>> _getChildren(String parentMediaId) async {
  final client = appState.client;
  if (client == null) return const [];
  try {
    switch (parentMediaId) {
      case 'root':
        return const [
          MediaItem(id: 'playlists', title: 'Playlists', playable: false),
          MediaItem(id: 'albums', title: 'Albums', playable: false),
          MediaItem(id: 'artists', title: 'Artists', playable: false),
          MediaItem(id: 'starred', title: 'Starred', playable: false),
        ];
      case 'playlists':
        return (await client.playlists())
            .map(
              (p) => MediaItem(
                id: 'playlist:${p.id}',
                title: p.name,
                artUri: p.coverArtUrl != null
                    ? Uri.tryParse(p.coverArtUrl!)
                    : null,
                playable: false,
              ),
            )
            .toList();
      case 'albums':
        return (await client.albums()).map(_albumItem).toList();
      case 'artists':
        return (await client.artists())
            .map(
              (a) => MediaItem(
                id: 'artist:${a.id}',
                title: a.name,
                artUri: a.coverArtUrl != null
                    ? Uri.tryParse(a.coverArtUrl!)
                    : null,
                playable: false,
              ),
            )
            .toList();
      case 'starred':
        return (await client.starredSongs())
            .map((t) => _trackItem('starred', t))
            .toList();
    }
    if (parentMediaId.startsWith('playlist:')) {
      final id = parentMediaId.substring('playlist:'.length);
      return (await client.playlistTracks(id))
          .map((t) => _trackItem(parentMediaId, t))
          .toList();
    }
    if (parentMediaId.startsWith('album:')) {
      final id = parentMediaId.substring('album:'.length);
      return (await client.albumTracks(id))
          .map((t) => _trackItem(parentMediaId, t))
          .toList();
    }
    if (parentMediaId.startsWith('artist:')) {
      final id = parentMediaId.substring('artist:'.length);
      return (await client.artistAlbums(id)).map(_albumItem).toList();
    }
  } catch (e) {
    debugPrint('car browse failed for $parentMediaId: $e');
  }
  return const [];
}

Future<void> _playFromMediaId(String mediaId) async {
  final client = appState.client;
  if (client == null) return;
  final sep = mediaId.indexOf(_leafSep);
  if (sep < 0) return;
  final parentId = mediaId.substring(0, sep);
  final trackId = mediaId.substring(sep + _leafSep.length);
  try {
    List<Track> tracks;
    String? label;
    if (parentId == 'starred') {
      tracks = await client.starredSongs();
      label = 'Starred';
    } else if (parentId.startsWith('playlist:')) {
      tracks = await client.playlistTracks(
        parentId.substring('playlist:'.length),
      );
      label = 'Playlist';
    } else if (parentId.startsWith('album:')) {
      tracks = await client.albumTracks(parentId.substring('album:'.length));
      label = 'Album';
    } else {
      return;
    }
    final index = tracks.indexWhere((t) => t.id == trackId);
    if (index < 0) return;
    await playerService.playQueue(
      tracks,
      index,
      client: client,
      contextLabel: label,
    );
  } catch (e) {
    debugPrint('car play-from-id failed for $mediaId: $e');
  }
}
