// t365 / t370: the granth PDF has a विषय सूची (contents) with page numbers, topic and description;
// "ग्रंथ कार्ड PDF" works for every granth — a tall card (पुराण, वेद … with long descriptions) is
// captured in strips (one GPU picture is limited to ~4096 px) and made like every other PDF.
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:granthprabandhan/services/card_pdf.dart';
import 'package:granthprabandhan/services/catalog_store.dart';
import 'package:granthprabandhan/services/pdf_builder.dart';
import 'package:granthprabandhan/services/pdf_queue.dart';
import 'package:granthprabandhan/services/storage.dart';

import 'helpers.dart';
import 'no_blank_pages_test.dart' show pdfPages;
import 'pdf_render_test.dart' show loadFonts;

List<int> kids(String pdf) {
  final m = RegExp(r'/Kids \[([^\]]*)\]').firstMatch(pdf)!;
  return [for (final x in RegExp(r'(\d+) 0 R').allMatches(m.group(1)!)) int.parse(x.group(1)!)];
}

void main() {
  setUp(setUpApp);

  testWidgets('विषय सूची: after the cover, one row per praman with topic, description and its page', (t) async {
    await t.runAsync(loadFonts);
    final specs = [
      PdfSpec(title: 'वेद', subtitle: 'लेखक', body: 'वेद ग्रंथ', cover: true),
      for (var i = 0; i < 40; i++) PdfSpec(title: 'प्रमाण ${i + 1}', subtitle: 'विषय ${i % 3}', body: 'विवरण ${i + 1}'),
    ];
    final b = BookPdfBuilder(contents: true);
    final pdf = await t.runAsync(() => b.build(specs, PdfStyle.fill90));
    final toc = tocPageCount(40);
    expect(toc, greaterThanOrEqualTo(2));
    expect(pdfPages(pdf!), 1 + toc + 40);
    expect(b.contentsRows, hasLength(40));
    expect(b.contentsRows.first.page, 1 + toc + 1);
    expect(b.contentsRows.first.topic, 'विषय 0');
    expect(b.contentsRows.first.description, 'विवरण 1');
    for (var i = 1; i < 40; i++) {
      expect(b.contentsRows[i].page, b.contentsRows[i - 1].page + 1);
    }
    // The contents pages are written last but sit right after the cover.
    final k = kids(String.fromCharCodes(pdf));
    final last = [...k]..sort();
    expect(k.sublist(1, 1 + toc), last.sublist(last.length - toc));
  });

  testWidgets('no विषय सूची in "केवल चित्र" or when not asked', (t) async {
    await t.runAsync(loadFonts);
    final specs = [for (var i = 0; i < 3; i++) PdfSpec(title: 'प्रमाण $i', body: 'x')];
    final a = BookPdfBuilder();
    final p = await t.runAsync(() => a.build(specs, PdfStyle.fill90));
    expect(pdfPages(p!), 3);
    expect(a.contentsRows, isEmpty);
  });

  testWidgets('a very tall card (taller than one GPU picture) still gives a card PDF', (t) async {
    final key = GlobalKey();
    await t.binding.setSurfaceSize(const Size(320, 640));
    addTearDown(() => t.binding.setSurfaceSize(null));
    await t.pumpWidget(MaterialApp(
      home: SingleChildScrollView(
        child: RepaintBoundary(
          key: key,
          child: Container(width: 320, height: 5200, decoration: const BoxDecoration(gradient: LinearGradient(colors: [Colors.white, Colors.brown], begin: Alignment.topCenter, end: Alignment.bottomCenter))),
        ),
      ),
    ));
    await t.pumpAndSettle();
    final shot = await t.runAsync(() => CardPdf.capture(key, pixelRatio: 3));
    expect(shot, isNotNull);
    expect(shot!.strips.length, greaterThan(1), reason: '15600 px tall: taken in strips');
    for (final s in shot.strips) {
      expect(s.h, lessThanOrEqualTo(CardPdf.maxStripPx));
    }
    final file = await t.runAsync(() => CardPdf.build(key, 'tall.pdf', pixelRatio: 3, dir: Store.I.root));
    final text = String.fromCharCodes(file!.readAsBytesSync());
    expect(text.startsWith('%PDF-'), isTrue);
    expect(RegExp(r'/Subtype /Image').allMatches(text).length, shot.strips.length);
    final box = RegExp(r'/MediaBox \[0 0 ([\d.]+) ([\d.]+)\]').firstMatch(text)!;
    expect(double.parse(box.group(2)!), lessThanOrEqualTo(CardPdf.maxPagePt));
  });

  testWidgets('ग्रंथ कार्ड PDF goes through the normal PDF flow (progress row → done)', (t) async {
    final key = GlobalKey();
    await t.pumpWidget(MaterialApp(home: Center(child: RepaintBoundary(key: key, child: const SizedBox(width: 200, height: 300, child: ColoredBox(color: Colors.orange))))));
    await t.pumpAndSettle();
    final shot = await t.runAsync(() => CardPdf.capture(key));
    PdfQueue.I.debugReset();
    PdfQueue.I.freeBytes = () async => 1 << 40;
    addTearDown(PdfQueue.I.debugReset);
    final g = CatalogStore.I.granths.first;
    final job = (await t.runAsync(() async => PdfQueue.I.cardPdf(g, shot!)))!;
    expect(PdfQueue.I.jobs.first, same(job));
    await t.runAsync(() async {
      for (var i = 0; i < 1500 && job.active; i++) {
        await Future<void>.delayed(const Duration(milliseconds: 20));
      }
    });
    expect(job.phase, PdfPhase.done, reason: job.error);
    expect(job.percent, 100);
    expect(File(job.filePath!).existsSync(), isTrue);
    expect(job.fileName, endsWith('कार्ड.pdf'));
  });
}
