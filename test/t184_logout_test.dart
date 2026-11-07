import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:granthprabandhan/main.dart';
import 'package:granthprabandhan/screens/login_screen.dart';
import 'package:granthprabandhan/services/firebase_bridge.dart';
import 'package:granthprabandhan/services/storage.dart';

import 'helpers.dart';
import 'links_grid_test.dart' show settle;

void main() {
  setUp(setUpApp);
  tearDown(() async {
    final fb = FirebaseBridge.I;
    fb.debugAuthenticate = null;
    fb.debugSignOutStep = null;
    fb.debugSignOutCalls.clear();
    LoginGate.enabled = false;
    await fb.debugSetAccount(null);
  });

  testWidgets('logout → Firebase + Google sign-out, account cleared, gate back; Google again logs in another account', (t) async {
    final fb = FirebaseBridge.I;
    LoginGate.enabled = true;
    LoginGate.acceptTerms(1);
    var picks = 0;
    final accounts = [const AccountInfo(email: 'a@gmail.com', name: 'A'), const AccountInfo(email: 'b@gmail.com', name: 'B')];
    fb.debugAuthenticate = () async => accounts[picks++]; // each call = the account picker
    fb.debugSignOutStep = (_) async {};
    await t.pumpWidget(const GranthApp(splash: false, links: false));
    await settle(t);
    await t.tap(find.byKey(const ValueKey('login-google')));
    await settle(t);
    expect(fb.account!.email, 'a@gmail.com');
    expect(find.byKey(const ValueKey('login-page')), findsNothing);

    await fb.signOut();
    await settle(t);
    expect(fb.debugSignOutCalls, ['firebase', 'google']);
    expect(fb.signedIn, isFalse);
    expect(Store.I.getString(FirebaseBridge.kAccount), isNull);
    expect(LoginGate.seen, isFalse);
    expect(find.byKey(const ValueKey('login-page')), findsOneWidget);

    await t.tap(find.byKey(const ValueKey('login-google')));
    await settle(t);
    expect(picks, 2, reason: 'the picker opened again');
    expect(fb.account!.email, 'b@gmail.com');
    expect(find.byKey(const ValueKey('login-page')), findsNothing);
  });

  test('Google signOut fails → disconnect; a Firebase failure never skips Google', () async {
    final fb = FirebaseBridge.I;
    await fb.debugSetAccount(const AccountInfo(email: 'a@gmail.com', name: 'A'));
    fb.debugSignOutStep = (s) async {
      if (s != 'disconnect') throw StateError(s);
    };
    await fb.signOut();
    expect(fb.debugSignOutCalls, ['firebase', 'google', 'disconnect']);
    expect(fb.signedIn, isFalse);
  });
}
