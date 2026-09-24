import 'package:flutter/material.dart';

Color hexToColor(String hex) {
  var h = hex.replaceAll('#', '').trim();
  if (h.length == 6) h = 'FF$h';
  return Color(int.tryParse(h, radix: 16) ?? 0xFF9090FF);
}

/// A circular avatar for an account.
///
/// Shows the uploaded profile picture when there is one, and otherwise the
/// account's initial on its accent colour. The initial is always drawn
/// underneath, so it stands in while the picture loads and if it fails.
class ProfileAvatar extends StatelessWidget {
  final String name;
  final String colorHex;
  final double size;

  /// Profile-picture URL, or null for the coloured initial. May also be a
  /// local file path when previewing a freshly-picked image before upload.
  final String? imageUrl;

  /// A picked-but-not-yet-uploaded file to preview instead of [imageUrl].
  final ImageProvider? preview;

  const ProfileAvatar({
    super.key,
    required this.name,
    required this.colorHex,
    this.size = 48,
    this.imageUrl,
    this.preview,
  });

  @override
  Widget build(BuildContext context) {
    final trimmed = name.trim();
    final initial = trimmed.isNotEmpty ? trimmed[0].toUpperCase() : '?';
    final image =
        preview ?? (imageUrl != null ? NetworkImage(imageUrl!) : null);

    return Container(
      width: size,
      height: size,
      clipBehavior: Clip.antiAlias,
      decoration: BoxDecoration(
        color: hexToColor(colorHex),
        shape: BoxShape.circle,
      ),
      alignment: Alignment.center,
      child: Stack(
        fit: StackFit.expand,
        children: [
          Center(
            child: Text(
              initial,
              style: TextStyle(
                color: Colors.white,
                fontSize: size * 0.42,
                fontWeight: FontWeight.w800,
              ),
            ),
          ),
          if (image != null)
            Image(
              image: image,
              fit: BoxFit.cover,
              gaplessPlayback: true,
              // Fall through to the initial rather than showing a broken tile.
              errorBuilder: (_, _, _) => const SizedBox.shrink(),
            ),
        ],
      ),
    );
  }
}
