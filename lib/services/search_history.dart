import 'dart:convert';

import 'storage.dart';

/// Local-only completed searches; no per-keystroke disk writes or network requests.
class SearchHistory {
  static const key = 'granth-search-history';
  static const limit = 5;

  static List<String> get recent {
    try {
      final value = jsonDecode(Store.I.getString(key) ?? '[]');
      if (value is! List) return const [];
      final seen = <String>{};
      return value
          .whereType<String>()
          .map((q) => q.trim())
          .where((q) => q.isNotEmpty && seen.add(q.toLowerCase()))
          .take(limit)
          .toList();
    } catch (_) {
      return const [];
    }
  }

  static Future<void> remember(String query) async {
    final q = query.trim();
    if (q.isEmpty) return;
    final next = [
      q,
      ...recent.where((v) => v.toLowerCase() != q.toLowerCase()),
    ].take(limit).toList();
    final encoded = jsonEncode(next);
    if (encoded != Store.I.getString(key)) {
      await Store.I.setString(key, encoded);
    }
  }
}
