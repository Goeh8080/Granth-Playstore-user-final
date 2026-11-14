/// t408 — "ग्रंथ कार्ड PDF": each praman drawn as its in-app [PramanCard] (same widget, same
/// card look, its pictures decoded first) off screen, for [PdfStyle.card] pages.
library;

import 'dart:io';
import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';

import '../models/models.dart';
import '../screens/pramans_screen.dart';
import '../services/api.dart' show mediaPath;
import '../services/image_cache.dart';
import '../services/pdf_builder.dart';
import '../state/ui_prefs.dart';
import '../theme/colors.dart';

class PramanCardPdf {
  /// The card is laid out at a phone's width (logical px) and drawn at [ratio]×.
  static const double cardWidth = 380;
  static const double ratio = 2.5;

  /// Room around the card so its shadow is on the page too.
  static const double pad = 6;

  static void register() => BookPdfBuilder.cardRenderer ??= render;

  static Future<ui.Image?> _decode(String? file, double width) async {
    if (file == null) return null;
    try {
      final f = File(file);
      if (!await f.exists()) return null;
      final bytes = await f.readAsBytes();
      final buf = await ui.ImmutableBuffer.fromUint8List(bytes);
      final desc = await ui.ImageDescriptor.encoded(buf);
      final w = math.min(desc.width, (width * ratio).round());
      final codec = await desc.instantiateCodec(targetWidth: w);
      final frame = await codec.getNextFrame();
      codec.dispose();
      desc.dispose();
      buf.dispose();
      return frame.image;
    } catch (_) {
      return null;
    }
  }

  static Future<String?> _fileOf(String? path) async {
    final p = mediaPath(path);
    if (p == null) return null;
    final f = ImageStore.I.cachedSync(p) ?? await ImageStore.I.get(p, priority: true);
    return f?.path;
  }

  /// Draws [spec]'s praman as its card (null when [PdfSpec.source] is not a praman).
  static Future<CardRaster?> render(PdfSpec spec) async {
    final p = spec.source;
    if (p is! Praman) return null;
    final proof = await _decode(spec.file ?? await _fileOf(p.imagePath), cardWidth);
    if (mediaPath(p.imagePath) != null && proof == null) return null; // never a card without its picture
    final granth = await _decode(await _fileOf(p.granthImage), 52);
    final editor = await _decode(await _fileOf(p.editorImagePath), 52);
    try {
      final card = PramanCard(
        praman: p,
        index: spec.index,
        total: spec.total,
        pictures: PramanCardPictures(proof: proof, granth: granth, editor: editor),
      );
      final image = await renderOffscreen(
        Container(color: GColors.cream, padding: const EdgeInsets.all(pad), child: card),
        width: cardWidth + pad * 2,
        pixelRatio: ratio,
      );
      final data = await image.toByteData(format: ui.ImageByteFormat.rawRgba);
      final w = image.width, h = image.height;
      image.dispose();
      if (data == null) return null;
      return (rgba: data.buffer.asUint8List(), w: w, h: h, width: w / ratio, height: h / ratio);
    } finally {
      proof?.dispose();
      granth?.dispose();
      editor?.dispose();
    }
  }
}

/// Lays [child] out at [width] (height: its own) in a separate pipeline — not on screen — and
/// returns the picture. Everything must be ready in one frame (no async images).
Future<ui.Image> renderOffscreen(Widget child, {required double width, double pixelRatio = 2, double maxHeight = 12000}) async {
  final view = WidgetsBinding.instance.platformDispatcher.views.first;
  final boundary = RenderRepaintBoundary();
  final renderView = RenderView(
    view: view,
    child: RenderPositionedBox(alignment: Alignment.topLeft, child: boundary),
    configuration: ViewConfiguration(logicalConstraints: BoxConstraints.tight(Size(width, maxHeight)), devicePixelRatio: pixelRatio),
  );
  final pipeline = PipelineOwner()..rootNode = renderView;
  renderView.prepareInitialFrame();
  final build = BuildOwner(focusManager: FocusManager(), onBuildScheduled: () {});
  final tree = MediaQuery(
    data: MediaQueryData(size: Size(width, maxHeight), devicePixelRatio: pixelRatio, disableAnimations: true),
    child: Theme(
      data: buildTheme(ios: UiPrefs.I.theme == 'ios'),
      child: Directionality(
        textDirection: TextDirection.ltr,
        // unbounded height, like a card in the app's scrolling list
        child: Material(type: MaterialType.transparency, child: UnconstrainedBox(constrainedAxis: Axis.horizontal, alignment: Alignment.topLeft, child: SizedBox(width: width, child: child))),
      ),
    ),
  );
  final adapter = RenderObjectToWidgetAdapter<RenderBox>(container: boundary, child: tree);
  final root = adapter.attachToRenderTree(build);
  try {
    build.buildScope(root);
    build.finalizeTree();
    pipeline.flushLayout();
    pipeline.flushCompositingBits();
    pipeline.flushPaint();
    final h = boundary.size.height;
    // ignore: invalid_use_of_protected_member
    final layer = boundary.layer! as OffsetLayer;
    return await layer.toImage(Rect.fromLTWH(0, 0, width, math.min(h, maxHeight)), pixelRatio: pixelRatio);
  } finally {
    // Unmount (listeners off, tickers disposed).
    RenderObjectToWidgetAdapter<RenderBox>(container: boundary, child: const SizedBox.shrink()).attachToRenderTree(build, root);
    build.buildScope(root);
    build.finalizeTree();
  }
}

