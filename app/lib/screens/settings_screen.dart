import 'dart:io';

import 'package:flutter/material.dart';
import 'package:path_provider/path_provider.dart';
import 'package:solar_icons/solar_icons.dart';

import '../services/abs_client.dart';
import '../services/abs_state.dart';
import '../services/app_state.dart';
import '../services/automation_state.dart';
import '../services/player_service.dart';
import '../services/settings_state.dart';
import '../theme.dart';
import 'connector_setup_screen.dart';

/// The app's settings, split by what each group actually governs: how audio
/// plays, what's kept on the device, which services are wired up, how the app
/// presents itself, listening stats, and what this thing is.
class SettingsScreen extends StatelessWidget {
  const SettingsScreen({super.key});

  static const _tabs = [
    Tab(text: 'Playback'),
    Tab(text: 'Storage'),
    Tab(text: 'Server'),
    Tab(text: 'Stats'),
    Tab(text: 'About'),
  ];

  @override
  Widget build(BuildContext context) {
    return DefaultTabController(
      length: _tabs.length,
      child: Scaffold(
        appBar: AppBar(
          title: const Text('Settings'),
          titleTextStyle: const TextStyle(
            color: AppColors.textPrimary,
            fontSize: 20,
            fontWeight: FontWeight.w800,
          ),
          bottom: TabBar(
            // Six destinations don't fit across a phone; scrolling keeps every
            // label readable instead of squeezing them to initials.
            isScrollable: true,
            tabAlignment: TabAlignment.start,
            labelColor: AppColors.accent,
            unselectedLabelColor: AppColors.textMuted,
            indicatorColor: AppColors.accent,
            tabs: _tabs,
          ),
        ),
        body: const TabBarView(
          children: [
            _PlaybackTab(),
            _StorageTab(),
            _ServerTab(),
            _StatsTab(),
            _AboutTab(),
          ],
        ),
      ),
    );
  }
}

// ---- Shared building blocks -------------------------------------------------

/// A titled group of settings on a card, matching the connector cards.
class _Section extends StatelessWidget {
  final String title;
  final String? subtitle;
  final List<Widget> children;
  const _Section({required this.title, this.subtitle, required this.children});

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.only(bottom: 14),
      padding: const EdgeInsets.fromLTRB(16, 14, 16, 14),
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: AppRadius.all(18),
        border: Border.all(color: AppColors.border),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            title,
            style: const TextStyle(
              color: AppColors.textPrimary,
              fontSize: 16,
              fontWeight: FontWeight.w700,
            ),
          ),
          if (subtitle != null)
            Padding(
              padding: const EdgeInsets.only(top: 2),
              child: Text(
                subtitle!,
                style: const TextStyle(color: AppColors.textMuted, fontSize: 13),
              ),
            ),
          const SizedBox(height: 10),
          ...children,
        ],
      ),
    );
  }
}

/// A labelled on/off row.
class _SwitchRow extends StatelessWidget {
  final String label;
  final String detail;
  final bool value;
  final ValueChanged<bool> onChanged;
  const _SwitchRow({
    required this.label,
    required this.detail,
    required this.value,
    required this.onChanged,
  });

  @override
  Widget build(BuildContext context) {
    return SwitchListTile(
      contentPadding: EdgeInsets.zero,
      dense: true,
      activeThumbColor: AppColors.accent,
      value: value,
      onChanged: onChanged,
      title: Text(
        label,
        style: const TextStyle(color: AppColors.textPrimary, fontSize: 15),
      ),
      subtitle: Text(
        detail,
        style: const TextStyle(color: AppColors.textMuted, fontSize: 12.5),
      ),
    );
  }
}

/// A row of mutually-exclusive choices rendered as chips.
class _ChoiceRow<T> extends StatelessWidget {
  final List<T> options;
  final T selected;
  final String Function(T) label;
  final ValueChanged<T> onSelect;
  const _ChoiceRow({
    required this.options,
    required this.selected,
    required this.label,
    required this.onSelect,
  });

  @override
  Widget build(BuildContext context) {
    return Wrap(
      spacing: 8,
      runSpacing: 8,
      children: [
        for (final o in options)
          GestureDetector(
            onTap: () => onSelect(o),
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
              decoration: BoxDecoration(
                color: o == selected
                    ? AppColors.accent.withValues(alpha: 0.18)
                    : AppColors.surfaceAlt,
                borderRadius: AppRadius.all(20),
                border: Border.all(
                  color: o == selected ? AppColors.accent : AppColors.border,
                ),
              ),
              child: Text(
                label(o),
                style: TextStyle(
                  color: o == selected
                      ? AppColors.accent
                      : AppColors.textPrimary,
                  fontSize: 13.5,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ),
          ),
      ],
    );
  }
}

/// A full-width secondary action inside a section.
class _ActionButton extends StatelessWidget {
  final IconData icon;
  final String label;
  final Color? color;
  final VoidCallback? onPressed;
  const _ActionButton({
    required this.icon,
    required this.label,
    this.color,
    this.onPressed,
  });

  @override
  Widget build(BuildContext context) {
    final c = color ?? AppColors.textPrimary;
    return SizedBox(
      width: double.infinity,
      child: OutlinedButton.icon(
        onPressed: onPressed,
        icon: Icon(icon, size: 18, color: c),
        label: Text(label, style: TextStyle(color: c)),
        style: OutlinedButton.styleFrom(
          side: const BorderSide(color: AppColors.border),
          shape: RoundedRectangleBorder(
            borderRadius: AppRadius.all(12),
          ),
        ),
      ),
    );
  }
}

/// A read-only "label — value" line.
class _InfoRow extends StatelessWidget {
  final String label;
  final String value;
  const _InfoRow({required this.label, required this.value});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 5),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            label,
            style: const TextStyle(color: AppColors.textMuted, fontSize: 14),
          ),
          const SizedBox(width: 16),
          Expanded(
            child: Text(
              value,
              textAlign: TextAlign.right,
              style: const TextStyle(
                color: AppColors.textPrimary,
                fontSize: 14,
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

void _toast(BuildContext context, String message) {
  ScaffoldMessenger.of(context)
    ..clearSnackBars()
    ..showSnackBar(
      SnackBar(behavior: SnackBarBehavior.floating, content: Text(message)),
    );
}

// ---- Playback ---------------------------------------------------------------

class _PlaybackTab extends StatelessWidget {
  const _PlaybackTab();

  static const _speeds = [0.75, 1.0, 1.25, 1.5, 1.75, 2.0];

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: settingsState,
      builder: (context, _) => ListView(
        padding: const EdgeInsets.all(16),
        children: [
          _Section(
            title: 'Streaming quality',
            subtitle:
                'The ceiling the server transcodes to before sending audio. '
                'Original is best over a LAN or a fast overlay network.',
            children: [
              _ChoiceRow<StreamQuality>(
                options: StreamQuality.values,
                selected: settingsState.quality,
                label: (q) => q.label,
                onSelect: (q) async {
                  await settingsState.setQuality(q);
                  if (context.mounted) {
                    _toast(context, 'Applies to the next track you start');
                  }
                },
              ),
              const SizedBox(height: 8),
              Text(
                settingsState.quality.detail,
                style: const TextStyle(
                  color: AppColors.textFaint,
                  fontSize: 12.5,
                ),
              ),
            ],
          ),
          _Section(
            title: 'Speed',
            subtitle: 'Applies to music and audiobooks alike.',
            children: [
              _ChoiceRow<double>(
                options: _speeds,
                selected: settingsState.playbackSpeed,
                label: (s) => '$s×',
                onSelect: (s) async {
                  await settingsState.setPlaybackSpeed(s);
                  await playerService.applyAudioSettings();
                },
              ),
            ],
          ),
          _Section(
            title: 'Behaviour',
            children: [
              _SwitchRow(
                label: 'Trim silence',
                detail: 'Skip silent stretches — most useful in audiobooks.',
                value: settingsState.skipSilence,
                onChanged: (v) async {
                  await settingsState.setSkipSilence(v);
                  await playerService.applyAudioSettings();
                },
              ),
              _SwitchRow(
                label: 'Resume where I left off',
                detail:
                    'Reload the last queue, paused at its saved spot, on launch.',
                value: settingsState.resumeOnLaunch,
                onChanged: settingsState.setResumeOnLaunch,
              ),
              // Lives here rather than in the Studio: the Studio's decks are
              // about how the app is drawn, and this is about how it moves.
              _SwitchRow(
                label: 'Reduce motion',
                detail: 'Drops the cover-art fade and the navigation bounce.',
                value: settingsState.reduceMotion,
                onChanged: settingsState.setReduceMotion,
              ),
            ],
          ),
        ],
      ),
    );
  }
}

// ---- Storage ----------------------------------------------------------------

class _StorageTab extends StatefulWidget {
  const _StorageTab();

  @override
  State<_StorageTab> createState() => _StorageTabState();
}

class _StorageTabState extends State<_StorageTab> {
  static const _cacheSizes = [50, 100, 200, 400];

  int _tempBytes = 0;
  bool _measuring = true;

  @override
  void initState() {
    super.initState();
    _measure();
  }

  /// Temporary files: the audio clips the "what's playing?" identifier records
  /// and anything else dropped in the cache directory.
  Future<void> _measure() async {
    var total = 0;
    try {
      final dir = await getTemporaryDirectory();
      await for (final e in dir.list(recursive: true, followLinks: false)) {
        if (e is File) {
          try {
            total += await e.length();
          } catch (_) {}
        }
      }
    } catch (_) {}
    if (mounted) {
      setState(() {
        _tempBytes = total;
        _measuring = false;
      });
    }
  }

  Future<void> _clearTemp() async {
    try {
      final dir = await getTemporaryDirectory();
      await for (final e in dir.list(followLinks: false)) {
        try {
          await e.delete(recursive: true);
        } catch (_) {}
      }
    } catch (_) {}
    if (mounted) {
      setState(() => _measuring = true);
      await _measure();
      if (mounted) _toast(context, 'Temporary files cleared');
    }
  }

  static String _mb(int bytes) =>
      '${(bytes / (1024 * 1024)).toStringAsFixed(1)} MB';

  @override
  Widget build(BuildContext context) {
    final cache = PaintingBinding.instance.imageCache;
    return ListenableBuilder(
      listenable: settingsState,
      builder: (context, _) => ListView(
        padding: const EdgeInsets.all(16),
        children: [
          _Section(
            title: 'Artwork cache',
            subtitle:
                'Decoded cover art held in memory. More keeps scrolling smooth; '
                'less frees memory on a small device.',
            children: [
              _ChoiceRow<int>(
                options: _cacheSizes,
                selected: settingsState.imageCacheMb,
                label: (mb) => '$mb MB',
                onSelect: (mb) async {
                  await settingsState.setImageCacheMb(mb);
                  if (mounted) setState(() {});
                },
              ),
              const SizedBox(height: 10),
              _InfoRow(
                label: 'In use',
                value: '${_mb(cache.currentSizeBytes)} · '
                    '${cache.currentSize} images',
              ),
              const SizedBox(height: 8),
              _ActionButton(
                icon: SolarIconsOutline.broom,
                label: 'Clear artwork cache',
                onPressed: () {
                  cache.clear();
                  cache.clearLiveImages();
                  setState(() {});
                  _toast(context, 'Artwork cache cleared');
                },
              ),
            ],
          ),
          _Section(
            title: 'Temporary files',
            subtitle:
                'Scratch files the app writes — recorded clips for track '
                'identification, and downloads in flight.',
            children: [
              _InfoRow(
                label: 'On disk',
                value: _measuring ? 'measuring…' : _mb(_tempBytes),
              ),
              const SizedBox(height: 8),
              _ActionButton(
                icon: SolarIconsOutline.trashBinMinimalistic,
                label: 'Delete temporary files',
                onPressed: _measuring ? null : _clearTemp,
              ),
            ],
          ),
          _Section(
            title: 'Saved playback session',
            subtitle:
                'The queue and position this account resumes from on launch.',
            children: [
              _ActionButton(
                icon: SolarIconsOutline.playCircle,
                label: 'Forget saved queue',
                color: const Color(0xFFE0605A),
                onPressed: () async {
                  await playerService.stop();
                  if (context.mounted) {
                    _toast(context, 'Saved queue forgotten');
                  }
                },
              ),
            ],
          ),
        ],
      ),
    );
  }
}

// ---- Server (connectors) ----------------------------------------------------

class _ServerTab extends StatelessWidget {
  const _ServerTab();

  static void _manage(BuildContext context, ConnectorKind kind) {
    Navigator.of(context).push(
      MaterialPageRoute(builder: (_) => ConnectorSetupScreen(kind: kind)),
    );
  }

  /// Forget a connector for the active account (server-side), then re-check so
  /// the card flips to "Off".
  static Future<void> _disconnect(String kind) async {
    await automationState.client?.deleteConnector(kind);
    if (kind == 'abs') {
      await absState.refresh();
    } else {
      await appState.refreshConnector();
    }
  }

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: Listenable.merge([appState, absState, automationState]),
      builder: (context, _) {
        final account = automationState.active;
        return ListView(
          padding: const EdgeInsets.all(16),
          children: [
            _Section(
              title: 'Musillow backend',
              subtitle:
                  'Everything — metadata, audio, artwork, recommendations — '
                  'goes through this one address.',
              children: [
                _InfoRow(label: 'Address', value: account?.url ?? '—'),
                _InfoRow(label: 'Signed in as', value: account?.username ?? '—'),
                const SizedBox(height: 8),
                _ActionButton(
                  icon: SolarIconsOutline.refresh,
                  label: 'Check connection',
                  onPressed: () async {
                    var ok = false;
                    try {
                      await automationState.client?.me();
                      ok = true;
                    } catch (_) {}
                    if (context.mounted) {
                      _toast(
                        context,
                        ok ? 'Backend reachable' : "Couldn't reach the backend",
                      );
                    }
                  },
                ),
              ],
            ),
            _ConnectorCard(
              icon: ConnectorKind.navidrome.icon,
              color: ConnectorKind.navidrome.color,
              name: ConnectorKind.navidrome.title,
              subtitle: 'Music library',
              connected: appState.navidromeReady,
              onManage: () => _manage(context, ConnectorKind.navidrome),
              onDisconnect: appState.navidromeReady
                  ? () => _disconnect('navidrome')
                  : null,
            ),
            const SizedBox(height: 14),
            _ConnectorCard(
              icon: ConnectorKind.audiobookshelf.icon,
              color: ConnectorKind.audiobookshelf.color,
              name: ConnectorKind.audiobookshelf.title,
              subtitle: 'Audiobooks, authors & series',
              connected: absState.isConnected,
              onManage: () => _manage(context, ConnectorKind.audiobookshelf),
              onDisconnect: absState.isConnected
                  ? () => _disconnect('abs')
                  : null,
            ),
          ],
        );
      },
    );
  }
}

class _ConnectorCard extends StatelessWidget {
  final IconData icon;
  final Color color;
  final String name;
  final String subtitle;
  final bool connected;
  final VoidCallback onManage;
  final VoidCallback? onDisconnect;
  const _ConnectorCard({
    required this.icon,
    required this.color,
    required this.name,
    required this.subtitle,
    required this.connected,
    required this.onManage,
    this.onDisconnect,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: AppRadius.all(18),
        border: Border.all(color: AppColors.border),
      ),
      child: Column(
        children: [
          Row(
            children: [
              Container(
                width: 46,
                height: 46,
                decoration: BoxDecoration(
                  color: color.withValues(alpha: 0.9),
                  borderRadius: AppRadius.all(12),
                ),
                child: Icon(icon, color: Colors.white, size: 24),
              ),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      name,
                      style: const TextStyle(
                        color: AppColors.textPrimary,
                        fontSize: 16,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                    Text(
                      subtitle,
                      style: const TextStyle(
                        color: AppColors.textMuted,
                        fontSize: 13,
                      ),
                    ),
                  ],
                ),
              ),
              _StatusChip(connected: connected),
            ],
          ),
          const SizedBox(height: 14),
          Row(
            children: [
              Expanded(
                child: OutlinedButton(
                  onPressed: onManage,
                  style: OutlinedButton.styleFrom(
                    foregroundColor: AppColors.textPrimary,
                    side: const BorderSide(color: AppColors.border),
                    shape: RoundedRectangleBorder(
                      borderRadius: AppRadius.all(12),
                    ),
                  ),
                  child: Text(connected ? 'Reconnect' : 'Connect'),
                ),
              ),
              if (onDisconnect != null) ...[
                const SizedBox(width: 10),
                IconButton(
                  onPressed: onDisconnect,
                  tooltip: 'Disconnect',
                  icon: const Icon(
                    SolarIconsOutline.logout,
                    color: AppColors.textMuted,
                  ),
                ),
              ],
            ],
          ),
        ],
      ),
    );
  }
}

class _StatusChip extends StatelessWidget {
  final bool connected;
  const _StatusChip({required this.connected});

  @override
  Widget build(BuildContext context) {
    final c = connected ? AppColors.teal : AppColors.textFaint;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
      decoration: BoxDecoration(
        color: c.withValues(alpha: 0.15),
        borderRadius: AppRadius.all(20),
      ),
      child: Text(
        connected ? 'Connected' : 'Off',
        style: TextStyle(color: c, fontSize: 12, fontWeight: FontWeight.w700),
      ),
    );
  }
}

// ---- Stats ------------------------------------------------------------------

/// Audiobookshelf listening stats (best-effort).
class _StatsTab extends StatelessWidget {
  const _StatsTab();

  @override
  Widget build(BuildContext context) {
    // Rebuild when the connector is confirmed, so opening this tab straight
    // after an account switch doesn't stick on the "not connected" copy.
    return ListenableBuilder(
      listenable: absState,
      builder: (context, _) => _body(),
    );
  }

  Widget _body() {
    // The client exists for any signed-in account; stats need ABS actually
    // configured on the backend for it.
    final client = absState.client;
    if (client == null || !absState.isConnected) {
      return _centered('Connect Audiobookshelf to see your listening stats.');
    }
    return FutureBuilder<AbsStats?>(
      future: client.stats(),
      builder: (context, snap) {
        if (snap.connectionState == ConnectionState.waiting) {
          return Center(
            child: CircularProgressIndicator(color: AppColors.accent),
          );
        }
        final s = snap.data;
        if (s == null) return _centered('Stats are unavailable right now.');
        return ListView(
          padding: const EdgeInsets.all(16),
          children: [
            _StatTile(
              label: 'Hours listened',
              value: s.totalHours.toStringAsFixed(1),
            ),
            _StatTile(label: 'Books finished', value: '${s.itemsFinished}'),
            _StatTile(label: 'Days listened', value: '${s.daysListened}'),
          ],
        );
      },
    );
  }

  Widget _centered(String t) => Padding(
    padding: const EdgeInsets.all(32),
    child: Center(
      child: Text(
        t,
        textAlign: TextAlign.center,
        style: const TextStyle(color: AppColors.textFaint),
      ),
    ),
  );
}

class _StatTile extends StatelessWidget {
  final String label;
  final String value;
  const _StatTile({required this.label, required this.value});

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: AppRadius.all(16),
        border: Border.all(color: AppColors.border),
      ),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(
            label,
            style: const TextStyle(color: AppColors.textMuted, fontSize: 15),
          ),
          Text(
            value,
            style: const TextStyle(
              color: AppColors.textPrimary,
              fontSize: 22,
              fontWeight: FontWeight.w800,
            ),
          ),
        ],
      ),
    );
  }
}

// ---- About ------------------------------------------------------------------

class _AboutTab extends StatelessWidget {
  const _AboutTab();

  static const _version = '1.0.0';

  @override
  Widget build(BuildContext context) {
    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        const _Section(
          title: 'Musillow',
          subtitle:
              'A self-hosted client for your own music and audiobooks. Your '
              'library stays on your server; the app is just the front of it.',
          children: [
            _InfoRow(label: 'Version', value: _version),
          ],
        ),
        const _Section(
          title: 'What it talks to',
          children: [
            _InfoRow(label: 'Music', value: 'Navidrome (Subsonic)'),
            _InfoRow(label: 'Audiobooks', value: 'Audiobookshelf'),
            _InfoRow(label: 'Backend', value: 'Musillow API'),
          ],
        ),
        _Section(
          title: 'Licences',
          subtitle: 'The open-source packages this app is built on.',
          children: [
            _ActionButton(
              icon: SolarIconsOutline.documentText,
              label: 'Open-source licences',
              onPressed: () => showLicensePage(
                context: context,
                applicationName: 'Musillow',
                applicationVersion: _version,
                applicationLegalese:
                    'A self-hosted music & audiobook client.',
              ),
            ),
          ],
        ),
      ],
    );
  }
}
