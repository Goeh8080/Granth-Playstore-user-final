part of 'religion_symbol.dart';

// Granth icon pack v3 — the premium religion tiles. Byte-identical in the admin and the
// user app. Hooks in `religion_symbol.dart`: `ReligionSymbol.build` starts with
// `if (GranthIconStyle.premium) return _v3Build(context);`, and `ReligionSymbolPainter`
// got `glow` (default true = v2) so the v3 tile can draw the bare glyph.

/// The v3 colours of a religion key: its own jewel palette, or (unknown keys / `misc`, or
/// [GranthIconStyle.religionUsesTone]) the folder's [Tone] as in v2.
IconV3Palette religionPaletteV3(String name, Tone tone) {
  final own = GranthIconStyle.religionUsesTone
      ? null
      : kReligionPaletteV3[name];
  if (own != null) return own;
  final (colors, ink) = toneColors(tone);
  return IconV3Palette(
    Color.lerp(colors.first, Colors.white, 0.08)!,
    Color.lerp(colors.last, Colors.black, 0.12)!,
    ink,
  );
}

extension _ReligionSymbolV3 on ReligionSymbol {
  Widget _v3Build(BuildContext context) => IconV3Box(
    size: size,
    shimmer: shimmer,
    painter: ReligionTilePainter(
      name,
      palette: religionPaletteV3(name, tone),
      dark: Theme.of(context).brightness == Brightness.dark,
    ),
  );
}

/// The whole v3 religion icon: tile, raised glyph, gloss. Recorded once per
/// (key, palette, theme) and replayed from [IconV3Cache].
class ReligionTilePainter extends CustomPainter {
  const ReligionTilePainter(
    this.name, {
    required this.palette,
    this.dark = false,
  });
  final String name;
  final IconV3Palette palette;
  final bool dark;

  @override
  bool shouldRepaint(ReligionTilePainter old) =>
      old.name != name || old.palette != palette || old.dark != dark;

  @override
  void paint(Canvas canvas, Size size) {
    final pic = IconV3Cache.get(('r', name, palette, dark), _record);
    final s = size.shortestSide;
    canvas.save();
    canvas.translate((size.width - s) / 2, (size.height - s) / 2);
    canvas.scale(s, s);
    canvas.drawPicture(pic);
    canvas.restore();
  }

  void _glyph(Canvas c, Color ink, Offset at) {
    c.save();
    c.translate(0.5 + at.dx, 0.487 + at.dy);
    c.scale(0.9);
    c.translate(-0.5, -0.5);
    ReligionSymbolPainter(name, ink, glow: false).paint(c, const Size(1, 1));
    c.restore();
  }

  void _record(Canvas c) {
    paintTileV3(c, palette, deep: true, dark: dark);
    final lightInk = palette.ink.computeLuminance() > 0.45;
    if (lightInk) {
      // raised: a soft shadow on the tile, then the glyph's own darker side (thickness)
      final sh = Color.lerp(palette.bottom, Colors.black, 0.6)!;
      _glyph(c, sh.withValues(alpha: 0.20), const Offset(0.008, 0.034));
      _glyph(
        c,
        Color.lerp(
          Color.lerp(palette.ink, palette.bottom, 0.55)!,
          Colors.black,
          0.15,
        )!,
        const Offset(0, 0.013),
      );
    } else {
      // pressed into a light tile: a light lip just under the glyph
      _glyph(
        c,
        Color.lerp(palette.top, Colors.white, 0.6)!,
        const Offset(0, 0.012),
      );
    }
    _glyph(c, palette.ink, Offset.zero);
    paintGlossV3(c, deep: true);
  }
}
