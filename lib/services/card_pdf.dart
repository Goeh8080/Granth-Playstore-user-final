/// "Card PDF" (round 14): the card exactly as it looks in the app — the widget under a
/// [RepaintBoundary] is drawn to a picture, put on a white page and written as a one-page PDF
/// with the app's own PDF writer. Everything stays on the phone (PDF folder → share / save).
library;

import 'dart:io';
import 'dart:math' as math;
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter/foundation.dart' show compute;

import 'package:flutter/rendering.dart';
import 'package:flutter/scheduler.dart';
import 'package:flutter/widgets.dart';

import 'file_actions.dart';
import 'pdf_stream.dart';
import 'storage.dart';

/// A captured card: white-backed RGBA strips (top to bottom) and the pixel ratio they were
/// drawn at. A tall card is taken in strips: one GPU picture can be at most ~4096 px on many
/// phones, so a long 1×1 card (पुराण / वेद granths with long descriptions) failed as one picture.
typedef CardStrip = ({Uint8List rgba, int w, int h});
typedef CardShot = ({List<CardStrip> strips, double ratio, double width, double height});

class CardPdf {
  /// Page margin around the card, in PDF points.
  static const double margin = 18;

  /// Tallest strip (physical pixels) taken in one go — safe on every phone GPU.
  static const int maxStripPx = 4096;

  /// Largest PDF page side in points (Acrobat's limit is 14400); taller cards are scaled down.
  static const double maxPagePt = 14400;

  /// Draws the boundary under [key] and writes `<dir>/<name>` (default: the app's PDF folder,
  /// overwriting an older card of the same name so save/share never pick up a stale file).
  /// Returns the file, or null when the card is not on screen. Encoding + compression run on a
  /// background isolate (no UI jank); the picture is lossless at ≥3× (the device's own ratio
  /// when higher), bounded to keep memory sane.
  static Future<File?> build(GlobalKey key, String name, {double? pixelRatio, Directory? dir}) async {
    final shot = await capture(key, pixelRatio: pixelRatio);
    if (shot == null) return null;
    final out = dir ?? Directory(Store.I.pdfDir);
    if (!await out.exists()) await out.create(recursive: true);
    final f = File('${out.path}/${FileActions.safeName(name)}');
    await write(shot, f.path);
    return f;
  }

  /// The card under [key] as white-backed RGBA strips, or null when it is not on screen.
  static Future<CardShot?> capture(GlobalKey key, {double? pixelRatio}) async {
    final ctx = key.currentContext;
    final ro = ctx?.findRenderObject();
    if (ro is! RenderRepaintBoundary || !ro.hasSize || !ro.attached) return null;
    // A frame may still be pending (popup closing, image fade): paint it first.
    if (SchedulerBinding.instance.hasScheduledFrame) await WidgetsBinding.instance.endOfFrame;
    if (!ro.attached) return null;
    final dpr = ctx != null && ctx.mounted ? (MediaQuery.maybeDevicePixelRatioOf(ctx) ?? 3.0) : 3.0;
    var ratio = pixelRatio ?? (dpr > 3 ? dpr : 3.0);
    final size = ro.size;
    final area = size.width * size.height;
    if (area > 0 && area * ratio * ratio > maxPixels) ratio = math.sqrt(maxPixels / area);
    // Never wider than one strip either.
    if (size.width * ratio > maxStripPx) ratio = maxStripPx / size.width;
    // The boundary's own layer, as RenderRepaintBoundary.toImage uses it — but a strip at a time.
    // ignore: invalid_use_of_protected_member
    final layer = ro.layer;
    if (layer is! OffsetLayer) return null;
    final stripH = maxStripPx / ratio; // logical height of one strip
    final strips = <CardStrip>[];
    for (var top = 0.0; top < size.height - 0.01; top += stripH) {
      final h = math.min(stripH, size.height - top);
      final shot = await layer.toImage(Rect.fromLTWH(0, top, size.width, h), pixelRatio: ratio);
      final w = shot.width, ph = shot.height;
      // Flatten onto white (the card's rounded corners are transparent).
      final rec = ui.PictureRecorder();
      final canvas = Canvas(rec);
      canvas.drawRect(Rect.fromLTWH(0, 0, w.toDouble(), ph.toDouble()), Paint()..color = const Color(0xFFFFFFFF));
      canvas.drawImage(shot, Offset.zero, Paint());
      final pic = rec.endRecording();
      final flat = await pic.toImage(w, ph);
      pic.dispose();
      shot.dispose();
      final data = await flat.toByteData(format: ui.ImageByteFormat.rawRgba);
      flat.dispose();
      if (data == null) return null;
      strips.add((rgba: data.buffer.asUint8List(), w: w, h: ph));
    }
    if (strips.isEmpty) return null;
    return (strips: strips, ratio: ratio, width: size.width, height: size.height);
  }

  /// Writes a captured card as a one-page PDF at [path] (background isolate).
  static Future<void> write(CardShot shot, String path) => compute(_write, (path: path, shot: shot));

  /// Largest card picture (pixels) — keeps a very long 1×1 card within memory.
  static const int maxPixels = 24000000;

  static void _write(({String path, CardShot shot}) a) {
    final shot = a.shot;
    // 1 logical pixel = 1 pt, so the card prints at its on-screen size (scaled down only when
    // the page would be taller than a PDF page may be).
    final k = math.min(1.0, maxPagePt / (shot.height + margin * 2));
    final cw = shot.width * k, ch = shot.height * k, m = margin * k;
    final page = PdfPageData(cw + m * 2, ch + m * 2);
    page.ops.add(PdfOp.fill(0, 0, page.w, page.h, 1, 1, 1));
    var top = 0.0; // from the card's top, in points
    for (final st in shot.strips) {
      final h = st.h / shot.ratio * k;
      final i = page.addPicture(PdfPicture.rgba(st.rgba, st.w, st.h));
      page.ops.add(PdfOp.image(i, m, m + ch - top - h, cw, h));
      top += h;
    }
    final part = '${a.path}.part';
    final pdf = PdfStreamWriter(part);
    try {
      pdf.addPage(page);
      pdf.close();
    } catch (_) {
      pdf.abort();
      try {
        File(part).deleteSync();
      } catch (_) {}
      rethrow;
    }
    File(part).renameSync(a.path);
  }

  static String fileName(String title) {
    final t = title.replaceAll(RegExp(r'[\\/:*?"<>|\n\r\t]+'), ' ').trim();
    final short = t.runes.length > 40 ? String.fromCharCodes(t.runes.take(40)).trim() : t;
    // Own suffix: never the same name as the granth's हाईलाइट PDF in the PDF folder.
    return '${short.isEmpty ? 'card' : short} - कार्ड.pdf';
  }

  static Future<void> share(File f) => FileActions.shareFile(f.path, f.uri.pathSegments.last);
  static Future<bool> save(File f) => FileActions.exportToDevice(f.path, f.uri.pathSegments.last);
}
