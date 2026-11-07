import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:granthprabandhan/main.dart';
import 'package:granthprabandhan/screens/home_shell.dart';
import 'package:granthprabandhan/screens/login_screen.dart';
import 'package:granthprabandhan/services/catalog_store.dart';
import 'package:granthprabandhan/services/firebase_bridge.dart';
import 'package:granthprabandhan/services/remote_config.dart';
import 'package:granthprabandhan/services/storage.dart';
import 'package:granthprabandhan/state/router.dart';
import 'package:granthprabandhan/state/ui_prefs.dart';
import 'package:granthprabandhan/widgets/zoom.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'helpers.dart';
import 'links_grid_test.dart' show settle;
import 'offline_test.dart' show pictureCatalog;

/// Round-4: a saved grid and accepted terms survive a cold restart (fresh widget tree, fresh
/// Store memory, prefs re-read from the SharedPreferences mock), with the signed config
/// (live values: grid 1, grid_pages pramans/topics 3) applied after the prefs.
void main() {
  setUp(() async {
    await setUpApp();
    AppZoom.current.value = ZoomView.identity;
    SyncStrip.open.value = false;
    UiPrefs.I.refresh();
    CatalogStore.I.debugSetCatalog(pictureCatalog());
  });
  tearDown(() async {
    LoginGate.enabled = false;
    RemoteConfig.I.debugReset();
    await FirebaseBridge.I.debugSetAccount(null);
  });

  void liveConfig() {
    RemoteConfig.I.uiGrid = 1;
    RemoteConfig.I.uiGridPages = parseGridPages({'grid_pages': {'granths': 3, 'pramans': 3, 'topics': 3, 'gallery': 3}});
    UiPrefs.I.remoteChanged();
    RemoteConfig.I.notifyListeners();
  }

  /// Kills the app: the tree goes, the session memory goes, the prefs file stays.
  Future<void> coldRestart(WidgetTester t) async {
    await t.pumpWidget(const SizedBox());
    final saved = await t.runAsync(() async {
      final p = await SharedPreferences.getInstance();
      return {for (final k in p.getKeys()) k: p.get(k)!};
    });
    SharedPreferences.setMockInitialValues(saved!);
    await t.runAsync(() async => Store.I.initForTest(await SharedPreferences.getInstance(), Store.I.root));
    RemoteConfig.I.debugReset();
    FirebaseBridge.I.debugForgetMemory();
    AppNav.I = AppNav();
  }

  Future<void> boot(WidgetTester t) async {
    await t.binding.setSurfaceSize(const Size(412, 915));
    addTearDown(() => t.binding.setSurfaceSize(null));
    await t.pumpWidget(const GranthApp(splash: false, links: false));
    await settle(t);
  }

  for (final page in [('pramans', 'praman'), ('topics', 'topic')]) {
    testWidgets('${page.$1}: saved 1×1 survives a restart with the config loaded later', (t) async {
      liveConfig();
      AppNav.I.go('#/${page.$1}');
      await boot(t);
      await t.tap(find.byKey(const ValueKey('grid-1')).first);
      await settle(t);
      await coldRestart(t);
      AppNav.I.go('#/${page.$1}');
      await boot(t);
      liveConfig(); // the signed config arrives after the prefs
      await settle(t);
      expect(UiPrefs.I.pageCols(page.$1, page.$1 == 'pramans' ? Store.kPramanCols : Store.kTopicCols), 1);
      expect(find.byKey(const ValueKey('grid-1')), findsWidgets);
      final sel = t.widget<Semantics>(find.ancestor(of: find.byKey(const ValueKey('grid-1')).first, matching: find.byType(Semantics)).first);
      expect(sel.properties.selected, isTrue);
    });
  }

  testWidgets('admin default 3 on a 1|2 page: layout and pill both say 2', (t) async {
    liveConfig();
    expect(UiPrefs.I.pageCols('pramans', Store.kPramanCols), 2);
  });

  testWidgets('grid_pages: number and {default} are defaults, {force} wins and locks', (t) async {
    expect(parseGridPages({'grid_pages': {'granth': 3, 'topics': {'default': 1}, 'pramans': {'force': 1}}}), {'granths': 3, 'topics': 1});
    expect(parseGridForce({'grid_pages': {'granth': {'force': 1}, 'topics': 2, 'gallery': {'force': 7}}}), {'granths': 1});
    Store.I.setString(Store.kGranthCols, '2');
    RemoteConfig.I.uiGridPages = {'granths': 3};
    expect(UiPrefs.I.granthCols, 2); // user › default
    RemoteConfig.I.uiGridForce = {'granths': 1};
    expect(UiPrefs.I.granthCols, 1); // force › user
    expect(UiPrefs.I.gridLocked('granths'), isTrue);
    AppNav.I.go('#/granths?all=1'); // Test the granth grid, not the shelves grid.
    await boot(t);
    expect(find.byKey(const ValueKey('grid-locked')), findsOneWidget);
    await t.tap(find.byKey(const ValueKey('grid-2')).first, warnIfMissed: false);
    await settle(t);
    expect(Store.I.getString(Store.kGranthCols), '2');
    expect(UiPrefs.I.granthCols, 1);
  });

  testWidgets('accepted terms: no terms page after a cold restart', (t) async {
    LoginGate.enabled = true;
    await FirebaseBridge.I.debugSetAccount(const AccountInfo(email: 'a@gmail.com', name: 'A'));
    await boot(t);
    expect(find.byKey(const ValueKey('terms-page')), findsOneWidget);
    await t.tap(find.byKey(const ValueKey('terms-accept')));
    await settle(t);
    await coldRestart(t);
    expect(FirebaseBridge.I.signedIn, isTrue);
    await boot(t);
    RemoteConfig.I.uiTerms = const TermsInfo('https://granth-management.web.app/terms', 1);
    RemoteConfig.I.notifyListeners();
    await settle(t);
    expect(find.byKey(const ValueKey('terms-page')), findsNothing);
    expect(find.byKey(const ValueKey('login-passed')), findsOneWidget);
  });

  testWidgets('slow phone: prefs open after the first frame → no terms flash, saved grid applied', (t) async {
    LoginGate.enabled = true;
    await FirebaseBridge.I.debugSetAccount(const AccountInfo(email: 'a@gmail.com', name: 'A'));
    LoginGate.acceptTerms(1);
    UiPrefs.I.setCols(Store.kPramanCols, 1);
    await coldRestart(t);
    final prefs = await t.runAsync(SharedPreferences.getInstance);
    await t.runAsync(() => Store.I.initForTest(null, Store.I.root)); // prefs not open yet
    FirebaseBridge.I.debugForgetMemory();
    liveConfig();
    AppNav.I.go('#/pramans');
    await boot(t);
    expect(find.byKey(const ValueKey('terms-page')), findsNothing);
    Store.I.debugAdoptPrefs(prefs!);
    FirebaseBridge.I.debugForgetMemory();
    await settle(t);
    expect(find.byKey(const ValueKey('terms-page')), findsNothing);
    expect(UiPrefs.I.pageCols('pramans', Store.kPramanCols), 1);
    await t.pumpWidget(const SizedBox());
    await t.pump(const Duration(seconds: 10));
  });

  // T184 item 4: a 3×3 grid must be 3 columns on the very FIRST frame after a cold start.
  Future<void> firstFrame(WidgetTester t) async {
    await t.binding.setSurfaceSize(const Size(412, 915));
    addTearDown(() => t.binding.setSurfaceSize(null));
    await t.pumpWidget(const GranthApp(splash: false, links: false));
    await t.pump();
  }

  testWidgets('T184 cold start: saved 3 is the first frame (no 2×2 flash)', (t) async {
    UiPrefs.I.setCols(Store.kGranthCols, 3);
    await coldRestart(t);
    AppNav.I.go('#/granths');
    await firstFrame(t);
    expect(find.byKey(const ValueKey('grid-3')), findsWidgets);
    final ks = find.byType(KeyedSubtree).evaluate().map((e) => e.widget.key).whereType<ValueKey<String>>().map((k) => k.value).where((v) => v.startsWith('grid-')).toSet();
    expect(ks, isNot(contains('grid-2')));
    expect(UiPrefs.I.granthCols, 3);
    await settle(t);
  });

  testWidgets('T184 cold start: admin default 3, no user value → 3 on the first frame; user 3 snaps to 2 on a 1|2 page', (t) async {
    await coldRestart(t);
    RemoteConfig.I.uiGridPages = {'granths': 3};
    AppNav.I.go('#/granths');
    await firstFrame(t);
    expect(UiPrefs.I.granthCols, 3);
    Store.I.setString(Store.kPramanCols, '3');
    expect(UiPrefs.I.pageCols('pramans', Store.kPramanCols), 2, reason: 'user value snapped to the page');
    RemoteConfig.I.uiGridForce = {'pramans': 1};
    expect(UiPrefs.I.pageCols('pramans', Store.kPramanCols), 1, reason: 'force › user');
    await settle(t);
  });
}
