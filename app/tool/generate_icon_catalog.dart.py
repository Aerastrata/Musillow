"""Generate lib/generated/solar_catalog.g.dart from the solar_icons package.

Run:  python3 tool/generate_icon_catalog.dart.py
The catalogue lets the icon picker offer every Solar glyph by name; without it
the app could only reference the handful of icons written into the source.
"""
import re, pathlib, sys

PKG = pathlib.Path('/home/nathaniel/.pub-cache/hosted/pub.dev/solar_icons-0.1.0/lib/src')
OUT = pathlib.Path('lib/generated/solar_catalog.g.dart')

ENTRY = re.compile(r'^  static const ([a-zA-Z0-9_]+) = IconData\((0x[0-9a-fA-F]+),')

def parse(name):
    icons = []
    for line in (PKG / name).read_text().splitlines():
        m = ENTRY.match(line)
        if m and not m.group(1).startswith('_'):
            icons.append((m.group(1), m.group(2)))
    return icons

outline = parse('solar_icons_outline.dart')
bold = parse('solar_icons_bold.dart')
if not outline or not bold:
    sys.exit('no icons parsed — has the solar_icons package moved?')

# Only names present in both styles, so every catalogue entry can render either
# an outline or a filled version of the same glyph.
bold_map = dict(bold)
paired = [(n, c, bold_map[n]) for n, c in outline if n in bold_map]

def words(name):
    """camelCase2 -> 'camel case 2', for the picker's search."""
    s = re.sub(r'([a-z])([A-Z])', r'\1 \2', name)
    s = re.sub(r'([a-zA-Z])(\d)', r'\1 \2', s)
    return s.lower()

lines = [
    '// GENERATED FILE — do not edit by hand.',
    '// Regenerate with: python3 tool/generate_icon_catalog.dart.py',
    '//',
    '// Every Solar icon available in both the outline and bold styles, so the',
    "// icon picker can offer the full set rather than the few the app's source",
    '// happens to name.',
    "import 'package:flutter/widgets.dart';",
    '',
    "const _outlineFamily = 'SolarIconsOutline';",
    "const _boldFamily = 'SolarIconsBold';",
    "const _package = 'solar_icons';",
    '',
    '/// One glyph, in both styles.',
    'class SolarGlyph {',
    '  final String name;',
    '',
    '  /// Lower-cased, space-separated form of [name], for search.',
    '  final String terms;',
    '  final IconData outline;',
    '  final IconData bold;',
    '  const SolarGlyph(this.name, this.terms, this.outline, this.bold);',
    '}',
    '',
    'const solarCatalog = <SolarGlyph>[',
]
for name, oc, bc in paired:
    lines.append(
        f"  SolarGlyph('{name}', '{words(name)}', "
        f"IconData({oc}, fontFamily: _outlineFamily, fontPackage: _package), "
        f"IconData({bc}, fontFamily: _boldFamily, fontPackage: _package)),"
    )
lines += [
    '];',
    '',
    '/// Glyphs by name, for resolving a saved icon override back to an IconData.',
    'final solarByName = <String, SolarGlyph>{',
    '  for (final g in solarCatalog) g.name: g,',
    '};',
    '',
]
OUT.parent.mkdir(parents=True, exist_ok=True)
OUT.write_text('\n'.join(lines))
print(f'{len(paired)} glyphs -> {OUT}')
