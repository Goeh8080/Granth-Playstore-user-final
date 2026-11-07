/// Support tickets (CONTRACT §5.1): a daily IST token per ticket, admin replies, follow-ups.
/// Anonymous: identified only by the install id. Offline → a Hindi error, nothing is lost
/// (the text stays in the box until it is sent).
library;

import 'dart:convert';
import 'dart:io' show Platform;

import 'package:dio/dio.dart';
import 'package:flutter/foundation.dart';

import '../config.dart';
import 'analytics.dart';

class SupportMsg {
  const SupportMsg(this.fromAdmin, this.text, this.at, {this.id = -1, this.read = false, this.pending = false});
  final bool fromAdmin;
  final String text, at;

  /// §20.6: 0 = the original question; -1 = not known (old server).
  final int id;

  /// §20.6: admin message acked by this app / user message opened by an admin.
  final bool read;

  /// Sent from this app, not yet confirmed by a refresh.
  final bool pending;
}

class SupportTicket {
  SupportTicket(this.raw);
  final Map<String, dynamic> raw;
  int get id => (raw['id'] as num?)?.toInt() ?? 0;
  int get token => (raw['token'] as num?)?.toInt() ?? 0;
  String get date => '${raw['date'] ?? ''}';
  String get subject => '${raw['subject'] ?? ''}';

  /// §20: `question`; older servers sent `message`.
  String get message => '${raw['question'] ?? raw['message'] ?? ''}';
  bool get open => raw['status'] != 'closed';
  String? get lastReplyAt => raw['last_reply_at'] is String ? raw['last_reply_at'] as String : null;
  bool get replied => raw['replied'] == true || lastReplyAt != null;

  /// §20.6 `unread_replies` (admin messages not acked yet); older `has_new_reply`.
  int get unreadReplies => (raw['unread_replies'] as num?)?.toInt() ?? (raw['has_new_reply'] == true ? 1 : 0);
  bool get hasNewReply => unreadReplies > 0;
  bool get hasThread => raw['messages'] is List;
  List<SupportMsg> get messages => [
    for (final m in (raw['messages'] is List ? raw['messages'] as List : const []))
      if (m is Map) SupportMsg(m['from'] == 'admin', '${m['text'] ?? ''}', '${m['at'] ?? ''}', id: (m['id'] as num?)?.toInt() ?? -1, read: m['read'] == true, pending: m['pending'] == true),
  ];

  /// "टोकन #3 · 31-10-2026" (date is the IST date from the server; else the created day).
  String get label {
    final src = date.isNotEmpty ? date : '${raw['created_at'] ?? ''}'.split('T').first;
    final p = src.split('-');
    final d = p.length == 3 ? '${p[2]}-${p[1]}-${p[0]}' : src;
    return d.isEmpty ? 'टोकन #$token' : 'टोकन #$token · $d';
  }
}

class SupportService extends ChangeNotifier {
  SupportService({Dio? dio, String? base, String Function()? iid, bool? enabled})
    : _dio =
          dio ??
          Dio(
            BaseOptions(
              connectTimeout: const Duration(seconds: 10),
              sendTimeout: const Duration(seconds: 10),
              receiveTimeout: const Duration(seconds: 10),
              responseType: ResponseType.plain,
              validateStatus: (s) => s != null && s < 600,
            ),
          ),
      base = (base ?? kAdminBase).replaceAll(RegExp(r'/+$'), ''),
      _iid = iid,
      enabled = enabled ?? !Platform.environment.containsKey('FLUTTER_TEST');
  static SupportService I = SupportService();

  final Dio _dio;
  final String base;
  final String Function()? _iid;
  bool enabled;
  List<SupportTicket> tickets = [];
  int unread = 0;
  bool loading = false;
  String? error;

  String get iid => _iid?.call() ?? Analytics.I.iid;
  Map<String, String> get _headers => {'Content-Type': 'application/json', if (kAppKey.isNotEmpty) 'X-App-Key': kAppKey.trim()};

  /// The Firebase uid (optional; the server ignores it for now, §20).
  static String? Function() uidOf = () => null;

  /// Hindi text for every §20 error (status + `error` code).
  static String errorText(int? status, [Object? body]) {
    final code = body is Map ? '${body['error'] ?? ''}' : '';
    switch (status) {
      case 401:
        return 'ऐप की पहचान नहीं हो सकी। कृपया ऐप अपडेट करें।';
      case 400:
        return switch (code) {
          'bad_install_id' => 'इस फ़ोन की पहचान (install ID) सही नहीं है।',
          'bad_json' => 'अनुरोध सही नहीं था। फिर कोशिश करें।',
          'bad_token' => 'टोकन नंबर सही नहीं है।',
          'bad_date' => 'तारीख़ सही नहीं है।',
          _ => 'संदेश 2 से 2000 अक्षरों का होना चाहिए।',
        };
      case 404:
        return 'यह टिकट नहीं मिला।';
      case 409:
        return 'यह टिकट बंद हो चुका है। नया टिकट बनाएँ।';
      case 413:
        return 'संदेश बहुत लंबा है।';
      case 429:
        return 'बहुत अधिक अनुरोध — आज की सीमा पूरी हो गई (दिन में 20 संदेश)। थोड़ी देर बाद या कल कोशिश करें।';
      case 503:
        return 'सहायता सेवा अभी उपलब्ध नहीं है। थोड़ी देर बाद कोशिश करें।';
    }
    return 'नेटवर्क नहीं मिला। कृपया फिर कोशिश करें।';
  }

  Future<({int? status, Object? json})> _call(String method, String path, [Map<String, dynamic>? body]) async {
    if (!enabled || base.isEmpty) return (status: null, json: null);
    try {
      final r = await _dio.request<String>(
        '$base$path',
        data: body == null ? null : jsonEncode(body),
        options: Options(method: method, headers: _headers),
      );
      Object? j;
      try {
        j = jsonDecode(r.data ?? '');
      } catch (_) {}
      return (status: r.statusCode, json: j);
    } catch (_) {
      return (status: null, json: null);
    }
  }

  String get _who {
    final u = uidOf();
    return 'install_id=${Uri.encodeQueryComponent(iid)}${u == null || u.isEmpty ? '' : '&uid=${Uri.encodeQueryComponent(u)}'}';
  }

  static List<SupportTicket> _list(Object? j) => [
    for (final e in (j is Map && j['tickets'] is List ? j['tickets'] as List : (j is Map && j['items'] is List ? j['items'] as List : (j is List ? j : const []))))
      if (e is Map<String, dynamic>) SupportTicket(e),
  ];

  DateTime? _last;

  /// Refreshes at most once a minute (badges on Sahayata / dashboard).
  Future<void> refreshSoon() async {
    if (_last != null && DateTime.now().difference(_last!) < const Duration(minutes: 1)) return;
    await refresh();
  }

  /// §20.7 status: all my tickets with their threads + the unread count, in one call.
  Future<void> refresh() async {
    _last = DateTime.now();
    loading = true;
    error = null;
    notifyListeners();
    final r = await _call('GET', '/support/status?$_who');
    loading = false;
    final j = r.json;
    if (r.status == 200 && j is Map) {
      tickets = _list(j);
      unread = (j['unread_replies'] as num?)?.toInt() ?? tickets.fold(0, (a, t) => a + t.unreadReplies);
    } else {
      error = errorText(r.status, j);
    }
    notifyListeners();
  }

  /// "स्थिति देखें": my tickets, optionally one token (+ IST date). Never another install's.
  Future<({List<SupportTicket> tickets, String? error})> status({int? token, String? date}) async {
    final r = await _call('GET', '/support/status?$_who${token == null ? '' : '&token=$token'}${date == null || date.isEmpty ? '' : '&date=$date'}');
    if (r.status == 200) {
      final l = _list(r.json);
      if (token == null) {
        tickets = l;
        final j = r.json;
        unread = j is Map ? (j['unread_replies'] as num?)?.toInt() ?? 0 : 0;
        notifyListeners();
      }
      return (tickets: l, error: null);
    }
    return (tickets: const <SupportTicket>[], error: errorText(r.status, r.json));
  }

  SupportTicket? byId(int id) {
    for (final t in tickets) {
      if (t.id == id) return t;
    }
    return null;
  }

  void _put(SupportTicket t) {
    final i = tickets.indexWhere((x) => x.id == t.id);
    tickets = [...tickets];
    if (i < 0) {
      tickets.insert(0, t);
    } else {
      tickets[i] = t;
    }
    unread = tickets.fold(0, (a, t) => a + t.unreadReplies);
    notifyListeners();
  }

  /// §20.2: one ticket with its thread. Returns null (ok) or a Hindi error.
  Future<String?> thread(int id) async {
    final r = await _call('GET', '/support/tickets/$id?$_who');
    final j = r.json;
    if (r.status == 200 && j is Map<String, dynamic>) {
      _put(SupportTicket(j));
      return null;
    }
    return errorText(r.status, j);
  }

  /// New ticket. Returns null (ok) or a Hindi error.
  Future<String?> create(String message, {String subject = '', String name = '', String contact = ''}) async {
    final m = message.trim();
    if (m.runes.length < 2 || m.runes.length > 2000) return errorText(400);
    final r = await _call('POST', '/support/tickets', {
      'iid': iid,
      'message': m,
      if (subject.trim().isNotEmpty) 'subject': _cut(subject.trim(), 120),
      if (name.trim().isNotEmpty) 'name': _cut(name.trim(), 60),
      if (contact.trim().isNotEmpty) 'contact': _cut(contact.trim(), 100),
      'app_version': kAppVersion,
    });
    if (r.status == 201 || r.status == 200) {
      lastCreatedId = (r.json is Map ? ((r.json as Map)['id'] as num?)?.toInt() : null);
      await refresh();
      return null;
    }
    return errorText(r.status, r.json);
  }

  int? lastCreatedId;

  /// §20.3: a user message in the two-way chat. Returns null (ok) or a Hindi error;
  /// 409 marks the ticket closed.
  Future<String?> send(int id, String text) async {
    final m = text.trim();
    if (m.runes.length < 2 || m.runes.length > 2000) return errorText(400);
    final u = uidOf();
    final r = await _call('POST', '/support/tickets/$id/messages', {'install_id': iid, if (u != null && u.isNotEmpty) 'uid': u, 'text': m});
    final t = byId(id);
    if (r.status == 201 || r.status == 200) {
      final j = r.json is Map ? r.json as Map : const {};
      if (t != null) {
        final raw = Map<String, dynamic>.of(t.raw);
        raw['messages'] = [
          ...(raw['messages'] is List ? raw['messages'] as List : const []),
          {'from': 'user', 'text': '${j['text'] ?? m}', 'at': '${j['at'] ?? DateTime.now().toUtc().toIso8601String()}', 'id': j['id'], 'read': false},
        ];
        _put(SupportTicket(raw));
      }
      return null;
    }
    if (r.status == 409 && t != null) _put(SupportTicket({...t.raw, 'status': 'closed'}));
    return errorText(r.status, r.json);
  }

  /// Play account deletion: asks the server to delete this install's data (presence, support
  /// tickets, uid). The endpoint shape isn't final, so 404 / 405 / network errors only log and
  /// return their status; the caller goes on with the Firebase delete either way.
  /// CONTRACT §22: POST /account/delete {install_id, id_token}. On 200 the server has removed
  /// the D1 data AND the Firebase Auth user. [dataDeleted]: 502/503 said the data is gone (retry safe).
  Future<({int? status, String? code, bool dataDeleted})> deleteAccountData(String? idToken) async {
    final r = await _call('POST', '/account/delete', {'install_id': iid, if (idToken != null && idToken.isNotEmpty) 'id_token': idToken});
    final j = r.json;
    return (
      status: r.status,
      code: j is Map ? j['error']?.toString() : null,
      dataDeleted: j is Map && j['data_deleted'] == true,
    );
  }

  /// Hindi message for a failed §22 account delete.
  static String deleteErrorText(int? status, String? code, {bool dataDeleted = false}) {
    switch (code) {
      case 'invalid_token':
        return 'Google पहचान की पुष्टि नहीं हो सकी। कृपया दोबारा लॉगिन करके फिर कोशिश करें।';
      case 'bad_app_key':
        return 'ऐप की पहचान स्वीकार नहीं हुई। कृपया ऐप अपडेट करें।';
      case 'bad_install_id':
        return 'इस डिवाइस की पहचान सही नहीं है। कृपया ऐप दोबारा खोलकर कोशिश करें।';
      case 'missing_id_token':
        return 'लॉगिन की जानकारी नहीं मिली। कृपया दोबारा लॉगिन करके कोशिश करें।';
      case 'rate_limited':
        return 'बहुत बार कोशिश हुई। कृपया थोड़ी देर बाद फिर कोशिश करें।';
    }
    if (status == 401) return 'Google पहचान की पुष्टि नहीं हो सकी। कृपया दोबारा लॉगिन करके फिर कोशिश करें।';
    if (status == 429) return 'बहुत बार कोशिश हुई। कृपया थोड़ी देर बाद फिर कोशिश करें।';
    if (dataDeleted) return 'आपका डेटा हटा दिया गया है, पर खाता पूरी तरह हटाना बाकी है। कृपया फिर से कोशिश करें।';
    if (status == null) return 'इंटरनेट नहीं है। कृपया कनेक्शन जाँचकर फिर कोशिश करें।';
    return 'खाता अभी हटाया नहीं जा सका। कृपया थोड़ी देर बाद फिर कोशिश करें।';
  }

  /// Forgets the tickets shown on this device (after an account delete).
  void clearLocal() {
    tickets = [];
    unread = 0;
    error = null;
    _last = null;
    notifyListeners();
  }

  /// Back-compat name.
  Future<String?> reply(int id, String message) => send(id, message);

  /// §20.6: marks the admin replies of these tickets as read (call when a thread opens).
  Future<void> ack(List<int> ids) async {
    if (ids.isEmpty) return;
    final r = await _call('POST', '/support/tickets/ack', {'iid': iid, 'ids': ids.take(50).toList()});
    if (r.status == 200) {
      tickets = [
        for (final t in tickets)
          ids.contains(t.id)
              ? SupportTicket({
                  ...t.raw,
                  'unread_replies': 0,
                  'has_new_reply': false,
                  if (t.hasThread) 'messages': [for (final m in t.raw['messages'] as List) m is Map && m['from'] == 'admin' ? {...m, 'read': true} : m],
                })
              : t,
      ];
      unread = tickets.fold(0, (a, t) => a + t.unreadReplies);
      notifyListeners();
    }
  }

  static String _cut(String s, int n) => s.runes.length <= n ? s : String.fromCharCodes(s.runes.take(n));
}
