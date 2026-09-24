import 'package:flutter/material.dart';
import 'package:solar_icons/solar_icons.dart';

import '../models/track.dart';
import '../theme.dart';
import 'fading_image.dart';

/// Square cover art. Renders the network image when a URL exists, otherwise a
/// gradient tile seeded from the track id so each looks distinct. Falls back to
/// the gradient while loading or on error.
class CoverArt extends StatelessWidget {
  final Track track;
  final double size;
  final double radius;

  const CoverArt({
    super.key,
    required this.track,
    this.size = 64,
    this.radius = 16,
  });

  @override
  Widget build(BuildContext context) {
    // The shadow goes outside the clip: a ClipRRect would cut it off.
    return DecoratedBox(
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(radius),
        boxShadow: AppShadow.lift(blur: size * 0.18, dy: size * 0.06),
      ),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(radius),
        child: SizedBox(
          width: size,
          height: size,
          child: FadingImage(url: track.coverArtUrl, placeholder: _gradient()),
        ),
      ),
    );
  }

  Widget _gradient() {
    final hue = (track.id.hashCode % 360).abs().toDouble();
    final c1 = HSLColor.fromAHSL(1, hue, 0.4, 0.35).toColor();
    final c2 = HSLColor.fromAHSL(1, (hue + 40) % 360, 0.4, 0.22).toColor();
    return DecoratedBox(
      decoration: BoxDecoration(
        gradient: LinearGradient(
          colors: [c1, c2],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
      ),
      child: const Center(
        child: Icon(SolarIconsBold.musicNote, color: AppColors.textFaint, size: 22),
      ),
    );
  }
}
