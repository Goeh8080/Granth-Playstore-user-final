/// t303: the phone's own list of recent notifications for the Dashboard "सूचनाएँ" card —
/// admin replies (AI answers and Sahayata ticket replies), new प्रमाण after a sync, चर्चित
/// विषय and the daily प्रमाण. Kept only on this phone under one new optional key
/// ([kKey]); older builds never read it, and a missing / unreadable value is just an empty
/// list (nothing is migrated or rewritten). Each entry knows exactly what to open on tap.
library;

import 'dart:async';
import 'dart:convert';

import 'package:flutter/foundation.dart';

import '../ai/chat_controller.dart';
import '../state/router.dart';
import 'app_update.dart';
import 'storage.dart';

class NotifEntry {
  const NotifEntry({required this.id, required this.kind, required this.title, this.body = '', required this.at, this.link = '', this.conv, this.seen = false});

  /// Dedupe key (the same event is never listed twice).
  final String id;

  /// `admin_reply` | `support_reply` | `new_praman` | `trending` | `daily`.
  final String kind;
  final String title;
  final String body;
  final int at;

  /// App hash to open (`#/support?t=12`, `#/pramans?id=…`).
  final String link;

  /// AI chat that holds an admin reply (opens that exact conversation).
  final String? conv;
  final bool seen;

  NotifEntry copyWith({bool? seen}) => NotifEntry(id: id, kind: kind, title: title, body: body, at: at, link: link, conv: conv, seen: seen ?? this.seen);

  Map<String, Object?> toJson() => {'id': id, 'kind': kind, 'title': title, 'body': body, 'at': at, 'link': link, if (conv != null) 'conv': conv, 'seen': seen};

  static NotifEntry? fromJson(Object? j) {
    if (j is! Map) return null;
    final id = j['id'], kind = j['kind'], title = j['title'], at = j['at'];
    if (id is! String || id.isEmpty || kind is! String || title is! String || at is! num) return null;
    final conv = j['conv'];
    return NotifEntry(
      id: id,
      kind: kind,
      title: title,
      body: j['body'] is String ? j['body'] as String : '',
      at: at.toInt(),
      link: j['link'] is String ? j['link'] as String : '',
      conv: conv is String && conv.isNotEmpty ? conv : null,
      seen: j['seen'] == true,
    );
  }
}

class NotificationLog extends ChangeNotifier {
  NotificationLog._() {
    // Saved settings that arrive late (slow start): read the list again from them.
    Store.I.adopted.addListener(() {
      _cache = null;
      notifyListeners();
    });
  }
  static final NotificationLog I = NotificationLog._();

  static const kKey = 'granth-notif-log';
  static const max = 40;

  List<NotifEntry>? _cache;

  List<NotifEntry> get entries => _cache ??= _read();

  int get unseen => entries.where((e) => !e.seen).length;

  List<NotifEntry> _read() {
    try {
      final raw = Store.I.getString(kKey);
      if (raw == null || raw.isEmpty) return [];
      final l = jsonDecode(raw);
      if (l is! List) return [];
      return [for (final e in l) ?NotifEntry.fromJson(e)];
    } catch (_) {
      return []; // unreadable → empty, never a crash
    }
  }

  void _write() {
    try {
      Store.I.setString(kKey, jsonEncode([for (final e in entries) e.toJson()]));
    } catch (_) {}
  }

  /// Adds [e] on top unless an entry with the same id is already listed.
  bool add(NotifEntry e) {
    if (entries.any((x) => x.id == e.id)) return false;
    final l = [e, ...entries]..sort((a, b) => b.at.compareTo(a.at));
    _cache = l.length > max ? l.sublist(0, max) : l;
    _write();
    notifyListeners();
    return true;
  }

  /// Convenience for the hooks: never throws.
  void record({required String id, required String kind, required String title, String body = '', String link = '', String? conv}) {
    try {
      final one = body.replaceAll(RegExp(r'\s+'), ' ').trim();
      add(NotifEntry(id: id, kind: kind, title: title, body: one.length > 140 ? '${one.substring(0, 139)}…' : one, at: DateTime.now().millisecondsSinceEpoch, link: link, conv: conv));
    } catch (_) {}
  }

  void markSeen(String id) {
    final i = entries.indexWhere((e) => e.id == id);
    if (i < 0 || entries[i].seen) return;
    _cache = [...entries]..[i] = entries[i].copyWith(seen: true);
    _write();
    notifyListeners();
  }

  /// Opens exactly what the entry is about: the admin reply's own chat, the ticket thread,
  /// the praman / topic.
  Future<void> open(NotifEntry e) async {
    markSeen(e.id);
    if (e.kind == 'app_update') {
      unawaited(AppUpdate.I.prompt()); // don't block the tap on the dialog's lifetime
      return;
    }
    final conv = e.conv;
    if (conv != null) {
      AppNav.I.go('#/ai'); // enters AI (fresh) first…
      await ChatController.I.load();
      await ChatController.I.open(conv); // …then shows the chat with the reply
      return;
    }
    if (e.link.isNotEmpty) AppNav.I.openLink(e.link);
  }

  @visibleForTesting
  void debugReset() {
    _cache = null;
    notifyListeners();
  }
}
