import 'package:flutter/material.dart';

import '../screens/now_playing_screen.dart';
import '../services/player_service.dart';
import '../theme.dart';
import 'cover_art.dart';
import '../services/icon_registry.dart';
import 'app_icon.dart';

/// A compact now-playing bar that appears above the bottom nav whenever a
/// track is loaded. Shows the cover, title/artist, and a play/pause toggle.
class MiniPlayer extends StatelessWidget {
  const MiniPlayer({super.key});

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: playerService,
      builder: (context, _) {
        final track = playerService.current;
        if (track == null) return const SizedBox.shrink();

        return GestureDetector(
          onTap: () => Navigator.of(context).push(NowPlayingScreen.route()),
          behavior: HitTestBehavior.opaque,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(14, 10, 6, 10),
                child: Row(
                  children: [
                    CoverArt(track: track, size: 50, radius: 12),
                    const SizedBox(width: 12),
                    Expanded(
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          track.title,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(
                            color: AppColors.textPrimary,
                            fontSize: 14,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                        Text(
                          track.artist,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(
                            color: AppColors.textFaint,
                            fontSize: 12,
                          ),
                        ),
                      ],
                    ),
                  ),
                  IconButton(
                    iconSize: 34,
                    color: AppColors.textPrimary,
                    icon: AppIcon(
                      playerService.isPlaying
                          ? IconSlot.miniPause
                          : IconSlot.miniPlay,
                      size: 34,
                    ),
                    onPressed: playerService.toggle,
                  ),
                  // Dismiss: stop playback and hide the bar.
                  IconButton(
                    iconSize: 22,
                    color: AppColors.textMuted,
                    icon: const AppIcon(IconSlot.miniClose, size: 22),
                    onPressed: playerService.stop,
                  ),
                  ],
                ),
              ),
            ],
          ),
        );
      },
    );
  }
}
