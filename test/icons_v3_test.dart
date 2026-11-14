// Icon pack v3 (user app copy of the admin test): API compatibility, fallback, palettes, shimmer rules, classic mode, cache.
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:granthprabandhan/widgets/common.dart' show Tone;
import 'package:granthprabandhan/widgets/group_icon.dart';
import 'package:granthprabandhan/widgets/icon_v3_style.dart';
import 'package:granthprabandhan/widgets/religion_symbol.dart';

Future<Uint8List> _raster(CustomPainter p, {double px = 48}) async {
  final rec = ui.PictureRecorder();
  p.paint(Canvas(rec), Size.square(px));
  final img = await rec.endRecording().toImage(px.toInt(), px.toInt());
  final data = await img.toByteData(format: ui.ImageByteFormat.rawRgba);
  return data!.buffer.asUint8List();
}

ReligionTilePainter _rel(
  String k, {
  Tone tone = Tone.maroon,
  bool dark = false,
}) => ReligionTilePainter(k, palette: religionPaletteV3(k, tone), dark: dark);

final _folderKeys = [...groupIconNames, ...newGroupIconNames];
final _religionKeys = [...religionSymbolNames, ...newReligionSymbolNames];

Widget _app(Widget child, {bool disableAnimations = false}) => MaterialApp(
  home: MediaQuery(
    data: MediaQueryData(disableAnimations: disableAnimations),
    child: Scaffold(body: Center(child: child)),
  ),
);

void main() {
  tearDown(() {
    GranthIconStyle.premium = true;
    GranthIconStyle.shimmerEnabled = true;
    GranthIconStyle.religionUsesTone = false;
  });

  test('the catalogue is 38 folder + 18 religion keys (26 old + 30 new)', () {
    expect(_folderKeys.length, 38);
    expect(_religionKeys.length, 18);
    expect(groupIconNames.length + religionSymbolNames.length, 26);
    expect(newGroupIconNames.length + newReligionSymbolNames.length, 30);
  });

  test('every folder key has a v3 hue, every religion key a v3 palette', () {
    for (final k in _folderKeys) {
      expect(kFolderHueV3.containsKey(k), isTrue, reason: k);
    }
    for (final k in _religionKeys.where((k) => k != 'misc')) {
      expect(kReligionPaletteV3.containsKey(k), isTrue, reason: k);
    }
  });

  testWidgets('old constructors keep working (same APIs)', (t) async {
    await t.pumpWidget(
      _app(
        const Wrap(
          children: [
            GroupIcon('book-red'),
            GroupIcon('gita', size: 24),
            ReligionSymbol('om'),
            ReligionSymbol('kamal', tone: Tone.gold, size: 32),
            CustomPaint(painter: GroupIconPainter('scroll')),
            CustomPaint(painter: ReligionSymbolPainter('om', Colors.white)),
          ],
        ),
      ),
    );
    expect(t.takeException(), isNull);
    expect(t.getSize(find.byType(GroupIcon).first), const Size(56, 56));
    expect(t.getSize(find.byType(ReligionSymbol).first), const Size(72, 72));
    expect(t.getSize(find.byType(GroupIcon).last), const Size(24, 24));
  });

  test(
    'all 56 keys paint in light and dark, each unlike the fallback',
    () async {
      final miscG = await _raster(const GroupIconPainter('misc'));
      for (final dark in [false, true]) {
        for (final k in _folderKeys.where((k) => k != 'misc')) {
          final px = await _raster(GroupIconPainter(k, dark: dark));
          final ref = dark
              ? await _raster(const GroupIconPainter('misc', dark: true))
              : miscG;
          expect(px, isNot(equals(ref)), reason: 'folder $k dark=$dark');
        }
        final miscR = await _raster(_rel('misc', dark: dark));
        for (final k in _religionKeys.where((k) => k != 'misc')) {
          expect(
            await _raster(_rel(k, dark: dark)),
            isNot(equals(miscR)),
            reason: 'religion $k dark=$dark',
          );
        }
      }
    },
  );

  test('unknown keys fall back to misc, as before', () async {
    expect(
      await _raster(const GroupIconPainter('no-such-key')),
      equals(await _raster(const GroupIconPainter('misc'))),
    );
    expect(
      await _raster(_rel('no-such-key')),
      equals(await _raster(_rel('misc'))),
    );
    // legacy alias
    expect(await _raster(_rel('ektara')), equals(await _raster(_rel('kabir'))));
  });

  test('religion: own colour per key; misc/unknown follow the tone', () {
    expect(religionPaletteV3('om', Tone.gold), kReligionPaletteV3['om']);
    expect(
      religionPaletteV3('crescent', Tone.saffron).bottom,
      kReligionPaletteV3['crescent']!.bottom,
    );
    expect(
      religionPaletteV3('misc', Tone.gold),
      isNot(religionPaletteV3('misc', Tone.maroon)),
    );
    expect(
      religionPaletteV3('xyz', Tone.gold),
      religionPaletteV3('misc', Tone.gold),
    );
    GranthIconStyle.religionUsesTone = true;
    expect(
      religionPaletteV3('om', Tone.gold),
      religionPaletteV3('misc', Tone.gold),
    );
  });

  test('dark theme paints differently (deeper shadow + rim)', () async {
    expect(
      await _raster(const GroupIconPainter('book-red', dark: true)),
      isNot(equals(await _raster(const GroupIconPainter('book-red')))),
    );
  });

  test('icons are recorded once and replayed from the cache', () async {
    IconV3Cache.clear();
    await _raster(const GroupIconPainter('gita'));
    await _raster(_rel('om'));
    final n = IconV3Cache.length;
    for (var i = 0; i < 5; i++) {
      await _raster(const GroupIconPainter('gita'), px: 24 + i * 8);
      await _raster(_rel('om'), px: 24 + i * 8);
    }
    expect(IconV3Cache.length, n, reason: 'size must not create new entries');
  });

  testWidgets('shimmer is off by default: no ticker, no extra layer', (
    t,
  ) async {
    await t.pumpWidget(
      _app(
        const Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            GroupIcon('gita', size: 40),
            ReligionSymbol('om', size: 40),
          ],
        ),
      ),
    );
    expect(t.hasRunningAnimations, isFalse);
    expect(
      find.descendant(
        of: find.byType(GroupIcon),
        matching: find.byType(RepaintBoundary),
      ),
      findsNothing,
    );
    await t.pumpAndSettle(); // settles: nothing animates
  });

  testWidgets('shimmer: true animates (one controller, isolated layer)', (
    t,
  ) async {
    await t.pumpWidget(_app(const GroupIcon('gita', size: 96, shimmer: true)));
    expect(t.hasRunningAnimations, isTrue);
    expect(
      find.descendant(
        of: find.byType(GroupIcon),
        matching: find.byType(RepaintBoundary),
      ),
      findsOneWidget,
    );
    await t.pump(const Duration(milliseconds: 500));
    expect(t.takeException(), isNull);
    await t.pumpWidget(
      _app(const ReligionSymbol('om', size: 96, shimmer: true)),
    );
    expect(t.hasRunningAnimations, isTrue);
    await t.pumpWidget(const SizedBox()); // controller disposed cleanly
    expect(t.hasRunningAnimations, isFalse);
  });

  testWidgets('shimmer respects reduced motion', (t) async {
    await t.pumpWidget(
      _app(
        const GroupIcon('gita', size: 96, shimmer: true),
        disableAnimations: true,
      ),
    );
    expect(t.hasRunningAnimations, isFalse);
  });

  testWidgets('shimmer respects the app setting', (t) async {
    GranthIconStyle.shimmerEnabled = false;
    await t.pumpWidget(
      _app(const ReligionSymbol('om', size: 96, shimmer: true)),
    );
    expect(t.hasRunningAnimations, isFalse);
  });

  testWidgets('premium = false paints the exact v2 look', (t) async {
    GranthIconStyle.premium = false;
    await t.pumpWidget(
      _app(
        const Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            GroupIcon('book-red', size: 40, shimmer: true),
            ReligionSymbol('om', size: 40),
          ],
        ),
      ),
    );
    expect(t.hasRunningAnimations, isFalse);
    final cp = t.widget<CustomPaint>(
      find.descendant(
        of: find.byType(GroupIcon),
        matching: find.byType(CustomPaint),
      ),
    );
    expect((cp.painter! as GroupIconPainter).classic, isTrue);
    // v2 religion = gradient Container + bare ReligionSymbolPainter
    expect(
      find.descendant(
        of: find.byType(ReligionSymbol),
        matching: find.byType(Container),
      ),
      findsOneWidget,
    );
  });

  test('classic painter differs from v3 (v2 kept intact)', () async {
    expect(
      await _raster(const GroupIconPainter('book-red', classic: true)),
      isNot(equals(await _raster(const GroupIconPainter('book-red')))),
    );
  });
}
