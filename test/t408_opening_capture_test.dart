// t408: records the opening (Flutter part: AnimatedSplash → Granth tab) frame by frame for
// opening.mp4. Frames → /workspace/ui-ref/out/v2/opening_frames/ only when CAPTURE_UI=1;
// otherwise it just checks the opening still hands over to the app.
import 'dart:convert';
import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:granthprabandhan/main.dart';
import 'package:granthprabandhan/models/models.dart';
import 'package:granthprabandhan/screens/shelves_screen.dart';
import 'package:granthprabandhan/screens/splash_screen.dart';
import 'package:granthprabandhan/services/catalog_store.dart';
import 'package:granthprabandhan/services/storage.dart';
import 'package:granthprabandhan/state/router.dart';
import 'package:granthprabandhan/state/ui_prefs.dart';

import 'helpers.dart';
import 'pdf_render_test.dart' show loadFonts;

final _capture = Platform.environment['CAPTURE_UI'] == '1';
const _dir = '/workspace/ui-ref/out/v2/opening_frames';

void main() {
  setUp(() async {
    await setUpApp();
    await Store.I.setString(granthViewKey, 'folders');
    UiPrefs.I.taskbar = true;
    UiPrefs.I.setCols(Store.kGranthCols, 3);
    final raw = (jsonDecode(File('test/fixtures/granth_examples/catalog.json').readAsStringSync()) as List).cast<Map<String, dynamic>>();
    CatalogStore.I.debugSetCatalog(Catalog(topics: [], granths: raw.map(Granth.new).toList(), pramans: []));
  });

  testWidgets('opening: splash animation, then the Granth tab', (t) async {
    await t.runAsync(loadFonts);
    await t.binding.setSurfaceSize(const Size(411, 891));
    addTearDown(() => t.binding.setSurfaceSize(null));
    AppNav.I.go('#/granths');
    final key = GlobalKey();
    if (_capture) {
      final d = Directory(_dir);
      if (d.existsSync()) d.deleteSync(recursive: true);
      d.createSync(recursive: true);
    }
    await t.pumpWidget(RepaintBoundary(key: key, child: const GranthApp(links: false)));
    expect(find.byKey(AnimatedSplash.overlayKey), findsOneWidget);
    const fps = 30;
    for (var i = 0; i < fps * 4.4; i++) {
      await t.pump(const Duration(microseconds: 1000000 ~/ fps));
      if (!_capture) continue;
      await t.runAsync(() async {
        final img = await (key.currentContext!.findRenderObject() as RenderRepaintBoundary).toImage(pixelRatio: 2);
        final data = await img.toByteData(format: ui.ImageByteFormat.png);
        File('$_dir/f${i.toString().padLeft(4, '0')}.png').writeAsBytesSync(data!.buffer.asUint8List());
        img.dispose();
      });
    }
    expect(find.byKey(AnimatedSplash.overlayKey), findsNothing);
    expect(find.text('Granths'), findsOneWidget);
    await t.pumpWidget(const SizedBox());
    await t.pump(const Duration(seconds: 4));
  });
}
