// T184 item 10: hidden iOS theme — tap the Settings version 7 times → theme picker
// (डिफ़ॉल्ट / iOS). Curved, soft, opaque cards (not liquid glass); persisted.
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:granthprabandhan/services/storage.dart';
import 'package:granthprabandhan/state/ui_prefs.dart';
import 'package:granthprabandhan/screens/home_shell.dart';
import 'package:granthprabandhan/widgets/zoom.dart';

import 'helpers.dart';
import 'links_grid_test.dart' show settle;
import 'round5_test.dart' show fingerTap, openApp, openSettings;
import 'themes_test.dart' show decos;

bool isIos(BoxDecoration d) =>
    d.borderRadius == BorderRadius.circular(22) && (d.boxShadow ?? const []).any((s) => s.blurRadius == 22) && d.color != null && d.color!.a == 1;

Future<void> tapVersion(WidgetTester t, int n) async {
  for (var i = 0; i < n; i++) {
    await fingerTap(t, find.byKey(const ValueKey('set-version')), wobble: Offset.zero);
    await t.pump(const Duration(milliseconds: 60));
  }
  await settle(t, 4);
}

void main() {
  setUp(() async {
    await setUpApp();
    AppZoom.current.value = ZoomView.identity;
    SyncStrip.open.value = false;
  });

  testWidgets('7 taps open the theme picker; iOS applies at once and persists', (t) async {
    await openApp(t);
    await openSettings(t, 'about');
    await tapVersion(t, 6);
    expect(find.byKey(const ValueKey('set-theme-ios')), findsNothing, reason: 'hidden until the 7th tap');
    await tapVersion(t, 1);
    final ios = find.byKey(const ValueKey('set-theme-ios'));
    expect(ios, findsOneWidget);
    expect(find.byKey(const ValueKey('set-theme-default')), findsOneWidget);
    await t.ensureVisible(ios);
    await settle(t, 2);
    await fingerTap(t, ios);
    await settle(t, 4);
    expect(UiPrefs.I.theme, 'ios');
    expect(Store.I.getString(Store.kTheme), 'ios');
    expect(decos(t).where(isIos), isNotEmpty, reason: 'soft curved cards on screen');
    expect(decos(t).where((d) => d.color != null && d.color!.a < 0.8 && (d.boxShadow ?? const []).any((s) => s.blurRadius == 28)), isEmpty, reason: 'not glass');
    expect(t.takeException(), isNull);

    // Restart: still iOS.
    await t.pumpWidget(const SizedBox());
    await openApp(t);
    expect(UiPrefs.I.theme, 'ios');
    expect(decos(t).where(isIos), isNotEmpty);

    // Back to default.
    UiPrefs.I.theme = 'default';
    await settle(t, 3);
    expect(decos(t).where(isIos), isEmpty);
    await t.pump(const Duration(seconds: 3));
  });
}
