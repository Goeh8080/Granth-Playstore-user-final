/// ज्ञान चर्चा: the questions this install was asked lately (id + normalized text), kept on disk
/// so a question is not asked again in the same chat nor in the next sessions (tester t365:
/// "ज्ञान चर्चा में question repeat होना").
library;

import 'dart:convert';

import '../services/storage.dart';

class RecentQuiz {
  RecentQuiz._();
  static final RecentQuiz I = RecentQuiz._();

  static const kKey = 'granth-quiz-recent';
  static const kMax = 300;

  // Read through Store every time (prefs are in memory): no stale cache after a reset.

  static String norm(String text) => text.toLowerCase().replaceAll(RegExp(r'[\s\p{P}*_`]+', unicode: true), '');

  List<Map<String, String>> get _list {
    final out = <Map<String, String>>[];
    try {
      final j = jsonDecode(Store.I.getString(kKey) ?? '[]');
      if (j is List) {
        for (final e in j) {
          if (e is Map && e['i'] is String) out.add({'i': e['i'] as String, 't': e['t'] is String ? e['t'] as String : ''});
        }
      }
    } catch (_) {}
    return out;
  }

  /// True when [id] or [text] was asked lately.
  bool seen(String id, String text) {
    final t = norm(text);
    return _list.any((e) => e['i'] == id || (t.isNotEmpty && e['t'] == t));
  }

  /// The newest ids first (sent to the worker as an additive `avoid_question_ids` hint).
  List<String> recentIds([int n = 50]) => [for (final e in _list.reversed.take(n)) e['i']!];

  Future<void> add(String id, String text) async {
    final t = norm(text);
    final list = _list..removeWhere((e) => e['i'] == id || (t.isNotEmpty && e['t'] == t));
    list.add({'i': id, 't': t});
    while (list.length > kMax) {
      list.removeAt(0);
    }
    try {
      await Store.I.setString(kKey, jsonEncode(list));
    } catch (_) {}
  }
}
