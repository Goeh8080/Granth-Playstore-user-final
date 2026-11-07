import 'dart:convert';

import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart' hide Fake;
import 'package:granthprabandhan/services/ai_feedback.dart';

import 'helpers.dart';
import 'round14_test.dart' show Fake;

void main() {
  setUp(setUpApp);
  AiFeedback make(Fake f) => AiFeedback(dio: Dio()..httpClientAdapter = f, base: 'https://a.test', appKey: 'k', iid: () => 'iid1', enabled: true);
  Map body(RequestOptions o) => (o.data is String ? jsonDecode(o.data as String) : o.data) as Map;

  test('`at` is sent as an ISO-8601 UTC string', () async {
    final f = Fake([200]);
    await make(f).down('a', question: 'q', answer: 'x');
    final at = body(f.seen.single)['at'];
    expect(at, isA<String>());
    expect(DateTime.parse(at as String).isUtc, isTrue);
    expect(AiFeedback.isoAt(1700000000), '2023-11-14T22:13:20.000Z');
  });

  for (final code in [400, 413]) {
    test('$code is NOT done: stays queued and is surfaced', () async {
      final f = Fake([code, 200]);
      final fb = make(f);
      await fb.down('b', question: 'q', answer: 'x');
      expect(fb.queue.length, 1);
      expect(fb.lastRejected, code);
      expect(await fb.flush(), 1);
      expect(fb.queue, isEmpty);
      expect(fb.lastRejected, isNull);
    });
  }
}
