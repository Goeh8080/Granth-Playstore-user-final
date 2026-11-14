// t361: gendered Navigator speech (female voice → feminine Hindi) and hold-to-talk on the
// Tatv AI buttons (tap unchanged; admin switch required).
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:granthprabandhan/ai/navigator/nav_phrases.dart';
import 'package:granthprabandhan/ai/navigator/nav_tts.dart';
import 'package:granthprabandhan/ai/navigator/voice_navigator.dart';
import 'package:granthprabandhan/screens/home_shell.dart';
import 'package:granthprabandhan/services/remote_config.dart';
import 'package:granthprabandhan/services/storage.dart';
import 'package:granthprabandhan/state/router.dart';
import 'package:granthprabandhan/widgets/common.dart';
import 'helpers.dart';

class _Speech implements NavSpeech {
  int inits = 0, listens = 0;
  bool grant = true;
  @override
  bool listening = false;
  @override
  Future<bool> init() async {
    inits++;
    return grant;
  }

  @override
  Future<void> listen({required void Function(NavHeard heard) onHeard, required void Function(String? error) onDone, required Duration listenFor, required Duration pauseFor, bool command = true}) async {
    listens++;
    listening = true;
  }

  @override
  Future<void> stop() async => listening = false;
}

class _Silent extends NavSpeaker {
  _Silent() : super(voice: () => null);
  @override
  Future<bool> say(String text, {String lang = 'hi', String? voiceId}) async {
    said.add(text);
    return false;
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUp(() async {
    await setUpApp();
    RemoteConfig.I.debugReset();
  });

  group('NavPhrases.forGender', () {
    test('female: feminine verbs in every gendered line', () {
      final f = NavPhrases.forGender('female');
      expect(f.opening('वेद'), 'वेद खोल रही हूँ');
      expect(f.opening('ग्रंथ (फ़ोल्डर)'), 'ग्रंथ खोल रही हूँ');
      expect(f.unknown, 'समझ नहीं पाई');
      expect(f.unknownToast(' pizza '), 'समझ नहीं पाई: pizza');
      expect(f.searching, 'ढूँढ रही हूँ');
      expect(f.listening, 'सुन रही हूँ…');
      expect(f.preview, 'नमस्ते, मैं इस आवाज़ में बोलूँगी');
    });

    test('male: masculine verbs in every gendered line', () {
      final m = NavPhrases.forGender('male');
      expect(m.opening('वेद'), 'वेद खोल रहा हूँ');
      expect(m.unknown, 'समझ नहीं पाया');
      expect(m.unknownToast('x'), 'समझ नहीं पाया: x');
      expect(m.searching, 'ढूँढ रहा हूँ');
      expect(m.listening, 'सुन रहा हूँ…');
      expect(m.preview, 'नमस्ते, मैं इस आवाज़ में बोलूँगा');
    });

    test('no line of one gender leaks the other gender\'s forms', () {
      final fem = RegExp(r'रही|पाई|बोलूँगी'), masc = RegExp(r'रहा\b|रहा |पाया|बोलूँगा');
      for (final l in NavPhrases.female.all()) {
        expect(masc.hasMatch(l), isFalse, reason: 'female: $l');
      }
      for (final l in NavPhrases.male.all()) {
        expect(fem.hasMatch(l), isFalse, reason: 'male: $l');
      }
      // Neutral lines stay identical.
      expect(NavPhrases.female.clarify(['वेद', 'पुराण']), NavPhrases.male.clarify(['वेद', 'पुराण']));
      expect(NavPhrases.female.again, NavPhrases.male.again);
      expect(NavPhrases.female.all().length, NavPhrases.male.all().length);
    });

    test('other / unknown gender → feminine', () {
      expect(NavPhrases.forGender('other').gender, NavGender.female);
      expect(NavPhrases.forGender(null).gender, NavGender.female);
      expect(NavPhrases.forGender(' MALE ').gender, NavGender.male);
    });

    test('current(): saved voice decides; nothing saved = Vani (female); phone / Monika = female', () async {
      expect(navVoiceGender(), 'female');
      expect(kNavDefaultVoices.first.name, 'Vani');
      await Store.I.setString(kNavVoicesCacheKey, '{"voices":[{"id":"tatv_hi_f_vani","name":"Vani","gender":"female"},{"id":"tatv_hi_m_arjun","name":"Arjun","gender":"male"}],"default_voice_id":"tatv_hi_f_vani"}');
      await Store.I.setString(kNavVoiceKey, 'tatv_hi_m_arjun');
      expect(NavPhrases.current().opening('वेद'), 'वेद खोल रहा हूँ');
      await Store.I.setString(kNavVoiceKey, 'tatv_hi_f_vani');
      expect(NavPhrases.current().unknown, 'समझ नहीं पाई');
      await Store.I.setString(kNavVoiceKey, kPhoneVoice);
      expect(NavPhrases.current().gender, NavGender.female);
      await Store.I.setString(kNavVoiceKey, kNavLegacyMonika);
      expect(navSpeakVoice(), kNavPreferredVoice, reason: 'old Monika choice → Vani');
      // A voice only on the server list still sets gender once GET /tts/voices is cached.
      await Store.I.setString(kNavVoicesCacheKey, '{"voices":[{"id":"m5qndnI7u4OAdXhH0Mr5","name":"Krishna","gender":"male"},{"id":"OZ0L6eISlOejga3XjDFt","name":"Talia","gender":"female"}],"default_voice_id":"OZ0L6eISlOejga3XjDFt"}');
      await Store.I.setString(kNavVoiceKey, 'm5qndnI7u4OAdXhH0Mr5');
      expect(NavPhrases.current().unknown, 'समझ नहीं पाया');
      await Store.I.setString(kNavVoiceKey, 'OZ0L6eISlOejga3XjDFt');
      expect(NavPhrases.current().unknown, 'समझ नहीं पाई');
    });

    test('runtime speech + toast follow the voice', () async {
      VoiceNavigator.debugReset();
      final sp = _Silent();
      VoiceNavigator.I
        ..speech = _Speech()
        ..speaker = sp;
      await Store.I.setString(kNavVoicesCacheKey, '{"voices":[{"id":"tatv_hi_f_vani","name":"Vani","gender":"female"},{"id":"tatv_hi_m_arjun","name":"Arjun","gender":"male"}]}');
      await VoiceNavigator.I.handle('pizza order karo');
      expect(sp.said.last, 'समझ नहीं पाई');
      await Store.I.setString(kNavVoiceKey, 'tatv_hi_m_arjun');
      await VoiceNavigator.I.handle('pizza order karo');
      expect(sp.said.last, 'समझ नहीं पाया');
      await VoiceNavigator.I.handle('settings kholo');
      expect(sp.said.last, 'सेटिंग खोल रहा हूँ');
      await Store.I.setString(kNavVoiceKey, 'tatv_hi_f_vani');
      await VoiceNavigator.I.handle('gallery kholo');
      expect(sp.said.last, 'गैलरी खोल रही हूँ');
      AppNav.I.go('#/dashboard');
    });
  });

  group('hold the Tatv AI button', () {
    late _Speech speech;
    setUp(() {
      VoiceNavigator.debugReset();
      speech = _Speech();
      VoiceNavigator.I
        ..speech = speech
        ..speaker = _Silent();
      AppNav.I.go('#/dashboard');
    });
    tearDown(() => RemoteConfig.I.navigatorEnabled = false);

    Widget fab({Future<bool> Function(BuildContext)? confirm}) => MaterialApp(
          home: Scaffold(
            body: Center(
              child: NavHoldTrigger(
                id: 'fab',
                confirmOptIn: confirm,
                child: Pressable(key: const ValueKey('ask-ai-fab'), onTap: () => AppNav.I.openLink('#/ai'), child: const SizedBox(width: 140, height: 48, child: Text('Ask Tatv AI'))),
              ),
            ),
          ),
        );

    testWidgets('tap still opens Tatv AI (admin on, opted in) and does not listen', (tester) async {
      RemoteConfig.I.navigatorEnabled = true;
      await tester.runAsync(() => VoiceNavigator.I.setOptIn(true));
      await tester.pumpWidget(fab());
      await tester.tap(find.byKey(const ValueKey('ask-ai-fab')));
      await tester.pump(const Duration(milliseconds: 300));
      expect(AppNav.I.route.panel, Panel.ai);
      expect(speech.listens, 0);
    });

    testWidgets('long-press starts listening right away + shows the indicator; AI not opened', (tester) async {
      RemoteConfig.I.navigatorEnabled = true;
      await tester.runAsync(() => VoiceNavigator.I.setOptIn(true));
      await tester.pumpWidget(fab());
      await tester.longPress(find.byKey(const ValueKey('ask-ai-fab')));
      await tester.pump(const Duration(milliseconds: 100));
      expect(speech.listens, 1);
      expect(VoiceNavigator.I.state, NavVoiceState.listening);
      expect(VoiceNavigator.I.listenSource, 'hold');
      expect(find.byKey(const ValueKey('nav-hold-listening')), findsOneWidget);
      expect(find.text('सुन रही हूँ…'), findsOneWidget);
      expect(AppNav.I.route.panel, isNot(Panel.ai));
      VoiceNavigator.I.setOptIn(false);
      await tester.pump(const Duration(milliseconds: 100));
      expect(find.byKey(const ValueKey('nav-hold-listening')), findsNothing);
    });

    testWidgets('admin flag off: no hold gesture, no listening, no prompt; tap still opens AI', (tester) async {
      var asked = 0;
      await tester.pumpWidget(fab(confirm: (_) async {
        asked++;
        return true;
      }));
      await tester.longPress(find.byKey(const ValueKey('ask-ai-fab')));
      await tester.pump(const Duration(milliseconds: 100));
      expect(speech.listens + speech.inits + asked, 0);
      expect(find.byKey(const ValueKey('nav-hold-listening')), findsNothing);
      // No hold gesture is registered at all, so the button acts exactly as before t361.
      expect(tester.widget<GestureDetector>(find.byKey(const ValueKey('nav-hold-fab'))).onLongPress, isNull);
      AppNav.I.go('#/dashboard');
      await tester.tap(find.byKey(const ValueKey('ask-ai-fab')));
      await tester.pump(const Duration(milliseconds: 300));
      expect(AppNav.I.route.panel, Panel.ai);
    });

    testWidgets('not opted in: asks first; "अभी नहीं" → nothing; "हाँ" → mic asked, then listens', (tester) async {
      RemoteConfig.I.navigatorEnabled = true;
      var answer = false;
      var asked = 0;
      await tester.pumpWidget(fab(confirm: (_) async {
        asked++;
        return answer;
      }));
      await tester.longPress(find.byKey(const ValueKey('ask-ai-fab')));
      await tester.pump();
      expect(asked, 1);
      expect(speech.inits + speech.listens, 0);
      expect(VoiceNavigator.I.optedIn, isFalse);
      answer = true;
      await tester.longPress(find.byKey(const ValueKey('ask-ai-fab')));
      await tester.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 100)));
      await tester.pump();
      expect(asked, 2);
      expect(speech.inits, 1, reason: 'mic permission asked once');
      expect(VoiceNavigator.I.optedIn, isTrue);
      expect(speech.listens, 1);
      await tester.runAsync(() => VoiceNavigator.I.setOptIn(false));
    });

    testWidgets('mic refused: stays off, no listening', (tester) async {
      RemoteConfig.I.navigatorEnabled = true;
      speech.grant = false;
      await tester.pumpWidget(fab(confirm: (_) async => true));
      await tester.longPress(find.byKey(const ValueKey('ask-ai-fab')));
      await tester.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 100)));
      await tester.pump(const Duration(seconds: 3));
      expect(VoiceNavigator.I.optedIn, isFalse);
      expect(speech.listens, 0);
    });

    testWidgets('bottom bar: centre तत्त्व AI tab — tap opens AI, hold listens', (tester) async {
      RemoteConfig.I.navigatorEnabled = true;
      await tester.runAsync(() => VoiceNavigator.I.setOptIn(true));
      await tester.pumpWidget(MaterialApp(home: Scaffold(body: Align(alignment: Alignment.bottomCenter, child: BottomTabs(route: AppNav.I.route)))));
      expect(find.byKey(const ValueKey('nav-hold-tab')), findsOneWidget);
      await tester.longPress(find.byKey(const ValueKey('tab-2')));
      await tester.pump(const Duration(milliseconds: 100));
      expect(speech.listens, 1);
      expect(AppNav.I.route.panel, isNot(Panel.ai));
      VoiceNavigator.I.setOptIn(false);
      await tester.pump(const Duration(milliseconds: 100));
      await tester.tap(find.byKey(const ValueKey('tab-2')));
      await tester.pump(const Duration(milliseconds: 300));
      expect(AppNav.I.route.panel, Panel.ai);
    });
  });
}
