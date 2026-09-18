/// Bringing pictures and PDFs into a page.
library;

import 'dart:io';
import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:aantekening_core/aantekening_core.dart';
import 'package:aantekening_store/aantekening_store.dart';
import 'package:file_selector/file_selector.dart';
import 'package:pdfrx/pdfrx.dart';

/// What the user is inserting.
enum MediaKind { image, pdf }

/// One picture or PDF page, stored and measured, ready to be placed.
class ImportedMedia {
  const ImportedMedia({
    required this.kind,
    required this.assetId,
    required this.width,
    required this.height,
    this.pageIndex = 0,
    this.text,
  });

  final EmbedKind kind;
  final String assetId;
  final int pageIndex;

  /// Natural size in page units.
  final double width;
  final double height;

  /// A PDF page's text layer, for search.
  final String? text;

  /// This item placed inside a text box.
  BlockEmbed toEmbed() => BlockEmbed(
    kind: kind,
    assetId: assetId,
    pageIndex: pageIndex,
    width: width,
    height: height,
    text: text,
  );

  /// This item placed on the canvas by itself, with its top-left at [at] and
  /// no wider than [maxWidth].
  NoteElement toElement(ui.Offset at, {double maxWidth = double.infinity}) {
    final scale = math.min(1.0, maxWidth / width);
    final frame = Frame(
      x: at.dx,
      y: at.dy,
      width: width * scale,
      height: height * scale,
    );
    final now = DateTime.now().millisecondsSinceEpoch;
    return switch (kind) {
      EmbedKind.image => ImageElement(
        id: Ulid.generate(),
        frame: frame,
        createdAt: now,
        updatedAt: now,
        assetId: assetId,
      ),
      EmbedKind.pdfPage => PdfElement(
        id: Ulid.generate(),
        frame: frame,
        createdAt: now,
        updatedAt: now,
        assetId: assetId,
        pageIndex: pageIndex,
        extractedText: text,
      ),
    };
  }
}

/// Asks for files and imports them into the workspace's asset store.
abstract final class MediaImport {
  /// Page units per PDF point: PDF pages are measured at 72 per inch, the page
  /// at 96, so a letter-size page comes in exactly as wide as the page guide.
  static const double pdfScale = 96 / 72;

  /// The widest a picture comes in, in page units. Screenshots from a large
  /// monitor would otherwise arrive wider than the whole page.
  static const double maxImageWidth = 800;

  static const XTypeGroup _images = XTypeGroup(
    label: 'Images',
    extensions: <String>['png', 'jpg', 'jpeg', 'gif', 'webp', 'bmp'],
    mimeTypes: <String>[
      'image/png',
      'image/jpeg',
      'image/gif',
      'image/webp',
      'image/bmp',
    ],
    uniformTypeIdentifiers: <String>['public.image'],
  );

  static const XTypeGroup _pdfs = XTypeGroup(
    label: 'PDF documents',
    extensions: <String>['pdf'],
    mimeTypes: <String>['application/pdf'],
    uniformTypeIdentifiers: <String>['com.adobe.pdf'],
  );

  /// Lets the user choose files of [kind] and imports them.
  ///
  /// Returns an empty list if the user cancels. A PDF yields one item per
  /// page, in order.
  static Future<List<ImportedMedia>> pickAndImport(
    AantekeningStore store,
    MediaKind kind,
  ) async {
    final files = await openFiles(
      acceptedTypeGroups: <XTypeGroup>[
        if (kind == MediaKind.image) _images else _pdfs,
      ],
    );
    final imported = <ImportedMedia>[];
    for (final file in files) {
      imported.addAll(await importFile(store, File(file.path)));
    }
    return imported;
  }

  /// Imports one file, deciding from its type whether it is a picture or a PDF.
  static Future<List<ImportedMedia>> importFile(
    AantekeningStore store,
    File file,
  ) async {
    final mimeType = AssetStore.mimeTypeForPath(file.path);
    if (mimeType == 'application/pdf') return _importPdf(store, file);
    if (mimeType.startsWith('image/') && mimeType != 'image/svg+xml') {
      return <ImportedMedia>[await _importImage(store, file)];
    }
    throw UnsupportedError('Cannot import ${file.path}: not a picture or PDF');
  }

  static Future<ImportedMedia> _importImage(
    AantekeningStore store,
    File file,
  ) async {
    final bytes = await file.readAsBytes();
    final asset = await store.assets.importFile(file);

    // Only the header is read to learn the size; the picture is decoded when
    // it is drawn, at the size it is drawn.
    final buffer = await ui.ImmutableBuffer.fromUint8List(bytes);
    final descriptor = await ui.ImageDescriptor.encoded(buffer);
    final width = descriptor.width.toDouble();
    final height = descriptor.height.toDouble();
    descriptor.dispose();
    buffer.dispose();

    final scale = math.min(1.0, maxImageWidth / math.max(width, 1));
    return ImportedMedia(
      kind: EmbedKind.image,
      assetId: asset.id,
      width: width * scale,
      height: height * scale,
    );
  }

  static Future<List<ImportedMedia>> _importPdf(
    AantekeningStore store,
    File file,
  ) async {
    final asset = await store.assets.importFile(file);
    await pdfrxFlutterInitialize();
    final document = await PdfDocument.openFile(file.path);
    try {
      return <ImportedMedia>[
        for (var i = 0; i < document.pages.length; i++)
          ImportedMedia(
            kind: EmbedKind.pdfPage,
            assetId: asset.id,
            pageIndex: i,
            width: document.pages[i].width * pdfScale,
            height: document.pages[i].height * pdfScale,
            text: _normalize((await document.pages[i].loadText())?.fullText),
          ),
      ];
    } finally {
      await document.dispose();
    }
  }

  /// Collapses a PDF text layer's whitespace, which is mostly line breaks
  /// where the page was typeset rather than where sentences end.
  static String? _normalize(String? text) {
    if (text == null) return null;
    final collapsed = text.replaceAll(RegExp(r'\s+'), ' ').trim();
    return collapsed.isEmpty ? null : collapsed;
  }
}
