// Granth icon pack v3 — the shared "premium" look of the folder and religion icons.
//
// This file is byte-identical in the admin app and the user app. It has no app imports, so it
// can be dropped next to `group_icon.dart` / `religion_symbol.dart` in either app.
//
// Look: a rounded-square gradient tile with a soft drop shadow, an inner bevel (light top
// edge, shaded bottom edge), the symbol with a little depth, and a glossy sheen over the
// top half. Everything is painted in a 0..1 unit box with plain gradients and translucent
// shapes — NO blur / mask filters / saveLayer for the tile — and each finished icon is
// recorded once into a [ui.Picture] ([IconV3Cache]) and replayed afterwards, so a list
// of 50 icons costs 50 `drawPicture` calls.
//
// The optional shimmer is a moving light band over the tile. It is OFF by default, runs on
// one AnimationController per icon only while it is on, and never runs when the platform
// asks for reduced motion (`MediaQuery.disableAnimations`) or inside a muted [TickerMode].
import 'dart:collection';
import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:flutter/material.dart';

/// App-wide switches of the icon look. Change them before the icons build (e.g. from a
/// setting at start-up, then rebuild); the icons read them in `build`.
abstract final class GranthIconStyle {
  /// `false` paints the exact v2 look (escape hatch, e.g. for very old phones).
  static bool premium = true;

  /// Master switch for the optional shimmer. An icon shimmers only when this is true AND
  /// the widget was built with `shimmer: true` AND the platform allows animations.
  static bool shimmerEnabled = true;

  /// v3 gives each religion key its own colour (ॐ maroon, चाँद-तारा green, …). Set to `true`
  /// to keep the v2 behaviour where the folder's [Tone] colours every religion tile.
  static bool religionUsesTone = false;

  /// One shimmer sweep + pause.
  static Duration shimmerPeriod = const Duration(milliseconds: 3200);
}

/// The colours of one icon: the tile gradient and (for religion symbols) the glyph ink.
@immutable
class IconV3Palette {
  const IconV3Palette(this.top, this.bottom, this.ink);
  final Color top;
  final Color bottom;
  final Color ink;

  @override
  bool operator ==(Object other) =>
      other is IconV3Palette &&
      other.top == top &&
      other.bottom == bottom &&
      other.ink == ink;

  @override
  int get hashCode => Object.hash(top, bottom, ink);
}

const _cream = Color(0xFFFFF7E6);
const _brown = Color(0xFF4E2A08);

/// Deep jewel-tone tiles of the religion symbols (old 8 + new 10). Unknown keys → `null`
/// (the caller then uses the folder's tone, as in v2).
const Map<String, IconV3Palette> kReligionPaletteV3 = {
  'om': IconV3Palette(Color(0xFFC0394A), Color(0xFF6A1222), _cream),
  'crescent': IconV3Palette(Color(0xFF2DB574), Color(0xFF0C5A38), _cream),
  'khanda': IconV3Palette(
    Color(0xFFFFA43A),
    Color(0xFFC9500B),
    Color(0xFFFFFBF2),
  ),
  'cross': IconV3Palette(
    Color(0xFF4F86EC),
    Color(0xFF1B3C8F),
    Color(0xFFFFFFFF),
  ),
  'dharma': IconV3Palette(Color(0xFFFFD86A), Color(0xFFC88A12), _brown),
  'jain': IconV3Palette(Color(0xFFF77A55), Color(0xFFA8301C), _cream),
  'kabir': IconV3Palette(Color(0xFF2FA9BA), Color(0xFF0E5463), _cream),
  'ektara': IconV3Palette(Color(0xFF2FA9BA), Color(0xFF0E5463), _cream),
  'swastik': IconV3Palette(
    Color(0xFFF2533B),
    Color(0xFF9C1A0C),
    Color(0xFFFFF1C9),
  ),
  'trishul': IconV3Palette(
    Color(0xFF7489AB),
    Color(0xFF2B3750),
    Color(0xFFF4F7FF),
  ),
  'kamal': IconV3Palette(
    Color(0xFFB06BE0),
    Color(0xFF5A2486),
    Color(0xFFFFF0F8),
  ),
  'deepak': IconV3Palette(
    Color(0xFF4C52B8),
    Color(0xFF1B1D52),
    Color(0xFFFFE08A),
  ),
  'shikhar': IconV3Palette(Color(0xFFE07250), Color(0xFF8E2C18), _cream),
  'mangal-kalash': IconV3Palette(
    Color(0xFFE85A97),
    Color(0xFF8E1849),
    Color(0xFFFFF1D2),
  ),
  'surya': IconV3Palette(
    Color(0xFFFFC23D),
    Color(0xFFE5571A),
    Color(0xFF6E1608),
  ),
  'vriksh': IconV3Palette(Color(0xFF7CCB52), Color(0xFF2A6E19), _cream),
  'bahai': IconV3Palette(
    Color(0xFF3CAEE8),
    Color(0xFF13568F),
    Color(0xFFFFFDF2),
  ),
  'atash': IconV3Palette(
    Color(0xFF5A5F6B),
    Color(0xFF1E2127),
    Color(0xFFFFC15A),
  ),
};

/// The identity colour of each folder key (its book cover / main colour). The v3 folder tile
/// is a light, glossy tint of it, so the saturated cover still stands out on the tile.
const Map<String, Color> kFolderHueV3 = {
  'scroll': Color(0xFFD9A233),
  'book-red': Color(0xFFD93A45),
  'book-green': Color(0xFF2E9F5B),
  'book-blue': Color(0xFF3B73D9),
  'book-orange': Color(0xFFEE8A24),
  'swords': Color(0xFF7D8BA3),
  'books': Color(0xFFC28A3A),
  'quran': Color(0xFF1F7A4D),
  'hadees': Color(0xFF1C8C86),
  'granth-sahib': Color(0xFF2F58B8),
  'dasam': Color(0xFF8C2B3A),
  'bible': Color(0xFF3A4170),
  'tripitak': Color(0xFFD9A84A),
  'dhammapad': Color(0xFFE5871C),
  'kabir-sagar': Color(0xFF1C7C8C),
  'bijak': Color(0xFF8A5A2C),
  'shabdavali': Color(0xFF7B4FB0),
  'misc': Color(0xFFE09A3E),
  'gita': Color(0xFF3D3FA3),
  'ved': Color(0xFFE09A12),
  'ramayan': Color(0xFF557A1C),
  'mahabharat': Color(0xFF9A2318),
  'puran': Color(0xFFD6457A),
  'upanishad': Color(0xFF33475B),
  'bhagwat': Color(0xFF1B8CC4),
  'shiv': Color(0xFF586579),
  'devi': Color(0xFFB3164C),
  'hanuman': Color(0xFFE55A1B),
  'satsang': Color(0xFF128A70),
  'bhajan': Color(0xFFC23F9C),
  'aarti': Color(0xFFB4621C),
  'mala': Color(0xFF6A4434),
  'kalash': Color(0xFF2E7D3A),
  'mandir': Color(0xFF8A2346),
  'sant-vani': Color(0xFF4A5DA6),
  'gyan': Color(0xFF1F2A80),
  'amritvani': Color(0xFF0A8C8C),
  'sakhi': Color(0xFF4A4444),
};

Color _hsl(Color c, {double? s, required double l, double sMul = 1}) {
  final h = HSLColor.fromColor(c);
  return h
      .withSaturation(((s ?? h.saturation) * sMul).clamp(0.0, 1.0))
      .withLightness(l.clamp(0.0, 1.0))
      .toColor();
}

/// The light glossy tile of a folder key (unknown keys → the `misc` tile).
IconV3Palette folderPaletteV3(String key) {
  final hue = kFolderHueV3[key] ?? kFolderHueV3['misc']!;
  final sat = HSLColor.fromColor(hue).saturation;
  final s = math.min(sat, 0.85);
  return IconV3Palette(
    _hsl(hue, s: s * 0.95, l: 0.93),
    _hsl(hue, s: s * 0.80, l: 0.79),
    hue,
  );
}

// ---- geometry (unit box) -----------------------------------------------------------------

/// The tile inside the 0..1 box; the room under it holds the drop shadow.
const Rect kTileRectV3 = Rect.fromLTRB(0.035, 0.022, 0.965, 0.952);
const Radius kTileRadiusV3 = Radius.circular(0.255);
final RRect kTileRRectV3 = RRect.fromRectAndRadius(kTileRectV3, kTileRadiusV3);
final Path _tilePath = Path()..addRRect(kTileRRectV3);

/// The gloss: the tile cut by a big ellipse, so the sheen ends in a soft curve mid-tile.
final Path _glossPath = Path.combine(
  PathOperation.intersect,
  Path()..addRRect(kTileRRectV3.deflate(0.012)),
  Path()..addOval(const Rect.fromLTRB(-0.42, -0.70, 1.42, 0.52)),
);

const _unit = Rect.fromLTWH(0, 0, 1, 1);

// ---- painting ----------------------------------------------------------------------------

/// Paints shadow + gradient tile + inner bevel. [deep] = a dark jewel tile (religion);
/// otherwise a light tint tile (folders). [dark] = the app is in dark theme.
void paintTileV3(
  Canvas c,
  IconV3Palette p, {
  required bool deep,
  required bool dark,
}) {
  final r = kTileRRectV3;
  // 1) soft drop shadow: three stacked translucent copies, offset down (no blur).
  final shadowInk = dark
      ? const Color(0xFF000000)
      : Color.lerp(p.bottom, const Color(0xFF2A1406), deep ? 0.55 : 0.80)!;
  final base = dark ? 0.20 : (deep ? 0.11 : 0.085);
  for (final (dy, grow, a) in const [
    (0.040, 0.000, 0.55),
    (0.028, -0.006, 0.75),
    (0.016, -0.010, 1.0),
  ]) {
    c.drawRRect(
      r.shift(Offset(0, dy)).inflate(grow),
      Paint()..color = shadowInk.withValues(alpha: base * a),
    );
  }
  // 2) the gradient body: lit from the top-left.
  c.drawRRect(
    r,
    Paint()
      ..shader = LinearGradient(
        begin: const Alignment(-0.55, -1),
        end: const Alignment(0.55, 1),
        colors: [
          Color.lerp(p.top, Colors.white, deep ? 0.04 : 0.25)!,
          p.top,
          p.bottom,
        ],
        stops: const [0.0, 0.32, 1.0],
      ).createShader(kTileRectV3),
  );
  // a faint radial glow behind the symbol gives the tile some volume
  c.drawRRect(
    r,
    Paint()
      ..shader = RadialGradient(
        center: const Alignment(0, -0.05),
        radius: 0.62,
        colors: [
          Colors.white.withValues(alpha: deep ? 0.14 : 0.20),
          Colors.white.withValues(alpha: 0),
        ],
      ).createShader(kTileRectV3),
  );
  // 3) inner bevel: a bright top edge and a shaded bottom edge, just inside the rim.
  final inner = r.deflate(0.016);
  // the shaded edge is a deeper shade of the tile's own hue (black would turn it grey)
  final edge = Color.lerp(
    p.bottom,
    deep ? Colors.black : p.ink,
    deep ? 0.5 : 0.55,
  )!;
  c.drawRRect(
    inner,
    Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 0.02
      ..shader = LinearGradient(
        begin: Alignment.topCenter,
        end: Alignment.bottomCenter,
        colors: [
          Colors.white.withValues(alpha: deep ? 0.42 : 0.95),
          Colors.white.withValues(alpha: 0),
        ],
        stops: const [0.0, 0.42],
      ).createShader(kTileRectV3),
  );
  c.drawRRect(
    inner,
    Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 0.022
      ..shader = LinearGradient(
        begin: Alignment.topCenter,
        end: Alignment.bottomCenter,
        colors: [
          edge.withValues(alpha: 0),
          edge.withValues(alpha: deep ? 0.30 : 0.22),
        ],
        stops: const [0.6, 1.0],
      ).createShader(kTileRectV3),
  );
  // 4) the rim: a crisp darker hairline (and a faint light one in dark theme).
  c.drawRRect(
    r,
    Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 0.008
      ..color = Color.lerp(
        p.bottom,
        Colors.black,
        deep ? 0.25 : 0.1,
      )!.withValues(alpha: deep ? 0.55 : 0.35),
  );
  if (dark) {
    c.drawRRect(
      r.inflate(0.006),
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 0.006
        ..color = Colors.white.withValues(alpha: 0.10),
    );
  }
}

/// The glossy sheen over the top of the tile; painted after the symbol.
void paintGlossV3(Canvas c, {required bool deep}) {
  c.drawPath(
    _glossPath,
    Paint()
      ..shader = LinearGradient(
        begin: Alignment.topCenter,
        end: Alignment.bottomCenter,
        colors: [
          Colors.white.withValues(alpha: deep ? 0.26 : 0.30),
          Colors.white.withValues(alpha: deep ? 0.06 : 0.06),
          Colors.white.withValues(alpha: 0.0),
        ],
        stops: const [0.0, 0.62, 1.0],
      ).createShader(const Rect.fromLTRB(0, 0.02, 1, 0.52)),
  );
}

/// A soft contact shadow (an ellipse that fades out) under a free-standing illustration.
void paintContactShadowV3(
  Canvas c,
  Rect oval,
  Color ink, {
  double alpha = 0.22,
}) {
  // a round radial gradient, squashed into the oval
  c.save();
  c.translate(oval.center.dx, oval.center.dy);
  c.scale(oval.width / 2, oval.height / 2);
  c.drawCircle(
    Offset.zero,
    1,
    Paint()
      ..shader = RadialGradient(
        colors: [
          ink.withValues(alpha: alpha),
          ink.withValues(alpha: 0),
        ],
      ).createShader(Rect.fromCircle(center: Offset.zero, radius: 1)),
  );
  c.restore();
}

/// A small LRU of recorded icons (unit-box pictures). Evicted pictures are left to the GC —
/// a frame that already recorded one keeps its own reference.
abstract final class IconV3Cache {
  static const int capacity = 256;
  static final LinkedHashMap<Object, ui.Picture> _m = LinkedHashMap();

  static ui.Picture get(Object key, void Function(Canvas c) draw) {
    final hit = _m.remove(key);
    if (hit != null) return _m[key] = hit;
    final rec = ui.PictureRecorder();
    draw(Canvas(rec, _unit));
    final pic = rec.endRecording();
    _m[key] = pic;
    if (_m.length > capacity) _m.remove(_m.keys.first);
    return pic;
  }

  static int get length => _m.length;
  static void clear() => _m.clear();
}

// ---- the widget frame ----------------------------------------------------------------------

/// Sizes an icon painter and, only when asked and allowed, lays the shimmer over it.
class IconV3Box extends StatelessWidget {
  const IconV3Box({
    super.key,
    required this.size,
    required this.painter,
    this.shimmer = false,
  });
  final double size;
  final CustomPainter painter;
  final bool shimmer;

  /// True when this context lets an icon shimmer.
  static bool shimmerAllowed(BuildContext context) =>
      GranthIconStyle.premium &&
      GranthIconStyle.shimmerEnabled &&
      !(MediaQuery.maybeDisableAnimationsOf(context) ?? false) &&
      TickerMode.valuesOf(context).enabled;

  @override
  Widget build(BuildContext context) {
    final base = CustomPaint(painter: painter, size: Size.square(size));
    if (!shimmer || !shimmerAllowed(context)) {
      return SizedBox(width: size, height: size, child: base);
    }
    return SizedBox(
      width: size,
      height: size,
      child: _Shimmer(child: RepaintBoundary(child: base)),
    );
  }
}

class _Shimmer extends StatefulWidget {
  const _Shimmer({required this.child});
  final Widget child;

  @override
  State<_Shimmer> createState() => _ShimmerState();
}

class _ShimmerState extends State<_Shimmer>
    with SingleTickerProviderStateMixin {
  late final AnimationController _c = AnimationController(
    vsync: this,
    duration: GranthIconStyle.shimmerPeriod,
  )..repeat();

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => CustomPaint(
    foregroundPainter: IconShimmerPainter(_c),
    child: widget.child,
  );
}

/// The light band that sweeps over the tile (first 45 % of each period, then rests).
class IconShimmerPainter extends CustomPainter {
  IconShimmerPainter(this.t) : super(repaint: t);
  final Animation<double> t;

  @override
  void paint(Canvas canvas, Size size) {
    final v = t.value / 0.45;
    if (v >= 1) return;
    final s = size.shortestSide;
    canvas.save();
    canvas.translate((size.width - s) / 2, (size.height - s) / 2);
    canvas.scale(s, s);
    canvas.clipPath(_tilePath);
    final x = -2.2 + 4.4 * Curves.easeInOut.transform(v);
    canvas.drawRect(
      _unit,
      Paint()
        ..shader = LinearGradient(
          begin: Alignment(x - 1, -1),
          end: Alignment(x + 1, 1),
          colors: [
            Colors.white.withValues(alpha: 0),
            Colors.white.withValues(alpha: 0.30),
            Colors.white.withValues(alpha: 0),
          ],
          stops: const [0.38, 0.5, 0.62],
        ).createShader(_unit),
    );
    canvas.restore();
  }

  @override
  bool shouldRepaint(IconShimmerPainter old) => old.t != t;
}
