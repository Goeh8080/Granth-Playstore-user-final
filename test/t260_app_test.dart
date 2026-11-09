import 'package:granthprabandhan/models/structure.dart';
import 'package:granthprabandhan/services/shelves.dart';
import 'package:granthprabandhan/widgets/religion_symbol.dart';
import 'package:granthprabandhan/services/card_pdf.dart';
import 'package:granthprabandhan/services/catalog_store.dart';
import 'package:granthprabandhan/services/ai_feedback.dart';
import 'package:flutter/rendering.dart';
import 'dart:ui' as ui;
import 'package:shared_preferences/shared_preferences.dart';
import 'package:granthprabandhan/services/image_cache.dart';
import 'package:granthprabandhan/widgets/granth_image.dart';
import 'package:granthprabandhan/widgets/overlays.dart';
import 'package:granthprabandhan/widgets/zoom.dart';
import 'package:granthprabandhan/screens/shelves_screen.dart';
import 'package:granthprabandhan/state/router.dart';
import 'package:granthprabandhan/screens/ai_screen.dart';
import 'package:granthprabandhan/ai/ai_client.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:granthprabandhan/services/search_history.dart';
import 'package:granthprabandhan/widgets/common.dart';
import 'package:granthprabandhan/screens/granths_screen.dart';
import 'package:granthprabandhan/state/ui_prefs.dart';
import 'package:granthprabandhan/services/remote_config.dart';
import 'package:granthprabandhan/services/storage.dart';
import 'helpers.dart';

void main() {
  setUp(setUpApp);
  test(
    'history keeps only five complete, nonempty, deduplicated searches',
    () async {
      for (final q in [
        'one',
        'two',
        'three',
        'four',
        'five',
        'six',
        ' TWO ',
        '  ',
      ]) {
        await SearchHistory.remember(q);
      }
      expect(SearchHistory.recent, ['TWO', 'six', 'five', 'four', 'three']);
    },
  );
  testWidgets('history recalls query at 320dp without overflow', (t) async {
    await SearchHistory.remember('गीता');
    await t.binding.setSurfaceSize(const Size(320, 700));
    addTearDown(() => t.binding.setSurfaceSize(null));
    var query = '';
    await t.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: SearchField(placeholder: 'खोजें', onChanged: (q) => query = q),
        ),
      ),
    );
    await t.tap(find.byType(TextField));
    await t.pumpAndSettle();
    await t.tap(find.text('गीता'));
    await t.pumpAndSettle();
    expect(query, 'गीता');
    expect(t.takeException(), isNull);
  });
  testWidgets('folder header uses shelves policy, not granths policy', (
    t,
  ) async {
    RemoteConfig.I.uiGridForce = {'shelves': 3, 'granths': 1};
    addTearDown(() => RemoteConfig.I.debugReset());
    UiPrefs.I.setCols(Store.kGranthCols, 2);
    await t.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: CustomScrollView(
            slivers: [
              GranthsPanel(
                idle: (_, _, _) =>
                    const SliverToBoxAdapter(child: Text('folders')),
              ),
            ],
          ),
        ),
      ),
    );
    await t.pumpAndSettle();
    expect(t.widget<GridSwitch>(find.byType(GridSwitch)).value, 3);
    expect(t.widget<GridSwitch>(find.byType(GridSwitch)).locked, isTrue);
  });
  test(
    'history survives preference reload and ignores corrupted storage',
    () async {
      await SearchHistory.remember('वेद');
      final p = await SharedPreferences.getInstance();
      await Store.I.initForTest(p, Store.I.root);
      expect(SearchHistory.recent, ['वेद']);
      await Store.I.setString(SearchHistory.key, 'bad json');
      expect(SearchHistory.recent, isEmpty);
    },
  );

  testWidgets('folder-level search filters descendant granths at 320dp', (
    t,
  ) async {
    await t.binding.setSurfaceSize(const Size(320, 700));
    addTearDown(() => t.binding.setSurfaceSize(null));
    await t.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: CustomScrollView(
            slivers: [ShelvesPanel(route: GRoute.parse('#/granths?r=hindu'))],
          ),
        ),
      ),
    );
    await t.pumpAndSettle();
    await t.enterText(find.byType(TextField), 'gita');
    await t.pump(const Duration(milliseconds: 300));
    await t.pumpAndSettle();
    expect(find.byType(GranthCard), findsWidgets);
    expect(t.takeException(), isNull);
  });

  testWidgets(
    'original decode at zoom, bounded decode at rest, no file recompression',
    (t) async {
      final file = ImageStore.I.fileFor('uploads/quality.png');
      await t.runAsync(() async {
        final recorder = ui.PictureRecorder();
        final canvas = Canvas(recorder)..drawColor(Colors.blue, BlendMode.src);
        canvas.drawRect(
          const Rect.fromLTWH(100, 100, 20, 20),
          Paint()..color = Colors.red,
        );
        final picture = recorder.endRecording();
        final image = await picture.toImage(2200, 1200);
        final png = await image.toByteData(format: ui.ImageByteFormat.png);
        await file.writeAsBytes(png!.buffer.asUint8List());
        image.dispose();
        picture.dispose();
      });
      final bytes = file.readAsBytesSync();
      AppZoom.magnified.value = false;
      addTearDown(() => AppZoom.magnified.value = false);
      await t.pumpWidget(
        const MaterialApp(
          home: Scaffold(body: GranthImage(path: 'uploads/quality.png')),
        ),
      );
      await t.runAsync(
        () => Future<void>.delayed(const Duration(milliseconds: 100)),
      );
      await t.pumpAndSettle();
      ImageProvider provider() => t.widget<Image>(find.byType(Image)).image;
      expect(provider(), isA<ResizeImage>());
      AppZoom.magnified.value = true;
      await t.pump();
      expect(provider(), isA<FileImage>());
      for (var i = 0; i < 10; i++) {
        await t.runAsync(
          () => Future<void>.delayed(const Duration(milliseconds: 50)),
        );
        await t.pump(const Duration(milliseconds: 50));
      }
      final raw = t.renderObject<RenderImage>(find.byType(RawImage).first);
      expect(
        raw.image?.width,
        2200,
        reason: 'actual decoded width equals the original, not 1080',
      );
      expect(file.readAsBytesSync(), bytes);
    },
  );

  testWidgets(
    'opening photo from outer zoom resets parent and viewer can zoom back out',
    (t) async {
      await t.binding.setSurfaceSize(const Size(320, 700));
      addTearDown(() => t.binding.setSurfaceSize(null));
      AppZoom.suspended.value = 0;
      await t.pumpWidget(
        MaterialApp(
          builder: (_, child) => AppZoom(child: child!),
          home: Builder(
            builder: (context) => Scaffold(
              body: Center(
                child: TextButton(
                  onPressed: () =>
                      openLightbox(context, ['uploads/missing.png']),
                  child: const Text('open'),
                ),
              ),
            ),
          ),
        ),
      );
      Future<void> pinch(double from, double to) async {
        final a = await t.startGesture(Offset(160 - from / 2, 300), pointer: 7);
        final b = await t.startGesture(Offset(160 + from / 2, 300), pointer: 8);
        await t.pump();
        await a.moveTo(Offset(160 - to / 2, 300));
        await b.moveTo(Offset(160 + to / 2, 300));
        await t.pump();
        await a.up();
        await b.up();
        await t.pump(const Duration(milliseconds: 500));
        await t.pump();
      }

      await pinch(80, 180);
      expect(AppZoom.current.value.scale, greaterThan(1));
      // Invoke the real button callback, avoiding the intentionally transformed tap location.
      t.widget<TextButton>(find.byType(TextButton)).onPressed!();
      await t.pump(const Duration(milliseconds: 500));
      await t.pump();
      expect(AppZoom.current.value.scale, 1);
      expect(AppZoom.suspended.value, 1);
      await pinch(80, 180);
      final stage = t.state<ZoomStageState>(find.byType(ZoomStage));
      expect(stage.view.scale, greaterThan(1));
      await t.tapAt(const Offset(160, 300));
      await t.pump(const Duration(milliseconds: 100));
      await t.tapAt(const Offset(160, 300));
      await t.pump(const Duration(milliseconds: 500));
      await t.pump();
      await t.pump(const Duration(milliseconds: 350));
      expect(stage.view.scale, 1);
      expect(t.takeException(), isNull);
      await t.tap(find.text('बंद'));
      await t.pump(const Duration(milliseconds: 500));
      await t.pump();
      expect(AppZoom.suspended.value, 0);
    },
  );

  testWidgets(
    'quiz grades only after submit: a right pick is green, the other cards stay plain at 320dp',
    (t) async {
      await t.binding.setSurfaceSize(const Size(320, 700));
      addTearDown(() => t.binding.setSurfaceSize(null));
      const q = QuizQuestion(
        id: 'q',
        text: 'प्रश्न?',
        options: ['सही', 'गलत', 'दूसरा गलत', 'तीसरा गलत'],
      );
      await t.pumpWidget(
        const MaterialApp(
          home: Scaffold(
            body: QuizOptions(
              question: q,
              selected: 'सही',
              result: QuizResult(questionId: 'q', correct: true),
            ),
          ),
        ),
      );
      final containers = t
          .widgetList<Container>(find.byType(Container))
          .where((c) => c.decoration is BoxDecoration)
          .toList();
      expect(
        containers
            .where(
              (c) =>
                  (c.decoration as BoxDecoration).color ==
                  const Color(0xFFE3F4E6),
            )
            .length,
        1,
      );
      expect(
        containers
            .where(
              (c) =>
                  (c.decoration as BoxDecoration).color ==
                  const Color(0xFFFBE4E1),
            )
            .length,
        0,
      );
      expect(t.takeException(), isNull);
    },
  );

  test('offline flag stays queued, not reported as delivered', () async {
    final feedback = AiFeedback(enabled: false);
    await feedback.down('answer-1', question: 'प्रश्न', answer: 'उत्तर');
    expect(feedback.isQueued('answer-1'), isTrue);
    expect(feedback.vote('answer-1'), -1);
  });

  testWidgets(
    'Granth PDF picker has third card option and card renders as PDF at 320dp',
    (t) async {
      await t.binding.setSurfaceSize(const Size(320, 1000));
      addTearDown(() => t.binding.setSurfaceSize(null));
      UiPrefs.I.animations = false;
      final key = GlobalKey();
      await t.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: SingleChildScrollView(
              child: RepaintBoundary(
                key: key,
                child: GranthCard(
                  granth: CatalogStore.I.granths.first,
                  index: 1,
                  total: 2,
                  cols: 1,
                ),
              ),
            ),
          ),
        ),
      );
      await t.pumpAndSettle();
      final file = await t.runAsync(
        () => CardPdf.build(key, 'card-test.pdf', dir: Store.I.root),
      );
      expect(file, isNotNull);
      expect(String.fromCharCodes(file!.readAsBytesSync().take(5)), '%PDF-');
      await t.tap(find.text('हाईलाइट PDF'));
      await t.pumpAndSettle();
      expect(
        find.byKey(const ValueKey('granth-card-pdf-option')),
        findsOneWidget,
      );
      expect(t.takeException(), isNull);
    },
  );
  testWidgets('legacy ektara renders identically to canonical kabir', (t) async {
    Future<List<int>> pixels(String name) async {
      final recorder = ui.PictureRecorder();
      ReligionSymbolPainter(name, Colors.brown).paint(Canvas(recorder), const Size(80, 80));
      final picture = recorder.endRecording();
      final image = await picture.toImage(80, 80);
      final data = await image.toByteData(format: ui.ImageByteFormat.rawRgba);
      image.dispose(); picture.dispose();
      return data!.buffer.asUint8List().toList();
    }
    final result = await t.runAsync(() async => [await pixels('ektara'), await pixels('kabir')]);
    expect(result![0], result[1]);
  });

  testWidgets('canonical Other tone honors explicit valid colors and keeps historical defaults', (t) async {
    expect(ShelfReligion.fromJson({'id': 'r', 'title': 'R'}).tone, 'maroon');
    expect(ShelfGroup.fromJson({'id': 'other', 'title': 'अन्य'}).tone, 'gold');
    expect(ShelfGroup.fromJson({'id': 'other', 'title': 'अन्य', 'tone': 'unknown'}).tone, 'gold');
    expect(religionSymbolNames, isNot(contains('ektara')));
    for (final pair in {'saffron': Tone.saffron, 'maroon': Tone.maroon, 'gold': Tone.gold}.entries) {
      Shelves.use(Structure.fromMap({'other': {'id': 'other', 'title': 'अन्य', 'icon': 'ektara', 'tone': pair.key}}));
      await t.pumpWidget(MaterialApp(home: Scaffold(body: CustomScrollView(slivers: [ShelvesPanel(route: GRoute.parse('#/granths'))]))));
      await t.pumpAndSettle();
      final symbols = t.widgetList<ReligionSymbol>(find.byType(ReligionSymbol));
      expect(symbols.where((s) => s.name == 'ektara').single.tone, pair.value);
      await t.pumpWidget(const SizedBox());
    }
  });

}
