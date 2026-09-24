import 'package:flutter/material.dart';
import 'package:solar_icons/solar_icons.dart';

import '../services/automation_state.dart';
import '../theme.dart';
import '../widgets/profile_avatar.dart';
import 'account_editor_screen.dart';
import 'settings_screen.dart';
import 'studio_screen.dart';
import 'switch_account_screen.dart';

/// Account home: the active profile, editing, switching, and sign-out.
class AccountScreen extends StatelessWidget {
  const AccountScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Account'),
        titleTextStyle: const TextStyle(
          color: AppColors.textPrimary,
          fontSize: 20,
          fontWeight: FontWeight.w800,
        ),
      ),
      body: ListenableBuilder(
        listenable: automationState,
        builder: (context, _) {
          final account = automationState.active;
          final name = account?.username ?? 'Signed out';
          return ListView(
            children: [
              Padding(
                padding: const EdgeInsets.all(20),
                child: Row(
                  children: [
                    ProfileAvatar(
                      name: name,
                      colorHex: account?.colorHex ?? '#9090FF',
                      size: 64,
                      imageUrl: automationState.avatarUrl,
                    ),
                    const SizedBox(width: 16),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            name,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: const TextStyle(
                              color: AppColors.textPrimary,
                              fontSize: 20,
                              fontWeight: FontWeight.w800,
                            ),
                          ),
                          if ((account?.email ?? '').isNotEmpty)
                            Text(
                              account!.email!,
                              style: const TextStyle(
                                color: AppColors.textMuted,
                                fontSize: 13,
                              ),
                            ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
              const Divider(height: 1, color: AppColors.border),
              _tile(
                SolarIconsOutline.user,
                'Edit account',
                () => Navigator.of(context).push(
                  MaterialPageRoute(builder: (_) => const AccountEditorScreen()),
                ),
                chevron: true,
              ),
              _tile(
                SolarIconsOutline.usersGroupRounded,
                'Switch account',
                () => Navigator.of(context).push(
                  MaterialPageRoute(builder: (_) => const SwitchAccountScreen()),
                ),
                chevron: true,
              ),
              _tile(
                SolarIconsOutline.logout,
                'Sign out',
                () async {
                  await automationState.logoutActive();
                  if (context.mounted) {
                    Navigator.of(context).popUntil((r) => r.isFirst);
                  }
                },
                color: const Color(0xFFE0605A),
              ),
              const Divider(height: 1, color: AppColors.border),
              _tile(
                SolarIconsOutline.paletteRound,
                'Studio',
                () => Navigator.of(context).push(
                  MaterialPageRoute(builder: (_) => const StudioScreen()),
                ),
                chevron: true,
              ),
              _tile(
                SolarIconsOutline.settings,
                'Settings',
                () => Navigator.of(context).push(
                  MaterialPageRoute(builder: (_) => const SettingsScreen()),
                ),
                chevron: true,
              ),
              const SizedBox(height: 24),
            ],
          );
        },
      ),
    );
  }

  Widget _tile(
    IconData icon,
    String label,
    VoidCallback onTap, {
    Color? color,
    bool chevron = false,
  }) => ListTile(
    leading: Icon(icon, color: color ?? AppColors.textPrimary),
    title: Text(label, style: TextStyle(color: color ?? AppColors.textPrimary)),
    trailing: chevron
        ? const Icon(
            SolarIconsOutline.altArrowRight,
            size: 18,
            color: AppColors.textFaint,
          )
        : null,
    onTap: onTap,
  );
}
