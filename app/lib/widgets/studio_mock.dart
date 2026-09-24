import 'package:flutter/material.dart';

import '../services/home_layout.dart';
import '../services/icon_registry.dart';
import '../theme.dart';
import 'app_icon.dart';

/// What the Studio is letting you change right now.
enum StudioMode { icons, modules }

/// Which app screen a mock is standing in for.
enum StudioPage {
  home('Home'),
  explore('Explore'),
  library('Library'),
  player('Player');

  const StudioPage(this.label);
  final String label;
}

/// Editing context for a mock screen.
///
/// Mocks are built from widgets the Studio owns, so an icon or a module is a
/// real child that can carry its own tap handler. That's why editing here is
/// exact — there are no screen coordinates to guess at, and nothing depends on
/// what the live page happened to fetch.
class StudioEdit extends InheritedWidget {
  /// Null in the small swipeable preview, which is for looking, not touching.
  final StudioMode? mode;
  final void Function(IconSlot slot)? onIcon;
  final void Function(String uid)? onSelectModule;
  final String? selectedModule;

  const StudioEdit({
    super.key,
    required this.mode,
    this.onIcon,
    this.onSelectModule,
    this.selectedModule,
    required super.child,
  });

  static StudioEdit? of(BuildContext context) =>
      context.dependOnInheritedWidgetOfExactType<StudioEdit>();

  @override
  bool updateShouldNotify(StudioEdit old) =>
      mode != old.mode || selectedModule != old.selectedModule;
}

/// An icon in a mock screen. Tapping it in icon mode opens the picker — no
/// outline, no target box, just the icon itself.
class EditableIcon extends StatelessWidget {
  final IconSlot slot;
  final double size;
  final Color? color;

  const EditableIcon(this.slot, {super.key, this.size = 24, this.color});

  @override
  Widget build(BuildContext context) {
    final icon = AppIcon(slot, size: size, color: color);
    final edit = StudioEdit.of(context);
    if (edit?.mode != StudioMode.icons || edit?.onIcon == null) return icon;
    return GestureDetector(
      onTap: () => edit!.onIcon!(slot),
      behavior: HitTestBehavior.opaque,
      // A slightly larger touch area than the glyph, without drawing anything.
      child: Padding(padding: const EdgeInsets.all(4), child: icon),
    );
  }
}

/// One module in the mock Home page. Tapping it in module mode selects it.
class EditableModule extends StatelessWidget {
  final String uid;
  final Widget child;

  const EditableModule({super.key, required this.uid, required this.child});

  @override
  Widget build(BuildContext context) {
    final edit = StudioEdit.of(context);
    if (edit?.mode != StudioMode.modules) return child;
    final selected = edit?.selectedModule == uid;
    return GestureDetector(
      onTap: () => edit?.onSelectModule?.call(uid),
      behavior: HitTestBehavior.opaque,
      child: Container(
        margin: const EdgeInsets.symmetric(horizontal: 6, vertical: 3),
        decoration: BoxDecoration(
          border: Border.all(
            color: selected ? AppColors.accent : AppColors.border,
            width: selected ? 2 : 1,
          ),
          borderRadius: AppRadius.all(14),
          color: selected
              ? AppColors.accent.withValues(alpha: 0.08)
              : Colors.transparent,
        ),
        child: child,
      ),
    );
  }
}

// ---- Placeholder art --------------------------------------------------------

/// A stand-in for cover art: a gradient seeded from [seed], so a mock page
/// looks like a real one without fetching anything.
class MockArt extends StatelessWidget {
  final int seed;
  final double size;
  final double radius;
  final bool circle;

  const MockArt({
    super.key,
    required this.seed,
    this.size = 64,
    this.radius = 14,
    this.circle = false,
  });

  @override
  Widget build(BuildContext context) {
    final hue = (seed * 47) % 360.0;
    return Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        borderRadius: circle ? null : AppRadius.all(radius),
        shape: circle ? BoxShape.circle : BoxShape.rectangle,
        // Stand-in art carries the shadow setting for the same reason real
        // cover art does — it's the most repeated raised surface on the page,
        // so it's where a depth change is easiest to judge.
        boxShadow: AppShadow.lift(blur: size * 0.18, dy: size * 0.06),
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [
            HSLColor.fromAHSL(1, hue, 0.38, 0.34).toColor(),
            HSLColor.fromAHSL(1, (hue + 40) % 360, 0.38, 0.20).toColor(),
          ],
        ),
      ),
    );
  }
}

/// A grey bar standing in for a line of text.
class MockBar extends StatelessWidget {
  final double width;
  final double height;
  final Color? color;
  const MockBar(this.width, {super.key, this.height = 10, this.color});

  @override
  Widget build(BuildContext context) => Container(
    width: width,
    height: height,
    decoration: BoxDecoration(
      color: color ?? AppColors.surfaceAlt,
      borderRadius: AppRadius.all(6),
    ),
  );
}

Widget _heading(String text) => Padding(
  padding: const EdgeInsets.fromLTRB(16, 16, 16, 10),
  child: Text(
    text,
    style: const TextStyle(
      color: AppColors.textPrimary,
      fontSize: 19,
      fontWeight: FontWeight.w800,
    ),
  ),
);

// ---- The mock screens -------------------------------------------------------

/// Builds the stand-in for [page], reflecting the current accent, corners,
/// font, icons and — for Home — module arrangement.
class MockScreen extends StatelessWidget {
  final StudioPage page;
  const MockScreen({super.key, required this.page});

  @override
  Widget build(BuildContext context) {
    return ColoredBox(
      color: AppColors.background,
      child: switch (page) {
        StudioPage.home => const _MockHome(),
        StudioPage.explore => const _MockExplore(),
        StudioPage.library => const _MockLibrary(),
        StudioPage.player => const _MockPlayer(),
      },
    );
  }
}

/// Header + scrolling body + mini player + nav bar: the shape every tab shares.
class _Shell extends StatelessWidget {
  final String title;
  final int navIndex;
  final Widget body;
  const _Shell({
    required this.title,
    required this.navIndex,
    required this.body,
  });

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      bottom: false,
      child: Column(
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(20, 10, 14, 6),
            child: Row(
              children: [
                Expanded(
                  child: Text(
                    title,
                    style: const TextStyle(
                      fontSize: 26,
                      fontWeight: FontWeight.w800,
                      color: AppColors.textPrimary,
                    ),
                  ),
                ),
                const EditableIcon(
                  IconSlot.account,
                  size: 26,
                  color: AppColors.textMuted,
                ),
              ],
            ),
          ),
          Expanded(child: body),
          const _MockBottomBar(),
        ],
      ),
    );
  }
}

class _MockBottomBar extends StatelessWidget {
  const _MockBottomBar();

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: AppRadius.top(30),
      ),
      padding: const EdgeInsets.only(bottom: 10),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          // Mini player.
          Padding(
            padding: const EdgeInsets.fromLTRB(12, 10, 8, 6),
            child: Row(
              children: [
                const MockArt(seed: 3, size: 38, radius: 10),
                const SizedBox(width: 10),
                Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: const [
                    MockBar(90, height: 9),
                    SizedBox(height: 5),
                    MockBar(58, height: 7),
                  ],
                ),
                const Spacer(),
                const EditableIcon(
                  IconSlot.miniPlay,
                  size: 30,
                  color: AppColors.textPrimary,
                ),
                const SizedBox(width: 4),
                const EditableIcon(
                  IconSlot.miniClose,
                  size: 20,
                  color: AppColors.textMuted,
                ),
              ],
            ),
          ),
          // Nav.
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 8),
            child: Row(
              children: [
                _navItem(IconSlot.navHomeActive, 'Home', AppColors.accent, true),
                _navItem(IconSlot.navExplore, 'Explore', AppColors.teal, false),
                _navItem(IconSlot.navLibrary, 'Library', AppColors.orange, false),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _navItem(IconSlot slot, String label, Color colour, bool active) =>
      Expanded(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            EditableIcon(
              slot,
              size: 23,
              color: active ? colour : AppColors.textMuted,
            ),
            const SizedBox(height: 3),
            Text(
              label,
              style: TextStyle(
                color: active ? colour : AppColors.textMuted,
                fontSize: 11,
                fontWeight: active ? FontWeight.w700 : FontWeight.w500,
              ),
            ),
          ],
        ),
      );
}

/// Home, assembled from whatever modules are switched on and in whatever order
/// they're arranged — so this is where a layout change shows up.
class _MockHome extends StatelessWidget {
  const _MockHome();

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: homeLayout,
      builder: (context, _) {
        final visible = homeLayout.visible;
        return _Shell(
          title: 'Home',
          navIndex: 0,
          body: visible.isEmpty
              ? const Center(
                  child: Padding(
                    padding: EdgeInsets.all(32),
                    child: Text(
                      'Every module is switched off.\nAdd one to build the page.',
                      textAlign: TextAlign.center,
                      style: TextStyle(color: AppColors.textFaint),
                    ),
                  ),
                )
              : ListView(
                  padding: const EdgeInsets.only(bottom: 20),
                  children: [
                    for (final m in visible)
                      EditableModule(
                        uid: m.uid,
                        child: _module(m, homeLayout.instanceIndex(m)),
                      ),
                  ],
                ),
        );
      },
    );
  }

  Widget _module(HomeModule m, int copy) => switch (m.type) {
    HomeModuleType.greeting => const Padding(
      padding: EdgeInsets.fromLTRB(16, 10, 16, 4),
      child: Text(
        'Good evening',
        style: TextStyle(
          color: AppColors.textPrimary,
          fontSize: 22,
          fontWeight: FontWeight.w800,
        ),
      ),
    ),
    HomeModuleType.spotlight => _spotlight(copy),
    HomeModuleType.quickPicks => _quickPicks(),
    HomeModuleType.mixes => _cardRow('Your mixes', 3, 120, seed: 10),
    HomeModuleType.continueListening => _continueRow(),
    HomeModuleType.albumsForYou => _cardRow('Albums for you', 4, 110, seed: 20),
    HomeModuleType.moodRows => _cardRow('Because you like…', 4, 110, seed: 30),
    HomeModuleType.forgottenFaves => _wideRow('Forgotten faves'),
    HomeModuleType.newReleases => _cardRow('New releases', 4, 110, seed: 40),
    HomeModuleType.jumpBackIn => _cardRow('Jump back in', 4, 110, seed: 50),
    HomeModuleType.artists => _artistRow(),
    HomeModuleType.playlists => _cardRow('Your playlists', 4, 110, seed: 60),
    // A block the user built. Its shape is what the preview has to get right —
    // the contents are stand-ins here as everywhere else on this screen.
    HomeModuleType.custom => _customBlock(m, copy),
  };

  /// A stand-in for a custom block, drawn in the shape it was given so the
  /// preview shows the arrangement rather than a generic row.
  Widget _customBlock(HomeModule m, int copy) {
    final seed = 70 + m.uid.hashCode.abs() % 40;
    return switch (m.layout ?? HomeModuleLayout.row) {
      HomeModuleLayout.row => _cardRow(m.title, 4, 110, seed: seed),
      HomeModuleLayout.grid => _mockGrid(m.title, seed),
      HomeModuleLayout.list => _wideRow(m.title),
      HomeModuleLayout.banner => _mockBanner(m.title, seed + copy),
    };
  }

  Widget _mockGrid(String title, int seed) => Column(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      _heading(title),
      Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16),
        child: Column(
          children: [
            for (var row = 0; row < 2; row++)
              Padding(
                padding: const EdgeInsets.only(bottom: 8),
                child: Row(
                  children: [
                    for (var col = 0; col < 2; col++) ...[
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            MockArt(seed: seed + row * 2 + col, size: 92),
                            const SizedBox(height: 6),
                            const MockBar(64, height: 8),
                          ],
                        ),
                      ),
                      if (col == 0) const SizedBox(width: 10),
                    ],
                  ],
                ),
              ),
          ],
        ),
      ),
    ],
  );

  Widget _mockBanner(String title, int seed) => Column(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      _heading(title),
      Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16),
        child: Container(
          height: 120,
          decoration: BoxDecoration(
            borderRadius: AppRadius.all(18),
            boxShadow: AppShadow.lift(blur: 18, dy: 6),
            gradient: LinearGradient(
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
              colors: [
                HSLColor.fromAHSL(1, (seed * 47) % 360.0, 0.38, 0.34).toColor(),
                HSLColor.fromAHSL(1, (seed * 47 + 40) % 360.0, 0.38, 0.20)
                    .toColor(),
              ],
            ),
          ),
          child: const Padding(
            padding: EdgeInsets.all(14),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisAlignment: MainAxisAlignment.end,
              children: [
                MockBar(120, height: 12),
                SizedBox(height: 6),
                MockBar(70, height: 8),
              ],
            ),
          ),
        ),
      ),
    ],
  );

  Widget _spotlight(int copy) => Padding(
    padding: const EdgeInsets.fromLTRB(16, 10, 16, 10),
    child: Stack(
      children: [
        ClipRRect(
          borderRadius: AppRadius.all(20),
          child: SizedBox(
            height: 150,
            width: double.infinity,
            // A second banner is seeded differently, matching how a duplicate
            // module opens on a different track.
            child: MockArt(seed: 7 + copy * 13, size: 400, radius: 20),
          ),
        ),
        Positioned(
          left: 16,
          bottom: 18,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: const [
              MockBar(96, height: 8),
              SizedBox(height: 8),
              MockBar(150, height: 15),
              SizedBox(height: 7),
              MockBar(84, height: 9),
            ],
          ),
        ),
        Positioned(
          right: 16,
          bottom: 20,
          child: Container(
            width: 52,
            height: 52,
            alignment: Alignment.center,
            decoration: BoxDecoration(
              color: AppColors.accent,
              shape: BoxShape.circle,
            ),
            child: const EditableIcon(
              IconSlot.play,
              size: 24,
              color: Colors.white,
            ),
          ),
        ),
      ],
    ),
  );

  Widget _quickPicks() => Column(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      _heading('Quick Picks'),
      Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16),
        child: Column(
          children: [
            for (var r = 0; r < 3; r++)
              Padding(
                padding: const EdgeInsets.only(bottom: 8),
                child: Row(
                  children: [
                    for (var c = 0; c < 2; c++) ...[
                      Expanded(
                        child: Container(
                          height: 54,
                          decoration: BoxDecoration(
                            color: AppColors.surface,
                            borderRadius: AppRadius.all(12),
                          ),
                          child: Row(
                            children: [
                              MockArt(seed: r * 2 + c, size: 54, radius: 12),
                              const SizedBox(width: 10),
                              const MockBar(70, height: 9),
                            ],
                          ),
                        ),
                      ),
                      if (c == 0) const SizedBox(width: 8),
                    ],
                  ],
                ),
              ),
          ],
        ),
      ),
    ],
  );

  Widget _cardRow(String title, int count, double size, {required int seed}) =>
      Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _heading(title),
          SizedBox(
            height: size + 34,
            child: ListView.builder(
              scrollDirection: Axis.horizontal,
              padding: const EdgeInsets.symmetric(horizontal: 16),
              physics: const NeverScrollableScrollPhysics(),
              itemCount: count,
              itemBuilder: (_, i) => Padding(
                padding: const EdgeInsets.only(right: 12),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    MockArt(seed: seed + i, size: size),
                    const SizedBox(height: 8),
                    MockBar(size * 0.7, height: 9),
                    const SizedBox(height: 5),
                    MockBar(size * 0.45, height: 7),
                  ],
                ),
              ),
            ),
          ),
        ],
      );

  Widget _wideRow(String title) => Column(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      _heading(title),
      SizedBox(
        height: 110,
        child: ListView.builder(
          scrollDirection: Axis.horizontal,
          padding: const EdgeInsets.symmetric(horizontal: 16),
          physics: const NeverScrollableScrollPhysics(),
          itemCount: 3,
          itemBuilder: (_, i) => Padding(
            padding: const EdgeInsets.only(right: 12),
            child: ClipRRect(
              borderRadius: AppRadius.all(14),
              child: SizedBox(
                width: 200,
                height: 100,
                child: MockArt(seed: 70 + i, size: 200, radius: 14),
              ),
            ),
          ),
        ),
      ),
    ],
  );

  Widget _continueRow() => Column(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      _heading('Continue listening'),
      Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16),
        child: Row(
          children: [
            const MockArt(seed: 80, size: 64),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const MockBar(130, height: 10),
                  const SizedBox(height: 6),
                  const MockBar(80, height: 8),
                  const SizedBox(height: 10),
                  ClipRRect(
                    borderRadius: AppRadius.all(4),
                    child: LinearProgressIndicator(
                      value: 0.42,
                      minHeight: 4,
                      backgroundColor: AppColors.surfaceAlt,
                      valueColor: AlwaysStoppedAnimation(AppColors.accent),
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    ],
  );

  Widget _artistRow() => Column(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      _heading('Artists'),
      SizedBox(
        height: 110,
        child: ListView.builder(
          scrollDirection: Axis.horizontal,
          padding: const EdgeInsets.symmetric(horizontal: 16),
          physics: const NeverScrollableScrollPhysics(),
          itemCount: 5,
          itemBuilder: (_, i) => Padding(
            padding: const EdgeInsets.only(right: 14),
            child: Column(
              children: [
                MockArt(seed: 90 + i, size: 72, circle: true),
                const SizedBox(height: 8),
                const MockBar(52, height: 8),
              ],
            ),
          ),
        ),
      ),
    ],
  );
}

class _MockExplore extends StatelessWidget {
  const _MockExplore();

  @override
  Widget build(BuildContext context) {
    return _Shell(
      title: 'Explore',
      navIndex: 1,
      body: ListView(
        padding: const EdgeInsets.only(bottom: 20),
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 6, 16, 12),
            child: Row(
              children: [
                Expanded(
                  child: Container(
                    height: 46,
                    padding: const EdgeInsets.symmetric(horizontal: 14),
                    decoration: BoxDecoration(
                      color: AppColors.surfaceAlt,
                      borderRadius: AppRadius.all(14),
                    ),
                    child: Row(
                      children: const [
                        EditableIcon(
                          IconSlot.search,
                          size: 20,
                          color: AppColors.textFaint,
                        ),
                        SizedBox(width: 10),
                        MockBar(120, height: 9),
                      ],
                    ),
                  ),
                ),
                const SizedBox(width: 10),
                EditableIcon(
                  IconSlot.identify,
                  size: 26,
                  color: AppColors.accent,
                ),
              ],
            ),
          ),
          _heading('Charts'),
          for (var i = 0; i < 5; i++)
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 0, 16, 12),
              child: Row(
                children: [
                  MockArt(seed: 100 + i, size: 52),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: const [
                        MockBar(140, height: 10),
                        SizedBox(height: 6),
                        MockBar(90, height: 8),
                      ],
                    ),
                  ),
                  EditableIcon(
                    IconSlot.download,
                    size: 22,
                    color: AppColors.accent,
                  ),
                ],
              ),
            ),
        ],
      ),
    );
  }
}

class _MockLibrary extends StatelessWidget {
  const _MockLibrary();

  static const _cats = [
    (IconSlot.libSongs, 'Songs', AppColors.teal),
    (IconSlot.libPlaylists, 'Playlists', Color(0xFF4FD07A)),
    (IconSlot.libAlbums, 'Albums', Color(0xFF5B9CFF)),
    (IconSlot.libArtists, 'Artists', Color(0xFF9090FF)),
    (IconSlot.libGenres, 'Genres', Color(0xFFB57BFF)),
    (IconSlot.libRadio, 'Radio', Color(0xFFFF5A7A)),
    (IconSlot.libBooks, 'Audio Books', Color(0xFFF5A623)),
    (IconSlot.libAuthors, 'Authors', AppColors.orange),
  ];

  @override
  Widget build(BuildContext context) {
    return _Shell(
      title: 'Library',
      navIndex: 2,
      body: GridView.builder(
        padding: const EdgeInsets.fromLTRB(16, 6, 16, 20),
        gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
          crossAxisCount: 2,
          mainAxisSpacing: 12,
          crossAxisSpacing: 12,
          childAspectRatio: 1.5,
        ),
        physics: const NeverScrollableScrollPhysics(),
        itemCount: _cats.length,
        itemBuilder: (_, i) {
          final (slot, label, colour) = _cats[i];
          return Container(
            padding: const EdgeInsets.all(14),
            decoration: BoxDecoration(
              color: AppColors.surface,
              borderRadius: AppRadius.all(16),
              border: Border.all(color: AppColors.border),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text(
                  label,
                  style: const TextStyle(
                    color: AppColors.textPrimary,
                    fontWeight: FontWeight.w700,
                    fontSize: 15,
                  ),
                ),
                Align(
                  alignment: Alignment.bottomRight,
                  child: Container(
                    width: 44,
                    height: 44,
                    alignment: Alignment.center,
                    decoration: BoxDecoration(
                      color: colour,
                      borderRadius: AppRadius.all(12),
                    ),
                    child: EditableIcon(slot, size: 22, color: Colors.white),
                  ),
                ),
              ],
            ),
          );
        },
      ),
    );
  }
}

class _MockPlayer extends StatelessWidget {
  const _MockPlayer();

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 24),
        child: Column(
          children: [
            Row(
              children: const [
                EditableIcon(
                  IconSlot.collapse,
                  size: 28,
                  color: AppColors.textPrimary,
                ),
                Spacer(),
                EditableIcon(
                  IconSlot.more,
                  size: 24,
                  color: AppColors.textPrimary,
                ),
              ],
            ),
            const Spacer(),
            LayoutBuilder(
              builder: (context, c) => ClipRRect(
                borderRadius: AppRadius.all(22),
                child: MockArt(seed: 5, size: c.maxWidth * 0.86, radius: 22),
              ),
            ),
            const Spacer(),
            Row(
              children: [
                Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: const [
                    MockBar(170, height: 15),
                    SizedBox(height: 9),
                    MockBar(110, height: 10),
                  ],
                ),
                const Spacer(),
                const EditableIcon(
                  IconSlot.save,
                  size: 26,
                  color: AppColors.textPrimary,
                ),
                const SizedBox(width: 6),
                EditableIcon(
                  IconSlot.likeFilled,
                  size: 26,
                  color: const Color(0xFFFF5A7A),
                ),
              ],
            ),
            const SizedBox(height: 20),
            ClipRRect(
              borderRadius: AppRadius.all(4),
              child: LinearProgressIndicator(
                value: 0.36,
                minHeight: 4,
                backgroundColor: AppColors.surfaceAlt,
                valueColor: AlwaysStoppedAnimation(AppColors.accent),
              ),
            ),
            const SizedBox(height: 22),
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                const EditableIcon(
                  IconSlot.shuffle,
                  size: 24,
                  color: AppColors.textMuted,
                ),
                const EditableIcon(
                  IconSlot.previous,
                  size: 34,
                  color: AppColors.textPrimary,
                ),
                Container(
                  width: 68,
                  height: 68,
                  alignment: Alignment.center,
                  decoration: BoxDecoration(
                    color: AppColors.accent,
                    shape: BoxShape.circle,
                  ),
                  child: const EditableIcon(
                    IconSlot.play,
                    size: 34,
                    color: Colors.white,
                  ),
                ),
                const EditableIcon(
                  IconSlot.next,
                  size: 34,
                  color: AppColors.textPrimary,
                ),
                const EditableIcon(
                  IconSlot.repeat,
                  size: 24,
                  color: AppColors.textMuted,
                ),
              ],
            ),
            const SizedBox(height: 24),
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceEvenly,
              children: const [
                EditableIcon(
                  IconSlot.queue,
                  size: 22,
                  color: AppColors.textMuted,
                ),
                EditableIcon(
                  IconSlot.lyrics,
                  size: 22,
                  color: AppColors.textMuted,
                ),
                EditableIcon(
                  IconSlot.trackInfo,
                  size: 22,
                  color: AppColors.textMuted,
                ),
              ],
            ),
            const SizedBox(height: 18),
          ],
        ),
      ),
    );
  }
}
