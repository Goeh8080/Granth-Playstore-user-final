// §25 public request drafts, no transport. Owner scope is local isolation, NOT auth proof.
import 'dart:async';
import 'dart:convert';
import 'dart:math';
import '../config.dart';
import '../services/storage.dart';
import 'quiz_v2.dart';

String newAiV2Id() {
  final random = Random.secure();
  return List.generate(
    16,
    (_) => random.nextInt(256).toRadixString(16).padLeft(2, '0'),
  ).join();
}

void _request(String id) {
  if (!RegExp(r'^[A-Za-z0-9_.:-]{1,64}$').hasMatch(id)) {
    throw ArgumentError('invalid request id');
  }
}

void _session(String id) {
  if (!RegExp(r'^s_[0-9a-f]{24}$').hasMatch(id)) {
    throw ArgumentError('invalid session id');
  }
}

dynamic _freeze(dynamic x) => x is Map
    ? Map<String, dynamic>.unmodifiable(
        x.map((k, v) => MapEntry(k as String, _freeze(v))),
      )
    : x is List
    ? List<dynamic>.unmodifiable(x.map(_freeze))
    : x;
String _canonical(Object? x) {
  Object? sort(Object? y) => y is Map
      ? {for (final k in y.keys.cast<String>().toList()..sort()) k: sort(y[k])}
      : y is List
      ? y.map(sort).toList()
      : y;
  return jsonEncode(sort(x));
}

class QuizV2Command {
  QuizV2Command._(
    this.kind,
    this.sessionId,
    Map<String, dynamic> body,
    Map<String, dynamic> draft,
  ) : body = _freeze(body),
      _draft = _freeze(draft);
  final String kind;
  final String? sessionId;
  final Map<String, dynamic> body, _draft;
  String get requestId => body['request_id'] as String;
  String get path => kind == 'create'
      ? '/ai/quiz/session'
      : '/ai/quiz/session/$sessionId/${kind == 'next' ? 'next' : 'attempt'}';
  factory QuizV2Command.create(String id) {
    _request(id);
    return QuizV2Command._(
      'create',
      null,
      {'schema_version': 2, 'request_id': id},
      {'kind': 'create', 'request_id': id},
    );
  }
  factory QuizV2Command.next(String sid, String source, String id) {
    _request(id);
    _session(sid);
    if (!const ['ved', 'puran', 'all'].contains(source)) {
      throw ArgumentError('invalid source');
    }
    return QuizV2Command._(
      'next',
      sid,
      {
        'schema_version': 2,
        'request_id': id,
        'source': source,
        'supported_question_types': ['single_choice'],
      },
      {'kind': 'next', 'session_id': sid, 'source': source, 'request_id': id},
    );
  }
  factory QuizV2Command.attempt(QuizV2Question q, String option, String id) {
    _request(id);
    _session(q.sessionId);
    if (!q.options.any((o) => o.id == option)) {
      throw ArgumentError('invalid option');
    }
    return QuizV2Command._(
      'attempt',
      q.sessionId,
      {
        'schema_version': 2,
        'request_id': id,
        'attempt_id': q.attemptId,
        'question_id': q.id,
        'revision': q.revision,
        'answer': {'type': 'single_choice', 'option_id': option},
      },
      {
        'kind': 'attempt',
        'request_id': id,
        'question': q.toEnvelope(),
        'option_id': option,
      },
    );
  }
  Map<String, dynamic> toJson() => _draft;
  static QuizV2Command? restore(Object? x) {
    try {
      final j = aiObject(x), id = j['request_id'] as String;
      return switch (j['kind']) {
        'create' => QuizV2Command.create(id),
        'next' => QuizV2Command.next(
          j['session_id'] as String,
          j['source'] as String,
          id,
        ),
        'attempt' => QuizV2Command.attempt(
          QuizV2Question.parse(j['question'])!,
          j['option_id'] as String,
          id,
        ),
        _ => null,
      };
    } catch (_) {
      return null;
    }
  }
}

String _text(String value, int max) {
  final s = value.trim();
  if (s.isEmpty || s.runes.length > max) {
    throw ArgumentError('report text missing or too long');
  }
  return s;
}

class AiV2ReportDraft {
  AiV2ReportDraft._(Map<String, dynamic> value) : body = _freeze(value);
  final Map<String, dynamic> body;
  String get id => body['client_report_id'] as String;
  factory AiV2ReportDraft.quiz(
    QuizV2Question q, {
    required String reportId,
    String? correction,
    String? reason,
  }) {
    _request(reportId);
    return AiV2ReportDraft._({
      'schema_version': 2,
      'client_report_id': reportId,
      'context': 'gyan_charcha',
      'kind': correction == null ? 'thumbs_down' : 'correction',
      'attempt_id': q.attemptId,
      'question_id': q.id,
      'question_revision': q.revision,
      if (correction != null) 'correction': _text(correction, 2000),
      if (reason != null && reason.trim().isNotEmpty)
        'reason': _text(reason, 300),
      'lang': 'hi',
      'app_version': kAppVersion,
      'at': DateTime.now().toUtc().toIso8601String(),
    });
  }
  factory AiV2ReportDraft.chat({
    required String question,
    required String answer,
    required String reportId,
    String? correction,
    String? reason,
  }) {
    _request(reportId);
    return AiV2ReportDraft._({
      'schema_version': 2,
      'client_report_id': reportId,
      'context': 'normal_chat',
      'kind': correction == null ? 'thumbs_down' : 'correction',
      'question': _text(question, 500),
      'answer': _text(answer, 2000),
      if (correction != null) 'correction': _text(correction, 2000),
      if (reason != null && reason.trim().isNotEmpty)
        'reason': _text(reason, 300),
      'lang': 'hi',
      'app_version': kAppVersion,
      'at': DateTime.now().toUtc().toIso8601String(),
    });
  }
  static AiV2ReportDraft? restore(Object? value) {
    try {
      final b = aiObject(value), context = b['context'];
      const common = [
        'schema_version',
        'client_report_id',
        'context',
        'kind',
        'correction',
        'reason',
        'lang',
        'app_version',
        'at',
      ];
      final fields = context == 'normal_chat'
          ? ['question', 'answer']
          : context == 'gyan_charcha'
          ? ['attempt_id', 'question_id', 'question_revision']
          : <String>[];
      if (fields.isEmpty ||
          b.keys.any((k) => !common.contains(k) && !fields.contains(k)) ||
          b['schema_version'] != 2 ||
          !const ['thumbs_down', 'correction'].contains(b['kind'])) {
        return null;
      }
      _request(b['client_report_id'] as String);
      if (b['kind'] == 'correction') _text(b['correction'] as String, 2000);
      if (b.containsKey('reason')) _text(b['reason'] as String, 300);
      if (b['lang'] != 'hi' ||
          b['app_version'] is! String ||
          (b['app_version'] as String).length > 64 ||
          b['at'] is! String ||
          (b['at'] as String).length > 64 ||
          DateTime.tryParse(b['at']) == null) {
        return null;
      }
      if (context == 'normal_chat') {
        _text(b['question'] as String, 500);
        _text(b['answer'] as String, 2000);
      } else if (b['attempt_id'] is! String ||
          !RegExp(r'^a_[0-9a-f]{24}$').hasMatch(b['attempt_id']) ||
          b['question_id'] is! String ||
          !RegExp(r'^q_[0-9a-f]{16}$').hasMatch(b['question_id']) ||
          b['question_revision'] is! int ||
          (b['question_revision'] as int) < 1) {
        return null;
      }
      if (utf8.encode(jsonEncode(b)).length > 8192) return null;
      return AiV2ReportDraft._(b);
    } catch (_) {
      return null;
    }
  }

  bool canSend(
    AiV2Capabilities c, {
    required String owner,
    required String? currentOwner,
    bool reviewed = kAiV2RolloutEnabled,
  }) =>
      reviewed &&
      owner.isNotEmpty &&
      owner == currentOwner &&
      c.flagsEnabled(body['context'] as String);
}

class AiV2DraftStore {
  static final I = AiV2DraftStore();
  Future<void> _tail = Future<void>.value();
  Future<T> _lock<T>(Future<T> Function() work) {
    final c = Completer<T>();
    _tail = _tail.then((_) async {
      try {
        c.complete(await work());
      } catch (e, s) {
        c.completeError(e, s);
      }
    });
    return c.future;
  }

  String _key(String kind, String owner) {
    if (!RegExp(r'^[A-Za-z0-9_-]{1,128}$').hasMatch(owner)) {
      throw ArgumentError('invalid local owner');
    }
    return 'granth-ai-v2-$kind:$owner';
  }

  Object? _read(String key) {
    try {
      return jsonDecode(Store.I.getString(key) ?? '');
    } catch (_) {
      return null;
    }
  }

  Future<bool> saveQuiz(String owner, QuizV2Command command) => _lock(() async {
    final prior = pendingQuiz(owner);
    if (prior != null) {
      return _canonical(prior.toJson()) == _canonical(command.toJson());
    }
    await Store.I.setString(_key('op', owner), jsonEncode(command.toJson()));
    return true;
  });
  QuizV2Command? pendingQuiz(String owner) =>
      QuizV2Command.restore(_read(_key('op', owner)));
  Future<void> clearQuiz(String owner, String requestId) => _lock(() async {
    if (pendingQuiz(owner)?.requestId == requestId) {
      await Store.I.remove(_key('op', owner));
    }
  });
  List<Map<String, dynamic>> reports(String owner) {
    final raw = _read(_key('flags', owner));
    return raw is List
        ? [
            for (final x in raw)
              if (x is Map<String, dynamic>) x,
          ]
        : [];
  }

  String? reportStatus(String owner, String reportId) =>
      reports(owner)
              .where(
                (e) => aiObject(e['payload'])['client_report_id'] == reportId,
              )
              .firstOrNull?['status']
          as String?;
  Future<void> queueReport(String owner, AiV2ReportDraft report) =>
      _lock(() async {
        if (utf8.encode(jsonEncode(report.body)).length > 8192) {
          throw StateError('payload_too_large');
        }
        final q = reports(owner),
            old = q
                .where(
                  (e) =>
                      aiObject(e['payload'])['client_report_id'] == report.id,
                )
                .firstOrNull;
        if (old != null) {
          if (_canonical(old['payload']) != _canonical(report.body)) {
            throw StateError('report_conflict');
          }
          return;
        }
        while (q.length >= 50) {
          final i = q.indexWhere((e) => e['status'] == 'sent');
          if (i < 0) throw StateError('report_queue_full');
          q.removeAt(i);
        }
        q.add({'payload': report.body, 'status': 'queued'});
        await Store.I.setString(_key('flags', owner), jsonEncode(q));
      });
  Future<void> clearOwner(String owner) => _lock(() async {
    for (final kind in ['op', 'flags', 'session', 'report-keys']) {
      await Store.I.remove(_key(kind, owner));
    }
  });
  Future<bool> ackReport(
    String owner,
    String reportId,
    int status,
    Object? response,
  ) => _lock(() async {
    final r = aiObject(response);
    if (status != 202 || r['id'] is! int || (r['id'] as int) < 1) return false;
    final q = reports(owner),
        item = q
            .where(
              (e) => aiObject(e['payload'])['client_report_id'] == reportId,
            )
            .firstOrNull;
    if (item == null) return false;
    if (item['status'] == 'sent' && item['server_id'] != r['id']) return false;
    item['status'] = 'sent';
    item['server_id'] = r['id'];
    await Store.I.setString(_key('flags', owner), jsonEncode(q));
    return true;
  });
}
