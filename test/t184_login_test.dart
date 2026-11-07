// Google login always works: stale-account retry, Firebase provider fallback, exact error
// codes; every build signed with the Satlok key (never the debug key).
import 'dart:io';

import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:google_sign_in/google_sign_in.dart';
import 'package:granthprabandhan/services/firebase_bridge.dart';

import 'helpers.dart';

const acc = AccountInfo(email: 'a@gmail.com', name: 'A');

void main() {
  late FirebaseBridge fb;
  setUp(() async {
    await setUpApp();
    fb = FirebaseBridge.I;
    await fb.debugSetAccount(null);
  });
  tearDown(() async {
    fb.debugGoogleStep = null;
    await fb.debugSetAccount(null);
  });

  test('serverClientId defaults to the web client id', () {
    expect(kGoogleWebClientId, '386256348529-55gsprsn906i00e6726tu1gdo253kipv.apps.googleusercontent.com');
  });

  test('first try works: picker → credential', () async {
    fb.debugGoogleStep = (s) async => s == 'authenticate' ? 'id' : acc;
    expect(await fb.signIn(), isNull);
    expect(fb.debugGoogleCalls, ['authenticate', 'credential']);
    expect(fb.signedIn, isTrue);
  });

  for (final (name, ex) in [
    ('canceled', const GoogleSignInException(code: GoogleSignInExceptionCode.canceled)),
    ('[16] reauth', const GoogleSignInException(code: GoogleSignInExceptionCode.unknownError, description: '[16] Account reauth failed.')),
  ]) {
    test('$name → signOut + disconnect → retry once succeeds', () async {
      var n = 0;
      fb.debugGoogleStep = (s) async {
        if (s == 'authenticate' && n++ == 0) throw ex;
        return s == 'authenticate' ? 'id' : acc;
      };
      expect(await fb.signIn(), isNull);
      expect(fb.debugGoogleCalls, ['authenticate', 'signOut', 'disconnect', 'authenticate', 'credential']);
      expect(fb.signedIn, isTrue);
    });
  }

  test('retry fails too → FirebaseAuth.signInWithProvider fallback', () async {
    fb.debugGoogleStep = (s) async {
      if (s == 'authenticate') throw const GoogleSignInException(code: GoogleSignInExceptionCode.canceled);
      return acc;
    };
    expect(await fb.signIn(), isNull);
    expect(fb.debugGoogleCalls, ['authenticate', 'signOut', 'disconnect', 'authenticate', 'provider']);
    expect(fb.signedIn, isTrue);
  });

  test('everything fails → the exact codes are shown', () async {
    fb.debugGoogleStep = (s) async {
      if (s == 'authenticate') throw const GoogleSignInException(code: GoogleSignInExceptionCode.canceled, description: '[16] Account reauth failed.');
      if (s == 'provider') throw FirebaseAuthException(code: 'web-context-canceled');
      return null;
    };
    final e = await fb.signIn();
    expect(e, contains('canceled: [16] Account reauth failed.'));
    expect(e, contains('provider: web-context-canceled'));
    expect(fb.error, e);
    expect(fb.signedIn, isFalse);
  });

  test('other codes are not retried and show their code', () async {
    fb.debugGoogleStep = (s) async => throw const GoogleSignInException(code: GoogleSignInExceptionCode.clientConfigurationError, description: 'bad sha');
    final e = await fb.signIn();
    expect(e, contains('clientConfigurationError: bad sha'));
    expect(fb.debugGoogleCalls, ['authenticate']);
  });

  test('gradle: debug and release use the Satlok key; no key.properties → every build fails', () {
    final g = File('android/app/build.gradle.kts').readAsStringSync();
    final debug = RegExp(r'debug \{[^}]*signingConfigs\.getByName\("release"\)').hasMatch(g);
    expect(debug, isTrue);
    expect(g, contains('throw GradleException'));
    for (final t in ['assemble', 'bundle', 'Debug', 'Release']) {
      expect(g, contains('"$t"'));
    }
    expect(g, isNot(contains('getByName("debug")')));
  });
}
