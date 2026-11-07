// OFFLINE HTTP mocks of reviewed backend7cbcb93 §25. No live or Google-token-verification claim.
import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';
import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:granthprabandhan/ai/quiz_v2_flow.dart';
import 'package:granthprabandhan/ai/v2_drafts.dart';
import 'ai_v2_offline_test.dart' show capabilities, publicQuestion, publicGrade;
import 'helpers.dart';

class QuizNet implements HttpClientAdapter {
  final paths = <String>[],
      bodies = <Map<String, dynamic>>[],
      headers = <Map<String, dynamic>>[];
  int capStatus = 200, nextStatus = 200, flagsStatus = 202, attemptStatus = 200;
  Object? nextOverride, attemptOverride;
  List<String>? flagContexts;
  bool enabled = true, failNext = false;
  Completer<void>? gate;
  @override
  Future<ResponseBody> fetch(
    RequestOptions o,
    Stream<Uint8List>? s,
    Future<void>? c,
  ) async {
    paths.add(o.path);
    headers.add(o.headers);
    final b = o.data is String ? jsonDecode(o.data) : o.data;
    bodies.add(b is Map<String, dynamic> ? b : {});
    if (o.path.endsWith('/capabilities')) {
      final cap = capabilities(enabled: enabled);
      if (flagContexts != null) {
        (cap['flags'] as Map)['contexts'] = flagContexts;
      }
      return ResponseBody.fromString(jsonEncode(cap), capStatus);
    }
    if (o.path.endsWith('/flags')) {
      return ResponseBody.fromString(
        flagsStatus == 202 ? '{"id":7}' : '{"error":"unavailable"}',
        flagsStatus,
      );
    }
    if (gate != null) await gate!.future;
    if (o.path.endsWith('/session')) {
      return ResponseBody.fromString(
        jsonEncode({
          'schema_version': 2,
          'state': 'choose_source',
          'session_id': 's_111111111111111111111111',
          'source_choices': [
            {'id': 'ved', 'label': 'वेद से'},
            {'id': 'puran', 'label': 'पुराण से'},
            {'id': 'all', 'label': 'सारे ग्रंथ'},
          ],
          'question': null,
          'result': null,
        }),
        201,
      );
    }
    if (o.path.endsWith('/next')) {
      if (failNext) {
        failNext = false;
        throw DioException(
          requestOptions: o,
          type: DioExceptionType.connectionError,
        );
      }
      return ResponseBody.fromString(
        jsonEncode(nextOverride ?? publicQuestion()),
        nextStatus,
      );
    }
    return ResponseBody.fromString(
      jsonEncode(attemptOverride ?? publicGrade()),
      attemptStatus,
    );
  }

  @override
  void close({bool force = false}) {}
}

void main() {
  setUp(setUpApp);
  late QuizNet net;
  String? owner;
  late AiV2Flow f;
  setUp(() {
    owner = 'owner-a';
    net = QuizNet();
    f = AiV2Flow(
      dio: Dio()..httpClientAdapter = net,
      base: 'https://offline.invalid',
      appKey: 'test-key',
      owner: () => owner,
      token: () async => 'mock-firebase-id-token',
      rollout: true,
      drafts: AiV2DraftStore(),
    );
  });
  test(
    'OFFLINE: rollout OFF/404/disabled stay safe and never send v2 protocol to legacy ask',
    () async {
      final off = AiV2Flow(
        dio: Dio()..httpClientAdapter = net,
        owner: () => owner,
        token: () async => 'mock',
        rollout: false,
      );
      expect(await off.prepare(), 'legacy');
      expect(net.paths, isEmpty);
      net.capStatus = 404;
      expect(await f.prepare(), 'legacy');
      expect(net.paths.length, 1);
      net.capStatus = 200;
      net.enabled = false;
      expect(await f.prepare(), 'disabled');
      expect(net.paths.any((p) => p.contains('/session')), isFalse);
    },
  );
  test(
    'OFFLINE: source-locked verified-owner requests, persistent retry id and post-submit colors',
    () async {
      expect(await f.prepare(), 'ready');
      expect(f.state, 'choose_source');
      net.failNext = true;
      await f.chooseSource('ved');
      expect(f.errorCode, isNotNull);
      final before = net.bodies.last;
      expect(before['source'], 'ved');
      expect(f.question, isNull);
      await f.retry();
      expect(net.bodies.last, before);
      expect(f.question!.source, 'ved');
      expect(f.grade, isNull);
      expect(
        net.headers.last['Authorization'],
        'Bearer mock-firebase-id-token',
      );
      expect(net.headers.last['X-App-Key'], 'test-key');
      await f.submit('a');
      expect(f.state, 'graded');
      expect(f.grade!.correctByOption['a'], isFalse);
      expect(f.grade!.correctByOption['b'], isTrue);
      expect(net.paths.any((p) => p.contains('/ask')), isFalse);
      expect(
        net.bodies.any(
          (b) => b.containsKey('uid') || b.containsKey('id_token'),
        ),
        isFalse,
      );
    },
  );
  test(
    'OFFLINE: account change drops late response and cannot reuse other account pending operation',
    () async {
      net.gate = Completer<void>();
      final prepare = f.prepare();
      await Future<void>.delayed(Duration.zero);
      owner = 'owner-b';
      net.gate!.complete();
      await prepare;
      expect(f.question, isNull);
      expect(f.sessionId, isNull);
      expect(AiV2DraftStore().pendingQuiz('owner-b'), isNull);
    },
  );
  test(
    'OFFLINE: separate context reports retain stable id and become delivered only on202 ACK',
    () async {
      expect(
        await f.tryReportChat('msg1', question: 'प्रश्न', answer: 'उत्तर'),
        'queued',
      );
      await f.flushReports();
      expect(f.reportStatus('msg1'), 'sent');
      final sent = net.bodies
          .where(
            (b) => b['schema_version'] == 2 && b['context'] == 'normal_chat',
          )
          .single;
      expect(sent['client_report_id'], isNotEmpty);
      expect(sent.containsKey('attempt_id'), isFalse);
    },
  );
  test(
    'OFFLINE: exhaustion never falls back across sources; outage is not exhaustion',
    () async {
      await f.prepare();
      net.nextOverride = {
        'schema_version': 2,
        'session_id': 's_111111111111111111111111',
        'source': 'ved',
        'state': 'exhausted',
        'reason': 'all_seen',
        'can_change_source': true,
        'question': null,
        'result': null,
      };
      await f.chooseSource('ved');
      expect(f.state, 'exhausted');
      expect(f.exhaustionReason, 'all_seen');
      expect(net.bodies.last['source'], 'ved');
      await f.changeSource();
      expect(f.state, 'choose_source');
      net.nextStatus = 503;
      net.nextOverride = {'schema_version': 2, 'error': 'catalog_unavailable'};
      await f.chooseSource('puran');
      expect(f.state, isNot('exhausted'));
      expect(f.errorCode, 'catalog_unavailable');
    },
  );
  test(
    'OFFLINE: concurrent thumbs-downs reuse one stable report identity',
    () async {
      await Future.wait([
        f.tryReportChat('same', question: 'प्रश्न', answer: 'उत्तर'),
        f.tryReportChat('same', question: 'प्रश्न', answer: 'उत्तर'),
      ]);
      expect(AiV2DraftStore().reports('owner-a').length, 1);
    },
  );
  test('OFFLINE immutable attempt retry survives process restart', () async {
    await f.prepare();
    await f.chooseSource('ved');
    net.attemptStatus = 503;
    net.attemptOverride = {'error': 'unavailable'};
    await f.submit('a');
    final body = Map<String, dynamic>.of(net.bodies.last);
    expect(f.pending, true);
    final resumed = AiV2Flow(
      dio: Dio()..httpClientAdapter = net,
      base: 'https://offline.invalid',
      appKey: 'test-key',
      owner: () => owner,
      token: () async => 'mock-firebase-id-token',
      rollout: true,
      drafts: AiV2DraftStore(),
    );
    net.attemptStatus = 200;
    net.attemptOverride = null;
    await resumed.prepare();
    expect(resumed.state, 'graded');
    expect(net.bodies.last, body);
    expect(resumed.pending, false);
  });
  test(
    'OFFLINE bound410 is not retried forever; advancing uses a NEW request ID',
    () async {
      await f.prepare();
      net.nextStatus = 410;
      net.nextOverride = {'error': 'question_unavailable'};
      await f.chooseSource('ved');
      final id = net.bodies.last['request_id'];
      expect(f.pending, false);
      expect(f.canAdvance, true);
      net.nextStatus = 200;
      net.nextOverride = null;
      await f.next();
      expect(net.bodies.last['request_id'], isNot(id));
      expect(net.bodies.last['source'], 'ved');
      expect(f.question, isNotNull);
    },
  );
  test(
    'OFFLINE pre-submit answer-key envelope is rejected, not rendered or saved',
    () async {
      await f.prepare();
      final leaked = publicQuestion();
      (leaked['question'] as Map)['correct_option_id'] = 'b';
      net.nextOverride = leaked;
      await f.chooseSource('ved');
      expect(f.question, isNull);
      expect(f.grade, isNull);
      expect(f.errorCode, 'invalid_response');
    },
  );

  test(
    'OFFLINE historical legacy quiz cannot be mislabeled as a v2 normal-chat flag',
    () async {
      expect(
        await f.tryReportChat(
          'legacy-quiz',
          question: 'q',
          answer: 'a',
          legacyQuiz: true,
        ),
        'legacy_quiz',
      );
      expect(f.drafts.reports('owner-a'), isEmpty);
    },
  );
  test(
    'OFFLINE one disabled flags context does not block another enabled context',
    () async {
      await f.prepare();
      await f.chooseSource('ved');
      expect(await f.reportQuiz(), 'queued');
      expect(
        await f.tryReportChat('normal', question: 'q', answer: 'a'),
        'queued',
      );
      net.flagContexts = ['normal_chat'];
      await f.flushReports();
      expect(f.quizReportStatus, 'queued');
      expect(f.reportStatus('normal'), 'sent');
    },
  );
}
