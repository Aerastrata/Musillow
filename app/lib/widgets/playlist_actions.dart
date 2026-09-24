import 'package:flutter/material.dart';
import 'package:solar_icons/solar_icons.dart';

import '../models/track.dart';
import '../services/app_state.dart';
import '../theme.dart';

/// A small square playlist cover (network image, else a fallback icon tile).
class PlaylistCover extends StatelessWidget {
  final String? url;
  final double size;
  final double radius;
  const PlaylistCover({
    super.key,
    required this.url,
    this.size = 52,
    this.radius = 10,
  });

  @override
  Widget build(BuildContext context) {
    return ClipRRect(
      borderRadius: BorderRadius.circular(radius),
      child: SizedBox(
        width: size,
        height: size,
        child: url != null
            ? Image.network(
                url!,
                fit: BoxFit.cover,
                gaplessPlayback: true,
                errorBuilder: (_, _, _) => _fallback(),
                loadingBuilder: (c, child, p) =>
                    p == null ? child : _fallback(),
              )
            : _fallback(),
      ),
    );
  }

  Widget _fallback() => Container(
    color: AppColors.teal.withValues(alpha: 0.9),
    child: const Icon(SolarIconsBold.playlist, color: Colors.white, size: 24),
  );
}

/// Present the "add to playlist" bottom sheet for [songIds]. Lets the user pick
/// an existing playlist or create a new one seeded with these songs.
Future<void> showAddToPlaylistSheet(
  BuildContext context, {
  required List<String> songIds,
}) {
  return showModalBottomSheet<void>(
    context: context,
    backgroundColor: AppColors.surface,
    isScrollControlled: true,
    shape: RoundedRectangleBorder(
      borderRadius: AppRadius.top(24),
    ),
    builder: (_) => _AddToPlaylistSheet(songIds: songIds),
  );
}

/// Prompt for a playlist name and create it (optionally seeded with
/// [seedSongIds]). Returns the new playlist id, or null if cancelled/failed.
Future<String?> showCreatePlaylistDialog(
  BuildContext context, {
  List<String> seedSongIds = const [],
}) async {
  final controller = TextEditingController();
  final name = await showDialog<String>(
    context: context,
    builder: (ctx) => AlertDialog(
      backgroundColor: AppColors.surfaceAlt,
      title: const Text(
        'New playlist',
        style: TextStyle(color: AppColors.textPrimary),
      ),
      content: TextField(
        controller: controller,
        autofocus: true,
        style: const TextStyle(color: AppColors.textPrimary),
        cursorColor: AppColors.accent,
        textCapitalization: TextCapitalization.words,
        decoration: const InputDecoration(
          hintText: 'Playlist name',
          hintStyle: TextStyle(color: AppColors.textFaint),
        ),
        onSubmitted: (v) => Navigator.of(ctx).pop(v.trim()),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(ctx).pop(),
          child: const Text('Cancel', style: TextStyle(color: AppColors.textMuted)),
        ),
        TextButton(
          onPressed: () => Navigator.of(ctx).pop(controller.text.trim()),
          child: Text('Create', style: TextStyle(color: AppColors.accent)),
        ),
      ],
    ),
  );
  if (name == null || name.isEmpty) return null;
  final client = appState.client;
  if (client == null) return null;
  try {
    return await client.createPlaylist(name, songIds: seedSongIds);
  } catch (_) {
    if (context.mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text("Couldn't create playlist")),
      );
    }
    return null;
  }
}

class _AddToPlaylistSheet extends StatefulWidget {
  final List<String> songIds;
  const _AddToPlaylistSheet({required this.songIds});

  @override
  State<_AddToPlaylistSheet> createState() => _AddToPlaylistSheetState();
}

class _AddToPlaylistSheetState extends State<_AddToPlaylistSheet> {
  late Future<List<Playlist>> _future;

  @override
  void initState() {
    super.initState();
    _future = appState.client?.playlists() ?? Future.value(const []);
  }

  Future<void> _addTo(String playlistId, String playlistName) async {
    final client = appState.client;
    if (client == null) return;
    final messenger = ScaffoldMessenger.of(context);
    final navigator = Navigator.of(context);
    try {
      await client.addToPlaylist(playlistId, widget.songIds);
      navigator.pop();
      messenger.showSnackBar(
        SnackBar(
          content: Text('Added to $playlistName'),
          duration: const Duration(seconds: 1),
        ),
      );
    } catch (_) {
      messenger.showSnackBar(
        const SnackBar(content: Text("Couldn't add to playlist")),
      );
    }
  }

  Future<void> _createAndAdd() async {
    final messenger = ScaffoldMessenger.of(context);
    final navigator = Navigator.of(context);
    // Create seeded with the songs directly — no second round-trip.
    final id = await showCreatePlaylistDialog(
      context,
      seedSongIds: widget.songIds,
    );
    if (id == null) return;
    navigator.pop();
    messenger.showSnackBar(
      const SnackBar(
        content: Text('Playlist created'),
        duration: Duration(seconds: 1),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return DraggableScrollableSheet(
      expand: false,
      initialChildSize: 0.55,
      maxChildSize: 0.9,
      builder: (context, controller) => Column(
        children: [
          Container(
            margin: const EdgeInsets.only(top: 10, bottom: 6),
            width: 40,
            height: 4,
            decoration: BoxDecoration(
              color: AppColors.border,
              borderRadius: AppRadius.all(2),
            ),
          ),
          const Padding(
            padding: EdgeInsets.fromLTRB(20, 4, 20, 8),
            child: Align(
              alignment: Alignment.centerLeft,
              child: Text(
                'Add to playlist',
                style: TextStyle(
                  color: AppColors.textPrimary,
                  fontSize: 18,
                  fontWeight: FontWeight.w800,
                ),
              ),
            ),
          ),
          ListTile(
            onTap: _createAndAdd,
            leading: Container(
              width: 52,
              height: 52,
              decoration: BoxDecoration(
                color: AppColors.accent.withValues(alpha: 0.18),
                borderRadius: AppRadius.all(10),
              ),
              child: Icon(SolarIconsOutline.addSquare,
                  color: AppColors.accent),
            ),
            title: const Text(
              'New playlist',
              style: TextStyle(
                color: AppColors.textPrimary,
                fontWeight: FontWeight.w700,
              ),
            ),
          ),
          const Divider(color: AppColors.border, height: 1),
          Expanded(
            child: FutureBuilder<List<Playlist>>(
              future: _future,
              builder: (context, snap) {
                if (snap.connectionState != ConnectionState.done) {
                  return Center(
                    child: CircularProgressIndicator(color: AppColors.accent),
                  );
                }
                final lists = snap.data ?? const <Playlist>[];
                if (lists.isEmpty) {
                  return const Center(
                    child: Padding(
                      padding: EdgeInsets.all(24),
                      child: Text(
                        'No playlists yet — create one above.',
                        style: TextStyle(color: AppColors.textMuted),
                      ),
                    ),
                  );
                }
                return ListView.builder(
                  controller: controller,
                  itemCount: lists.length,
                  itemBuilder: (context, i) {
                    final p = lists[i];
                    return ListTile(
                      leading: PlaylistCover(url: p.coverArtUrl),
                      title: Text(
                        p.name,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                          color: AppColors.textPrimary,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                      subtitle: Text(
                        p.subtitle,
                        style: const TextStyle(color: AppColors.textMuted),
                      ),
                      onTap: () => _addTo(p.id, p.name),
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
