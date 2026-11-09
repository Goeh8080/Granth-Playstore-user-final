// "Kabhi kabhi red green nahi ho rahe option" (Nov 10): the verdict must always color the
// question it belongs to — loose option matching, labels, late replies, reloads — and an answer
// shows at most 5 pramaan.
import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:granthprabandhan/ai/ai_client.dart';
import 'package:granthprabandhan/ai/chat_controller.dart';
import 'package:granthprabandhan/ai/chat_store.dart';
import 'package:granthprabandhan/ai/retriever.dart';
import 'package:granthprabandhan/screens/ai_screen.dart';

import 'ai_retrieval_test.dart' show realPramans;
import 'helpers.dart';

const _id = '1e08501d60739092';
const _opts = ['1398 ई.', '1500 ई.', '1440 ई.', '1600 ई.'];
const _q = QuizQuestion(id: _id, text: 'कबीर साहेब किस वर्ष प्रकट हुए?', options: _opts);

/// Answers from a queue; an entry may be a Completer so a test controls when the reply lands.
class HoldClient extends AiClient {
  HoldClient(this.script) : super(endpoint: 'http://x', iid: () => null, uid: () => null);
  final List<Object> script;
  final List<String?> replyTo = [];
  @override
  Future<AiAnswer> ask(String question, List<AiTurn> history, List<Candidate> candidates) async {
    replyTo.add(quizReplyTo);
    final r = script.removeAt(0);
    if (r is AiException) throw r;
    return r is Completer<AiAnswer> ? r.future : r as AiAnswer;
  }
}

const _ask = AiAnswer(answer: '', cited: [], provider: 'p', nextQuestion: _q);
AiAnswer _verdict({String id = _id, bool? correct = false, int? ci = 0, String? co = '1398 ई.', int? si = 1}) =>
    AiAnswer(answer: 'सही उत्तर 1398', cited: const [], provider: 'p',
      quizResult: QuizResult(questionId: id, correct: correct, feedback: 'सही उत्तर 1398', correctIndex: ci, correctOption: co, selectedIndex: si));

Future<(ChatController, ChatStore)> _started(List<Object> script) async {
  final store = ChatStore.fresh();
  final ps = realPramans();
  final c = ChatController(client: HoldClient([_ask, ...script]), store: store, pramans: () => ps, version: () => 7);
  await c.load();
  expect(await c.startGyan(), isTrue);
  expect(c.quiz?.q.id, _id);
  return (c, store);
}

ChatMsg _question(List<ChatMsg> m) => m.lastWhere((x) => x.quizQuestion?.id == _id);

void main() {
  setUp(setUpApp);

  group('robust right / picked option', () {
    test('correct_option matches loosely: labels, case, punctuation, Devanagari digits', () {
      for (final co in ['B) 1500 ई.', 'ख) 1500 ई', '2. 1500 ई।', '१५०० ई.', '  1500 ई ']) {
        expect(QuizResult(questionId: 'q', correct: false, correctOption: co).correctIndexIn(_opts), 1, reason: co);
      }
      expect(quizOptionIndex(['A) राम', 'B) श्याम'], 'श्याम'), 1);
      expect(quizOptionIndex(['राम', 'राम।'], 'राम!'), -1, reason: 'ambiguous loose match is not guessed');
    });

    test('correct_index: 0-based int or string; 1-based only when nothing else fits; text wins', () {
      expect(QuizResult.fromJson({'question_id': 'q', 'correct': false, 'correct_index': '2'})!.correctIndexIn(_opts), 2);
      expect(QuizResult.fromJson({'question_id': 'q', 'correct': false, 'correct_index': 1.0})!.correctIndexIn(_opts), 1);
      expect(const QuizResult(questionId: 'q', correct: false, correctIndex: 4).correctIndexIn(_opts), 3, reason: '4 of 4 only fits 1-based');
      expect(const QuizResult(questionId: 'q', correct: false, correctIndex: 7, correctOption: '1440 ई.').correctIndexIn(_opts), 2);
      expect(const QuizResult(questionId: 'q', correct: false, correctIndex: 0, correctOption: '1440 ई.').correctIndexIn(_opts), 2);
      expect(const QuizResult(questionId: 'q', correct: false, correctIndex: 9).correctIndexIn(_opts), isNull);
    });

    test('picked option: text, "B" / "2" / "ख" labels, else selected_index; verdict wins', () {
      const r = QuizResult(questionId: 'q', correct: false, selectedIndex: 3);
      for (final (s, i) in [('1500 ई', 1), ('B', 1), ('c)', 2), ('2', 1), ('ख', 1), ('option 4', 3), ('कुछ और', 3), (null, 3)]) {
        expect(r.selectedIndexIn(_opts, s), i, reason: '$s');
      }
      // right pick: the pick is green even if the index disagrees; wrong pick never green.
      expect(const QuizResult(questionId: 'q', correct: true, correctIndex: 0).correctIndexIn(_opts, selected: 'B'), 1);
      expect(const QuizResult(questionId: 'q', correct: false, correctIndex: 1).correctIndexIn(_opts, selected: 'B'), isNull);
    });

    testWidgets('the tapped option shows (gold) before the verdict; colors after', (t) async {
      Future<List<Color?>> colors(QuizResult? r) async {
        await t.pumpWidget(MaterialApp(home: Scaffold(body: QuizOptions(question: _q, selected: '1440 ई.', result: r))));
        await t.pumpAndSettle();
        return [for (var i = 0; i < 4; i++) (t.widget<Container>(find.descendant(of: find.byKey(ValueKey('quiz-opt-$i')), matching: find.byType(Container)).first).decoration! as BoxDecoration).color];
      }
      final before = await colors(null);
      expect(before[2], isNot(Colors.white));
      expect([before[0], before[1], before[3]], everyElement(Colors.white));
      final after = await colors(const QuizResult(questionId: _id, correct: false, correctOption: 'A) 1398 ई'));
      expect(after[0], QuizOptions.kGreenBg);
      expect([after[1], after[2], after[3]], everyElement(QuizOptions.kRedBg));
    });
  });

  group('verdict lands on its question', () {
    test('pick is saved on the question at tap time, before the reply', () async {
      final hold = Completer<AiAnswer>();
      final (c, _) = await _started([hold]);
      final sent = c.answerQuiz('1500 ई.');
      await Future<void>.delayed(Duration.zero);
      expect(c.sending, isTrue);
      expect(_question(c.messages).quizSelection, '1500 ई.');
      expect(_question(c.messages).quizResult, isNull);
      hold.complete(_verdict());
      await sent;
      final q = _question(c.messages);
      expect(q.quizResult!.correctIndexIn(_opts, selected: q.quizSelection), 0);
      expect(q.quizResult!.selectedIndexIn(_opts, q.quizSelection), 1);
      expect(c.quiz, isNull);
    });

    test('typed "B" with no quiz_reply_to: the worker grades the pending question, the app colors it', () async {
      final (c, _) = await _started([_verdict(si: null)]);
      c.quiz = null; // e.g. the open question was lost after a rebuild
      await c.send('B');
      expect((c.client as HoldClient).replyTo.last, isNull);
      final q = _question(c.messages);
      expect(q.quizResult, isNotNull);
      expect(q.quizResult!.selectedIndexIn(_opts, q.quizSelection), 1);
      expect(c.messages.last.quizResult, isNotNull, reason: 'verdict chip + explanation');
    });

    test('question_id mismatch: used for the replied question only if correct_option is one of its options', () async {
      final (c, _) = await _started([_verdict(id: 'ffffffffffffffff')]);
      await c.answerQuiz('1500 ई.');
      expect(_question(c.messages).quizResult?.correctOption, '1398 ई.');
      final (d, _) = await _started([_verdict(id: 'ffffffffffffffff', co: 'कोई दूसरा')]);
      await d.answerQuiz('1500 ई.');
      expect(_question(d.messages).quizResult, isNull, reason: 'a verdict for another question is not painted here');
    });

    test('a graded question is never re-graded by a later verdict', () {
      final msgs = [ChatMsg(role: 'assistant', text: _q.text, quizQuestion: _q).graded(const QuizResult(questionId: _id, correct: true), '1398 ई.')];
      expect(applyQuizVerdict(msgs, const QuizResult(questionId: _id, correct: false), reply: 'B'), isNull);
      expect(msgs.single.quizResult!.correct, isTrue);
    });

    test('reply arrives after the user started a new chat: saved chat still colored, reopen shows it', () async {
      final hold = Completer<AiAnswer>();
      final (c, store) = await _started([hold]);
      final id = c.current!.id;
      final sent = c.answerQuiz('1500 ई.');
      await Future<void>.delayed(Duration.zero);
      c.newChat();
      hold.complete(_verdict());
      await sent;
      final saved = (await store.load(id))!;
      expect(_question(saved.messages).quizResult!.correctIndex, 0);
      expect(saved.messages.last.quizResult, isNotNull, reason: 'explanation kept');
      await c.open(id);
      final q = _question(c.messages);
      expect(q.quizResult!.correctIndexIn(_opts, selected: q.quizSelection), 0);
      expect(q.quizResult!.selectedIndexIn(_opts, q.quizSelection), 1);
      expect(c.quiz, isNull, reason: 'answered: no longer open');
    });

    test('reply arrives after the same chat was reopened: the open copy is colored too', () async {
      final hold = Completer<AiAnswer>();
      final (c, store) = await _started([hold]);
      final id = c.current!.id;
      final sent = c.answerQuiz('1500 ई.');
      await Future<void>.delayed(Duration.zero);
      await c.open(id); // new Conversation object for the same chat
      expect(c.quiz?.q.id, _id);
      hold.complete(_verdict());
      await sent;
      expect(_question(c.messages).quizResult, isNotNull);
      expect(c.quiz, isNull);
      expect(_question((await store.load(id))!.messages).quizResult, isNotNull);
    });

    test('saved chat reload keeps pick + coloring fields', () async {
      final (c, store) = await _started([_verdict()]);
      final id = c.current!.id;
      await c.answerQuiz('1500 ई.');
      final q = _question((await store.load(id))!.messages);
      expect((q.quizSelection, q.quizResult!.correctIndex, q.quizResult!.correctOption, q.quizResult!.selectedIndex), ('1500 ई.', 0, '1398 ई.', 1));
    });
  });

  group('Tatv Ai review (w12)', () {
    const id2 = 'aaaaaaaaaaaaaaaa';
    const q2 = QuizQuestion(id: id2, text: 'दूसरा प्रश्न?', options: ['क', 'ख', 'ग', 'घ']);
    // q1 still open, then the worker sends q2 without a verdict: two unanswered cards.
    Future<(ChatController, HoldClient)> twoCards(List<Object> script) async {
      final (c, _) = await _started([const AiAnswer(answer: '', cited: [], provider: 'p', nextQuestion: q2), ...script]);
      await c.send('नया प्रश्न');
      expect(c.quiz?.q.id, id2);
      expect(c.messages.where((m) => m.quizQuestion != null && m.quizResult == null).length, 2);
      return (c, c.client as HoldClient);
    }

    test('1) verdict with no quiz_reply_to goes to the card named by question_id (older card)', () async {
      final (c, hc) = await twoCards([_verdict(si: null)]);
      c.quiz = null;
      await c.send('1398');
      expect(hc.replyTo.last, isNull);
      expect(_question(c.messages).quizResult!.correctIndex, 0);
      expect(c.messages.lastWhere((m) => m.quizQuestion?.id == id2).quizResult, isNull, reason: 'newest card untouched');
    });

    test('2) tapping an older unanswered card sends ITS id as quiz_reply_to; answered cards stay closed', () async {
      final (c, hc) = await twoCards([_verdict()]);
      final chat = c.current!.id;
      expect(c.canAnswerCard(chat, _question(c.messages)), isTrue);
      expect(await c.answerQuiz('1500 ई.', questionId: _id), isTrue);
      expect(hc.replyTo.last, _id, reason: 'not the newest quiz.q.id ($id2)');
      final q1 = _question(c.messages);
      expect((q1.quizSelection, q1.quizResult!.correctIndex), ('1500 ई.', 0));
      final card2 = c.messages.lastWhere((m) => m.quizQuestion?.id == id2);
      expect(card2.quizResult, isNull);
      expect(c.canAnswerCard(chat, card2), isTrue, reason: 'the newer card can still be answered');
      expect(c.canAnswerCard(chat, q1), isFalse);
      final asks = hc.replyTo.length;
      expect(await c.answerQuiz('1440 ई.', questionId: _id), isFalse);
      expect(hc.replyTo.length, asks, reason: 'nothing sent for an answered card');
      expect(c.canAnswerCard('other-chat', card2), isFalse);
    });

    test('2) a retry after an error still replies to the tapped card', () async {
      final (c, hc) = await twoCards([const AiException(AiFailure.unavailable, 'x'), _verdict()]);
      await c.answerQuiz('1500 ई.', questionId: _id);
      expect(c.error, isNotNull);
      await c.retry();
      expect(hc.replyTo.sublist(hc.replyTo.length - 2), [_id, _id]);
      expect(_question(c.messages).quizResult, isNotNull);
    });

    testWidgets('3) free-text answer (selected_index null): right option green, nothing red', (t) async {
      await t.pumpWidget(MaterialApp(home: Scaffold(body: QuizOptions(question: _q, selected: 'मुझे नहीं पता',
        result: const QuizResult(questionId: _id, correct: false, correctIndex: 0, correctOption: '1398 ई.')))));
      await t.pumpAndSettle();
      final c = [for (var i = 0; i < 4; i++) (t.widget<Container>(find.descendant(of: find.byKey(ValueKey('quiz-opt-$i')), matching: find.byType(Container)).first).decoration! as BoxDecoration).color];
      expect(c[0], QuizOptions.kGreenBg);
      expect([c[1], c[2], c[3]], everyElement(Colors.white));
      expect(find.textContaining('✗'), findsNothing);
      // right answer typed as text: green on the right option even without selected_index
      await t.pumpWidget(MaterialApp(home: Scaffold(body: QuizOptions(question: _q, selected: 'चौदह सौ अट्ठानवे',
        result: const QuizResult(questionId: _id, correct: true, correctIndex: 0)))));
      await t.pumpAndSettle();
      expect((t.widget<Container>(find.descendant(of: find.byKey(const ValueKey('quiz-opt-0')), matching: find.byType(Container)).first).decoration! as BoxDecoration).color, QuizOptions.kGreenBg);
    });
  });

  testWidgets('an answer shows at most 5 pramaan, cited first', (t) async {
    final refs = [
      for (var i = 1; i <= 6; i++) AiRef(type: 'praman', id: i, title: 'प्रमाण $i', route: '#/pramans?id=$i'),
      const AiRef(type: 'praman', id: 50, title: 'उद्धृत', route: '#/pramans?id=50', cited: true),
      const AiRef(type: 'topic', id: 9, title: 'विषय', route: '#/pramans?topic=9'),
    ];
    await t.binding.setSurfaceSize(const Size(320, 900));
    addTearDown(() => t.binding.setSurfaceSize(null));
    await t.pumpWidget(MaterialApp(home: Scaffold(body: AiRefPills(refs, find: (_) => null))));
    final pills = find.descendant(of: find.byKey(const ValueKey('ai-refs')), matching: find.byWidgetPredicate((w) => w.key is ValueKey<String> && (w.key! as ValueKey<String>).value.startsWith('ai-ref-')));
    expect(pills, findsNWidgets(kMaxPramanShown));
    expect(find.byKey(const ValueKey('ai-ref-0-praman-50')), findsOneWidget, reason: 'cited first');
    expect(t.takeException(), isNull);
  });
}
