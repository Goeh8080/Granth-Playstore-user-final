// ज्ञान चर्चा (Nov 10 feedback): card-style options, green/red after the verdict, no repeated
// question in the chat, and the additive `iid`/`uid` on POST /ask.
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:granthprabandhan/ai/ai_client.dart';
import 'package:granthprabandhan/ai/chat_controller.dart';
import 'package:granthprabandhan/ai/chat_store.dart';
import 'package:granthprabandhan/ai/retriever.dart';
import 'package:granthprabandhan/screens/ai_screen.dart';
import 'package:granthprabandhan/theme/colors.dart';

import 'ai_chat_store_test.dart' show FakeClient;
import 'ai_retrieval_test.dart' show realPramans;
import 'helpers.dart';

const _q = QuizQuestion(id: 'q', text: 'कबीर साहेब किस वर्ष प्रकट हुए?', options: ['1398 ई. में काशी के लहरतारा तालाब पर कमल के फूल पर', '1500', '1440', '1600']);
const _iid = '0123456789abcdef0123456789abcdef';

List<BoxDecoration> _cards(WidgetTester t) => [
  for (var i = 0; i < _q.options.length; i++)
    (t.widget<Container>(find.descendant(of: find.byKey(ValueKey('quiz-opt-$i')), matching: find.byType(Container)).first).decoration! as BoxDecoration),
];

Future<void> _pump(WidgetTester t, Widget w, {double scale = 1}) async {
  await t.binding.setSurfaceSize(const Size(320, 900));
  addTearDown(() => t.binding.setSurfaceSize(null));
  await t.pumpWidget(MaterialApp(home: MediaQuery(data: MediaQueryData(size: const Size(320, 900), textScaler: TextScaler.linear(scale)), child: Scaffold(body: SingleChildScrollView(child: w)))));
  await t.pumpAndSettle();
}

void main() {
  setUp(setUpApp);

  group('quiz_result coloring fields', () {
    test('parsed when present, absent on the old worker, round-trip in history', () {
      final a = parseAskResponse(200, jsonEncode({
        'answer': 'गलत',
        'next_question': null,
        'quiz_result': {'question_id': 'q', 'correct': false, 'feedback': 'देखें', 'correct_index': 0, 'correct_option': '1398', 'selected_index': 2},
      }));
      final r = a.quizResult!;
      expect((r.correctIndex, r.correctOption, r.selectedIndex), (0, '1398', 2));
      expect(QuizResult.fromJson(r.toJson())!.toJson(), r.toJson());
      final old = QuizResult.fromJson({'question_id': 'q', 'correct': true, 'feedback': ''})!;
      expect((old.correctIndex, old.correctOption, old.selectedIndex), (null, null, null));
      expect(old.toJson().keys, {'question_id', 'correct', 'feedback'}, reason: 'old saved chats stay byte-compatible');
      expect(QuizResult.fromJson({'question_id': 'q', 'correct_index': 9, 'selected_index': -1})!.correctIndex, isNull);
    });

    test('correct option: index, else its text, else the right pick itself', () {
      const opts = ['a', 'b', 'c'];
      expect(const QuizResult(questionId: 'q', correct: false, correctIndex: 1).correctIndexIn(opts), 1);
      expect(const QuizResult(questionId: 'q', correct: false, correctOption: 'c').correctIndexIn(opts), 2);
      expect(const QuizResult(questionId: 'q', correct: false, correctIndex: 0, correctOption: 'c').correctIndexIn(opts), 2, reason: 'text wins over a stale index');
      expect(const QuizResult(questionId: 'q', correct: true).correctIndexIn(opts, selected: 'b'), 1);
      expect(const QuizResult(questionId: 'q', correct: false).correctIndexIn(opts, selected: 'b'), isNull);
      expect(const QuizResult(questionId: 'q', selectedIndex: 2).selectedIndexIn(opts, null), 2);
    });
  });

  group('card-style options', () {
    testWidgets('before the verdict: white cards, gold border, tappable, no overflow at 320dp ×1.3', (t) async {
      String? tapped;
      await _pump(t, QuizOptions(question: _q, onAnswer: (o) => tapped = o), scale: 1.3);
      for (final d in _cards(t)) {
        expect(d.color, Colors.white);
        expect((d.border! as Border).top.color, GColors.gold);
        expect(d.borderRadius, BorderRadius.circular(14));
      }
      expect(t.getSize(find.byKey(const ValueKey('quiz-opt-1'))).height, greaterThanOrEqualTo(52));
      await t.tap(find.byKey(const ValueKey('quiz-opt-1')));
      expect(tapped, '1500');
      expect(t.takeException(), isNull);
    });

    testWidgets('right pick: only it turns green', (t) async {
      await _pump(t, QuizOptions(question: _q, selected: '1500', result: const QuizResult(questionId: 'q', correct: true, correctIndex: 1, selectedIndex: 1)));
      final c = _cards(t);
      expect(c[1].color, QuizOptions.kGreenBg);
      expect([c[0].color, c[2].color, c[3].color], everyElement(Colors.white));
      expect(find.text('✓ 1500'), findsOneWidget);
    });

    testWidgets('wrong pick: every wrong option red, the right one green; taps are ignored', (t) async {
      var taps = 0;
      await _pump(t, QuizOptions(question: _q, selected: '1440', onAnswer: (_) => taps++,
        result: const QuizResult(questionId: 'q', correct: false, correctIndex: 0, selectedIndex: 2)), scale: 1.3);
      final c = _cards(t);
      expect(c[0].color, QuizOptions.kGreenBg);
      expect([c[1].color, c[2].color, c[3].color], everyElement(QuizOptions.kRedBg));
      expect(find.text('✗ 1440'), findsOneWidget);
      expect(find.textContaining('✓ 1398'), findsOneWidget);
      await t.tap(find.byKey(const ValueKey('quiz-opt-3')));
      expect(taps, 0);
      expect(t.takeException(), isNull);
    });

    testWidgets('old worker (no correct option): only the wrong pick turns red', (t) async {
      await _pump(t, QuizOptions(question: _q, selected: '1440', result: const QuizResult(questionId: 'q', correct: false)));
      final c = _cards(t);
      expect(c[2].color, QuizOptions.kRedBg);
      expect([c[0].color, c[1].color, c[3].color], everyElement(Colors.white));
    });

    testWidgets('the explanation fades in after the colors; history shows at once', (t) async {
      final now = DateTime.now().millisecondsSinceEpoch;
      await t.pumpWidget(MaterialApp(home: Column(children: [
        QuizReveal(key: const ValueKey('fresh'), at: now, child: const Text('फ़ीडबैक')),
        QuizReveal(key: const ValueKey('old'), at: now - 60000, child: const Text('पुराना')),
      ])));
      double op(String k) => t.widget<Opacity>(find.descendant(of: find.byKey(ValueKey(k)), matching: find.byType(Opacity))).opacity;
      expect(op('fresh'), 0);
      expect(find.descendant(of: find.byKey(const ValueKey('old')), matching: find.byType(Opacity)), findsNothing);
      await t.pumpAndSettle();
      expect(op('fresh'), 1);
    });
  });

  group('no repeated question', () {
    test('prose that only repeats a quiz question is dropped', () {
      expect(stripRepeatedQuestions('सही उत्तर!\n\n**प्रश्न:** कबीर कौन थे?', ['कबीर कौन थे']), 'सही उत्तर!');
      expect(stripRepeatedQuestions('कबीर कौन थे?', ['कबीर कौन थे?']), '');
      expect(stripRepeatedQuestions('कबीर एक संत थे।', ['कबीर कौन थे?']), 'कबीर एक संत थे।');
    });

    test('chat shows a re-asked question once (unless it is the open one)', () {
      const a = QuizQuestion(id: 'a', text: 'प्रश्न अ?'), b = QuizQuestion(id: 'b', text: 'प्रश्न अ');
      final msgs = [
        const ChatMsg(role: 'user', text: kGyanStart),
        const ChatMsg(role: 'assistant', text: 'प्रश्न अ?', quizQuestion: a),
        const ChatMsg(role: 'assistant', text: 'प्रश्न अ?'), // prose copy
        const ChatMsg(role: 'assistant', text: 'प्रश्न अ', quizQuestion: b), // same text, new id
        const ChatMsg(role: 'assistant', text: 'उत्तर'),
      ];
      expect(visibleChatIndexes(msgs), [0, 1, 4]);
      expect(visibleChatIndexes(msgs, activeId: 'b'), [0, 1, 3, 4]);
    });

    test('controller: the verdict never repeats the question; a re-sent question is not added', () async {
      final fc = FakeClient([
        const AiAnswer(answer: '', cited: [], provider: 'p', nextQuestion: _q),
        AiAnswer(answer: 'गलत।\n\n${_q.text}', cited: const [], provider: 'p', nextQuestion: _q,
          quizResult: const QuizResult(questionId: 'q', correct: false, feedback: 'गलत', correctIndex: 0, selectedIndex: 1)),
      ]);
      final ps = realPramans();
      final c = ChatController(client: fc, store: ChatStore.fresh(), pramans: () => ps, version: () => 7);
      await c.load();
      expect(await c.startGyan(), isTrue);
      await c.answerQuiz('1500');
      final asked = c.messages.where((m) => m.quizQuestion != null).toList();
      expect(asked.length, 1);
      expect(asked.single.quizResult!.correctIndex, 0);
      final verdict = c.messages.last;
      expect(verdict.quizResult!.correct, isFalse);
      expect(verdict.text, isNot(contains('कबीर साहेब')));
    });
  });

  group('POST /ask iid / uid', () {
    test('additive, validated like presence', () {
      final base = buildAskBody('q', const [], const <Candidate>[]);
      expect(base.containsKey('iid') || base.containsKey('uid'), isFalse, reason: 'old callers unchanged');
      final b = buildAskBody('q', const [], const <Candidate>[], iid: _iid, uid: 'Abc_123-x');
      expect((b['iid'], b['uid']), (_iid, 'Abc_123-x'));
      final bad = buildAskBody('q', const [], const <Candidate>[], iid: 'XYZ', uid: 'bad uid/..');
      expect(bad.containsKey('iid') || bad.containsKey('uid'), isFalse);
    });
  });
}
