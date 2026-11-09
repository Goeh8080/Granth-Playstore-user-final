/// The state of "तत्त्व AI से पूछे", kept for the whole session so that opening a praman from an
/// answer and pressing Back returns to the same chat (nothing here lives in a widget).
library;

import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/widgets.dart';

import '../models/models.dart';
import '../services/notification_log.dart';
import '../services/admin_sync.dart';
import '../services/analytics.dart';
import '../services/catalog_store.dart';
import '../services/pdf_notify.dart';
import 'ai_client.dart';
import 'cannot_answer.dart';
import 'sanitize.dart';
import 'chat_store.dart';
import 'extra_sources.dart';
import 'retriever.dart';

/// "क्या आप यह प्रश्न admin को भेजना चाहेंगे?" — shown under an answer the AI could not give.
/// Shown when the model's reply was empty (or only ids).
/// The user turn that asks the worker for a ज्ञान चर्चा question.
const kGyanStart = 'ज्ञान चर्चा: मुझसे एक प्रश्न पूछिए';

/// Worker w9: in ज्ञान चर्चा the answer ends with "**अगला प्रश्न:** …"; the app shows
/// `next_question` as a card, so that tail is removed from the answer text.
String stripNextQuestionTail(String s) => s.replaceFirst(RegExp(r'\s*\**\s*अगला प्रश्न\s*[:：]?\s*\**\s*[:：]?[\s\S]*$'), '').trimRight();

/// Compares quiz question texts: case, spaces and punctuation do not count.
String normalizeQuizText(String text) => text.toLowerCase().replaceAll(RegExp(r'[\s\p{P}*_`]+', unicode: true), '');

/// Removes lines of an answer that only repeat one of [questions] (with or without a
/// "प्रश्न:" label), so a quiz question is never shown twice in a row.
String stripRepeatedQuestions(String text, Iterable<String> questions) {
  final qs = {for (final q in questions) normalizeQuizText(q)}..remove('');
  if (qs.isEmpty || text.isEmpty) return text;
  final label = RegExp(r'^\s*[*_]*\s*(?:अगला\s+)?प्रश्न\s*[:：]?\s*[*_]*\s*[:：]?');
  final kept = [
    for (final line in text.split('\n'))
      if (!qs.contains(normalizeQuizText(line.replaceFirst(label, ''))) || normalizeQuizText(line).isEmpty) line,
  ];
  return kept.join('\n').replaceAll(RegExp(r'\n{3,}'), '\n\n').trim();
}

/// Puts a ज्ञान चर्चा verdict on the question message it belongs to; returns its index, or null.
///
/// The verdict's own `question_id` decides (the worker may grade a pending question even when
/// the app sent no `quiz_reply_to`). If that id is not in this chat, the question replied to is
/// used only when the verdict's `correct_option` is one of its options. A question that already
/// has a verdict is never re-graded. The pick saved at tap time wins over the reply text.
int? applyQuizVerdict(List<ChatMsg> msgs, QuizResult v, {required String reply, String? replyTo}) {
  var i = msgs.lastIndexWhere((m) => m.quizQuestion?.id == v.questionId);
  if (i >= 0 && msgs[i].quizResult != null) return null;
  if (i < 0 && replyTo != null && v.correctOption != null) {
    final j = msgs.lastIndexWhere((m) => m.quizQuestion?.id == replyTo && m.quizResult == null);
    if (j >= 0 && quizOptionIndex(msgs[j].quizQuestion!.options, v.correctOption!) >= 0) i = j;
  }
  if (i < 0) return null;
  final m = msgs[i];
  final pick = m.quizSelection;
  final opts = m.quizQuestion!.options;
  final usePick = pick != null && (quizOptionIndex(opts, reply) < 0 && quizOptionLabel(reply, opts.length) == null || reply.trim() == pick.trim());
  msgs[i] = m.graded(v, usePick ? pick : reply);
  return i;
}

/// Which of [msgs] the chat shows: a quiz question asked again later (same id or text) is shown
/// once, and an assistant message that only repeats a neighbouring quiz question is hidden. The
/// question being answered right now ([activeId]) always stays visible.
List<int> visibleChatIndexes(List<ChatMsg> msgs, {String? activeId}) {
  final seenIds = <String>{}, seenTexts = <String>{};
  final out = <int>[];
  for (var i = 0; i < msgs.length; i++) {
    final m = msgs[i];
    final q = m.quizQuestion;
    if (q != null) {
      final t = normalizeQuizText(q.text);
      final dup = seenIds.contains(q.id) || (t.isNotEmpty && seenTexts.contains(t));
      seenIds.add(q.id);
      seenTexts.add(t);
      if (dup && q.id != activeId && m.quizResult == null) continue;
      out.add(i);
      continue;
    }
    if (!m.isUser && !m.isAdmin && m.quizResult == null && m.refs.isEmpty && m.cited.isEmpty) {
      final t = normalizeQuizText(m.text);
      bool same(int j) => j >= 0 && j < msgs.length && msgs[j].quizQuestion != null && normalizeQuizText(msgs[j].quizQuestion!.text) == t;
      if (t.isNotEmpty && (same(i - 1) || same(i + 1))) continue;
    }
    out.add(i);
  }
  return out;
}

const kEmptyAnswer = 'क्षमा करें, इस प्रश्न का सीधा उत्तर नहीं मिला।';

class AdminOffer {
  AdminOffer(this.convId, this.question, {this.reason});

  /// The worker's not-found `reason`, sent as `context: "ai_not_found:<reason>"`.
  final String? reason;
  final String convId;
  final String question;
  bool sending = false;

  /// A friendly reason the last try did not go through (offline, limit, …).
  String? message;
  bool canRetry = true;
}

/// "ज्ञान चर्चा": a question taken from the admin's notes (or a praman's topic), its answer and the
/// pramans — revealed on a tap.
class ChatController extends ChangeNotifier {
  ChatController({
    AiClient? client,
    ChatStore? store,
    List<Praman> Function()? pramans,
    int Function()? version,
    AdminSync? admin,
    AdminKnowledge? knowledge,
    List<Topic> Function()? topics,
    math.Random? random,
  }) : _client = client,
       _store = store,
       _pramans = pramans,
       _version = version,
       _admin = admin,
       _knowledge = knowledge,
       _topics = topics,
       _rng = random;

  static ChatController I = ChatController();

  final AiClient? _client;
  final ChatStore? _store;
  final List<Praman> Function()? _pramans;
  final int Function()? _version;
  final AdminSync? _admin;
  final AdminKnowledge? _knowledge;
  final List<Topic> Function()? _topics;
  final math.Random? _rng;

  AdminSync get admin => _admin ?? AdminSync.I;
  AdminKnowledge get knowledge => _knowledge ?? AdminKnowledge.I;
  List<Topic> get topics => (_topics ?? () => CatalogStore.I.topics)();
  math.Random get rng => _rng ?? math.Random();

  AiClient get client => _client ?? AiClient();
  ChatStore get store => _store ?? ChatStore.I;
  List<Praman> get pramans => (_pramans ?? () => CatalogStore.I.pramans)();
  int get version => (_version ?? () => CatalogStore.I.catalogVersion)();

  /// The text box of the composer lives here so a draft survives a visit to a praman.
  final TextEditingController input = TextEditingController();

  Conversation? current;
  List<ConversationInfo> chats = [];
  bool sending = false;
  AiException? error;
  bool loaded = false;

  /// Set when the last answer could not answer the question; null otherwise (not saved with the chat).
  AdminOffer? offer;

  /// ज्ञान चर्चा quiz loop: chats in quiz mode (asks go out with `mode:"gyan_charcha"`).
  final Set<String> quizChats = {};

  /// The server's open quiz question for [QuizQuestion]; answering it sends `quiz_reply_to`.
  ({String convId, QuizQuestion q})? quiz;

  /// Whether to offer "अगला प्रश्न" (quiz chat, nothing pending, no server question).
  bool get offerNext {
    final id = current?.id;
    return id != null && quizChats.contains(id) && !sending && error == null && quiz?.convId != id && messages.isNotEmpty && !messages.last.isUser;
  }

  /// Bumped when something was added to the open chat (the screen scrolls on it).
  int tick = 0;
  int _run = 0;
  Future<void>? _loading;

  List<ChatMsg> get messages => current?.messages ?? const [];

  /// Loads the history list (once). Opening AI always starts a NEW chat; old chats stay in
  /// the history (Goutam t184: no resume of the last chat).
  Future<void> load() => _loading ??= _load();

  Future<void> _load() async {
    chats = await store.list();
    loaded = true;
    notifyListeners();
    // Build the retrieval index in the background so the first question is quick.
    if (pramans.isNotEmpty) Retriever.I.ensure(pramans, version).ignore();
    unawaited(knowledge.loadCached()); // the admin's notes (disk copy) are ready for the first question
  }

  /// The user entered AI afresh (tab / link, not Back from a praman): a new, empty chat.
  void enterFresh() {
    if (current == null && !sending) return;
    newChat();
  }

  /// Starts an empty chat (the old one stays in the history).
  void newChat() {
    _run++;
    current = null;
    sending = false;
    error = null;
    offer = null;
    quiz = null;
    tick++;
    notifyListeners();
  }

  Future<void> open(String id) async {
    final c = await store.load(id);
    if (c == null) {
      chats = await store.list();
      notifyListeners();
      return;
    }
    _run++;
    current = c;
    quiz = null;
    if (c.messages.any((m) => m.quizQuestion != null)) {
      quizChats.add(c.id);
      final pending = c.messages.where((m) => m.quizQuestion != null && m.quizResult == null).lastOrNull;
      if (pending != null) quiz = (convId: c.id, q: pending.quizQuestion!);
    }
    sending = false;
    error = null;
    offer = null;
    tick++;
    notifyListeners();
  }

  Future<void> delete(String id) async {
    chats = await store.delete(id);
    if (current?.id == id) newChat();
    notifyListeners();
  }

  Future<void> clearAll() async {
    await store.clearAll();
    chats = [];
    newChat();
  }

  /// Asks [raw]. Returns false when nothing was sent (empty text or a question is on its way).
  Future<bool> send(String raw) async {
    final q = raw.trim();
    if (q.isEmpty || sending) return false;
    final now = DateTime.now().millisecondsSinceEpoch;
    final c = current ??= Conversation(id: newChatId(), title: _startQuiz ? 'ज्ञान चर्चा' : titleFor(q), created: now, updated: now);
    if (_startQuiz) quizChats.add(c.id);
    _startQuiz = false;
    c.messages.add(ChatMsg(role: 'user', text: q.length > kQuestionMax ? q.substring(0, kQuestionMax) : q, at: now));
    c.updated = now;
    error = null;
    sending = true; // locks the composer at once (the save below is asynchronous)
    tick++;
    notifyListeners();
    Analytics.I.aiAsked();
    await _persist(c);
    await _ask(c);
    return true;
  }

  /// "फिर कोशिश करें": asks the last question again.
  Future<void> retry() async {
    offer = null;
    final c = current;
    if (c == null || sending || !c.pending) return;
    error = null;
    notifyListeners();
    await _ask(c);
  }

  Future<void> _ask(Conversation c) async {
    final run = ++_run;
    sending = true;
    notifyListeners();
    final question = c.messages.last.text;
    final earlier = c.messages.sublist(0, c.messages.length - 1);
    final history = [
      for (final m in earlier)
        if (!m.isAdmin) AiTurn(m.role, m.text),
    ]; // admin messages are not AI turns
    try {
      final ps = pramans;
      final context = earlier.where((m) => m.isUser).isEmpty ? null : earlier.lastWhere((m) => m.isUser).text;
      // Extras (additive; empty when offline or nothing matches): the admin's notes, the topics.
      await knowledge.loadCached();
      final notes = await knowledge.candidates(question);
      final tops = await TopicSource.I.candidates(topics, version, question);
      final room = (kCandidatesMax - notes.length - tops.length).clamp(1, kCandidatesMax);
      final prs = await Retriever.I.candidates(ps, version, question, context: context, k: room);
      final cands = [...notes, ...prs, ...tops];
      final inQuiz = quizChats.contains(c.id);
      final replyTo = inQuiz && quiz?.convId == c.id ? quiz!.q.id : null;
      client
        ..mode = inQuiz ? 'gyan_charcha' : null
        ..quizReplyTo = replyTo;
      final AiAnswer a;
      try {
        a = await client.ask(question, history, cands);
      } finally {
        client
          ..mode = null
          ..quizReplyTo = null;
      }
      if (run != _run) {
        // The user left this chat (new chat / another chat) while the verdict was on its way:
        // still color the question it belongs to, so reopening the chat shows green / red.
        if (quizChats.contains(c.id) && a.quizResult != null) await _lateVerdict(c, a.quizResult!, question, replyTo);
        return;
      }
      if (replyTo != null && quiz?.q.id == replyTo) quiz = null;
      final known = <int>[
        for (final id in a.cited)
          if (Retriever.I.praman(id) != null) id,
      ];
      final now = DateTime.now().millisecondsSinceEpoch;
      // Never show raw candidate ids ("id-467"): the praman / note / topic name instead.
      final names = {for (final x in cands) x.id: x.granth.isEmpty ? x.title : '${x.title} (${x.granth})'};
      final candidate = inQuiz ? a.nextQuestion : null;
      final repeated = candidate != null && c.messages.any((m) => m.quizQuestion?.id == candidate.id || (m.quizQuestion != null && normalizeQuizText(m.quizQuestion!.text) == normalizeQuizText(candidate.text)));
      final nq = repeated ? null : candidate;
      final verdict = a.quizResult;
      if (inQuiz && verdict != null) {
        final i = applyQuizVerdict(c.messages, verdict, reply: question, replyTo: replyTo);
        if (i != null && quiz?.convId == c.id && quiz?.q.id == c.messages[i].quizQuestion!.id) quiz = null;
      }
      var text = sanitizeAiText(a.answer, (id) => names[id], sourceName: (n) => n >= 1 && n <= cands.length ? names[cands[n - 1].id] : null);
      if (candidate != null) text = stripNextQuestionTail(text); // the card shows it
      // The answered question and the next one are on their cards: never repeat them in prose.
      if (inQuiz) {
        text = stripRepeatedQuestions(text, [
          ?candidate?.text,
          for (final m in c.messages)
            if (m.quizQuestion != null) m.quizQuestion!.text,
        ]);
      }
      // A fresh quiz is only the question + its options, not a second prose copy.
      if (candidate != null && a.quizResult == null) text = '';
      if (repeated && text.isEmpty) text = 'यह प्रश्न पहले पूछा जा चुका है। नया प्रश्न चुनें।';
      final verdictOnly = inQuiz && a.quizResult != null; // the ✓/✗ chip still shows
      if (text.isEmpty && nq == null && !verdictOnly) text = kEmptyAnswer;
      if (text.isNotEmpty || verdictOnly) {
        c.messages.add(
        ChatMsg(
          role: 'assistant',
          text: text.length > kMaxMessageChars ? text.substring(0, kMaxMessageChars) : text,
          cited: known,
          at: now,
          sources: a.sources,
          refs: a.refs,
          correction: a.correction,
          quizResult: inQuiz ? a.quizResult : null,
        ),
      );
      }
      // ज्ञान चर्चा: the AI asks the next question itself (quiz loop).
      if (nq != null) {
        c.messages.add(ChatMsg(role: 'assistant', text: nq.text, quizQuestion: nq, at: now + 1));
        quiz = (convId: c.id, q: nq);
      }
      c.updated = now;
      sending = false;
      offer = !(verdictOnly && text.isEmpty) && aiCannotAnswer(answer: text, cited: a.cited, isPraman: (id) => Retriever.I.praman(id) != null, notFound: a.offerAdmin)
          ? AdminOffer(c.id, question, reason: a.found == false ? (a.reason ?? 'no_source') : null)
          : null;
      if (a.found == false) Analytics.I.aiFailed(question, a.reason ?? 'no_source');
      tick++;
      Analytics.I.aiAnswered();
      notifyListeners();
      await _persist(c);
    } on AiException catch (e) {
      if (run != _run) return;
      Analytics.I.aiFailed(question, e.kind.name);
      error = e;
      sending = false;
      notifyListeners();
    } catch (_) {
      if (run != _run) return;
      Analytics.I.aiFailed(question, 'error');
      error = const AiException(AiFailure.unavailable, 'कुछ गड़बड़ हो गई। कृपया फिर कोशिश करें।');
      sending = false;
      notifyListeners();
    }
  }

  Future<void> _persist(Conversation c) async {
    try {
      chats = await store.save(c);
      notifyListeners();
    } catch (_) {
      // A full disk must not break the chat: the conversation just stays in memory.
    }
  }

  @visibleForTesting
  void debugReset() {
    current = null;
    chats = [];
    sending = false;
    error = null;
    offer = null;
    quiz = null;
    quizChats.clear();
    loaded = false;
    _loading = null;
    _run++;
    input.clear();
  }
  // ---- ask the admin (round 13) ------------------------------------------------------------

  /// "हाँ": sends the question the AI could not answer to the admin.
  Future<void> askAdmin() async {
    final o = offer;
    if (o == null || o.sending) return;
    o.sending = true;
    o.message = null;
    notifyListeners();
    final r = await admin.sendQuestion(o.question, convId: o.convId, context: o.reason == null ? null : 'ai_not_found:${o.reason}');
    o.sending = false;
    if (r.ok) {
      if (identical(offer, o)) offer = null;
      final c = await _conv(o.convId);
      if (c != null) {
        final now = DateTime.now().millisecondsSinceEpoch;
        c.messages.add(ChatMsg(role: 'assistant', text: r.message, at: now));
        c.updated = now;
        if (identical(c, current)) tick++;
        await _persist(c);
      }
      unawaited(PdfNotify.I.ensurePermission()); // so the "उत्तर आ गया" notification can be seen
    } else {
      o.message = r.message;
      o.canRetry = r.canRetry;
    }
    notifyListeners();
  }

  /// "नहीं".
  void declineOffer() {
    if (offer == null || offer!.sending) return;
    offer = null;
    notifyListeners();
  }

  Future<Conversation?> _conv(String id) async {
    if (current?.id == id) return current;
    return store.load(id);
  }

  /// Stores an admin answer in the chat it belongs to (or a new one). True only when it is saved
  /// — or was saved before (a repeated poll): the caller acks the server only then.
  Future<bool> deliverAdminAnswer(AdminAnswer a, String? convId) async {
    try {
      final ref = a.ref;
      Conversation? c = convId == null ? null : await _conv(convId);
      if (c == null) {
        // The chat is gone (deleted) or unknown: a chat of its own, so nothing is lost.
        final now = DateTime.now().millisecondsSinceEpoch;
        c = Conversation(id: newChatId(), title: 'admin का उत्तर', created: now, updated: now);
      }
      if (c.messages.any((m) => m.ref == ref)) return true;
      final now = DateTime.now().millisecondsSinceEpoch;
      c.messages.add(
        ChatMsg(role: 'admin', text: a.answer.length > kMaxMessageChars ? a.answer.substring(0, kMaxMessageChars) : a.answer, at: now, ref: ref, ask: a.question.isEmpty ? null : a.question),
      );
      c.updated = now;
      chats = await store.save(c);
      NotificationLog.I.record(id: 'admin:$ref', kind: 'admin_reply', title: 'admin का उत्तर', body: a.answer, conv: c.id);
      if (current == null && !sending) current = c;
      if (identical(c, current)) tick++;
      notifyListeners();
      return true;
    } catch (_) {
      return false;
    }
  }

  // ---- ज्ञान चर्चा (round 13) --------------------------------------------------------------

  bool _startQuiz = false;

  /// ज्ञान चर्चा: asks the Tatv AI worker (`mode:"gyan_charcha"`) for a question. The worker
  /// generates it from one app praman and returns it as `next_question`; the app never asks
  /// questions from the admin's notes itself (notes are AI-only, w9 contract §2).
  Future<bool> startGyan() async {
    if (sending) return false;
    final c = current;
    if (c != null && c.messages.isNotEmpty && !quizChats.contains(c.id)) newChat();
    if (current != null) {
      quizChats.add(current!.id);
    } else {
      _startQuiz = true;
    }
    quiz = null;
    final ok = await send(kGyanStart);
    _startQuiz = false;
    return ok;
  }

  /// Taps an option of the server's quiz question (sent with `quiz_reply_to`). The pick is kept
  /// on the question message at once (and saved), so the verdict colors the right card even if
  /// the reply text is changed, the widget is rebuilt or the chat is reloaded.
  Future<bool> answerQuiz(String option) async {
    if (sending) return false;
    final c = current, q = quiz;
    if (c != null && q != null && q.convId == c.id) {
      final i = c.messages.lastIndexWhere((m) => m.quizQuestion?.id == q.q.id && m.quizResult == null);
      if (i >= 0) c.messages[i] = c.messages[i].picked(option);
    }
    return send(option);
  }

  /// A verdict that came back after the user left the chat: grade its question in the saved chat
  /// (and in the open copy of that chat, if it was reopened), and keep the explanation when the
  /// user's reply is still the last message.
  Future<void> _lateVerdict(Conversation c, QuizResult v, String reply, String? replyTo) async {
    final open = current?.id == c.id ? current! : null;
    for (final conv in {c, ?open}) {
      final i = applyQuizVerdict(conv.messages, v, reply: reply, replyTo: replyTo);
      if (i == null) continue;
      final last = conv.messages.last;
      if (last.isUser && last.text == reply) {
        conv.messages.add(ChatMsg(role: 'assistant', text: v.feedback, quizResult: v, at: DateTime.now().millisecondsSinceEpoch));
      }
      if (identical(conv, open) && quiz?.q.id == conv.messages[i].quizQuestion!.id) quiz = null;
    }
    try {
      await _persist(open ?? c);
    } catch (_) {}
    if (open != null) {
      tick++;
      notifyListeners();
    }
  }

  /// "नया प्रश्न": the worker returned no `next_question` (generation failed / old worker):
  /// resend with the mode set.
  Future<bool> nextQuestion() => send(kGyanStart);
}
