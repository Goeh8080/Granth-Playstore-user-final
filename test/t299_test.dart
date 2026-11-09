// t299/t301: admin-forced Granth view, themed chooser text, full previews, 100% image
// quality (decode + PDF), card PDF end to end, login page copy.
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:granthprabandhan/screens/granths_screen.dart';
import 'package:granthprabandhan/screens/login_screen.dart';
import 'package:granthprabandhan/screens/shelves_screen.dart';
import 'package:granthprabandhan/services/card_pdf.dart';
import 'package:granthprabandhan/services/catalog_store.dart';
import 'package:granthprabandhan/services/pdf_builder.dart';
import 'package:granthprabandhan/services/remote_config.dart';
import 'package:granthprabandhan/services/storage.dart';
import 'package:granthprabandhan/state/router.dart';
import 'package:granthprabandhan/state/ui_prefs.dart';
import 'package:granthprabandhan/widgets/granth_image.dart';
import 'package:image/image.dart' as img;
import 'helpers.dart';

void main() {
  setUp(() async {
    await setUpApp();
    await Store.I.remove(granthViewKey);
    RemoteConfig.I.uiGranthViewMode = null;
    UiPrefs.I.animations = true;
  });
  tearDown(() => RemoteConfig.I.uiGranthViewMode = null);

  Future<void> boot(WidgetTester t, {ThemeData? theme}) async {
    await t.binding.setSurfaceSize(const Size(320, 640));
    addTearDown(() => t.binding.setSurfaceSize(null));
    await t.pumpWidget(MaterialApp(
      theme: theme,
      home: Scaffold(body: CustomScrollView(slivers: [ShelvesPanel(route: GRoute.parse('#/granths'))])),
    ));
    await t.pump();
    await t.pump(const Duration(milliseconds: 300));
    await t.pump(const Duration(milliseconds: 16));
  }

  group('ui.granth_view_mode', () {
    test('parse: folders / list / aliases; user_choice, unknown, missing → null', () {
      expect(parseGranthViewMode({'granth_view_mode': 'folders'}), 'folders');
      expect(parseGranthViewMode({'granth_view_mode': 'LIST'}), 'list');
      expect(parseGranthViewMode({'granth_view_mode': 'ek_suchi'}), 'list');
      expect(parseGranthViewMode({'granth_view_mode': 'user_choice'}), isNull);
      expect(parseGranthViewMode({'granth_view_mode': 'grid'}), isNull);
      expect(parseGranthViewMode({'granth_view_mode': 3}), isNull);
      expect(parseGranthViewMode({}), isNull);
      expect(parseGranthViewMode(null), isNull);
    });

    testWidgets('admin list: chooser skipped, flat list shown, saved user choice untouched', (t) async {
      await Store.I.setString(granthViewKey, 'folders');
      RemoteConfig.I.uiGranthViewMode = 'list';
      await boot(t);
      expect(find.byKey(const ValueKey('granth-view-picker')), findsNothing);
      expect(find.byType(GranthCard), findsWidgets);
      expect(Store.I.getString(granthViewKey), 'folders', reason: 'old saved prefs are never rewritten');
    });

    testWidgets('admin folders with no saved choice: no chooser, folders shown', (t) async {
      RemoteConfig.I.uiGranthViewMode = 'folders';
      await boot(t);
      expect(find.byKey(const ValueKey('granth-view-picker')), findsNothing);
      expect(find.byType(FolderRow), findsWidgets);
      expect(Store.I.getString(granthViewKey), isNull);
    });

    testWidgets('user_choice/absent: once-only chooser still appears', (t) async {
      await boot(t);
      expect(find.byKey(const ValueKey('granth-view-picker')), findsOneWidget);
    });

    testWidgets('chooser cannot be dismissed without a pick; pick is saved and not asked again', (t) async {
      await boot(t);
      expect(find.byKey(const ValueKey('granth-view-picker')), findsOneWidget);
      await t.tapAt(const Offset(4, 4)); // outside the card
      await t.pump(const Duration(milliseconds: 400));
      expect(find.byKey(const ValueKey('granth-view-picker')), findsOneWidget, reason: 'outside tap does not close it');
      await t.binding.handlePopRoute(); // Android Back
      await t.pump(const Duration(milliseconds: 400));
      expect(find.byKey(const ValueKey('granth-view-picker')), findsOneWidget, reason: 'Back does not close it');
      await t.tap(find.byKey(const ValueKey('granth-view-list')));
      await t.pump(const Duration(milliseconds: 400));
      expect(Store.I.getString(granthViewKey), 'list');
      await t.pumpWidget(const SizedBox());
      await boot(t);
      expect(find.byKey(const ValueKey('granth-view-picker')), findsNothing, reason: 'asked only once');
    });

    test('logout key: the saved choice uses the shared Store key', () {
      expect(granthViewKey, Store.kGranthView);
      expect(granthViewKey, 'granth-view-mode', reason: 'old installs keep their saved choice');
    });
  });

  testWidgets('chooser text follows the theme (primary + text theme), previews show full width', (t) async {
    const primary = Color(0xFF00695C);
    final theme = ThemeData(colorScheme: ColorScheme.fromSeed(seedColor: primary, primary: primary));
    await boot(t, theme: theme);
    Text text(String k) => t.widget<Text>(find.byKey(ValueKey(k)));
    expect(text('granth-view-heading').style?.color, primary);
    expect(text('granth-view-title-folders').style?.color, primary);
    expect(text('granth-view-title-list').style?.color, primary);
    final bodyColor = theme.textTheme.bodySmall!.color!;
    expect(text('granth-view-note').style?.color, bodyColor.withValues(alpha: 0.72));
    for (final mode in ['folders', 'list']) {
      final strip = find.byKey(ValueKey('granth-view-preview-$mode'));
      final image = find.descendant(of: strip, matching: find.byType(Image));
      expect(t.getSize(image).width, closeTo(t.getSize(strip).width, 0.5), reason: '$mode: every column visible');
    }
    // Complete folder screen is taller than its window → it scrolls (loops) through all of it.
    final fStrip = find.byKey(const ValueKey('granth-view-preview-folders'));
    final fImage = find.descendant(of: fStrip, matching: find.byType(Image));
    expect(t.getSize(fImage).height, greaterThan(t.getSize(fStrip).height));
    final y0 = t.getTopLeft(fImage).dy;
    await t.pump(const Duration(milliseconds: 4500));
    expect(t.getTopLeft(fImage).dy, lessThan(y0 - 10), reason: 'folder preview loops down to the end');
    expect(t.takeException(), isNull);
  });

  test('preview assets: complete folder screen and real 3×3 list at 2×', () {
    final f = img.decodePng(File('assets/previews/granth-folders-example.png').readAsBytesSync())!;
    final l = img.decodePng(File('assets/previews/granth-list-example.png').readAsBytesSync())!;
    expect(f.width / f.height, closeTo(780 / 1880, 0.001));
    expect(l.width / l.height, closeTo(780 / 1146, 0.001));
  });

  testWidgets('display decode width: physical pixels ≥3×, 128 px buckets', (t) async {
    late BuildContext ctx;
    await t.pumpWidget(MediaQuery(data: const MediaQueryData(devicePixelRatio: 2.0), child: Builder(builder: (c) {
      ctx = c;
      return const SizedBox();
    })));
    expect(displayDecodeWidth(ctx, 400), 1280);
    expect(displayDecodeWidth(ctx, 52), 256);
    expect(displayDecodeWidth(ctx, double.infinity), isNull);
  });

  test('PDF: converted pictures keep full resolution, lossless (no JPEG re-encode, no downscale)', () {
    final src = img.Image(width: 5000, height: 40, numChannels: 4);
    img.fill(src, color: img.ColorRgba8(10, 120, 200, 128));
    final p = prepareImageSync(Uint8List.fromList(img.encodePng(src)))!;
    expect(p.w, 5000);
    expect(p.h, 40);
    expect(p.rgba, isTrue);
    final webpLike = img.Image(width: 4500, height: 30);
    img.fill(webpLike, color: img.ColorRgb8(1, 2, 3));
    final bmp = prepareImageSync(Uint8List.fromList(img.encodeBmp(webpLike)))!;
    expect((bmp.w, bmp.h, bmp.rgba), (4500, 30, true));
  });

  testWidgets('card PDF end to end: own name, PDF folder, overwrites itself, never the हाईलाइट PDF', (t) async {
    await t.binding.setSurfaceSize(const Size(320, 1000));
    addTearDown(() => t.binding.setSurfaceSize(null));
    UiPrefs.I.animations = false;
    final g = CatalogStore.I.granths.first;
    final key = GlobalKey();
    await t.pumpWidget(MaterialApp(
      home: Scaffold(body: SingleChildScrollView(child: RepaintBoundary(key: key, child: GranthCard(granth: g, index: 1, total: 2, cols: 1)))),
    ));
    await t.pumpAndSettle();
    final name = CardPdf.fileName(g.title);
    expect(name, endsWith(' - कार्ड.pdf'));
    // A highlight PDF of the same granth already sits in the PDF folder.
    final hl = File('${Store.I.pdfDir}/${g.title}.pdf')..createSync(recursive: true);
    hl.writeAsStringSync('%PDF-highlight');
    final a = await t.runAsync(() => CardPdf.build(key, name));
    expect(a, isNotNull);
    expect(a!.path, startsWith(Store.I.pdfDir));
    final bytes = a.readAsBytesSync();
    expect(String.fromCharCodes(bytes.take(5)), '%PDF-');
    final head = String.fromCharCodes(bytes.take(4000).where((b) => b < 128));
    final w = int.parse(RegExp(r'/Width (\d+)').firstMatch(head)!.group(1)!);
    expect(w, greaterThanOrEqualTo(320 * 3), reason: 'card drawn at ≥3×');
    expect(head, contains('/FlateDecode'));
    final first = a.lastModifiedSync();
    final b = await t.runAsync(() => CardPdf.build(key, name));
    expect(b!.path, a.path);
    expect(b.lastModifiedSync().isBefore(first), isFalse);
    expect(hl.readAsStringSync(), '%PDF-highlight', reason: 'highlight PDF untouched');
    expect(File('${a.path}.part').existsSync(), isFalse);
    expect(t.takeException(), isNull);
  });

  testWidgets('login page no longer says anything about login being required', (t) async {
    await t.pumpWidget(MaterialApp(home: LoginPage(onSkip: () {})));
    expect(find.textContaining('ज़रूरी'), findsNothing);
    expect(find.textContaining('अकाउंट में दिखेंगे'), findsOneWidget);
    expect(find.byKey(const ValueKey('login-skip')), findsOneWidget);
  });
}
