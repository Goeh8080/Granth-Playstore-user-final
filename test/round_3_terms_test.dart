import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:granthprabandhan/main.dart';
import 'package:granthprabandhan/screens/home_shell.dart';
import 'package:granthprabandhan/services/catalog_store.dart';
import 'package:granthprabandhan/screens/login_screen.dart';
import 'package:granthprabandhan/services/firebase_bridge.dart';
import 'package:granthprabandhan/services/remote_config.dart';
import 'package:granthprabandhan/services/storage.dart';
import 'package:granthprabandhan/state/ui_prefs.dart';
import 'package:granthprabandhan/widgets/zoom.dart';

import 'helpers.dart';
import 'links_grid_test.dart' show settle;
import 'offline_test.dart' show pictureCatalog;

/// Round-3: the terms page after Google login (`ui.terms {url, version}`).
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

  setUp(() => LoginGate.enabled = true);
  tearDown(() async {
    LoginGate.enabled = false;
    RemoteConfig.I.debugReset();
    await FirebaseBridge.I.debugSetAccount(null);
  });

  Future<void> signIn() => FirebaseBridge.I.debugSetAccount(const AccountInfo(email: 'a@gmail.com', name: 'A'));

  test('ui.terms parsing with fallbacks', () {
    expect(parseTerms(null), TermsInfo.fallback);
    expect(TermsInfo.fallback.url, 'https://granth-management.web.app/terms');
    expect(TermsInfo.fallback.version, 1);
    expect(parseTerms({'terms': {'url': 'https://x.org/t', 'version': 3}}), const TermsInfo('https://x.org/t', 3));
    expect(parseTerms({'terms': {'url': 'javascript:alert(1)', 'version': 0}}), TermsInfo.fallback);
    expect(parseTerms({'terms': {'version': '2'}}).version, 2);
    expect(parseTerms({'terms': 'bad'}), TermsInfo.fallback);
    expect(TermsInfo.fallback.privacyUrl, 'https://granth-management.web.app/privacy');
    expect(parseTerms({'terms': {'url': 'https://a.org/t', 'privacy_url': 'https://a.org/p', 'version': 1}}).privacyUrl, 'https://a.org/p');
    expect(parseTerms({'terms': {'privacy_url': 'http://insecure/p'}}).privacyUrl, kPrivacyUrl);
  });

  testWidgets('already signed in: terms shown once; accept is stored; not shown again', (t) async {
    await signIn();
    await boot(t);
    expect(find.byKey(const ValueKey('terms-page')), findsOneWidget);
    expect(find.text('स्वीकार करें'), findsOneWidget);
    expect(find.byKey(const ValueKey('terms-link')), findsOneWidget);
    expect(find.byKey(const ValueKey('privacy-link')), findsOneWidget);
    expect(find.byKey(const ValueKey('terms-decline')), findsOneWidget);
    await t.tap(find.byKey(const ValueKey('terms-accept')));
    await settle(t);
    expect(find.byKey(const ValueKey('terms-page')), findsNothing);
    expect(Store.I.getString(Store.kTermsAccepted), '1');
    await t.pumpWidget(const SizedBox());
    await boot(t);
    expect(find.byKey(const ValueKey('terms-page')), findsNothing);
  });

  testWidgets('a newer ui.terms.version asks again', (t) async {
    await signIn();
    LoginGate.acceptTerms(1);
    await boot(t);
    expect(find.byKey(const ValueKey('terms-page')), findsNothing);
    RemoteConfig.I.uiTerms = const TermsInfo('https://x.org/t', 2);
    RemoteConfig.I.notifyListeners();
    await settle(t);
    expect(find.byKey(const ValueKey('terms-page')), findsOneWidget);
    await t.tap(find.byKey(const ValueKey('terms-accept')));
    await settle(t);
    expect(LoginGate.termsAccepted, 2);
  });

  testWidgets('right after Google login: login → terms → app; skip-login users never see it', (t) async {
    await boot(t);
    expect(find.byKey(const ValueKey('login-page')), findsOneWidget);
    await signIn();
    await settle(t);
    expect(find.byKey(const ValueKey('terms-page')), findsOneWidget);
    await FirebaseBridge.I.debugSetAccount(null);
    await settle(t);
    expect(find.byKey(const ValueKey('terms-page')), findsNothing);
  });

  for (final w in [320.0, 412.0]) {
    testWidgets('terms page at ${w.toInt()}dp, text 1.3: no overflow', (t) async {
      UiPrefs.I.textSize = 'xlarge';
      await signIn();
      final key = await boot(t, w: w, h: w == 320 ? 640 : 915);
      expect(find.byKey(const ValueKey('terms-page')), findsOneWidget);
      expect(t.takeException(), isNull);
      if (w == 412) await snap(t, key, 'round3_terms.png');
    });
  }

  testWidgets('अस्वीकार signs the user out and nothing is stored', (t) async {
    await signIn();
    await boot(t);
    await t.tap(find.byKey(const ValueKey('terms-decline')));
    await settle(t);
    expect(FirebaseBridge.I.signedIn, isFalse);
    expect(find.byKey(const ValueKey('terms-page')), findsNothing);
    expect(Store.I.getString(Store.kTermsAccepted), isNull);
  });
}
