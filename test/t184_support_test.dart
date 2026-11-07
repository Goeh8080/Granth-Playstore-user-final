// T184 items 5–7: support chat (§20 / §20.6 / §20.7), check status, badges, dashboard card;
// account deletion (Play). 320dp × text 1.3, no overflow. Previews when PREVIEW_DIR is set:
//   PREVIEW_DIR=/workspace/previews flutter test test/t184_support_test.dart
import 'dart:convert';
import 'dart:io';
import 'dart:ui' as ui;

import 'package:dio/dio.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:granthprabandhan/main.dart';
import 'package:granthprabandhan/screens/login_screen.dart';
import 'package:granthprabandhan/services/firebase_bridge.dart';
import 'package:granthprabandhan/services/storage.dart';
import 'package:granthprabandhan/services/support.dart';
import 'package:granthprabandhan/state/router.dart';

import 'helpers.dart';
import 'links_grid_test.dart' show settle;

const iid = 'b0b0b0b0b0b0b0b0b0b0b0b0b0b0b0b0';

(int, Map<String, dynamic>) deleteResp = (404, {'error': 'not_found'});

Map<String, dynamic> ticket({bool open = true, int unread = 1}) => {
  'id': 12,
  'token': 3,
  'date': '2026-11-03',
  'subject': 'PDF नहीं खुलती',
  'question': 'PDF डाउनलोड के बाद नहीं खुलती, क्या करें?',
  'status': open ? 'open' : 'closed',
  'last_reply_at': '2026-11-03T06:00:00Z',
  'replied': true,
  'unread_replies': unread,
  'messages': [
    {'id': 0, 'from': 'user', 'text': 'PDF डाउनलोड के बाद नहीं खुलती, क्या करें?', 'at': '2026-11-03T05:30:00Z', 'read': true},
    {'id': 1, 'from': 'admin', 'text': 'कृपया ऐप में सेटिंग → डाउनलोड से कैश साफ़ करके फिर कोशिश करें।', 'at': '2026-11-03T06:00:00Z', 'read': unread == 0},
  ],
};

/// Answers by method + path; records every call.
class Server implements HttpClientAdapter {
  Server({this.open = true});
  bool open;
  int unread = 1;
  final calls = <String>[];
  final bodies = <Object?>[];
  @override
  Future<ResponseBody> fetch(RequestOptions o, Stream<Uint8List>? s, Future<void>? c) async {
    Object? body;
    if (s != null) {
      final b = <int>[];
      await for (final x in s) {
        b.addAll(x);
      }
      body = jsonDecode(utf8.decode(b));
    }
    calls.add('${o.method} ${o.uri.path}${o.uri.query.isEmpty ? '' : '?${o.uri.query}'}');
    bodies.add(body);
    (int, Object) r;
    final p = o.uri.path;
    if (p == '/support/status') {
      final tok = o.uri.queryParameters['token'];
      r = (200, {
        'tickets': tok == null || tok == '3' ? [ticket(open: open, unread: unread)] : [],
        'unread_replies': unread,
      });
    } else if (p == '/support/tickets/12' && o.method == 'GET') {
      r = (200, ticket(open: open, unread: unread));
    } else if (p == '/support/tickets/12/messages') {
      r = open ? (201, {'from': 'user', 'text': (body as Map)['text'], 'at': '2026-11-03T06:10:00Z', 'ok': true, 'id': 2}) : (409, {'error': 'closed'});
    } else if (p == '/support/tickets/ack') {
      unread = 0;
      r = (200, {'ok': true, 'updated': 1});
    } else if (p == '/account/delete') {
      r = deleteResp;
    } else {
      r = (404, {'error': 'not_found'});
    }
    return ResponseBody.fromString(jsonEncode(r.$2), r.$1, headers: {
      'content-type': ['application/json'],
    });
  }

  @override
  void close({bool force = false}) {}
}

void main() {
  final dir = Platform.environment['PREVIEW_DIR'];
  late Server server;
  setUp(() async {
    await setUpApp();
    server = Server();
    final dio = Dio(BaseOptions(responseType: ResponseType.plain, validateStatus: (s) => s != null && s < 600))..httpClientAdapter = server;
    SupportService.I = SupportService(dio: dio, base: 'https://h.example', iid: () => iid, enabled: true);
  });
  tearDown(() async {
    final fb = FirebaseBridge.I;
    fb.debugDeleteStep = null;
    fb.debugDeleteCalls.clear();
    fb.debugAuthenticate = null;
    fb.debugSignOutStep = null;
    LoginGate.enabled = false;
    await fb.debugSetAccount(null);
  });

  Future<GlobalKey> boot(WidgetTester t) async {
    if (dir != null) {
      await t.runAsync(() async {
        for (final e in {
          'NotoDeva': ['NotoSansDevanagari-Regular', 'NotoSansDevanagari-Medium', 'NotoSansDevanagari-SemiBold'],
          'DMSans': ['DMSans-Regular', 'DMSans-Medium', 'DMSans-SemiBold'],
          'YatraOne': ['YatraOne-Devanagari'],
          'YatraOneLatin': ['YatraOne-Latin'],
        }.entries) {
          final l = FontLoader(e.key);
          for (final f in e.value) {
            l.addFont(Future.value(ByteData.sublistView(File('assets/fonts/$f.ttf').readAsBytesSync())));
          }
          await l.load();
        }
      });
    }
    // 320dp × text 1.3 (the overflow check); previews at 2x.
    await t.binding.setSurfaceSize(const Size(640, 1400));
    t.view.devicePixelRatio = 2;
    t.platformDispatcher.textScaleFactorTestValue = 1.3;
    addTearDown(t.platformDispatcher.clearTextScaleFactorTestValue);
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
      final img = await (key.currentContext!.findRenderObject() as RenderRepaintBoundary).toImage(pixelRatio: 2);
      final d = await img.toByteData(format: ui.ImageByteFormat.png);
      File('$dir/$name').writeAsBytesSync(d!.buffer.asUint8List());
    });
  }

  Future<void> net(WidgetTester t) async {
    await t.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 80)));
    await settle(t);
  }

  testWidgets('chat: thread bubbles + ticks, ack on open, send, closed → 409 notice; no overflow', (t) async {
    final key = await boot(t);
    AppNav.I.openLink('#/support?t=12');
    await net(t);
    await net(t);
    expect(AppNav.I.route.legalPage, 'support/ticket/12');
    expect(find.byKey(const ValueKey('ticket-chat-page')), findsOneWidget);
    expect(find.byKey(const ValueKey('chat-msg-1')), findsOneWidget);
    expect(server.calls, contains('GET /support/tickets/12?install_id=$iid'));
    expect(server.calls, contains('POST /support/tickets/ack'));
    expect(server.bodies[server.calls.indexOf('POST /support/tickets/ack')], {
      'iid': iid,
      'ids': [12],
    });
    expect(SupportService.I.unread, 0);
    await t.enterText(find.byKey(const ValueKey('chat-input')), 'धन्यवाद, अब खुल गई');
    await t.tap(find.byKey(const ValueKey('chat-send')));
    await net(t);
    expect(server.bodies[server.calls.indexOf('POST /support/tickets/12/messages')], {'install_id': iid, 'text': 'धन्यवाद, अब खुल गई'});
    expect(find.text('धन्यवाद, अब खुल गई'), findsOneWidget);
    expect(find.byKey(const ValueKey('chat-tick-2-sent')), findsOneWidget);
    expect(t.takeException(), isNull);
    await t.binding.setSurfaceSize(const Size(640, 1700));
    await settle(t);
    await snap(t, key, 't184_ticket_chat.png');
    server.open = false;
    await t.enterText(find.byKey(const ValueKey('chat-input')), 'एक और');
    await t.tap(find.byKey(const ValueKey('chat-send')));
    await net(t);
    expect(find.byKey(const ValueKey('chat-closed')), findsOneWidget);
    expect(find.byKey(const ValueKey('chat-input')), findsNothing);
    expect(t.takeException(), isNull);
    await t.pumpWidget(const SizedBox()); // stops the 12 s poll
    await t.pump(const Duration(seconds: 3)); // toast
  });

  testWidgets('Check status: lists my tickets, token search, tap opens the chat; no overflow', (t) async {
    final key = await boot(t);
    AppNav.I.openLink('#/support?check=1');
    await net(t);
    expect(find.byKey(const ValueKey('support-check-page')), findsOneWidget);
    expect(server.calls.first, 'GET /support/status?install_id=$iid');
    expect(find.byKey(const ValueKey('ticket-12')), findsOneWidget);
    expect(find.byKey(const ValueKey('ticket-new-12')), findsOneWidget);
    expect(t.takeException(), isNull);
    await snap(t, key, 't184_check_status.png');
    await t.enterText(find.byKey(const ValueKey('support-check-input')), '9');
    await t.tap(find.byKey(const ValueKey('support-check-go')));
    await net(t);
    expect(server.calls.last, 'GET /support/status?install_id=$iid&token=9');
    expect(find.byKey(const ValueKey('support-check-error')), findsOneWidget);
    await t.enterText(find.byKey(const ValueKey('support-check-input')), '3');
    await t.tap(find.byKey(const ValueKey('support-check-go')));
    await net(t);
    expect(find.byKey(const ValueKey('found-12')), findsOneWidget);
    await t.tap(find.byKey(const ValueKey('ticket-open-12')).first);
    await net(t);
    expect(AppNav.I.route.legalPage, 'support/ticket/12');
    expect(t.takeException(), isNull);
    await t.pumpWidget(const SizedBox());
  });

  testWidgets('Sahayata page: no reply form, unread badge, Check status button; dashboard card opens the chat', (t) async {
    final key = await boot(t);
    AppNav.I.openLink('#/support');
    await net(t);
    expect(find.byKey(const ValueKey('ticket-reply-12'), skipOffstage: false), findsNothing);
    expect(find.byKey(const ValueKey('support-mine-badge')), findsOneWidget);
    expect(find.text('1'), findsWidgets);
    expect(t.takeException(), isNull);
    await snap(t, key, 't184_support_page.png');
    AppNav.I.go('#/settings?s=support');
    await net(t);
    expect(find.byKey(const ValueKey('set-support'), skipOffstage: false), findsOneWidget);
    expect(find.byKey(const ValueKey('set-support-badge'), skipOffstage: false), findsOneWidget);
    expect(find.byKey(const ValueKey('support-check'), skipOffstage: false), findsOneWidget);
    expect(t.takeException(), isNull);
    await snap(t, key, 't184_settings_support.png');
    await t.tap(find.byKey(const ValueKey('support-check'), skipOffstage: false));
    await net(t);
    expect(AppNav.I.route.legalPage, 'support/check');
    AppNav.I.go('#/');
    await net(t);
    final card = find.byKey(const ValueKey('dash-support'), skipOffstage: false);
    expect(card, findsOneWidget);
    await t.ensureVisible(card);
    await settle(t);
    expect(find.byKey(const ValueKey('dash-support-badge')), findsOneWidget);
    expect(t.takeException(), isNull);
    await snap(t, key, 't184_dashboard_support.png');
    await t.tap(card);
    await net(t);
    expect(AppNav.I.route.legalPage, 'support/ticket/12');
    await t.pumpWidget(const SizedBox());
  });

  testWidgets('खाता हटाएँ: confirm → server (404 ok) → Firebase delete (reauth on recent-login) → disconnect → login gate', (t) async {
    final fb = FirebaseBridge.I;
    await fb.debugSetAccount(const AccountInfo(email: 'a@gmail.com', name: 'A'));
    await Store.I.setString(Store.kLoginSeen, '1');
    var fbTries = 0;
    fb.debugDeleteStep = (s) async {
      if (s == 'firebase' && fbTries++ == 0) throw FirebaseAuthException(code: 'requires-recent-login');
    };
    final key = await boot(t);
    AppNav.I.openLink('#/account');
    await net(t);
    final del = find.byKey(const ValueKey('account-delete'), skipOffstage: false);
    expect(del, findsOneWidget);
    expect(find.byKey(const ValueKey('account-delete-web'), skipOffstage: false), findsOneWidget);
    expect(t.takeException(), isNull);
    await t.ensureVisible(del);
    await settle(t);
    await snap(t, key, 't184_account_delete.png');
    await t.tap(del);
    await settle(t);
    await t.tap(find.byKey(const ValueKey('account-delete-cancel')));
    await settle(t);
    expect(fb.debugDeleteCalls, isEmpty);
    await t.tap(del);
    await settle(t);
    await t.tap(find.byKey(const ValueKey('account-delete-confirm')));
    await net(t);
    expect(fb.debugDeleteCalls, ['server', 'firebase', 'reauth', 'firebase', 'disconnect']);
    expect(server.calls, contains('POST /account/delete'));
    expect(server.bodies[server.calls.indexOf('POST /account/delete')], {'install_id': iid, 'id_token': 'tok'});
    expect(fb.signedIn, isFalse);
    expect(Store.I.getString(FirebaseBridge.kAccount), isNull);
    expect(LoginGate.seen, isFalse);
    await t.pump(const Duration(seconds: 3)); // toast
  });

  test('a sign-in that finishes after logout does not log back in', () async {
    final fb = FirebaseBridge.I;
    fb.debugSignOutStep = (_) async {};
    final gate = Future<void>.delayed(const Duration(milliseconds: 50));
    fb.debugAuthenticate = () async {
      await gate;
      return const AccountInfo(email: 'late@gmail.com', name: 'L');
    };
    final f = fb.signIn();
    await fb.signOut();
    await f;
    expect(fb.signedIn, isFalse);
  });

  test('§22: 200 means the server deleted the Auth user — no app-side delete, just disconnect + local clear', () async {
    final fb = FirebaseBridge.I;
    await fb.debugSetAccount(const AccountInfo(email: 'a@gmail.com', name: 'A'));
    await Store.I.setString(Store.kLoginSeen, '1');
    fb.debugDeleteStep = (_) async {};
    deleteResp = (200, {'ok': true});
    addTearDown(() => deleteResp = (404, {'error': 'not_found'}));
    expect(await fb.deleteAccount(), isNull);
    expect(fb.debugDeleteCalls, ['server', 'disconnect']);
    expect(server.bodies[server.calls.indexOf('POST /account/delete')], {'install_id': iid, 'id_token': 'tok'});
    expect(fb.signedIn, isFalse);
    expect(LoginGate.seen, isFalse);
  });

  test('§22 errors: Hindi message, account kept (401/422/429/503 data_deleted)', () async {
    final fb = FirebaseBridge.I;
    fb.debugDeleteStep = (_) async {};
    addTearDown(() => deleteResp = (404, {'error': 'not_found'}));
    for (final (st, code, want) in [
      (401, 'invalid_token', 'Google पहचान'),
      (401, 'bad_app_key', 'ऐप की पहचान'),
      (422, 'bad_install_id', 'डिवाइस की पहचान'),
      (422, 'missing_id_token', 'लॉगिन की जानकारी'),
      (429, 'rate_limited', 'बहुत बार'),
      (503, 'upstream', 'डेटा हटा दिया गया'),
    ]) {
      await fb.debugSetAccount(const AccountInfo(email: 'a@gmail.com', name: 'A'));
      fb.debugDeleteCalls.clear();
      deleteResp = (st, {'error': code, if (st == 503) 'data_deleted': true});
      final err = await fb.deleteAccount();
      expect(err, contains(want), reason: '$st $code');
      expect(fb.debugDeleteCalls, ['server'], reason: 'no Firebase delete / disconnect on error');
      expect(fb.signedIn, isTrue);
    }
  });
}
