import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:granthprabandhan/screens/shelves_screen.dart';
import 'package:granthprabandhan/state/router.dart';
import 'package:granthprabandhan/services/storage.dart';

import 'helpers.dart';

/// Captures still + frame sequence of the side-by-side looping chooser for proof media.
/// Run: PREVIEW_DIR=/workspace/ai_audit/nov7_app/previews-real CAPTURE_CHOOSER_ANIM=1 \
///   flutter test test/granth_choice_anim_capture_test.dart --no-pub
void main() {
  final previewKey = GlobalKey();

  setUp(() async {
    await setUpApp();
    await Store.I.remove('granth-view-mode');
  });

  testWidgets('capture animating chooser frames', (t) async {
    final dir = Platform.environment['PREVIEW_DIR'];
    final capture = Platform.environment['CAPTURE_CHOOSER_ANIM'] == '1';
    if (dir == null || !capture) return;

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

    await t.binding.setSurfaceSize(const Size(320, 640));
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
              slivers: [ShelvesPanel(route: GRoute.parse('#/granths'))],
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
    // Wait out showPop's 280ms fade+rise so the sheet and scrim are fully settled.
    await t.pump();
    await t.pump(const Duration(milliseconds: 300));
    await t.pump(const Duration(milliseconds: 16));
    expect(find.byKey(const ValueKey('granth-view-picker')), findsOneWidget);

    Directory(dir).createSync(recursive: true);
    final framesDir = Directory('$dir/chooser-anim-frames')..createSync(recursive: true);
    for (final f in framesDir.listSync()) {
      f.deleteSync();
    }

    Future<void> shot(String path) async {
      await t.runAsync(() async {
        final image =
            await (previewKey.currentContext!.findRenderObject()
                    as RenderRepaintBoundary)
                .toImage(pixelRatio: 2);
        final bytes = await image.toByteData(format: ui.ImageByteFormat.png);
        File(path).writeAsBytesSync(bytes!.buffer.asUint8List());
        image.dispose();
      });
    }

    await shot('$dir/granth-choice-anim-still-320dp.png');
    await shot('$dir/granth-choice-320dp.png');
    await shot('$dir/granth-choice-side-by-side-320dp-1.3.png');

    // Capture only after entry settled; ~3.2s of preview scroll at 10 fps.
    for (var i = 0; i < 32; i++) {
      await t.pump(const Duration(milliseconds: 100));
      await shot('${framesDir.path}/frame_${i.toString().padLeft(3, '0')}.png');
    }
    expect(t.takeException(), isNull);
  });
}
