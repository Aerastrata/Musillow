import 'dart:io';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:path_provider/path_provider.dart';

import '../generated/solar_catalog.g.dart';
import '../services/icon_registry.dart';
import '../theme.dart';
import '../widgets/app_icon.dart';

/// Pick the icon for one [IconSlot].
///
/// Offers the whole Solar set — both cuts of all 1,247 glyphs — plus any image
/// from the device, so a slot isn't limited to what the app happens to ship.
class IconPickerScreen extends StatefulWidget {
  final IconSlot slot;
  const IconPickerScreen({super.key, required this.slot});

  @override
  State<IconPickerScreen> createState() => _IconPickerScreenState();
}

class _IconPickerScreenState extends State<IconPickerScreen> {
  final _search = TextEditingController();
  late IconStyle _style;
  String _query = '';

  @override
  void initState() {
    super.initState();
    _style = iconRegistry.specFor(widget.slot).style;
  }

  @override
  void dispose() {
    _search.dispose();
    super.dispose();
  }

  List<SolarGlyph> get _results {
    if (_query.isEmpty) return solarCatalog;
    // Every search word must appear, so "music note" narrows rather than widens.
    final words = _query.split(RegExp(r'\s+')).where((w) => w.isNotEmpty);
    return solarCatalog
        .where((g) => words.every((w) => g.terms.contains(w)))
        .toList(growable: false);
  }

  Future<void> _pickFromFiles() async {
    final picked = await FilePicker.pickFile(type: FileType.image);
    if (picked == null) return;
    try {
      // Copy the bytes into app storage rather than keeping the picked path:
      // on Android the pick is often a content:// handle with no readable path,
      // and the override has to survive a restart either way.
      final bytes = await picked.readAsBytes();
      final dir = Directory(
        '${(await getApplicationSupportDirectory()).path}/icons',
      );
      await dir.create(recursive: true);
      final ext = picked.extension ?? 'png';
      final dest = File(
        '${dir.path}/${widget.slot.name}-${DateTime.now().millisecondsSinceEpoch}.$ext',
      );
      await dest.writeAsBytes(bytes);
      await iconRegistry.set(widget.slot, IconSpec(imagePath: dest.path));
      if (mounted) Navigator.of(context).pop(true);
    } catch (_) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text("Couldn't use that image")),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final results = _results;
    final current = iconRegistry.specFor(widget.slot);
    return Scaffold(
      appBar: AppBar(
        title: Text(widget.slot.label),
        titleTextStyle: const TextStyle(
          color: AppColors.textPrimary,
          fontSize: 19,
          fontWeight: FontWeight.w800,
        ),
        actions: [
          if (iconRegistry.isOverridden(widget.slot))
            TextButton(
              onPressed: () async {
                await iconRegistry.clear(widget.slot);
                if (context.mounted) Navigator.of(context).pop(true);
              },
              child: Text(
                'Reset',
                style: TextStyle(color: AppColors.accent),
              ),
            ),
        ],
      ),
      body: Column(
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 4, 16, 10),
            child: Row(
              children: [
                Container(
                  width: 52,
                  height: 52,
                  alignment: Alignment.center,
                  decoration: BoxDecoration(
                    color: AppColors.surfaceAlt,
                    borderRadius: AppRadius.all(14),
                    border: Border.all(color: AppColors.border),
                  ),
                  child: AppIcon(widget.slot, size: 26, color: AppColors.accent),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Text(
                    current.isCustom
                        ? 'Your own image'
                        : 'Currently ${current.glyph ?? '—'}',
                    style: const TextStyle(
                      color: AppColors.textMuted,
                      fontSize: 13,
                    ),
                  ),
                ),
              ],
            ),
          ),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16),
            child: TextField(
              controller: _search,
              onChanged: (v) => setState(() => _query = v.trim().toLowerCase()),
              style: const TextStyle(color: AppColors.textPrimary),
              decoration: InputDecoration(
                hintText: 'Search ${solarCatalog.length} icons',
                hintStyle: const TextStyle(color: AppColors.textFaint),
                prefixIcon: const Icon(
                  Icons.search,
                  color: AppColors.textFaint,
                ),
                filled: true,
                fillColor: AppColors.surfaceAlt,
                isDense: true,
                border: OutlineInputBorder(
                  borderRadius: AppRadius.all(14),
                  borderSide: BorderSide.none,
                ),
              ),
            ),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 12, 16, 6),
            child: Row(
              children: [
                for (final s in IconStyle.values) ...[
                  GestureDetector(
                    onTap: () => setState(() => _style = s),
                    child: Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 16,
                        vertical: 7,
                      ),
                      decoration: BoxDecoration(
                        color: _style == s
                            ? AppColors.accent.withValues(alpha: 0.18)
                            : AppColors.surfaceAlt,
                        borderRadius: AppRadius.all(20),
                        border: Border.all(
                          color: _style == s
                              ? AppColors.accent
                              : AppColors.border,
                        ),
                      ),
                      child: Text(
                        s == IconStyle.outline ? 'Outline' : 'Filled',
                        style: TextStyle(
                          color: _style == s
                              ? AppColors.accent
                              : AppColors.textMuted,
                          fontSize: 13,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(width: 8),
                ],
                const Spacer(),
                TextButton.icon(
                  onPressed: _pickFromFiles,
                  icon: Icon(
                    Icons.add_photo_alternate_outlined,
                    size: 18,
                    color: AppColors.accent,
                  ),
                  label: Text(
                    'From files',
                    style: TextStyle(color: AppColors.accent, fontSize: 13),
                  ),
                ),
              ],
            ),
          ),
          Expanded(
            child: results.isEmpty
                ? const Center(
                    child: Text(
                      'No icons match that.',
                      style: TextStyle(color: AppColors.textFaint),
                    ),
                  )
                : GridView.builder(
                    padding: const EdgeInsets.fromLTRB(12, 4, 12, 24),
                    gridDelegate:
                        const SliverGridDelegateWithFixedCrossAxisCount(
                          crossAxisCount: 5,
                          mainAxisSpacing: 8,
                          crossAxisSpacing: 8,
                        ),
                    itemCount: results.length,
                    itemBuilder: (context, i) {
                      final g = results[i];
                      final selected =
                          !current.isCustom &&
                          current.glyph == g.name &&
                          current.style == _style;
                      return GestureDetector(
                        onTap: () async {
                          await iconRegistry.set(
                            widget.slot,
                            IconSpec(glyph: g.name, style: _style),
                          );
                          if (context.mounted) Navigator.of(context).pop(true);
                        },
                        child: Container(
                          decoration: BoxDecoration(
                            color: selected
                                ? AppColors.accent.withValues(alpha: 0.18)
                                : AppColors.surface,
                            borderRadius: AppRadius.all(14),
                            border: Border.all(
                              color: selected
                                  ? AppColors.accent
                                  : AppColors.border,
                            ),
                          ),
                          child: Icon(
                            _style == IconStyle.bold ? g.bold : g.outline,
                            size: 24,
                            color: selected
                                ? AppColors.accent
                                : AppColors.textPrimary,
                          ),
                        ),
                      );
                    },
                  ),
          ),
        ],
      ),
    );
  }
}
