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
            'TiroDevanagari': ['TiroDevanagariSanskrit-Regular'],
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
      addTearDown(() => t.binding.setSurfaceSize(null));
      final key = GlobalKey();
      for (final mode in ['folders', 'list']) {
        // Tall phone surface so the COMPLETE folder screen (every religion folder) is captured.
        await t.binding.setSurfaceSize(Size(390, mode == 'folders' ? 1500 : 1100));
        UiPrefs.I.setCols(Store.kGranthCols, mode == 'folders' ? 2 : 3);
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
        if (mode == 'list') {
          final cards = t
              .widgetList<GranthCard>(find.byType(GranthCard))
              .toList();
          expect(cards.take(3).every((c) => c.cols == 3), true);
          final positions = [
            for (var i = 0; i < 3; i++)
              t.getRect(find.byType(GranthCard).at(i)),
          ];
          expect((positions[0].top - positions[2].top).abs(), lessThan(1));
          expect(positions[1].left, greaterThan(positions[0].right));
          expect(positions[2].left, greaterThan(positions[1].right));
        }
        final cropY = ((t.getTopLeft(first).dy - 66).clamp(0, 700) * 2).round();
        // End: below the last folder row (full folder screen) / above the floating AI button.
        final fab = find.byKey(const ValueKey('ask-ai-fab'));
        final fabTop = fab.evaluate().isEmpty ? double.infinity : t.getTopLeft(fab).dy - 8;
        double endDy;
        if (mode == 'folders') {
          final rows = find.byType(FolderRow);
          endDy = t.getBottomLeft(rows.last).dy + 14;
          expect(endDy, lessThan(fabTop), reason: 'whole folder screen must fit above the AI button');
        } else {
          final cards = find.byType(GranthCard);
          endDy = t.getBottomLeft(cards.at(2)).dy + 14;
          if (endDy > fabTop) endDy = fabTop;
        }
        final cropEnd = (endDy * 2).round();
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
              (cropEnd - cropY).toDouble(),
            ),
            Rect.fromLTWH(
              0,
              0,
              full.width.toDouble(),
              (cropEnd - cropY).toDouble(),
            ),
            Paint(),
          );
          final picture = recorder.endRecording();
          final image = await picture.toImage(full.width, cropEnd - cropY);
          // ignore: avoid_print
          print('CAPTURE $mode ${full.width}x${cropEnd - cropY}');
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
