import 'package:flutter/material.dart';

import '../services/settings_state.dart';
import '../theme.dart';
import '../services/icon_registry.dart';
import 'app_icon.dart';

/// One destination in the bottom bar.
class BouncyNavItem {
  /// Icon slots rather than glyphs, so both states are retheme-able.
  final IconSlot icon; // shown when idle
  final IconSlot activeIcon; // shown when selected
  final String label;
  final Color color;

  const BouncyNavItem({
    required this.icon,
    required this.activeIcon,
    required this.label,
    required this.color,
  });
}

/// A floating bottom navigation bar.
///
/// Every destination always shows its icon *and* label. The selected one is
/// distinguished purely by a color change and a slightly larger, bolder label —
/// no background pill — and pops in with an elastic "bounce" whenever the
/// selection changes. Items are equal width, so selecting one never shoves the
/// others aside.
class BouncyNavBar extends StatefulWidget {
  final List<BouncyNavItem> items;
  final int currentIndex;
  final ValueChanged<int> onSelect;

  const BouncyNavBar({
    super.key,
    required this.items,
    required this.currentIndex,
    required this.onSelect,
  });

  @override
  State<BouncyNavBar> createState() => _BouncyNavBarState();
}

class _BouncyNavBarState extends State<BouncyNavBar>
    with SingleTickerProviderStateMixin {
  late final AnimationController _bounce;

  @override
  void initState() {
    super.initState();
    _bounce = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 620),
    )..forward();
  }

  @override
  void didUpdateWidget(covariant BouncyNavBar old) {
    super.didUpdateWidget(old);
    // Re-fire the elastic pop whenever the selection changes.
    if (old.currentIndex != widget.currentIndex) {
      _bounce.forward(from: 0);
    }
  }

  @override
  void dispose() {
    _bounce.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final bottomInset = MediaQuery.of(context).padding.bottom;

    // Transparent row; the surrounding bottom panel provides the background.
    // Equal top/bottom padding keeps the icons symmetric; only half the
    // safe-area inset is reserved below so the row sits lower (nearer the edge)
    // instead of floating high in a tall panel.
    final pad = 10 + bottomInset * 0.5;
    return Padding(
      padding: EdgeInsets.fromLTRB(8, pad, 8, pad),
      child: Row(
        children: [
          for (var i = 0; i < widget.items.length; i++)
            _NavButton(
              item: widget.items[i],
              selected: i == widget.currentIndex,
              bounce: _bounce,
              onTap: () => widget.onSelect(i),
            ),
        ],
      ),
    );
  }
}

class _NavButton extends StatelessWidget {
  final BouncyNavItem item;
  final bool selected;
  final Animation<double> bounce;
  final VoidCallback onTap;

  const _NavButton({
    required this.item,
    required this.selected,
    required this.bounce,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final color = selected ? item.color : AppColors.textMuted;

    // "Reduce motion" keeps every state change but removes the travel: the
    // transitions collapse to zero-length and the elastic pop is skipped.
    final still = settingsState.reduceMotion;

    Widget content = Column(
      mainAxisSize: MainAxisSize.min,
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        AnimatedScale(
          scale: selected ? 1.12 : 1.0,
          duration: Duration(milliseconds: still ? 0 : 240),
          curve: Curves.easeOutBack,
          child: AppIcon(
            selected ? item.activeIcon : item.icon,
            color: color,
            size: 24,
          ),
        ),
        const SizedBox(height: 4),
        // Label is always present; grows and brightens when selected.
        AnimatedDefaultTextStyle(
          duration: Duration(milliseconds: still ? 0 : 220),
          style: TextStyle(
            color: color,
            fontSize: selected ? 12.5 : 11,
            fontWeight: selected ? FontWeight.w700 : FontWeight.w500,
          ),
          child: Text(item.label),
        ),
      ],
    );

    // Elastic bounce (scale overshoot + small hop) on the freshly-selected item.
    if (selected && !still) {
      final pop = CurvedAnimation(parent: bounce, curve: Curves.elasticOut);
      content = AnimatedBuilder(
        animation: pop,
        builder: (context, child) {
          final t = pop.value; // overshoots past 1.0, then settles.
          final scale = 0.88 + 0.12 * t;
          final hop = -4.0 * (1.0 - (t - 1.0).abs()).clamp(0.0, 1.0);
          return Transform.translate(
            offset: Offset(0, hop),
            child: Transform.scale(scale: scale, child: child),
          );
        },
        child: content,
      );
    }

    return Expanded(
      child: GestureDetector(
        onTap: onTap,
        behavior: HitTestBehavior.opaque,
        child: content,
      ),
    );
  }
}
