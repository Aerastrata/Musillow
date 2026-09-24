import 'dart:io';

import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import 'package:solar_icons/solar_icons.dart';

import '../services/automation_client.dart';
import '../services/automation_state.dart';
import '../theme.dart';
import '../widgets/profile_avatar.dart';

/// Edit the active account: profile picture, display name, email, password,
/// and accent colour.
class AccountEditorScreen extends StatefulWidget {
  const AccountEditorScreen({super.key});

  @override
  State<AccountEditorScreen> createState() => _AccountEditorScreenState();
}

class _AccountEditorScreenState extends State<AccountEditorScreen> {
  final _name = TextEditingController();
  final _email = TextEditingController();
  final _password = TextEditingController();
  late String _color;
  bool _obscure = true;
  bool _saving = false;
  String? _error;

  /// A picked image, held locally until Save so cancelling out of the editor
  /// leaves the stored picture alone.
  File? _pickedPicture;
  bool _removePicture = false;

  @override
  void initState() {
    super.initState();
    final a = automationState.active;
    _name.text = a?.username ?? '';
    _email.text = a?.email ?? '';
    _color = a?.colorHex ?? accountPalette.first;
    // Another device may have set a picture since this one last looked.
    automationState.refreshProfile().then((_) {
      if (mounted) setState(() {});
    });
  }

  @override
  void dispose() {
    _name.dispose();
    _email.dispose();
    _password.dispose();
    super.dispose();
  }

  /// Pick a picture from the device. It's downscaled here so the upload is a
  /// few dozen KB rather than a full-resolution camera shot.
  Future<void> _pickPicture() async {
    try {
      final img = await ImagePicker().pickImage(
        source: ImageSource.gallery,
        maxWidth: 512,
        maxHeight: 512,
        imageQuality: 85,
      );
      if (img == null) return;
      setState(() {
        _pickedPicture = File(img.path);
        _removePicture = false;
      });
    } catch (_) {
      setState(() => _error = "Couldn't open the picture.");
    }
  }

  void _clearPicture() => setState(() {
    _pickedPicture = null;
    _removePicture = true;
  });

  /// True when there's something to show in the avatar — a fresh pick, or a
  /// stored picture that hasn't been marked for removal.
  bool get _hasPicture =>
      _pickedPicture != null ||
      (!_removePicture && automationState.avatarUrl != null);

  Future<void> _save() async {
    setState(() {
      _saving = true;
      _error = null;
    });
    try {
      await automationState.updateProfile(
        username: _name.text.trim().isEmpty ? null : _name.text.trim(),
        email: _email.text.trim(),
        password: _password.text,
        colorHex: _color,
      );
      // The picture is a separate upload, so it goes after the profile write.
      if (_pickedPicture != null) {
        await automationState.setAvatar(_pickedPicture!.path);
      } else if (_removePicture) {
        await automationState.removeAvatar();
      }
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(const SnackBar(content: Text('Saved')));
        Navigator.of(context).pop();
      }
    } on AutomationException catch (e) {
      setState(() => _error = e.message);
    } catch (e) {
      setState(() => _error = 'Save failed.');
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Edit account'),
        actions: [
          _saving
              ? const Padding(
                  padding: EdgeInsets.all(16),
                  child: SizedBox(
                    width: 18,
                    height: 18,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  ),
                )
              : TextButton(
                  onPressed: _save,
                  child: Text(
                    'Save',
                    style: TextStyle(
                      color: AppColors.accent,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ),
        ],
      ),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(20, 12, 20, 32),
        children: [
          Center(
            child: Column(
              children: [
                ProfileAvatar(
                  name: _name.text.isEmpty ? '?' : _name.text,
                  colorHex: _color,
                  size: 96,
                  imageUrl: _removePicture ? null : automationState.avatarUrl,
                  preview: _pickedPicture != null
                      ? FileImage(_pickedPicture!)
                      : null,
                ),
                const SizedBox(height: 14),
                Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    OutlinedButton.icon(
                      onPressed: _pickPicture,
                      icon: const Icon(SolarIconsOutline.galleryAdd, size: 18),
                      label: Text(
                        _hasPicture ? 'Change picture' : 'Upload picture',
                      ),
                      style: OutlinedButton.styleFrom(
                        foregroundColor: AppColors.textPrimary,
                        side: const BorderSide(color: AppColors.border),
                        shape: RoundedRectangleBorder(
                          borderRadius: AppRadius.all(12),
                        ),
                      ),
                    ),
                    if (_hasPicture) ...[
                      const SizedBox(width: 8),
                      TextButton(
                        onPressed: _clearPicture,
                        child: const Text(
                          'Remove',
                          style: TextStyle(color: AppColors.textMuted),
                        ),
                      ),
                    ],
                  ],
                ),
              ],
            ),
          ),
          const SizedBox(height: 28),
          _label('Display name'),
          _field(_name, 'username'),
          const SizedBox(height: 18),
          _label('Email'),
          _field(_email, 'you@example.com', keyboard: TextInputType.emailAddress),
          const SizedBox(height: 18),
          _label('New password'),
          _field(
            _password,
            'leave blank to keep current',
            obscure: _obscure,
            trailing: IconButton(
              icon: Icon(
                _obscure ? SolarIconsOutline.eye : SolarIconsOutline.eyeClosed,
                color: AppColors.textMuted,
              ),
              onPressed: () => setState(() => _obscure = !_obscure),
            ),
          ),
          const SizedBox(height: 24),
          _label('Accent colour'),
          Wrap(
            spacing: 12,
            runSpacing: 12,
            children: [for (final c in accountPalette) _swatch(c)],
          ),
          if (_error != null) ...[
            const SizedBox(height: 16),
            Text(_error!, style: const TextStyle(color: Color(0xFFE0605A))),
          ],
        ],
      ),
    );
  }

  Widget _swatch(String hex) {
    final selected = hex.toUpperCase() == _color.toUpperCase();
    return GestureDetector(
      onTap: () => setState(() => _color = hex),
      child: Container(
        width: 42,
        height: 42,
        decoration: BoxDecoration(
          color: hexToColor(hex),
          shape: BoxShape.circle,
          border: selected
              ? Border.all(color: AppColors.textPrimary, width: 3)
              : null,
        ),
      ),
    );
  }

  Widget _label(String text) => Padding(
    padding: const EdgeInsets.only(bottom: 8),
    child: Text(
      text,
      style: const TextStyle(
        color: AppColors.textMuted,
        fontWeight: FontWeight.w600,
      ),
    ),
  );

  Widget _field(
    TextEditingController c,
    String hint, {
    bool obscure = false,
    TextInputType? keyboard,
    Widget? trailing,
  }) {
    return TextField(
      controller: c,
      obscureText: obscure,
      keyboardType: keyboard,
      autocorrect: false,
      enableSuggestions: false,
      onChanged: (_) => setState(() {}),
      style: const TextStyle(color: AppColors.textPrimary),
      decoration: InputDecoration(
        hintText: hint,
        hintStyle: const TextStyle(color: AppColors.textFaint),
        filled: true,
        fillColor: AppColors.surfaceAlt,
        isDense: true,
        suffixIcon: trailing,
        border: OutlineInputBorder(
          borderRadius: AppRadius.all(14),
          borderSide: BorderSide.none,
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: AppRadius.all(14),
          borderSide: const BorderSide(color: AppColors.border),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: AppRadius.all(14),
          borderSide: BorderSide(color: AppColors.accent, width: 1.6),
        ),
      ),
    );
  }
}
