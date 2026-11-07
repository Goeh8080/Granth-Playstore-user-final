import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:granthprabandhan/main.dart';
import 'package:granthprabandhan/services/catalog_store.dart';
import 'package:granthprabandhan/state/router.dart';
import 'package:granthprabandhan/state/ui_prefs.dart';
import 'package:granthprabandhan/widgets/common.dart';

import 'helpers.dart';
import 'links_grid_test.dart' show settle;
import 'offline_test.dart' show pictureCatalog;

/// Round-4 UI: top bar order, Ask Tatv AI tab, Aaj ka Pramaan page.
void main() {
  final dir = Platform.environment['PREVIEW_DIR'];

  setUp(() async {
    await setUpApp();
    UiPrefs.I.taskbar = true;
    UiPrefs.I.refresh();
    CatalogStore.I.debugSetCatalog(pictureCatalog());
  });

  Future<GlobalKey> boot(WidgetTester t, double w, {double scale = 1}) async {
    if (dir != null) {
      const fonts = {
        'NotoDeva': ['NotoSansDevanagari-Regular', 'NotoSansDevanagari-Medium', 'NotoSansDevanagari-SemiBold'],
        'DMSans': ['DMSans-Regular', 'DMSans-Medium', 'DMSans-SemiBold'],
        'YatraOne': ['YatraOne-Devanagari'],
        'YatraOneLatin': ['YatraOne-Latin'],
      };
      await t.runAsync(() async {
        for (final e in fonts.entries) {
          final l = FontLoader(e.key);
          for (final f in e.value) {
            l.addFont(Future.value(ByteData.sublistView(File('assets/fonts/$f.ttf').readAsBytesSync())));
          }
          await l.load();
        }
      });
    }
    await t.binding.setSurfaceSize(Size(w * 2, 780 * 2));
    t.view.devicePixelRatio = 2;
    addTearDown(() => t.binding.setSurfaceSize(null));
    addTearDown(t.view.resetDevicePixelRatio);
    t.platformDispatcher.textScaleFactorTestValue = scale;
    addTearDown(t.platformDispatcher.clearTextScaleFactorTestValue);
    final key = GlobalKey();
    await t.pumpWidget(RepaintBoundary(key: key, child: const GranthApp(splash: false, links: false)));
    await settle(t);
    return key;
  }

  Future<void> snap(WidgetTester t, GlobalKey key, String name) async {
    if (dir == null) return;
    await t.runAsync(() async {
      final img = await (key.currentContext!.findRenderObject() as RenderRepaintBoundary).toImage(pixelRatio: 1);
      final d = await img.toByteData(format: ui.ImageByteFormat.png);
      Directory(dir).createSync(recursive: true);
      File('$dir/$name').writeAsBytesSync(d!.buffer.asUint8List());
    });
  }

  Finder icon(String n) => find.byWidgetPredicate((w) => w is GIcon && w.name == n);

  for (final (w, s) in [(320.0, 1.3), (411.0, 1.0)]) {
    testWidgets('top bar PH→settings→account; AI tab; no profile tab; no daily card (${w.toInt()}dp × $s)', (t) async {
      final key = await boot(t, w, scale: s);
      expect(t.takeException(), isNull);
      final acc = t.getCenter(find.byKey(const ValueKey('mast-account'))).dx;
      final set = t.getCenter(icon('settings').first).dx;
      final ph = t.getCenter(icon('images').first).dx;
      expect(ph < set && set < acc, isTrue, reason: 'images $ph, settings $set, account $acc');
      expect(find.byKey(const ValueKey('tab-profile-avatar')), findsNothing);
      expect(find.byKey(const ValueKey('daily-praman')), findsNothing);
      expect(find.descendant(of: find.byKey(const ValueKey('tab-2')), matching: find.byKey(const ValueKey('tab-ai'))), findsOneWidget);
      if (w == 411) await snap(t, key, 'round4_dashboard.png');
      // Open AI from Topics, Back returns to Topics.
      await t.tap(find.byKey(const ValueKey('tab-1')));
      await settle(t);
      expect(AppNav.I.route.panel, Panel.topics);
      expect(find.byKey(const ValueKey('topics-trending')), findsWidgets);
      if (w == 411) await snap(t, key, 'round4_topics.png');
      await t.tap(find.byKey(const ValueKey('tab-2')));
      await settle(t);
      expect(AppNav.I.route.panel, Panel.ai);
      expect(t.takeException(), isNull);
      if (w == 411) await snap(t, key, 'round4_ai.png');
      AppNav.I.back();
      await settle(t);
      expect(AppNav.I.route.panel, Panel.topics);
      // Aaj ka Pramaan page.
      AppNav.I.openLink('#/today');
      await settle(t);
      expect(find.byKey(const ValueKey('today-page')), findsOneWidget);
      expect(t.takeException(), isNull);
      if (w == 411) await snap(t, key, 'round4_today.png');
      await t.runAsync(() => Future.delayed(const Duration(milliseconds: 300)));
      AppNav.I.back();
      await settle(t);
      expect(AppNav.I.route.panel, Panel.topics);
    });
  }
}
