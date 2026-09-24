import 'package:flutter/material.dart';

import '../services/settings_state.dart';

/// A network image that fades in over its placeholder instead of snapping in.
///
/// Cover art arrives one file at a time as it downloads; without this every
/// tile pops the instant its bytes land, which reads as the page assembling
/// itself in front of you.
class FadingImage extends StatelessWidget {
  final String? url;

  /// Shown until the image has a frame, and if it fails outright.
  final Widget placeholder;
  final BoxFit fit;

  const FadingImage({
    super.key,
    required this.url,
    required this.placeholder,
    this.fit = BoxFit.cover,
  });

  @override
  Widget build(BuildContext context) {
    if (url == null) return placeholder;
    return Stack(
      fit: StackFit.expand,
      children: [
        placeholder,
        Image.network(
          url!,
          fit: fit,
          gaplessPlayback: true,
          frameBuilder: (context, child, frame, wasSynchronouslyLoaded) {
            // Already in the image cache: show it without a pointless fade.
            // "Reduce motion" drops the fade entirely.
            if (wasSynchronouslyLoaded || settingsState.reduceMotion) {
              return child;
            }
            return AnimatedOpacity(
              opacity: frame == null ? 0 : 1,
              duration: const Duration(milliseconds: 280),
              curve: Curves.easeOut,
              child: child,
            );
          },
          errorBuilder: (context, error, stack) => placeholder,
        ),
      ],
    );
  }
}
