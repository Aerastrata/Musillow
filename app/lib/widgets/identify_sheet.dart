import 'package:flutter/material.dart';
import 'package:solar_icons/solar_icons.dart';

import '../services/automation_client.dart';
import '../services/identify_service.dart';
import '../theme.dart';

/// The "what's playing?" sheet: listens, matches, then offers the result.
///
/// Pops with the recognised [CatalogResult] when the user accepts it, so the
/// caller can drop it into search; pops with null if they back out.
class IdentifySheet extends StatefulWidget {
  const IdentifySheet({super.key});

  @override
  State<IdentifySheet> createState() => _IdentifySheetState();
}

class _IdentifySheetState extends State<IdentifySheet>
    with SingleTickerProviderStateMixin {
  late final AnimationController _pulse = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 1400),
  )..repeat();

  @override
  void initState() {
    super.initState();
    // Start listening as soon as the sheet is on screen.
    WidgetsBinding.instance.addPostFrameCallback((_) => identifyService.run());
  }

  @override
  void dispose() {
    _pulse.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: identifyService,
      builder: (context, _) {
        final stage = identifyService.stage;
        return Container(
          padding: EdgeInsets.fromLTRB(
            24,
            20,
            24,
            24 + MediaQuery.of(context).viewInsets.bottom,
          ),
          decoration: BoxDecoration(
            color: AppColors.surface,
            borderRadius: AppRadius.top(28),
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                width: 44,
                height: 4,
                decoration: BoxDecoration(
                  color: AppColors.border,
                  borderRadius: AppRadius.all(2),
                ),
              ),
              const SizedBox(height: 26),
              if (stage == IdentifyStage.done && identifyService.match != null)
                ..._matchView(identifyService.match!)
              else if (stage == IdentifyStage.failed)
                ..._failedView()
              else
                ..._listeningView(stage),
              const SizedBox(height: 8),
            ],
          ),
        );
      },
    );
  }

  // ---- States --------------------------------------------------------------

  List<Widget> _listeningView(IdentifyStage stage) {
    final listening = stage == IdentifyStage.listening;
    return [
      AnimatedBuilder(
        animation: _pulse,
        builder: (context, child) {
          // Two rings expanding out of the mic, offset so there's always one
          // mid-flight — a cheap "it's hearing you" cue.
          return SizedBox(
            width: 140,
            height: 140,
            child: Stack(
              alignment: Alignment.center,
              children: [
                for (final phase in const [0.0, 0.5])
                  _ring((_pulse.value + phase) % 1.0),
                child!,
              ],
            ),
          );
        },
        child: Container(
          width: 78,
          height: 78,
          decoration: BoxDecoration(
            color: AppColors.accent,
            shape: BoxShape.circle,
          ),
          child: const Icon(
            SolarIconsBold.microphone,
            color: Colors.white,
            size: 34,
          ),
        ),
      ),
      const SizedBox(height: 22),
      Text(
        listening ? 'Listening…' : 'Matching…',
        style: const TextStyle(
          color: AppColors.textPrimary,
          fontSize: 19,
          fontWeight: FontWeight.w800,
        ),
      ),
      const SizedBox(height: 6),
      Text(
        listening
            ? 'Hold your phone towards the music.'
            : 'Checking what that was.',
        textAlign: TextAlign.center,
        style: const TextStyle(color: AppColors.textMuted),
      ),
      const SizedBox(height: 22),
      TextButton(
        onPressed: () => Navigator.of(context).pop(),
        child: const Text(
          'Cancel',
          style: TextStyle(color: AppColors.textMuted),
        ),
      ),
    ];
  }

  Widget _ring(double t) {
    return Opacity(
      opacity: (1 - t) * 0.45,
      child: Container(
        width: 78 + t * 62,
        height: 78 + t * 62,
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          border: Border.all(color: AppColors.accent, width: 2),
        ),
      ),
    );
  }

  List<Widget> _failedView() {
    return [
      const Icon(
        SolarIconsOutline.microphone,
        size: 54,
        color: AppColors.textFaint,
      ),
      const SizedBox(height: 18),
      Text(
        identifyService.error ?? 'No match.',
        textAlign: TextAlign.center,
        style: const TextStyle(
          color: AppColors.textPrimary,
          fontSize: 17,
          fontWeight: FontWeight.w700,
        ),
      ),
      const SizedBox(height: 20),
      Row(
        children: [
          Expanded(
            child: OutlinedButton(
              onPressed: () => Navigator.of(context).pop(),
              style: OutlinedButton.styleFrom(
                foregroundColor: AppColors.textPrimary,
                side: const BorderSide(color: AppColors.border),
                padding: const EdgeInsets.symmetric(vertical: 14),
                shape: RoundedRectangleBorder(
                  borderRadius: AppRadius.all(14),
                ),
              ),
              child: const Text('Close'),
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: FilledButton(
              onPressed: identifyService.run,
              style: FilledButton.styleFrom(
                backgroundColor: AppColors.accent,
                padding: const EdgeInsets.symmetric(vertical: 14),
                shape: RoundedRectangleBorder(
                  borderRadius: AppRadius.all(14),
                ),
              ),
              child: const Text('Try again'),
            ),
          ),
        ],
      ),
    ];
  }

  List<Widget> _matchView(CatalogResult match) {
    return [
      ClipRRect(
        borderRadius: AppRadius.all(18),
        child: match.artworkUrl != null
            ? Image.network(
                match.artworkUrl!,
                width: 148,
                height: 148,
                fit: BoxFit.cover,
                errorBuilder: (context, error, stack) => _artFallback(),
              )
            : _artFallback(),
      ),
      const SizedBox(height: 18),
      Text(
        match.title,
        textAlign: TextAlign.center,
        maxLines: 2,
        overflow: TextOverflow.ellipsis,
        style: const TextStyle(
          color: AppColors.textPrimary,
          fontSize: 21,
          fontWeight: FontWeight.w800,
        ),
      ),
      const SizedBox(height: 4),
      Text(
        [match.artist, if (match.year != null) match.year!].join(' • '),
        textAlign: TextAlign.center,
        style: const TextStyle(color: AppColors.textMuted, fontSize: 15),
      ),
      if (match.owned) ...[
        const SizedBox(height: 10),
        const _Chip(label: 'Already in your library', color: AppColors.teal),
      ],
      const SizedBox(height: 22),
      Row(
        children: [
          Expanded(
            child: OutlinedButton(
              onPressed: identifyService.run,
              style: OutlinedButton.styleFrom(
                foregroundColor: AppColors.textPrimary,
                side: const BorderSide(color: AppColors.border),
                padding: const EdgeInsets.symmetric(vertical: 14),
                shape: RoundedRectangleBorder(
                  borderRadius: AppRadius.all(14),
                ),
              ),
              child: const Text('Again'),
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            flex: 2,
            child: FilledButton(
              onPressed: () => Navigator.of(context).pop(match),
              style: FilledButton.styleFrom(
                backgroundColor: AppColors.accent,
                padding: const EdgeInsets.symmetric(vertical: 14),
                shape: RoundedRectangleBorder(
                  borderRadius: AppRadius.all(14),
                ),
              ),
              child: const Text(
                'Show in search',
                style: TextStyle(fontWeight: FontWeight.w700),
              ),
            ),
          ),
        ],
      ),
    ];
  }

  Widget _artFallback() => Container(
    width: 148,
    height: 148,
    color: AppColors.surfaceAlt,
    child: const Icon(
      SolarIconsBold.musicNote,
      color: AppColors.textFaint,
      size: 44,
    ),
  );
}

class _Chip extends StatelessWidget {
  final String label;
  final Color color;
  const _Chip({required this.label, required this.color});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.15),
        borderRadius: AppRadius.all(20),
      ),
      child: Text(
        label,
        style: TextStyle(
          color: color,
          fontSize: 12.5,
          fontWeight: FontWeight.w700,
        ),
      ),
    );
  }
}
