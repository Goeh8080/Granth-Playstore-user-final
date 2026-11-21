import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:granthprabandhan/main.dart';
import 'package:granthprabandhan/screens/login_screen.dart';
import 'package:granthprabandhan/services/remote_config.dart';
import 'package:granthprabandhan/services/firebase_bridge.dart';
import 'package:granthprabandhan/state/ui_prefs.dart';
import 'package:granthprabandhan/services/storage.dart';
import 'package:granthprabandhan/state/router.dart';
import 'package:granthprabandhan/widgets/granth_view_setting.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'helpers.dart';

Future<void> settle(WidgetTester t, [int n = 14]) async {
  for (var i = 0; i < n; i++) {
    await t.pump(const Duration(milliseconds: 100));
  }
}

void main() {
  setUp(() async {
    await setUpApp();
    await Store.I.remove(granthViewKey); // a truly fresh install
  });
  tearDown(() async {
    LoginGate.enabled = false;
    await FirebaseBridge.I.debugSetAccount(null);
    RemoteConfig.I.debugReset();
  });

  testWidgets('t430 fresh install (slow prefs, login skipped): chooser shown on the Granth tab', (t) async {
    SharedPreferences.setMockInitialValues({});
    final p = (await t.runAsync(() async {
      final p = await SharedPreferences.getInstance();
      await Store.I.initForTest(null, await Directory.systemTemp.createTemp('fresh'));
      return p;
    }))!;
    LoginGate.enabled = true;
    final old = FlutterError.onError;
    FlutterError.onError = (d) {
      if ('${d.exception}'.contains('overflowed')) return; // test font metrics on the login page
      old?.call(d);
    };
    await t.binding.setSurfaceSize(const Size(412, 915));
    addTearDown(() => t.binding.setSurfaceSize(null));
    await t.pumpWidget(const GranthApp(splash: false, links: false));
    await settle(t, 3);
    Store.I.debugAdoptPrefs(p);
    await settle(t);
    final skip = find.text('बाद में');
    if (skip.evaluate().isNotEmpty) {
      await t.tap(skip.first);
      await settle(t);
    }
    AppNav.I.go('#/granths');
    await settle(t, 20);
    final shown = find.byKey(const ValueKey('granth-view-picker')).evaluate().length;
    FlutterError.onError = old;
    expect(shown, 1);
  });
  testWidgets('t430 live config (login_required, grid_pages), Google sign-in: chooser shown on the Granth tab', (t) async {
    SharedPreferences.setMockInitialValues({});
    final p = (await t.runAsync(() async {
      final p = await SharedPreferences.getInstance();
      await Store.I.initForTest(null, await Directory.systemTemp.createTemp('fresh'));
      return p;
    }))!;
    LoginGate.enabled = true;
    RemoteConfig.I.uiLoginRequired = true;
    RemoteConfig.I.uiGrid = 2;
    RemoteConfig.I.uiGridPages = parseGridPages({'grid_pages': {'granths': 3, 'shelves': 2, 'pramans': 2, 'topics': 1, 'gallery': 2, 'dashboard': 1}});
    UiPrefs.I.remoteChanged();
    final old = FlutterError.onError;
    FlutterError.onError = (d) {
      if ('${d.exception}'.contains('overflowed')) return; // test font metrics on the login page
      old?.call(d);
    };
    await t.binding.setSurfaceSize(const Size(412, 915));
    addTearDown(() => t.binding.setSurfaceSize(null));
    await t.pumpWidget(const GranthApp(splash: false, links: false));
    await settle(t, 3);
    Store.I.debugAdoptPrefs(p);
    await settle(t);
    await FirebaseBridge.I.debugSetAccount(const AccountInfo(email: 'a@gmail.com', name: 'A'));
    await settle(t);
    final accept = find.byKey(const ValueKey('terms-accept'));
    if (accept.evaluate().isNotEmpty) {
      await t.ensureVisible(accept);
      await t.tap(accept);
      await settle(t);
    }
    AppNav.I.go('#/granths');
    await settle(t, 20);
    final shown = find.byKey(const ValueKey('granth-view-picker')).evaluate().length;
    FlutterError.onError = old;
    expect(shown, 1);
  });

  testWidgets('t430 fresh install → chooser shown → choice saved → never shown again (also after restart)', (t) async {
    SharedPreferences.setMockInitialValues({});
    await t.binding.setSurfaceSize(const Size(412, 915));
    addTearDown(() => t.binding.setSurfaceSize(null));
    await t.pumpWidget(const GranthApp(splash: false, links: false));
    await settle(t, 3);
    AppNav.I.go('#/granths');
    await settle(t, 20);
    expect(find.byKey(const ValueKey('granth-view-picker')), findsOneWidget);
    await t.tap(find.byKey(const ValueKey('granth-view-list')));
    await settle(t, 10);
    expect(find.byKey(const ValueKey('granth-view-picker')), findsNothing);
    expect(Store.I.getString(granthViewKey), 'list');
    // Leave and come back: not asked again.
    AppNav.I.go('#/dashboard');
    await settle(t, 6);
    AppNav.I.go('#/granths');
    await settle(t, 20);
    expect(find.byKey(const ValueKey('granth-view-picker')), findsNothing);
    // "Restart": a new app tree on the same saved settings.
    await t.pumpWidget(const SizedBox());
    await t.pumpWidget(const GranthApp(splash: false, links: false));
    await settle(t, 3);
    AppNav.I.go('#/granths');
    await settle(t, 20);
    expect(find.byKey(const ValueKey('granth-view-picker')), findsNothing);
  });

  testWidgets('t430 upgraded 1.0.0 user who never chose: asked once', (t) async {
    // 1.0.0 left other settings but no granth-view-mode.
    await Store.I.setString(Store.kSchema, '1');
    await t.binding.setSurfaceSize(const Size(412, 915));
    addTearDown(() => t.binding.setSurfaceSize(null));
    await t.pumpWidget(const GranthApp(splash: false, links: false));
    await settle(t, 3);
    AppNav.I.go('#/granths');
    await settle(t, 20);
    expect(find.byKey(const ValueKey('granth-view-picker')), findsOneWidget);
    await t.tap(find.byKey(const ValueKey('granth-view-folders')));
    await settle(t, 10);
    expect(Store.I.getString(granthViewKey), 'folders');
  });

  testWidgets('t430 chooser closed by something else (no choice): asked again', (t) async {
    await t.binding.setSurfaceSize(const Size(412, 915));
    addTearDown(() => t.binding.setSurfaceSize(null));
    await t.pumpWidget(const GranthApp(splash: false, links: false));
    await settle(t, 3);
    AppNav.I.go('#/granths');
    await settle(t, 20);
    expect(find.byKey(const ValueKey('granth-view-picker')), findsOneWidget);
    appNavigatorKey.currentState!.pop(); // e.g. another popup's close popped it
    await settle(t, 20);
    expect(find.byKey(const ValueKey('granth-view-picker')), findsOneWidget);
    expect(Store.I.getString(granthViewKey), isNull);
  });

  testWidgets('t430 login page: the red terms text opens all policy cards before sign-in', (t) async {
    final old = FlutterError.onError;
    FlutterError.onError = (d) {
      if ('${d.exception}'.contains('overflowed')) return; // test font metrics on the login page
      old?.call(d);
    };
    await t.binding.setSurfaceSize(const Size(412, 915));
    addTearDown(() => t.binding.setSurfaceSize(null));
    await t.pumpWidget(MaterialApp(home: LoginPage(onSkip: () {})));
    await settle(t, 5);
    await t.tap(find.byKey(const ValueKey('login-legal')));
    await settle(t, 8);
    expect(find.byKey(const ValueKey('legal-standalone')), findsOneWidget);
    expect(find.byKey(const ValueKey('legal-privacy')), findsOneWidget);
    await t.tap(find.byKey(const ValueKey('legal-privacy')));
    await settle(t, 8);
    expect(find.text('गोपनीयता नीति'), findsWidgets);
    await t.tap(find.byKey(const ValueKey('legal-standalone-back')));
    await settle(t, 8);
    expect(find.byKey(const ValueKey('legal-privacy')), findsOneWidget);
    FlutterError.onError = old;
  });
}
