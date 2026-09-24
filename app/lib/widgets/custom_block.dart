import 'package:flutter/material.dart';
import 'package:solar_icons/solar_icons.dart';

import '../services/home_layout.dart';
import '../theme.dart';
import 'home_sections.dart';

/// One thing inside a custom block, whatever it started life as.
///
/// Albums, mixes, playlists, tracks and artists all reduce to this — a picture,
/// two lines, and something to do when tapped. Flattening them is what lets any
/// [HomeModuleSource] be drawn in any [HomeModuleLayout]: the layouts never
/// learn what kind of thing they are showing.
class BlockItem {
  final String id;
  final String title;
  final String subtitle;
  final String? artworkUrl;
  final VoidCallback onTap;

  /// Round art, for people rather than records.
  final bool circular;

  const BlockItem({
    required this.id,
    required this.title,
    required this.subtitle,
    required this.artworkUrl,
    required this.onTap,
    this.circular = false,
  });
}

/// A block the user designed: their heading, their shape, their contents.
class CustomBlock extends StatelessWidget {
  final String title;
  final HomeModuleLayout layout;
  final List<BlockItem> items;

  /// Which copy of a duplicated block this is, so two banners of the same
  /// source open on different items rather than showing the same one twice.
  final int copy;

  const CustomBlock({
    super.key,
    required this.title,
    required this.layout,
    required this.items,
    this.copy = 0,
  });

  @override
  Widget build(BuildContext context) => switch (layout) {
    HomeModuleLayout.row => _row(),
    HomeModuleLayout.grid => _grid(),
    HomeModuleLayout.list => _list(),
    HomeModuleLayout.banner => _banner(),
  };

  // ---- Row: the shape most of the shipped sections use ---------------------

  Widget _row() => CardStrip(
    title: title,
    count: items.length,
    cardWidth: 150,
    coverHeight: 150,
    coverBuilder: (i) => _cover(items[i], 150, 150),
    labelBuilder: (i) => _label(items[i]),
    onTap: (i) => items[i].onTap(),
  );

  // ---- Grid: two columns, no sideways scrolling ----------------------------

  Widget _grid() {
    // Capped rather than unbounded: a grid grows the page downwards, so an
    // eighty-album source would otherwise bury everything below it.
    final shown = items.take(6).toList();
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        SectionHeader(title),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 20),
          child: LayoutBuilder(
            builder: (context, box) {
              const gap = 12.0;
              final w = (box.maxWidth - gap) / 2;
              return Wrap(
                spacing: gap,
                runSpacing: gap,
                children: [
                  for (final item in shown)
                    SizedBox(
                      width: w,
                      child: GestureDetector(
                        onTap: item.onTap,
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            _cover(item, w, w),
                            const SizedBox(height: 8),
                            _label(item),
                          ],
                        ),
                      ),
                    ),
                ],
              );
            },
          ),
        ),
      ],
    );
  }

  // ---- List: full-width rows -----------------------------------------------

  Widget _list() {
    final shown = items.take(6).toList();
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        SectionHeader(title),
        for (final item in shown)
          GestureDetector(
            onTap: item.onTap,
            behavior: HitTestBehavior.opaque,
            child: Padding(
              padding: const EdgeInsets.fromLTRB(20, 0, 20, 12),
              child: Row(
                children: [
                  _cover(item, 54, 54),
                  const SizedBox(width: 12),
                  Expanded(child: _label(item)),
                  const Icon(
                    SolarIconsOutline.altArrowRight,
                    color: AppColors.textFaint,
                    size: 18,
                  ),
                ],
              ),
            ),
          ),
      ],
    );
  }

  // ---- Banner: one large panel ---------------------------------------------

  Widget _banner() {
    if (items.isEmpty) return const SizedBox.shrink();
    final item = items[copy % items.length];
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        SectionHeader(title),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 20),
          child: GestureDetector(
            onTap: item.onTap,
            child: ClipRRect(
              borderRadius: AppRadius.all(20),
              child: SizedBox(
                height: 170,
                width: double.infinity,
                child: Stack(
                  fit: StackFit.expand,
                  children: [
                    SectionCover(
                      url: item.artworkUrl,
                      width: double.infinity,
                      height: 170,
                      radius: 0,
                    ),
                    // The art is arbitrary, so the text needs its own ground.
                    DecoratedBox(
                      decoration: BoxDecoration(
                        gradient: LinearGradient(
                          begin: Alignment.bottomLeft,
                          end: Alignment.topRight,
                          colors: [
                            Colors.black.withValues(alpha: 0.85),
                            Colors.black.withValues(alpha: 0.15),
                          ],
                        ),
                      ),
                    ),
                    Padding(
                      padding: const EdgeInsets.all(18),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        mainAxisAlignment: MainAxisAlignment.end,
                        children: [
                          Text(
                            item.title,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: const TextStyle(
                              color: Colors.white,
                              fontSize: 22,
                              fontWeight: FontWeight.w900,
                            ),
                          ),
                          Text(
                            item.subtitle,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: const TextStyle(
                              color: Colors.white70,
                              fontSize: 13,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ],
    );
  }

  // ---- Shared parts --------------------------------------------------------

  /// A circular item is just a cover with a radius of half its width — the
  /// cover already clips to whatever radius it's given.
  Widget _cover(BlockItem item, double w, double h) => SectionCover(
    url: item.artworkUrl,
    width: w,
    height: h,
    radius: item.circular ? w / 2 : 12,
    icon: item.circular ? SolarIconsBold.user : SolarIconsBold.musicNote,
  );

  Widget _label(BlockItem item) => Column(
    mainAxisSize: MainAxisSize.min,
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      Text(
        item.title,
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
        style: const TextStyle(
          color: AppColors.textPrimary,
          fontSize: 14,
          fontWeight: FontWeight.w700,
        ),
      ),
      if (item.subtitle.isNotEmpty)
        Text(
          item.subtitle,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: const TextStyle(color: AppColors.textMuted, fontSize: 12.5),
        ),
    ],
  );
}
