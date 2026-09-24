import 'package:flutter/material.dart';
import 'package:solar_icons/solar_icons.dart';

import '../services/automation_state.dart';
import '../theme.dart';
import '../widgets/profile_avatar.dart';
import 'account_auth_screen.dart';

/// Lists saved accounts; tap to switch, or add another.
class SwitchAccountScreen extends StatelessWidget {
  const SwitchAccountScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Switch account'),
        titleTextStyle: const TextStyle(
          color: AppColors.textPrimary,
          fontSize: 20,
          fontWeight: FontWeight.w800,
        ),
      ),
      body: ListenableBuilder(
        listenable: automationState,
        builder: (context, _) {
          final accounts = automationState.accounts;
          final active = automationState.activeIndex;
          return ListView(
            children: [
              for (var i = 0; i < accounts.length; i++)
                ListTile(
                  leading: ProfileAvatar(
                    name: accounts[i].username,
                    colorHex: accounts[i].colorHex,
                    size: 44,
                    imageUrl: automationState.avatarUrlFor(accounts[i]),
                  ),
                  title: Text(
                    accounts[i].username,
                    style: const TextStyle(color: AppColors.textPrimary),
                  ),
                  subtitle: Text(
                    accounts[i].url,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(color: AppColors.textMuted),
                  ),
                  trailing: i == active
                      ? const Icon(
                          SolarIconsBold.checkCircle,
                          color: AppColors.teal,
                        )
                      : null,
                  onTap: i == active
                      ? null
                      : () async {
                          await automationState.switchTo(i);
                          if (context.mounted) Navigator.of(context).pop();
                        },
                ),
              const Divider(height: 1, color: AppColors.border),
              ListTile(
                leading: Icon(
                  SolarIconsOutline.addCircle,
                  color: AppColors.accent,
                ),
                title: Text(
                  'Add account',
                  style: TextStyle(color: AppColors.accent),
                ),
                onTap: () => Navigator.of(context).push(
                  MaterialPageRoute(builder: (_) => const AccountAuthScreen()),
                ),
              ),
            ],
          );
        },
      ),
    );
  }
}
