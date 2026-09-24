import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import 'package:solar_icons/solar_icons.dart';

import '../models/track.dart';
import '../services/app_state.dart';
import '../services/player_service.dart';
import '../theme.dart';
import '../widgets/playlist_actions.dart';
import 'now_playing_screen.dart';

/// An editable view of one of the user's playlists: play/shuffle, reorder by
/// drag, swipe-to-remove, rename, change the cover, or delete the playlist.
/// Persists every membership/order change to Navidrome via the backend.
class PlaylistDetailScreen extends StatefulWidget {
  final Playlist playlist;

  /// Called (after this screen pops) when the playlist was renamed, its cover
  /// changed, or it was deleted — so the list behind it can refresh.
  final VoidCallback? onChanged;

  const PlaylistDetailScreen({
    super.key,
    required this.playlist,
    this.onChanged,
  });

  @override
  State<PlaylistDetailScreen> createState() => _PlaylistDetailScreenState();
}

class _PlaylistDetailScreenState extends State<PlaylistDetailScreen> {
  late String _name = widget.playlist.name;
  List<Track> _tracks = const [];
  bool _loading = true;
  bool _dirty = false; // whether anything changed (for onChanged callback)

  // Cover shown in the header. Bumped with a cache-buster after edits.
  String? _coverUrl;

  String get _id => widget.playlist.id;

  @override
  void initState() {
    super.initState();
    _coverUrl = widget.playlist.coverArtUrl;
    _load();
  }

  Future<void> _load() async {
    final client = appState.client;
    if (client == null) return;
    try {
      final tracks = await client.playlistTracks(_id);
      if (!mounted) return;
      setState(() {
        _tracks = tracks;
        _loading = false;
      });
    } catch (_) {
      if (mounted) setState(() => _loading = false);
    }
  }

  /// Push the current order/membership to the server.
  Future<void> _persistOrder() async {
    final client = appState.client;
    if (client == null) return;
    _dirty = true;
    try {
      await client.updatePlaylist(
        _id,
        songIds: _tracks.map((t) => t.id).toList(),
      );
    } catch (_) {
      _snack("Couldn't save changes");
    }
  }

  void _snack(String msg) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(msg), duration: const Duration(seconds: 1)),
    );
  }

  void _play({bool shuffle = false}) {
    final client = appState.client;
    if (client == null || _tracks.isEmpty) return;
    final list = shuffle ? (List<Track>.of(_tracks)..shuffle()) : _tracks;
    playerService.playQueue(list, 0, client: client, contextLabel: _name);
    Navigator.of(context).push(NowPlayingScreen.route());
  }

  // newIndex arrives already adjusted for the removed item (fork's
  // onReorderItem contract), so it maps straight onto insert().
  void _onReorder(int oldIndex, int newIndex) {
    setState(() {
      final t = _tracks.removeAt(oldIndex);
      _tracks.insert(newIndex, t);
    });
    _persistOrder();
  }

  void _removeAt(int i) {
    setState(() => _tracks.removeAt(i));
    _persistOrder();
  }

  Future<void> _rename() async {
    final controller = TextEditingController(text: _name);
    final newName = await showDialog<String>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: AppColors.surfaceAlt,
        title: const Text('Rename playlist',
            style: TextStyle(color: AppColors.textPrimary)),
        content: TextField(
          controller: controller,
          autofocus: true,
          style: const TextStyle(color: AppColors.textPrimary),
          cursorColor: AppColors.accent,
          onSubmitted: (v) => Navigator.of(ctx).pop(v.trim()),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(),
            child: const Text('Cancel',
                style: TextStyle(color: AppColors.textMuted)),
          ),
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(controller.text.trim()),
            child: Text('Save', style: TextStyle(color: AppColors.accent)),
          ),
        ],
      ),
    );
    if (newName == null || newName.isEmpty || newName == _name) return;
    final client = appState.client;
    if (client == null) return;
    try {
      await client.updatePlaylist(_id, name: newName);
      _dirty = true;
      setState(() => _name = newName);
    } catch (_) {
      _snack("Couldn't rename");
    }
  }

  Future<void> _delete() async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: AppColors.surfaceAlt,
        title: const Text('Delete playlist?',
            style: TextStyle(color: AppColors.textPrimary)),
        content: Text(
          'This removes "$_name" from your library.',
          style: const TextStyle(color: AppColors.textMuted),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(false),
            child: const Text('Cancel',
                style: TextStyle(color: AppColors.textMuted)),
          ),
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(true),
            child: const Text('Delete',
                style: TextStyle(color: Color(0xFFFF5A7A))),
          ),
        ],
      ),
    );
    if (ok != true) return;
    final client = appState.client;
    if (client == null) return;
    try {
      await client.deletePlaylist(_id);
      widget.onChanged?.call();
      if (mounted) Navigator.of(context).pop();
    } catch (_) {
      _snack("Couldn't delete playlist");
    }
  }

  // ---- Cover editing --------------------------------------------------------

  void _refreshCover() {
    _dirty = true;
    setState(() {
      _coverUrl = appState.client
          ?.playlistCoverUrl(_id, v: DateTime.now().millisecondsSinceEpoch)
          .toString();
    });
  }

  Future<void> _changeCover() async {
    await showModalBottomSheet<void>(
      context: context,
      backgroundColor: AppColors.surface,
      shape: RoundedRectangleBorder(
        borderRadius: AppRadius.top(24),
      ),
      builder: (ctx) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const SizedBox(height: 12),
            ListTile(
              leading: const Icon(SolarIconsOutline.gallery,
                  color: AppColors.textPrimary),
              title: const Text('Upload an image',
                  style: TextStyle(color: AppColors.textPrimary)),
              onTap: () {
                Navigator.of(ctx).pop();
                _uploadCover();
              },
            ),
            ListTile(
              leading: const Icon(SolarIconsOutline.musicNote,
                  color: AppColors.textPrimary),
              title: const Text("Use a song's art",
                  style: TextStyle(color: AppColors.textPrimary)),
              enabled: _tracks.isNotEmpty,
              onTap: () {
                Navigator.of(ctx).pop();
                _pickCoverFromSong();
              },
            ),
            ListTile(
              leading: const Icon(SolarIconsOutline.trashBinMinimalistic,
                  color: Color(0xFFFF5A7A)),
              title: const Text('Remove custom cover',
                  style: TextStyle(color: Color(0xFFFF5A7A))),
              onTap: () {
                Navigator.of(ctx).pop();
                _clearCover();
              },
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _uploadCover() async {
    final client = appState.client;
    if (client == null) return;
    final XFile? img = await ImagePicker().pickImage(
      source: ImageSource.gallery,
      maxWidth: 1024,
      maxHeight: 1024,
      imageQuality: 88,
    );
    if (img == null) return;
    try {
      await client.uploadPlaylistCover(_id, img.path);
      _refreshCover();
    } catch (_) {
      _snack("Couldn't upload cover");
    }
  }

  Future<void> _pickCoverFromSong() async {
    final track = await showModalBottomSheet<Track>(
      context: context,
      backgroundColor: AppColors.surface,
      isScrollControlled: true,
      shape: RoundedRectangleBorder(
        borderRadius: AppRadius.top(24),
      ),
      builder: (ctx) => DraggableScrollableSheet(
        expand: false,
        initialChildSize: 0.6,
        maxChildSize: 0.9,
        builder: (ctx, controller) => Column(
          children: [
            const Padding(
              padding: EdgeInsets.fromLTRB(20, 16, 20, 8),
              child: Align(
                alignment: Alignment.centerLeft,
                child: Text('Pick cover art',
                    style: TextStyle(
                        color: AppColors.textPrimary,
                        fontSize: 18,
                        fontWeight: FontWeight.w800)),
              ),
            ),
            Expanded(
              child: ListView.builder(
                controller: controller,
                itemCount: _tracks.length,
                itemBuilder: (ctx, i) {
                  final t = _tracks[i];
                  return ListTile(
                    leading: PlaylistCover(url: t.coverArtUrl, size: 44),
                    title: Text(t.title,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(color: AppColors.textPrimary)),
                    subtitle: Text(t.artist,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(color: AppColors.textMuted)),
                    onTap: () => Navigator.of(ctx).pop(t),
                  );
                },
              ),
            ),
          ],
        ),
      ),
    );
    if (track == null) return;
    final client = appState.client;
    if (client == null) return;
    try {
      await client.setPlaylistCoverFromSong(_id, track.id);
      _refreshCover();
    } catch (_) {
      _snack("Couldn't set cover");
    }
  }

  Future<void> _clearCover() async {
    final client = appState.client;
    if (client == null) return;
    try {
      await client.clearPlaylistCover(_id);
      _dirty = true;
      setState(() => _coverUrl = null);
    } catch (_) {
      _snack("Couldn't remove cover");
    }
  }

  @override
  Widget build(BuildContext context) {
    return PopScope(
      canPop: true,
      onPopInvokedWithResult: (didPop, _) {
        if (didPop && _dirty) widget.onChanged?.call();
      },
      child: Scaffold(
        body: CustomScrollView(
          slivers: [
            SliverAppBar(
              pinned: true,
              backgroundColor: AppColors.background,
              leading: IconButton(
                icon: const Icon(SolarIconsOutline.altArrowLeft),
                onPressed: () => Navigator.of(context).maybePop(),
              ),
              actions: [
                PopupMenuButton<String>(
                  icon: const Icon(SolarIconsOutline.menuDots),
                  color: AppColors.surfaceAlt,
                  shape: RoundedRectangleBorder(
                      borderRadius: AppRadius.all(16)),
                  onSelected: (v) {
                    switch (v) {
                      case 'rename':
                        _rename();
                      case 'cover':
                        _changeCover();
                      case 'delete':
                        _delete();
                    }
                  },
                  itemBuilder: (_) => const [
                    PopupMenuItem(value: 'rename', child: Text('Rename')),
                    PopupMenuItem(value: 'cover', child: Text('Change cover')),
                    PopupMenuItem(value: 'delete', child: Text('Delete playlist')),
                  ],
                ),
              ],
            ),
            SliverToBoxAdapter(child: _header()),
            if (_loading)
              SliverFillRemaining(
                hasScrollBody: false,
                child: Center(
                  child: CircularProgressIndicator(color: AppColors.accent),
                ),
              )
            else if (_tracks.isEmpty)
              const SliverFillRemaining(
                hasScrollBody: false,
                child: Center(
                  child: Text('This playlist is empty.',
                      style: TextStyle(color: AppColors.textMuted)),
                ),
              )
            else
              SliverReorderableList(
                itemCount: _tracks.length,
                onReorderItem: _onReorder,
                itemBuilder: (context, i) {
                  final t = _tracks[i];
                  return _TrackTile(
                    key: ObjectKey(t),
                    track: t,
                    index: i,
                    onRemove: () => _removeAt(i),
                    onTap: () => _play(),
                  );
                },
              ),
            const SliverToBoxAdapter(child: SizedBox(height: 120)),
          ],
        ),
      ),
    );
  }

  Widget _header() {
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 4, 20, 12),
      child: Column(
        children: [
          GestureDetector(
            onTap: _changeCover,
            child: Stack(
              alignment: Alignment.bottomRight,
              children: [
                PlaylistCover(url: _coverUrl, size: 180, radius: 16),
                Container(
                  margin: const EdgeInsets.all(8),
                  padding: const EdgeInsets.all(6),
                  decoration: const BoxDecoration(
                    color: Colors.black54,
                    shape: BoxShape.circle,
                  ),
                  child: const Icon(SolarIconsOutline.pen,
                      color: Colors.white, size: 16),
                ),
              ],
            ),
          ),
          const SizedBox(height: 14),
          Text(
            _name,
            textAlign: TextAlign.center,
            style: const TextStyle(
              color: AppColors.textPrimary,
              fontSize: 22,
              fontWeight: FontWeight.w800,
            ),
          ),
          const SizedBox(height: 2),
          Text(
            '${_tracks.length} ${_tracks.length == 1 ? "song" : "songs"}',
            style: const TextStyle(color: AppColors.textMuted),
          ),
          const SizedBox(height: 14),
          Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              FilledButton.icon(
                onPressed: _tracks.isEmpty ? null : () => _play(),
                style: FilledButton.styleFrom(
                  backgroundColor: AppColors.accent,
                  foregroundColor: Colors.white,
                ),
                icon: const Icon(SolarIconsBold.play, size: 18),
                label: const Text('Play'),
              ),
              const SizedBox(width: 12),
              OutlinedButton.icon(
                onPressed: _tracks.isEmpty ? null : () => _play(shuffle: true),
                style: OutlinedButton.styleFrom(
                  foregroundColor: AppColors.textPrimary,
                  side: const BorderSide(color: AppColors.border),
                ),
                icon: const Icon(SolarIconsOutline.shuffle, size: 18),
                label: const Text('Shuffle'),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

/// A reorderable, swipe-to-remove track row in the playlist editor.
class _TrackTile extends StatelessWidget {
  final Track track;
  final int index;
  final VoidCallback onRemove;
  final VoidCallback onTap;
  const _TrackTile({
    super.key,
    required this.track,
    required this.index,
    required this.onRemove,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return Dismissible(
      key: ObjectKey(track),
      direction: DismissDirection.endToStart,
      background: Container(
        alignment: Alignment.centerRight,
        padding: const EdgeInsets.only(right: 24),
        color: const Color(0xFFFF5A7A).withValues(alpha: 0.18),
        child: const Icon(SolarIconsOutline.trashBinMinimalistic,
            color: Color(0xFFFF5A7A)),
      ),
      onDismissed: (_) => onRemove(),
      child: ListTile(
        leading: PlaylistCover(url: track.coverArtUrl, size: 44, radius: 8),
        title: Text(
          track.title,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: const TextStyle(color: AppColors.textPrimary),
        ),
        subtitle: Text(
          track.artist,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: const TextStyle(color: AppColors.textMuted),
        ),
        trailing: ReorderableDragStartListener(
          index: index,
          child: const Icon(SolarIconsOutline.hamburgerMenu,
              color: AppColors.textMuted, size: 20),
        ),
        onTap: onTap,
      ),
    );
  }
}
