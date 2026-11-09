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

class CardPdf {
  /// Page margin around the card, in PDF points.
  static const double margin = 18;

  /// Draws the boundary under [key] and writes `<dir>/<name>` (default: the app's PDF folder,
  /// overwriting an older card of the same name so save/share never pick up a stale file).
  /// Returns the file, or null when the card is not on screen. Encoding + compression run on a
  /// background isolate (no UI jank); the picture is lossless at ≥3× (the device's own ratio
  /// when higher), bounded to keep memory sane.
  static Future<File?> build(GlobalKey key, String name, {double? pixelRatio, Directory? dir}) async {
    final ctx = key.currentContext;
    final ro = ctx?.findRenderObject();
    if (ro is! RenderRepaintBoundary || !ro.hasSize || !ro.attached) return null;
    // A frame may still be pending (popup closing, image fade): paint it first.
    if (SchedulerBinding.instance.hasScheduledFrame) await WidgetsBinding.instance.endOfFrame;
    final dpr = ctx != null && ctx.mounted ? (MediaQuery.maybeDevicePixelRatioOf(ctx) ?? 3.0) : 3.0;
    var ratio = pixelRatio ?? (dpr > 3 ? dpr : 3.0);
    final area = ro.size.width * ro.size.height;
    if (area > 0 && area * ratio * ratio > maxPixels) ratio = math.sqrt(maxPixels / area);
    final shot = await ro.toImage(pixelRatio: ratio);
    final w = shot.width, h = shot.height;
    // Flatten onto white (the card's rounded corners are transparent).
    final rec = ui.PictureRecorder();
    final canvas = Canvas(rec);
    canvas.drawRect(Rect.fromLTWH(0, 0, w.toDouble(), h.toDouble()), Paint()..color = const Color(0xFFFFFFFF));
    canvas.drawImage(shot, Offset.zero, Paint());
    final pic = rec.endRecording();
    final flat = await pic.toImage(w, h);
    pic.dispose();
    shot.dispose();
    final data = await flat.toByteData(format: ui.ImageByteFormat.rawRgba);
    flat.dispose();
    if (data == null) return null;
    final out = dir ?? Directory(Store.I.pdfDir);
    if (!await out.exists()) await out.create(recursive: true);
    final f = File('${out.path}/${FileActions.safeName(name)}');
    await compute(_write, (path: f.path, rgba: data.buffer.asUint8List(), w: w, h: h, ratio: ratio));
    return f;
  }

  /// Largest card picture (pixels) — keeps a very long 1×1 card within memory.
  static const int maxPixels = 24000000;

  static void _write(({String path, Uint8List rgba, int w, int h, double ratio}) a) {
    // 1 logical pixel = 1 pt, so the card prints at its on-screen size.
    final cw = a.w / a.ratio, ch = a.h / a.ratio;
    final page = PdfPageData(cw + margin * 2, ch + margin * 2);
    page.ops.add(PdfOp.fill(0, 0, page.w, page.h, 1, 1, 1));
    final i = page.addPicture(PdfPicture.rgba(a.rgba, a.w, a.h));
    page.ops.add(PdfOp.image(i, margin, margin, cw, ch));
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
