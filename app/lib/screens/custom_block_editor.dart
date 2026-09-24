import 'package:flutter/material.dart';
import 'package:solar_icons/solar_icons.dart';

import '../services/home_layout.dart';
import '../theme.dart';

/// Build a Home block of your own: a shape, a name, and what goes in it.
///
/// The three choices are independent on purpose — any source can be drawn in
/// any shape. That's the whole difference between this and the shipped modules,
/// which each pair one source with one fixed presentation.
///
/// Returns nothing; it writes to [homeLayout] itself and pops.
class CustomBlockEditor extends StatefulWidget {
  /// The block being changed, or null to build a new one.
  final HomeModule? existing;

  const CustomBlockEditor({super.key, this.existing});

  @override
  State<CustomBlockEditor> createState() => _CustomBlockEditorState();
}

class _CustomBlockEditorState extends State<CustomBlockEditor> {
  late final TextEditingController _name = TextEditingController(
    text: widget.existing?.name ?? '',
  );
  late HomeModuleLayout _layout =
      widget.existing?.layout ?? HomeModuleLayout.row;
  late HomeModuleSource _source =
      widget.existing?.source ?? HomeModuleSource.albumsForYou;

  bool get _editing => widget.existing != null;

  @override
  void dispose() {
    _name.dispose();
    super.dispose();
  }

  /// The heading to use when the name is left blank — the source's own label,
  /// which is very likely what the block is anyway.
  String get _effectiveName =>
      _name.text.trim().isEmpty ? _source.label : _name.text.trim();

  Future<void> _save() async {
    final existing = widget.existing;
    if (existing != null) {
      await homeLayout.editCustom(
        existing.uid,
        name: _effectiveName,
        layout: _layout,
        source: _source,
      );
    } else {
      await homeLayout.addCustom(
        name: _effectiveName,
        layout: _layout,
        source: _source,
      );
    }
    if (mounted) Navigator.of(context).pop();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text(_editing ? 'Edit block' : 'Build a block'),
        titleTextStyle: const TextStyle(
          color: AppColors.textPrimary,
          fontSize: 20,
          fontWeight: FontWeight.w800,
        ),
        actions: [
          TextButton(
            onPressed: _save,
            child: Text(
              'Save',
              style: TextStyle(
                color: AppColors.accent,
                fontWeight: FontWeight.w800,
              ),
            ),
          ),
        ],
      ),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(16, 4, 16, 32),
        children: [
          _step(1, 'Shape', 'How the block is laid out.'),
          GridView.count(
            shrinkWrap: true,
            physics: const NeverScrollableScrollPhysics(),
            crossAxisCount: 2,
            mainAxisSpacing: 10,
            crossAxisSpacing: 10,
            childAspectRatio: 1.5,
            children: [
              for (final l in HomeModuleLayout.values)
                _LayoutCard(
                  layout: l,
                  selected: _layout == l,
                  onTap: () => setState(() => _layout = l),
                ),
            ],
          ),

          _step(2, 'Name', 'The heading above it. Leave blank to use the '
              'source\'s own name.'),
          TextField(
            controller: _name,
            style: const TextStyle(color: AppColors.textPrimary, fontSize: 15),
            onChanged: (_) => setState(() {}),
            decoration: InputDecoration(
              hintText: _source.label,
              hintStyle: const TextStyle(color: AppColors.textFaint),
              filled: true,
              fillColor: AppColors.surface,
              contentPadding: const EdgeInsets.symmetric(
                horizontal: 14,
                vertical: 14,
              ),
              enabledBorder: OutlineInputBorder(
                borderRadius: AppRadius.all(14),
                borderSide: const BorderSide(color: AppColors.border),
              ),
              focusedBorder: OutlineInputBorder(
                borderRadius: AppRadius.all(14),
                borderSide: BorderSide(color: AppColors.accent),
              ),
            ),
          ),

          _step(3, 'Contents', 'What the block is filled with.'),
          for (final s in HomeModuleSource.values)
            _SourceRow(
              source: s,
              selected: _source == s,
              onTap: () => setState(() => _source = s),
            ),
        ],
      ),
    );
  }

  Widget _step(int number, String title, String detail) => Padding(
    padding: EdgeInsets.fromLTRB(0, number == 1 ? 12 : 26, 0, 12),
    child: Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Container(
          width: 22,
          height: 22,
          alignment: Alignment.center,
          decoration: BoxDecoration(
            color: AppColors.accent.withValues(alpha: 0.18),
            shape: BoxShape.circle,
          ),
          child: Text(
            '$number',
            style: TextStyle(
              color: AppColors.accent,
              fontSize: 12,
              fontWeight: FontWeight.w800,
            ),
          ),
        ),
        const SizedBox(width: 10),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                title,
                style: const TextStyle(
                  color: AppColors.textPrimary,
                  fontSize: 16,
                  fontWeight: FontWeight.w800,
                ),
              ),
              Text(
                detail,
                style: const TextStyle(
                  color: AppColors.textMuted,
                  fontSize: 12.5,
                ),
              ),
            ],
          ),
        ),
      ],
    ),
  );
}

/// One shape to choose from, drawn as a miniature of itself rather than named
/// only — the arrangement is the thing being picked, so it should be visible.
class _LayoutCard extends StatelessWidget {
  final HomeModuleLayout layout;
  final bool selected;
  final VoidCallback onTap;

  const _LayoutCard({
    required this.layout,
    required this.selected,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) => GestureDetector(
    onTap: onTap,
    child: Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: selected
            ? AppColors.accent.withValues(alpha: 0.13)
            : AppColors.surface,
        borderRadius: AppRadius.all(16),
        border: Border.all(
          color: selected ? AppColors.accent : AppColors.border,
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Expanded(child: _sketch()),
          const SizedBox(height: 8),
          Text(
            layout.label,
            style: TextStyle(
              color: selected ? AppColors.accent : AppColors.textPrimary,
              fontSize: 14,
              fontWeight: FontWeight.w700,
            ),
          ),
        ],
      ),
    ),
  );

  Color get _ink =>
      (selected ? AppColors.accent : AppColors.textFaint).withValues(alpha: 0.5);

  Widget _block({double? w, double h = 8}) => Container(
    width: w,
    height: h,
    decoration: BoxDecoration(color: _ink, borderRadius: AppRadius.all(4)),
  );

  Widget _sketch() => switch (layout) {
    HomeModuleLayout.row => Row(
      children: [
        for (var i = 0; i < 3; i++) ...[
          Expanded(child: _block(h: double.infinity)),
          if (i < 2) const SizedBox(width: 5),
        ],
      ],
    ),
    HomeModuleLayout.grid => Column(
      children: [
        for (var r = 0; r < 2; r++) ...[
          Expanded(
            child: Row(
              children: [
                Expanded(child: _block(h: double.infinity)),
                const SizedBox(width: 5),
                Expanded(child: _block(h: double.infinity)),
              ],
            ),
          ),
          if (r < 1) const SizedBox(height: 5),
        ],
      ],
    ),
    HomeModuleLayout.list => Column(
      mainAxisAlignment: MainAxisAlignment.spaceEvenly,
      children: [for (var i = 0; i < 3; i++) _block(w: double.infinity, h: 7)],
    ),
    HomeModuleLayout.banner => _block(w: double.infinity, h: double.infinity),
  };
}

/// One content source to point a block at.
class _SourceRow extends StatelessWidget {
  final HomeModuleSource source;
  final bool selected;
  final VoidCallback onTap;

  const _SourceRow({
    required this.source,
    required this.selected,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) => GestureDetector(
    onTap: onTap,
    behavior: HitTestBehavior.opaque,
    child: Container(
      margin: const EdgeInsets.only(bottom: 8),
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 11),
      decoration: BoxDecoration(
        color: selected
            ? AppColors.accent.withValues(alpha: 0.13)
            : AppColors.surface,
        borderRadius: AppRadius.all(14),
        border: Border.all(
          color: selected ? AppColors.accent : AppColors.border,
        ),
      ),
      child: Row(
        children: [
          Icon(
            source.icon,
            size: 19,
            color: selected ? AppColors.accent : AppColors.textMuted,
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Text(
              source.label,
              style: TextStyle(
                color: selected ? AppColors.accent : AppColors.textPrimary,
                fontSize: 15,
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
          if (selected)
            Icon(SolarIconsBold.checkCircle, color: AppColors.accent, size: 18),
        ],
      ),
    ),
  );
}
