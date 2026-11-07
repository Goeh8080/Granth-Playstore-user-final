import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:granthprabandhan/main.dart';
import 'package:granthprabandhan/screens/home_shell.dart';
import 'package:granthprabandhan/services/catalog_store.dart';
import 'package:granthprabandhan/services/storage.dart';
import 'package:granthprabandhan/state/router.dart';
import 'package:granthprabandhan/state/ui_prefs.dart';
import 'package:granthprabandhan/widgets/zoom.dart';

import 'helpers.dart';
import 'links_grid_test.dart' show settle;
import 'offline_test.dart' show pictureCatalog;

/// Round-2: no tab bar on the AI chat, sync/offline moved to Settings, 4-step text size.
/// Previews (real fonts) are written only when PREVIEW_DIR is set.
void main() {
  final dir = Platform.environment['PREVIEW_DIR'];

  setUp(() async {
    await setUpApp();
    AppZoom.current.value = ZoomView.identity;
    SyncStrip.open.value = false;
    UiPrefs.I.refresh();
    CatalogStore.I.debugSetCatalog(pictureCatalog());
  });

  Future<GlobalKey> boot(WidgetTester t, {double w = 412, double h = 915}) async {
    const fonts = {
      'NotoDeva': ['NotoSansDevanagari-Regular', 'NotoSansDevanagari-Medium', 'NotoSansDevanagari-SemiBold'],
      'DMSans': ['DMSans-Regular', 'DMSans-Medium', 'DMSans-SemiBold'],
      'YatraOne': ['YatraOne-Devanagari'],
      'YatraOneLatin': ['YatraOne-Latin'],
    };
    if (dir != null) {
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
    await t.binding.setSurfaceSize(Size(w * 2, h * 2));
    t.view.devicePixelRatio = 2;
    addTearDown(() => t.binding.setSurfaceSize(null));
    addTearDown(t.view.resetDevicePixelRatio);
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

  testWidgets('bottom tabs: shown on the dashboard, hidden on the AI chat', (t) async {
    UiPrefs.I.taskbar = true;
    await boot(t);
    expect(find.byKey(const ValueKey('bottom-tabs')), findsOneWidget);
    AppNav.I.go('#/ai');
    await settle(t, 6);
    expect(find.byKey(const ValueKey('bottom-tabs')), findsNothing);
    AppNav.I.go('#/dashboard');
    await settle(t, 6);
    expect(find.byKey(const ValueKey('bottom-tabs')), findsOneWidget);
  });

  testWidgets('dashboard has no sync strip; Settings → सिंक / ऑफ़लाइन has it', (t) async {
    final key = await boot(t);
    expect(find.byType(SyncStrip), findsNothing);
    expect(find.byKey(const ValueKey('sync-button')), findsNothing);
    AppNav.I.go('#/settings');
    await settle(t, 6);
    expect(find.byKey(const ValueKey('set-folder-sync'), skipOffstage: false), findsOneWidget);
    await snap(t, key, 'round2_settings_folders.png');
    AppNav.I.go('#/settings?s=sync');
    await settle(t, 6);
    expect(find.byType(SyncStrip), findsOneWidget);
    expect(find.byKey(const ValueKey('sync-button')), findsOneWidget);
    expect(find.byKey(const ValueKey('set-auto-sync-on')), findsOneWidget);
    SyncStrip.open.value = true;
    await settle(t, 6);
    expect(t.takeException(), isNull);
    await snap(t, key, 'round2_settings_sync.png');
  });

  for (final w in [320.0, 412.0]) {
    testWidgets('अक्षर का आकार: बहुत बड़ा is saved, applied and does not overflow at ${w.toInt()}dp', (t) async {
      final key = await boot(t, w: w, h: 760);
      AppNav.I.go('#/settings?s=display');
      await settle(t, 6);
      expect(find.byKey(const ValueKey('set-text-xlarge')), findsOneWidget);
      await t.tap(find.byKey(const ValueKey('set-text-xlarge')));
      await settle(t, 4);
      expect(UiPrefs.I.textSize, 'xlarge');
      expect(Store.I.getString(Store.kTextSize), 'xlarge');
      expect(MediaQuery.textScalerOf(t.element(find.byKey(const ValueKey('set-text-sample')))).scale(10), closeTo(13, 0.001));
      expect(t.takeException(), isNull);
      if (w == 412) await snap(t, key, 'round2_text_size_xlarge.png');
      for (final h in ['#/dashboard', '#/topics', '#/granths', '#/pramans', '#/settings', '#/settings?s=sync', '#/account', '#/ai']) {
        AppNav.I.go(h);
        await settle(t, 6);
        expect(t.takeException(), isNull, reason: '$h at ${w.toInt()}dp');
      }
      UiPrefs.I.textSize = 'normal';
    });
  }
}
