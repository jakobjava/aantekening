/// Drawing a page as it is printed: on its paper, a sheet of it at a time.
library;

import 'dart:math' as math;
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:aantekening_canvas/aantekening_canvas.dart';
import 'package:aantekening_core/aantekening_core.dart';
import 'package:aantekening_store/aantekening_store.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/painting.dart';
import 'package:pdfrx/pdfrx.dart';

import '../ai/offscreen_text.dart';
import '../editor/media_views.dart';

/// A strip of a sheet of paper drawn as pixels: [width] by [height], four
/// bytes to a pixel as Flutter gives them, [top] pixels down the sheet.
typedef PrintedStrip = ({Uint8List rgba, int width, int height, int top});

/// Draws pages as they are printed: each element as the page shows it, on
/// the page's paper — its ruling, or each sheet's template — with what is
/// written and typed over the pictures and printouts, and ink over all.
///
/// The PDFs printouts come from are opened once for all the pages drawn,
/// and closed by [close].
class PagePrinter {
  PagePrinter(this.store);

  final AantekeningStore store;

  /// The most pixels down a picture drawn at once: a sheet taller is drawn
  /// in strips, each well within what a graphics card takes.
  static const int stripPixels = 4096;

  /// How many pixels to a page unit what is written on a page shown as one
  /// paper is looked at, to find where it can be cut: a pixel to a unit,
  /// for the gaps between lines to be seen.
  static const double _profileScale = 1;

  /// How much darker than white a point has to be to be written on: paper
  /// a shade off white is no writing.
  static const int _blank = 240;

  final Map<String, Future<PdfDocument?>> _pdfs =
      <String, Future<PdfDocument?>>{};

  /// How [document] is laid out on paper, with [header] at the top of it:
  /// its sheets, if it is shown as sheets; else cut onto sheets of A4
  /// where nothing is cut through, or on one long page, as [print] has it.
  Future<List<PrintedSheet>> layOut(
    PageDocument document, {
    CanvasHeader? header,
    CanvasPrint print = CanvasPrint.sheets,
  }) async {
    if (document.canvas.sheetsShown case final sheets?) {
      return PrintLayout.ofSheets(sheets);
    }
    return PrintLayout.ofCanvas(
      await profile(document, header: header),
      print: print,
    );
  }

  /// What is drawn on [document], with [header], row by row, as it is
  /// seen: drawn without its ruling, in strips, every point darker than
  /// white counted.
  Future<ContentProfile> profile(
    PageDocument document, {
    CanvasHeader? header,
  }) async {
    final bounds = header == null
        ? document.contentBounds
        : document.contentBounds.union(_bounds(header.frame));
    if (bounds.isEmpty) return ContentProfile.empty();
    // A page far wider than it is tall is looked at more coarsely across:
    // what is wanted is where its rows are blank.
    final scale = math.min(_profileScale, stripPixels / bounds.width);
    final width = (bounds.width * scale).ceil();
    final rows = (bounds.height * scale).ceil();
    final marked = Uint32List(rows);
    final left = Float64List(rows)..fillRange(0, rows, double.infinity);
    final right = Float64List(rows)
      ..fillRange(0, rows, double.negativeInfinity);
    for (var from = 0; from < rows; from += stripPixels) {
      final tall = math.min(stripPixels, rows - from);
      final region = Aabb(
        bounds.left,
        bounds.top + from / scale,
        bounds.left + width / scale,
        bounds.top + (from + tall) / scale,
      );
      final pixels = await _draw(
        document,
        header: header,
        region: region,
        shown: region,
        scale: scale,
        width: width,
        height: tall,
        paper: false,
      );
      for (var row = 0; row < tall; row++) {
        var count = 0;
        var first = -1;
        var last = -1;
        for (var x = 0, at = row * width * 4; x < width; x++, at += 4) {
          if (pixels[at] < _blank ||
              pixels[at + 1] < _blank ||
              pixels[at + 2] < _blank) {
            count++;
            if (first < 0) first = x;
            last = x;
          }
        }
        if (count == 0) continue;
        marked[from + row] = count;
        left[from + row] = bounds.left + first / scale;
        right[from + row] = bounds.left + (last + 1) / scale;
      }
    }
    return ContentProfile(
      top: bounds.top,
      step: 1 / scale,
      marked: marked,
      left: left,
      right: right,
    );
  }

  /// [sheet] of [document], with [header], drawn [dpi] pixels to an inch
  /// of paper, in strips from the top, each but the last a pixel longer
  /// than its share, so that none shows a seam between it and the next.
  Future<List<PrintedStrip>> draw(
    PageDocument document,
    PrintedSheet sheet, {
    required double dpi,
    CanvasHeader? header,
  }) async {
    final width = math.max(1, (sheet.width * dpi / 96).round());
    final height = math.max(1, (sheet.height * dpi / 96).round());
    final scale = width / sheet.region.width;
    final strips = <PrintedStrip>[];
    for (var from = 0; from < height; from += stripPixels) {
      final tall = math.min(stripPixels + 1, height - from);
      final top = sheet.region.top + from / scale;
      final region = Aabb(
        sheet.region.left,
        top,
        sheet.region.right,
        top + tall / scale,
      );
      strips.add((
        rgba: await _draw(
          document,
          header: header,
          region: region,
          shown: sheet.shown,
          scale: scale,
          width: width,
          height: tall,
          sheet: sheet.sheet,
        ),
        width: width,
        height: tall,
        top: from,
      ));
    }
    return strips;
  }

  /// Closes the PDFs opened to draw printouts.
  Future<void> close() async {
    final opened = _pdfs.values.toList();
    _pdfs.clear();
    for (final document in opened) {
      await (await document)?.dispose();
    }
  }

  /// [region] of [document] drawn [scale] pixels to a page unit, [width]
  /// by [height] pixels, as Flutter gives pixels: the paper and its ruling
  /// beneath, unless not [paper]; then of what is written, and of [header],
  /// what lies in [shown] — on [sheet], if it is a sheet's, what has its
  /// middle on it, and whole.
  ///
  /// The elements are drawn as the canvas lays them: the pictures and PDF
  /// pages set as the background first, then the rest by how high each
  /// lies, and ink over all of them, the highlighter multiplied with what
  /// it covers.
  Future<Uint8List> _draw(
    PageDocument document, {
    required Aabb region,
    required Aabb shown,
    required double scale,
    required int width,
    required int height,
    int? sheet,
    CanvasHeader? header,
    bool paper = true,
  }) async {
    final size = Size(width.toDouble(), height.toDouble());
    final sheets = sheet == null ? null : document.canvas.sheets;
    final drawn = Aabb(
      math.max(region.left, shown.left),
      math.max(region.top, shown.top),
      math.min(region.right, shown.right),
      math.min(region.bottom, shown.bottom),
    );
    bool on(Frame frame, Aabb bounds) => sheets == null
        ? bounds.intersects(drawn)
        : sheets.sheetAt(frame.y + frame.height / 2) == sheet &&
              bounds.intersects(region);
    bool onIt(NoteElement element) => switch (element) {
      // Ink is cut at the sheet's edges, as the page cuts it.
      InkElement() => element.bounds.intersects(drawn),
      _ => on(element.frame, element.bounds),
    };
    var title = header != null && on(header.frame, _bounds(header.frame))
        ? header
        : null;
    final elements = <NoteElement>[
      for (final element in document.sortedByZ)
        if (onIt(element)) element,
    ];
    final ink = elements.whereType<InkElement>().toList();
    // The background beneath the rest, each in the order it lies in.
    final rest = <NoteElement>[
      for (final locked in <bool>[true, false])
        for (final element in elements)
          if (element is! InkElement && element.locked == locked) element,
    ];

    final layers = <_Layer>[];
    try {
      // Text boxes and TikZ pictures one after another are drawn together;
      // a picture between them draws them apart.
      var together = <NoteElement>[];
      Future<void> drawTogether() async {
        if (together.isEmpty && title == null) return;
        final text = await drawTextBoxes(
          together,
          region: Rect.fromLTRB(
            region.left,
            region.top,
            region.right,
            region.bottom,
          ),
          scale: scale,
          // The title beneath everything else on the page.
          header: title,
        );
        title = null;
        final objects = <(Rect, ui.Image)>[];
        for (final (embed, rect) in text.objects) {
          final pixels = (rect.width * scale).round();
          final image = switch (embed.kind) {
            EmbedKind.image => await _picture(embed.assetId, pixels),
            EmbedKind.pdfPage => await _pdfPage(
              embed.assetId,
              embed.pageIndex,
              pixels,
            ),
            EmbedKind.file || EmbedKind.tikz => null,
          };
          if (image != null) objects.add((rect, image));
        }
        layers.add(_Layer.text(text.image, objects));
        together = <NoteElement>[];
      }

      for (final element in rest) {
        switch (element) {
          case TextElement() || TikzElement():
            together.add(element);
          case ImageElement(:final assetId, :final fit):
            await drawTogether();
            final image = await _picture(
              assetId,
              (element.frame.width * scale).round(),
            );
            if (image != null) layers.add(_Layer.media(element, image, fit));
          case PdfElement(:final assetId, :final pageIndex):
            await drawTogether();
            final image = await _pdfPage(
              assetId,
              pageIndex,
              (element.frame.width * scale).round(),
            );
            if (image != null) {
              layers.add(_Layer.media(element, image, MediaFit.stretch));
            }
          case InkElement():
            break;
        }
      }
      await drawTogether();

      final recorder = ui.PictureRecorder();
      final canvas = Canvas(recorder);
      Rect onImage(Aabb page) => Rect.fromLTRB(
        (page.left - region.left) * scale,
        (page.top - region.top) * scale,
        (page.right - region.left) * scale,
        (page.bottom - region.top) * scale,
      );
      final background = document.canvas.background;
      if (!paper) {
        canvas.drawRect(
          Offset.zero & size,
          Paint()..color = const Color(0xFFFFFFFF),
        );
      } else if (sheets != null) {
        final band = sheets.bandOf(sheet!);
        paintSheet(
          canvas,
          onImage(band),
          scale,
          sheets.templates[sheet.clamp(0, sheets.count - 1)],
          width: band.width,
          height: band.height,
          paper: Color(background.paperColor),
        );
      } else {
        BackgroundPainter(
          background: background,
          view: ValueNotifier<CanvasViewport>(
            CanvasViewport(
              origin: Offset(region.left, region.top),
              zoom: scale,
            ),
          ),
        ).paint(canvas, size);
      }

      canvas
        ..save()
        ..clipRect(onImage(sheets == null ? drawn : region));
      for (final layer in layers) {
        layer.paint(canvas, onImage, scale);
      }
      canvas
        ..restore()
        ..save()
        ..clipRect(onImage(drawn));
      final viewport = CanvasViewport(
        origin: Offset(region.left, region.top),
        zoom: scale,
      );
      for (final layer in InkLayer.values) {
        InkPainter(
          elements: ink,
          viewport: viewport,
          layer: layer,
        ).paint(canvas, size);
      }
      canvas.restore();

      final picture = recorder.endRecording();
      final image = await picture.toImage(width, height);
      picture.dispose();
      try {
        final data = await image.toByteData();
        return data!.buffer.asUint8List(data.offsetInBytes, data.lengthInBytes);
      } finally {
        image.dispose();
      }
    } finally {
      for (final layer in layers) {
        layer.dispose();
      }
    }
  }

  /// Where a header framed by [frame] lies, room left below it for a title
  /// over more than one line.
  static Aabb _bounds(Frame frame) =>
      Aabb.fromLTWH(frame.x, frame.y, frame.width, frame.height * 2);

  /// The picture [assetId], decoded [pixelWidth] pixels wide or less.
  Future<ui.Image?> _picture(String assetId, int pixelWidth) async {
    final bytes = await store.assets.readBytes(assetId);
    if (bytes == null) return null;
    try {
      final codec = await ui.instantiateImageCodec(
        bytes,
        targetWidth: math.max(1, math.min(pixelWidth, stripPixels)),
      );
      final frame = await codec.getNextFrame();
      codec.dispose();
      return frame.image;
    } on Object {
      return null;
    }
  }

  /// Page [pageIndex] of the PDF [assetId], drawn [pixelWidth] pixels wide
  /// or less.
  Future<ui.Image?> _pdfPage(
    String assetId,
    int pageIndex,
    int pixelWidth,
  ) async {
    final document = await (_pdfs[assetId] ??= _open(assetId));
    if (document == null) return null;
    return renderPdfPage(
      document,
      pageIndex,
      math.max(1, math.min(pixelWidth, stripPixels)),
    );
  }

  Future<PdfDocument?> _open(String assetId) async {
    final asset = await store.assets.find(assetId);
    if (asset == null) return null;
    final file = store.assets.fileFor(asset);
    if (!file.existsSync()) return null;
    await pdfrxFlutterInitialize();
    try {
      return await PdfDocument.openFile(file.path);
    } on Object {
      return null;
    }
  }
}

/// What is drawn of a page, beneath its ink, in order: a picture or PDF
/// page, or text boxes drawn together with the pictures in them.
class _Layer {
  _Layer.media(NoteElement this.element, this.image, this.fit)
    : objects = const <(Rect, ui.Image)>[];

  _Layer.text(this.image, this.objects)
    : element = null,
      fit = MediaFit.stretch;

  final NoteElement? element;
  final ui.Image image;
  final MediaFit fit;

  /// The pictures and PDF pages in the text boxes, and where they lie in
  /// page units from the region's corner.
  final List<(Rect, ui.Image)> objects;

  void paint(Canvas canvas, Rect Function(Aabb page) onImage, double scale) {
    final paint = Paint()..filterQuality = FilterQuality.medium;
    final element = this.element;
    if (element == null) {
      for (final (rect, object) in objects) {
        canvas.drawImageRect(
          object,
          _whole(object),
          Rect.fromLTWH(
            rect.left * scale,
            rect.top * scale,
            rect.width * scale,
            rect.height * scale,
          ),
          paint,
        );
      }
      canvas.drawImage(image, Offset.zero, Paint());
      return;
    }
    final frame = element.frame;
    final rect = onImage(
      Aabb.fromLTWH(frame.x, frame.y, frame.width, frame.height),
    );
    final picture = Size(image.width.toDouble(), image.height.toDouble());
    final fitted = applyBoxFit(
      switch (fit) {
        MediaFit.contain => BoxFit.contain,
        MediaFit.cover => BoxFit.cover,
        MediaFit.stretch => BoxFit.fill,
      },
      picture,
      rect.size,
    );
    canvas
      ..save()
      ..translate(rect.center.dx, rect.center.dy)
      ..rotate(frame.rotation)
      ..translate(-rect.center.dx, -rect.center.dy)
      ..clipRect(rect)
      ..drawImageRect(
        image,
        Alignment.center.inscribe(fitted.source, Offset.zero & picture),
        Alignment.center.inscribe(fitted.destination, rect),
        paint,
      )
      ..restore();
  }

  static Rect _whole(ui.Image image) =>
      Offset.zero & Size(image.width.toDouble(), image.height.toDouble());

  void dispose() {
    image.dispose();
    for (final (_, object) in objects) {
      object.dispose();
    }
  }
}
