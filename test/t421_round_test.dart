// t421 (Goutam, 21 Nov 2026): Granth tab "pehle jesa" (no hero), old folder logo sizes, the
// grow-on-press, the chooser / Settings videos, admin media (icon_url / icon_video_url /
// chooser + brand videos), the Navigator's cached-phrase-only voice and wake on opt-in.
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:granthprabandhan/ai/navigator/nav_phrases.dart';
import 'package:granthprabandhan/ai/navigator/nav_tts.dart';
import 'package:granthprabandhan/ai/navigator/voice_navigator.dart';
import 'package:granthprabandhan/config.dart';
import 'package:granthprabandhan/models/structure.dart';
import 'package:granthprabandhan/screens/shelves_screen.dart';
import 'package:granthprabandhan/services/remote_config.dart';
import 'package:granthprabandhan/services/storage.dart';
import 'package:granthprabandhan/widgets/common.dart';
import 'package:granthprabandhan/widgets/remote_media.dart';

import 'helpers.dart';

class _Speech implements NavSpeech {
  @override
  Future<bool> init() async => true;
  @override
  bool get listening => false;
  @override
  Future<void> listen({required void Function(NavHeard heard) onHeard, required void Function(String? error) onDone, required Duration listenFor, required Duration pauseFor, bool command = true}) async {}
  @override
  Future<void> stop() async {}
}

void main() {
  setUp(() async {
    await setUpApp();
    RemoteConfig.I.debugReset();
  });

  test('version 1.0.1+2 everywhere', () {
    expect(kAppVersion, '1.0.1');
    expect(kBuildNumber, 2);
    expect(kAppFull, '1.0.1+2');
    expect(kTtsUserAgent, contains('1.0.1'));
    expect(File('pubspec.yaml').readAsStringSync(), contains('version: 1.0.1+2'));
    final wf = File('.github/workflows/android-apk.yml').readAsStringSync();
    expect(wf, contains('name: Playstore - 1.0.1'));
    expect(wf, contains('Playstore-1.0.1.aab'));
    expect(wf, contains('Playstore-1.0.1-arm64.apk'));
    expect(wf, isNot(contains('1.0.0')));
  });

  test('folder logos are the old normal size; the hero file is gone', () {
    expect([folderPicSize(1), folderPicSize(2), folderPicSize(3)], [60, 84, 58]);
    expect(File('lib/widgets/granths_hero.dart').existsSync(), isFalse);
    expect(File('lib/screens/granths_screen.dart').readAsStringSync(), isNot(contains('GranthsHero')));
  });

  testWidgets('a folder tile grows (~1.05) while pressed and springs back; tap still works', (t) async {
    var taps = 0;
    await t.pumpWidget(MaterialApp(
      home: Scaffold(
        body: Center(
          child: SizedBox(
            width: 160,
            height: 160,
            child: FolderRow(cols: 2, leading: (s) => SizedBox.square(dimension: s), title: 'वेद', subtitle: '4 ग्रंथ • 10 प्रमाण', onTap: () => taps++),
          ),
        ),
      ),
    ));
    final g = await t.startGesture(t.getCenter(find.byType(FolderRow)));
    await t.pump(const Duration(milliseconds: 200));
    expect(t.widget<AnimatedScale>(find.byType(AnimatedScale).first).scale, kGrowScale);
    await g.up();
    await t.pump(const Duration(milliseconds: 500));
    expect(t.widget<AnimatedScale>(find.byType(AnimatedScale).first).scale, 1);
    expect(taps, 1);
  });

  test('admin media URLs: https + right type only, unknown/missing → null (backward compatible)', () {
    expect(parseMediaUrl('https://x.dev/a/icon.png', kImageExts), 'https://x.dev/a/icon.png');
    expect(parseMediaUrl('https://x.dev/a/icon.svg?v=2', kImageExts), isNotNull);
    expect(parseMediaUrl('https://x.dev/a/loop.mp4', kVideoExts), isNotNull);
    expect(parseMediaUrl('http://x.dev/a/icon.png', kImageExts), isNull);
    expect(parseMediaUrl('https://x.dev/a/loop.mp4', kImageExts), isNull);
    expect(parseMediaUrl(42, kImageExts), isNull);
    expect(parseMediaUrl(null, kVideoExts), isNull);
    final s = parseStructure({
      'religions': [
        {
          'id': 'hindu',
          'title': 'हिन्दू',
          'icon': 'om',
          'icon_url': 'https://cdn.x/om.webp',
          'icon_video_url': 'https://cdn.x/om.mp4',
          'groups': [
            {'id': 'ved', 'title': 'वेद', 'icon': 'scroll', 'icon_url': 'https://cdn.x/ved.png', 'future_field': 1},
            {'id': 'gita', 'title': 'गीता', 'icon': 'book-red', 'icon_video_url': 'ftp://bad'},
          ],
        },
      ],
      'other': {'title': 'अन्य', 'icon_video_url': 'https://cdn.x/other.mp4'},
    })!;
    final h = s.religions.single;
    expect(h.iconUrl, 'https://cdn.x/om.webp');
    expect(h.iconVideoUrl, 'https://cdn.x/om.mp4');
    expect(h.groups.first.iconUrl, 'https://cdn.x/ved.png');
    expect(h.groups.first.iconVideoUrl, isNull);
    expect(h.groups.last.iconVideoUrl, isNull, reason: 'bad URL ignored');
    expect(h.groups.last.icon, 'book-red', reason: 'painted icon stays');
    expect(s.other.iconVideoUrl, 'https://cdn.x/other.mp4');
    // bundled structure (no media fields) still parses
    expect(Structure.fromMap({'religions': [{'id': 'a', 'title': 'A'}]}).religions.single.iconUrl, isNull);
  });

  testWidgets('RemoteIcon: no URLs → the painted fallback; LoopVideo in tests shows its fallback', (t) async {
    await t.pumpWidget(const MaterialApp(
      home: Column(children: [
        RemoteIcon(size: 40, fallback: Text('painted')),
        SizedBox(width: 80, height: 80, child: LoopVideo(asset: 'assets/brand/video/lotus_folders.mp4', fallback: Text('mini'))),
      ]),
    ));
    await t.pump(const Duration(milliseconds: 100));
    expect(find.text('painted'), findsOneWidget);
    expect(find.text('mini'), findsOneWidget);
    expect(File('assets/brand/video/lotus_folders.mp4').lengthSync(), lessThan(420 * 1024));
    expect(File('assets/brand/video/book_list.mp4').lengthSync(), lessThan(420 * 1024));
  });

  test('wake phrase turns on with the opt-in (real default)', () async {
    VoiceNavigator.debugReset();
    VoiceNavigator.wakeOnOptIn = true;
    addTearDown(() async {
      await VoiceNavigator.I.setOptIn(false);
      VoiceNavigator.wakeOnOptIn = false;
    });
    VoiceNavigator.I.speech = _Speech();
    RemoteConfig.I.navigatorEnabled = true;
    expect(await VoiceNavigator.I.setOptIn(true), isTrue);
    expect(Store.I.getString(VoiceNavigator.kWake), '1');
    expect(VoiceNavigator.I.wakeOn, isTrue);
    RemoteConfig.I.navigatorEnabled = false;
  });

  test('cached-only voice: an uncached line is never POSTed; a cached line is', () async {
    final sent = <String>[];
    final c = TtsClient(endpoint: 'https://w.example', iid: () => null, uid: () => null, transport: (m, u, h, b, t) async {
      sent.add(String.fromCharCodes(b ?? const []));
      return (status: 503, contentType: 'application/json', body: Uint8List(0), retryAfter: null);
    });
    final sp = NavSpeaker(client: c, enabled: () => true, voice: () => kNavMaleVoice, cachedOnly: (_) => true);
    expect(await sp.say('वेद खोल रहा हूँ'), isFalse);
    expect(sp.lastSilent, isTrue);
    expect(sent, isEmpty);
    await sp.say(NavPhrases.male.opening('वेद'));
    expect(sent.length, 1);
  });
}
