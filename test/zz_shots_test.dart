// Local-only screenshot render (not committed).
import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:granthprabandhan/main.dart';
import 'package:granthprabandhan/services/api.dart';
import 'package:granthprabandhan/services/catalog_store.dart';
import 'package:granthprabandhan/services/storage.dart';
import 'package:granthprabandhan/state/router.dart';
import 'package:granthprabandhan/widgets/granth_view_setting.dart';
import 'package:granthprabandhan/widgets/panel.dart';
import 'package:granthprabandhan/widgets/remote_media.dart';
import 'package:granthprabandhan/services/media_manifest.dart';
import 'package:granthprabandhan/services/shelves.dart';
import 'package:granthprabandhan/screens/login_screen.dart';

import 'helpers.dart';

const out = '/home/box/work/shots';

Future<void> settle(WidgetTester t, [int n = 14]) async {
  for (var i = 0; i < n; i++) {
    await t.pump(const Duration(milliseconds: 100));
  }
}

void main() {
  setUp(() async {
    await setUpApp();
    await Store.I.remove(granthViewKey);
    await Store.I.setString(Store.kTaskbar, '1'); // live config: ui.taskbar {force: true}
    final d = '$out/data';
    final c = parseCatalog([
      File('$d/getTopics.json').readAsStringSync(),
      File('$d/getGranths.json').readAsStringSync(),
      File('$d/getPramans.json').readAsStringSync(),
      DateTime.now().millisecondsSinceEpoch,
    ]);
    CatalogStore.I.debugSetCatalog(c);
  });

  testWidgets('shots', (t) async {
    await t.runAsync(() async {
      for (final e in {
        'NotoDeva': ['NotoSansDevanagari-Regular', 'NotoSansDevanagari-Medium', 'NotoSansDevanagari-SemiBold'],
        'DMSans': ['DMSans-Regular', 'DMSans-Medium', 'DMSans-SemiBold'],
        'YatraOne': ['YatraOne-Devanagari'],
        'YatraOneLatin': ['YatraOne-Latin'],
        'NotoDevaFull': ['NotoSansDevanagari-Full'],
        'TiroDevanagari': ['TiroDevanagariSanskrit-Regular'],
        'DMSerif': ['DMSerifDisplay-Regular', 'DMSerifDisplay-Italic'],
        'Roboto': ['DMSans-Regular'],
      }.entries) {
        final l = FontLoader(e.key);
        for (final f in e.value) {
          l.addFont(Future.value(ByteData.sublistView(File('assets/fonts/$f.ttf').readAsBytesSync())));
        }
        await l.load();
      }
    });
    await t.binding.setSurfaceSize(const Size(412, 892));
    t.view.devicePixelRatio = 2.625;
    addTearDown(() => t.binding.setSurfaceSize(null));
    final key = GlobalKey();
    await t.pumpWidget(RepaintBoundary(key: key, child: const GranthApp(splash: false, links: false)));
    await settle(t);
    Future<void> snap(String name) async {
      await t.runAsync(() async {
        final img = await (key.currentContext!.findRenderObject() as RenderRepaintBoundary).toImage(pixelRatio: 2.625);
        final d = await img.toByteData(format: ui.ImageByteFormat.png);
        File('$out/$name').writeAsBytesSync(d!.buffer.asUint8List());
      });
    }
    void measure(String tab) {
      final h = find.byType(PageHeader);
      final st = find.descendant(of: find.byType(StickyHeader), matching: find.byType(RepaintBoundary));
      final ph = t.getRect(h.first);
      final sh = st.evaluate().isEmpty ? Rect.zero : t.getRect(st.first);
      final title = t.widget<PageHeader>(h.first);
      // ignore: avoid_print
      print('MEASURE $tab header=${ph.size} at ${ph.top} sticky=${sh.size} at ${sh.top} title=${title.title} sub=${title.subtitle} trailing=${title.trailing != null} low=${title.trailingLow} leading=${title.leading != null} tone=${title.tone} icon=${title.icon}');
    }
    for (final r in ['#/pramans', '#/topics', '#/dashboard', '#/gallery']) {
      AppNav.I.openLink(r);
      await settle(t, 20);
      if (find.byType(PageHeader).evaluate().isNotEmpty) measure(r);
    }
    AppNav.I.openLink('#/pramans');
    await settle(t, 20);
    await snap('10_pramaan_tab.png');
    AppNav.I.openLink('#/topics');
    await settle(t, 20);
    await snap('12_topics_tab.png');
    AppNav.I.openLink('#/granths');
    await settle(t, 20);
    final folders = find.byKey(const ValueKey('granth-view-folders'));
    if (folders.evaluate().isNotEmpty) {
      await snap('01_chooser.png');
      await t.tap(folders);
      await settle(t, 20);
    }
    measure('#/granths');
    await snap(Platform.environment['SHOT'] ?? '11_granth_tab.png');
    // Settings → डिस्प्ले (ग्रंथ दृश्य block)
    AppNav.I.openLink('#/settings?s=display');
    await settle(t, 20);
    final gv = find.text('ग्रंथ दृश्य');
    if (gv.evaluate().isNotEmpty) {
      await t.ensureVisible(gv.first);
      await t.drag(find.byType(Scrollable).first, const Offset(0, -120));
      await settle(t, 10);
    }
    await snap('13_settings_display.png');
    // 20: admin folder logo videos (poster frames) on two folders
    // ignore: avoid_print
    print('RELIGIONS ${Shelves.structure.religions.map((r) => '${r.id}:${r.icon}').join(' ')}');
    const lv = '/home/box/work/logo-videos';
    const u1 = 'https://media.example/book_opening_terracotta.mp4', p1 = 'https://media.example/book_opening_terracotta_poster.jpg';
    const u2 = 'https://media.example/lotus_blooming_pink.mp4', p2 = 'https://media.example/lotus_blooming_pink_poster.jpg';
    MediaCache.I.debugPut(p1, File('$lv/book_opening_terracotta_poster.jpg'));
    MediaCache.I.debugPut(p2, File('$lv/lotus_blooming_pink_poster.jpg'));
    MediaManifest.I.debugSet(parseMediaManifest({
      'schema': 1,
      'active_pack': 'p_demo',
      'videos': [
        {'pack': 'p_demo', 'placement': 'folder', 'target': 'folder:hindu', 'url': u1, 'poster_url': p1, 'provider': 'r2'},
        {'pack': 'p_demo', 'placement': 'folder', 'target': 'folder:buddh', 'url': u2, 'poster_url': p2, 'provider': 'r2'},
      ],
    })!);
    AppNav.I.openLink('#/granths');
    await settle(t, 30);
    for (final e in find.byType(Image).evaluate()) {
      await t.runAsync(() => precacheImage((e.widget as Image).image, e).timeout(const Duration(seconds: 3), onTimeout: () {}));
    }
    await settle(t, 5);
    await snap('20_folder_logo_video.png');
    MediaManifest.I.debugSet(ParsedManifest.empty);
    // 21: login page, 22: legal list opened from it
    await t.pumpWidget(RepaintBoundary(key: key, child: MaterialApp(debugShowCheckedModeBanner: false, theme: Theme.of(t.element(find.byType(Scaffold).first)), home: LoginPage(onSkip: () {}))));
    await settle(t, 30);
    for (final e in find.byType(Image).evaluate()) {
      await t.runAsync(() => precacheImage((e.widget as Image).image, e).timeout(const Duration(seconds: 3), onTimeout: () {}));
    }
    await settle(t, 5);
    await snap('21_login.png');
    await t.tap(find.byKey(const ValueKey('login-legal')));
    await settle(t, 20);
    await snap('22_legal_from_login.png');
  });
}
