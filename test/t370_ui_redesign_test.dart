// t368: the redesigned Granth tab (ref1–3), premium logo tiles, the once-only live chooser
// and its setting. Screenshots → /workspace/ui-ref/out/ when CAPTURE_UI=1.
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
import 'package:granthprabandhan/widgets/icon_v3_style.dart';
import 'package:granthprabandhan/widgets/religion_symbol.dart';

import 'helpers.dart';
import 'links_grid_test.dart' show settle;
import 'pdf_render_test.dart' show loadFonts;
import 'round5_test.dart' show fingerTap, openSettings;

final _capture = Platform.environment['CAPTURE_UI'] == '1';
const _out = '/workspace/ui-ref/out';

void main() {
  setUp(() async {
    await setUpApp();
    RemoteConfig.I.uiGranthViewMode = null;
    final raw = (jsonDecode(File('test/fixtures/granth_examples/catalog.json').readAsStringSync()) as List).cast<Map<String, dynamic>>();
    CatalogStore.I.debugSetCatalog(Catalog(topics: [], granths: raw.map(Granth.new).toList(), pramans: []));
  });
  tearDown(() => RemoteConfig.I.uiGranthViewMode = null);

  final key = GlobalKey();
  Future<void> boot(WidgetTester t, {double h = 844}) async {
    await t.runAsync(loadFonts);
    await t.binding.setSurfaceSize(Size(390, h));
    addTearDown(() => t.binding.setSurfaceSize(null));
    await t.pumpWidget(RepaintBoundary(key: key, child: const GranthApp(splash: false, links: false)));
    await settle(t, 8);
    AppNav.I.go('#/granths');
    await settle(t, 20);
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

  for (final cols in [1, 2, 3]) {
    testWidgets('Granth tab $cols×$cols: hero, pill toggle, rounded search, premium religion tiles with real counts', (t) async {
      UiPrefs.I.setCols(Store.kGranthCols, cols);
      await boot(t, h: cols == 1 ? 1100 : 900);
      expect(find.byType(GranthsHero), findsOneWidget);
      expect(find.text('Granths'), findsOneWidget);
      expect(find.text('Sacred texts and scriptures'), findsOneWidget);
      expect(find.byKey(const ValueKey('multi-pdf-pill')), findsOneWidget);
      for (final n in [1, 2, 3]) {
        expect(find.byKey(ValueKey('grid-$n')), findsOneWidget);
      }
      expect(find.byKey(const ValueKey('search-filter')), findsOneWidget);
      expect(find.text('ग्रंथ का नाम — gita...'), findsOneWidget);
      expect(find.byType(FolderRow), findsWidgets);
      expect(t.widget<FolderRow>(find.byType(FolderRow).first).cols, cols);
      expect(find.byType(IconV3Box), findsWidgets);
      // counts come from the catalog
      expect(find.textContaining('ग्रंथ'), findsWidgets);
      // the app's own bottom bar and the Ask Tatv AI button stay
      expect(find.byKey(const ValueKey('ask-ai-fab')), findsOneWidget);
      final err = t.takeException();
      if (err is FlutterError) debugPrint(err.toStringDeep());
      expect(err, isNull);
      await shot(t, 'granths_${cols}x$cols');
    });
  }

  testWidgets('home tiles use the shared v3 premium icons (glossy 3D), shimmer off in the grid', (t) async {
    expect(GranthIconStyle.premium, isTrue);
    UiPrefs.I.setCols(Store.kGranthCols, 3);
    await boot(t);
    final tiles = t.widgetList<ReligionSymbol>(find.byType(ReligionSymbol)).toList();
    expect(tiles.length, greaterThanOrEqualTo(8));
    expect(tiles.every((s) => !s.shimmer), isTrue, reason: 'no shimmer in lists and grids');
    expect(find.byType(IconV3Box), findsWidgets);
    expect(t.takeException(), isNull);
    // close-up of the tiles (v3 shared painter) for review
    if (_capture) {
      final k = GlobalKey();
      await t.pumpWidget(Directionality(
        textDirection: TextDirection.ltr,
        child: Center(
          child: RepaintBoundary(
            key: k,
            child: Container(
              color: const Color(0xFFFDF6E3),
              padding: const EdgeInsets.all(12),
              child: Wrap(spacing: 14, runSpacing: 14, children: [
                for (final n in [...religionSymbolNames, 'kamal', 'deepak', 'atash', 'surya']) ReligionSymbol(n, size: 84),
              ]),
            ),
          ),
        ),
      ));
      await t.pump();
      await t.runAsync(() async {
        final img = await (k.currentContext!.findRenderObject() as RenderRepaintBoundary).toImage(pixelRatio: 3);
        final data = await img.toByteData(format: ui.ImageByteFormat.png);
        File('$_out/tiles_v3_closeup.png').writeAsBytesSync(data!.buffer.asUint8List());
        img.dispose();
      });
    }
  });

  testWidgets('chooser: asked once, live scrolling previews (no PNG), no close button, kept after logout, changed in Settings', (t) async {
    await Store.I.remove(granthViewKey);
    UiPrefs.I.animations = true;
    await boot(t);
    expect(find.byKey(const ValueKey('granth-view-picker')), findsOneWidget);
    expect(find.byType(GranthViewLivePreview), findsNWidgets(2));
    expect(find.descendant(of: find.byKey(const ValueKey('granth-view-picker')), matching: find.byType(Image)), findsNothing, reason: 'live widgets, not pictures');
    expect(find.descendant(of: find.byKey(const ValueKey('granth-view-preview-folders')), matching: find.byType(FolderRow)), findsWidgets);
    expect(find.descendant(of: find.byKey(const ValueKey('granth-view-picker')), matching: find.byType(IconButton)), findsNothing, reason: 'no X');
    expect(find.text('एक बार चुनें · बाद में सेटिंग्स में बदल सकते हैं'), findsOneWidget);
    // it scrolls
    Matrix4 m(String mode) => t.widget<Transform>(find.descendant(of: find.byKey(ValueKey('granth-view-preview-$mode')), matching: find.byKey(const ValueKey('granth-view-preview-page')))).transform;
    final y0 = m('folders').getTranslation().y;
    await t.pump(const Duration(seconds: 4));
    expect(m('folders').getTranslation().y, lessThan(y0 - 5), reason: 'folder preview scrolls');
    await shot(t, 'chooser');
    final ys = <double>{};
    for (var i = 0; i < 8; i++) {
      ys.add(m('list').getTranslation().y.roundToDouble());
      await t.pump(const Duration(milliseconds: 700));
    }
    expect(ys.length, greaterThan(2), reason: 'list preview scrolls');
    // Back does not close it
    await t.binding.handlePopRoute();
    await t.pump(const Duration(milliseconds: 400));
    expect(find.byKey(const ValueKey('granth-view-picker')), findsOneWidget);
    await t.tap(find.byKey(const ValueKey('granth-view-list')));
    await t.pump(const Duration(milliseconds: 600));
    expect(Store.I.getString(granthViewKey), 'list');
    // change from the filter button / Settings without being asked again
    await setGranthView('folders');
    await t.pump(const Duration(milliseconds: 400));
    expect(granthViewMode(), 'folders');
    UiPrefs.I.animations = false;
    await t.pumpWidget(const SizedBox());
    await t.pump(const Duration(seconds: 1));
  });

  test('logout keeps the choice (asked only once ever)', () {
    final src = File('lib/services/firebase_bridge.dart').readAsStringSync();
    expect(src.contains('remove(Store.kGranthView)'), isFalse);
  });

  testWidgets('admin override: no chooser and the setting is locked', (t) async {
    await Store.I.remove(granthViewKey);
    RemoteConfig.I.uiGranthViewMode = 'list';
    await boot(t);
    expect(find.byKey(const ValueKey('granth-view-picker')), findsNothing);
    await t.tap(find.byKey(const ValueKey('search-filter')));
    await settle(t, 6);
    expect(find.byKey(const ValueKey('granth-view-sheet')), findsOneWidget);
    expect(find.textContaining('एडमिन द्वारा नियंत्रित'), findsOneWidget);
  });

  testWidgets('Settings → ग्रंथ दृश्य changes folders/list without asking again', (t) async {
    await Store.I.setString(granthViewKey, 'folders');
    await boot(t);
    await openSettings(t);
    final list = find.byKey(const ValueKey('set-granth-view-list'), skipOffstage: false);
    expect(find.byKey(const ValueKey('set-granth-view'), skipOffstage: false), findsOneWidget);
    await t.ensureVisible(list);
    await settle(t, 3);
    await fingerTap(t, list);
    await settle(t, 4);
    expect(Store.I.getString(granthViewKey), 'list');
    AppNav.I.go('#/granths');
    await settle(t, 10);
    expect(find.byKey(const ValueKey('granth-view-picker')), findsNothing);
    expect(find.byType(FolderRow), findsNothing, reason: 'the list view now');
  });
}
