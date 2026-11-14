part of 'group_icon.dart';

// Granth icon pack v3 — the premium folder icons. Byte-identical in the admin and the user
// app. Hooks in `group_icon.dart`: `GroupIcon.build` → [_GroupIconWidgetV3._v3Build],
// first line of `GroupIconPainter.paint` → [_GroupIconV3._paintV3], first line of `_tile`
// → `if (_rec) return;`, and two calls in `_book` ([_bookShadowV3], [_coverGlossV3]).

/// Folder keys that are not a book cover: they get a contact shadow on the tile instead.
const Set<String> _nonBookV3 = {
  'scroll',
  'swords',
  'books',
  'hadees',
  'tripitak',
  'misc',
};

/// Outline of the book (cover + pages peeking out), for its drop shadow.
final Path _bookSilhouetteV3 = Path.combine(
  PathOperation.union,
  Path()..addRRect(
    RRect.fromRectAndRadius(
      const Rect.fromLTWH(0.27, 0.17, 0.57, 0.72),
      const Radius.circular(0.04),
    ),
  ),
  Path()..addRRect(
    RRect.fromRectAndRadius(
      const Rect.fromLTWH(0.19, 0.11, 0.58, 0.72),
      const Radius.circular(0.05),
    ),
  ),
);

final RRect _coverV3 = RRect.fromRectAndRadius(
  const Rect.fromLTWH(0.19, 0.11, 0.58, 0.72),
  const Radius.circular(0.05),
);

extension _GroupIconWidgetV3 on GroupIcon {
  Widget _v3Build(BuildContext context) => IconV3Box(
    size: size,
    shimmer: shimmer,
    painter: GroupIconPainter(
      name,
      dark: Theme.of(context).brightness == Brightness.dark,
      classic: !GranthIconStyle.premium,
    ),
  );
}

extension _GroupIconV3 on GroupIconPainter {
  /// Known keys keep their name; anything else is drawn (and cached) as `misc`.
  String get _v3Key =>
      groupIconNames.contains(name) || newGroupIconNames.contains(name)
      ? name
      : 'misc';

  /// Paints the whole v3 icon from the cache; false in classic mode (and while recording).
  bool _paintV3(Canvas canvas, Size size) {
    if (classic || _rec) return false;
    final key = _v3Key;
    final pic = IconV3Cache.get(('g', key, dark), (c) {
      final pal = folderPaletteV3(key);
      paintTileV3(c, pal, deep: false, dark: dark);
      if (_nonBookV3.contains(key)) {
        paintContactShadowV3(
          c,
          const Rect.fromLTRB(0.12, 0.74, 0.88, 0.94),
          Color.lerp(pal.ink, const Color(0xFF2A1406), 0.55)!,
          alpha: 0.30,
        );
      }
      // the tile's gloss goes UNDER the illustration, so book covers keep their colour
      // (each cover has its own sheen, see _coverGlossV3)
      paintGlossV3(c, deep: false);
      c.save();
      c.translate(0, -0.006);
      GroupIconPainter._v3(key).paint(c, const Size(1, 1));
      c.restore();
    });
    final s = size.shortestSide;
    canvas.save();
    canvas.translate((size.width - s) / 2, (size.height - s) / 2);
    canvas.scale(s, s);
    canvas.drawPicture(pic);
    canvas.restore();
    return true;
  }

  /// A soft two-step shadow under the book, cast down-right.
  void _bookShadowV3(Canvas c, Color color) {
    if (!_rec) return;
    final ink = Color.lerp(color, const Color(0xFF1E0E04), 0.6)!;
    c.drawPath(
      _bookSilhouetteV3.shift(const Offset(0.026, 0.036)),
      _fill(ink.withValues(alpha: 0.12)),
    );
    c.drawPath(
      _bookSilhouetteV3.shift(const Offset(0.014, 0.018)),
      _fill(ink.withValues(alpha: 0.20)),
    );
  }

  /// Gloss on the cover: a diagonal sheen from the top-left and a lit top edge.
  void _coverGlossV3(Canvas c, Color color) {
    if (!_rec) return;
    c.save();
    c.clipRRect(_coverV3);
    c.drawRect(
      _coverV3.outerRect,
      Paint()
        ..shader = LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [
            Colors.white.withValues(alpha: 0.24),
            Colors.white.withValues(alpha: 0.06),
            Colors.white.withValues(alpha: 0),
            Colors.black.withValues(alpha: 0.14),
          ],
          stops: const [0.0, 0.26, 0.5, 1.0],
        ).createShader(_coverV3.outerRect),
    );
    c.restore();
    c.drawLine(
      const Offset(0.33, 0.122),
      const Offset(0.735, 0.122),
      _line(Colors.white.withValues(alpha: 0.45), 0.009),
    );
  }
}
