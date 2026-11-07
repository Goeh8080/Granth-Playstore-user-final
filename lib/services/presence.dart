/// Round-3 (CONTRACT §19.1): live presence. `POST {kAdminBase}/presence/heartbeat` when the app
/// comes to the foreground, every 20 s while it stays there and on every screen change;
/// `POST /presence/leave` when it goes to the background. Nothing is sent in the background.
/// Fire-and-forget: any status or network error is ignored and never retried (the next tick is
/// the retry). The app key is sent as `X-App-Key` and never logged.
library;

import 'dart:async';
import 'dart:convert';
import 'dart:io' show Platform;

import 'package:dio/dio.dart';
import 'package:flutter/widgets.dart';

import '../config.dart';
import '../state/router.dart';
import 'analytics.dart';
import 'firebase_bridge.dart';

class Presence with WidgetsBindingObserver {
  Presence({Dio? dio, String? base, this.appKey = kAppKey, String Function()? iid, String? Function()? uid, String Function()? screen, Future<String?> Function(bool forceRefresh)? token, bool? enabled})
    : _dio = dio ?? Dio(BaseOptions(connectTimeout: const Duration(seconds: 8), receiveTimeout: const Duration(seconds: 8))),
      base = (base ?? kAdminBase).replaceAll(RegExp(r'/+$'), ''),
      _iid = iid ?? (() => Analytics.I.iid),
      _uid = uid ?? (() => FirebaseBridge.I.uid),
      _screen = screen ?? (() => Analytics.screenName(AppNav.I.route)),
      _token = token ?? ((force) => FirebaseBridge.I.googleIdToken(forceRefresh: force)),
      enabled = enabled ?? !Platform.environment.containsKey('FLUTTER_TEST');

  static Presence I = Presence();

  static const interval = Duration(seconds: 20);

  final Dio _dio;
  final String base;
  final String appKey;
  final String Function() _iid;
  final String? Function() _uid;
  final String Function() _screen;
  final bool enabled;
  final Future<String?> Function(bool forceRefresh) _token;
  bool _forceRefresh = false, _refreshAttempted = false, _signingOut = false;
  Future<void> _tail = Future<void>.value();
  bool _heartbeatPending = false;

  /// Drain prior heartbeats, then close the verified session before credentials vanish.
  Future<void> beforeSignOut() async {
    if (!enabled) return;
    _signingOut = true;
    await _tail;
    await _send('leave');
  }

  void afterSignOut() {
    _signingOut = false;
    if (_foreground) _beat();
  }

  bool _started = false;
  bool _foreground = false;
  Timer? _timer;
  String? _lastScreen;

  bool get foreground => _foreground;

  /// Called once after the first frame (the app is in the foreground then).
  void start() {
    if (_started) return;
    _started = true;
    try {
      WidgetsBinding.instance.addObserver(this);
      AppNav.I.addListener(_onNav);
    } catch (_) {}
    _enterForeground();
  }

  void stop() {
    if (!_started) return;
    _started = false;
    try {
      WidgetsBinding.instance.removeObserver(this);
      AppNav.I.removeListener(_onNav);
    } catch (_) {}
    _timer?.cancel();
    _timer = null;
    _foreground = false;
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    switch (state) {
      case AppLifecycleState.resumed:
        _enterForeground();
      case AppLifecycleState.paused || AppLifecycleState.hidden || AppLifecycleState.detached:
        _leave();
      case AppLifecycleState.inactive:
        break; // a dialog / the notification shade: still on screen
    }
  }

  void _enterForeground() {
    if (_foreground) return;
    _foreground = true;
    _timer?.cancel();
    _timer = Timer.periodic(interval, (_) => _beat());
    _beat();
  }

  void _leave() {
    if (!_foreground) return;
    _foreground = false;
    _timer?.cancel();
    _timer = null;
    unawaited(_post('leave'));
  }

  void _onNav() {
    if (!_foreground) return;
    if (_safeScreen() == _lastScreen) return;
    _beat();
  }

  void _beat() {
    if (_foreground) unawaited(_post('heartbeat'));
  }

  String? _safeScreen() {
    try {
      final s = _screen().toLowerCase();
      return RegExp(r'^[a-z0-9_-]{1,24}$').hasMatch(s) ? s : null;
    } catch (_) {
      return null;
    }
  }

  /// The JSON body (CONTRACT §19.1). Invalid optional fields are left out.
  @visibleForTesting
  Map<String, String>? body() {
    final iid = _iid();
    if (!RegExp(r'^[0-9a-f]{32}$').hasMatch(iid)) return null;
    String? uid;
    try {
      uid = _uid();
    } catch (_) {}
    final scr = _safeScreen();
    return {
      'install_id': iid,
      if (uid != null && RegExp(r'^[A-Za-z0-9_-]{1,128}$').hasMatch(uid)) 'uid': uid,
      'screen': ?scr,
      if (RegExp(r'^[0-9A-Za-z.+_-]{1,24}$').hasMatch(kAppVersion)) 'app_version': kAppVersion,
    };
  }

  Future<void> _post(String kind) {
    if (!enabled || _signingOut || (kind == 'heartbeat' && _heartbeatPending)) return Future<void>.value();
    if (kind == 'heartbeat') _heartbeatPending = true;
    final next = _tail.then((_) => _send(kind)).whenComplete(() {
      if (kind == 'heartbeat') _heartbeatPending = false;
    });
    _tail = next;
    return next;
  }

  Future<void> _send(String kind) async {
    if (!enabled) return;
    try {
      final b = body();
      if (b == null) return;
      final force = _forceRefresh;
      _forceRefresh = false;
      final token = await _token(force).timeout(const Duration(seconds: 5));
      if (token != null && token.isNotEmpty) b['id_token'] = token;
      if (utf8.encode(jsonEncode(b)).length > 6144) b.remove('id_token');
      if (kind == 'heartbeat') _lastScreen = b['screen'];
      final response = await _dio.post<String>(
        '$base/presence/$kind',
        data: jsonEncode(b),
        options: Options(
          contentType: 'application/json',
          headers: {if (appKey.trim().isNotEmpty) 'X-App-Key': appKey.trim()},
          responseType: ResponseType.plain,
          validateStatus: (_) => true, // 204 ok; 4xx/5xx ignored, no retry
        ),
      );
      final identity = response.headers.value('x-granth-identity');
      if (identity == 'verified' || identity == 'none') _refreshAttempted = false;
      if ((identity == 'expired' || identity == 'invalid') && !_refreshAttempted) {
        _refreshAttempted = true;
        _forceRefresh = true; // next tick only; no immediate retry or refresh loop
      }
    } catch (_) {
      // Offline / timeout: skip; the next heartbeat tick tries again.
    }
  }
}
