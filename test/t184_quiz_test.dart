import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:granthprabandhan/ai/ai_client.dart';
import 'package:granthprabandhan/ai/chat_controller.dart';
import 'package:granthprabandhan/ai/chat_store.dart';
import 'package:granthprabandhan/ai/retriever.dart';

import 'ai_chat_store_test.dart' show FakeClient;
import 'ai_retrieval_test.dart' show realPramans;
import 'helpers.dart';

class ModeClient extends FakeClient {
  ModeClient(super.script);
  final List<(String?, String?)> sent = [];
  @override
  Future<AiAnswer> ask(String question, List<AiTurn> history, List<Candidate> candidates) {
    sent.add((mode, quizReplyTo));
    return super.ask(question, history, candidates);
  }
}

void main() {
  setUp(setUpApp);

  test('parse: next_question / quiz_result, absent → null', () {
    final a = parseAskResponse(200, jsonEncode({
      'answer': 'उत्तर',
      'next_question': {'id': 'q7', 'text': 'कबीर साहेब कब प्रकट हुए?', 'options': ['1398', '1500', 7], 'praman_id': 12},
      'quiz_result': {'question_id': 'q6', 'correct': false, 'feedback': 'फिर देखें'},
    }));
    expect(a.nextQuestion!.id, 'q7');
    expect(a.nextQuestion!.options, ['1398', '1500']);
    expect(a.nextQuestion!.pramanId, 12);
    expect(a.quizResult!.correct, isFalse);
    final b = parseAskResponse(200, jsonEncode({'answer': 'x', 'next_question': null}));
    expect(b.nextQuestion, isNull);
    expect(b.quizResult, isNull);
    expect(buildAskBody('q', const [], const []).containsKey('mode'), isFalse);
    expect(buildAskBody('q', const [], const [], mode: 'gyan_charcha', quizReplyTo: 'q7'), containsPair('quiz_reply_to', {'question_id': 'q7'}));
    expect(stripNextQuestionTail('उत्तर।\n\n**अगला प्रश्न:** कबीर कौन?'), 'उत्तर।');
    expect(stripNextQuestionTail('केवल उत्तर'), 'केवल उत्तर');
  });

  test('quiz loop: mode sent, next question shown, option reply carries quiz_reply_to, result kept', () async {
    final fc = ModeClient([
      const AiAnswer(answer: 'उत्तर १\n\n**अगला प्रश्न:** प्रश्न १?', cited: [], provider: 'p', nextQuestion: QuizQuestion(id: 'q1', text: 'प्रश्न १?', options: ['क', 'ख'])),
      const AiAnswer(answer: 'ठीक', cited: [], provider: 'p', quizResult: QuizResult(questionId: 'q1', correct: true, feedback: 'सही')),
    ]);
    final ps = realPramans();
    final c = ChatController(client: fc, store: ChatStore.fresh(), pramans: () => ps, version: () => 7);
    await c.load();
    expect(await c.startGyan(), isTrue);
    expect(fc.sent.last, ('gyan_charcha', null));
    expect(c.messages.where((m) => !m.isUser).length, 1, reason: 'only the question, not duplicate prose/options');
    expect(c.messages.last.quizQuestion!.options, ['क', 'ख']);
    expect(c.quiz!.q.id, 'q1');
    expect(c.messages.last.text, contains('प्रश्न १?'));
    expect(c.offerNext, isFalse);
    await c.answerQuiz('क');
    expect(fc.sent.last, ('gyan_charcha', 'q1'));
    expect(c.quiz, isNull);
    expect(c.messages.last.quizResult!.correct, isTrue);
    expect(c.offerNext, isTrue);
    expect(fc.mode, isNull);
    // a normal chat never sends the mode
    c.newChat();
    fc.script.add(const AiAnswer(answer: 'x', cited: [], provider: 'p'));
    await c.send('सामान्य प्रश्न');
    expect(fc.sent.last, (null, null));
  });

  test('worker returns no next_question → नया प्रश्न resends with the mode', () async {
    final fc = ModeClient([
      const AiAnswer(answer: 'अभी प्रश्न नहीं बना', cited: [], provider: 'p'),
      const AiAnswer(answer: 'ठीक', cited: [], provider: 'p', nextQuestion: QuizQuestion(id: 'q2', text: 'प्रश्न २?')),
    ]);
    final ps = realPramans();
    final c = ChatController(client: fc, store: ChatStore.fresh(), pramans: () => ps, version: () => 7);
    await c.load();
    await c.startGyan();
    expect(c.offerNext, isTrue);
    await c.nextQuestion();
    expect(fc.sent.last, ('gyan_charcha', null));
    expect(c.quiz!.q.id, 'q2');
  });
  test('same quiz question is not shown twice in one conversation', () async {
    const repeated = QuizQuestion(id: 'same', text: 'एक ही प्रश्न?', options: ['क', 'ख']);
    final fc = ModeClient([
      const AiAnswer(answer: '**अगला प्रश्न:** एक ही प्रश्न?', cited: [], provider: 'p', nextQuestion: repeated),
      const AiAnswer(answer: 'सही', cited: [], provider: 'p', quizResult: QuizResult(questionId: 'same', correct: true), nextQuestion: repeated),
    ]);
    final ps = realPramans();
    final c = ChatController(client: fc, store: ChatStore.fresh(), pramans: () => ps, version: () => 7);
    await c.load();
    await c.startGyan();
    await c.answerQuiz('क');
    expect(c.quiz, isNull);
    expect(c.offerNext, isTrue);
    expect(c.messages.where((m) => m.text.contains('एक ही प्रश्न?')).length, 1);
  });

}
