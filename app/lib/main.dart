import 'dart:async';

import 'package:flutter/material.dart';
import 'package:just_audio_background/just_audio_background.dart';

import 'theme.dart';
import 'services/automation_state.dart';
import 'services/appearance_state.dart';
import 'services/car_browser.dart';
import 'services/home_layout.dart';
import 'services/theme_templates.dart';
import 'services/player_service.dart';
import 'services/settings_state.dart';
import 'widgets/bouncy_nav_bar.dart';
import 'widgets/mini_player.dart';
import 'widgets/profile_avatar.dart';
import 'screens/home_screen.dart';
import 'screens/explore_screen.dart';
import 'screens/library_screen.dart';
import 'screens/account_screen.dart';
import 'screens/account_auth_screen.dart';
import 'services/icon_registry.dart';
import 'widgets/app_icon.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  // Set up the foreground media service before any audio player is created, so
  // playback keeps running (and its stream connection stays alive) when the
  // screen is off / the app is backgrounded.
  await JustAudioBackground.init(
    androidNotificationChannelId: 'com.lthirius.music_app.playback',
    androidNotificationChannelName: 'Playback',
    androidNotificationOngoing: true,
    // The launcher icon is a solid silhouette and renders as a featureless
    // blob at status-bar size; this is the mark drawn as an outline.
    androidNotificationIcon: 'drawable/ic_notification',
  );
  // Hand the notification's Like and Shuffle buttons to the player.
  playerService.bindNotificationActions();
  // Expose the library as a browsable tree for Android Auto (and Wear/
  // Assistant), backed by whichever account's client is currently bound.
  bindCarBrowser();
  // Device preferences (playback quality, caching, presentation) before
  // anything reads them — the restored session builds stream URLs from them.
  await settingsState.load();
  // How the app looks, and how Home is arranged — both are read during the
  // very first build, so they load before runApp rather than flashing the
  // defaults and then resettling.
  await appearanceState.load();
  await iconRegistry.load();
  await homeLayout.load();
  await templateStore.load();
  await playerService.applyAudioSettings();
  // The account drives everything: loading it binds the music and audiobook
  // clients to that account's backend session, and restores that account's
  // last music session (loaded paused at the saved spot).
  await automationState.loadSaved();
  // Pick up a profile picture or name set on another device, without holding
  // up the first frame.
  unawaited(automationState.refreshProfile());
  runApp(const MusicApp());
}

class MusicApp extends StatelessWidget {
  const MusicApp({super.key});

  @override
  Widget build(BuildContext context) {
    // Rebuilt on any presentation change, so accent, font, corner style and
    // text size all take effect across the whole app the moment they change.
    return ListenableBuilder(
      listenable: Listenable.merge([settingsState, appearanceState]),
      builder: (context, _) => MaterialApp(
        title: 'Musillow',
        debugShowCheckedModeBanner: false,
        theme: buildAppTheme(),
        // The app owns text sizing outright (Appearance > Text size) rather
        // than inheriting the system scale, so the layouts stay predictable.
        builder: (context, child) => MediaQuery(
          data: MediaQuery.of(context).copyWith(
            textScaler: TextScaler.linear(settingsState.textScale),
          ),
          child: child!,
        ),
        home: const _Gate(),
      ),
    );
  }
}

/// Requires a signed-in Musillow account before showing the app. Music/audiobook
/// connectors are set up afterwards, in Settings.
class _Gate extends StatelessWidget {
  const _Gate();

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: automationState,
      builder: (context, _) => automationState.isConnected
          // Keyed on the session so switching accounts rebuilds every screen
          // from scratch rather than leaving the last account's data on show.
          ? RootShell(key: ValueKey(automationState.session))
          : const AccountAuthScreen(),
    );
  }
}

/// Desktop shell: the wheel nav across the top, the active section below.
class RootShell extends StatefulWidget {
  /// Which tab to open on. The Studio uses this to preview a given screen
  /// complete with its surrounding chrome.
  final int initialIndex;

  const RootShell({super.key, this.initialIndex = 0});

  @override
  State<RootShell> createState() => _RootShellState();
}

class _RootShellState extends State<RootShell> {
  late int _index = widget.initialIndex;

  static final _navItems = <BouncyNavItem>[
    BouncyNavItem(
      icon: IconSlot.navHome,
      activeIcon: IconSlot.navHomeActive,
      label: 'Home',
      color: AppColors.accent,
    ),
    BouncyNavItem(
      icon: IconSlot.navExplore,
      activeIcon: IconSlot.navExploreActive,
      label: 'Explore',
      color: AppColors.teal,
    ),
    BouncyNavItem(
      // Bold in both states (the outline glyph is illegible at this size when
      // idle); the muted color still distinguishes unselected.
      icon: IconSlot.navLibrary,
      activeIcon: IconSlot.navLibraryActive,
      label: 'Library',
      color: AppColors.orange,
    ),
  ];

  static const _screens = [HomeScreen(), ExploreScreen(), LibraryScreen()];

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      extendBody: true,
      body: SafeArea(
        bottom: false,
        child: Column(
          children: [
            _AppHeader(title: _navItems[_index].label),
            Expanded(child: IndexedStack(index: _index, children: _screens)),
          ],
        ),
      ),
      // Mini player + nav live in one rounded panel anchored to the bottom;
      // the mini player simply expands this header upward when a track plays.
      bottomNavigationBar: Container(
        clipBehavior: Clip.antiAlias,
        decoration: BoxDecoration(
          color: AppColors.surface,
          borderRadius: AppRadius.top(34),
          boxShadow: AppShadow.lift(blur: 24, dy: -6, opacity: 0.4),
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const MiniPlayer(),
            BouncyNavBar(
              items: _navItems,
              currentIndex: _index,
              onSelect: (i) => setState(() => _index = i),
            ),
          ],
        ),
      ),
    );
  }
}

/// Shared top header shown on every tab: the section title, with the account's
/// picture on the right. Settings live inside Account rather than getting their
/// own permanent button up here.
class _AppHeader extends StatelessWidget {
  final String title;
  const _AppHeader({required this.title});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(24, 10, 8, 6),
      child: Row(
        children: [
          Expanded(
            child: Text(
              title,
              style: const TextStyle(
                fontSize: 28,
                fontWeight: FontWeight.w800,
                color: AppColors.textPrimary,
              ),
            ),
          ),
          ListenableBuilder(
            listenable: automationState,
            builder: (context, _) {
              final account = automationState.active;
              return IconButton(
                tooltip: 'Account',
                onPressed: () => Navigator.of(context).push(
                  MaterialPageRoute(builder: (_) => const AccountScreen()),
                ),
                icon: account == null
                    ? const AppIcon(
                        IconSlot.account,
                        color: AppColors.textMuted,
                      )
                    : ProfileAvatar(
                        name: account.username,
                        colorHex: account.colorHex,
                        size: 32,
                        imageUrl: automationState.avatarUrl,
                      ),
              );
            },
          ),
        ],
      ),
    );
  }
}
