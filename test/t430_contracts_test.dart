import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:granthprabandhan/legal/legal_pages.dart';
import 'package:granthprabandhan/services/media_manifest.dart';
import 'package:granthprabandhan/theme/app_theme.dart';

void main() {
  group('t430 theme key', () {
    test('absent = bundled (white surfaces, app accents)', () {
      AppTheme.I.apply(null);
      expect(AppTheme.I.background, const Color(0xFFFFFFFF));
      expect(AppTheme.I.surface, const Color(0xFFFFFFFF));
      expect(AppTheme.I.primary, const Color(0xFF7B1F2E));
      expect(AppTheme.I.secondary, const Color(0xFFE8821A));
      expect(AppTheme.I.loginGradient.length, 4);
    });
    test('valid fields apply, an invalid field is ignored on its own', () {
      AppTheme.I.apply({'primary': '#112233', 'secondary': 'red', 'background': '#abcdef', 'login_gradient': ['#FFFFFF', '#000000']});
      expect(AppTheme.I.primary, const Color(0xFF112233));
      expect(AppTheme.I.secondary, const Color(0xFFE8821A));
      expect(AppTheme.I.background, const Color(0xFFABCDEF));
      expect(AppTheme.I.loginGradient, const [Color(0xFFFFFFFF), Color(0xFF000000)]);
      AppTheme.I.apply({'login_gradient': ['#FFFFFF']}); // 1 stop: ignored
      expect(AppTheme.I.loginGradient, AppTheme.defaultLoginGradient);
      AppTheme.I.apply(null);
    });
  });

  group('t430 legal key', () {
    tearDown(() => remoteLegal = const []);
    test('absent = bundled pages', () {
      expect(legalPages(), same(kLegalPages));
    });
    test('admin order first, edits replace, new pages added, bad entries skipped', () {
      remoteLegal = parseLegal([
        {'id': 'cookies2', 'title': 'नई नीति', 'body': '## शीर्षक\nपहला\n\n- एक\n- दो', 'updated_at': '2026-11-21T15:00:00.000Z'},
        {'id': 'privacy', 'title': 'गोपनीयता (नई)', 'body': 'नया पाठ'},
        {'id': 'BAD ID', 'title': 'x', 'body': 'y'},
        {'id': 'terms', 'title': '', 'body': 'y'},
      ]);
      final p = legalPages();
      expect(p.first.slug, 'cookies2');
      expect(p[1].title, 'गोपनीयता (नई)');
      expect(p.where((e) => e.slug == 'privacy').length, 1);
      expect(p.length, kLegalPages.length + 1);
      final b = p.first.blocks();
      expect(b.first.text, 'अंतिम अपडेट: 2026-11-21');
      expect(b.any((e) => e.kind == LegalKind.h && e.text == 'शीर्षक'), isTrue);
      expect(b.any((e) => e.kind == LegalKind.bullets && e.items.length == 2), isTrue);
    });
  });

  group('t430 manifest packs', () {
    test('live p_builtin manifest = nothing changes', () {
      final m = parseMediaManifest({'schema': 1, 'active_pack': 'p_builtin', 'packs': [{'id': 'p_builtin', 'name': 'Built-in', 'builtin': true}], 'icons': [], 'videos': []})!;
      expect(m.activePack, 'p_builtin');
      expect(m.packs.single.builtin, isTrue);
      expect(m.icons, isEmpty);
    });
    test('folder wins over key, key fallback, video loops by default, icon is poster', () {
      final mm = MediaManifest()
        ..debugSet(parseMediaManifest({
          'active_pack': 'p_0123456789ab',
          'icons': [
            {'pack': 'p_0123456789ab', 'target': 'key:om', 'url': 'https://x.dev/om.png'},
            {'pack': 'p_other', 'target': 'key:cross', 'url': 'https://x.dev/c.png'},
            {'target': 'slot:page:home', 'url': 'https://x.dev/h.png'},
          ],
          'videos': [
            {'pack': 'p_0123456789ab', 'placement': 'icon', 'target': 'key:om', 'url': 'https://x.dev/om.mp4', 'poster_url': null},
            {'pack': 'p_0123456789ab', 'placement': 'folder', 'target': 'folder:buddh', 'url': 'https://x.dev/b.mp4', 'loop': false},
            {'placement': 'chooser_list', 'url': 'https://x.dev/l.mp4'},
          ],
        })!);
      final hindu = mm.logoFor(folderPath: 'hindu', iconKey: 'om');
      expect(hindu.video?.url, 'https://x.dev/om.mp4');
      expect(hindu.video?.loop, isTrue);
      expect(hindu.poster, 'https://x.dev/om.png');
      final buddh = mm.logoFor(folderPath: 'buddh', iconKey: 'dharma');
      expect(buddh.video?.loop, isFalse);
      expect(mm.logoFor(folderPath: 'christian', iconKey: 'cross').image, isNull, reason: 'other pack ignored');
      expect(mm.iconFor('slot:page:home'), 'https://x.dev/h.png');
      expect(mm.videoFor('chooser_list')?.loop, isFalse, reason: 'chooser plays once');
    });
  });
}
