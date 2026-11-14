// t408 — "ग्रंथ कार्ड PDF" for a whole granth: every praman as its in-app card (one card per
// page), with the cover and the विषय सूची, from the same picker as the हाईलाइट PDF, for one
// granth and for "Multiple granth PDF". Sample → /workspace/ui-ref/out/v2/cardpdf_sample.pdf
// when CAPTURE_UI=1.
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:granthprabandhan/models/models.dart';
import 'package:granthprabandhan/services/catalog_store.dart';
import 'package:granthprabandhan/services/pdf_builder.dart';
import 'package:granthprabandhan/services/pdf_queue.dart';
import 'package:granthprabandhan/state/ui_prefs.dart';
import 'package:granthprabandhan/widgets/pdf_sheets.dart';
import 'package:granthprabandhan/widgets/praman_card_pdf.dart';

import 'helpers.dart';
import 'no_blank_pages_test.dart' show pdfPages;
import 'pdf_render_test.dart' show loadFonts;

final _capture = Platform.environment['CAPTURE_UI'] == '1';
const _fx = 'test/fixtures/granth_examples';

Praman _praman(int i, {String granthId = 'gita', String image = ''}) => Praman({
      'id': '$granthId-$i',
      'title': 'गीता अध्याय ${(i - 1) ~/ 4 + 1} · श्लोक ${i * 3}',
      'description': 'प्रमाण $i: शास्त्र का यह श्लोक पूर्ण परमात्मा की भक्ति के बारे में बताता है।',
      'topic_id': 't${i % 3}',
      'topic_title': ['पूर्ण परमात्मा', 'तत्वदर्शी संत', 'सत भक्ति'][i % 3],
      'granth_id': granthId,
      'granth_title': 'श्रीमद्भगवद्गीता',
      'image_path': image,
      'position': '$i',
    });

/// The job was started inside the test's fake clock (a tap), so its timers move only with
/// pump(); its real work (isolates, image codecs) needs real time — alternate the two.
Future<void> _waitDone(WidgetTester t, List<PdfJob> jobs) async {
  for (var i = 0; i < 4000 && jobs.any((j) => j.active); i++) {
    await t.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 5)));
    await t.pump(const Duration(milliseconds: 20));
  }
}

void main() {
  setUp(() async {
    await setUpApp();
    PramanCardPdf.register();
  });

  testWidgets('52 praman pictures → 52 card pages (+ cover + विषय सूची), each the in-app card', (t) async {
    await t.runAsync(loadFonts);
    final pics = ['$_fx/praman_69bbba95277ff.jpg', '$_fx/praman_6a4bdae79caa5.jpg', '$_fx/praman_69bbc71e21216.webp'];
    const n = 52;
    final specs = [
      PdfSpec(title: 'श्रीमद्भगवद्गीता', subtitle: 'वेद व्यास', body: 'श्रीमद्भगवद्गीता — 52 प्रमाण', cover: true),
      for (var i = 1; i <= n; i++) PdfQueue.pramanSpec(_praman(i), i, n)..file = pics[i % pics.length],
    ];
    final b = BookPdfBuilder(contents: true);
    final pdf = await t.runAsync(() => b.build(specs, PdfStyle.card));
    final toc = tocPageCount(n);
    expect(b.cardPages, n, reason: 'one card page per praman');
    expect(pdfPages(pdf!), 1 + toc + n);
    expect(b.contentsRows, hasLength(n));
    expect(b.contentsRows.first.page, 1 + toc + 1);
    expect(b.contentsRows.last.page, 1 + toc + n);
    if (_capture) File('/workspace/ui-ref/out/v2/cardpdf_sample.pdf').writeAsBytesSync(pdf);
  });

  testWidgets('the card itself: the PramanCard widget with its picture, no on-screen buttons', (t) async {
    await t.runAsync(loadFonts);
    final spec = PdfQueue.pramanSpec(_praman(1), 1, 52)..file = '$_fx/praman_69bbba95277ff.jpg';
    final r = await t.runAsync(() => PramanCardPdf.render(spec));
    expect(r, isNotNull);
    expect(r!.width, closeTo(PramanCardPdf.cardWidth + PramanCardPdf.pad * 2, 0.5));
    expect(r.height, inInclusiveRange(300, 3000), reason: 'title, text and the picture; the card own height');
    expect(r.w, (r.width * PramanCardPdf.ratio).round());
  });

  Future<void> boot(WidgetTester t, PdfRequest Function() req) async {
    final granths = [
      Granth({'id': 'gita', 'title': 'श्रीमद्भगवद्गीता', 'position': '1'}),
      Granth({'id': 'ved', 'title': 'यजुर्वेद', 'position': '2'}),
    ];
    final pramans = [for (var i = 1; i <= 12; i++) _praman(i), for (var i = 1; i <= 5; i++) _praman(i, granthId: 'ved')];
    CatalogStore.I.debugSetCatalog(Catalog(topics: [], granths: granths, pramans: pramans));
    PdfQueue.I.debugReset();
    PdfQueue.I.freeBytes = () async => 1 << 40;
    addTearDown(PdfQueue.I.debugReset);
    UiPrefs.I.animations = false;
    await t.runAsync(loadFonts);
    await t.pumpWidget(MaterialApp(
      home: Scaffold(body: Builder(builder: (context) => Center(child: TextButton(key: const ValueKey('go'), onPressed: () => askPdf(context, req()), child: const Text('PDF'))))),
    ));
    await t.tap(find.byKey(const ValueKey('go')));
    await t.pumpAndSettle();
    expect(find.text('PDF शैली'), findsOneWidget, reason: 'the same style sheet as the हाईलाइट PDF');
    await t.tap(find.byKey(const ValueKey('granth-card-pdf-option')));
    await t.pump(const Duration(milliseconds: 300));
    await t.tap(find.text('OK'));
    await t.pump(const Duration(milliseconds: 300));
  }

  testWidgets('one granth: picker → card option → queued like the हाईलाइट PDF, all cards in it', (t) async {
    final before = UiPrefs.I.pdfStyle;
    await boot(t, () => GranthPdfRequest(CatalogStore.I.granths.first));
    final jobs = PdfQueue.I.jobs.toList();
    expect(jobs, hasLength(1));
    await _waitDone(t, jobs);
    final j = jobs.single;
    expect(j.phase, PdfPhase.done, reason: j.error);
    expect(j.fileName, endsWith('कार्ड.pdf'));
    expect(j.galleryId, 'pdf-card-gita');
    final pages = pdfPages(File(j.filePath!).readAsBytesSync());
    expect(pages, 1 + tocPageCount(12) + 12, reason: 'cover + विषय सूची + 12 cards');
    expect(UiPrefs.I.pdfStyle, before, reason: 'card is not saved as the default style');
    await t.pumpWidget(const SizedBox());
    await t.pump(const Duration(seconds: 1));
  });

  testWidgets('Multiple granth PDF offers the card PDF too: one card PDF per granth', (t) async {
    await boot(t, () => MultiGranthPdfRequest(CatalogStore.I.granths));
    final jobs = PdfQueue.I.jobs.toList();
    expect(jobs, hasLength(2));
    await _waitDone(t, jobs);
    final counts = {'pdf-card-gita': 12, 'pdf-card-ved': 5};
    for (final j in jobs) {
      expect(j.phase, PdfPhase.done, reason: j.error);
      expect(j.fileName, endsWith('कार्ड.pdf'));
      final n = counts[j.galleryId]!;
      expect(pdfPages(File(j.filePath!).readAsBytesSync()), 1 + tocPageCount(n) + n);
    }
    await t.pumpWidget(const SizedBox());
    await t.pump(const Duration(seconds: 1));
  });
}
