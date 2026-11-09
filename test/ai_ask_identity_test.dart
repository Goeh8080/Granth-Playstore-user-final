// POST /ask carries the stable install id (and the uid when signed in) over a real socket.
// Kept apart from widget tests: TestWidgetsFlutterBinding answers every HttpClient with 400.
import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:granthprabandhan/ai/ai_client.dart';
import 'package:granthprabandhan/ai/retriever.dart';

const _iid = '0123456789abcdef0123456789abcdef';

void main() {
    test('the client sends iid always and uid only when signed in', () async {
      final bodies = <Map>[];
      final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
      addTearDown(() => server.close(force: true));
      server.listen((req) async {
        bodies.add(jsonDecode(await utf8.decoder.bind(req).join()) as Map);
        req.response
          ..headers.contentType = ContentType.json
          ..write(jsonEncode({'answer': 'ok', 'cited': [], 'provider': 'p'}));
        await req.response.close();
      });
      String? uid;
      final client = AiClient(endpoint: 'http://127.0.0.1:${server.port}', iid: () => _iid, uid: () => uid);
      await client.ask('q', const [], const <Candidate>[]);
      uid = 'firebaseUid1';
      await client.ask('q', const [], const <Candidate>[]);
      expect(bodies[0]['iid'], _iid);
      expect(bodies[0].containsKey('uid'), isFalse);
      expect(bodies[1]['uid'], 'firebaseUid1');
      final throwing = AiClient(endpoint: 'http://127.0.0.1:${server.port}', iid: () => throw StateError('x'), uid: () => throw StateError('y'));
      await throwing.ask('q', const [], const <Candidate>[]);
      expect(bodies[2].containsKey('iid'), isFalse);
    });
}
