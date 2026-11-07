// Reviewed schema7cbcb93 §25; production rollout HOLD until backend0015/deployment approval.
// Tests opt into rollout on a mock adapter. Never routes v2 bodies to legacy /ask.
import 'dart:async';
import 'dart:convert';
import 'package:dio/dio.dart';
import 'package:flutter/foundation.dart';
import '../config.dart';
import '../services/firebase_bridge.dart';
import '../services/storage.dart';
import 'quiz_v2.dart';
import 'v2_drafts.dart';

class _V2Failure implements Exception {
  const _V2Failure(this.code, [this.status = 0]);
  final String code;
  final int status;
}

class AiV2Flow extends ChangeNotifier {
  AiV2Flow({
    Dio? dio,
    String? base,
    String? appKey,
    String? Function()? owner,
    Future<String?> Function()? token,
    this.rollout = kAiV2RolloutEnabled,
    AiV2DraftStore? drafts,
  }) : _dio =
           dio ?? Dio(BaseOptions(connectTimeout: const Duration(seconds: 8))),
       _base = (base ?? kAdminBase).replaceAll(RegExp(r'/+$'), ''),
       _appKey = appKey ?? kAppKey,
       _identity = owner ?? (() => FirebaseBridge.I.uid),
       _token = token ?? (() => FirebaseBridge.I.googleIdToken()),
       drafts = drafts ?? AiV2DraftStore.I {
    if (owner == null) {
      _observeAuth = true;
      FirebaseBridge.I.addListener(_authChanged);
    }
  }
  static AiV2Flow I = AiV2Flow();
  final Dio _dio;
  final String _base, _appKey;
  final String? Function() _identity;
  final Future<String?> Function() _token;
  final bool rollout;
  final AiV2DraftStore drafts;
  bool _observeAuth = false;
  String? _owner, _session, _source, _selected, _error, _exhaustedReason;
  String _state = 'choose_source';
  QuizV2Question? _question;
  QuizV2Grade? _grade;
  AiV2Capabilities? _caps;
  final Set<String> _gradedIds = {};
  int _generation = 0;
  bool busy = false, _flushing = false;
  String? get currentOwner => _identity();
  bool get canReportQuiz =>
      ownerMatches &&
      question != null &&
      _caps?.flagsEnabled('gyan_charcha') == true;
  bool get ownerMatches => _owner != null && _owner == _identity();
  String get state => _owner != null && !ownerMatches ? 'unavailable' : _state;
  String? get exhaustionReason => ownerMatches ? _exhaustedReason : null;
  String? get sessionId => ownerMatches ? _session : null;
  QuizV2Question? get question => ownerMatches ? _question : null;
  QuizV2Grade? get grade => ownerMatches ? _grade : null;
  String? get errorCode =>
      _owner != null && !ownerMatches ? 'auth_required' : _error;
  bool get pending => ownerMatches && drafts.pendingQuiz(_owner!) != null;
  bool get canAdvance =>
      ownerMatches &&
      !busy &&
      !pending &&
      (_grade != null ||
          _error == 'question_unavailable' ||
          _error == 'already_submitted_different_payload');
  void _authChanged() {
    if (_owner != null && !ownerMatches) {
      _generation++;
      _owner = null;
      _question = null;
      _grade = null;
      _session = null;
      _source = null;
      _state = 'unavailable';
      _error = 'auth_required';
      busy = false;
      notifyListeners();
    }
  }

  @override
  void dispose() {
    if (_observeAuth) FirebaseBridge.I.removeListener(_authChanged);
    super.dispose();
  }

  Map<String, dynamic> _decode(Object? data) {
    if (data is String) {
      if (data.length > 131072) throw const _V2Failure('invalid_response');
      return aiObject(jsonDecode(data));
    }
    return aiObject(data);
  }

  Future<AiV2Capabilities?> _discover() async {
    if (!rollout) return null;
    try {
      final r = await _dio.get<dynamic>(
        '$_base/ai/capabilities',
        options: Options(
          responseType: ResponseType.plain,
          receiveTimeout: const Duration(seconds: 8),
          validateStatus: (_) => true,
        ),
      );
      if (r.statusCode != 200) return null;
      final c = AiV2Capabilities.parse(_decode(r.data));
      return c.supported ? c : null;
    } catch (_) {
      return null;
    }
  }

  Future<Response<dynamic>> _post(
    String owner,
    String path,
    Map<String, dynamic> body,
  ) async {
    if (!rollout || _identity() != owner) {
      throw const _V2Failure('auth_required', 401);
    }
    if (_appKey.isEmpty) throw const _V2Failure('app_key_required', 401);
    final encoded = jsonEncode(body);
    if (utf8.encode(encoded).length > 8192) {
      throw const _V2Failure('payload_too_large', 413);
    }
    final token = await _token().timeout(const Duration(seconds: 5));
    if (_identity() != owner || token == null || token.isEmpty) {
      throw const _V2Failure('auth_required', 401);
    }
    final r = await _dio.post<dynamic>(
      '$_base$path',
      data: encoded,
      options: Options(
        responseType: ResponseType.plain,
        contentType: 'application/json',
        receiveTimeout: const Duration(seconds: 8),
        sendTimeout: const Duration(seconds: 8),
        validateStatus: (_) => true,
        headers: {'X-App-Key': _appKey, 'Authorization': 'Bearer $token'},
      ),
    );
    if (_identity() != owner) throw const _V2Failure('auth_required', 401);
    if ((r.statusCode ?? 500) < 200 || (r.statusCode ?? 500) >= 300) {
      final code = _decode(r.data)['error'];
      const allowed = {
        'auth_required',
        'app_key_required',
        'google_sign_in_required',
        'quiz_disabled',
        'attempt_owner_mismatch',
        'session_not_found',
        'attempt_not_found',
        'revision_conflict',
        'request_id_conflict',
        'request_in_progress',
        'catalog_changed',
        'question_unavailable',
        'unsupported_type',
        'invalid_option',
        'invalid_source',
        'source_required',
        'source_locked',
        'rate_limited',
        'already_submitted_different_payload',
        'catalog_unavailable',
        'bank_unavailable',
        'praman_catalog_unavailable',
        'flags_disabled',
        'report_conflict',
        'unavailable',
      };
      throw _V2Failure(
        code is String && allowed.contains(code) ? code : 'unavailable',
        r.statusCode ?? 0,
      );
    }
    return r;
  }

  String _key(String owner) => 'granth-ai-v2-session:$owner';
  Future<void> _save(String owner) async {
    await Store.I.setString(
      _key(owner),
      jsonEncode({
        'session_id': _session,
        'source': _source,
        'state': _state,
        'selected': _selected,
        'question': _question?.toEnvelope(),
        'grade': _question == null || _selected == null
            ? null
            : _grade?.toEnvelope(_question!, _selected!),
        'reason': _exhaustedReason,
        'advance_error':
            const [
              'question_unavailable',
              'already_submitted_different_payload',
            ].contains(_error)
            ? _error
            : null,
        'graded_ids': _gradedIds.toList(),
      }),
    );
  }

  void _load(String owner) {
    _session = null;
    _source = null;
    _selected = null;
    _question = null;
    _grade = null;
    _state = 'choose_source';
    _exhaustedReason = null;
    _error = null;
    _gradedIds.clear();
    try {
      final j = aiObject(jsonDecode(Store.I.getString(_key(owner)) ?? ''));
      if (j['session_id'] is! String ||
          !RegExp(r'^s_[0-9a-f]{24}$').hasMatch(j['session_id'])) {
        return;
      }
      _session = j['session_id'];
      _source = const ['ved', 'puran', 'all'].contains(j['source'])
          ? j['source']
          : null;
      final q = QuizV2Question.parse(j['question']);
      if (q != null && q.sessionId == _session && q.source == _source) {
        _question = q;
        _selected = j['selected'] is String ? j['selected'] : null;
        _grade = _selected == null
            ? null
            : QuizV2Grade.parse(j['grade'], q, _selected!);
      }
      if (j['graded_ids'] is List) {
        _gradedIds.addAll(
          (j['graded_ids'] as List).whereType<String>().take(500),
        );
      }
      if (const [
        'all_seen',
        'bank_empty',
        'no_supported_types',
      ].contains(j['reason'])) {
        _exhaustedReason = j['reason'];
      }
      if (const [
        'question_unavailable',
        'already_submitted_different_payload',
      ].contains(j['advance_error'])) {
        _error = j['advance_error'];
      }
      _state = _grade != null
          ? 'graded'
          : _source == null
          ? 'choose_source'
          : j['state'] == 'exhausted'
          ? 'exhausted'
          : 'question';
    } catch (_) {
      /* corrupt local draft: never trust it as authority */
    }
  }

  Future<String> prepare() async {
    if (!rollout) return 'legacy';
    if (busy) return 'busy';
    busy = true;
    final gen = ++_generation, owner = _identity();
    notifyListeners();
    final caps = await _discover();
    if (gen != _generation) {
      busy = false;
      return 'auth';
    }
    _caps = caps;
    if (caps == null) {
      busy = false;
      notifyListeners();
      return 'legacy';
    }
    if (!caps.quizEnabled) {
      _question = null;
      _grade = null;
      busy = false;
      notifyListeners();
      return 'disabled';
    }
    if (owner == null || _identity() != owner) {
      busy = false;
      notifyListeners();
      return 'auth';
    }
    _owner = owner;
    _load(owner);
    busy = false;
    final op = drafts.pendingQuiz(owner);
    if (op != null) {
      if (op.kind == 'attempt') {
        _question = QuizV2Question.parse(op.toJson()['question']);
        _session = op.sessionId;
        _source = _question?.source;
        _selected = aiObject(op.body['answer'])['option_id'] as String?;
      }
      await _run(op);
    } else if (_session == null) {
      await _run(QuizV2Command.create(newAiV2Id()));
    } else if (_question != null && _grade == null && _source != null) {
      _question = null;
      await _run(QuizV2Command.next(_session!, _source!, newAiV2Id()));
    }
    notifyListeners();
    return ownerMatches ? 'ready' : 'auth';
  }

  Future<void> chooseSource(String s) async {
    if (!const ['ved', 'puran', 'all'].contains(s) ||
        _session == null ||
        busy ||
        pending) {
      return;
    }
    if (_source != null && _source != s) {
      _error = 'source_locked';
      notifyListeners();
      return;
    }
    _source = s;
    await _run(QuizV2Command.next(_session!, s, newAiV2Id()));
  }

  Future<void> submit(String option) async {
    final q = question;
    if (q == null ||
        grade != null ||
        busy ||
        pending ||
        !q.options.any((o) => o.id == option)) {
      return;
    }
    _selected = option;
    await _run(QuizV2Command.attempt(q, option, newAiV2Id()));
  }

  Future<void> next() async {
    if (!canAdvance || _session == null || _source == null) return;
    await _run(QuizV2Command.next(_session!, _source!, newAiV2Id()));
  }

  Future<void> changeSource() async {
    if (!ownerMatches || busy || pending) return;
    _session = null;
    _source = null;
    _question = null;
    _grade = null;
    _selected = null;
    _state = 'choose_source';
    await _run(QuizV2Command.create(newAiV2Id()));
  }

  Future<void> retry() async {
    if (!ownerMatches || busy) return;
    final op = drafts.pendingQuiz(_owner!);
    if (op != null) await _run(op);
  }

  Future<void> _run(QuizV2Command op) async {
    if (!ownerMatches || busy || _caps?.quizEnabled != true) return;
    final owner = _owner!, gen = _generation;
    busy = true;
    _error = null;
    _exhaustedReason = null;
    notifyListeners();
    try {
      if (!await drafts.saveQuiz(owner, op)) {
        throw const _V2Failure('request_pending');
      }
      await _save(owner);
      final r = await _post(owner, op.path, op.body);
      if (gen != _generation || !ownerMatches) return;
      final e = _decode(r.data);
      if (e['schema_version'] != 2) throw const _V2Failure('invalid_response');
      if (op.kind == 'create') {
        final sid = e['session_id'], choices = e['source_choices'];
        if (e['state'] != 'choose_source' ||
            sid is! String ||
            !RegExp(r'^s_[0-9a-f]{24}$').hasMatch(sid) ||
            choices is! List ||
            !const [
              'ved',
              'puran',
              'all',
            ].every((id) => choices.any((c) => aiObject(c)['id'] == id)) ||
            e['question'] != null ||
            e['result'] != null) {
          throw const _V2Failure('invalid_response');
        }
        _session = sid;
        _source = null;
        _state = 'choose_source';
        _question = null;
        _grade = null;
        _selected = null;
      } else if (op.kind == 'next' && e['state'] == 'exhausted') {
        if (e['session_id'] != op.sessionId ||
            e['source'] != op.body['source'] ||
            !const [
              'all_seen',
              'bank_empty',
              'no_supported_types',
            ].contains(e['reason']) ||
            e['question'] != null ||
            e['result'] != null) {
          throw const _V2Failure('invalid_response');
        }
        _session = op.sessionId;
        _source = op.body['source'];
        _state = 'exhausted';
        _exhaustedReason = e['reason'];
        _question = null;
        _grade = null;
        _selected = null;
      } else if (op.kind == 'next') {
        final q = QuizV2Question.parse(e);
        if (q == null ||
            q.sessionId != op.sessionId ||
            q.source != op.body['source'] ||
            _gradedIds.contains(q.id)) {
          throw const _V2Failure('invalid_response');
        }
        _question = q;
        _grade = null;
        _selected = null;
        _session = q.sessionId;
        _source = q.source;
        _state = 'question';
      } else {
        final q = _question;
        final selected = aiObject(op.body['answer'])['option_id'];
        if (q == null || selected is! String) {
          throw const _V2Failure('invalid_response');
        }
        final result = QuizV2Grade.parse(e, q, selected);
        if (result == null) throw const _V2Failure('invalid_response');
        _grade = result;
        _selected = selected;
        _state = 'graded';
        _gradedIds.add(q.id);
        while (_gradedIds.length > 500) {
          _gradedIds.remove(_gradedIds.first);
        }
      }
      await _save(owner);
      await drafts.clearQuiz(owner, op.requestId);
    } catch (e) {
      if (gen != _generation || !ownerMatches) return;
      _error = e is _V2Failure ? e.code : 'unavailable';
      if (e is _V2Failure &&
          (e.code == 'question_unavailable' ||
              e.code == 'already_submitted_different_payload')) {
        _question = null;
        _grade = null;
        _selected = null;
        _state = 'unavailable';
        await drafts.clearQuiz(owner, op.requestId);
        await _save(owner);
      }
      if (e is _V2Failure && (e.status == 401 || e.code == 'quiz_disabled')) {
        _question = null;
        _grade = null;
        _state = 'unavailable';
      }
    } finally {
      if (gen == _generation) {
        busy = false;
        notifyListeners();
      }
    }
  }

  String _reportKey(String owner) => 'granth-ai-v2-report-keys:$owner';
  Map<String, dynamic> _reportKeys(String owner) {
    try {
      return aiObject(jsonDecode(Store.I.getString(_reportKey(owner)) ?? ''));
    } catch (_) {
      return {};
    }
  }

  String? reportStatus(String key) {
    final owner = _identity();
    if (owner == null) return null;
    final id = _reportKeys(owner)[key];
    return id is String ? drafts.reportStatus(owner, id) : null;
  }

  Future<String> tryReportChat(
    String key, {
    required String question,
    required String answer,
    String? correction,
    String? reason,
    bool legacyQuiz = false,
  }) async {
    if (!rollout) return 'legacy';
    final owner = _identity(), caps = await _discover();
    if (caps == null ||
        aiObject(caps.raw['flags'])['versions'] is! List ||
        !(aiObject(caps.raw['flags'])['versions'] as List).contains(2)) {
      return 'legacy';
    }
    // Legacy quiz IDs are not server-owned v2 attempts: never relabel them as normal chat.
    if (legacyQuiz) return 'legacy_quiz';
    if (!caps.flagsEnabled('normal_chat')) return 'disabled';
    if (owner == null || _identity() != owner) return 'auth';
    try {
      return await _queue(
        owner,
        key,
        AiV2ReportDraft.chat(
          question: question,
          answer: answer,
          reportId: newAiV2Id(),
          correction: correction,
          reason: reason,
        ),
      );
    } catch (_) {
      return 'error';
    }
  }

  Future<String> reportQuiz({String? correction, String? reason}) async {
    final q = question;
    if (!rollout || !ownerMatches || q == null) return 'auth';
    if (_caps?.flagsEnabled('gyan_charcha') != true) return 'disabled';
    try {
      return await _queue(
        _owner!,
        'quiz:${q.attemptId}:${correction == null ? 'down' : 'correction'}',
        AiV2ReportDraft.quiz(
          q,
          reportId: newAiV2Id(),
          correction: correction,
          reason: reason,
        ),
      );
    } catch (_) {
      return 'error';
    }
  }

  String? get quizReportStatus => question == null
      ? null
      : reportStatus('quiz:${question!.attemptId}:down');
  Future<void> _reportTail = Future<void>.value();
  Future<String> _queue(String owner, String key, AiV2ReportDraft report) {
    final c = Completer<String>();
    _reportTail = _reportTail.then((_) async {
      try {
        c.complete(await _queueOnce(owner, key, report));
      } catch (e, s) {
        c.completeError(e, s);
      }
    });
    return c.future;
  }

  Future<String> _queueOnce(
    String owner,
    String key,
    AiV2ReportDraft report,
  ) async {
    if (_identity() != owner) return 'auth';
    final keys = _reportKeys(owner), old = keys[key];
    if (old is String) {
      final status = drafts.reportStatus(owner, old);
      if (status != null) return status;
    }
    await drafts.queueReport(owner, report);
    if (_identity() != owner) return 'auth';
    keys[key] = report.id;
    while (keys.length > 300) {
      final removable = keys.keys
          .where(
            (k) =>
                k != key &&
                drafts.reportStatus(owner, keys[k] as String) != 'queued',
          )
          .firstOrNull;
      if (removable == null) break;
      keys.remove(removable);
    }
    await Store.I.setString(_reportKey(owner), jsonEncode(keys));
    notifyListeners();
    return 'queued';
  }

  Future<void> flushReports() async {
    if (!rollout || _flushing) return;
    final owner = _identity();
    if (owner == null) return;
    _flushing = true;
    try {
      final caps = await _discover();
      if (caps == null || _identity() != owner) return;
      for (final item in drafts.reports(owner)) {
        if (item['status'] != 'queued') continue;
        final report = AiV2ReportDraft.restore(item['payload']);
        if (report == null) continue;
        final b = report.body;
        if (_identity() != owner) break;
        // A disabled context retains its queue without starving the other card.
        if (!caps.flagsEnabled(b['context'] as String? ?? '')) continue;
        final r = await _post(owner, '/ai/flags', b);
        if (_identity() != owner) break;
        await drafts.ackReport(
          owner,
          b['client_report_id'] as String,
          r.statusCode ?? 0,
          _decode(r.data),
        );
      }
    } catch (_) {
      /* retain immutable reports, never downgrade v2 to v1 */
    } finally {
      _flushing = false;
      notifyListeners();
    }
  }
}
