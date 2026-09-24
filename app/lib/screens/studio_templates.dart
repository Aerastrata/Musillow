import 'dart:io';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:path_provider/path_provider.dart';
import 'package:solar_icons/solar_icons.dart';

import '../services/appearance_state.dart';
import '../services/theme_templates.dart';
import '../theme.dart';

/// Save, restore, and pass around whole looks.
class StudioTemplatesScreen extends StatelessWidget {
  const StudioTemplatesScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Templates'),
        titleTextStyle: const TextStyle(
          color: AppColors.textPrimary,
          fontSize: 20,
          fontWeight: FontWeight.w800,
        ),
      ),
      body: ListenableBuilder(
        listenable: templateStore,
        builder: (context, _) => ListView(
          padding: const EdgeInsets.fromLTRB(16, 8, 16, 32),
          children: [
            const Padding(
              padding: EdgeInsets.fromLTRB(4, 0, 4, 12),
              child: Text(
                'A template captures the accent, font, corners, every icon you '
                'changed, and your Home arrangement.',
                style: TextStyle(color: AppColors.textMuted, fontSize: 13),
              ),
            ),
            _Card(
              child: ListTile(
                contentPadding: EdgeInsets.zero,
                leading: _leading(SolarIconsBold.restart, AppColors.teal),
                title: const Text(
                  'Musillow',
                  style: TextStyle(
                    color: AppColors.textPrimary,
                    fontWeight: FontWeight.w700,
                  ),
                ),
                subtitle: const Text(
                  'The default look. Use this to get back if you mess up.',
                  style: TextStyle(color: AppColors.textMuted, fontSize: 12.5),
                ),
                onTap: () async {
                  final ok = await _confirm(
                    context,
                    'Restore the default look?',
                    'Puts the accent, font, corners, icons and Home layout '
                        'back to how the app shipped. Your saved templates are '
                        'kept.',
                    'Restore',
                  );
                  if (!ok) return;
                  await TemplateStore.applyDefault();
                  if (context.mounted) _toast(context, 'Default look restored');
                },
              ),
            ),
            const SizedBox(height: 6),
            for (final t in templateStore.saved)
              _Card(
                child: ListTile(
                  contentPadding: EdgeInsets.zero,
                  leading: _leading(SolarIconsBold.bookmark, AppColors.accent),
                  title: Text(
                    t.name,
                    style: const TextStyle(
                      color: AppColors.textPrimary,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                  subtitle: Text(
                    t.portable
                        ? 'Ready to share'
                        : 'Uses your own font or icon files — those stay on '
                              'this device',
                    style: const TextStyle(
                      color: AppColors.textMuted,
                      fontSize: 12.5,
                    ),
                  ),
                  onTap: () async {
                    await TemplateStore.apply(t.data);
                    if (context.mounted) _toast(context, 'Applied ${t.name}');
                  },
                  trailing: PopupMenuButton<String>(
                    color: AppColors.surfaceAlt,
                    icon: const Icon(
                      SolarIconsOutline.menuDots,
                      color: AppColors.textMuted,
                    ),
                    onSelected: (v) async {
                      if (v == 'export') await _export(context, t);
                      if (v == 'delete') await templateStore.delete(t.name);
                    },
                    itemBuilder: (_) => const [
                      PopupMenuItem(
                        value: 'export',
                        child: Text(
                          'Export to a file',
                          style: TextStyle(color: AppColors.textPrimary),
                        ),
                      ),
                      PopupMenuItem(
                        value: 'delete',
                        child: Text(
                          'Delete',
                          style: TextStyle(color: AppColors.danger),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            const SizedBox(height: 10),
            _wide(
              context,
              SolarIconsOutline.diskette,
              'Save current look',
              () => _save(context),
            ),
            const SizedBox(height: 8),
            _wide(
              context,
              SolarIconsOutline.folder,
              'Import from a file',
              () => _import(context),
            ),
          ],
        ),
      ),
    );
  }

  static Widget _leading(IconData icon, Color colour) => Container(
    width: 42,
    height: 42,
    alignment: Alignment.center,
    decoration: BoxDecoration(
      color: colour.withValues(alpha: 0.16),
      borderRadius: AppRadius.all(12),
    ),
    child: Icon(icon, color: colour, size: 20),
  );

  static Widget _wide(
    BuildContext context,
    IconData icon,
    String label,
    VoidCallback onPressed,
  ) => SizedBox(
    width: double.infinity,
    child: OutlinedButton.icon(
      onPressed: onPressed,
      icon: Icon(icon, size: 18, color: AppColors.textPrimary),
      label: Text(label, style: const TextStyle(color: AppColors.textPrimary)),
      style: OutlinedButton.styleFrom(
        side: const BorderSide(color: AppColors.border),
        shape: AppRadius.shape(12),
        padding: const EdgeInsets.symmetric(vertical: 14),
      ),
    ),
  );

  Future<void> _save(BuildContext context) async {
    final controller = TextEditingController();
    final name = await showDialog<String>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: AppColors.surface,
        title: const Text(
          'Name this look',
          style: TextStyle(color: AppColors.textPrimary),
        ),
        content: TextField(
          controller: controller,
          autofocus: true,
          style: const TextStyle(color: AppColors.textPrimary),
          decoration: const InputDecoration(hintText: 'e.g. Midnight green'),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(),
            child: const Text(
              'Cancel',
              style: TextStyle(color: AppColors.textMuted),
            ),
          ),
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(controller.text.trim()),
            child: Text('Save', style: TextStyle(color: AppColors.accent)),
          ),
        ],
      ),
    );
    if (name == null || name.isEmpty) return;
    await templateStore.save(name);
    if (context.mounted) _toast(context, 'Saved $name');
  }

  Future<void> _export(BuildContext context, Template t) async {
    try {
      // Written to the app's documents directory: somewhere the user can reach
      // it with a file manager and pass it on.
      final dir = await getApplicationDocumentsDirectory();
      final safe = t.name.replaceAll(RegExp(r'[^A-Za-z0-9._-]'), '_');
      final file = File('${dir.path}/musillow-$safe.json');
      await file.writeAsString(TemplateStore.encode(t));
      if (context.mounted) _toast(context, 'Saved to ${file.path}');
    } catch (e) {
      if (context.mounted) _toast(context, "Couldn't export: $e");
    }
  }

  Future<void> _import(BuildContext context) async {
    final picked = await FilePicker.pickFile();
    if (picked == null) return;
    try {
      final text = String.fromCharCodes(await picked.readAsBytes());
      final t = TemplateStore.decode(text);
      if (t == null) {
        if (context.mounted) _toast(context, "That isn't a template file");
        return;
      }
      await templateStore.add(t);
      if (context.mounted) _toast(context, 'Imported ${t.name}');
    } catch (_) {
      if (context.mounted) _toast(context, "Couldn't read that file");
    }
  }

  static Future<bool> _confirm(
    BuildContext context,
    String title,
    String body,
    String action,
  ) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: AppColors.surface,
        title: Text(title, style: const TextStyle(color: AppColors.textPrimary)),
        content: Text(body, style: const TextStyle(color: AppColors.textMuted)),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(false),
            child: const Text(
              'Cancel',
              style: TextStyle(color: AppColors.textMuted),
            ),
          ),
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(true),
            child: Text(action, style: TextStyle(color: AppColors.accent)),
          ),
        ],
      ),
    );
    return ok ?? false;
  }
}

class _Card extends StatelessWidget {
  final Widget child;
  const _Card({required this.child});

  @override
  Widget build(BuildContext context) => Container(
    margin: const EdgeInsets.only(bottom: 8),
    padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 2),
    decoration: BoxDecoration(
      color: AppColors.surface,
      borderRadius: AppRadius.all(16),
      border: Border.all(color: AppColors.border),
    ),
    child: child,
  );
}

void _toast(BuildContext context, String message) {
  ScaffoldMessenger.of(context)
    ..clearSnackBars()
    ..showSnackBar(
      SnackBar(behavior: SnackBarBehavior.floating, content: Text(message)),
    );
}

/// Pick a .ttf/.otf from the device and adopt it as the app's typeface.
Future<void> addCustomFont(BuildContext context) async {
  final picked = await FilePicker.pickFile(
    type: FileType.custom,
    allowedExtensions: const ['ttf', 'otf'],
  );
  if (picked == null) return;
  try {
    final bytes = await picked.readAsBytes();
    final dir = Directory(
      '${(await getApplicationSupportDirectory()).path}/fonts',
    );
    await dir.create(recursive: true);
    // The family is named after the file, which is what the user will recognise.
    final family = picked.name.replaceAll(RegExp(r'\.(ttf|otf)$'), '');
    final dest = File('${dir.path}/${picked.name}');
    await dest.writeAsBytes(bytes);
    final ok = await appearanceState.addCustomFont(family, dest.path);
    if (context.mounted) {
      _toast(context, ok ? 'Using $family' : "Couldn't load that font");
    }
  } catch (_) {
    if (context.mounted) _toast(context, "Couldn't load that font");
  }
}
