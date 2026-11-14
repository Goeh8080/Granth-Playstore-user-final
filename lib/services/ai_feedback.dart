/// 👍 / 👎 under each AI reply (round 14). A 👎 (with an optional reason) is meant for the
/// admin: it is queued on the phone and sent to `POST {kAdminBase}/ai/flags` (see
/// /workspace/round14_backend_needs.md). That endpoint does not exist yet: a 404/405/5xx or no
/// net keeps the item queued (≤ [kMaxQueue], newest kept) and the next sync tries again. Never
/// throws, never shows an error; the user's own vote is stored locally either way.
library;

import 'dart:convert';
import 'dart:io' show Platform;

import 'package:dio/dio.dart';
import 'package:flutter/foundation.dart';

import '../config.dart';
import 'analytics.dart';
import 'storage.dart';

const int kMaxQueue = 50;

class AiFeedback extends ChangeNotifier {
  AiFeedback({Dio? dio, String? base, String? appKey, String Function()? iid, bool? enabled})
    : _dio =
          dio ??
          Dio(
            BaseOptions(
              connectTimeout: const Duration(seconds: 8),
              sendTimeout: const Duration(seconds: 8),
              receiveTimeout: const Duration(seconds: 8),
              responseType: ResponseType.plain,
              validateStatus: (s) => s != null && s < 600,
            ),
          ),
      base = (base ?? kAdminBase).replaceAll(RegExp(r'/+$'), ''),
      appKey = (appKey ?? kAppKey).trim(),
      _iid = iid,
      enabled = enabled ?? !Platform.environment.containsKey('FLUTTER_TEST');
  static AiFeedback I = AiFeedback();

  static const kVotes = 'granth-ai-votes'; // {"<msg key>": 1 | -1}
  static const kQueue = 'granth-ai-flagq'; // [ {question, answer, reason, at, ...} ]

  final Dio _dio;
  final String base;
  final String appKey;
  final String Function()? _iid;
  bool enabled;
  bool _flushing = false;

  String get iid => (_iid ?? () => Analytics.I.iid)();

  Map<String, dynamic> _map(String k) {
    try {
      final j = jsonDecode(Store.I.getString(k) ?? '');
      if (j is Map<String, dynamic>) return j;
    } catch (_) {}
    return {};
  }

  List<Map<String, dynamic>> get queue {
    try {
      final j = jsonDecode(Store.I.getString(kQueue) ?? '');
      if (j is List) {
        return [
          for (final e in j)
            if (e is Map<String, dynamic>) e,
        ];
      }
    } catch (_) {}
    return [];
  }

  /// Local vote does not imply delivery: reports stay queued until HTTP 2xx.
  bool isQueued(String key) => queue.any((item) => item['key'] == key);

  /// 1, -1 or 0 (no vote).
  int vote(String key) => switch (_map(kVotes)[key]) {
    1 => 1,
    -1 => -1,
    _ => 0,
  };

  void up(String key) => _setVote(key, vote(key) == 1 ? 0 : 1);

  void _setVote(String key, int v) {
    final m = _map(kVotes);
    if (v == 0) {
      m.remove(key);
    } else {
      m[key] = v;
    }
    // Keep the map small: the 300 newest votes are plenty.
    while (m.length > 300) {
      m.remove(m.keys.first);
    }
    Store.I.setString(kVotes, jsonEncode(m));
    notifyListeners();
  }

  /// 👎: records the vote, queues the report and tries to send it now.
  ///
  /// [quiz] (additive): a 👎 on a ज्ञान चर्चा question card also sends
  /// `quiz:{question_id, text, options, correct_index, selected_index}` ([quizFlag]).
  Future<void> down(String key, {required String question, required String answer, String reason = '', String chat = '', Map<String, Object?>? quiz}) async {
    _setVote(key, -1);
    final q = queue
      ..removeWhere((e) => e['key'] == key)
      ..add({'key': key, 'question': _cut(question, 500), 'answer': _cut(answer, 2000), 'reason': _cut(reason.trim(), 300), 'chat': chat, 'at': DateTime.now().toUtc().toIso8601String(), 'quiz': ?quiz});
    while (q.length > kMaxQueue) {
      q.removeAt(0);
    }
    await Store.I.setString(kQueue, jsonEncode(q));
    notifyListeners();
    await flush();
  }

  /// User correction of an AI answer ("ye galat hai, asal mein …"). Queued like 👎 and sent as
  /// `kind:"correction"` to POST /ai/flags. It only affects future answers after an admin approves it
  /// (it then appears in /ai/knowledge.json as an admin note).
  Future<void> correct(String key, {required String question, required String answer, required String correction, String chat = ''}) async {
    final ck = '$key:c';
    final q = queue
      ..removeWhere((e) => e['key'] == ck)
      ..add({'key': ck, 'kind': 'correction', 'question': _cut(question, 500), 'answer': _cut(answer, 2000), 'correction': _cut(correction.trim(), 2000), 'chat': chat, 'at': DateTime.now().toUtc().toIso8601String()});
    while (q.length > kMaxQueue) {
      q.removeAt(0);
    }
    await Store.I.setString(kQueue, jsonEncode(q));
    notifyListeners();
    await flush();
  }

  /// The `quiz` object of a 👎 on a quiz card: ids/texts capped, indexes 0-based or null.
  static Map<String, Object?> quizFlag({required String questionId, required String text, required List<String> options, int? correctIndex, int? selectedIndex}) => {
    'question_id': _cut(questionId, 64),
    'text': _cut(text, 500),
    'options': [for (final o in options.take(8)) _cut(o, 200)],
    'correct_index': correctIndex,
    'selected_index': selectedIndex,
  };

  static String _cut(String s, int n) => s.runes.length > n ? String.fromCharCodes(s.runes.take(n)) : s;

  /// The last report the server refused (400 / 413): it stays queued (never marked done) and
  /// this status is kept so the UI / diagnostics can surface it. Null after a clean flush.
  int? lastRejected;

  /// `at` as an ISO-8601 UTC string (older queued items stored epoch seconds).
  static Object? isoAt(Object? at) => at is num ? DateTime.fromMillisecondsSinceEpoch((at < 1e11 ? at * 1000 : at).toInt(), isUtc: true).toIso8601String() : at;

  /// Sends the queued reports; each one leaves the queue only after a 2xx. A 400 / 413 is NOT
  /// done: the report stays queued and [lastRejected] is set. Returns how many were sent.
  Future<int> flush() async {
    if (!enabled || _flushing || base.isEmpty) return 0;
    _flushing = true;
    var sent = 0;
    lastRejected = null;
    try {
      for (final item in queue) {
        int? status;
        try {
          final r = await _dio.post<String>(
            '$base/ai/flags',
            data: jsonEncode({'iid': iid, 'kind': 'thumbs_down', 'lang': 'hi', 'app_version': kAppVersion, ...item, 'at': ?isoAt(item['at'])}..remove('key')),
            options: Options(contentType: 'application/json', headers: {if (appKey.isNotEmpty) 'X-App-Key': appKey}, responseType: ResponseType.plain, validateStatus: (s) => s != null && s < 600),
          );
          status = r.statusCode;
        } catch (_) {
          status = null;
        }
        if (status == 400 || status == 413) {
          lastRejected = status; // kept queued; the next report is still tried
          continue;
        }
        final done = status != null && status >= 200 && status < 300;
        if (!done) break; // offline / endpoint missing / busy: keep the rest for later
        final rest = queue..removeWhere((e) => e['key'] == item['key']);
        Store.I.setString(kQueue, jsonEncode(rest));
        sent++;
      }
    } finally {
      _flushing = false;
      notifyListeners();
    }
    return sent;
  }

  @visibleForTesting
  void debugReset() {
    Store.I.remove(kVotes);
    Store.I.remove(kQueue);
  }
}
