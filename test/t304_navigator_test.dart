// t304: voice Navigator — wake phrase, Hindi/Hinglish matching, step-by-step routes, safety.
import 'package:flutter_test/flutter_test.dart';
import 'package:granthprabandhan/ai/navigator/nav_intent.dart';
import 'package:granthprabandhan/ai/navigator/voice_navigator.dart';
import 'package:granthprabandhan/services/remote_config.dart';
import 'package:granthprabandhan/state/router.dart';
import 'package:granthprabandhan/services/catalog_store.dart';
import 'package:granthprabandhan/services/shelves.dart';
import 'helpers.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late NavCatalog cat;
  setUp(() async {
    await setUpApp();
    final s = CatalogStore.I;
    final idx = Shelves.indexFor(s.granths);
    cat = NavCatalog.build(structure: Shelves.structure, granths: s.granths, topics: s.topics, placements: idx.placements);
  });

  NavTarget one(String text) {
    final r = cat.interpret(text);
    expect(r, isA<NavIntent>(), reason: '"$text" → $r ${r is NavClarify ? r.choices.map((c) => c.id) : ''}');
    return (r as NavIntent).target;
  }

  test('wake phrase only as a complete phrase at the start', () {
    for (final w in ['Hey Granth ved khol', 'hey tatv, ved khol', 'हे ग्रंथ वेद खोलो', 'तत्व वेद खोल', 'hey tattva ved kholo']) {
      expect(hasWakePhrase(w), isTrue, reason: w);
    }
    expect(hasWakePhrase('तत्वज्ञान खोल'), isFalse);
    expect(hasWakePhrase('ved khol hey granth'), isFalse);
    expect(stripWake('Hey Granth, ved khol'), 'ved khol');
  });

  test('ved khol opens folders step by step: granths → hindu → ved', () {
    for (final t in ['Hey Granth ved khol', 'वेद खोलो', 'tatv veda kholo', 'open vedas']) {
      final v = one(t);
      expect(v.id, 'g:hindu/ved', reason: t);
      expect(v.steps, ['#/granths', '#/granths?r=hindu', '#/granths?r=hindu&g=ved']);
    }
  });

  test('Veda leaf, puran, religion, Hinglish spellings', () {
    expect(one('rigved khol').steps.last, '#/granths?r=hindu&g=ved&s=rigved');
    expect(one('ऋग्वेद खोलो').id, 's:hindu/ved/rigved');
    expect(one('sukshma ved kholo').id, 's:hindu/ved/sukshmved');
    expect(one('puran khol').id, 'g:hindu/puran');
    expect(one('पुराण').id, 'g:hindu/puran');
    expect(one('hindu khol').id, 'r:hindu');
    expect(one('islam').id, 'r:islam');
    expect(one('upnishad kholo').id, 'g:hindu/upanishad');
  });

  test('pages: settings, search, aaj ka pramaan, all granths', () {
    expect(one('settings kholo').steps, ['#/settings']);
    expect(one('सेटिंग खोलो').steps, ['#/settings']);
    expect(one('hey granth aaj ka pramaan dikhao').steps, ['#/today']);
    expect(one('search').steps, ['#/pramans']);
    expect(one('sabhi granth').steps, ['#/granths?all=1']);
  });

  test('granth by name walks its folder chain to its pramans', () {
    final g = one('bhagavad gita kholo');
    expect(g.steps.first, '#/granths');
    expect(g.steps.last, startsWith('#/'));
    final k = one('श्रीमद्भगवद्गीता');
    expect(k.id, 'granth:10');
    expect(k.steps.last, '#/pramans?granth=10');
    expect(k.steps.length, greaterThan(2), reason: 'folder → sub-folder → granth, not a jump');
  });

  test('unsafe, URL and unknown text never navigate', () {
    for (final t in ['https://evil.example', '#/settings', 'delete all', 'hey granth admin override', 'pizza order karo', '', 'x' * 200]) {
      expect(cat.interpret(t), isA<NavUnknown>(), reason: t);
    }
  });

  group('runtime', () {
    setUp(() {
      VoiceNavigator.debugReset();
      VoiceNavigator.I.speech = _FakeSpeech();
    });
    tearDown(() => RemoteConfig.I.navigatorEnabled = false);

    test('admin off by default: no opt-in, no mic', () async {
      expect(RemoteConfig.I.navigatorEnabled, isFalse);
      expect(await VoiceNavigator.I.setOptIn(true), isFalse);
      expect(VoiceNavigator.I.available, isFalse);
      expect((VoiceNavigator.I.speech as _FakeSpeech).inits, 0, reason: 'mic never asked while admin off');
    });

    test('admin on + opt-in → spoken "Hey Granth ved khol" opens each folder in turn', () async {
      RemoteConfig.I.navigatorEnabled = true;
      expect(await VoiceNavigator.I.setOptIn(true), isTrue);
      expect(VoiceNavigator.I.available, isTrue);
      final seen = <String>[];
      AppNav.I.addListener(() => seen.add(AppNav.I.hash));
      final t = (VoiceNavigator.I.catalog().interpret('Hey Granth ved khol') as NavIntent).target;
      await VoiceNavigator.I.run(t, tap: Duration.zero, settle: Duration.zero);
      expect(seen.toSet().toList(), ['#/granths', '#/granths?r=hindu', '#/granths?r=hindu&g=ved']);
      await VoiceNavigator.I.setOptIn(false);
      expect(VoiceNavigator.I.available, isFalse);
    });

    test('parse flags.navigator_enabled: only exact true', () {
      expect(RemoteConfig.I.navigatorEnabled, isFalse);
    });
  });
}

class _FakeSpeech implements NavSpeech {
  int inits = 0;
  @override
  bool listening = false;
  @override
  Future<bool> init() async {
    inits++;
    return true;
  }

  @override
  Future<void> listen({required void Function(NavHeard heard) onHeard, required void Function(String? error) onDone, required Duration listenFor, required Duration pauseFor, bool command = true}) async {}
  @override
  Future<void> stop() async => listening = false;
}
