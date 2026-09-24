import 'package:flutter/material.dart';
import 'package:solar_icons/solar_icons.dart';

import '../services/home_layout.dart';
import '../theme.dart';
import 'custom_block_editor.dart';

/// The blocks you've built for Home.
///
/// Only the custom ones: arranging the page — order, what's on it, what isn't —
/// is done by tapping the Home preview in the Studio and working on the page
/// itself, which is a better place for it than a list of names. This screen is
/// for the thing that has no home there: designing a block in the first place.
class CustomBlocksScreen extends StatelessWidget {
  const CustomBlocksScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Blocks'),
        titleTextStyle: const TextStyle(
          color: AppColors.textPrimary,
          fontSize: 20,
          fontWeight: FontWeight.w800,
        ),
      ),
      body: ListenableBuilder(
        listenable: homeLayout,
        builder: (context, _) {
          final blocks = homeLayout.modules
              .where((m) => m.type == HomeModuleType.custom)
              .toList();
          return Column(
            children: [
              const Padding(
                padding: EdgeInsets.fromLTRB(20, 4, 20, 14),
                child: Text(
                  'A block is a shape, a name, and something to fill it with. '
                  'Once built it sits on Home like any other section — open the '
                  'Home preview to move it.',
                  style: TextStyle(color: AppColors.textMuted, fontSize: 13),
                ),
              ),
              Expanded(
                child: blocks.isEmpty
                    ? const _Empty()
                    : ListView.builder(
                        padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
                        itemCount: blocks.length,
                        itemBuilder: (context, i) => _BlockTile(
                          module: blocks[i],
                          onEdit: () => Navigator.of(context).push(
                            MaterialPageRoute(
                              builder: (_) =>
                                  CustomBlockEditor(existing: blocks[i]),
                            ),
                          ),
                          onDuplicate: () => homeLayout.duplicate(blocks[i].uid),
                          onRemove: () => homeLayout.remove(blocks[i].uid),
                        ),
                      ),
              ),
              SafeArea(
                top: false,
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(16, 8, 16, 12),
                  child: SizedBox(
                    width: double.infinity,
                    child: OutlinedButton.icon(
                      onPressed: () => Navigator.of(context).push(
                        MaterialPageRoute(
                          builder: (_) => const CustomBlockEditor(),
                        ),
                      ),
                      icon: Icon(
                        SolarIconsOutline.widgetAdd,
                        size: 18,
                        color: AppColors.accent,
                      ),
                      label: Text(
                        'Build a block',
                        style: TextStyle(color: AppColors.accent),
                      ),
                      style: OutlinedButton.styleFrom(
                        side: const BorderSide(color: AppColors.border),
                        shape: AppRadius.shape(12),
                        padding: const EdgeInsets.symmetric(vertical: 14),
                      ),
                    ),
                  ),
                ),
              ),
            ],
          );
        },
      ),
    );
  }
}

class _Empty extends StatelessWidget {
  const _Empty();

  @override
  Widget build(BuildContext context) => Center(
    child: Padding(
      padding: const EdgeInsets.symmetric(horizontal: 40),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(
            SolarIconsOutline.widget,
            size: 42,
            color: AppColors.textFaint,
          ),
          const SizedBox(height: 14),
          const Text(
            'No blocks yet',
            style: TextStyle(
              color: AppColors.textPrimary,
              fontSize: 16,
              fontWeight: FontWeight.w700,
            ),
          ),
          const SizedBox(height: 6),
          const Text(
            'Build one to put your mixes in a grid, your albums in a banner, '
            'or anything else the shipped sections don\'t do.',
            textAlign: TextAlign.center,
            style: TextStyle(color: AppColors.textMuted, fontSize: 13),
          ),
        ],
      ),
    ),
  );
}

class _BlockTile extends StatelessWidget {
  final HomeModule module;
  final VoidCallback onEdit;
  final VoidCallback onDuplicate;
  final VoidCallback onRemove;

  const _BlockTile({
    required this.module,
    required this.onEdit,
    required this.onDuplicate,
    required this.onRemove,
  });

  @override
  Widget build(BuildContext context) {
    final on = module.enabled;
    return GestureDetector(
      onTap: onEdit,
      behavior: HitTestBehavior.opaque,
      child: Container(
        margin: const EdgeInsets.only(bottom: 10),
        padding: const EdgeInsets.fromLTRB(12, 10, 6, 10),
        decoration: BoxDecoration(
          color: AppColors.surface,
          borderRadius: AppRadius.all(16),
          border: Border.all(color: AppColors.border),
        ),
        child: Row(
          children: [
            Container(
              width: 38,
              height: 38,
              decoration: BoxDecoration(
                color: AppColors.accent.withValues(alpha: 0.16),
                borderRadius: AppRadius.all(10),
              ),
              child: Icon(
                module.layout?.icon ?? SolarIconsOutline.widget,
                size: 19,
                color: AppColors.accent,
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    module.title,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      color: on ? AppColors.textPrimary : AppColors.textFaint,
                      fontSize: 15,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                  Text(
                    module.subtitle,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                      color: AppColors.textMuted,
                      fontSize: 12,
                    ),
                  ),
                ],
              ),
            ),
            PopupMenuButton<String>(
              color: AppColors.surfaceAlt,
              icon: const Icon(
                SolarIconsOutline.menuDots,
                color: AppColors.textMuted,
                size: 20,
              ),
              onSelected: (v) {
                if (v == 'edit') onEdit();
                if (v == 'duplicate') onDuplicate();
                if (v == 'remove') onRemove();
              },
              itemBuilder: (_) => const [
                PopupMenuItem(
                  value: 'edit',
                  child: Text(
                    'Edit',
                    style: TextStyle(color: AppColors.textPrimary),
                  ),
                ),
                PopupMenuItem(
                  value: 'duplicate',
                  child: Text(
                    'Add another copy',
                    style: TextStyle(color: AppColors.textPrimary),
                  ),
                ),
                PopupMenuItem(
                  value: 'remove',
                  child: Text(
                    'Delete',
                    style: TextStyle(color: AppColors.danger),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}
