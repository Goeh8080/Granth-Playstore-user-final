// Explicit regeneration only: genuine GranthApp screens, offline fixed public catalog/covers.
import 'dart:convert';
import 'dart:io';
import 'dart:ui' as ui;
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:granthprabandhan/main.dart';
import 'package:granthprabandhan/screens/granths_screen.dart';
import 'package:granthprabandhan/screens/shelves_screen.dart';
import 'package:granthprabandhan/models/models.dart';
import 'package:granthprabandhan/services/catalog_store.dart';
import 'package:granthprabandhan/services/image_cache.dart';
import 'package:granthprabandhan/services/storage.dart';
import 'package:granthprabandhan/state/router.dart';
import 'package:granthprabandhan/state/ui_prefs.dart';
import 'helpers.dart';
import 'links_grid_test.dart' show settle;

void main() {
  setUp(setUpApp);
  testWidgets(
    'capture genuine folder and flat-list app screenshots (offline fixture)',
    skip: Platform.environment['CAPTURE_EXAMPLES'] != '1',
    (t) async {
      final raw =
          (jsonDecode(
                    File(
                      'test/fixtures/granth_examples/catalog.json',
                    ).readAsStringSync(),
                  )
                  as List)
              .cast<Map<String, dynamic>>();
      CatalogStore.I.debugSetCatalog(
        Catalog(topics: [], granths: raw.map(Granth.new).toList(), pramans: []),
      );
      await t.runAsync(() async {
        for (final family in {
          'NotoDeva': [
            'NotoSansDevanagari-Regular',
            'NotoSansDevanagari-Medium',
            'NotoSansDevanagari-SemiBold',
          ],
          'DMSans': ['DMSans-Regular', 'DMSans-Medium', 'DMSans-SemiBold'],
          'YatraOne': ['YatraOne-Devanagari'],
          'YatraOneLatin': ['YatraOne-Latin'],
          'NotoDevaFull': ['NotoSansDevanagari-Full'],
        }.entries) {
          final loader = FontLoader(family.key);
          for (final f in family.value) {
            loader.addFont(
              Future.value(
                ByteData.sublistView(
                  File('assets/fonts/$f.ttf').readAsBytesSync(),
                ),
              ),
            );
          }
          await loader.load();
        }
        for (final g in raw) {
          final p = g['imagePath'] as String? ?? '';
          final f = File('test/fixtures/granth_examples/${p.split('/').last}');
          if (p.isNotEmpty && f.existsSync()) {
            final out = ImageStore.I.fileFor(p);
            out.parent.createSync(recursive: true);
            f.copySync(out.path);
          }
        }
      });
      await t.binding.setSurfaceSize(const Size(390, 780));
      addTearDown(() => t.binding.setSurfaceSize(null));
      final key = GlobalKey();
      for (final mode in ['folders', 'list']) {
        UiPrefs.I.setCols(Store.kGranthCols, mode == 'folders' ? 2 : 1);
        await Store.I.setString('granth-view-mode', mode);
        await t.pumpWidget(const SizedBox());
        await t.pumpWidget(
          RepaintBoundary(
            key: key,
            child: GranthApp(key: ValueKey(mode), splash: false, links: false),
          ),
        );
        await settle(t, 8);
        AppNav.I.go('#/granths');
        await settle(t, 20);
        await t.runAsync(() async {
          for (final g in raw) {
            final path = g['imagePath'] as String? ?? '';
            final file = ImageStore.I.cachedSync(path);
            if (file != null) {
              await precacheImage(
                ResizeImage(FileImage(file), width: 1080),
                key.currentContext!,
              );
            }
          }
        });
        // Actual file decodes run outside FakeAsync, never a live image download.
        for (var i = 0; i < 8; i++) {
          await t.runAsync(
            () => Future<void>.delayed(const Duration(milliseconds: 30)),
          );
          await t.pump(const Duration(milliseconds: 100));
        }
        expect(find.byKey(const ValueKey('granth-view-picker')), findsNothing);
        expect(t.takeException(), isNull);
        final first = mode == 'folders'
            ? find.byType(FolderRow).first
            : find.byType(GranthCard).first;
        final cropY = ((t.getTopLeft(first).dy - 66).clamp(0, 700) * 2).round();
        await t.runAsync(() async {
          final full =
              await (key.currentContext!.findRenderObject()
                      as RenderRepaintBoundary)
                  .toImage(pixelRatio: 2);
          final recorder = ui.PictureRecorder();
          Canvas(recorder).drawImageRect(
            full,
            Rect.fromLTWH(
              0,
              cropY.toDouble(),
              full.width.toDouble(),
              full.height - cropY.toDouble(),
            ),
            Rect.fromLTWH(
              0,
              0,
              full.width.toDouble(),
              full.height - cropY.toDouble(),
            ),
            Paint(),
          );
          final picture = recorder.endRecording();
          final image = await picture.toImage(full.width, full.height - cropY);
          full.dispose();
          picture.dispose();
          final data = await image.toByteData(format: ui.ImageByteFormat.png);
          final out = File('assets/previews/granth-$mode-example.png');
          out.parent.createSync(recursive: true);
          out.writeAsBytesSync(data!.buffer.asUint8List());
          image.dispose();
        });
      }
    },
  );
}
