import 'dart:async';

import 'package:app_links/app_links.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'screens/home_shell.dart';
import 'screens/login_screen.dart';
import 'screens/splash_screen.dart';
import 'services/catalog_store.dart';
import 'services/device_profile.dart';
import 'services/file_actions.dart';
import 'services/analytics.dart';
import 'services/presence.dart';
import 'services/firebase_bridge.dart';
import 'services/remote_config.dart';
import 'services/shelves.dart';
import 'services/events.dart';
import 'services/storage.dart';
import 'services/support.dart';
import 'state/router.dart';
import 'state/ui_prefs.dart';
import 'theme/colors.dart';
import 'widgets/zoom.dart';
import 'widgets/bounded_scroll.dart';
import 'util/log.dart';
import 'ai/chat_controller.dart';

void main() {
  runZonedGuarded<Future<void>>(
    () async {
      WidgetsFlutterBinding.ensureInitialized();
      _installErrorHandlers();
      Future<void> boot = Future<void>.value();
      // Every init step is guarded: an exception or a hang here must never stop runApp,
      // otherwise the phone stays on the native launch screen forever.
      try {
        await SystemChrome.setPreferredOrientations([DeviceOrientation.portraitUp]).timeout(const Duration(seconds: 2));
      } catch (e) {
        log('init: orientation: $e');
      }
      try {
        await Store.I.init().timeout(const Duration(seconds: 6));
      } catch (e) {
        log('init: store: $e');
      }
      // Not awaited for long: both only tune / tidy, the app works without them.
      try {
        await Future.wait([DeviceProfile.load(), FileActions.cleanupPartials()]).timeout(const Duration(seconds: 2));
      } catch (e) {
        log('init: profile/cleanup: $e');
      }
      try {
        await Shelves.load().timeout(const Duration(seconds: 2));
      } catch (e) {
        log('init: structure: $e');
      }
      try {
        await RemoteConfig.I.load().timeout(const Duration(seconds: 2));
      } catch (e) {
        log('init: remote config: $e');
      }
      try {
        AppNav.onEnterAi = () => ChatController.I.enterFresh();
        SupportService.uidOf = () => FirebaseBridge.I.uid;
        AppNav.I.restore();
      } catch (e) {
        log('init: restore: $e');
      }
      try {
        EventLog.I.log('app_open', 'app');
      } catch (_) {}
      try {
        // The catalog loads in the background; the splash never waits for the network.
        boot = CatalogStore.I.boot().catchError((Object e, StackTrace st) => log('boot: $e\n$st'));
      } catch (e) {
        log('init: boot: $e');
      }
      // Firebase (analytics, crashlytics, optional login, push topics): never blocks the app.
      Analytics.I.named('app_open'); // CONTRACT §6.2: once per cold start, to /events and, once Firebase is up, as the optional GA4 app_open
      unawaited(FirebaseBridge.I.init().then((_) => Analytics.forward?.call('app_open', const {})).catchError((Object e) => log('init: firebase: $e')));
      runApp(GranthApp(ready: boot));
      RemoteConfig.I.booted = true; // a config file read after its 2 s boot slot redraws the grids
      // Anonymous usage counts start after the first frame; they never delay the app.
      WidgetsBinding.instance.addPostFrameCallback((_) {
        Analytics.I.start();
        Presence.I.start(); // CONTRACT §19.1 live presence
      });
    },
    (error, stack) {
      log('Uncaught: $error\n$stack');
      FirebaseBridge.I.recordError(error, stack); // no-op until Firebase is up
    },
  );
}

/// Crash safety. Before Firebase is up errors are only logged (debug builds); once it is up,
/// [FirebaseBridge.init] chains Crashlytics onto both handlers, and zone errors (runZonedGuarded)
/// go to Crashlytics through [FirebaseBridge.recordError].
void _installErrorHandlers() {
  FlutterError.onError = (details) {
    // Release: nothing on the console; Crashlytics is chained on by FirebaseBridge.init.
    if (!kReleaseMode) FlutterError.presentError(details);
  };
  PlatformDispatcher.instance.onError = (error, stack) {
    log('Platform error: $error\n$stack');
    return true; // handled; FirebaseBridge.init chains Crashlytics (fatal) in front of this
  };
  if (kReleaseMode) ErrorWidget.builder = releaseErrorWidget;
}

/// Release-mode stand-in for a widget that failed to build: a small, calm note instead of a
/// red/grey box. Never shows the error text.
Widget releaseErrorWidget(FlutterErrorDetails details) => const Directionality(
  textDirection: TextDirection.ltr,
  child: Padding(
    padding: EdgeInsets.all(12),
    child: Center(
      child: Text(
        'यह भाग अभी नहीं दिख पा रहा है।',
        key: ValueKey('release-error-widget'),
        textAlign: TextAlign.center,
        style: TextStyle(fontSize: 13, color: Color(0xFF8A6A4A), decoration: TextDecoration.none),
      ),
    ),
  ),
);

class GranthApp extends StatefulWidget {
  const GranthApp({super.key, this.ready, this.splash = true, this.links = true, this.linkStream, this.initialLink});
  final Future<void>? ready;
  final bool splash;
  final bool links;

  /// For tests: replaces `AppLinks().uriLinkStream` (warm-start links).
  final Stream<Uri>? linkStream;

  /// For tests: replaces `AppLinks().getInitialLink()` (the link that cold-started the app).
  final Future<Uri?>? initialLink;
  @override
  State<GranthApp> createState() => _GranthAppState();
}

class _GranthAppState extends State<GranthApp> with WidgetsBindingObserver {
  StreamSubscription<Uri>? _links;
  String _lastLink = '';
  int _lastLinkAt = 0;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    // Stored text size / keep-screen-on (settings are loaded by now).
    UiPrefs.I.refresh(start: true);
    if (widget.links) _listenLinks();
  }

  /// Shared links: the one that started the app (cold start) and any opened later while
  /// it runs (warm start, delivered through `onNewIntent`). Both go through [_open]; the
  /// 5 s de-dup drops the copy app_links also replays on its stream.
  void _listenLinks() {
    try {
      final stream = widget.linkStream ?? AppLinks().uriLinkStream;
      _links = stream.listen(_safeOpen, onError: (_) {});
    } catch (e) {
      log('links: stream: $e');
    }
    try {
      final first = widget.initialLink ?? AppLinks().getInitialLink();
      first
          .then((u) {
            if (u != null) _safeOpen(u);
          })
          .catchError((Object e) => log('links: initial: $e'));
    } catch (e) {
      log('links: initial: $e');
    }
  }

  void _safeOpen(Uri u) {
    try {
      _open(u);
    } catch (e, st) {
      // A malformed link must never break the app: fall back to the dashboard.
      log('links: $u: $e\n$st');
      AppNav.I.openLink('#/dashboard');
    }
  }

  /// `__granthOpenLink` with the same 5 s de-duplication.
  void _open(Uri u) {
    final h = hashFromLink(u);
    if (h == null) return;
    final now = DateTime.now().millisecondsSinceEpoch;
    if (_lastLink == h && now - _lastLinkAt < 5000) return;
    _lastLink = h;
    _lastLinkAt = now;
    AppNav.I.openLink(h);
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      CatalogStore.I.onResume();
      // The home screen always handles Back itself (inner screens go up a level; the root asks
      // before exiting). A new MainActivity (reopened from recents, a notification tap, after the
      // photo highlighter) starts without that flag, and Android would then close the app on
      // Back — so say it again on every resume.
      SystemNavigator.setFrameworkHandlesBack(true).catchError((Object _) {});
    }
    if (state == AppLifecycleState.paused || state == AppLifecycleState.hidden) CatalogStore.I.onPause();
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _links?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => ListenableBuilder(
    // the hidden iOS theme switches at once
    listenable: UiPrefs.I,
    builder: (context, _) => MaterialApp(
      title: 'ग्रंथ प्रबंधन',
      debugShowCheckedModeBanner: false,
      scrollBehavior: const BoundedScrollBehavior(),
      theme: buildTheme(ios: UiPrefs.I.theme == 'ios'),
      builder: (context, child) => ValueListenableBuilder<double>(
        // Settings → अक्षर का आकार: a factor on the phone's own text size, same 1.3 cap.
        valueListenable: UiPrefs.I.textFactor,
        builder: (context, f, zoomed) {
          final phone = MediaQuery.textScalerOf(context);
          final scaler = f == 1.0 ? phone.clamp(maxScaleFactor: 1.3) : TextScaler.linear(phone.scale(100) / 100 * f).clamp(minScaleFactor: 0.8, maxScaleFactor: 1.3);
          return MediaQuery(
            data: MediaQuery.of(context).copyWith(textScaler: scaler),
            child: zoomed!,
          );
        },
        // Whole-app pinch zoom like the original WebView (viewport maximum-scale=5).
        child: AppZoom(child: child!),
      ),
      home: widget.splash
          ? AnimatedSplash(
              ready: widget.ready,
              child: const LoginGate(child: HomeShell()),
            )
          : const LoginGate(child: HomeShell()),
    ),
  );
}
