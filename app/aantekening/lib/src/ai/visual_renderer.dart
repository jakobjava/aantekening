/// Drawing what is on a page as a picture for a model to look at.
library;

import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:aantekening_ai/aantekening_ai.dart';
import 'package:aantekening_canvas/aantekening_canvas.dart';
import 'package:aantekening_core/aantekening_core.dart';
import 'package:aantekening_store/aantekening_store.dart';
import 'package:flutter/painting.dart';
import 'package:pdfrx/pdfrx.dart';

import '../editor/media_views.dart';
import 'offscreen_text.dart';

/// Draws a page's visuals (see [DigestVisual]) as PNG pictures: a PDF page
/// with the writing over it, a drawing, a picture — as the page shows them.
///
/// The same visual of the same version of a page is drawn once.
class VisualRenderer {
  VisualRenderer(this.store);

  final AantekeningStore store;

  /// The longest side of a picture, in pixels: enough to read handwriting,
  /// and no more than models take in at full detail.
  static const int maxSide = 1568;

  /// Room round a region, in page units, so writing at its edge is not cut.
  static const double _margin = 12;

  final Map<String, ImagePart> _drawn = <String, ImagePart>{};

  /// [visual] of [document], at [revision], or null if it cannot be drawn.
  Future<ImagePart?> render(
    PageDocument document,
    DigestVisual visual, {
    required int revision,
  }) async {
    final key = '${document.id}/${visual.id}/$revision';
    final kept = _drawn[key];
    if (kept != null) return kept;
    final image = visual.bounds == null
        ? await _asset(visual)
        : await _region(document, visual, visual.bounds!);
    if (image == null) return null;
    if (_drawn.length > 64) _drawn.remove(_drawn.keys.first);
    return _drawn[key] = image;
  }

  /// A region of the page, with what [visual] shows in it drawn as the
  /// canvas draws it: the sheets — pictures and PDF pages, the background's
  /// first — and the printouts in text boxes, then highlighter ink, the
  /// typed text, and pen ink over it all. A worksheet comes out as it is on
  /// the page: the sheet, with what was written and typed on it where it
  /// was.
  Future<ImagePart?> _region(
    PageDocument document,
    DigestVisual visual,
    Aabb bounds,
  ) async {
    final region = Rect.fromLTRB(
      bounds.left - _margin,
      bounds.top - _margin,
      bounds.right + _margin,
      bounds.bottom + _margin,
    );
    final scale = math.min(
      2.0,
      maxSide / math.max(region.width, region.height),
    );
    final size = region.size * scale;

    final elements = <NoteElement>[
      for (final id in visual.elementIds) ?document.elementById(id),
    ]..sort((a, b) => a.z.compareTo(b.z));
    final ink = elements.whereType<InkElement>().toList();
    final boxes = elements.whereType<TextElement>().toList();
    final media = <(NoteElement, ui.Image)>[];
    for (final element in elements) {
      final image = await _mediaOf(
        element,
        (element.frame.width * scale).round(),
      );
      if (image != null) media.add((element, image));
    }
    final text = boxes.isEmpty
        ? null
        : await drawTextBoxes(boxes, region: region, scale: scale);
    final objects = <(Rect, ui.Image)>[
      for (final (embed, rect) in text?.objects ?? const <(BlockEmbed, Rect)>[])
        if (await _embedImage(embed, (rect.width * scale).round())
            case final image?)
          (rect, image),
    ];

    final recorder = ui.PictureRecorder();
    final canvas = Canvas(recorder)
      ..drawRect(Offset.zero & size, Paint()..color = const Color(0xFFFFFFFF));
    final viewport = CanvasViewport(origin: region.topLeft, zoom: scale);
    void drawImage(ui.Image image, Rect rect, [double rotation = 0]) => canvas
      ..save()
      ..translate(rect.center.dx, rect.center.dy)
      ..rotate(rotation)
      ..translate(-rect.center.dx, -rect.center.dy)
      ..drawImageRect(
        image,
        Offset.zero & Size(image.width.toDouble(), image.height.toDouble()),
        rect,
        Paint()..filterQuality = FilterQuality.medium,
      )
      ..restore();
    Rect onImage(Rect page) => Rect.fromLTWH(
      (page.left - region.left) * scale,
      (page.top - region.top) * scale,
      page.width * scale,
      page.height * scale,
    );

    for (final locked in <bool>[true, false]) {
      for (final (element, image) in media) {
        if (element.locked != locked) continue;
        final frame = element.frame;
        drawImage(
          image,
          onImage(Rect.fromLTWH(frame.x, frame.y, frame.width, frame.height)),
          frame.rotation,
        );
      }
    }
    for (final (rect, image) in objects) {
      drawImage(
        image,
        Rect.fromLTWH(
          rect.left * scale,
          rect.top * scale,
          rect.width * scale,
          rect.height * scale,
        ),
      );
    }
    InkPainter(
      elements: ink,
      viewport: viewport,
      layer: InkLayer.beneath,
    ).paint(canvas, size);
    if (text != null) canvas.drawImage(text.image, Offset.zero, Paint());
    InkPainter(
      elements: ink,
      viewport: viewport,
      layer: InkLayer.above,
    ).paint(canvas, size);

    final picture = recorder.endRecording();
    try {
      final image = await picture.toImage(
        size.width.ceil(),
        size.height.ceil(),
      );
      return await _png(image, visual.description);
    } finally {
      picture.dispose();
      text?.image.dispose();
      for (final (_, image) in media) {
        image.dispose();
      }
      for (final (_, image) in objects) {
        image.dispose();
      }
    }
  }

  /// The picture or PDF page [embed] shows, [pixelWidth] wide.
  Future<ui.Image?> _embedImage(BlockEmbed embed, int pixelWidth) =>
      switch (embed.kind) {
        EmbedKind.image => _picture(embed.assetId, pixelWidth),
        EmbedKind.pdfPage => _pdfPage(
          embed.assetId,
          embed.pageIndex,
          pixelWidth,
        ),
      };

  /// A picture or PDF page in a text box, drawn alone.
  Future<ImagePart?> _asset(DigestVisual visual) async {
    final assetId = visual.assetId;
    if (assetId == null) return null;
    final image = visual.pdfPageIndex != null
        ? await _pdfPage(assetId, visual.pdfPageIndex!, maxSide)
        : await _picture(assetId, maxSide);
    return image == null ? null : _png(image, visual.description);
  }

  Future<ui.Image?> _mediaOf(NoteElement element, int pixelWidth) =>
      switch (element) {
        ImageElement(:final assetId) => _picture(assetId, pixelWidth),
        PdfElement(:final assetId, :final pageIndex) => _pdfPage(
          assetId,
          pageIndex,
          pixelWidth,
        ),
        _ => Future<ui.Image?>.value(),
      };

  Future<ui.Image?> _picture(String assetId, int pixelWidth) async {
    final bytes = await store.assets.readBytes(assetId);
    if (bytes == null) return null;
    try {
      final codec = await ui.instantiateImageCodec(
        bytes,
        targetWidth: math.min(pixelWidth, maxSide),
      );
      final frame = await codec.getNextFrame();
      codec.dispose();
      return frame.image;
    } on Object {
      return null;
    }
  }

  Future<ui.Image?> _pdfPage(
    String assetId,
    int pageIndex,
    int pixelWidth,
  ) async {
    final asset = await store.assets.find(assetId);
    if (asset == null) return null;
    final file = store.assets.fileFor(asset);
    if (!file.existsSync()) return null;
    await pdfrxFlutterInitialize();
    final document = await PdfDocument.openFile(file.path);
    try {
      return await renderPdfPage(
        document,
        pageIndex,
        math.min(pixelWidth, maxSide),
      );
    } finally {
      await document.dispose();
    }
  }

  static Future<ImagePart?> _png(ui.Image image, String label) async {
    try {
      final data = await image.toByteData(format: ui.ImageByteFormat.png);
      return data == null
          ? null
          : ImagePart(
              data.buffer.asUint8List(),
              mediaType: 'image/png',
              label: label,
            );
    } finally {
      image.dispose();
    }
  }
}
