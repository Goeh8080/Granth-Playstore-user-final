import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:granthprabandhan/main.dart';
import 'package:granthprabandhan/screens/home_shell.dart';
import 'package:granthprabandhan/services/catalog_store.dart';
import 'package:granthprabandhan/services/remote_config.dart';
import 'package:granthprabandhan/services/storage.dart';
import 'package:granthprabandhan/state/router.dart';
import 'package:granthprabandhan/state/ui_prefs.dart';
import 'package:granthprabandhan/widgets/zoom.dart';

import 'helpers.dart';
import 'links_grid_test.dart' show settle;
import 'offline_test.dart' show pictureCatalog;

/// Round-3: the floating taskbar (off by default, Settings toggle, admin `ui.taskbar`).
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

  tearDown(RemoteConfig.I.debugReset);

  testWidgets('fresh install: no taskbar; Settings → Display toggle shows it', (t) async {
    await boot(t);
    expect(UiPrefs.I.taskbar, isFalse);
    expect(find.byKey(const ValueKey('bottom-tabs')), findsNothing);
    AppNav.I.go('#/settings?s=display');
    await settle(t, 8);
    final on = find.byKey(const ValueKey('set-taskbar-on'));
    await t.scrollUntilVisible(on, 200, scrollable: find.byType(Scrollable).first);
    await t.tap(on);
    await settle(t, 6);
    expect(UiPrefs.I.taskbar, isTrue);
    expect(Store.I.getString(Store.kTaskbar), '1');
    AppNav.I.go('#/dashboard');
    await settle(t, 8);
    expect(find.byKey(const ValueKey('bottom-tabs')), findsOneWidget);
  });

  test('ui.taskbar parsing and precedence', () {
    expect(parseTaskbar(null), TaskbarRule.none);
    expect(parseTaskbar({'taskbar': true}), const TaskbarRule(def: true));
    expect(parseTaskbar({'taskbar': 'yes'}), TaskbarRule.none);
    expect(
      parseTaskbar({
        'taskbar': {'force': false, 'default': true},
      }),
      const TaskbarRule(force: false),
    );
    expect(
      parseTaskbar({
        'taskbar': {'enabled': false},
      }),
      const TaskbarRule(force: false),
    );
    expect(
      parseTaskbar({
        'taskbar': {'enabled': true},
      }),
      const TaskbarRule(def: true),
    );
    expect(
      parseTaskbar({
        'taskbar': {'enabled': true, 'default': false},
      }),
      const TaskbarRule(def: false),
    );
    expect(resolveTaskbar(TaskbarRule.none, null), isFalse);
    expect(resolveTaskbar(const TaskbarRule(def: true), null), isTrue);
    expect(resolveTaskbar(const TaskbarRule(def: true), false), isFalse);
    expect(resolveTaskbar(const TaskbarRule(force: true), false), isTrue);
    expect(resolveTaskbar(const TaskbarRule(force: false), true), isFalse);
  });

  testWidgets('admin force on: shown without a local choice; still hidden on AI chat', (t) async {
    RemoteConfig.I.uiTaskbar = const TaskbarRule(force: true);
    await boot(t);
    expect(find.byKey(const ValueKey('bottom-tabs')), findsOneWidget);
    AppNav.I.go('#/settings?s=display');
    await settle(t, 8);
    final label = find.textContaining('एडमिन द्वारा नियंत्रित (Managed by admin)');
    await t.scrollUntilVisible(label, 200, scrollable: find.byType(Scrollable).first);
    await t.tap(find.byKey(const ValueKey('set-taskbar-off')));
    await settle(t, 4);
    expect(UiPrefs.I.taskbar, isTrue); // locked
    AppNav.I.go('#/ai');
    await settle(t, 6);
    expect(find.byKey(const ValueKey('bottom-tabs')), findsNothing);
  });

  for (final w in [320.0, 412.0]) {
    testWidgets('floating taskbar at ${w.toInt()}dp, text 1.3: no overflow', (t) async {
      UiPrefs.I.taskbar = true;
      UiPrefs.I.textSize = 'xlarge';
      final key = await boot(t, w: w);
      expect(find.byKey(const ValueKey('bottom-tabs')), findsOneWidget);
      expect(t.takeException(), isNull);
      AppNav.I.go('#/granths');
      await settle(t, 8);
      expect(t.takeException(), isNull);
      // Inset pill: never touches the screen edges.
      final screen = t.getRect(find.byType(GranthApp));
      final bar = t.getRect(find.byKey(const ValueKey('bottom-tabs')));
      expect(bar.left, greaterThanOrEqualTo(screen.left));
      expect(bar.right, lessThanOrEqualTo(screen.right));
      await settle(t, 14);
      if (w == 412) await snap(t, key, 'round3_taskbar.png');
    });
  }
}
