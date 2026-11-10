part of 'group_icon.dart';

/// Proposed NEW folder icons (design stage, local only). Same book-cover look as
/// `shabdavali` / `book-red` / `kabir-sagar`: a coloured cover with spine, gold ribbon and
/// a symbol on the cover. NOT offered by the picker yet: the installed user apps and the
/// server (`GROUP_ICONS`) do not know these keys, so they are only painted here.
const List<String> newGroupIconNames = [
  'gita',
  'ved',
  'ramayan',
  'mahabharat',
  'puran',
  'upanishad',
  'bhagwat',
  'shiv',
  'devi',
  'hanuman',
  'satsang',
  'bhajan',
  'aarti',
  'mala',
  'kalash',
  'mandir',
  'sant-vani',
  'gyan',
  'amritvani',
  'sakhi',
];

const _cream = Color(0xFFFFF6E0);
const _goldLight = Color(0xFFFFD873);

/// Centre of the cover's symbol area (right of the spine, under the ribbon).
const _o = Offset(0.53, 0.49);

extension _NewFolderIcons on GroupIconPainter {
  /// Paints a new key; false when [name] is not one of [newGroupIconNames].
  bool _paintNew(Canvas c, String name) {
    switch (name) {
      case 'gita':
        _book(c, const Color(0xFF3D3FA3), emblem: _eConch);
      case 'ved':
        _book(c, const Color(0xFFE09A12), emblem: _eOm, trim: true);
      case 'ramayan':
        _book(c, const Color(0xFF557A1C), emblem: _eBow);
      case 'mahabharat':
        _book(c, const Color(0xFF9A2318), emblem: _eChariotWheel, trim: true);
      case 'puran':
        _book(c, const Color(0xFFD6457A), emblem: _eLotus);
      case 'upanishad':
        _book(c, const Color(0xFF33475B), emblem: _eDiya);
      case 'bhagwat':
        _book(c, const Color(0xFF1B8CC4), emblem: _eFluteFeather);
      case 'shiv':
        _book(c, const Color(0xFF586579), emblem: _eTrishul);
      case 'devi':
        _book(c, const Color(0xFFB3164C), emblem: _eYantra, trim: true);
      case 'hanuman':
        _book(c, const Color(0xFFE55A1B), emblem: _eGada);
      case 'satsang':
        _book(c, const Color(0xFF128A70), emblem: _ePeople);
      case 'bhajan':
        _book(c, const Color(0xFFC23F9C), emblem: _eNotes);
      case 'aarti':
        _book(c, const Color(0xFFB4621C), emblem: _eThali);
      case 'mala':
        _book(c, const Color(0xFF5A3A2E), emblem: _eMala);
      case 'kalash':
        _book(c, const Color(0xFF2E7D3A), emblem: _eKalash);
      case 'mandir':
        _book(c, const Color(0xFF8A2346), emblem: _eTemple);
      case 'sant-vani':
        _book(c, const Color(0xFF4A5DA6), emblem: _eSpeech);
      case 'gyan':
        _book(c, const Color(0xFF1F2A80), emblem: _eSun);
      case 'amritvani':
        _book(c, const Color(0xFF0A8C8C), emblem: _eDrop);
      case 'sakhi':
        _book(c, const Color(0xFF2E2B2B), emblem: _eQuill);
      default:
        return false;
    }
    return true;
  }

  // ---- emblems (inside x 0.34..0.72, y 0.29..0.72) -----------------------------------

  /// गीता — the शंख (conch) of Krishna.
  void _eConch(Canvas c, Color color) {
    c.save();
    c.translate(_o.dx, _o.dy + 0.01);
    c.rotate(-0.55);
    final body = Path()
      ..moveTo(0, 0.2)
      ..cubicTo(0.06, 0.13, 0.12, 0.02, 0.1, -0.06)
      ..quadraticBezierTo(0.085, -0.13, 0.03, -0.15)
      ..lineTo(0, -0.215)
      ..lineTo(-0.03, -0.15)
      ..quadraticBezierTo(-0.085, -0.13, -0.1, -0.06)
      ..cubicTo(-0.12, 0.02, -0.06, 0.13, 0, 0.2)
      ..close();
    c.drawPath(body, _fill(_cream));
    // the open lip, on one side
    final lip = Path()
      ..moveTo(0.02, 0.17)
      ..quadraticBezierTo(0.15, 0.06, 0.12, -0.07)
      ..quadraticBezierTo(0.06, 0.04, 0.02, 0.17)
      ..close();
    c.drawPath(lip, _fill(const Color(0xFFF7C9A8)));
    final band = _line(const Color(0xFFD9A07A), 0.014);
    for (final y in [-0.1, -0.035, 0.03]) {
      c.drawPath(
        Path()
          ..moveTo(-0.095 + (y + 0.1) * 0.12, y)
          ..quadraticBezierTo(0, y + 0.04, 0.095 - (y + 0.1) * 0.12, y),
        band,
      );
    }
    c.restore();
    c.drawCircle(const Offset(0.53, 0.73), 0.016, _fill(_gold));
  }

  /// वेद — ॐ on a turmeric cover.
  void _eOm(Canvas c, Color color) {
    final p = _omPath ??= ReligionSymbolPainter.parse(kPathOm);
    const ext = 0.3;
    c.save();
    c.translate(_o.dx - ext / 2, _o.dy - ext / 2 - 0.01);
    c.scale(ext / 1000);
    c.drawPath(p, _fill(const Color(0xFF7A230F)));
    c.restore();
    c.drawLine(
      const Offset(0.43, 0.7),
      const Offset(0.63, 0.7),
      _line(const Color(0xFF7A230F), 0.014),
    );
  }

  /// रामायण — धनुष-बाण (a drawn bow and arrow).
  void _eBow(Canvas c, Color color) {
    const top = Offset(0.47, 0.29);
    const bot = Offset(0.47, 0.69);
    const nock = Offset(0.4, 0.49);
    // string pulled back
    final s = _line(Colors.white.withValues(alpha: 0.9), 0.009);
    c.drawLine(top, nock, s);
    c.drawLine(nock, bot, s);
    // bow
    c.drawPath(
      Path()
        ..moveTo(top.dx, top.dy)
        ..quadraticBezierTo(0.74, 0.49, bot.dx, bot.dy),
      _line(_goldLight, 0.03),
    );
    c.drawCircle(top, 0.016, _fill(_gold));
    c.drawCircle(bot, 0.016, _fill(_gold));
    // arrow
    c.drawLine(nock, const Offset(0.7, 0.49), _line(Colors.white, 0.015));
    c.drawPath(
      Path()
        ..moveTo(0.745, 0.49)
        ..lineTo(0.685, 0.455)
        ..lineTo(0.695, 0.49)
        ..lineTo(0.685, 0.525)
        ..close(),
      _fill(Colors.white),
    );
    final f = _line(_goldLight, 0.012);
    for (final dx in [0.0, 0.03]) {
      c.drawLine(Offset(0.41 + dx, 0.49), Offset(0.39 + dx, 0.455), f);
      c.drawLine(Offset(0.41 + dx, 0.49), Offset(0.39 + dx, 0.525), f);
    }
  }

  /// महाभारत — the रथ-चक्र (chariot wheel), heavy rim and twelve spokes.
  void _eChariotWheel(Canvas c, Color color) {
    const o = Offset(0.53, 0.48);
    c.drawCircle(o, 0.15, _line(_goldLight, 0.034));
    c.drawCircle(o, 0.15, _line(_goldDark, 0.008));
    for (var i = 0; i < 12; i++) {
      final a = i * math.pi / 6;
      final d = Offset(math.cos(a), math.sin(a));
      c.drawLine(o + d * 0.045, o + d * 0.135, _line(_goldLight, 0.013));
      c.drawCircle(o + d * 0.15, 0.011, _fill(_goldDark));
    }
    c.drawCircle(o, 0.05, _fill(_goldLight));
    c.drawCircle(o, 0.022, _fill(_goldDark));
  }

  /// पुराण — the lotus (कमल).
  void _eLotus(Canvas c, Color color) {
    const light = Color(0xFFFFF0F5);
    const mid = Color(0xFFFFC7DA);
    Path petal(double len, double w) => Path()
      ..moveTo(0, 0)
      ..quadraticBezierTo(w, -len * 0.55, 0, -len)
      ..quadraticBezierTo(-w, -len * 0.55, 0, 0)
      ..close();
    const base = Offset(0.53, 0.62);
    for (final (a, len, w, col) in [
      (-1.25, 0.15, 0.06, mid),
      (1.25, 0.15, 0.06, mid),
      (-0.62, 0.21, 0.07, light),
      (0.62, 0.21, 0.07, light),
      (0.0, 0.27, 0.085, Colors.white),
    ]) {
      c.save();
      c.translate(base.dx, base.dy);
      c.rotate(a);
      c.drawPath(petal(len, w), _fill(col));
      c.drawLine(
        Offset(0, -len * 0.15),
        Offset(0, -len * 0.75),
        _line(_shade(color, 0.12).withValues(alpha: 0.6), 0.008),
      );
      c.restore();
    }
    c.drawPath(
      Path()
        ..moveTo(0.38, 0.69)
        ..quadraticBezierTo(0.455, 0.655, 0.53, 0.69)
        ..quadraticBezierTo(0.605, 0.725, 0.68, 0.69),
      _line(_goldLight, 0.016),
    );
  }

  /// उपनिषद — the दीया of knowledge (तमसो मा ज्योतिर्गमय).
  void _eDiya(Canvas c, Color color) {
    // halo
    c.drawCircle(
      const Offset(0.53, 0.43),
      0.115,
      _fill(_goldLight.withValues(alpha: 0.18)),
    );
    // flame
    final flame = Path()
      ..moveTo(0.53, 0.29)
      ..cubicTo(0.6, 0.38, 0.6, 0.47, 0.53, 0.5)
      ..cubicTo(0.46, 0.47, 0.46, 0.38, 0.53, 0.29)
      ..close();
    c.drawPath(flame, _fill(const Color(0xFFFFB534)));
    final inner = Path()
      ..moveTo(0.53, 0.36)
      ..cubicTo(0.565, 0.42, 0.565, 0.47, 0.53, 0.49)
      ..cubicTo(0.495, 0.47, 0.495, 0.42, 0.53, 0.36)
      ..close();
    c.drawPath(inner, _fill(const Color(0xFFFFF2B0)));
    // lamp bowl
    final bowl = Path()
      ..moveTo(0.37, 0.53)
      ..lineTo(0.69, 0.53)
      ..quadraticBezierTo(0.68, 0.65, 0.53, 0.66)
      ..quadraticBezierTo(0.38, 0.65, 0.37, 0.53)
      ..close();
    c.drawPath(bowl, _fill(_gold));
    c.drawPath(
      Path()
        ..moveTo(0.69, 0.53)
        ..quadraticBezierTo(0.74, 0.51, 0.75, 0.48)
        ..quadraticBezierTo(0.72, 0.55, 0.67, 0.57),
      _fill(_gold),
    );
    c.drawLine(
      const Offset(0.37, 0.53),
      const Offset(0.69, 0.53),
      _line(_goldLight, 0.014),
    );
    c.drawRRect(
      RRect.fromRectAndRadius(
        const Rect.fromLTWH(0.47, 0.66, 0.12, 0.035),
        const Radius.circular(0.012),
      ),
      _fill(_goldDark),
    );
  }

  /// भागवत — बाँसुरी and मोरपंख (flute and peacock feather).
  void _eFluteFeather(Canvas c, Color color) {
    // feather
    c.save();
    c.translate(0.565, 0.455);
    c.rotate(0.5);
    c.scale(1.25);
    c.drawLine(
      const Offset(0, 0.22),
      const Offset(0, -0.12),
      _line(const Color(0xFFE8F5D0), 0.01),
    );
    final vane = Path()
      ..moveTo(0, 0.12)
      ..cubicTo(0.1, 0.02, 0.09, -0.16, 0, -0.2)
      ..cubicTo(-0.09, -0.16, -0.1, 0.02, 0, 0.12)
      ..close();
    c.drawPath(vane, _fill(const Color(0xFF3FB55A)));
    final barbs = _line(const Color(0xFF9BE07E), 0.006);
    for (var i = 0; i < 5; i++) {
      final y = 0.08 - i * 0.05;
      c.drawLine(Offset(0, y), Offset(0.065, y - 0.04), barbs);
      c.drawLine(Offset(0, y), Offset(-0.065, y - 0.04), barbs);
    }
    c.drawOval(
      Rect.fromCenter(
        center: const Offset(0, -0.07),
        width: 0.11,
        height: 0.13,
      ),
      _fill(const Color(0xFFE8C547)),
    );
    c.drawOval(
      Rect.fromCenter(
        center: const Offset(0, -0.065),
        width: 0.08,
        height: 0.095,
      ),
      _fill(const Color(0xFF1A9E9A)),
    );
    c.drawOval(
      Rect.fromCenter(
        center: const Offset(0, -0.06),
        width: 0.045,
        height: 0.055,
      ),
      _fill(const Color(0xFF15306E)),
    );
    c.restore();
    // flute across
    c.save();
    c.translate(0.53, 0.53);
    c.rotate(-0.62);
    final flute = RRect.fromRectAndRadius(
      Rect.fromCenter(center: Offset.zero, width: 0.38, height: 0.04),
      const Radius.circular(0.02),
    );
    c.drawRRect(flute, _fill(const Color(0xFFE9B949)));
    c.drawRRect(flute, _line(_goldDark, 0.006));
    for (final x in [-0.155, 0.13]) {
      c.drawLine(
        Offset(x, -0.02),
        Offset(x, 0.02),
        _line(const Color(0xFFB0281E), 0.012),
      );
    }
    for (var i = 0; i < 5; i++) {
      c.drawCircle(
        Offset(-0.07 + i * 0.04, 0),
        0.008,
        _fill(const Color(0xFF6E4410)),
      );
    }
    c.restore();
  }

  /// शिव — त्रिशूल with a डमरू.
  void _eTrishul(Canvas c, Color color) {
    final w = _line(Colors.white, 0.022);
    c.drawLine(const Offset(0.53, 0.38), const Offset(0.53, 0.73), w);
    // prongs
    c.drawPath(
      Path()
        ..moveTo(0.53, 0.27)
        ..lineTo(0.555, 0.33)
        ..lineTo(0.53, 0.42)
        ..lineTo(0.505, 0.33)
        ..close(),
      _fill(Colors.white),
    );
    final side = _line(Colors.white, 0.02);
    c.drawPath(
      Path()
        ..moveTo(0.53, 0.43)
        ..quadraticBezierTo(0.42, 0.43, 0.42, 0.3),
      side,
    );
    c.drawPath(
      Path()
        ..moveTo(0.53, 0.43)
        ..quadraticBezierTo(0.64, 0.43, 0.64, 0.3),
      side,
    );
    for (final x in [0.42, 0.64]) {
      c.drawPath(
        Path()
          ..moveTo(x, 0.27)
          ..lineTo(x + 0.02, 0.315)
          ..lineTo(x - 0.02, 0.315)
          ..close(),
        _fill(Colors.white),
      );
    }
    // damru tied on the shaft
    final d = Path()
      ..moveTo(0.46, 0.5)
      ..lineTo(0.6, 0.5)
      ..lineTo(0.545, 0.56)
      ..lineTo(0.6, 0.62)
      ..lineTo(0.46, 0.62)
      ..lineTo(0.515, 0.56)
      ..close();
    c.drawPath(d, _fill(_gold));
    c.drawLine(
      const Offset(0.46, 0.5),
      const Offset(0.6, 0.5),
      _line(_goldLight, 0.012),
    );
    c.drawLine(
      const Offset(0.46, 0.62),
      const Offset(0.6, 0.62),
      _line(_goldLight, 0.012),
    );
    c.drawPath(
      Path()
        ..moveTo(0.545, 0.56)
        ..quadraticBezierTo(0.62, 0.58, 0.64, 0.64),
      _line(Colors.white.withValues(alpha: 0.8), 0.007),
    );
    c.drawCircle(const Offset(0.643, 0.648), 0.012, _fill(Colors.white));
  }

  /// देवी — श्री यंत्र (interlaced triangles in a lotus ring, with the बिंदु).
  void _eYantra(Canvas c, Color color) {
    const o = Offset(0.53, 0.49);
    final g = _line(_goldLight, 0.014);
    c.drawCircle(o, 0.165, g);
    for (var i = 0; i < 8; i++) {
      final a = i * math.pi / 4 + math.pi / 8;
      c.drawCircle(
        o + Offset(math.cos(a), math.sin(a)) * 0.165,
        0.018,
        _fill(_goldLight),
      );
    }
    Path tri(double r, bool up, double dy) {
      final s = up ? -1.0 : 1.0;
      return Path()
        ..moveTo(o.dx, o.dy + dy + s * r)
        ..lineTo(o.dx + r * 0.866, o.dy + dy - s * r * 0.5)
        ..lineTo(o.dx - r * 0.866, o.dy + dy - s * r * 0.5)
        ..close();
    }

    final t = _line(Colors.white, 0.011);
    c.drawPath(tri(0.125, true, 0.0), t);
    c.drawPath(tri(0.125, false, 0.0), t);
    c.drawPath(tri(0.075, true, 0.012), t);
    c.drawPath(tri(0.075, false, -0.012), t);
    c.drawCircle(o, 0.018, _fill(_goldLight));
  }

  /// हनुमान — गदा (the mace).
  void _eGada(Canvas c, Color color) {
    c.save();
    c.translate(0.53, 0.5);
    c.rotate(0.62);
    // handle
    c.drawRRect(
      RRect.fromRectAndRadius(
        Rect.fromLTWH(-0.017, -0.02, 0.034, 0.23),
        const Radius.circular(0.017),
      ),
      _fill(_gold),
    );
    c.drawCircle(const Offset(0, 0.215), 0.026, _fill(_goldLight));
    for (final y in [0.05, 0.12]) {
      c.drawLine(Offset(-0.022, y), Offset(0.022, y), _line(_goldDark, 0.012));
    }
    // head
    const h = Offset(0, -0.1);
    c.drawCircle(h, 0.11, _fill(_goldLight));
    c.drawOval(
      Rect.fromCenter(center: h, width: 0.22, height: 0.06),
      _line(_goldDark, 0.012),
    );
    c.drawOval(
      Rect.fromCenter(center: h, width: 0.12, height: 0.22),
      _line(_goldDark, 0.012),
    );
    c.drawCircle(h, 0.11, _line(_goldDark, 0.01));
    c.drawCircle(const Offset(0, -0.225), 0.022, _fill(_goldLight));
    c.drawCircle(
      const Offset(-0.035, -0.135),
      0.022,
      _fill(Colors.white.withValues(alpha: 0.45)),
    );
    c.restore();
  }

  /// सत्संग — three seekers sitting together.
  void _ePeople(Canvas c, Color color) {
    void person(Offset head, double r, Color col) {
      c.drawCircle(head, r, _fill(col));
      c.drawPath(
        Path()
          ..moveTo(head.dx - r * 2.0, head.dy + r * 3.6)
          ..quadraticBezierTo(
            head.dx - r * 2.0,
            head.dy + r * 1.5,
            head.dx,
            head.dy + r * 1.5,
          )
          ..quadraticBezierTo(
            head.dx + r * 2.0,
            head.dy + r * 1.5,
            head.dx + r * 2.0,
            head.dy + r * 3.6,
          )
          ..close(),
        _fill(col),
      );
    }

    final side = Colors.white.withValues(alpha: 0.72);
    person(const Offset(0.42, 0.44), 0.042, side);
    person(const Offset(0.64, 0.44), 0.042, side);
    // a thin outline in the cover colour keeps the front figure apart from the others
    c.drawCircle(const Offset(0.53, 0.39), 0.052 + 0.014, _fill(color));
    c.drawPath(
      Path()
        ..moveTo(0.53 - 0.104 - 0.014, 0.39 + 0.187)
        ..quadraticBezierTo(
          0.53 - 0.104 - 0.014,
          0.39 + 0.068 - 0.014,
          0.53,
          0.39 + 0.068 - 0.014,
        )
        ..quadraticBezierTo(
          0.53 + 0.104 + 0.014,
          0.39 + 0.068 - 0.014,
          0.53 + 0.104 + 0.014,
          0.39 + 0.187,
        )
        ..close(),
      _fill(color),
    );
    person(const Offset(0.53, 0.39), 0.052, Colors.white);
    c.drawPath(
      Path()
        ..moveTo(0.36, 0.66)
        ..quadraticBezierTo(0.53, 0.72, 0.7, 0.66),
      _line(_goldLight, 0.016),
    );
    c.drawCircle(const Offset(0.53, 0.31), 0.013, _fill(_goldLight));
  }

  /// भजन — music notes (and a pair of मंजीरा).
  void _eNotes(Canvas c, Color color) {
    final w = _fill(Colors.white);
    // beamed pair
    c.drawLine(
      const Offset(0.47, 0.6),
      const Offset(0.47, 0.34),
      _line(Colors.white, 0.02),
    );
    c.drawLine(
      const Offset(0.65, 0.56),
      const Offset(0.65, 0.3),
      _line(Colors.white, 0.02),
    );
    c.drawPath(
      Path()
        ..moveTo(0.46, 0.33)
        ..lineTo(0.66, 0.29)
        ..lineTo(0.66, 0.345)
        ..lineTo(0.46, 0.385)
        ..close(),
      w,
    );
    for (final p in [const Offset(0.43, 0.61), const Offset(0.61, 0.57)]) {
      c.save();
      c.translate(p.dx, p.dy);
      c.rotate(-0.4);
      c.drawOval(
        Rect.fromCenter(center: Offset.zero, width: 0.095, height: 0.068),
        w,
      );
      c.restore();
    }
    c.drawCircle(const Offset(0.53, 0.71), 0.018, _fill(_gold));
  }

  /// आरती — the आरती थाली with its flame.
  void _eThali(Canvas c, Color color) {
    // plate
    c.drawOval(
      Rect.fromCenter(
        center: const Offset(0.53, 0.6),
        width: 0.36,
        height: 0.12,
      ),
      _fill(_goldLight),
    );
    c.drawOval(
      Rect.fromCenter(
        center: const Offset(0.53, 0.595),
        width: 0.29,
        height: 0.08,
      ),
      _fill(_gold),
    );
    // little diyas
    for (final x in [0.43, 0.63]) {
      c.drawPath(
        Path()
          ..moveTo(x - 0.035, 0.575)
          ..lineTo(x + 0.035, 0.575)
          ..quadraticBezierTo(x + 0.03, 0.605, x, 0.607)
          ..quadraticBezierTo(x - 0.03, 0.605, x - 0.035, 0.575)
          ..close(),
        _fill(_goldDark),
      );
      _flame(c, Offset(x, 0.572), 0.065);
    }
    // central lamp
    c.drawPath(
      Path()
        ..moveTo(0.48, 0.575)
        ..lineTo(0.58, 0.575)
        ..lineTo(0.56, 0.53)
        ..lineTo(0.5, 0.53)
        ..close(),
      _fill(_goldDark),
    );
    c.drawOval(
      Rect.fromCenter(
        center: const Offset(0.53, 0.525),
        width: 0.12,
        height: 0.03,
      ),
      _fill(_goldLight),
    );
    _flame(c, const Offset(0.53, 0.515), 0.2);
    // swastik dots under the plate
    for (final dx in [-0.04, 0.0, 0.04]) {
      c.drawCircle(Offset(0.53 + dx, 0.705), 0.011, _fill(_goldLight));
    }
  }

  void _flame(Canvas c, Offset base, double h) {
    final w = h * 0.36;
    final f = Path()
      ..moveTo(base.dx, base.dy - h)
      ..cubicTo(
        base.dx + w * 1.2,
        base.dy - h * 0.55,
        base.dx + w,
        base.dy,
        base.dx,
        base.dy,
      )
      ..cubicTo(
        base.dx - w,
        base.dy,
        base.dx - w * 1.2,
        base.dy - h * 0.55,
        base.dx,
        base.dy - h,
      )
      ..close();
    c.drawPath(f, _fill(const Color(0xFFFFB534)));
    final ih = h * 0.6;
    final iw = w * 0.5;
    c.drawPath(
      Path()
        ..moveTo(base.dx, base.dy - ih)
        ..cubicTo(
          base.dx + iw * 1.2,
          base.dy - ih * 0.5,
          base.dx + iw,
          base.dy,
          base.dx,
          base.dy,
        )
        ..cubicTo(
          base.dx - iw,
          base.dy,
          base.dx - iw * 1.2,
          base.dy - ih * 0.5,
          base.dx,
          base.dy - ih,
        )
        ..close(),
      _fill(const Color(0xFFFFF2B0)),
    );
  }

  /// माला — a जप माला of rudraksha beads with its सुमेरु and tassel.
  void _eMala(Canvas c, Color color) {
    const o = Offset(0.53, 0.45);
    const n = 18;
    for (var i = 0; i < n; i++) {
      final a = math.pi / 2 + (i + 0.5) * 2 * math.pi / n;
      final p = o + Offset(math.cos(a) * 0.14, math.sin(a) * 0.15);
      c.drawCircle(p, 0.022, _fill(const Color(0xFFD08A4A)));
      c.drawCircle(
        p + const Offset(-0.006, -0.006),
        0.007,
        _fill(const Color(0xFFF2C08A)),
      );
    }
    // sumeru bead + tassel
    const s = Offset(0.53, 0.615);
    c.drawCircle(s, 0.028, _fill(_goldLight));
    final tassel = Path()
      ..moveTo(0.515, 0.64)
      ..lineTo(0.545, 0.64)
      ..lineTo(0.575, 0.745)
      ..lineTo(0.485, 0.745)
      ..close();
    c.drawPath(tassel, _fill(const Color(0xFFE8433A)));
    for (final x in [0.505, 0.53, 0.555]) {
      c.drawLine(
        Offset(x, 0.665),
        Offset(x + (x - 0.53) * 0.6, 0.74),
        _line(const Color(0xFFB02A22), 0.005),
      );
    }
  }

  /// कलश — the मंगल कलश with mango leaves and a coconut.
  void _eKalash(Canvas c, Color color) {
    // leaves
    final leaf = _fill(const Color(0xFF9BE07E));
    for (final a in [-1.0, -0.45, 0.45, 1.0]) {
      c.save();
      c.translate(0.53, 0.42);
      c.rotate(a);
      c.drawPath(
        Path()
          ..moveTo(0, 0)
          ..quadraticBezierTo(0.035, -0.07, 0, -0.14)
          ..quadraticBezierTo(-0.035, -0.07, 0, 0)
          ..close(),
        leaf,
      );
      c.restore();
    }
    // coconut
    c.drawOval(
      Rect.fromCenter(
        center: const Offset(0.53, 0.345),
        width: 0.1,
        height: 0.12,
      ),
      _fill(const Color(0xFFA9692E)),
    );
    c.drawPath(
      Path()
        ..moveTo(0.53, 0.285)
        ..quadraticBezierTo(0.545, 0.25, 0.53, 0.235),
      _line(const Color(0xFFA9692E), 0.014),
    );
    // pot
    final pot = Path()
      ..moveTo(0.47, 0.42)
      ..lineTo(0.59, 0.42)
      ..lineTo(0.58, 0.46)
      ..cubicTo(0.7, 0.49, 0.7, 0.66, 0.6, 0.69)
      ..lineTo(0.46, 0.69)
      ..cubicTo(0.36, 0.66, 0.36, 0.49, 0.48, 0.46)
      ..close();
    c.drawPath(pot, _fill(_gold));
    c.drawRRect(
      RRect.fromRectAndRadius(
        const Rect.fromLTWH(0.455, 0.41, 0.15, 0.03),
        const Radius.circular(0.012),
      ),
      _fill(_goldLight),
    );
    // swastik-red band
    c.drawPath(
      Path()
        ..moveTo(0.405, 0.56)
        ..quadraticBezierTo(0.53, 0.6, 0.655, 0.56),
      _line(const Color(0xFFD7262E), 0.014),
    );
    c.drawCircle(
      const Offset(0.53, 0.53),
      0.016,
      _fill(const Color(0xFFD7262E)),
    );
    c.drawRRect(
      RRect.fromRectAndRadius(
        const Rect.fromLTWH(0.47, 0.685, 0.12, 0.03),
        const Radius.circular(0.012),
      ),
      _fill(_goldDark),
    );
  }

  /// मंदिर — a temple शिखर with its कलश and ध्वज.
  void _eTemple(Canvas c, Color color) {
    final w = _fill(_cream);
    // flag
    c.drawLine(
      const Offset(0.53, 0.33),
      const Offset(0.53, 0.235),
      _line(_cream, 0.01),
    );
    c.drawPath(
      Path()
        ..moveTo(0.535, 0.235)
        ..lineTo(0.62, 0.255)
        ..lineTo(0.535, 0.285)
        ..close(),
      _fill(const Color(0xFFFF9F2E)),
    );
    // shikhar
    final shikhar = Path()
      ..moveTo(0.53, 0.33)
      ..cubicTo(0.6, 0.38, 0.63, 0.47, 0.63, 0.54)
      ..lineTo(0.43, 0.54)
      ..cubicTo(0.43, 0.47, 0.46, 0.38, 0.53, 0.33)
      ..close();
    c.drawPath(shikhar, w);
    final band = _line(_shade(color, 0.05).withValues(alpha: 0.55), 0.008);
    for (final y in [0.42, 0.48]) {
      c.drawLine(
        Offset(0.53 - (y - 0.3) * 0.38, y),
        Offset(0.53 + (y - 0.3) * 0.38, y),
        band,
      );
    }
    c.drawCircle(const Offset(0.53, 0.33), 0.018, _fill(_goldLight));
    // mandap + steps
    c.drawRect(const Rect.fromLTWH(0.4, 0.54, 0.26, 0.13), w);
    final door = Path()
      ..moveTo(0.505, 0.67)
      ..lineTo(0.505, 0.6)
      ..quadraticBezierTo(0.53, 0.565, 0.555, 0.6)
      ..lineTo(0.555, 0.67)
      ..close();
    c.drawPath(door, _fill(_shade(color, -0.08)));
    c.drawRect(
      const Rect.fromLTWH(0.375, 0.54, 0.31, 0.022),
      _fill(_goldLight),
    );
    c.drawRect(const Rect.fromLTWH(0.36, 0.67, 0.34, 0.03), _fill(_goldLight));
  }

  /// संत वाणी — a speech bubble with the lines of the वाणी.
  void _eSpeech(Canvas c, Color color) {
    final b = Path()
      ..addRRect(
        RRect.fromRectAndRadius(
          const Rect.fromLTWH(0.37, 0.32, 0.33, 0.25),
          const Radius.circular(0.07),
        ),
      )
      ..moveTo(0.43, 0.55)
      ..lineTo(0.41, 0.66)
      ..lineTo(0.5, 0.56)
      ..close();
    c.drawPath(b, _fill(Colors.white));
    final l = _line(color, 0.02);
    c.drawLine(const Offset(0.43, 0.4), const Offset(0.64, 0.4), l);
    c.drawLine(const Offset(0.43, 0.45), const Offset(0.6, 0.45), l);
    c.drawLine(const Offset(0.43, 0.5), const Offset(0.54, 0.5), l);
    c.drawCircle(const Offset(0.64, 0.68), 0.018, _fill(_goldLight));
    c.drawCircle(const Offset(0.585, 0.68), 0.012, _fill(_goldLight));
  }

  /// ज्ञान — the rising sun of knowledge.
  void _eSun(Canvas c, Color color) {
    const o = Offset(0.53, 0.48);
    for (var i = 0; i < 12; i++) {
      final a = i * math.pi / 6;
      final d = Offset(math.cos(a), math.sin(a));
      final n = Offset(-d.dy, d.dx);
      c.drawPath(
        Path()
          ..moveTo((o + d * 0.175).dx, (o + d * 0.175).dy)
          ..lineTo((o + d * 0.1 + n * 0.03).dx, (o + d * 0.1 + n * 0.03).dy)
          ..lineTo((o + d * 0.1 - n * 0.03).dx, (o + d * 0.1 - n * 0.03).dy)
          ..close(),
        _fill(i.isEven ? _goldLight : _gold),
      );
    }
    c.drawCircle(
      o,
      0.095,
      Paint()
        ..shader = const RadialGradient(
          colors: [Color(0xFFFFF0B0), Color(0xFFFFC234)],
        ).createShader(Rect.fromCircle(center: o, radius: 0.095)),
    );
  }

  /// अमृतवाणी — the drop of nectar.
  void _eDrop(Canvas c, Color color) {
    final drop = Path()
      ..moveTo(0.53, 0.28)
      ..cubicTo(0.6, 0.38, 0.65, 0.45, 0.65, 0.52)
      ..cubicTo(0.65, 0.59, 0.6, 0.64, 0.53, 0.64)
      ..cubicTo(0.46, 0.64, 0.41, 0.59, 0.41, 0.52)
      ..cubicTo(0.41, 0.45, 0.46, 0.38, 0.53, 0.28)
      ..close();
    c.drawPath(
      drop,
      Paint()
        ..shader = const LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [Colors.white, Color(0xFFBFF2EE)],
        ).createShader(const Rect.fromLTWH(0.41, 0.28, 0.24, 0.36)),
    );
    c.drawPath(
      Path()
        ..moveTo(0.46, 0.5)
        ..quadraticBezierTo(0.46, 0.57, 0.51, 0.595),
      _line(color.withValues(alpha: 0.45), 0.016),
    );
    c.drawPath(
      Path()
        ..moveTo(0.4, 0.705)
        ..quadraticBezierTo(0.53, 0.665, 0.66, 0.705),
      _line(_goldLight, 0.014),
    );
  }

  /// साखी — the poet's कलम (quill) and ink pot.
  void _eQuill(Canvas c, Color color) {
    // ink pot
    c.drawRRect(
      RRect.fromRectAndRadius(
        const Rect.fromLTWH(0.38, 0.6, 0.13, 0.1),
        const Radius.circular(0.025),
      ),
      _fill(_gold),
    );
    c.drawRect(const Rect.fromLTWH(0.405, 0.575, 0.08, 0.03), _fill(_goldDark));
    // quill
    c.save();
    c.translate(0.57, 0.45);
    c.rotate(0.6);
    final vane = Path()
      ..moveTo(0, 0.2)
      ..cubicTo(0.09, 0.05, 0.08, -0.12, 0.02, -0.21)
      ..cubicTo(-0.05, -0.12, -0.07, 0.05, 0, 0.2)
      ..close();
    c.drawPath(vane, _fill(_cream));
    c.drawPath(
      Path()
        ..moveTo(0, 0.27)
        ..quadraticBezierTo(0.01, 0.0, 0.02, -0.2),
      _line(const Color(0xFFB9A27A), 0.009),
    );
    final barb = _line(const Color(0xFFD9C9A6), 0.005);
    for (var i = 0; i < 5; i++) {
      final y = 0.12 - i * 0.065;
      c.drawLine(Offset(0.008, y), Offset(0.05, y - 0.04), barb);
    }
    c.restore();
  }
}

Path? _omPath;
