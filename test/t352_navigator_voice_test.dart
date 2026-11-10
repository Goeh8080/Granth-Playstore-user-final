// t352: Navigator speaks in a server (ElevenLabs) voice via the Worker's /tts, robust
// listening (alternates, fuzzy wake, retries) and the voice picker.
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:granthprabandhan/ai/navigator/nav_intent.dart';
import 'package:granthprabandhan/ai/navigator/nav_tts.dart';
import 'package:granthprabandhan/ai/navigator/nav_voice_sheet.dart';
import 'package:granthprabandhan/ai/navigator/voice_navigator.dart';
import 'package:granthprabandhan/services/catalog_store.dart';
import 'package:granthprabandhan/services/remote_config.dart';
import 'package:granthprabandhan/services/shelves.dart';
import 'package:granthprabandhan/services/storage.dart';
import 'package:granthprabandhan/state/router.dart';
import 'package:granthprabandhan/state/toast.dart';
import 'helpers.dart';

final _mp3 = Uint8List.fromList(List<int>.generate(400, (i) => i % 251));

class _Call {
  _Call(this.method, this.url, this.headers, this.body);
  final String method;
  final Uri url;
  final Map<String, String> headers;
  final Map<String, dynamic>? body;
}

/// Mock Worker: records calls, answers with [status] (200 → MP3 / voices JSON).
class _Worker {
  int status = 200;
  Duration? retryAfter;
  String contentType = 'audio/mpeg';
  final calls = <_Call>[];
  List<_Call> get posts => calls.where((c) => c.method == 'POST').toList();

  Future<TtsReply> call(String method, Uri url, Map<String, String> headers, List<int>? body, Duration timeout) async {
    calls.add(_Call(method, url, headers, body == null ? null : jsonDecode(utf8.decode(body)) as Map<String, dynamic>));
    if (status != 200) return (status: status, contentType: 'application/json', body: Uint8List.fromList(utf8.encode('{"error":"x"}')), retryAfter: retryAfter);
    if (method == 'GET') {
      return (
        status: 200,
        contentType: 'application/json',
        body: Uint8List.fromList(utf8.encode(jsonEncode({
          'voices': [
            {'id': 'kvQSb3naDTi3sgHwwBC1', 'name': 'Monika', 'gender': 'female'},
            {'id': 'm5qndnI7u4OAdXhH0Mr5', 'name': 'Krishna', 'gender': 'male'},
          ],
          'default_voice_id': 'kvQSb3naDTi3sgHwwBC1',
        }))),
        retryAfter: null,
      );
    }
    return (status: 200, contentType: contentType, body: _mp3, retryAfter: null);
  }

  TtsClient client({String endpoint = 'https://w.example', String path = kTtsPath}) => TtsClient(endpoint: endpoint, path: path, transport: call, iid: () => 'a' * 32, uid: () => null);
}

class _Audio implements NavAudio {
  _Audio([this.speech]);
  final _Speech? speech;
  final plays = <int>[];
  final local = <String>[];
  bool micOnWhilePlaying = false;
  bool phone = false;
  @override
  Future<bool> play(Uint8List bytes, String mime) async {
    if (speech?.listening ?? false) micOnWhilePlaying = true;
    plays.add(bytes.length);
    return true;
  }

  @override
  Future<void> stop() async {}
  @override
  Future<bool> hasLocalVoice() async => phone;
  @override
  Future<bool> speakLocal(String text, {String lang = 'hi-IN'}) async {
    if (!phone) return false;
    local.add(text);
    return true;
  }
}

class _Speech implements NavSpeech {
  int inits = 0, listens = 0;
  final commands = <bool>[];
  void Function(NavHeard)? onHeard;
  void Function(String?)? onDone;
  @override
  bool listening = false;
  @override
  Future<bool> init() async {
    inits++;
    return true;
  }

  @override
  Future<void> listen({required void Function(NavHeard heard) onHeard, required void Function(String? error) onDone, required Duration listenFor, required Duration pauseFor, bool command = true}) async {
    listens++;
    commands.add(command);
    listening = true;
    this.onHeard = onHeard;
    this.onDone = (e) {
      listening = false;
      onDone(e);
    };
  }

  @override
  Future<void> stop() async => listening = false;
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late NavCatalog cat;
  setUp(() async {
    await setUpApp();
    RemoteConfig.I.debugReset();
    final s = CatalogStore.I;
    cat = NavCatalog.build(structure: Shelves.structure, granths: s.granths, topics: s.topics, placements: Shelves.indexFor(s.granths).placements);
  });

  group('TtsClient (w13 contract)', () {
    test('POST {base}/tts with the /ask header, JSON body text/lang/voice_id/iid → MP3', () async {
      final w = _Worker();
      final r = await w.client().synth('  वेद खोल रहा हूँ ', voiceId: 'm5qndnI7u4OAdXhH0Mr5');
      expect(r!.bytes, _mp3);
      expect(r.mime, 'audio/mpeg');
      final c = w.calls.single;
      expect(c.method, 'POST');
      expect(c.url.toString(), 'https://w.example/tts');
      expect(c.headers['X-Granth-Client'], 'granth-app-1');
      expect(c.headers['Content-Type'], startsWith('application/json'));
      expect(c.headers['User-Agent'], isNotEmpty);
      expect(c.body, {'text': 'वेद खोल रहा हूँ', 'lang': 'hi', 'voice_id': 'm5qndnI7u4OAdXhH0Mr5', 'iid': 'a' * 32});
      expect(c.headers.values.join(' ').toLowerCase(), isNot(contains('eleven')), reason: 'no provider key in the app');
    });

    test('voice_id omitted when none chosen; path configurable; text capped at 300', () async {
      final w = _Worker();
      await w.client(path: 'speak').synth('x' * 400);
      expect(w.calls.single.url.toString(), 'https://w.example/speak');
      expect(w.calls.single.body!.containsKey('voice_id'), isFalse);
      expect((w.calls.single.body!['text'] as String).length, 300);
    });

    test('base: endpoints.tts → endpoints.ai → built-in prod (never the preview default)', () {
      expect(TtsClient().endpoint, 'https://granth-ai.vedpuran8090.workers.dev');
      RemoteConfig.I.aiEndpoint = 'https://ai.example';
      expect(TtsClient().url.toString(), 'https://ai.example/tts');
      RemoteConfig.I.ttsEndpoint = 'https://granth-ai-preview.vedpuran8090.workers.dev';
      expect(TtsClient().voicesUrl.toString(), 'https://granth-ai-preview.vedpuran8090.workers.dev/tts/voices');
      expect(parseHttpsBase('https://t.example/'), 'https://t.example');
      expect(parseHttpsBase('http://insecure.example'), isNull);
    });

    test('503 / 429 / 404 / 401 / HTML / empty / thrown → null, never throws', () async {
      for (final s in [503, 429, 404, 405, 401, 413, 415, 500]) {
        final w = _Worker()..status = s;
        final c = w.client();
        expect(await c.synth('हाँ'), isNull, reason: '$s');
        expect(c.lastStatus, s);
      }
      final html = _Worker()..contentType = 'text/html';
      expect(await html.client().synth('हाँ'), isNull);
      final boom = TtsClient(endpoint: 'https://w.example', transport: (m, u, h, b, t) async => throw const SocketException('down'));
      expect(await boom.synth('हाँ'), isNull);
      expect(boom.lastFail, TtsFail.offline);
      expect(await boom.voices(), isNull);
    });

    test('GET /tts/voices → list + default; saved for the picker; bundled list offline', () async {
      expect(navServerVoices().map((v) => v.name), ['Monika', 'Krishna', 'Talia', 'Finley'], reason: 'bundled');
      expect(navServerVoices().where((v) => v.gender == 'male'), isNotEmpty);
      expect(navServerVoices().where((v) => v.gender == 'female'), isNotEmpty);
      final w = _Worker();
      expect(await refreshNavVoices(w.client()), isTrue);
      expect(w.calls.single.method, 'GET');
      expect(w.calls.single.url.toString(), 'https://w.example/tts/voices');
      expect(w.calls.single.headers['X-Granth-Client'], 'granth-app-1');
      expect(navServerVoices().map((v) => v.id), ['kvQSb3naDTi3sgHwwBC1', 'm5qndnI7u4OAdXhH0Mr5']);
      expect(navDefaultVoice(), 'kvQSb3naDTi3sgHwwBC1');
      expect(await refreshNavVoices((_Worker()..status = 404).client()), isFalse);
      expect(navServerVoices().length, 2, reason: 'a failed refresh keeps the last list');
    });

    test('ui.navigator_voices (admin) parsed; bad ids skipped; fallback bundled', () {
      expect(parseNavigatorVoices(null), kNavDefaultVoices);
      expect(parseNavigatorVoices({'navigator_voices': 'x'}), kNavDefaultVoices);
      final v = parseNavigatorVoices({
        'navigator_voices': [
          {'id': 'abcDEF123', 'name': 'Arjun', 'gender': 'male'},
          {'id': 'bad id!', 'name': 'X'},
          {'id': 'f00', 'gender': 'F'},
        ],
      });
      expect(v.map((e) => e.id), ['abcDEF123', 'f00']);
      expect(v.last.gender, 'female');
      expect(v.last.name, 'महिला आवाज़');
    });

    test('real dart:io transport against a local server (method, headers, body, Retry-After)', () async {
      await HttpOverrides.runWithHttpOverrides(() async {
        final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
        final seen = <String>[];
        server.listen((req) async {
          final body = await utf8.decoder.bind(req).join();
          seen.add('${req.method} ${req.uri.path} ${req.headers.value('x-granth-client')} $body');
          if (req.uri.path == '/tts' && body.contains('limit')) {
            req.response
              ..statusCode = 429
              ..headers.set('Retry-After', '30')
              ..write('{"error":"rate_limited"}');
          } else {
            req.response
              ..headers.contentType = ContentType('audio', 'mpeg')
              ..add(_mp3);
          }
          await req.response.close();
        });
        final c = TtsClient(endpoint: 'http://127.0.0.1:${server.port}', iid: () => null, uid: () => null);
        final r = await c.synth('नमस्ते');
        expect(r?.bytes, _mp3);
        expect(await c.synth('limit'), isNull);
        expect(c.lastFail, TtsFail.rateLimited);
        expect(c.lastRetryAfter, const Duration(seconds: 30));
        expect(seen.first, startsWith('POST /tts granth-app-1 {"text":"नमस्ते","lang":"hi"}'));
        await server.close(force: true);
      }, _RealHttp());
    });
  });

  group('NavSpeaker fallback', () {
    test('plays the clip; same phrase + voice comes from the cache', () async {
      final w = _Worker(), a = _Audio();
      final sp = NavSpeaker(client: w.client(), audio: a, voice: () => null);
      expect(await sp.say('वेद खोल रहा हूँ'), isTrue);
      expect(await sp.say('वेद खोल रहा हूँ'), isTrue);
      expect(w.posts.length, 1);
      expect(a.plays, [400, 400]);
      await sp.say('वेद खोल रहा हूँ', voiceId: 'm5qndnI7u4OAdXhH0Mr5');
      expect(w.posts.length, 2, reason: 'another voice is another clip');
    });

    for (final (status, wait) in [(503, const Duration(minutes: 2)), (429, const Duration(seconds: 30)), (404, const Duration(minutes: 10))]) {
      test('$status → silent (no audio, no throw, no toast) and backs off $wait', () async {
        var now = DateTime(2026, 11, 10, 9);
        final w = _Worker()
          ..status = status
          ..retryAfter = status == 429 ? const Duration(seconds: 30) : null;
        final a = _Audio();
        final sp = NavSpeaker(client: w.client(), audio: a, voice: () => null, now: () => now);
        final toasts = Toast.serial;
        expect(await sp.say('वेद खोल रहा हूँ'), isFalse);
        expect(a.plays, isEmpty);
        expect(Toast.serial, toasts);
        expect(sp.speaking, isFalse);
        expect(await sp.say('गीता खोल रहा हूँ'), isFalse);
        expect(w.posts.length, 1, reason: 'no new request while backing off');
        now = now.add(wait + const Duration(seconds: 1));
        w.status = 200;
        expect(await sp.say('गीता खोल रहा हूँ'), isTrue);
        expect(w.posts.length, 2);
      });
    }

    test('429 Retry-After 3600 is honoured (capped at 1 h)', () async {
      final now = DateTime(2026, 11, 10, 9);
      final w = _Worker()
        ..status = 429
        ..retryAfter = const Duration(hours: 5);
      final sp = NavSpeaker(client: w.client(), audio: _Audio(), voice: () => null, now: () => now);
      await sp.say('हाँ');
      expect(sp.offUntil, now.add(const Duration(hours: 1)));
    });

    test('server down → phone voice when the device has one; "phone" choice never calls the server', () async {
      final w = _Worker()..status = 503;
      final a = _Audio()..phone = true;
      final sp = NavSpeaker(client: w.client(), audio: a, voice: () => null);
      expect(await sp.say('वेद खोल रहा हूँ'), isTrue);
      expect(a.local, ['वेद खोल रहा हूँ']);
      final w2 = _Worker();
      final sp2 = NavSpeaker(client: w2.client(), audio: a, voice: () => kPhoneVoice);
      await sp2.say('हाँ');
      expect(w2.calls, isEmpty);
    });

    test('400 unknown voice_id → retried once with the Worker default', () async {
      final w = _Worker();
      final seen = <String?>[];
      final c = TtsClient(
        endpoint: 'https://w.example',
        iid: () => null,
        uid: () => null,
        transport: (m, u, h, b, t) async {
          final j = jsonDecode(utf8.decode(b!)) as Map;
          seen.add(j['voice_id'] as String?);
          return j['voice_id'] == null ? w.call(m, u, h, b, t) : (status: 400, contentType: 'application/json', body: Uint8List(0), retryAfter: null);
        },
      );
      final a = _Audio();
      expect(await NavSpeaker(client: c, audio: a, voice: () => 'gone').say('हाँ'), isTrue);
      expect(seen, ['gone', null]);
      expect(a.plays.length, 1);
    });
  });

  group('intents → routes', () {
    NavTarget one(String text) {
      final r = cat.interpret(text);
      expect(r, isA<NavIntent>(), reason: '"$text" → $r ${r is NavClarify ? r.choices.map((c) => c.id) : ''}');
      return (r as NavIntent).target;
    }

    test('pages and folders', () {
      final table = {
        'hey granth gallery kholo': ['#/gallery'],
        'tatv ai kholo': ['#/ai'],
        'हे ग्रंथ सेटिंग खोलो': ['#/settings'],
        'aaj ka praman dikhao': ['#/today'],
        'vishay kholo': ['#/topics'],
        'support': ['#/support'],
        'he granth ved kholo': ['#/granths', '#/granths?r=hindu', '#/granths?r=hindu&g=ved'],
        'gita kholo': ['#/granths', '#/granths?r=hindu', '#/granths?r=hindu&g=geeta'],
        'kabir sagar kholo': ['#/granths', '#/granths?r=kabir', '#/granths?r=kabir&g=kabir-sagar'],
      };
      table.forEach((t, steps) => expect(one(t).steps, steps, reason: t));
      expect(one('mrityu ke baad kya').steps, ['#/topics', '#/pramans?topic=1']);
    });

    test('voice commands → the voice picker action (no route)', () {
      for (final t in ['awaaz badlo', 'Hey Granth awaz badlo', 'voice change', 'change voice', 'kaunsi awaaz', 'आवाज़ बदलो', 'हे ग्रंथ आवाज बदलो', 'कौन सी आवाज़']) {
        final v = one(t);
        expect(v.id, kNavActionVoice, reason: t);
        expect(v.steps, isEmpty);
      }
    });

    test('fixed false matches: "shiv" ≠ सिख, "anya" ≠ AI; "ved kholo?" (recognizer "?") works', () {
      expect(cat.interpret('shiv'), isNot(isA<NavIntent>().having((i) => i.target.id, 'id', 'r:sikh')));
      final anya = cat.interpret('anya');
      expect(anya is NavIntent && anya.target.id == 'page:ai', isFalse);
      expect(one('ved kholo?').id, 'g:hindu/ved');
      expect(cat.interpret('https://x.example/?a=1'), isA<NavUnknown>());
      expect(cat.interpret('#/settings'), isA<NavUnknown>());
    });

    test('alternates: the first meaningful one wins; unsafe best guess never navigates', () {
      final r = cat.interpretAll(['bed bol', 'ved khol', 'gita khol']);
      expect((r as NavIntent).target.id, 'g:hindu/ved');
      expect(cat.interpretAll(['delete all', 'ved khol']), isA<NavUnknown>());
      expect(cat.interpretAll(['', '  ']), isA<NavUnknown>());
    });
  });

  group('fuzzy wake phrase', () {
    test('accepts Hindi / English / Devanagari / Latin / run-together / slips', () {
      final ok = {
        'hey granth ved kholo': 'ved kholo',
        'he granth ved kholo': 'ved kholo',
        'Hey Grand ved kholo': 'ved kholo',
        'hey grunth ved kholo': 'ved kholo',
        'हे ग्रंथ वेद खोलो': 'वेद खोलो',
        'हे ग्रन्थ वेद खोलो': 'वेद खोलो',
        'है ग्रंथ वेद': 'वेद',
        'a granth ved kholo': 'ved kholo',
        'heygranth ved kholo': 'ved kholo',
        'hey granth ji ved kholo': 'ved kholo',
        'hey tatv gita': 'gita',
        'hey tatva gita': 'gita',
        'hey tatwa gita': 'gita',
        'ok tatv gita': 'gita',
        'तत्व गीता': 'गीता',
        'tattva gita': 'gita',
        'hey granth': '',
      };
      ok.forEach((t, rest) => expect(matchWake(t), rest, reason: t));
    });

    test('rejects commands and look-alikes', () {
      for (final t in ['granth kholo', 'ved khol hey granth', 'ek granth kholo', 'तत्वज्ञान खोल', 'hey ved kholo', 'gallery', '']) {
        expect(matchWake(t), isNull, reason: t);
      }
    });

    test('across alternates: any alternate with the wake phrase arms it', () {
      final w = wakeAcross(['hello grandpa', 'hey grand ved kholo', 'he granth ved kholo']);
      expect(w!.rest, ['ved kholo']);
      expect(wakeAcross(['ved kholo', 'gita']), isNull);
    });
  });

  group('runtime: speaks, mutes the mic, retries', () {
    late _Speech sp;
    late _Worker w;
    late _Audio audio;
    late List<String> seen;
    setUp(() async {
      VoiceNavigator.debugReset();
      sp = _Speech();
      w = _Worker();
      audio = _Audio(sp);
      final v = VoiceNavigator.I
        ..speech = sp
        ..speaker = NavSpeaker(client: w.client(), audio: audio)
        ..retryGap = Duration.zero;
      RemoteConfig.I.navigatorEnabled = true;
      expect(await v.setOptIn(true), isTrue);
      seen = [];
      AppNav.I.addListener(() => seen.add(AppNav.I.hash));
    });
    tearDown(() {
      RemoteConfig.I.navigatorEnabled = false;
      AppNav.I.go('#/dashboard');
    });

    test('"Hey Granth ved khol" → folders step by step + says "वेद खोल रहा हूँ" (mic off)', () async {
      sp.listening = true;
      final r = await VoiceNavigator.I.handle('Hey Granth ved khol');
      expect(r, isA<NavIntent>());
      expect(seen.toSet().toList(), ['#/granths', '#/granths?r=hindu', '#/granths?r=hindu&g=ved']);
      expect(VoiceNavigator.I.speaker.said, ['वेद खोल रहा हूँ']);
      expect(w.posts.single.body!['text'], 'वेद खोल रहा हूँ');
      expect(audio.plays, [400]);
      expect(audio.micOnWhilePlaying, isFalse);
      expect(VoiceNavigator.I.speaking, isFalse);
    });

    test('saved voice is sent as voice_id', () async {
      await Store.I.setString(kNavVoiceKey, 'm5qndnI7u4OAdXhH0Mr5');
      await VoiceNavigator.I.handle('settings kholo');
      expect(w.posts.single.body!['voice_id'], 'm5qndnI7u4OAdXhH0Mr5');
      expect(w.posts.single.body!['text'], 'सेटिंग खोल रहा हूँ');
    });

    test('server 503 → navigation still works, silently', () async {
      w.status = 503;
      final toasts = Toast.serial;
      await VoiceNavigator.I.handle('gallery kholo');
      expect(seen.last, '#/gallery');
      expect(audio.plays, isEmpty);
      expect(Toast.serial, toasts);
    });

    test('unknown → says "समझ नहीं आया"', () async {
      await VoiceNavigator.I.handle('pizza order karo');
      expect(VoiceNavigator.I.speaker.said, [kNavSayUnknown]);
    });

    test('"awaaz badlo" opens the voice picker', () async {
      var opened = 0;
      VoiceNavigator.I.openVoicePickerOverride = () async => opened++;
      await VoiceNavigator.I.handle('awaaz badlo');
      expect(opened, 1);
      expect(seen, isEmpty);
    });

    test('mic: error_no_match → "फिर से बोलिए" + listen again, at most $kNavRetries times', () async {
      await VoiceNavigator.I.listenOnce();
      expect(sp.listens, 1);
      expect(sp.commands.single, isTrue, reason: 'command window');
      sp.onDone!('error_no_match');
      await pumpEventQueue();
      expect(sp.listens, 2);
      expect(VoiceNavigator.I.speaker.said, [kNavSayAgain]);
      expect(Toast.message.value, 'फिर से बोलिए');
      sp.onDone!('error_network');
      await pumpEventQueue();
      expect(sp.listens, 3);
      sp.onDone!('error_no_match');
      await pumpEventQueue();
      expect(sp.listens, 3, reason: 'gives up after $kNavRetries retries');
    });

    test('mic: noisy final with a low-confidence nonsense best guess retries; an alternate that matches navigates', () async {
      await VoiceNavigator.I.listenOnce();
      sp.onHeard!(const NavHeard(['ब ब'], confidence: 0.1));
      await pumpEventQueue();
      expect(sp.listens, 2);
      sp.onHeard!(const NavHeard(['bed bol', 'ved khol'], confidence: 0.2));
      await pumpEventQueue(times: 50);
      await Future<void>.delayed(const Duration(seconds: 4));
      expect(seen.toSet().toList(), ['#/granths', '#/granths?r=hindu', '#/granths?r=hindu&g=ved']);
    });

    test('a clarification does not trap the next, different command', () async {
      final v = VoiceNavigator.I;
      final cl = v.catalog().interpretAll(['dummy']);
      expect(cl, isA<NavUnknown>());
      // Force a pending clarification, then say something unrelated.
      final r1 = await v.handle('x', result: NavClarify([v.catalog().targets.firstWhere((t) => t.id == 'g:hindu/ved'), v.catalog().targets.firstWhere((t) => t.id == 'g:hindu/puran')]));
      expect(r1, isA<NavClarify>());
      expect(v.speaker.said.last, startsWith('कौन-सा खोलूँ? वेद या पुराण'));
      final r2 = v.interpretHeard(['settings kholo']);
      expect((r2 as NavIntent).target.id, 'page:settings');
      final r3 = v.interpretHeard(['ved']);
      expect((r3 as NavIntent).target.id, 'g:hindu/ved');
    });
  });

  group('voice picker sheet', () {
    testWidgets('lists ≥ 2 server voices (male + female); tap saves + previews with that voice_id', (tester) async {
      final w = _Worker();
      final a = _Audio();
      final speaker = NavSpeaker(client: w.client(), audio: a);
      await tester.pumpWidget(MaterialApp(home: Scaffold(body: NavVoiceSheet(speaker: speaker))));
      expect(find.text('Monika · महिला'), findsOneWidget);
      expect(find.text('Krishna · पुरुष'), findsOneWidget);
      expect(find.byKey(const ValueKey('nav-voice-phone')), findsNothing, reason: 'no phone TTS on this device');
      await tester.runAsync(() async {
        await tester.tap(find.byKey(const ValueKey('nav-voice-m5qndnI7u4OAdXhH0Mr5')));
        await Future<void>.delayed(const Duration(milliseconds: 50));
      });
      await tester.pump();
      expect(Store.I.getString(kNavVoiceKey), 'm5qndnI7u4OAdXhH0Mr5');
      expect(w.posts.single.body!['voice_id'], 'm5qndnI7u4OAdXhH0Mr5');
      expect(w.posts.single.body!['text'], kNavVoicePreview);
      expect(a.plays.length, 1);
    });

    testWidgets('phone voice offered only when the device has one', (tester) async {
      final speaker = NavSpeaker(client: _Worker().client(), audio: _Audio()..phone = true);
      await tester.pumpWidget(MaterialApp(home: Scaffold(body: NavVoiceSheet(speaker: speaker, phone: true))));
      expect(find.byKey(const ValueKey('nav-voice-phone')), findsOneWidget);
    });

    testWidgets('NavTouchLayer builds with no audio WebView yet', (tester) async {
      await tester.pumpWidget(const MaterialApp(home: Stack(children: [Positioned.fill(child: NavTouchLayer())])));
      expect(find.byType(NavAudioHost), findsOneWidget);
      expect(tester.takeException(), isNull);
    });
  });
}

class _RealHttp extends HttpOverrides {}
