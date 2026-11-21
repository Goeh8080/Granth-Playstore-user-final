// POST /ask carries the stable install id, app_version and (signed in with Google) the Firebase
// id_token in the JSON body over a real socket (t421: no uid, no Authorization header).
// Kept apart from widget tests: TestWidgetsFlutterBinding answers every HttpClient with 400.
import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:granthprabandhan/ai/ai_client.dart';
import 'package:granthprabandhan/ai/retriever.dart';

const _iid = '0123456789abcdef0123456789abcdef';

void main() {
    test('the client sends iid + app_version always and id_token only when signed in', () async {
      final bodies = <Map>[];
      final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
      addTearDown(() => server.close(force: true));
      server.listen((req) async {
        expect(req.headers.value('authorization'), isNull);
        bodies.add(jsonDecode(await utf8.decoder.bind(req).join()) as Map);
        req.response
          ..headers.contentType = ContentType.json
          ..write(jsonEncode({'answer': 'ok', 'cited': [], 'provider': 'p'}));
        await req.response.close();
      });
      String? tok;
      final client = AiClient(endpoint: 'http://127.0.0.1:${server.port}', iid: () => _iid, uid: () => 'firebaseUid1', idToken: () async => tok);
      await client.ask('q', const [], const <Candidate>[]);
      tok = 'eyJhbGciOi.eyJzdWIiOi.c2lnbmF0dXJl';
      await client.ask('q', const [], const <Candidate>[]);
      expect(bodies[0]['iid'], _iid);
      expect(bodies[0]['app_version'], '1.0.1');
      expect(bodies[0].containsKey('id_token'), isFalse);
      expect(bodies[1]['id_token'], tok);
      expect(bodies.every((b) => !b.containsKey('uid')), isTrue);
      final throwing = AiClient(endpoint: 'http://127.0.0.1:${server.port}', iid: () => throw StateError('x'), idToken: () async => throw StateError('y'));
      await throwing.ask('q', const [], const <Candidate>[]);
      expect(bodies[2].containsKey('iid'), isFalse);
    });
}
