/// Firebase (project granth-management): Analytics, Crashlytics, optional Google sign-in and
/// FCM topic subscriptions. Everything is optional and guarded: when Firebase can not start
/// (tests, no Play services, offline first run) the app works exactly as before.
library;

import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:firebase_analytics/firebase_analytics.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_crashlytics/firebase_crashlytics.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter/foundation.dart';
import 'package:google_sign_in/google_sign_in.dart';

import '../ai/v2_drafts.dart';
import '../state/router.dart';
import '../state/toast.dart';
import 'analytics.dart';
import 'remote_config.dart';
import 'presence.dart';
import 'storage.dart';
import 'support.dart';
import '../util/log.dart';

/// Optional Web OAuth client id (when google-services.json carries none).
const String kGoogleWebClientId = String.fromEnvironment('GOOGLE_WEB_CLIENT_ID', defaultValue: '386256348529-55gsprsn906i00e6726tu1gdo253kipv.apps.googleusercontent.com');

/// FCM topics (provisional until CONTRACT.md names them; see round14_backend_needs.md).
/// CONTRACT §6.3 FCM topics. `all` is always on (unless `flags.notifications_enabled` is false).
class PushTopics {
  static const all = 'all';
  static const newPraman = 'new_praman';
  static const newTopic = 'new_topic';
  static const trending = 'trending';
  static const daily = 'daily';
  static const toggles = [daily, newPraman, newTopic, trending];
  static const every = [all, ...toggles];
}

class AccountInfo {
  const AccountInfo({required this.email, this.name = '', this.photo = ''});
  final String email, name, photo;
  Map<String, String> toJson() => {'email': email, 'name': name, 'photo': photo};
  static AccountInfo? fromJson(Object? j) =>
      j is Map && j['email'] is String && (j['email'] as String).isNotEmpty ? AccountInfo(email: j['email'] as String, name: '${j['name'] ?? ''}', photo: '${j['photo'] ?? ''}') : null;
}

class FirebaseBridge extends ChangeNotifier {
  FirebaseBridge._();
  static final FirebaseBridge I = FirebaseBridge._();

  static const kAccount = 'granth-account';
  static const kPush = 'granth-push-topics';

  bool ready = false;
  bool busy = false;
  String? error;

  /// Round-2: what the sign-in is doing right now (shown under the button), e.g. "Google खाता…".
  String? stage;
  AccountInfo? _account;

  static bool get _supported => !kIsWeb && Platform.isAndroid && !Platform.environment.containsKey('FLUTTER_TEST');

  AccountInfo? get account => _account ??= AccountInfo.fromJson(_decode(Store.I.getString(kAccount)));
  bool get signedIn => account != null;

  /// The Firebase uid while signed in (for presence); null when signed out or Firebase is off.
  String? get uid {
    if (!signedIn || !ready) return null;
    try {
      return FirebaseAuth.instance.currentUser?.uid;
    } catch (_) {
      return null;
    }
  }

  static Object? _decode(String? s) {
    try {
      return s == null ? null : jsonDecode(s);
    } catch (_) {
      return null;
    }
  }

  Future<void> init() async {
    if (!_supported || ready) return;
    try {
      await Firebase.initializeApp().timeout(const Duration(seconds: 4));
      ready = true;
    } catch (e) {
      log('firebase: init: $e');
      return;
    }
    try {
      await FirebaseCrashlytics.instance.setCrashlyticsCollectionEnabled(!kDebugMode);
      final prev = FlutterError.onError;
      FlutterError.onError = (d) {
        prev?.call(d);
        FirebaseCrashlytics.instance.recordFlutterError(d);
      };
      final prevP = PlatformDispatcher.instance.onError;
      PlatformDispatcher.instance.onError = (e, st) {
        FirebaseCrashlytics.instance.recordError(e, st, fatal: true);
        return prevP?.call(e, st) ?? true;
      };
    } catch (e) {
      log('firebase: crashlytics: $e');
    }
    Analytics.screenForward = (screen) => unawaited(FirebaseAnalytics.instance.logScreenView(screenName: screen).catchError((_) {}));
    Analytics.forward = (name, params) => unawaited(FirebaseAnalytics.instance.logEvent(name: name, parameters: params).catchError((_) {}));
    // The signed-in Firebase user wins over the cache (e.g. revoked on another device).
    try {
      final u = FirebaseAuth.instance.currentUser;
      if (u == null && _account != null) await _setAccount(null);
      if (u != null && u.email != null) await _setAccount(AccountInfo(email: u.email!, name: u.displayName ?? '', photo: u.photoURL ?? ''));
    } catch (_) {}
    unawaited(syncTopics());
    unawaited(_initMessaging());
    notifyListeners();
  }

  /// Records a non-fatal error (no-op without Firebase).
  void recordError(Object e, StackTrace? st) {
    if (!ready) return;
    try {
      FirebaseCrashlytics.instance.recordError(e, st);
    } catch (_) {}
  }

  Future<void> _setAccount(AccountInfo? a) async {
    _account = a;
    if (a == null) {
      await Store.I.remove(kAccount);
    } else {
      await Store.I.setString(kAccount, jsonEncode(a.toJson()));
    }
    notifyListeners();
  }

  /// Google sign-in (optional). Returns null on success, or a Hindi message.
  Future<void>? _gInit;

  /// Tests: stands in for the Google account picker + Firebase credential sign-in.
  @visibleForTesting
  Future<AccountInfo> Function()? debugAuthenticate;

  /// Tests: stands in for each real Google/Firebase step of [signIn] ('authenticate' → id token,
  /// 'credential' / 'provider' → AccountInfo, 'signOut', 'disconnect'); calls go to [debugGoogleCalls].
  @visibleForTesting
  Future<Object?> Function(String step)? debugGoogleStep;
  @visibleForTesting
  final List<String> debugGoogleCalls = [];

  /// Tests: stand-ins for FirebaseAuth.signOut / GoogleSignIn.signOut / disconnect; each call
  /// is recorded in [debugSignOutCalls].
  @visibleForTesting
  Future<void> Function(String step)? debugSignOutStep;
  @visibleForTesting
  final List<String> debugSignOutCalls = [];

  Future<void> _gReady() => _gInit ??= GoogleSignIn.instance.initialize(serverClientId: kGoogleWebClientId.isEmpty ? null : kGoogleWebClientId).catchError((Object e) {
    _gInit = null;
    throw e;
  });

  /// Bumped by [signOut]/[deleteAccount]: a sign-in that finishes after them is ignored.
  int _gen = 0;

  Future<String?> signIn() async {
    if (busy) return null;
    final gen = ++_gen;
    if (debugAuthenticate != null) {
      busy = true;
      error = null;
      try {
        final a = await debugAuthenticate!();
        if (gen != _gen) return null; // logged out meanwhile
        await _setAccount(a);
        return null;
      } catch (e) {
        return error = 'Google लॉगिन नहीं हो सका ($e)।';
      } finally {
        busy = false;
        stage = null;
        notifyListeners();
      }
    }
    final fake = debugGoogleStep;
    if (fake == null && !ready) {
      log('sign-in: firebase not ready (google-services.json missing from build?)');
      return error = 'लॉगिन अभी उपलब्ध नहीं है (Firebase चालू नहीं)।';
    }
    busy = true;
    error = null;
    _stage('Google से जुड़ रहे हैं…');
    debugGoogleCalls.clear();
    Future<T> step<T>(String name, Future<T> Function() real) async {
      debugGoogleCalls.add(name);
      return fake != null ? (await fake(name)) as T : real();
    }

    // Picker → id token → Firebase credential sign-in (also creates the user on first sign-in).
    Future<AccountInfo> viaPicker() async {
      final idToken = await step<String?>('authenticate', () async {
        final g = GoogleSignIn.instance;
        // google_sign_in 7.x: initialize() must be called exactly once per app run.
        await _gReady();
        if (!g.supportsAuthenticate()) throw StateError('authenticate-unsupported');
        _stage('Google खाता चुनें…');
        final acc = await g.authenticate();
        _stage('खाता मिला, लॉगिन हो रहा है…');
        return acc.authentication.idToken;
      });
      if (idToken == null || idToken.isEmpty) throw StateError('no-id-token');
      return step<AccountInfo>('credential', () async {
        final cred = await FirebaseAuth.instance.signInWithCredential(GoogleAuthProvider.credential(idToken: idToken)).timeout(const Duration(seconds: 30));
        final u = cred.user;
        if (u == null) throw StateError('no-firebase-user');
        return AccountInfo(email: u.email ?? '', name: u.displayName ?? '', photo: u.photoURL ?? '');
      });
    }

    String code(GoogleSignInException e) {
      final d = (e.description ?? '').trim();
      return '${e.code.name}${d.isEmpty ? '' : ': $d'}';
    }

    try {
      AccountInfo a;
      try {
        a = await viaPicker();
      } on GoogleSignInException catch (e) {
        final first = code(e);
        log('google sign-in failed: $first');
        recordError(e, StackTrace.current);
        // "canceled" / "[16] Account reauth failed": a stale cached Google account. Clear it, retry once.
        final stale = e.code == GoogleSignInExceptionCode.canceled || first.contains('[16]') || first.toLowerCase().contains('reauth');
        if (!stale) return error = 'Google लॉगिन नहीं हो सका ($first)। कृपया इंटरनेट जाँचें और दोबारा प्रयास करें।';
        for (final n in ['signOut', 'disconnect']) {
          try {
            await step<void>(n, () async => n == 'signOut' ? GoogleSignIn.instance.signOut() : GoogleSignIn.instance.disconnect());
          } catch (x) {
            log('sign-in retry: $n: $x');
          }
        }
        _stage('दोबारा कोशिश हो रही है…');
        try {
          a = await viaPicker();
        } on GoogleSignInException catch (e2) {
          final second = code(e2);
          log('google sign-in retry failed: $second; trying Firebase provider sign-in');
          _stage('दूसरे तरीके से लॉगिन हो रहा है…');
          try {
            a = await step<AccountInfo>('provider', () async {
              final cred = await FirebaseAuth.instance.signInWithProvider(GoogleAuthProvider());
              final u = cred.user;
              if (u == null) throw StateError('no-firebase-user');
              return AccountInfo(email: u.email ?? '', name: u.displayName ?? '', photo: u.photoURL ?? '');
            });
          } on FirebaseAuthException catch (e3) {
            return error = 'Google लॉगिन नहीं हो सका ($first → $second → provider: ${e3.code})। दोबारा प्रयास करें।';
          } catch (e3) {
            return error = 'Google लॉगिन नहीं हो सका ($first → $second → provider: $e3)। दोबारा प्रयास करें।';
          }
        }
      }
      if (gen != _gen) {
        // Logged out while the picker / token exchange was running: don't log back in.
        if (fake == null) unawaited(FirebaseAuth.instance.signOut().catchError((Object _) {}));
        return null;
      }
      await _setAccount(a);
      return null;
    } on FirebaseAuthException catch (e) {
      log('firebase auth sign-in failed: code=${e.code} msg=${e.message}');
      recordError(e, StackTrace.current);
      return error = 'लॉगिन नहीं हो सका (${e.code})। कृपया दोबारा प्रयास करें।';
    } catch (e) {
      log('sign-in failed: $e');
      recordError(e, StackTrace.current);
      return error = 'Google लॉगिन नहीं हो सका ($e)।';
    } finally {
      busy = false;
      stage = null;
      notifyListeners();
    }
  }

  void _stage(String s) {
    stage = s;
    notifyListeners();
  }

  /// Logout: Firebase and Google are both signed out (each step on its own, so one failure
  /// never skips the other). If Google's signOut fails, disconnect clears the cached account so
  /// the next "Sign in with Google" shows the account picker again (another account works too).
  /// The local account is cleared and the login gate shows again.
  Future<void> signOut() async {
    _gen++; // an in-flight sign-in result is dropped
    await Presence.I.beforeSignOut();
    Future<bool> step(String name, Future<void> Function() real) async {
      debugSignOutCalls.add(name);
      try {
        await (debugSignOutStep != null ? debugSignOutStep!(name) : real());
        return true;
      } catch (e) {
        log('sign-out: $name: $e');
        return false;
      }
    }

    if (ready || debugSignOutStep != null) {
      await step('firebase', () => FirebaseAuth.instance.signOut());
      final ok = await step('google', () async {
        await _gReady();
        await GoogleSignIn.instance.signOut();
      });
      if (!ok) {
        await step('disconnect', () async {
          await _gReady();
          await GoogleSignIn.instance.disconnect();
        });
      }
    }
    busy = false;
    error = null;
    stage = null;
    await Store.I.remove(Store.kLoginSeen); // the login gate shows again
    // t368: the folders/list choice stays after logout (asked only once ever; Settings changes it).
    await _setAccount(null);
    Presence.I.afterSignOut();
  }

  /// Tests: stands in for each delete step ('server', 'firebase', 'reauth', 'disconnect');
  /// throw `FirebaseAuthException(code: 'requires-recent-login')` from 'firebase' to test reauth.
  @visibleForTesting
  Future<void> Function(String step)? debugDeleteStep;
  @visibleForTesting
  final List<String> debugDeleteCalls = [];

  /// Test hook: the id token sent to /account/delete when [debugDeleteStep] is set.
  String? debugIdToken = 'tok';

  /// Play account deletion ("खाता हटाएँ"): server data (POST /account/delete; a 404 while
  /// the endpoint isn't live is fine), then the Firebase user (re-authenticating with Google
  /// when Firebase wants a recent login), then Google disconnect (revokes the app), then the
  /// local account / tickets are cleared and the login gate shows. Returns null or a Hindi error.
  Future<String?> deleteAccount() async {
    if (debugDeleteStep == null && !ready) return 'खाता अभी हटाया नहीं जा सकता (Firebase चालू नहीं)।';
    final deletingUid = uid;
    _gen++;
    busy = true;
    error = null;
    _stage('खाता हटाया जा रहा है…');
    Future<void> run(String name, Future<void> Function() real) {
      debugDeleteCalls.add(name);
      return debugDeleteStep != null ? debugDeleteStep!(name) : real();
    }

    try {
      // §22: fresh token right before the call; on 200 the server already deleted the Auth user.
      String? tok;
      try {
        tok = debugDeleteStep != null ? debugIdToken : (ready ? await FirebaseAuth.instance.currentUser?.getIdToken(true) : null);
      } catch (e) {
        log('account delete: token: $e');
      }
      debugDeleteCalls.add('server');
      final r = await SupportService.I.deleteAccountData(tok);
      if (r.status == 404) {
        // Old server without §22: delete the Auth user from the app.
        Future<void> fbDelete() => run('firebase', () async => FirebaseAuth.instance.currentUser?.delete());
        try {
          await fbDelete();
        } on FirebaseAuthException catch (e) {
          if (e.code != 'requires-recent-login') rethrow;
          await run('reauth', () async {
            await _gReady();
            final acc = await GoogleSignIn.instance.authenticate();
            final t = acc.authentication.idToken;
            if (t == null || t.isEmpty) throw StateError('no-id-token');
            await FirebaseAuth.instance.currentUser?.reauthenticateWithCredential(GoogleAuthProvider.credential(idToken: t));
          });
          await fbDelete();
        }
      } else if (r.status != 200) {
        log('account delete: server ${r.status} ${r.code} data_deleted=${r.dataDeleted}');
        return error = SupportService.deleteErrorText(r.status, r.code, dataDeleted: r.dataDeleted);
      }
      try {
        await run('disconnect', () async {
          await _gReady();
          await GoogleSignIn.instance.disconnect();
        });
      } catch (e) {
        log('account delete: disconnect: $e');
      }
      try {
        if (debugDeleteStep == null) await FirebaseAuth.instance.signOut();
      } catch (_) {}
      if (deletingUid != null) await AiV2DraftStore.I.clearOwner(deletingUid);
      SupportService.I.clearLocal();
      busy = false;
      stage = null;
      await Store.I.remove(Store.kLoginSeen);
      // the folders/list choice is a device preference: kept (asked only once ever)
      await _setAccount(null);
      return null;
    } on GoogleSignInException catch (e) {
      log('account delete: reauth: ${e.code.name}');
      return error = 'खाता हटाने के लिए Google से दोबारा पुष्टि ज़रूरी है। कृपया फिर कोशिश करें।';
    } catch (e) {
      log('account delete failed: $e');
      recordError(e, StackTrace.current);
      return error = 'खाता हटाया नहीं जा सका ($e)। कृपया फिर कोशिश करें।';
    } finally {
      busy = false;
      stage = null;
      notifyListeners();
    }
  }

  /// A fresh Firebase ID token (for the server's Firebase verify), or null.
  Future<String?> idToken() async {
    try {
      return ready ? await FirebaseAuth.instance.currentUser?.getIdToken() : null;
    } catch (_) {
      return null;
    }
  }

  /// Presence accepts only a signed-in Google Firebase principal, never an OAuth token.
  Future<String?> googleIdToken({bool forceRefresh = false}) async {
    try {
      if (!ready || !signedIn) return null;
      final user = FirebaseAuth.instance.currentUser;
      if (user == null || !user.providerData.any((p) => p.providerId == 'google.com')) return null;
      final result = await user.getIdTokenResult(forceRefresh);
      return result.signInProvider == 'google.com' ? result.token : null;
    } catch (_) {
      return null;
    }
  }

  // ------------------------------------------------------------------ push topics
  Set<String> get topics {
    final j = _decode(Store.I.getString(kPush));
    if (j is List) {
      return {
        PushTopics.all,
        for (final e in j)
          if (e is String && PushTopics.every.contains(e)) e,
      };
    }
    return {...PushTopics.every};
  }

  bool subscribed(String t) => topics.contains(t);

  Future<void> setTopic(String t, bool on) async {
    final s = topics;
    on ? s.add(t) : s.remove(t);
    await Store.I.setString(kPush, jsonEncode(s.toList()..sort()));
    notifyListeners();
    if (!ready || !RemoteConfig.I.notificationsEnabled) return;
    try {
      if (on) {
        await FirebaseMessaging.instance.requestPermission();
        await FirebaseMessaging.instance.subscribeToTopic(t);
      } else {
        await FirebaseMessaging.instance.unsubscribeFromTopic(t);
      }
    } catch (e) {
      log('fcm: $t: $e');
    }
  }

  bool? _pushOn;

  /// Subscribes to the chosen topics, or unsubscribes from every topic when
  /// `flags.notifications_enabled === false` (CONTRACT §6.1). Re-run on config change.
  Future<void> syncTopics() async {
    if (!ready) return;
    final on = RemoteConfig.I.notificationsEnabled;
    _pushOn = on;
    try {
      final m = FirebaseMessaging.instance;
      final want = on ? topics : <String>{};
      for (final t in PushTopics.every) {
        want.contains(t) ? await m.subscribeToTopic(t) : await m.unsubscribeFromTopic(t);
      }
    } catch (e) {
      log('fcm: sync: $e');
    }
  }

  void _onConfig() {
    if (ready && _pushOn != RemoteConfig.I.notificationsEnabled) unawaited(syncTopics());
  }

  /// `data {topic, id?}` → the screen to open (CONTRACT §6.3), or null.
  static String? linkFor(Map<String, dynamic> data) {
    final id = '${data['id'] ?? ''}'.trim();
    if (id.isEmpty || !RegExp(r'^[A-Za-z0-9_-]{1,40}$').hasMatch(id)) return null;
    final kind = '${data['kind'] ?? data['type'] ?? ''}';
    if (kind == 'granth') return '#/pramans?granth=$id';
    return switch ('${data['topic'] ?? ''}') {
      PushTopics.newTopic || PushTopics.trending => '#/pramans?topic=$id',
      _ => kind == 'topic' ? '#/pramans?topic=$id' : '#/pramans?id=$id',
    };
  }

  void _openMessage(RemoteMessage m) {
    final l = linkFor(m.data);
    if (l != null) AppNav.I.openLink(l);
  }

  Future<void> _initMessaging() async {
    RemoteConfig.I.addListener(_onConfig);
    try {
      FirebaseMessaging.onMessageOpenedApp.listen(_openMessage);
      FirebaseMessaging.onMessage.listen((m) {
        final n = m.notification;
        if (n != null && (n.title ?? n.body) != null) Toast.show([n.title, n.body].whereType<String>().join(' · '));
      });
      final first = await FirebaseMessaging.instance.getInitialMessage();
      if (first != null) _openMessage(first);
    } catch (e) {
      log('fcm: init: $e');
    }
  }

  @visibleForTesting
  Future<void> debugSetAccount(AccountInfo? a) => _setAccount(a);

  /// For tests: a cold start (the account is read again from the saved settings).
  @visibleForTesting
  void debugForgetMemory() => _account = null;
}
