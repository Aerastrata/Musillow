import 'dart:io';

import 'package:flutter/material.dart';

import '../services/icon_registry.dart';

/// An icon named by its [IconSlot] rather than by a specific glyph.
///
/// Resolves through [iconRegistry], so remapping a slot in the icon editor
/// changes every place it appears. Renders a user-supplied image when the slot
/// has been pointed at one.
class AppIcon extends StatelessWidget {
  final IconSlot slot;
  final double size;
  final Color? color;

  const AppIcon(this.slot, {super.key, this.size = 24, this.color});

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: iconRegistry,
      builder: (context, _) {
        final spec = iconRegistry.specFor(slot);
        final resolved = color ?? IconTheme.of(context).color;

        if (spec.isCustom) {
          final file = File(spec.imagePath!);
          return SizedBox(
            width: size,
            height: size,
            child: Image.file(
              file,
              width: size,
              height: size,
              fit: BoxFit.contain,
              // A monochrome custom icon still picks up the surrounding colour;
              // a full-colour one is left as drawn.
              errorBuilder: (_, _, _) => Icon(
                Icons.broken_image_outlined,
                size: size,
                color: resolved,
              ),
            ),
          );
        }

        final data = spec.iconData;
        if (data == null) return SizedBox(width: size, height: size);
        return Icon(data, size: size, color: resolved);
      },
    );
  }
}
