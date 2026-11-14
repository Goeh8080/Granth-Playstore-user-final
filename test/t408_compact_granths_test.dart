// t408 (Goutam: "bade bade nahi", "buttons ki placement old wali hi he"): the Granth tab's
// top level laid out like ref1–3 — one header row (logo · Granths · temple · PDF pill on the
// right), a slim 1×1/2×2/3×3 pill (stacked over the search bar in 1×1, side by side in
// 2×2/3×3), compact religion tiles. Checked on 360×800 and 411×891 phones.
// Screenshots → /workspace/ui-ref/out/v2/ when CAPTURE_UI=1.
import 'dart:convert';
import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:granthprabandhan/main.dart';
import 'package:granthprabandhan/models/models.dart';
import 'package:granthprabandhan/screens/shelves_screen.dart';
import 'package:granthprabandhan/services/catalog_store.dart';
import 'package:granthprabandhan/services/remote_config.dart';
import 'package:granthprabandhan/services/storage.dart';
import 'package:granthprabandhan/state/router.dart';
import 'package:granthprabandhan/state/ui_prefs.dart';
import 'package:granthprabandhan/widgets/granths_hero.dart';

import 'helpers.dart';
import 'links_grid_test.dart' show settle;
import 'pdf_render_test.dart' show loadFonts;

final _capture = Platform.environment['CAPTURE_UI'] == '1';
const _out = '/workspace/ui-ref/out/v2';

void main() {
  setUp(() async {
    await setUpApp();
    RemoteConfig.I.uiGranthViewMode = null;
    await Store.I.setString(granthViewKey, 'folders');
    UiPrefs.I.taskbar = true;
    final raw = (jsonDecode(File('test/fixtures/granth_examples/catalog.json').readAsStringSync()) as List).cast<Map<String, dynamic>>();
    CatalogStore.I.debugSetCatalog(Catalog(topics: [], granths: raw.map(Granth.new).toList(), pramans: []));
  });
  tearDown(() => RemoteConfig.I.uiGranthViewMode = null);

  final key = GlobalKey();
  Future<void> boot(WidgetTester t, Size size) async {
    await t.runAsync(loadFonts);
    await t.binding.setSurfaceSize(size);
    addTearDown(() => t.binding.setSurfaceSize(null));
    await t.pumpWidget(RepaintBoundary(key: key, child: const GranthApp(splash: false, links: false)));
    await settle(t, 8);
    AppNav.I.go('#/granths');
    await settle(t, 24);
  }

  Future<void> shot(WidgetTester t, String name) async {
    if (!_capture) return;
    await t.runAsync(() async {
      final img = await (key.currentContext!.findRenderObject() as RenderRepaintBoundary).toImage(pixelRatio: 2);
      final data = await img.toByteData(format: ui.ImageByteFormat.png);
      Directory(_out).createSync(recursive: true);
      File('$_out/$name.png').writeAsBytesSync(data!.buffer.asUint8List());
      img.dispose();
    });
  }

  for (final size in const [Size(360, 800), Size(411, 891)]) {
    for (final cols in [1, 2, 3]) {
      testWidgets('${size.width.toInt()}×${size.height.toInt()} $cols×$cols: ref placement, compact tiles', (t) async {
        UiPrefs.I.setCols(Store.kGranthCols, cols);
        await boot(t, size);
        expect(t.takeException(), isNull);
        // header row: logo + title on the left, the PDF pill on the RIGHT of the same row
        final title = t.getRect(find.text('Granths'));
        final pill = t.getRect(find.byKey(const ValueKey('multi-pdf-pill')));
        expect(pill.left, greaterThan(title.right - 1), reason: 'pill right of the title');
        expect(pill.center.dy, inInclusiveRange(title.top - 24, title.bottom + 30), reason: 'pill on the title row');
        expect(t.getRect(find.byType(GranthsHero)).height, lessThan(90));
        // the slim app bar: no stats boxes, the menu button lives in it
        expect(find.byKey(const ValueKey('mast-menu')), findsOneWidget);
        expect(find.text('पवित्र ग्रन्थ'), findsOneWidget, reason: 'stats stay (slim)');
        expect(find.byKey(const ValueKey('mast-account')), findsOneWidget);
        // toggle and search: stacked in 1×1 (ref1), side by side in 2×2/3×3 (ref3)
        final grid = t.getRect(find.byKey(const ValueKey('grid-1')));
        final filter = t.getRect(find.byKey(const ValueKey('search-filter')));
        if (cols == 1) {
          expect(filter.top, greaterThan(grid.bottom), reason: 'search under the pill');
        } else {
          expect((filter.center.dy - grid.center.dy).abs(), lessThan(8), reason: 'pill and search on one row');
        }
        expect(grid.height, lessThanOrEqualTo(36));
        // compact folder cards
        final first = t.getRect(find.byType(FolderRow).first);
        final perRow = find.byType(FolderRow).evaluate().where((e) => (t.getRect(find.byWidget(e.widget)).top - first.top).abs() < 1).length;
        expect(perRow, cols);
        switch (cols) {
          case 1:
            expect(first.height, lessThanOrEqualTo(76), reason: '1×1 is a slim row (ref2)');
          default:
            // t408: iOS-style squircle tiles, exactly 1:1, in the old grid arrangement.
            expect(first.height, moreOrLessEquals(first.width, epsilon: 1), reason: 'square tiles');
            expect(first.width, lessThanOrEqualTo(cols == 2 ? 190 : 125), reason: 'compact, not big');
            final shape = t.widget<DecoratedBox>(find.descendant(of: find.byType(FolderRow).first, matching: find.byType(DecoratedBox)).first).decoration;
            expect(shape, isA<ShapeDecoration>().having((d) => d.shape, 'shape', isA<ContinuousRectangleBorder>()));
            expect((shape as ShapeDecoration).gradient, isNull, reason: 'flat old colours, no gloss');
        }
        expect(find.byKey(const ValueKey('ask-ai-fab')), findsOneWidget);
        expect(find.byKey(const ValueKey('bottom-tabs-hidden')), findsNothing);
        await shot(t, 'granths_${cols}x${cols}_${size.width.toInt()}');
      });
    }
  }

  testWidgets('menu button in the slim bar opens the nav menu; other tabs keep the full bar', (t) async {
    await boot(t, const Size(360, 800));
    await t.tap(find.byKey(const ValueKey('mast-menu')));
    await settle(t, 6);
    expect(AppNav.I.menuOpen, isTrue);
    expect(find.byKey(const ValueKey('nav-clipboard-list')), findsOneWidget);
    await t.tap(find.byKey(const ValueKey('nav-clipboard-list')));
    await settle(t, 10);
    expect(find.byKey(const ValueKey('mast-menu')), findsNothing);
    expect(find.text('पवित्र ग्रन्थ'), findsOneWidget);
  });
}
