part of 'religion_symbol.dart';

/// Proposed NEW religion icons (design stage, local only), drawn like the existing ones:
/// one ink colour (white on the maroon tile), bold silhouettes with punched details.
/// NOT offered by the picker yet: the installed user apps and the server
/// (`RELIGION_PICKER_ICONS`) do not know these keys.
const List<String> newReligionSymbolNames = [
  'swastik',
  'trishul',
  'kamal',
  'deepak',
  'shikhar',
  'mangal-kalash',
  'surya',
  'vriksh',
  'bahai',
  'atash',
];

extension _NewReligionSymbols on ReligionSymbolPainter {
  bool _paintNew(Canvas c, String name) {
    switch (name) {
      case 'swastik':
        _swastik(c);
      case 'trishul':
        _trishul(c);
      case 'kamal':
        _kamal(c);
      case 'deepak':
        _deepak(c);
      case 'shikhar':
        _shikhar(c);
      case 'mangal-kalash':
        _kalash(c);
      case 'surya':
        _surya(c);
      case 'vriksh':
        _vriksh(c);
      case 'bahai':
        _bahai(c);
      case 'atash':
        _atash(c);
      default:
        return false;
    }
    return true;
  }

  /// स्वस्तिक with its four dots.
  void _swastik(Canvas c) {
    const w = 0.075;
    final s = Paint()
      ..color = ink
      ..style = PaintingStyle.stroke
      ..strokeWidth = w
      ..strokeCap = StrokeCap.square
      ..strokeJoin = StrokeJoin.miter
      ..isAntiAlias = true;
    const o = Offset(0.5, 0.5);
    const r = 0.25;
    c.drawLine(const Offset(0.5, 0.25), const Offset(0.5, 0.75), s);
    c.drawLine(const Offset(0.25, 0.5), const Offset(0.75, 0.5), s);
    c.drawLine(const Offset(0.5, 0.25), const Offset(0.75, 0.25), s);
    c.drawLine(const Offset(0.75, 0.5), const Offset(0.75, 0.75), s);
    c.drawLine(const Offset(0.5, 0.75), const Offset(0.25, 0.75), s);
    c.drawLine(const Offset(0.25, 0.5), const Offset(0.25, 0.25), s);
    for (final d in const [
      Offset(-1, -1),
      Offset(1, -1),
      Offset(1, 1),
      Offset(-1, 1),
    ]) {
      c.drawCircle(o + d * (r * 0.5), 0.042, _fill);
    }
  }

  /// त्रिशूल with a डमरू.
  void _trishul(Canvas c) {
    _punched(
      c,
      () {
        c.drawLine(
          const Offset(0.5, 0.38),
          const Offset(0.5, 0.86),
          _stroke(0.05),
        );
        // centre prong
        c.drawPath(
          Path()
            ..moveTo(0.5, 0.12)
            ..lineTo(0.55, 0.24)
            ..lineTo(0.5, 0.42)
            ..lineTo(0.45, 0.24)
            ..close(),
          _fill,
        );
        // side prongs
        c.drawPath(
          Path()
            ..moveTo(0.5, 0.44)
            ..quadraticBezierTo(0.27, 0.44, 0.27, 0.2),
          _stroke(0.045),
        );
        c.drawPath(
          Path()
            ..moveTo(0.5, 0.44)
            ..quadraticBezierTo(0.73, 0.44, 0.73, 0.2),
          _stroke(0.045),
        );
        for (final x in [0.27, 0.73]) {
          c.drawPath(
            Path()
              ..moveTo(x, 0.13)
              ..lineTo(x + 0.04, 0.22)
              ..lineTo(x - 0.04, 0.22)
              ..close(),
            _fill,
          );
        }
        // damru
        c.drawPath(
          Path()
            ..moveTo(0.37, 0.53)
            ..lineTo(0.63, 0.53)
            ..lineTo(0.53, 0.62)
            ..lineTo(0.63, 0.71)
            ..lineTo(0.37, 0.71)
            ..lineTo(0.47, 0.62)
            ..close(),
          _fill,
        );
      },
      (cut) {
        cut
          ..style = PaintingStyle.stroke
          ..strokeWidth = 0.014;
        c.drawLine(const Offset(0.4, 0.555), const Offset(0.6, 0.555), cut);
        c.drawLine(const Offset(0.4, 0.685), const Offset(0.6, 0.685), cut);
      },
    );
  }

  /// कमल — the lotus on water.
  void _kamal(Canvas c) {
    Path petal(double len, double w) => Path()
      ..moveTo(0, 0)
      ..quadraticBezierTo(w, -len * 0.55, 0, -len)
      ..quadraticBezierTo(-w, -len * 0.55, 0, 0)
      ..close();
    const base = Offset(0.5, 0.68);
    _punched(
      c,
      () {
        for (final (a, len, w) in [
          (-1.3, 0.27, 0.1),
          (1.3, 0.27, 0.1),
          (-0.66, 0.38, 0.12),
          (0.66, 0.38, 0.12),
          (0.0, 0.5, 0.14),
        ]) {
          c.save();
          c.translate(base.dx, base.dy);
          c.rotate(a);
          c.drawPath(petal(len, w), _fill);
          c.restore();
        }
        c.drawPath(
          Path()
            ..moveTo(0.18, 0.77)
            ..quadraticBezierTo(0.34, 0.72, 0.5, 0.77)
            ..quadraticBezierTo(0.66, 0.82, 0.82, 0.77),
          _stroke(0.04),
        );
      },
      (cut) {
        cut
          ..style = PaintingStyle.stroke
          ..strokeWidth = 0.018;
        // gaps between petals so each one reads
        for (final a in [-0.98, -0.33, 0.33, 0.98]) {
          c.save();
          c.translate(base.dx, base.dy);
          c.rotate(a);
          c.drawLine(const Offset(0, -0.03), const Offset(0, -0.34), cut);
          c.restore();
        }
      },
    );
  }

  /// दीपक — the oil lamp and its flame.
  void _deepak(Canvas c) {
    _punched(
      c,
      () {
        c.drawPath(
          Path()
            ..moveTo(0.5, 0.13)
            ..cubicTo(0.62, 0.28, 0.63, 0.43, 0.5, 0.49)
            ..cubicTo(0.37, 0.43, 0.38, 0.28, 0.5, 0.13)
            ..close(),
          _fill,
        );
        c.drawPath(
          Path()
            ..moveTo(0.2, 0.53)
            ..lineTo(0.8, 0.53)
            ..quadraticBezierTo(0.78, 0.73, 0.5, 0.75)
            ..quadraticBezierTo(0.22, 0.73, 0.2, 0.53)
            ..close(),
          _fill,
        );
        c.drawPath(
          Path()
            ..moveTo(0.78, 0.53)
            ..quadraticBezierTo(0.86, 0.5, 0.88, 0.44)
            ..quadraticBezierTo(0.86, 0.58, 0.76, 0.61)
            ..close(),
          _fill,
        );
        c.drawRRect(
          RRect.fromRectAndRadius(
            const Rect.fromLTRB(0.38, 0.78, 0.62, 0.84),
            const Radius.circular(0.03),
          ),
          _fill,
        );
      },
      (cut) {
        c.drawPath(
          Path()
            ..moveTo(0.5, 0.29)
            ..cubicTo(0.56, 0.36, 0.56, 0.42, 0.5, 0.45)
            ..cubicTo(0.44, 0.42, 0.44, 0.36, 0.5, 0.29)
            ..close(),
          cut,
        );
        c.drawLine(
          const Offset(0.27, 0.6),
          const Offset(0.73, 0.6),
          cut
            ..style = PaintingStyle.stroke
            ..strokeWidth = 0.02
            ..strokeCap = StrokeCap.round,
        );
      },
    );
  }

  /// मंदिर शिखर with its कलश and ध्वज.
  void _shikhar(Canvas c) {
    _punched(
      c,
      () {
        c.drawLine(
          const Offset(0.5, 0.3),
          const Offset(0.5, 0.11),
          _stroke(0.022),
        );
        c.drawPath(
          Path()
            ..moveTo(0.51, 0.11)
            ..lineTo(0.68, 0.15)
            ..lineTo(0.51, 0.2)
            ..close(),
          _fill,
        );
        c.drawCircle(const Offset(0.5, 0.29), 0.035, _fill);
        c.drawPath(
          Path()
            ..moveTo(0.5, 0.3)
            ..cubicTo(0.63, 0.38, 0.69, 0.52, 0.69, 0.6)
            ..lineTo(0.31, 0.6)
            ..cubicTo(0.31, 0.52, 0.37, 0.38, 0.5, 0.3)
            ..close(),
          _fill,
        );
        c.drawRect(const Rect.fromLTRB(0.24, 0.6, 0.76, 0.84), _fill);
        c.drawRect(const Rect.fromLTRB(0.18, 0.84, 0.82, 0.88), _fill);
      },
      (cut) {
        cut
          ..style = PaintingStyle.stroke
          ..strokeWidth = 0.016;
        c.drawLine(const Offset(0.39, 0.46), const Offset(0.61, 0.46), cut);
        c.drawLine(const Offset(0.35, 0.53), const Offset(0.65, 0.53), cut);
        c.drawLine(const Offset(0.24, 0.64), const Offset(0.76, 0.64), cut);
        cut.style = PaintingStyle.fill;
        c.drawPath(
          Path()
            ..moveTo(0.44, 0.84)
            ..lineTo(0.44, 0.74)
            ..quadraticBezierTo(0.5, 0.67, 0.56, 0.74)
            ..lineTo(0.56, 0.84)
            ..close(),
          cut,
        );
      },
    );
  }

  /// मंगल कलश with mango leaves and a coconut.
  void _kalash(Canvas c) {
    _punched(
      c,
      () {
        for (final a in [-1.05, -0.5, 0.5, 1.05]) {
          c.save();
          c.translate(0.5, 0.4);
          c.rotate(a);
          c.drawPath(
            Path()
              ..moveTo(0, 0)
              ..quadraticBezierTo(0.06, -0.11, 0, -0.22)
              ..quadraticBezierTo(-0.06, -0.11, 0, 0)
              ..close(),
            _fill,
          );
          c.restore();
        }
        c.drawOval(
          Rect.fromCenter(
            center: const Offset(0.5, 0.27),
            width: 0.16,
            height: 0.19,
          ),
          _fill,
        );
        c.drawRRect(
          RRect.fromRectAndRadius(
            const Rect.fromLTRB(0.37, 0.38, 0.63, 0.43),
            const Radius.circular(0.02),
          ),
          _fill,
        );
        c.drawPath(
          Path()
            ..moveTo(0.41, 0.43)
            ..lineTo(0.59, 0.43)
            ..lineTo(0.585, 0.46)
            ..cubicTo(0.79, 0.5, 0.79, 0.78, 0.62, 0.82)
            ..lineTo(0.38, 0.82)
            ..cubicTo(0.21, 0.78, 0.21, 0.5, 0.415, 0.46)
            ..close(),
          _fill,
        );
        c.drawRRect(
          RRect.fromRectAndRadius(
            const Rect.fromLTRB(0.36, 0.82, 0.64, 0.87),
            const Radius.circular(0.02),
          ),
          _fill,
        );
      },
      (cut) {
        cut
          ..style = PaintingStyle.stroke
          ..strokeWidth = 0.016
          ..strokeCap = StrokeCap.round;
        c.drawLine(const Offset(0.36, 0.43), const Offset(0.64, 0.43), cut);
        // small swastik on the pot
        const o = Offset(0.5, 0.64);
        const r = 0.065;
        cut.strokeWidth = 0.02;
        cut.strokeCap = StrokeCap.square;
        c.drawLine(o.translate(0, -r), o.translate(0, r), cut);
        c.drawLine(o.translate(-r, 0), o.translate(r, 0), cut);
        c.drawLine(o.translate(0, -r), o.translate(r, -r), cut);
        c.drawLine(o.translate(r, 0), o.translate(r, r), cut);
        c.drawLine(o.translate(0, r), o.translate(-r, r), cut);
        c.drawLine(o.translate(-r, 0), o.translate(-r, -r), cut);
      },
    );
  }

  /// सूर्य — the sun disc with its rays.
  void _surya(Canvas c) {
    const o = Offset(0.5, 0.5);
    _punched(
      c,
      () {
        c.drawCircle(o, 0.19, _fill);
        for (var i = 0; i < 12; i++) {
          final a = i * math.pi / 6;
          final d = Offset(math.cos(a), math.sin(a));
          final n = Offset(-d.dy, d.dx);
          final len = i.isEven ? 0.35 : 0.3;
          final tip = o + d * len;
          final l = o + d * 0.22 + n * 0.045;
          final r = o + d * 0.22 - n * 0.045;
          c.drawPath(
            Path()
              ..moveTo(tip.dx, tip.dy)
              ..lineTo(l.dx, l.dy)
              ..lineTo(r.dx, r.dy)
              ..close(),
            _fill,
          );
        }
      },
      (cut) {
        c.drawCircle(
          o,
          0.14,
          cut
            ..style = PaintingStyle.stroke
            ..strokeWidth = 0.018,
        );
      },
    );
  }

  /// वृक्ष — the tree of life (कल्पवृक्ष): trunk, roots and a full crown.
  void _vriksh(Canvas c) {
    _punched(
      c,
      () {
        for (final (x, y, r) in [
          (0.5, 0.3, 0.15),
          (0.33, 0.4, 0.13),
          (0.67, 0.4, 0.13),
          (0.4, 0.5, 0.12),
          (0.6, 0.5, 0.12),
          (0.5, 0.45, 0.14),
        ]) {
          c.drawCircle(Offset(x, y), r, _fill);
        }
        c.drawPath(
          Path()
            ..moveTo(0.46, 0.55)
            ..lineTo(0.54, 0.55)
            ..lineTo(0.55, 0.76)
            ..quadraticBezierTo(0.6, 0.8, 0.7, 0.82)
            ..lineTo(0.3, 0.82)
            ..quadraticBezierTo(0.4, 0.8, 0.45, 0.76)
            ..close(),
          _fill,
        );
      },
      (cut) {
        cut
          ..style = PaintingStyle.stroke
          ..strokeWidth = 0.02
          ..strokeCap = StrokeCap.round;
        c.drawLine(const Offset(0.5, 0.6), const Offset(0.5, 0.3), cut);
        c.drawLine(const Offset(0.5, 0.48), const Offset(0.36, 0.4), cut);
        c.drawLine(const Offset(0.5, 0.42), const Offset(0.64, 0.35), cut);
        c.drawLine(const Offset(0.5, 0.53), const Offset(0.62, 0.48), cut);
      },
    );
  }

  /// बहाई — the nine-pointed star.
  void _bahai(Canvas c) {
    const o = Offset(0.5, 0.5);
    final p = Path();
    for (var i = 0; i < 18; i++) {
      final a = -math.pi / 2 + i * math.pi / 9;
      final r = i.isEven ? 0.37 : 0.22;
      final pt = o + Offset(math.cos(a), math.sin(a)) * r;
      i == 0 ? p.moveTo(pt.dx, pt.dy) : p.lineTo(pt.dx, pt.dy);
    }
    p.close();
    _punched(c, () => c.drawPath(p, _fill), (cut) {
      c.drawCircle(
        o,
        0.1,
        cut
          ..style = PaintingStyle.stroke
          ..strokeWidth = 0.02,
      );
    });
  }

  /// पारसी — the sacred fire (आतश) in its आफ़रगान vase.
  void _atash(Canvas c) {
    _punched(
      c,
      () {
        // flame
        c.drawPath(
          Path()
            ..moveTo(0.5, 0.12)
            ..cubicTo(0.56, 0.2, 0.68, 0.27, 0.66, 0.4)
            ..quadraticBezierTo(0.64, 0.47, 0.6, 0.48)
            ..lineTo(0.4, 0.48)
            ..quadraticBezierTo(0.36, 0.47, 0.34, 0.4)
            ..cubicTo(0.33, 0.31, 0.4, 0.27, 0.42, 0.2)
            ..quadraticBezierTo(0.46, 0.26, 0.46, 0.31)
            ..cubicTo(0.49, 0.25, 0.5, 0.19, 0.5, 0.12)
            ..close(),
          _fill,
        );
        // bowl
        c.drawPath(
          Path()
            ..moveTo(0.26, 0.5)
            ..lineTo(0.74, 0.5)
            ..quadraticBezierTo(0.72, 0.64, 0.56, 0.66)
            ..lineTo(0.44, 0.66)
            ..quadraticBezierTo(0.28, 0.64, 0.26, 0.5)
            ..close(),
          _fill,
        );
        // stem + foot
        c.drawRect(const Rect.fromLTRB(0.455, 0.66, 0.545, 0.77), _fill);
        c.drawPath(
          Path()
            ..moveTo(0.36, 0.86)
            ..quadraticBezierTo(0.4, 0.77, 0.5, 0.76)
            ..quadraticBezierTo(0.6, 0.77, 0.64, 0.86)
            ..close(),
          _fill,
        );
      },
      (cut) {
        c.drawPath(
          Path()
            ..moveTo(0.52, 0.3)
            ..cubicTo(0.58, 0.36, 0.6, 0.42, 0.55, 0.46)
            ..lineTo(0.45, 0.46)
            ..cubicTo(0.43, 0.41, 0.47, 0.37, 0.52, 0.3)
            ..close(),
          cut,
        );
        c.drawLine(
          const Offset(0.31, 0.555),
          const Offset(0.69, 0.555),
          cut
            ..style = PaintingStyle.stroke
            ..strokeWidth = 0.016
            ..strokeCap = StrokeCap.round,
        );
      },
    );
  }
}
