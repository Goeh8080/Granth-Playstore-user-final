// t408: the approved login (02-login-v1-logo, aurora background) and terms (03-terms-v3)
// designs — visuals only; every button keeps its callback. Screenshots → /workspace/ui-ref/out/v2/
// (login.png, terms.png) when CAPTURE_UI=1.
import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:granthprabandhan/screens/login_screen.dart';
import 'package:granthprabandhan/services/remote_config.dart';
import 'package:granthprabandhan/state/ui_prefs.dart';

import 'helpers.dart';
import 'pdf_render_test.dart' show loadFonts;

final _capture = Platform.environment['CAPTURE_UI'] == '1';

void main() {
  setUp(setUpApp);
  final key = GlobalKey();

  Future<void> show(WidgetTester t, Widget page) async {
    await t.runAsync(loadFonts);
    await t.binding.setSurfaceSize(const Size(411, 891));
    addTearDown(() => t.binding.setSurfaceSize(null));
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger.setMockMethodCallHandler(const MethodChannel('dev.fluttercommunity.plus/package_info'), (c) async => {'appName': 'ग्रंथ प्रबंधन', 'packageName': 'com.granth.app.user', 'version': '1.0.0', 'buildNumber': '1'});
    await t.pumpWidget(RepaintBoundary(key: key, child: MaterialApp(debugShowCheckedModeBanner: false, home: page)));
    for (final a in ['assets/brand/app_logo.png', 'assets/brand/app_book.png']) {
      await t.runAsync(() => precacheImage(AssetImage(a), key.currentContext!));
    }
    for (var i = 0; i < 10; i++) {
      await t.pump(const Duration(milliseconds: 100));
    }
  }

  Future<void> shot(WidgetTester t, String name) async {
    if (!_capture) return;
    await t.runAsync(() async {
      final img = await (key.currentContext!.findRenderObject() as RenderRepaintBoundary).toImage(pixelRatio: 2);
      final d = await img.toByteData(format: ui.ImageByteFormat.png);
      File('/workspace/ui-ref/out/v2/$name.png').writeAsBytesSync(d!.buffer.asUint8List());
    });
  }

  testWidgets('login: logo, aurora, arch card; both "बाद में" skip, Google button stays', (t) async {
    var skips = 0;
    await show(t, LoginPage(onSkip: () => skips++));
    expect(find.byType(AuroraBackground), findsOneWidget);
    expect(find.byKey(const ValueKey('login-google')), findsOneWidget);
    expect(find.byKey(const ValueKey('login-arch')), findsOneWidget);
    expect(t.takeException(), isNull);
    await shot(t, 'login');
    await t.tap(find.byKey(const ValueKey('login-skip')));
    await t.tap(find.byKey(const ValueKey('login-skip-top')));
    expect(skips, 2);
    await t.pumpWidget(const SizedBox());
  });

  testWidgets('login when compulsory: no skip anywhere; reduced motion keeps the blobs still', (t) async {
    UiPrefs.I.animations = false;
    await show(t, const LoginPage(onSkip: null));
    expect(find.byKey(const ValueKey('login-skip')), findsNothing);
    expect(find.byKey(const ValueKey('login-skip-top')), findsNothing);
    expect(t.binding.hasScheduledFrame, isFalse, reason: 'no animation running');
    UiPrefs.I.animations = true;
    await t.pumpWidget(const SizedBox());
  });

  testWidgets('terms: accept / decline / links keep their callbacks; app version shown', (t) async {
    var accepted = 0, declined = 0;
    await show(t, TermsPage(terms: TermsInfo.fallback, onAccept: () => accepted++, onDecline: () => declined++));
    expect(find.text('नियम और शर्तें'), findsOneWidget);
    expect(find.text('ऐप संस्करण 1.0.0'), findsOneWidget);
    expect(find.byKey(const ValueKey('terms-link')), findsOneWidget);
    expect(find.byKey(const ValueKey('privacy-link')), findsOneWidget);
    await shot(t, 'terms');
    await t.tap(find.byKey(const ValueKey('terms-accept')));
    await t.tap(find.byKey(const ValueKey('terms-decline')));
    expect((accepted, declined), (1, 1));
  });
}
