import 'dart:async';

import 'package:flutter/material.dart';

import '../services/abs_state.dart';
import '../services/app_state.dart';
import '../theme.dart';
import 'audiobooks_detail.dart';
import 'library_detail.dart';
import 'settings_screen.dart';
import '../services/icon_registry.dart';
import '../widgets/app_icon.dart';

/// One entry in the library grid.
class _LibCategory {
  final String label;
  final Color color;
  final IconSlot icon;
  const _LibCategory(this.label, this.color, this.icon);
}

final _categories = <_LibCategory>[
  _LibCategory('Songs', AppColors.teal, IconSlot.libSongs),
  _LibCategory('Playlists', const Color(0xFF4FD07A), IconSlot.libPlaylists),
  _LibCategory('Albums', const Color(0xFF5B9CFF), IconSlot.libAlbums),
  _LibCategory('Artists', AppColors.accent, IconSlot.libArtists),
  _LibCategory('Genres', const Color(0xFFB57BFF), IconSlot.libGenres),
  _LibCategory('Radio', const Color(0xFFFF5A7A), IconSlot.libRadio),
  _LibCategory('Audio Books', const Color(0xFFF5A623), IconSlot.libBooks),
  _LibCategory('Authors', AppColors.orange, IconSlot.libAuthors),
];

/// Library: a scrollable grid of compact category cards (image-3 style).
class LibraryScreen extends StatelessWidget {
  const LibraryScreen({super.key});

  void _open(BuildContext context, String label) {
    // Audiobook categories come from Audiobookshelf, not Navidrome.
    if (label == 'Audio Books' || label == 'Authors') {
      if (!absState.isConnected) {
        _promptConnectAbs(context, label);
        return;
      }
      final screen = label == 'Audio Books'
          ? const AudioBooksScreen()
          : const AbsAuthorsScreen();
      Navigator.of(context).push(MaterialPageRoute(builder: (_) => screen));
      return;
    }

    final client = appState.client;
    if (client == null) return;
    Widget? screen;
    switch (label) {
      case 'Songs':
        screen = TrackListScreen(
          title: 'Songs',
          future: client.randomSongs(size: 200),
        );
      case 'Albums':
        screen = AlbumsScreen(title: 'Albums', future: client.albums());
      case 'Artists':
        screen = const ArtistsScreen();
      case 'Playlists':
        screen = const PlaylistsScreen();
      case 'Genres':
        screen = const GenresScreen();
      case 'Radio':
        screen = const RadioScreen();
      default:
        return;
    }
    Navigator.of(context).push(MaterialPageRoute(builder: (_) => screen!));
  }

  void _promptConnectAbs(BuildContext context, String label) {
    final messenger = ScaffoldMessenger.of(context);
    // Floating so it isn't hidden behind the bottom nav + mini-player.
    messenger
      ..clearSnackBars()
      ..showSnackBar(
        SnackBar(
          behavior: SnackBarBehavior.floating,
          content: Text('Connect Audiobookshelf to use $label'),
          duration: const Duration(seconds: 3),
          action: SnackBarAction(
            label: 'Connect',
            onPressed: () => Navigator.of(context).push(
              MaterialPageRoute(builder: (_) => const SettingsScreen()),
            ),
          ),
        ),
      );
    // Force the dismissal ourselves: when the device has animations disabled,
    // a SnackBar's own auto-hide timer never starts (its reveal animation never
    // reports "completed"), so `duration` is ignored and it sits forever.
    Timer(const Duration(seconds: 3), () => messenger.removeCurrentSnackBar());
  }

  @override
  Widget build(BuildContext context) {
    return GridView.builder(
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 120),
      gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
        crossAxisCount: 2,
        childAspectRatio: 1.7,
        crossAxisSpacing: 12,
        mainAxisSpacing: 12,
      ),
      itemCount: _categories.length,
      itemBuilder: (context, i) => _CategoryTile(
        category: _categories[i],
        onTap: () => _open(context, _categories[i].label),
      ),
    );
  }
}

class _CategoryTile extends StatelessWidget {
  final _LibCategory category;
  final VoidCallback onTap;
  const _CategoryTile({required this.category, required this.onTap});

  @override
  Widget build(BuildContext context) {
    final color = category.color;
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        borderRadius: AppRadius.all(16),
        child: Ink(
          decoration: BoxDecoration(
            borderRadius: AppRadius.all(16),
            gradient: LinearGradient(
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
              colors: [
                color.withValues(alpha: 0.9),
                Color.lerp(color, Colors.black, 0.35)!,
              ],
            ),
          ),
          child: ClipRRect(
            borderRadius: AppRadius.all(16),
            child: Stack(
              children: [
                Padding(
                  padding: const EdgeInsets.fromLTRB(14, 14, 14, 14),
                  child: Text(
                    category.label,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                      color: Colors.white,
                      fontSize: 17,
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                ),
                // Tilted icon chip tucked into the corner (image-3 look).
                Positioned(
                  right: -8,
                  bottom: -8,
                  child: Transform.rotate(
                    angle: 0.35,
                    child: Container(
                      width: 52,
                      height: 52,
                      decoration: BoxDecoration(
                        color: Colors.black.withValues(alpha: 0.28),
                        borderRadius: AppRadius.all(10),
                        boxShadow: AppShadow.lift(
                          blur: 8,
                          dy: 3,
                          opacity: 0.25,
                        ),
                      ),
                      child: AppIcon(category.icon, color: Colors.white, size: 26),
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
