/// The network half of "तत्त्व AI से पूछे": one POST to the AI Worker. Plain `dart:io` (no new
/// package). The app never holds a provider key: the Worker does.
library;

import 'dart:async';
import 'dart:convert';
import 'dart:io';

import '../config.dart';
import '../services/analytics.dart';
import '../services/firebase_bridge.dart';
import '../services/remote_config.dart';
import 'retriever.dart';

/// One earlier turn sent along as context.
class AiTurn {
  const AiTurn(this.role, this.text);
  final String role; // 'user' | 'assistant'
  final String text;
  Map<String, String> toJson() => {'role': role, 'text': text};
}

/// What the Worker answered.
class AiAnswer {
  const AiAnswer({
    required this.answer,
    required this.cited,
    required this.provider,
    this.notFound,
    this.found,
    this.reason,
    this.askAdmin,
    this.sources = const [],
    this.refs = const [],
    this.correction,
    this.nextQuestion,
    this.quizResult,
  });
  final String answer;

  /// ज्ञान चर्चा (`mode:"gyan_charcha"`): the next quiz question; null outside the mode / absent.
  final QuizQuestion? nextQuestion;

  /// ज्ञान चर्चा: the verdict on a `quiz_reply_to` answer; null when absent.
  final QuizResult? quizResult;
  final List<int> cited;
  final String provider;

  /// Explicit server "not found" signal; null when the Worker did not send one.
  final bool? notFound;

  /// CONTRACT "AI not-found signal": `found`, `reason` (no_source|out_of_scope|low_confidence), `ask_admin`.
  final bool? found;
  final String? reason;
  final bool? askAdmin;

  /// SRJM book citations `sources:[{book,chapter,url}]`.
  final List<BookSource> sources;

  /// Tappable app references `refs:[{type, id, title, route, cited}]` (praman / topic / granth / note).
  final List<AiRef> refs;

  /// Worker detected a user correction ("ye galat hai, asal mein …"): offer "सुधार एडमिन को भेजें".
  final AiCorrection? correction;

  /// Whether to offer "प्रश्न एडमिन को भेजें?": `ask_admin:true`, else `found` alone decides; null → heuristic.
  bool? get offerAdmin => askAdmin == true ? true : (found != null ? !found! : notFound);
}

/// Tatv AI `next_question: {id, text, options?:[string], praman_id?}`.
class QuizQuestion {
  const QuizQuestion({required this.id, required this.text, this.options = const [], this.pramanId});
  final String id, text;
  final List<String> options;
  final int? pramanId;
  static QuizQuestion? fromJson(Object? j) {
    if (j is! Map) return null;
    final id = j['id'], t = j['text'];
    if (id == null || t is! String || t.trim().isEmpty) return null;
    final o = j['options'];
    final pid = j['praman_id'];
    return QuizQuestion(
      id: '$id',
      text: t.trim(),
      options: [
        if (o is List)
          for (final e in o.take(6))
            if (e is String && e.trim().isNotEmpty) e.trim(),
      ],
      pramanId: pid is num ? pid.toInt() : int.tryParse('${pid ?? ''}'),
    );
  }
}

/// Tatv AI `quiz_result: {question_id, correct: true|false|null, feedback}`, plus the additive
/// coloring fields `correct_index` (0-based), `correct_option` and `selected_index` (w11).
class QuizResult {
  const QuizResult({required this.questionId, this.correct, this.feedback = '', this.correctIndex, this.correctOption, this.selectedIndex});
  final String questionId;
  final bool? correct;
  final String feedback;
  final int? correctIndex, selectedIndex;
  final String? correctOption;
  static QuizResult? fromJson(Object? j) {
    if (j is! Map || j['question_id'] == null) return null;
    final c = j['correct'];
    // The worker sends 0-based integers; a numeric string or a float is accepted too. Range is
    // checked against the question's options later (correctIndexIn), not here.
    int? idx(Object? v) {
      final n = v is num ? (v == v.roundToDouble() ? v.toInt() : null) : (v is String ? int.tryParse(v.trim()) : null);
      return n != null && n >= 0 && n <= 9 ? n : null;
    }
    final co = j['correct_option'];
    return QuizResult(
      questionId: '${j['question_id']}',
      correct: c is bool ? c : null,
      feedback: j['feedback'] is String ? (j['feedback'] as String).trim() : '',
      correctIndex: idx(j['correct_index']),
      correctOption: co is String && co.trim().isNotEmpty ? co.trim() : null,
      selectedIndex: idx(j['selected_index']),
    );
  }

  /// Index of the right option in [options], or null when it is not known (older worker).
  ///
  /// Order: a 0-based `correct_index` that agrees with `correct_option` (or has no text to check);
  /// else the `correct_option` text matched loosely ([quizOptionKey]); else a 1-based index only
  /// when it fits nothing else (`== options.length`); else, for a right answer, the pick itself.
  /// The verdict wins over the fields: a "wrong" verdict never paints the pick green.
  int? correctIndexIn(List<String> options, {String? selected}) {
    final sel = selectedIndexIn(options, selected);
    int? found() {
      final byText = correctOption == null ? -1 : quizOptionIndex(options, correctOption!);
      final ci = correctIndex;
      if (ci != null && ci < options.length && (byText < 0 || byText == ci)) return ci;
      if (byText >= 0) return byText;
      if (ci != null && ci == options.length && ci > 0 && correctOption == null) return ci - 1;
      return null;
    }
    final right = found();
    if (correct == true) return sel ?? right;
    if (correct == false && right != null && right == sel) return null; // contradicts the verdict
    return right;
  }

  /// Index of the option the user picked: its text (loosely), an "A" / "2" / "ख" label, else the
  /// worker's `selected_index`.
  int? selectedIndexIn(List<String> options, String? selected) {
    if (selected != null && selected.trim().isNotEmpty) {
      final i = quizOptionIndex(options, selected);
      if (i >= 0) return i;
      final l = quizOptionLabel(selected, options.length);
      if (l != null) return l;
    }
    final si = selectedIndex;
    return si != null && si < options.length ? si : null;
  }

  Map<String, Object?> toJson() => {
    'question_id': questionId,
    'correct': correct,
    'feedback': feedback,
    'correct_index': ?correctIndex,
    'correct_option': ?correctOption,
    'selected_index': ?selectedIndex,
  };
}

/// Loose key for comparing quiz option texts: no leading "A)" / "क)" / "1." label, Devanagari
/// digits as Latin, lower case, no spaces or punctuation.
String quizOptionKey(String s) {
  var t = s.trim().replaceFirst(RegExp(r'^[\(\[]?\s*(?:[a-dA-D]|[क-घ]|[1-9]|[१-९])\s*[\)\]\.:।\-]\s*(?=\S)'), '');
  t = t.replaceAllMapped(RegExp('[०-९]'), (m) => '${m[0]!.codeUnitAt(0) - 0x0966}');
  return t.toLowerCase().replaceAll(RegExp(r'[\s\p{P}\p{S}]+', unicode: true), '');
}

/// The option in [options] that [text] names: exact (trimmed) first, else one loose match.
int quizOptionIndex(List<String> options, String text) {
  final exact = options.indexWhere((o) => o.trim() == text.trim());
  if (exact >= 0) return exact;
  final k = quizOptionKey(text);
  if (k.isEmpty) return -1;
  final hits = [for (final (i, o) in options.indexed) if (quizOptionKey(o) == k) i];
  return hits.length == 1 ? hits.single : -1;
}

/// "A", "b)", "(c)", "2", "२.", "ख", "option 3" → 0-based index (within [count]), else null.
int? quizOptionLabel(String text, int count) {
  final m = RegExp(r'^\s*(?:option|विकल्प|उत्तर|answer|jawab|जवाब)?\s*[:\-]?\s*\(?\s*([a-dA-D]|[1-9]|[१-९]|[क-घ])\s*[\).।:]?\s*$').firstMatch(text);
  if (m == null) return null;
  final c = m[1]!;
  final u = c.codeUnitAt(0);
  final i = switch (c) {
    _ when RegExp('[a-dA-D]').hasMatch(c) => c.toLowerCase().codeUnitAt(0) - 0x61,
    _ when RegExp('[1-9]').hasMatch(c) => u - 0x31,
    _ when RegExp('[१-९]').hasMatch(c) => u - 0x0967,
    _ => const ['क', 'ख', 'ग', 'घ'].indexOf(c),
  };
  return i >= 0 && i < count ? i : null;
}

/// One SRJM book citation under an answer.
class BookSource {
  const BookSource({required this.book, this.chapter = '', this.url = ''});
  final String book, chapter, url;
  String get label => chapter.isEmpty ? book : '$book · $chapter';
  bool get hasLink {
    final u = Uri.tryParse(url);
    return u != null && (u.scheme == 'https' || u.scheme == 'http') && u.host.isNotEmpty;
  }

  Map<String, String> toJson() => {'book': book, if (chapter.isNotEmpty) 'chapter': chapter, if (url.isNotEmpty) 'url': url};
  static BookSource? fromJson(Object? j) {
    if (j is! Map) return null;
    String s(Object? v, int max) => v is String ? (v.trim().length > max ? v.trim().substring(0, max) : v.trim()) : (v is num ? '$v' : '');
    final b = s(j['book'], 120);
    if (b.isEmpty) return null;
    return BookSource(book: b, chapter: s(j['chapter'], 120), url: s(j['url'], 500));
  }
}

/// One tappable app reference under an answer. `route` is an in-app hash route:
/// praman `#/pramans?id=ID`, topic `#/pramans?topic=ID`, granth `#/pramans?granth=ID`; note has none.
class AiRef {
  const AiRef({required this.type, required this.id, this.title = '', this.route, this.cited = false});
  final String type; // praman | topic | granth | note
  final int id;
  final String title;
  final String? route;
  final bool cited; // false = related (topic/granth of a cited praman, or a suggested praman)
  Map<String, Object> toJson() => {'type': type, 'id': id, if (title.isNotEmpty) 'title': title, 'route': ?route, 'cited': cited};
  static AiRef? fromJson(Object? j) {
    if (j is! Map) return null;
    final t = j['type'], id = j['id'];
    if (t is! String || !const {'praman', 'topic', 'granth', 'note'}.contains(t) || id is! int || id <= 0) return null;
    final r = j['route'];
    final okRoute = r is String && RegExp(r'^#/pramans\?(id|topic|granth)=\d+$').hasMatch(r);
    final title = j['title'] is String ? (j['title'] as String).trim() : '';
    return AiRef(type: t, id: id, title: title.length > 120 ? title.substring(0, 120) : title, route: okRoute ? r : null, cited: j['cited'] == true);
  }
}

List<AiRef> parseRefs(Object? v) => [
  if (v is List)
    for (final e in v.take(12)) ?AiRef.fromJson(e),
];

class AiCorrection {
  const AiCorrection({required this.question, required this.answer, required this.text});
  final String question, answer, text;
  Map<String, Object> toJson() => {'detected': true, 'question': question, 'answer': answer, 'text': text};
  static AiCorrection? fromJson(Object? j) {
    if (j is! Map || j['detected'] != true) return null;
    String s(Object? v) => v is String ? v : '';
    return AiCorrection(question: s(j['question']), answer: s(j['answer']), text: s(j['text']));
  }
}

List<BookSource> parseSources(Object? v) => [
  if (v is List)
    for (final e in v.take(10)) ?BookSource.fromJson(e),
];

/// Reads the Worker's explicit not-found signal (format still TBD, so several shapes are accepted):
/// `not_found: true`, `found: false`, `answer_found: false`, `cannot_answer: true`,
/// `status`/`result: "not_found"`. Returns null when absent so the heuristic decides.
bool? parseNotFound(Map json) {
  bool? b(Object? v) => v is bool ? v : (v == 'true' ? true : (v == 'false' ? false : null));
  final nf = b(json['not_found']) ?? b(json['notFound']) ?? b(json['cannot_answer']);
  if (nf != null) return nf;
  final f = b(json['found']) ?? b(json['answer_found']);
  if (f != null) return !f;
  for (final k in const ['status', 'result']) {
    final v = json[k];
    if (v is String && v.toLowerCase().replaceAll('-', '_') == 'not_found') return true;
  }
  return null;
}

enum AiFailure { offline, timeout, rateLimited, unavailable, rejected, tooLarge, badReply }

/// A failure with a message the user can read (Hindi) and whether trying again may help.
class AiException implements Exception {
  const AiException(this.kind, this.message, {this.status});
  final AiFailure kind;
  final String message;
  final int? status;

  bool get retryable => kind != AiFailure.rejected && kind != AiFailure.tooLarge;
  @override
  String toString() => 'AiException($kind, status=$status)';
}

const int kQuestionMax = 500;
const int kHistoryTurns = 4;
const int kHistoryTextMax = 600;
const int kCandidatesMax = 12;

String _cut(String s, int max) {
  final r = s.runes.toList();
  return r.length <= max ? s : String.fromCharCodes(r.take(max));
}

/// The JSON body of `POST /ask`, with every limit of the contract applied.
/// `iid` (32 lower-case hex install id) and `uid` (Firebase uid, signed in only) are additive and
/// validated like the presence body: an invalid value is left out, never sent.
Map<String, Object> buildAskBody(String question, List<AiTurn> history, List<Candidate> candidates, {String? mode, String? quizReplyTo, String? iid, String? uid, List<String> avoid = const []}) {
  final turns = history.where((t) => t.text.trim().isNotEmpty && (t.role == 'user' || t.role == 'assistant')).toList();
  final last = turns.length > kHistoryTurns ? turns.sublist(turns.length - kHistoryTurns) : turns;
  return {
    'question': _cut(question.trim(), kQuestionMax),
    'history': [for (final t in last) AiTurn(t.role, _cut(t.text.trim(), kHistoryTextMax)).toJson()],
    'candidates': [for (final c in candidates.take(kCandidatesMax)) c.toJson()],
    'mode': ?mode,
    if (quizReplyTo != null) 'quiz_reply_to': {'question_id': quizReplyTo},
    if (iid != null && kIidPattern.hasMatch(iid)) 'iid': iid,
    if (uid != null && kUidPattern.hasMatch(uid)) 'uid': uid,
    // Additive, unknown-safe: ज्ञान चर्चा question ids this install saw lately (no repeats).
    if (mode == 'gyan_charcha' && avoid.isNotEmpty) 'avoid_question_ids': [for (final a in avoid.take(50)) if (RegExp(r'^[a-f0-9]{16}$').hasMatch(a)) a],
  };
}

/// Same checks as `Presence.body()`.
final kIidPattern = RegExp(r'^[0-9a-f]{32}$');
final kUidPattern = RegExp(r'^[A-Za-z0-9_-]{1,128}$');

/// Praman ids from the `cited` field: numbers or numeric strings, no repeats, no junk.
List<int> parseCited(Object? raw) {
  if (raw is! List) return const [];
  final out = <int>[];
  for (final e in raw) {
    final v = e is num ? e.toInt() : int.tryParse('$e'.trim());
    if (v != null && v > 0 && !out.contains(v)) out.add(v);
  }
  return out;
}

String _messageFor(AiFailure k) => switch (k) {
  AiFailure.offline => 'इंटरनेट से जुड़ नहीं पाया। कनेक्शन जाँचकर फिर कोशिश करें।',
  AiFailure.timeout => 'उत्तर आने में बहुत समय लग रहा है। कृपया फिर कोशिश करें।',
  AiFailure.rateLimited => 'अभी बहुत प्रश्न आ रहे हैं। थोड़ी देर बाद फिर कोशिश करें।',
  AiFailure.unavailable => 'AI सेवा अभी उपलब्ध नहीं है। थोड़ी देर बाद फिर कोशिश करें।',
  AiFailure.rejected => 'यह प्रश्न स्वीकार नहीं हुआ। कृपया इसे छोटा या अलग तरह से लिखें।',
  AiFailure.tooLarge => 'प्रश्न बहुत बड़ा है। कृपया इसे छोटा करके पूछें।',
  AiFailure.badReply => 'AI से समझ न आने वाला उत्तर मिला। कृपया फिर कोशिश करें।',
};

/// Turns an HTTP status + body into an answer or an [AiException]. Pure, so it is unit-tested.
AiAnswer parseAskResponse(int status, String body) {
  Object? json;
  try {
    json = jsonDecode(body);
  } catch (_) {
    json = null;
  }
  if (status == 200) {
    if (json is Map && json['error'] == null) {
      final a = json['answer'];
      if (a is String && a.trim().isNotEmpty) {
        final p = json['provider'];
        return AiAnswer(
          answer: a.trim(),
          cited: parseCited(json['cited']),
          provider: p is String ? p : '',
          notFound: parseNotFound(json),
          found: json['found'] is bool ? json['found'] as bool : null,
          reason: json['reason'] is String && (json['reason'] as String).isNotEmpty ? json['reason'] as String : null,
          askAdmin: json['ask_admin'] is bool ? json['ask_admin'] as bool : null,
          sources: parseSources(json['sources']),
          refs: parseRefs(json['refs']),
          correction: AiCorrection.fromJson(json['correction']),
          nextQuestion: QuizQuestion.fromJson(json['next_question']),
          quizResult: QuizResult.fromJson(json['quiz_result']),
        );
      }
    }
    throw AiException(AiFailure.badReply, _messageFor(AiFailure.badReply), status: status);
  }
  final k = switch (status) {
    429 => AiFailure.rateLimited,
    413 => AiFailure.tooLarge,
    400 || 403 || 404 || 405 => AiFailure.rejected,
    _ => AiFailure.unavailable,
  };
  throw AiException(k, _messageFor(k), status: status);
}

class AiClient {
  AiClient({String? endpoint, this.timeout = const Duration(seconds: 45), this.backoff = const Duration(milliseconds: 1500), this.header = kAiClientHeader, String? Function()? iid, String? Function()? uid})
    : endpoint = (endpoint ?? RemoteConfig.I.aiEndpoint ?? kAiEndpoint).replaceAll(RegExp(r'/+$'), ''),
      _iid = iid ?? (() => Analytics.I.iid),
      _uid = uid ?? (() => FirebaseBridge.I.uid);

  /// Stable install id and the signed-in uid (injectable for tests). Never throw into [ask].
  final String? Function() _iid, _uid;
  String? _safe(String? Function() f) {
    try {
      return f();
    } catch (_) {
      return null;
    }
  }

  final String endpoint;
  final Duration timeout;
  final Duration backoff;
  final String header;

  /// ज्ञान चर्चा: set by the chat just before [ask] (`mode`, `quiz_reply_to`), cleared after.
  String? mode;
  String? quizReplyTo;
  List<String> avoid = const [];

  /// Asks once; on a timeout, a network error, a 429 or a 5xx it waits a little and asks once more.
  Future<AiAnswer> ask(String question, List<AiTurn> history, List<Candidate> candidates) async {
    final body = jsonEncode(buildAskBody(question, history, candidates, mode: mode, quizReplyTo: quizReplyTo, iid: _safe(_iid), uid: _safe(_uid), avoid: avoid));
    try {
      return await _once(body);
    } on AiException catch (e) {
      // A timeout already waited the full [timeout]: no silent second wait (up to ~90 s of spinner).
      // The user gets the error with a Retry button instead.
      if (!e.retryable || e.kind == AiFailure.timeout) rethrow;
      await Future<void>.delayed(e.kind == AiFailure.rateLimited ? backoff * 2 : backoff);
      return _once(body);
    }
  }

  Future<AiAnswer> _once(String body) async {
    final client = HttpClient()..connectionTimeout = const Duration(seconds: 15);
    try {
      return await _send(client, body).timeout(timeout);
    } on TimeoutException {
      throw AiException(AiFailure.timeout, _messageFor(AiFailure.timeout));
    } on SocketException {
      throw AiException(AiFailure.offline, _messageFor(AiFailure.offline));
    } on HandshakeException {
      throw AiException(AiFailure.offline, _messageFor(AiFailure.offline));
    } on HttpException {
      throw AiException(AiFailure.unavailable, _messageFor(AiFailure.unavailable));
    } finally {
      client.close(force: true);
    }
  }

  Future<AiAnswer> _send(HttpClient client, String body) async {
    final req = await client.postUrl(Uri.parse('$endpoint/ask'));
    req.headers
      ..contentType = ContentType('application', 'json', charset: 'utf-8')
      ..set('X-Granth-Client', header)
      ..set('Accept', 'application/json');
    final bytes = utf8.encode(body);
    req.contentLength = bytes.length;
    req.add(bytes);
    final res = await req.close();
    final text = await res.transform(utf8.decoder).join();
    return parseAskResponse(res.statusCode, text);
  }
}
