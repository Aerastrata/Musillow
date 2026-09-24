import 'package:flutter/material.dart';
import 'package:solar_icons/solar_icons.dart';

import '../services/appearance_state.dart';
import '../services/home_layout.dart';
import '../services/icon_registry.dart';
import '../services/settings_state.dart';
import '../theme.dart';
import '../widgets/app_icon.dart';
import '../widgets/colour_wheel.dart';
import '../widgets/studio_mock.dart';
import 'icon_picker_screen.dart';
import 'custom_block_editor.dart';
import 'custom_blocks_screen.dart';
import 'studio_templates.dart';

/// The Studio: change how the app looks against a preview of it.
///
/// The previews are stand-ins the Studio draws itself, not the running screens.
/// That means every icon and module is a real child widget it can hand a tap
/// handler to — editing is exact rather than guessed from screen coordinates —
/// and the player previews the same whether or not anything is playing.
class StudioScreen extends StatefulWidget {
  const StudioScreen({super.key});

  @override
  State<StudioScreen> createState() => _StudioScreenState();
}

class _StudioScreenState extends State<StudioScreen> {
  late final PageController _pages = PageController(viewportFraction: 0.78);
  late final PageController _decks = PageController();
  int _index = 0;
  int _deck = 0;

  /// The settings categories, in the order they're paged through.
  static const _categories = ['Accent colour', 'Text', 'Corners'];

  /// How many spare "add your own" cards trail the font grid.
  static const _emptyFontSlots = 2;

  @override
  void dispose() {
    _pages.dispose();
    _decks.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Studio'),
        titleTextStyle: const TextStyle(
          color: AppColors.textPrimary,
          fontSize: 20,
          fontWeight: FontWeight.w800,
        ),
        actions: [
          IconButton(
            tooltip: 'Blocks',
            icon: const Icon(
              SolarIconsOutline.widget,
              color: AppColors.textMuted,
            ),
            onPressed: () => Navigator.of(context).push(
              MaterialPageRoute(builder: (_) => const CustomBlocksScreen()),
            ),
          ),
          IconButton(
            tooltip: 'Templates',
            icon: const Icon(
              SolarIconsOutline.bookmark,
              color: AppColors.textMuted,
            ),
            onPressed: () => Navigator.of(context).push(
              MaterialPageRoute(builder: (_) => const StudioTemplatesScreen()),
            ),
          ),
        ],
      ),
      body: ListenableBuilder(
        listenable: Listenable.merge([
          appearanceState,
          iconRegistry,
          homeLayout,
          settingsState,
        ]),
        // Nothing here scrolls vertically: the two decks page sideways and the
        // preview takes whatever height is left over, so the whole Studio is
        // one screen however tall the phone is.
        builder: (context, _) => SafeArea(
          top: false,
          child: LayoutBuilder(
            builder: (context, box) => Column(
              children: [
                Expanded(child: _previewPager()),
                const SizedBox(height: 8),
                _dots(_index, StudioPage.values.length),
                const SizedBox(height: 12),
                SizedBox(
                  height: _deckHeight(box.maxHeight),
                  child: _settingsPager(),
                ),
                const SizedBox(height: 10),
                _dots(_deck, _categories.length),
                const SizedBox(height: 6),
              ],
            ),
          ),
        ),
      ),
    );
  }

  /// What the previews are keyed on, so a change to any deck redraws them.
  ///
  /// Text size is in here as well as the appearance: it isn't part of
  /// [AppearanceState] but it does change how the previews lay out.
  String get _stamp => '${appearanceState.stamp}|${settingsState.textScale}';

  /// How much of the screen the settings deck claims.
  ///
  /// It grows with the text size — the same controls need more room in Largest
  /// — but never past half the screen, so the preview stays the bigger half.
  double _deckHeight(double available) =>
      (232 * settingsState.textScale).clamp(180.0, available * 0.5);

  /// The swipeable carousel of screen stand-ins.
  Widget _previewPager() {
    final screen = MediaQuery.of(context).size;
    return PageView.builder(
      controller: _pages,
      onPageChanged: (i) => setState(() => _index = i),
      itemCount: StudioPage.values.length,
      itemBuilder: (context, i) {
        final page = StudioPage.values[i];
        return Padding(
          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
          child: GestureDetector(
            onTap: () => _openEditor(page),
            child: ClipRRect(
              borderRadius: AppRadius.all(26),
              child: FittedBox(
                fit: BoxFit.contain,
                child: SizedBox(
                  width: screen.width,
                  height: screen.height,
                  // Not interactive here — the small preview is for choosing a
                  // screen, the full-size one is for editing it.
                  child: AbsorbPointer(
                    child: KeyedSubtree(
                      key: ValueKey(_stamp),
                      child: MockScreen(page: page),
                    ),
                  ),
                ),
              ),
            ),
          ),
        );
      },
    );
  }

  Widget _dots(int active, int count) => Row(
    mainAxisAlignment: MainAxisAlignment.center,
    children: [
      for (var i = 0; i < count; i++)
        AnimatedContainer(
          duration: const Duration(milliseconds: 200),
          margin: const EdgeInsets.symmetric(horizontal: 3),
          width: i == active ? 20 : 7,
          height: 7,
          decoration: BoxDecoration(
            color: i == active ? AppColors.accent : AppColors.border,
            borderRadius: BorderRadius.circular(4),
          ),
        ),
    ],
  );

  void _openEditor(StudioPage page) => Navigator.of(context).push(
    MaterialPageRoute(builder: (_) => StudioEditorScreen(page: page)),
  );

  Widget _settingsPager() => PageView(
    controller: _decks,
    onPageChanged: (i) => setState(() => _deck = i),
    children: [_accentDeck(), _textDeck(), _cornersDeck()],
  );

  // ---- The three decks -----------------------------------------------------

  /// The presets as a 3x3, the live wheel beside them.
  ///
  /// Nine cells for eight presets plus the wheel's own colour, so the grid is
  /// exactly full — and the ninth is not a button that opens a picker, it *is*
  /// whatever the wheel is currently pointing at.
  Widget _accentDeck() {
    final swatches = <Widget>[
      for (final a in AccentChoice.values)
        _Swatch(
          color: a.color,
          label: a.label,
          selected:
              appearanceState.customAccent == null &&
              appearanceState.accent == a,
          onTap: () => appearanceState.setAccent(a),
        ),
      _CustomSwatch(
        colour: appearanceState.customAccent,
        // With no colour picked yet this adopts wherever the wheel is sitting,
        // which is the accent's own position — so it's a no-op that switches
        // the selection from "preset" to "mine", ready to be dragged.
        onTap: () => appearanceState.setCustomAccent(AppColors.accent),
      ),
    ];
    final colour = AppColors.accent;
    return _Deck(
      title: _categories[0],
      child: Row(
        children: [
          // Packed rather than spread: the swatches only need to be far
          // enough apart to hit, and everything they give up goes to the
          // wheel, which is the control that benefits from size.
          Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              for (var row = 0; row < 3; row++)
                Padding(
                  padding: const EdgeInsets.symmetric(vertical: 4),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      for (var col = 0; col < 3; col++)
                        Padding(
                          padding: const EdgeInsets.symmetric(horizontal: 4),
                          child: swatches[row * 3 + col],
                        ),
                    ],
                  ),
                ),
            ],
          ),
          const SizedBox(width: 12),
          Expanded(
            child: LayoutBuilder(
              builder: (context, box) {
                // The wheel is square, so it's bounded by whichever axis runs
                // out first once the brightness track and hex have their rows.
                final dial = (box.maxHeight - 44).clamp(60.0, box.maxWidth);
                return Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    ColourWheelDial(
                      colour: colour,
                      size: dial,
                      // Live while dragging, written once the finger lifts.
                      onChanged: (c) =>
                          appearanceState.setCustomAccent(c, persist: false),
                      onChangeEnd: appearanceState.setCustomAccent,
                    ),
                    Text(
                      '#${colour.toARGB32().toRadixString(16).substring(2).toUpperCase()}',
                      style: const TextStyle(
                        color: AppColors.textMuted,
                        fontSize: 11.5,
                        fontWeight: FontWeight.w700,
                        letterSpacing: 0.6,
                      ),
                    ),
                  ],
                );
              },
            ),
          ),
        ],
      ),
    );
  }

  /// The faces on offer, then how big to set them.
  ///
  /// The faces are a two-row grid that scrolls *sideways*, so adding your own
  /// fonts extends it along the only axis this screen scrolls on.
  Widget _textDeck() {
    final families = <_FontOption>[
      for (final f in AppFont.values)
        _FontOption(f.label, f.family, () => appearanceState.setFont(f)),
      for (final family in appearanceState.customFonts.keys)
        _FontOption(
          family,
          family,
          () => appearanceState.useFamily(family),
          onRemove: () => appearanceState.removeCustomFont(family),
        ),
    ];
    return _Deck(
      title: _categories[1],
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Expanded(
            // Cells are measured rather than given a fixed ratio so that
            // exactly six — the four faces plus two spare slots — fill the
            // deck with nothing cut off. Adding your own fonts pushes past
            // six and the grid then scrolls sideways for the extras.
            child: LayoutBuilder(
              builder: (context, box) {
                const gap = 9.0;
                final cell = Size(
                  (box.maxWidth - gap * 2) / 3,
                  (box.maxHeight - gap) / 2,
                );
                return GridView.builder(
                  scrollDirection: Axis.horizontal,
                  padding: EdgeInsets.zero,
                  gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
                    crossAxisCount: 2,
                    mainAxisSpacing: gap,
                    crossAxisSpacing: gap,
                    childAspectRatio: cell.height / cell.width,
                  ),
                  itemCount: families.length + _emptyFontSlots,
                  itemBuilder: (context, i) {
                    if (i >= families.length) {
                      return _AddFontCard(onTap: () => addCustomFont(context));
                    }
                    final o = families[i];
                    return _FontCard(
                      option: o,
                      selected: appearanceState.fontFamily == o.family,
                    );
                  },
                );
              },
            ),
          ),
          const SizedBox(height: 12),
          SizedBox(
            width: double.infinity,
            child: _Chips<double>(
              alignment: WrapAlignment.center,
              options: const [0.9, 1.0, 1.1, 1.25],
              selected: settingsState.textScale,
              label: (s) => switch (s) {
                0.9 => 'Compact',
                1.0 => 'Default',
                1.1 => 'Large',
                _ => 'Largest',
              },
              onSelect: settingsState.setTextScale,
            ),
          ),
        ],
      ),
    );
  }

  /// Shape and depth, with a card that shows both as you drag them.
  Widget _cornersDeck() => _Deck(
    title: _categories[2],
    child: Row(
      children: [
        Expanded(
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              _TickSlider(
                label: 'Shape',
                value: appearanceState.corners.label,
                index: CornerStyle.values.indexOf(appearanceState.corners),
                count: CornerStyle.values.length,
                onChanged: (i) =>
                    appearanceState.setCorners(CornerStyle.values[i]),
              ),
              const SizedBox(height: 6),
              _TickSlider(
                label: 'Shadow',
                value: appearanceState.shadow.label,
                index: ShadowDepth.values.indexOf(appearanceState.shadow),
                count: ShadowDepth.values.length,
                onChanged: (i) =>
                    appearanceState.setShadow(ShadowDepth.values[i]),
              ),
            ],
          ),
        ),
        const SizedBox(width: 18),
        const _CornerPreview(),
      ],
    ),
  );
}

/// One screen, full size and scrollable, with the editing controls over it.
class StudioEditorScreen extends StatefulWidget {
  final StudioPage page;
  const StudioEditorScreen({super.key, required this.page});

  @override
  State<StudioEditorScreen> createState() => _StudioEditorScreenState();
}

class _StudioEditorScreenState extends State<StudioEditorScreen> {
  StudioMode _mode = StudioMode.icons;
  String? _selected;

  /// Modules only make up the Home page; elsewhere it's icons only.
  bool get _modulesAvailable => widget.page == StudioPage.home;

  Future<void> _editIcon(IconSlot slot) async {
    await Navigator.of(context).push(
      MaterialPageRoute(builder: (_) => IconPickerScreen(slot: slot)),
    );
    if (mounted) setState(() {});
  }

  HomeModule? get _selectedModule {
    for (final m in homeLayout.modules) {
      if (m.uid == _selected) return m;
    }
    return null;
  }

  /// Movement is expressed against the visible order — what the user sees —
  /// because the stored list also holds switched-off modules.
  bool _canMove(HomeModule m, int delta) {
    final visible = homeLayout.visible;
    final i = visible.indexWhere((v) => v.uid == m.uid);
    return i >= 0 && i + delta >= 0 && i + delta < visible.length;
  }

  Future<void> _move(HomeModule m, int delta) async {
    final visible = homeLayout.visible;
    final i = visible.indexWhere((v) => v.uid == m.uid);
    if (i < 0 || i + delta < 0 || i + delta >= visible.length) return;
    final all = homeLayout.modules;
    final from = all.indexWhere((x) => x.uid == m.uid);
    final to = all.indexWhere((x) => x.uid == visible[i + delta].uid);
    if (from < 0 || to < 0) return;
    await homeLayout.move(from, to);
    if (mounted) setState(() {});
  }

  @override
  Widget build(BuildContext context) {
    final moduleMode = _mode == StudioMode.modules && _modulesAvailable;
    return Scaffold(
      backgroundColor: AppColors.background,
      body: ListenableBuilder(
        listenable: Listenable.merge([homeLayout, iconRegistry]),
        builder: (context, _) => Stack(
          children: [
            Positioned.fill(
              child: StudioEdit(
                mode: _mode,
                onIcon: _editIcon,
                selectedModule: moduleMode ? _selected : null,
                onSelectModule: (uid) => setState(
                  () => _selected = _selected == uid ? null : uid,
                ),
                child: KeyedSubtree(
                  key: ValueKey(appearanceState.stamp),
                  child: MockScreen(page: widget.page),
                ),
              ),
            ),
            if (moduleMode && _selectedModule != null)
              _moduleActions(_selectedModule!),
            _floatingControls(moduleMode),
          ],
        ),
      ),
      floatingActionButton: moduleMode
          ? FloatingActionButton(
              backgroundColor: AppColors.accent,
              onPressed: _addModule,
              child: const Icon(Icons.add, color: Colors.white),
            )
          : null,
    );
  }

  /// The actions for whichever module is selected, kept clear of the controls.
  Widget _moduleActions(HomeModule m) => Positioned(
    left: 0,
    right: 0,
    bottom: 92,
    child: Center(
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
        decoration: BoxDecoration(
          color: AppColors.surfaceAlt,
          borderRadius: AppRadius.all(22),
          border: Border.all(color: AppColors.accent),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 6),
              child: Text(
                m.title,
                style: const TextStyle(
                  color: AppColors.textPrimary,
                  fontSize: 13,
                  fontWeight: FontWeight.w700,
                ),
              ),
            ),
            _MiniAction(
              icon: SolarIconsOutline.altArrowUp,
              enabled: _canMove(m, -1),
              onTap: () => _move(m, -1),
            ),
            _MiniAction(
              icon: SolarIconsOutline.altArrowDown,
              enabled: _canMove(m, 1),
              onTap: () => _move(m, 1),
            ),
            if (m.type.repeatable)
              _MiniAction(
                icon: SolarIconsOutline.copy,
                enabled: true,
                onTap: () async {
                  await homeLayout.duplicate(m.uid);
                  if (mounted) setState(() {});
                },
              ),
            _MiniAction(
              icon: SolarIconsOutline.trashBinMinimalistic,
              enabled: true,
              danger: true,
              onTap: () async {
                await homeLayout.remove(m.uid);
                if (mounted) setState(() => _selected = null);
              },
            ),
          ],
        ),
      ),
    ),
  );

  Future<void> _addModule() async {
    final navigator = Navigator.of(context);
    final type = await showModalBottomSheet<HomeModuleType>(
      context: context,
      backgroundColor: AppColors.surface,
      shape: RoundedRectangleBorder(borderRadius: AppRadius.top(24)),
      builder: (ctx) => SafeArea(
        child: ListView(
          shrinkWrap: true,
          children: [
            const Padding(
              padding: EdgeInsets.fromLTRB(20, 18, 20, 8),
              child: Text(
                'Add a module',
                style: TextStyle(
                  color: AppColors.textPrimary,
                  fontSize: 18,
                  fontWeight: FontWeight.w800,
                ),
              ),
            ),
            ListTile(
              leading: Icon(
                SolarIconsOutline.widgetAdd,
                color: AppColors.accent,
              ),
              title: const Text(
                'Build your own',
                style: TextStyle(
                  color: AppColors.textPrimary,
                  fontWeight: FontWeight.w700,
                ),
              ),
              subtitle: const Text(
                'Pick a shape, name it, and choose what goes in it.',
                style: TextStyle(color: AppColors.textMuted, fontSize: 12.5),
              ),
              onTap: () {
                Navigator.of(ctx).pop();
                navigator.push(
                  MaterialPageRoute(builder: (_) => const CustomBlockEditor()),
                );
              },
            ),
            const Divider(color: AppColors.border, height: 12),
            for (final t in HomeModuleType.values)
              if (t != HomeModuleType.custom &&
                  (t.repeatable || homeLayout.countOf(t) == 0))
                ListTile(
                  leading: Icon(t.icon, color: AppColors.accent),
                  title: Text(
                    t.label,
                    style: const TextStyle(color: AppColors.textPrimary),
                  ),
                  subtitle: Text(
                    t.blurb,
                    style: const TextStyle(
                      color: AppColors.textMuted,
                      fontSize: 12.5,
                    ),
                  ),
                  onTap: () => Navigator.of(ctx).pop(t),
                ),
            const SizedBox(height: 8),
          ],
        ),
      ),
    );
    if (type == null) return;
    await homeLayout.add(type);
    // Select the new one so its move controls are right there.
    if (mounted) {
      setState(() => _selected = homeLayout.modules.last.uid);
    }
  }

  Widget _floatingControls(bool moduleMode) => SafeArea(
    child: Align(
      alignment: Alignment.bottomCenter,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
        child: Container(
          padding: const EdgeInsets.all(6),
          decoration: BoxDecoration(
            color: AppColors.surface,
            borderRadius: AppRadius.all(26),
            border: Border.all(color: AppColors.border),
            boxShadow: AppShadow.lift(blur: 20, dy: 6, opacity: 0.5),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              for (final m in StudioMode.values)
                if (m != StudioMode.modules || _modulesAvailable)
                  _ModeButton(
                    mode: m,
                    selected: _mode == m,
                    onTap: () => setState(() {
                      _mode = m;
                      _selected = null;
                    }),
                  ),
              if (!moduleMode)
                _MiniAction(
                  icon: SolarIconsOutline.gallery,
                  enabled: true,
                  onTap: () async {
                    await Navigator.of(context).push(
                      MaterialPageRoute(
                        builder: (_) => const IconSlotListScreen(),
                      ),
                    );
                    if (mounted) setState(() {});
                  },
                ),
              const SizedBox(width: 2),
              TextButton(
                onPressed: () => Navigator.of(context).pop(),
                child: Text(
                  'Done',
                  style: TextStyle(
                    color: AppColors.accent,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    ),
  );
}

class _ModeButton extends StatelessWidget {
  final StudioMode mode;
  final bool selected;
  final VoidCallback onTap;
  const _ModeButton({
    required this.mode,
    required this.selected,
    required this.onTap,
  });

  static String _label(StudioMode m) =>
      m == StudioMode.icons ? 'Icons' : 'Modules';
  static IconData _icon(StudioMode m) => m == StudioMode.icons
      ? SolarIconsOutline.gallery
      : SolarIconsOutline.widget;

  @override
  Widget build(BuildContext context) => GestureDetector(
    onTap: onTap,
    child: Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 9),
      margin: const EdgeInsets.only(right: 4),
      decoration: BoxDecoration(
        color: selected ? AppColors.accent : Colors.transparent,
        borderRadius: AppRadius.all(20),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(
            _icon(mode),
            size: 17,
            color: selected ? Colors.white : AppColors.textMuted,
          ),
          const SizedBox(width: 6),
          Text(
            _label(mode),
            style: TextStyle(
              color: selected ? Colors.white : AppColors.textMuted,
              fontSize: 13,
              fontWeight: FontWeight.w700,
            ),
          ),
        ],
      ),
    ),
  );
}

class _MiniAction extends StatelessWidget {
  final IconData icon;
  final bool enabled;
  final bool danger;
  final VoidCallback onTap;

  const _MiniAction({
    required this.icon,
    required this.enabled,
    required this.onTap,
    this.danger = false,
  });

  @override
  Widget build(BuildContext context) => GestureDetector(
    onTap: enabled ? onTap : null,
    child: Container(
      width: 36,
      height: 36,
      margin: const EdgeInsets.only(left: 5),
      decoration: BoxDecoration(
        color: AppColors.surface,
        shape: BoxShape.circle,
        border: Border.all(
          color: danger ? AppColors.danger : AppColors.border,
        ),
      ),
      child: Icon(
        icon,
        size: 17,
        color: !enabled
            ? AppColors.textFaint
            : danger
            ? AppColors.danger
            : AppColors.textPrimary,
      ),
    ),
  );
}

/// Every icon slot, grouped, for changing one without hunting it on a screen.
class IconSlotListScreen extends StatelessWidget {
  const IconSlotListScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final groups = <String, List<IconSlot>>{};
    for (final slot in IconSlot.values) {
      groups.putIfAbsent(slot.group, () => []).add(slot);
    }
    return Scaffold(
      appBar: AppBar(
        title: const Text('All icons'),
        titleTextStyle: const TextStyle(
          color: AppColors.textPrimary,
          fontSize: 20,
          fontWeight: FontWeight.w800,
        ),
      ),
      body: ListenableBuilder(
        listenable: iconRegistry,
        builder: (context, _) => ListView(
          padding: const EdgeInsets.fromLTRB(16, 8, 16, 32),
          children: [
            for (final entry in groups.entries) ...[
              Padding(
                padding: const EdgeInsets.fromLTRB(4, 14, 4, 8),
                child: Text(
                  entry.key.toUpperCase(),
                  style: const TextStyle(
                    color: AppColors.textFaint,
                    fontSize: 11.5,
                    letterSpacing: 1.1,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ),
              for (final slot in entry.value)
                ListTile(
                  contentPadding: const EdgeInsets.symmetric(horizontal: 4),
                  leading: Container(
                    width: 42,
                    height: 42,
                    alignment: Alignment.center,
                    decoration: BoxDecoration(
                      color: AppColors.surfaceAlt,
                      borderRadius: AppRadius.all(12),
                      border: Border.all(
                        color: iconRegistry.isOverridden(slot)
                            ? AppColors.accent
                            : AppColors.border,
                      ),
                    ),
                    child: AppIcon(
                      slot,
                      size: 22,
                      color: AppColors.textPrimary,
                    ),
                  ),
                  title: Text(
                    slot.label,
                    style: const TextStyle(color: AppColors.textPrimary),
                  ),
                  subtitle: iconRegistry.isOverridden(slot)
                      ? Text(
                          'Changed',
                          style: TextStyle(
                            color: AppColors.accent,
                            fontSize: 12,
                          ),
                        )
                      : null,
                  onTap: () => Navigator.of(context).push(
                    MaterialPageRoute(
                      builder: (_) => IconPickerScreen(slot: slot),
                    ),
                  ),
                ),
            ],
          ],
        ),
      ),
    );
  }
}

// ---- Small shared pieces ----------------------------------------------------

class _Swatch extends StatelessWidget {
  final Color color;
  final String label;
  final bool selected;
  final VoidCallback onTap;
  const _Swatch({
    required this.color,
    required this.label,
    required this.selected,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) => GestureDetector(
    onTap: onTap,
    child: Tooltip(
      message: label,
      child: Container(
        width: 46,
        height: 46,
        decoration: BoxDecoration(
          color: color,
          shape: BoxShape.circle,
          border: selected
              ? Border.all(color: AppColors.textPrimary, width: 3)
              : null,
        ),
        child: selected
            ? const Icon(
                SolarIconsBold.checkCircle,
                color: Colors.white,
                size: 20,
              )
            : null,
      ),
    ),
  );
}

/// The "any colour" swatch — opens the wheel.
class _CustomSwatch extends StatelessWidget {
  final Color? colour;
  final VoidCallback onTap;
  const _CustomSwatch({required this.colour, required this.onTap});

  @override
  Widget build(BuildContext context) => GestureDetector(
    onTap: onTap,
    child: Tooltip(
      message: 'Any colour',
      child: Container(
        width: 46,
        height: 46,
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          color: colour,
          gradient: colour == null
              ? const SweepGradient(
                  colors: [
                    Color(0xFFFF5A5A),
                    Color(0xFFF5D423),
                    Color(0xFF4FD07A),
                    Color(0xFF40D0B0),
                    Color(0xFF5B9CFF),
                    Color(0xFFB57BFF),
                    Color(0xFFFF5A7A),
                    Color(0xFFFF5A5A),
                  ],
                )
              : null,
          border: colour != null
              ? Border.all(color: AppColors.textPrimary, width: 3)
              : null,
        ),
        child: Icon(
          colour == null ? SolarIconsBold.paletteRound : SolarIconsBold.checkCircle,
          color: Colors.white,
          size: 20,
        ),
      ),
    ),
  );
}

class _Chips<T> extends StatelessWidget {
  final List<T> options;
  final T selected;
  final String Function(T) label;
  final ValueChanged<T> onSelect;
  final WrapAlignment alignment;
  const _Chips({
    required this.options,
    required this.selected,
    required this.label,
    required this.onSelect,
    this.alignment = WrapAlignment.start,
  });

  @override
  Widget build(BuildContext context) => Wrap(
    spacing: 8,
    runSpacing: 8,
    alignment: alignment,
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
                color: o == selected ? AppColors.accent : AppColors.textPrimary,
                fontSize: 13.5,
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
        ),
    ],
  );
}

/// One page of the settings deck: a titled card that fills the deck's height.
///
/// The title lives inside the card rather than above the deck, so swiping
/// between categories carries the heading with it and nothing has to animate
/// separately.
class _Deck extends StatelessWidget {
  final String title;
  final Widget child;

  const _Deck({required this.title, required this.child});

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.symmetric(horizontal: 14),
    child: Container(
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 14),
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: AppRadius.all(20),
        border: Border.all(color: AppColors.border),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            title,
            style: const TextStyle(
              color: AppColors.textPrimary,
              fontSize: 17,
              fontWeight: FontWeight.w800,
            ),
          ),
          const Divider(color: AppColors.border, height: 18),
          Expanded(child: child),
        ],
      ),
    ),
  );
}

/// An empty slot in the font grid — tap to load a .ttf/.otf of your own.
class _AddFontCard extends StatelessWidget {
  final VoidCallback onTap;
  const _AddFontCard({required this.onTap});

  @override
  Widget build(BuildContext context) => GestureDetector(
    onTap: onTap,
    child: const DottedBorderBox(
      child: Icon(
        SolarIconsOutline.addCircle,
        color: AppColors.textFaint,
        size: 22,
      ),
    ),
  );
}

/// A muted, dashed-looking placeholder frame. Drawn as a plain border in the
/// faint text colour: an empty slot should read as "nothing here yet" rather
/// than compete with the real cards beside it.
class DottedBorderBox extends StatelessWidget {
  final Widget child;
  const DottedBorderBox({super.key, required this.child});

  @override
  Widget build(BuildContext context) => Container(
    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
    decoration: BoxDecoration(
      color: AppColors.surfaceAlt.withValues(alpha: 0.45),
      borderRadius: AppRadius.all(14),
      border: Border.all(color: AppColors.border),
    ),
    child: Center(child: child),
  );
}

/// One selectable face, set in itself so the choice shows what it buys.
class _FontOption {
  final String label;
  final String family;
  final VoidCallback onTap;
  final VoidCallback? onRemove;
  const _FontOption(this.label, this.family, this.onTap, {this.onRemove});
}

class _FontCard extends StatelessWidget {
  final _FontOption option;
  final bool selected;
  const _FontCard({required this.option, required this.selected});

  @override
  Widget build(BuildContext context) => GestureDetector(
    onTap: option.onTap,
    child: Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      decoration: BoxDecoration(
        color: selected
            ? AppColors.accent.withValues(alpha: 0.14)
            : AppColors.surfaceAlt,
        borderRadius: AppRadius.all(14),
        border: Border.all(
          color: selected ? AppColors.accent : AppColors.border,
        ),
      ),
      // The name alone, set in its own face — the face is the description.
      child: Stack(
        children: [
          Center(
            child: Text(
              option.label,
              maxLines: 2,
              textAlign: TextAlign.center,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                fontFamily: option.family,
                color: selected ? AppColors.accent : AppColors.textPrimary,
                fontSize: 15,
                fontWeight: FontWeight.w700,
              ),
            ),
          ),
          if (option.onRemove != null)
            Positioned(
              top: 0,
              right: 0,
              child: GestureDetector(
                onTap: option.onRemove,
                child: const Icon(
                  SolarIconsOutline.trashBinMinimalistic,
                  color: AppColors.textFaint,
                  size: 15,
                ),
              ),
            )
          else if (selected)
            Positioned(
              top: 0,
              right: 0,
              child: Icon(
                SolarIconsBold.checkCircle,
                color: AppColors.accent,
                size: 15,
              ),
            ),
        ],
      ),
    ),
  );
}

/// A labelled row of notches — one per option, drag or tap to move between.
///
/// A slider rather than chips because shape and depth are felt as amounts
/// rather than as named choices; the name of the current notch is shown beside
/// the label so the setting is still nameable.
class _TickSlider extends StatelessWidget {
  final String label;
  final String value;
  final int index;
  final int count;
  final ValueChanged<int> onChanged;

  const _TickSlider({
    required this.label,
    required this.value,
    required this.index,
    required this.count,
    required this.onChanged,
  });

  @override
  Widget build(BuildContext context) => Column(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      Row(
        children: [
          Text(
            label,
            style: const TextStyle(
              color: AppColors.textPrimary,
              fontSize: 14.5,
              fontWeight: FontWeight.w700,
            ),
          ),
          const Spacer(),
          Text(
            value,
            style: TextStyle(
              color: AppColors.accent,
              fontSize: 12.5,
              fontWeight: FontWeight.w700,
            ),
          ),
        ],
      ),
      SliderTheme(
        data: SliderTheme.of(context).copyWith(
          trackHeight: 3,
          activeTrackColor: AppColors.accent,
          inactiveTrackColor: AppColors.border,
          thumbColor: AppColors.accent,
          overlayColor: AppColors.accent.withValues(alpha: 0.14),
          activeTickMarkColor: AppColors.background,
          inactiveTickMarkColor: AppColors.textFaint,
          thumbShape: const RoundSliderThumbShape(enabledThumbRadius: 8),
          overlayShape: const RoundSliderOverlayShape(overlayRadius: 16),
        ),
        child: Slider(
          value: index.toDouble(),
          min: 0,
          max: (count - 1).toDouble(),
          divisions: count - 1,
          onChanged: (v) => onChanged(v.round()),
        ),
      ),
    ],
  );
}

/// A stand-in card that carries whatever shape and depth are currently set, so
/// the two sliders can be judged against something rather than in the abstract.
class _CornerPreview extends StatelessWidget {
  const _CornerPreview();

  @override
  Widget build(BuildContext context) => Container(
    width: 108,
    height: 108,
    decoration: BoxDecoration(
      color: AppColors.surfaceAlt,
      borderRadius: AppRadius.all(18),
      border: Border.all(color: AppColors.border),
      boxShadow: AppShadow.lift(blur: 18, dy: 7, opacity: 0.55),
    ),
    child: const Center(
      child: Icon(SolarIconsBold.musicNote, color: AppColors.textMuted, size: 34),
    ),
  );
}
