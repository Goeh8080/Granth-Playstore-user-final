import 'package:flutter/services.dart';
import 'dart:io';
import 'dart:ui' as ui;
import 'package:flutter/rendering.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:granthprabandhan/screens/shelves_screen.dart';
import 'package:granthprabandhan/screens/granths_screen.dart';
import 'package:granthprabandhan/state/router.dart';
import 'package:granthprabandhan/services/storage.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'helpers.dart';

void main() {
  final previewKey = GlobalKey();
  setUp(() async {
    await setUpApp();
    await Store.I.remove('granth-view-mode');
  });
  Future<void> boot(WidgetTester t, String route) async {
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
    await t.binding.setSurfaceSize(const Size(320, 740));
    addTearDown(() => t.binding.setSurfaceSize(null));
    t.platformDispatcher.textScaleFactorTestValue = 1.3;
    addTearDown(t.platformDispatcher.clearTextScaleFactorTestValue);
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
    await t.runAsync(() async {
      for (final name in [
        'granth-folders-example.png',
        'granth-list-example.png',
      ]) {
        await precacheImage(
          AssetImage('assets/previews/$name'),
          previewKey.currentContext!,
        );
      }
    });
    await t.pumpAndSettle();
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
      File('$dir/$name').writeAsBytesSync(bytes!.buffer.asUint8List());
      image.dispose();
    });
  }

  testWidgets(
    'first Granth entry asks once; list survives restart; can switch to folders',
    (t) async {
      await boot(t, '#/granths');
      expect(find.byKey(const ValueKey('granth-view-picker')), findsOneWidget);
      final dir = Platform.environment['PREVIEW_DIR'];
      if (dir != null) {
        await t.runAsync(() async {
          final image =
              await (previewKey.currentContext!.findRenderObject()
                      as RenderRepaintBoundary)
                  .toImage(pixelRatio: 2);
          final bytes = await image.toByteData(format: ui.ImageByteFormat.png);
          Directory(dir).createSync(recursive: true);
          File(
            '$dir/granth-choice-320dp.png',
          ).writeAsBytesSync(bytes!.buffer.asUint8List());
          image.dispose();
        });
      }
      await t.ensureVisible(find.byKey(const ValueKey('granth-view-list')));
      await t.pumpAndSettle();
      await proof(t, 'granth-choice-list-example-320dp.png');
      await t.tap(find.byKey(const ValueKey('granth-view-list')));
      await t.pumpAndSettle();
      expect(find.byType(GranthCard), findsWidgets);
      expect(Store.I.getString('granth-view-mode'), 'list');
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
      await t.tap(find.byKey(const ValueKey('granth-view-change')));
      await t.pumpAndSettle();
      await t.ensureVisible(find.byKey(const ValueKey('granth-view-folders')));
      await t.tap(find.byKey(const ValueKey('granth-view-folders')));
      await t.pumpAndSettle();
      expect(Store.I.getString('granth-view-mode'), 'folders');
      expect(find.byType(FolderRow), findsWidgets);
      expect(t.takeException(), isNull);
    },
  );
  testWidgets('deep granth links do not trigger first-use choice', (t) async {
    await boot(t, '#/granths?all=1');
    expect(find.byKey(const ValueKey('granth-view-picker')), findsNothing);
    expect(Store.I.getString('granth-view-mode'), isNull);
  });
  testWidgets(
    'chooser contains genuine bundled folder and list screenshots with accessible labels',
    (t) async {
      await boot(t, '#/granths');
      final images = t
          .widgetList<Image>(find.byType(Image))
          .where((i) => i.image is AssetImage)
          .toList();
      expect(
        images.map((i) => (i.image as AssetImage).assetName),
        containsAll([
          'assets/previews/granth-folders-example.png',
          'assets/previews/granth-list-example.png',
        ]),
      );
      expect(
        images.where((i) => i.semanticLabel?.contains('उदाहरण') == true).length,
        2,
      );
      final painted = t.widgetList<RawImage>(
        find.descendant(
          of: find.byKey(const ValueKey('granth-view-picker')),
          matching: find.byType(RawImage),
        ),
      );
      expect(
        painted.where((i) => i.image != null).length,
        2,
        reason:
            'both real examples must actually decode/paint, not just have Image widgets',
      );
      for (final name in [
        'granth-folders-example.png',
        'granth-list-example.png',
      ]) {
        final bytes = File('assets/previews/$name').readAsBytesSync();
        final codec = await t.runAsync(() => ui.instantiateImageCodec(bytes));
        final frame = await t.runAsync(() => codec!.getNextFrame());
        expect(frame!.image.width, greaterThanOrEqualTo(700));
        frame.image.dispose();
        codec!.dispose();
      }
      expect(t.takeException(), isNull);
    },
  );
}
