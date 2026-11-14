import 'package:flutter/services.dart';
import 'dart:io';
import 'dart:ui' as ui;
import 'package:flutter/rendering.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:granthprabandhan/screens/shelves_screen.dart';
import 'package:granthprabandhan/screens/granths_screen.dart';
import 'package:granthprabandhan/state/router.dart';
import 'package:granthprabandhan/state/ui_prefs.dart';
import 'package:granthprabandhan/services/storage.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'helpers.dart';

void main() {
  final previewKey = GlobalKey();
  setUp(() async {
    await setUpApp();
    await Store.I.remove('granth-view-mode');
    UiPrefs.I.animations = true;
  });

  Future<void> boot(
    WidgetTester t,
    String route, {
    double scale = 1.3,
    double height = 640,
    bool disableAnimations = false,
  }) async {
    if (Platform.environment['PREVIEW_DIR'] != null) {
      await t.runAsync(() async {
        for (final entry in {
          'NotoDeva': 'NotoSansDevanagari-Regular',
          'DMSans': 'DMSans-Regular',
          'YatraOne': 'YatraOne-Devanagari',
          'YatraOneLatin': 'YatraOne-Latin',
        }.entries) {
          final loader = FontLoader(entry.key)
            ..addFont(
              Future.value(
                ByteData.sublistView(
                  File('assets/fonts/${entry.value}.ttf').readAsBytesSync(),
                ),
              ),
            );
          await loader.load();
        }
      });
    }
    await t.binding.setSurfaceSize(Size(320, height));
    addTearDown(() => t.binding.setSurfaceSize(null));
    t.platformDispatcher.textScaleFactorTestValue = scale;
    addTearDown(t.platformDispatcher.clearTextScaleFactorTestValue);
    if (disableAnimations) {
      t.platformDispatcher.accessibilityFeaturesTestValue =
          FakeAccessibilityFeatures(disableAnimations: true);
      addTearDown(t.platformDispatcher.clearAccessibilityFeaturesTestValue);
    }
    await t.pumpWidget(
      RepaintBoundary(
        key: previewKey,
        child: MaterialApp(
          debugShowCheckedModeBanner: false,
          home: Scaffold(
            body: CustomScrollView(
              slivers: [ShelvesPanel(route: GRoute.parse(route))],
            ),
          ),
        ),
      ),
    );
    // Looping preview tickers never idle; advance past showPop's 280ms entry fade/rise
    // so the sheet is fully opaque before assertions or PREVIEW_DIR captures.
    await t.pump();
    await t.pump(const Duration(milliseconds: 300));
    await t.pump(const Duration(milliseconds: 16));
  }

  Future<void> proof(WidgetTester t, String name) async {
    final dir = Platform.environment['PREVIEW_DIR'];
    if (dir == null) return;
    await t.runAsync(() async {
      final image =
          await (previewKey.currentContext!.findRenderObject()
                  as RenderRepaintBoundary)
              .toImage(pixelRatio: 2);
      final bytes = await image.toByteData(format: ui.ImageByteFormat.png);
      Directory(dir).createSync(recursive: true);
      File('$dir/$name').writeAsBytesSync(bytes!.buffer.asUint8List());
      image.dispose();
    });
  }

  Future<void> afterChoice(WidgetTester t) async {
    await t.pump();
    await t.pump(const Duration(milliseconds: 400));
    await t.pumpAndSettle();
  }

  testWidgets(
    'first Granth entry asks once; list survives restart; choice is final',
    (t) async {
      UiPrefs.I.setCols(Store.kGranthCols, 2);
      await boot(t, '#/granths');
      expect(find.byKey(const ValueKey('granth-view-picker')), findsOneWidget);
      expect(find.byKey(const ValueKey('granth-view-change')), findsNothing);
      expect(find.textContaining('दृश्य बदलें'), findsNothing);
      final dir = Platform.environment['PREVIEW_DIR'];
      if (dir != null) {
        await proof(t, 'granth-choice-320dp.png');
      }
      await t.tap(find.byKey(const ValueKey('granth-view-list')));
      await afterChoice(t);
      expect(find.byType(GranthCard), findsWidgets);
      expect(Store.I.getString('granth-view-mode'), 'list');
      expect(
        UiPrefs.I.granthCols,
        2,
        reason: 'preview3×3 must not change the user grid',
      );
      expect(find.byKey(const ValueKey('granth-view-change')), findsNothing);
      expect(find.textContaining('दृश्य बदलें'), findsNothing);
      await proof(t, 'granth-choice-list-example-320dp.png');
      await t.pumpWidget(const SizedBox());
      await t.runAsync(
        () async => Store.I.initForTest(
          await SharedPreferences.getInstance(),
          Store.I.root,
        ),
      );
      await boot(t, '#/granths');
      expect(find.byKey(const ValueKey('granth-view-picker')), findsNothing);
      expect(find.byType(GranthCard), findsWidgets);
      expect(find.byKey(const ValueKey('granth-view-change')), findsNothing);
      expect(find.textContaining('दृश्य बदलें'), findsNothing);
      expect(Store.I.getString('granth-view-mode'), 'list');
      expect(t.takeException(), isNull);
    },
  );

  testWidgets('saved choice never re-prompts and has no change control', (t) async {
    await Store.I.setString('granth-view-mode', 'folders');
    await boot(t, '#/granths');
    expect(find.byKey(const ValueKey('granth-view-picker')), findsNothing);
    expect(find.byKey(const ValueKey('granth-view-change')), findsNothing);
    expect(find.textContaining('दृश्य बदलें'), findsNothing);
    expect(find.byType(FolderRow), findsWidgets);
  });

  testWidgets('deep granth links do not trigger first-use choice', (t) async {
    await boot(t, '#/granths?all=1');
    expect(find.byKey(const ValueKey('granth-view-picker')), findsNothing);
    expect(Store.I.getString('granth-view-mode'), isNull);
  });

  testWidgets(
    't368: chooser previews are live mini screens (real folder rows / granth tiles), not pictures, with accessible labels',
    (t) async {
      await boot(t, '#/granths');
      final picker = find.byKey(const ValueKey('granth-view-picker'));
      expect(find.descendant(of: picker, matching: find.byType(Image)), findsNothing);
      expect(find.byType(GranthViewLivePreview), findsNWidgets(2));
      expect(find.descendant(of: find.byKey(const ValueKey('granth-view-preview-folders')), matching: find.byType(FolderRow)), findsWidgets);
      expect(find.descendant(of: find.byKey(const ValueKey('granth-view-preview-list')), matching: find.text('कबीर सागर')), findsOneWidget);
      expect(find.bySemanticsLabel(RegExp('उदाहरण: फ़ोल्डर दृश्य')), findsOneWidget);
      expect(find.bySemanticsLabel(RegExp('उदाहरण: सभी ग्रंथ')), findsOneWidget);
      expect(find.descendant(of: picker, matching: find.byType(IconButton)), findsNothing, reason: 'no close button');
      expect(t.takeException(), isNull);
    },
  );

  testWidgets(
    'settled chooser sheet is opaque with a dim barrier and no entry fade left',
    (t) async {
      await boot(t, '#/granths');
      expect(find.byKey(const ValueKey('granth-view-picker')), findsOneWidget);
      final barriers = t.widgetList<ModalBarrier>(find.byType(ModalBarrier)).toList();
      expect(barriers, isNotEmpty);
      final dim = barriers.map((b) => b.color).whereType<Color>().toList();
      expect(dim, isNotEmpty);
      expect(dim.first.a, greaterThan(0.45), reason: 'chooser needs a proper dim scrim');
      // Entry FadeTransition must be finished (opacity 1); sheet surface is opaque paper.
      final fades = t.widgetList<FadeTransition>(
        find.descendant(
          of: find.byType(Overlay),
          matching: find.byType(FadeTransition),
        ),
      );
      for (final f in fades) {
        expect(f.opacity.value, closeTo(1.0, 0.02));
      }
      final paper = t.getRect(find.byKey(const ValueKey('granth-view-picker')));
      expect(paper.top, greaterThan(40));
      expect(paper.bottom, lessThan(640));
      expect(paper.left, greaterThanOrEqualTo(0));
      expect(paper.right, lessThanOrEqualTo(320));
      await proof(t, 'granth-choice-settled-opaque-320dp.png');
      expect(t.takeException(), isNull);
    },
  );

  testWidgets(
    'both animated previews fit side by side without scrolling at320dp and1.3',
    (t) async {
      await boot(t, '#/granths');
      final a = t.getRect(find.byKey(const ValueKey('granth-view-folders'))),
          b = t.getRect(find.byKey(const ValueKey('granth-view-list')));
      expect(b.left, greaterThanOrEqualTo(a.right));
      expect((a.top - b.top).abs(), lessThan(1));
      expect(a.bottom, lessThanOrEqualTo(640));
      expect(b.bottom, lessThanOrEqualTo(640));
      expect(
        find.byKey(const ValueKey('granth-view-folders')).hitTestable(),
        findsOneWidget,
      );
      expect(
        find.byKey(const ValueKey('granth-view-list')).hitTestable(),
        findsOneWidget,
      );
      expect(
        find.byKey(const ValueKey('granth-view-preview-folders')),
        findsOneWidget,
      );
      expect(
        find.byKey(const ValueKey('granth-view-preview-list')),
        findsOneWidget,
      );
      expect(
        find.descendant(
          of: find.byKey(const ValueKey('granth-view-picker')),
          matching: find.byType(Scrollable),
        ),
        findsNothing,
      );
      await proof(t, 'granth-choice-side-by-side-320dp-1.3.png');
      expect(t.takeException(), isNull);
    },
  );

  for (final scale in [1.0, 2.0]) {
    testWidgets(
      'side-by-side chooser fits320dp at text scale $scale without disabling scaling',
      (t) async {
        await boot(
          t,
          '#/granths',
          scale: scale,
          height: scale == 2.0 ? 480 : 640,
        );
        final a = t.getRect(find.byKey(const ValueKey('granth-view-folders'))),
            b = t.getRect(find.byKey(const ValueKey('granth-view-list')));
        expect((a.top - b.top).abs(), lessThan(1));
        expect(b.left, greaterThanOrEqualTo(a.right));
        expect(
          find.byKey(const ValueKey('granth-view-folders')).hitTestable(),
          findsOneWidget,
        );
        expect(
          find.byKey(const ValueKey('granth-view-list')).hitTestable(),
          findsOneWidget,
        );
        expect(t.takeException(), isNull);
        await proof(t, 'granth-choice-side-by-side-320dp-$scale.png');
      },
    );
  }

  testWidgets('preview animation controllers dispose when chooser closes', (
    t,
  ) async {
    await boot(t, '#/granths');
    expect(find.byKey(const ValueKey('granth-view-preview-folders')), findsOneWidget);
    expect(find.byKey(const ValueKey('granth-view-preview-list')), findsOneWidget);
    final before = t.binding.transientCallbackCount;
    expect(before, greaterThan(0), reason: 'looping preview tickers should be active');
    await t.pump(const Duration(milliseconds: 500));
    await t.tap(find.byKey(const ValueKey('granth-view-folders')));
    await afterChoice(t);
    expect(find.byKey(const ValueKey('granth-view-picker')), findsNothing);
    expect(find.byKey(const ValueKey('granth-view-preview-folders')), findsNothing);
    expect(find.byKey(const ValueKey('granth-view-preview-list')), findsNothing);
    expect(t.takeException(), isNull);
  });

  testWidgets('reduce-motion keeps static previews without looping tickers', (
    t,
  ) async {
    await boot(t, '#/granths', disableAnimations: true);
    expect(find.byKey(const ValueKey('granth-view-picker')), findsOneWidget);
    expect(find.byKey(const ValueKey('granth-view-preview-folders')), findsOneWidget);
    expect(find.byKey(const ValueKey('granth-view-preview-list')), findsOneWidget);
    // Accessibility reduce-motion: Motion.on is false, so the previews stay at the top.
    double y(String mode) => t.widget<Transform>(find.descendant(of: find.byKey(ValueKey('granth-view-preview-$mode')), matching: find.byKey(const ValueKey('granth-view-preview-page')))).transform.getTranslation().y;
    expect(y('folders'), 0);
    await t.pump(const Duration(seconds: 3));
    expect(y('folders'), 0);
    expect(y('list'), 0);
    await t.tap(find.byKey(const ValueKey('granth-view-list')));
    await afterChoice(t);
    expect(Store.I.getString('granth-view-mode'), 'list');
    expect(t.takeException(), isNull);
  });
}
