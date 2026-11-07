// OFFLINE ONLY: local draft/idempotency storage is NOT Google verification or backend proof.
import 'dart:convert';
import 'package:flutter_test/flutter_test.dart';
import 'package:granthprabandhan/ai/quiz_v2.dart';
import 'package:granthprabandhan/ai/v2_drafts.dart';
import 'package:granthprabandhan/services/storage.dart';
import 'ai_v2_offline_test.dart' show publicQuestion, capabilities;
import 'helpers.dart';

void main() {
  setUp(setUpApp);
  test(
    'OFFLINE: stable exact request bodies never use legacy ask or client identity claims',
    () {
      final create = QuizV2Command.create('request-create');
      expect(create.path, '/ai/quiz/session');
      expect(create.body, {
        'schema_version': 2,
        'request_id': 'request-create',
      });
      final next = QuizV2Command.next(
        's_111111111111111111111111',
        'ved',
        'request-next',
      );
      expect(next.body, {
        'schema_version': 2,
        'request_id': 'request-next',
        'source': 'ved',
        'supported_question_types': ['single_choice'],
      });
      final q = QuizV2Question.parse(publicQuestion())!;
      final attempt = QuizV2Command.attempt(q, 'a', 'request-attempt');
      expect(attempt.body, {
        'schema_version': 2,
        'request_id': 'request-attempt',
        'attempt_id': q.attemptId,
        'question_id': q.id,
        'revision': 1,
        'answer': {'type': 'single_choice', 'option_id': 'a'},
      });
      expect(
        QuizV2Command.restore(jsonDecode(jsonEncode(attempt.toJson())))!.body,
        attempt.body,
      );
      expect(jsonEncode(attempt.body), isNot(contains('uid')));
      expect(attempt.path, isNot(contains('/ask')));
      expect(
        () => QuizV2Command.next(next.sessionId!, 'unknown', 'r'),
        throwsArgumentError,
      );
      expect(
        () => QuizV2Command.attempt(q, 'unknown', 'r'),
        throwsArgumentError,
      );
      expect(
        () => attempt.body['request_id'] = 'changed',
        throwsUnsupportedError,
      );
    },
  );
  test(
    'OFFLINE: pending op survives restart; concurrent taps cannot replace stable ID; owner isolation',
    () async {
      final store = AiV2DraftStore();
      final c = QuizV2Command.create('stable-create');
      final d = QuizV2Command.create('other-create');
      expect(
        await Future.wait([
          store.saveQuiz('owner-a', c),
          store.saveQuiz('owner-a', d),
        ]),
        [true, false],
      );
      expect(AiV2DraftStore().pendingQuiz('owner-a')!.body, c.body);
      expect(store.pendingQuiz('owner-b'), isNull);
      await store.clearQuiz('owner-a', 'other-create');
      expect(store.pendingQuiz('owner-a'), isNotNull);
      await store.clearQuiz('owner-a', 'stable-create');
      expect(store.pendingQuiz('owner-a'), isNull);
    },
  );
  test(
    'OFFLINE: independent flags contexts/report identity, no token storage, real ACK only',
    () async {
      final store = AiV2DraftStore();
      final q = QuizV2Question.parse(publicQuestion())!;
      final gc = AiV2ReportDraft.quiz(q, reportId: 'report-gc');
      final chat = AiV2ReportDraft.chat(
        question: 'प्रश्न',
        answer: 'उत्तर',
        reportId: 'report-chat',
        correction: 'सही उत्तर',
      );
      expect(gc.body['context'], 'gyan_charcha');
      expect(gc.body.containsKey('question'), isFalse);
      expect(gc.body['attempt_id'], q.attemptId);
      expect(chat.body['context'], 'normal_chat');
      expect(chat.body['kind'], 'correction');
      await store.queueReport('owner-a', gc);
      await store.queueReport('owner-a', chat);
      expect(store.reportStatus('owner-a', 'report-gc'), 'queued');
      expect(store.reportStatus('owner-b', 'report-gc'), isNull);
      expect(AiV2DraftStore().reports('owner-a').length, 2);
      expect(
        await store.ackReport('owner-a', 'report-gc', 200, {'id': 7}),
        isFalse,
      );
      expect(await store.ackReport('owner-a', 'report-gc', 202, {}), isFalse);
      expect(
        await store.ackReport('owner-a', 'report-gc', 202, {
          'id': 7,
          'duplicate': true,
        }),
        isTrue,
      );
      expect(store.reportStatus('owner-a', 'report-gc'), 'sent');
      final raw = Store.I.getString('granth-ai-v2-flags:owner-a')!;
      expect(raw, isNot(contains('Bearer')));
      expect(raw, isNot(contains('id_token')));
      expect(
        gc.canSend(
          AiV2Capabilities.parse(capabilities()),
          owner: 'owner-a',
          currentOwner: 'owner-b',
          reviewed: true,
        ),
        isFalse,
      );
      expect(
        gc.canSend(
          AiV2Capabilities.parse(capabilities()),
          owner: 'owner-a',
          currentOwner: 'owner-a',
        ),
        isFalse,
        reason: 'production review gate is OFF',
      );
    },
  );
  test('OFFLINE: over-budget UTF-8 reports are not falsely queued', () async {
    final huge = AiV2ReportDraft.chat(
      question: 'क' * 500,
      answer: 'क' * 2000,
      correction: 'क' * 2000,
      reportId: 'large',
    );
    await expectLater(
      AiV2DraftStore().queueReport('owner-a', huge),
      throwsStateError,
    );
  });
  test(
    'OFFLINE account deletion clears only that owner pending operations/reports/session',
    () async {
      final d = AiV2DraftStore();
      await d.saveQuiz('owner-a', QuizV2Command.create('a'));
      await d.saveQuiz('owner-b', QuizV2Command.create('b'));
      await d.queueReport(
        'owner-a',
        AiV2ReportDraft.chat(question: 'q', answer: 'a', reportId: 'flag-a'),
      );
      await Store.I.setString('granth-ai-v2-session:owner-a', 'local');
      await d.clearOwner('owner-a');
      expect(d.pendingQuiz('owner-a'), isNull);
      expect(d.reports('owner-a'), isEmpty);
      expect(Store.I.getString('granth-ai-v2-session:owner-a'), isNull);
      expect(d.pendingQuiz('owner-b'), isNotNull);
    },
  );
}
