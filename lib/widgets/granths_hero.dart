import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../theme/colors.dart';
import 'common.dart';

/// t368 — the top of the Granth tab (reference ref1–3): open-book-and-flame logo, serif
/// "Granths", "Sacred texts and scriptures" between gold rules, a faint temple silhouette and
/// the maroon "Multiple granth PDF ›" pill. Cream + maroon + gold, all vector (no assets).
class GranthsHero extends StatelessWidget {
  const GranthsHero({super.key, required this.title, required this.subtitle, required this.onPdf});
  final String title;
  final String subtitle;
  final VoidCallback onPdf;

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(builder: (context, c) {
      final w = c.maxWidth.isFinite ? c.maxWidth : 400.0;
      // v2 (ref1/ref3 placement): ONE header row — logo · serif "Granths" over the two-line
      // italic subtitle · temple art behind · the maroon "Multiple granth PDF ›" pill on the
      // right of the same row. Sizes scale with the width (360 → 411 dp phones, tablets).
      final narrow = w < 380;
      final logo = narrow ? 56.0 : (w < 560 ? 64.0 : 70.0);
      final titleSize = narrow ? 29.0 : (w < 560 ? 32.0 : 36.0);
      final parts = _subtitleLines(subtitle);
      final sub = GText.script(size: narrow ? 11.5 : 12.5, color: GColors.brown, height: 1.2)
          .copyWith(fontFamily: 'DMSerif', fontFamilyFallback: GFonts.scriptFallback, fontStyle: FontStyle.italic);
      final head = Row(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.center, children: [
        SizedBox(width: logo, height: logo, child: const CustomPaint(painter: GranthsLogoPainter())),
        const SizedBox(width: 6),
        Flexible(
          child: FittedBox(
            fit: BoxFit.scaleDown,
            alignment: Alignment.centerLeft,
            child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.center, children: [
              Text(title,
                  maxLines: 1,
                  style: GText.script(size: titleSize, color: GColors.maroon, height: 1.05).copyWith(
                    fontFamily: 'DMSerif',
                    fontFamilyFallback: GFonts.scriptFallback,
                    shadows: [Shadow(color: GColors.gold.withValues(alpha: 0.35), offset: const Offset(0, 1.5), blurRadius: 2)],
                  )),
              const SizedBox(height: 2),
              Row(mainAxisSize: MainAxisSize.min, children: [
                _rule(),
                const SizedBox(width: 5),
                Text(parts.$1, maxLines: 1, style: sub),
                const SizedBox(width: 5),
                _rule(),
              ]),
              if (parts.$2.isNotEmpty) Text(parts.$2, maxLines: 1, style: sub),
            ]),
          ),
        ),
      ]);
      final pill = KeyedSubtree(key: const ValueKey('header-trailing'), child: GranthsPdfPill(onTap: onPdf, compact: narrow));
      return SizedBox(
        key: const ValueKey('granths-hero-row'),
        height: logo + 14,
        child: Stack(clipBehavior: Clip.none, children: [
          // temple silhouette between the title and the pill, behind everything (ref3)
          Positioned(
            right: w * 0.24,
            top: -16,
            width: narrow ? 100 : 118,
            height: logo + 26,
            child: const IgnorePointer(child: CustomPaint(painter: TemplePainter())),
          ),
          Positioned.fill(
            child: Row(crossAxisAlignment: CrossAxisAlignment.center, children: [
              Expanded(child: Align(alignment: Alignment.centerLeft, child: head)),
              const SizedBox(width: 6),
              Flexible(child: Align(alignment: Alignment.centerRight, child: FittedBox(fit: BoxFit.scaleDown, child: pill))),
            ]),
          ),
        ]),
      );
    });
  }

  /// "Sacred texts and scriptures" → ("Sacred texts", "and scriptures") like the reference.
  static (String, String) _subtitleLines(String s) {
    final i = s.indexOf(' and ');
    if (i > 0) return (s.substring(0, i), s.substring(i + 1));
    return (s, '');
  }

  Widget _rule() => Container(
        width: 18,
        height: 1.4,
        decoration: BoxDecoration(gradient: LinearGradient(colors: [GColors.gold.withValues(alpha: 0), GColors.gold, GColors.gold.withValues(alpha: 0)])),
      );
}

/// The maroon "Multiple granth PDF ›" pill (gold rim, white PDF badge).
class GranthsPdfPill extends StatelessWidget {
  const GranthsPdfPill({super.key, required this.onTap, this.compact = false});
  final VoidCallback onTap;

  /// Narrow phones (360 dp): a slightly smaller pill so it shares the row with the title.
  final bool compact;

  @override
  Widget build(BuildContext context) => Semantics(
        button: true,
        label: 'Multiple granth PDF',
        child: Pressable(
          onTap: onTap,
          child: Container(
            key: const ValueKey('multi-pdf-pill'),
            padding: EdgeInsets.fromLTRB(5, 5, compact ? 8 : 10, 5),
            decoration: BoxDecoration(
              color: GColors.maroon, // t408: flat old maroon, no gloss
              borderRadius: BorderRadius.circular(999),
            ),
            child: Row(mainAxisSize: MainAxisSize.min, children: [
              Container(
                width: compact ? 22 : 25,
                height: compact ? 22 : 25,
                alignment: Alignment.center,
                decoration: BoxDecoration(color: GColors.paper, borderRadius: BorderRadius.circular(8)),
                child: Text('PDF', style: GText.sans(size: compact ? 7.5 : 8.5, weight: FontWeight.w800, color: GColors.maroon, height: 1)),
              ),
              SizedBox(width: compact ? 6 : 7),
              Flexible(child: ExcludeSemantics(child: Text('Multiple granth PDF', maxLines: 1, overflow: TextOverflow.ellipsis, style: GText.sans(size: compact ? 11 : 12, weight: FontWeight.w700, color: GColors.paper, height: 1.2)))),
              const SizedBox(width: 3),
              GIcon('chevron-right', size: compact ? 13 : 15, color: GColors.paper),
            ]),
          ),
        ),
      );
}

/// Open book (maroon cover, cream pages) with a gold lotus-flame rising from it.
class GranthsLogoPainter extends CustomPainter {
  const GranthsLogoPainter();

  @override
  void paint(Canvas canvas, Size size) {
    final s = size.shortestSide;
    canvas.save();
    canvas.scale(s / 100);
    // glow
    canvas.drawCircle(const Offset(50, 40), 34, Paint()..shader = RadialGradient(colors: [const Color(0x88FFD36B), const Color(0x00FFD36B)]).createShader(Rect.fromCircle(center: const Offset(50, 40), radius: 34)));
    // rays
    final ray = Paint()
      ..color = const Color(0x66E2A93A)
      ..strokeWidth = 1.2
      ..strokeCap = StrokeCap.round;
    for (var i = 0; i < 9; i++) {
      final a = math.pi * (1.1 + i * 0.1);
      canvas.drawLine(Offset(50 + math.cos(a) * 22, 44 + math.sin(a) * 22), Offset(50 + math.cos(a) * 34, 44 + math.sin(a) * 34), ray);
    }
    // flame petals (lotus-like)
    final gold = Paint()..shader = const LinearGradient(begin: Alignment.topCenter, end: Alignment.bottomCenter, colors: [Color(0xFFFFE9A6), Color(0xFFF3A417), Color(0xFFD9531C)]).createShader(const Rect.fromLTWH(30, 14, 40, 44));
    Path petal(double dx, double h, double w) => Path()
      ..moveTo(50 + dx, 58)
      ..quadraticBezierTo(50 + dx - w, 58 - h * 0.55, 50 + dx * 1.6, 58 - h)
      ..quadraticBezierTo(50 + dx + w, 58 - h * 0.55, 50 + dx, 58)
      ..close();
    canvas.drawPath(petal(-11, 22, 8), gold);
    canvas.drawPath(petal(11, 22, 8), gold);
    canvas.drawPath(petal(0, 40, 11), gold);
    canvas.drawPath(petal(0, 24, 5), Paint()..color = const Color(0xCCFFF6D8));
    // book cover
    final cover = Path()
      ..moveTo(8, 62)
      ..quadraticBezierTo(30, 52, 50, 64)
      ..quadraticBezierTo(70, 52, 92, 62)
      ..lineTo(92, 80)
      ..quadraticBezierTo(70, 72, 50, 86)
      ..quadraticBezierTo(30, 72, 8, 80)
      ..close();
    canvas.drawPath(cover, Paint()..shader = const LinearGradient(begin: Alignment.topCenter, end: Alignment.bottomCenter, colors: [Color(0xFFB0213A), Color(0xFF6E0F20)]).createShader(const Rect.fromLTWH(8, 52, 84, 34)));
    // pages
    final pages = Paint()..color = const Color(0xFFFFF6E2);
    final left = Path()
      ..moveTo(13, 60)
      ..quadraticBezierTo(32, 51, 50, 62)
      ..lineTo(50, 80)
      ..quadraticBezierTo(32, 69, 13, 76)
      ..close();
    final right = Path()
      ..moveTo(87, 60)
      ..quadraticBezierTo(68, 51, 50, 62)
      ..lineTo(50, 80)
      ..quadraticBezierTo(68, 69, 87, 76)
      ..close();
    canvas.drawPath(left, pages);
    canvas.drawPath(right, pages);
    final line = Paint()
      ..color = const Color(0x55A0293D)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 0.9;
    for (var i = 0; i < 3; i++) {
      final y = 63.0 + i * 4.5;
      canvas.drawPath(Path()..moveTo(18, y + 1)..quadraticBezierTo(33, y - 6, 46, y + 2), line);
      canvas.drawPath(Path()..moveTo(82, y + 1)..quadraticBezierTo(67, y - 6, 54, y + 2), line);
    }
    canvas.drawLine(const Offset(50, 62), const Offset(50, 82), Paint()..color = const Color(0xFFC9A84C)..strokeWidth = 1.2);
    canvas.drawPath(cover, Paint()..style = PaintingStyle.stroke..strokeWidth = 1.2..color = const Color(0xFFE2C97E));
    canvas.restore();
  }

  @override
  bool shouldRepaint(GranthsLogoPainter old) => false;
}

/// A soft gold temple silhouette (shikhara + domes) with two birds.
class TemplePainter extends CustomPainter {
  const TemplePainter();

  @override
  void paint(Canvas canvas, Size size) {
    canvas.save();
    canvas.scale(size.width / 130, size.height / 96);
    final p = Paint()..shader = LinearGradient(begin: Alignment.topCenter, end: Alignment.bottomCenter, colors: [GColors.gold.withValues(alpha: 0.42), GColors.gold.withValues(alpha: 0.14)]).createShader(const Rect.fromLTWH(0, 0, 130, 96));
    Path spire(double cx, double base, double h, double w) => Path()
      ..moveTo(cx - w, base)
      ..quadraticBezierTo(cx - w * 0.9, base - h * 0.6, cx, base - h)
      ..quadraticBezierTo(cx + w * 0.9, base - h * 0.6, cx + w, base)
      ..close();
    canvas.drawRect(const Rect.fromLTWH(14, 70, 102, 26), p);
    canvas.drawPath(spire(65, 72, 62, 18), p);
    canvas.drawPath(spire(38, 74, 36, 12), p);
    canvas.drawPath(spire(92, 74, 36, 12), p);
    canvas.drawPath(spire(20, 76, 22, 8), p);
    canvas.drawPath(spire(110, 76, 22, 8), p);
    canvas.drawRect(const Rect.fromLTWH(64.2, 2, 1.6, 9), p);
    // arched doors
    final door = Paint()..color = const Color(0x40FDF6E3);
    for (final x in [48.0, 65.0, 82.0]) {
      canvas.drawRRect(RRect.fromRectAndCorners(Rect.fromLTWH(x - 4, 80, 8, 16), topLeft: const Radius.circular(4), topRight: const Radius.circular(4)), door);
    }
    // birds
    final b = Paint()
      ..color = GColors.gold.withValues(alpha: 0.55)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.3
      ..strokeCap = StrokeCap.round;
    for (final o in [const Offset(104, 14), const Offset(118, 24)]) {
      canvas.drawPath(Path()..moveTo(o.dx - 5, o.dy)..quadraticBezierTo(o.dx - 2, o.dy - 3, o.dx, o.dy)..quadraticBezierTo(o.dx + 2, o.dy - 3, o.dx + 5, o.dy), b);
    }
    canvas.restore();
  }

  @override
  bool shouldRepaint(TemplePainter old) => false;
}

/// The maroon swoosh in the top-left corner of the Granth tab and the gold edge on it.
class HeroSwooshPainter extends CustomPainter {
  const HeroSwooshPainter();
  @override
  void paint(Canvas canvas, Size size) {
    final w = size.width;
    final path = Path()
      ..moveTo(0, 0)
      ..lineTo(w * 0.32, 0)
      ..quadraticBezierTo(w * 0.12, size.height * 0.10, 0, size.height * 0.42)
      ..close();
    canvas.drawPath(path, Paint()..shader = const LinearGradient(colors: [Color(0xFF8E1428), Color(0x007B1F2E)], begin: Alignment.topLeft, end: Alignment.bottomRight).createShader(Offset.zero & size));
    final edge = Path()
      ..moveTo(w * 0.32, 0)
      ..quadraticBezierTo(w * 0.12, size.height * 0.10, 0, size.height * 0.42);
    canvas.drawPath(edge, Paint()..style = PaintingStyle.stroke..strokeWidth = 1.4..color = GColors.gold.withValues(alpha: 0.55));
  }

  @override
  bool shouldRepaint(HeroSwooshPainter old) => false;
}
