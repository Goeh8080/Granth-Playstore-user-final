// OFFLINE contract tests only. §25 is LOCAL/UNREVIEWED, not evidence of a live backend.
import 'package:flutter_test/flutter_test.dart';
import 'package:granthprabandhan/ai/quiz_v2.dart';

Map<String, dynamic> capabilities({bool enabled = true}) => {
  'schema_version': 1,
  'settings_version': 1,
  'chat_versions': [1],
  'quiz': {
    'versions': [2],
    'enabled': enabled,
    'sources': ['ved', 'puran', 'all'],
    'question_types': ['single_choice'],
    'identity': 'verified_google',
    'reveal': 'after_submit',
    'strict_source': true,
    'no_repeats': true,
    'endpoints': {
      'create': '/ai/quiz/session',
      'next': '/ai/quiz/session/{session_id}/next',
      'attempt': '/ai/quiz/session/{session_id}/attempt',
    },
  },
  'flags': {
    'versions': [1, 2],
    'contexts': ['normal_chat', 'gyan_charcha'],
    'kinds': ['thumbs_down', 'correction'],
  },
  'navigator': {'versions': [], 'enabled': false, 'interpret_available': false},
};
Map<String, dynamic> publicQuestion() => {
  'schema_version': 2,
  'session_id': 's_111111111111111111111111',
  'source': 'ved',
  'state': 'question',
  'bank_version': 1,
  'suppression_version': 1,
  'question': {
    'question_id': 'q_1111111111111111',
    'revision': 1,
    'attempt_id': 'a_111111111111111111111111',
    'type': 'single_choice',
    'text': 'किस ग्रंथ का उदाहरण है?',
    'options': [
      for (final id in ['a', 'b', 'c', 'd']) {'id': id, 'text': 'विकल्प $id'},
    ],
  },
  'result': null,
};
Map<String, dynamic> publicGrade() => {
  'schema_version': 2,
  'session_id': 's_111111111111111111111111',
  'state': 'graded',
  'question': null,
  'can_request_next': true,
  'result': {
    'attempt_id': 'a_111111111111111111111111',
    'question_id': 'q_1111111111111111',
    'revision': 1,
    'status': 'graded',
    'correct': false,
    'selected_option_ids': ['a'],
    'correct_option_ids': ['b'],
    'option_results': [
      for (final id in ['a', 'b', 'c', 'd'])
        {'id': id, 'is_correct': id == 'b', 'selected': id == 'a'},
    ],
    'feedback': 'जमा करने के बाद जानकारी',
    'refs': [],
  },
};
void main() {
  test(
    'OFFLINE: exact §25 capabilities enable only reviewed single-choice shape',
    () {
      expect(AiV2Capabilities.parse(capabilities()).quizEnabled, isTrue);
      expect(
        AiV2Capabilities.parse(capabilities(enabled: false)).quizEnabled,
        isFalse,
      );
      expect(AiV2Capabilities.parse({}).quizEnabled, isFalse);
      final malicious = capabilities();
      (malicious['quiz'] as Map)['endpoints']['create'] =
          'https://elsewhere.invalid/steal';
      expect(AiV2Capabilities.parse(malicious).quizEnabled, isFalse);
      final earlyReveal = capabilities();
      (earlyReveal['quiz'] as Map)['reveal'] = 'before_submit';
      expect(AiV2Capabilities.parse(earlyReveal).quizEnabled, isFalse);
    },
  );
  test(
    'OFFLINE: public question is question/options only; answer-key leaks fail closed',
    () {
      final q = QuizV2Question.parse(publicQuestion());
      expect(q, isNotNull);
      expect(q!.options.length, 4);
      expect(q.text, 'किस ग्रंथ का उदाहरण है?');
      final leaked = publicQuestion();
      (leaked['question'] as Map)['correct_option_id'] = 'b';
      expect(QuizV2Question.parse(leaked), isNull);
      final early = publicQuestion();
      early['result'] = {
        'correct_option_ids': ['b'],
      };
      expect(QuizV2Question.parse(early), isNull);
      final unsupported = publicQuestion();
      (unsupported['question'] as Map)['type'] = 'multi_choice';
      expect(QuizV2Question.parse(unsupported), isNull);
    },
  );
  test(
    'OFFLINE: post-submit result binds immutable attempt/revision and all option colors',
    () {
      final q = QuizV2Question.parse(publicQuestion())!;
      final grade = QuizV2Grade.parse(publicGrade(), q, 'a');
      expect(grade, isNotNull);
      expect(grade!.correctByOption, {
        'a': false,
        'b': true,
        'c': false,
        'd': false,
      });
      final mismatch = publicGrade();
      (mismatch['result'] as Map)['revision'] = 2;
      expect(QuizV2Grade.parse(mismatch, q, 'a'), isNull);
      expect(QuizV2Grade.parse(publicGrade(), q, 'c'), isNull);
      final incomplete = publicGrade();
      ((incomplete['result'] as Map)['option_results'] as List).removeLast();
      expect(QuizV2Grade.parse(incomplete, q, 'a'), isNull);
    },
  );
}
