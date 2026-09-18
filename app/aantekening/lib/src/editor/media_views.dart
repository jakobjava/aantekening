/// Pictures and PDF pages, wherever they appear: on the canvas by themselves
/// or inside a text box.
library;

import 'dart:async';
import 'dart:collection';
import 'dart:ui' as ui;

import 'package:aantekening_canvas/aantekening_canvas.dart';
import 'package:aantekening_core/aantekening_core.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:pdfrx/pdfrx.dart';

import '../providers.dart';

/// An imported picture, read from the asset store.
class AssetImageView extends ConsumerWidget {
  const AssetImageView({
    required this.assetId,
    super.key,
    this.fit = MediaFit.contain,
  });

  final String assetId;
  final MediaFit fit;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final bytes = ref.watch(assetBytesProvider(assetId));

    return bytes.when(
      loading: () => const MediaPlaceholder(label: 'Loading image…'),
      error: (error, _) => MediaPlaceholder(label: 'Image failed: $error'),
      data: (data) => data == null
          ? const MediaPlaceholder(label: 'Image is missing')
          : Image.memory(
              data,
              fit: switch (fit) {
                MediaFit.contain => BoxFit.contain,
                MediaFit.cover => BoxFit.cover,
                MediaFit.stretch => BoxFit.fill,
              },
              filterQuality: FilterQuality.medium,
              gaplessPlayback: true,
            ),
    );
  }
}

/// One page of an imported PDF, drawn on white paper.
///
/// The page is rasterised at a resolution chosen from its size on screen, so
/// zooming in re-renders it sharply instead of magnifying a small bitmap.
/// Resolutions come in steps, and rendered pages are cached, so panning and
/// small zoom changes never re-render.
class PdfPageView extends ConsumerWidget {
  const PdfPageView({
    required this.assetId,
    required this.pageIndex,
    super.key,
  });

  final String assetId;
  final int pageIndex;

  /// The widths, in device pixels, a page is rendered at.
  static const List<int> _widthSteps = <int>[
    256,
    512,
    768,
    1024,
    1536,
    2048,
    3072,
    4096,
  ];

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final zoom = CanvasScope.zoomOf(context);
    final pixelRatio = MediaQuery.maybeDevicePixelRatioOf(context) ?? 1;
    final document = ref.watch(pdfDocumentProvider(assetId));

    return DecoratedBox(
      decoration: BoxDecoration(
        color: Colors.white,
        border: Border.all(color: const Color(0x22000000)),
        boxShadow: const <BoxShadow>[
          BoxShadow(
            color: Color(0x14000000),
            blurRadius: 6,
            offset: Offset(0, 2),
          ),
        ],
      ),
      child: document.when(
        loading: () => const SizedBox.expand(),
        error: (error, _) => MediaPlaceholder(label: 'PDF failed: $error'),
        data: (doc) {
          if (doc == null || pageIndex >= doc.pages.length) {
            return const MediaPlaceholder(label: 'PDF is missing');
          }
          return LayoutBuilder(
            builder: (context, constraints) {
              final wanted = constraints.maxWidth * zoom * pixelRatio;
              final width = _widthSteps.firstWhere(
                (step) => step >= wanted,
                orElse: () => _widthSteps.last,
              );
              return _PdfRaster(
                document: doc,
                assetId: assetId,
                pageIndex: pageIndex,
                pixelWidth: width,
              );
            },
          );
        },
      ),
    );
  }
}

class _PdfRaster extends StatefulWidget {
  const _PdfRaster({
    required this.document,
    required this.assetId,
    required this.pageIndex,
    required this.pixelWidth,
  });

  final PdfDocument document;
  final String assetId;
  final int pageIndex;
  final int pixelWidth;

  @override
  State<_PdfRaster> createState() => _PdfRasterState();
}

class _PdfRasterState extends State<_PdfRaster> {
  /// How long the zoom must rest before a page is re-rendered at a new
  /// resolution. Re-rendering at every step of a pinch would stall it; the
  /// page is scaled from its current image in the meantime.
  static const Duration _settle = Duration(milliseconds: 180);

  ui.Image? _image;
  int _requested = 0;
  Timer? _settleTimer;

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void didUpdateWidget(_PdfRaster old) {
    super.didUpdateWidget(old);
    final samePage =
        old.pageIndex == widget.pageIndex &&
        old.assetId == widget.assetId &&
        old.document == widget.document;
    if (!samePage) {
      _load();
    } else if (old.pixelWidth != widget.pixelWidth) {
      _settleTimer?.cancel();
      if (_image == null) {
        _load();
      } else {
        _settleTimer = Timer(_settle, _load);
      }
    }
  }

  @override
  void dispose() {
    _settleTimer?.cancel();
    _image?.dispose();
    super.dispose();
  }

  void _load() {
    if (!mounted) return;
    final request = ++_requested;
    final document = widget.document;
    final pageIndex = widget.pageIndex;
    final pixelWidth = widget.pixelWidth;
    unawaited(
      RasterCache.pdfPages
          .obtain(
            '${widget.assetId}/$pageIndex/$pixelWidth',
            () => renderPdfPage(document, pageIndex, pixelWidth),
          )
          .then(
            (image) {
              // A newer size may have been asked for while this one
              // rendered; the page keeps its previous image until then.
              if (!mounted || request != _requested || image == null) {
                image?.dispose();
                return;
              }
              setState(() {
                _image?.dispose();
                _image = image;
              });
            },
            onError: (Object error) {
              debugPrint('PDF page $pageIndex failed to render: $error');
            },
          ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final image = _image;
    if (image == null) return const SizedBox.expand();
    return RawImage(
      image: image,
      fit: BoxFit.fill,
      filterQuality: FilterQuality.medium,
    );
  }
}

/// Rasterised images, kept so that scrolling back to a PDF page or rebuilding
/// it does not render it again.
///
/// Bounded by total pixels rather than by count, because one poster-sized page
/// can cost as much memory as fifty slides.
class RasterCache {
  RasterCache({this.maxPixels = 64 * 1024 * 1024});

  /// The cache for PDF pages; about 256 MB of decoded pixels.
  static final RasterCache pdfPages = RasterCache();

  final int maxPixels;

  final LinkedHashMap<String, ui.Image> _images =
      LinkedHashMap<String, ui.Image>();
  final Map<String, Future<ui.Image?>> _pending = <String, Future<ui.Image?>>{};
  int _pixels = 0;

  /// How many images are held.
  int get length => _images.length;

  /// A handle to the image for [key], produced by [produce] if it is not held
  /// yet. Concurrent requests for one key share a single [produce] call.
  ///
  /// The caller owns the returned handle and must dispose of it.
  Future<ui.Image?> obtain(
    String key,
    Future<ui.Image?> Function() produce,
  ) async {
    final cached = _images.remove(key);
    if (cached != null) {
      _images[key] = cached;
      return cached.clone();
    }

    // The callback must not return the removed future: whenComplete waits on
    // whatever its callback returns, and a future waiting on itself never
    // completes — which is how every PDF page once stayed blank.
    final image = await (_pending[key] ??= produce().whenComplete(() {
      _pending.remove(key);
    }));
    if (image == null) return null;

    if (!_images.containsKey(key)) {
      _images[key] = image;
      _pixels += image.width * image.height;
      _evict();
    }
    return (_images[key] ?? image).clone();
  }

  void _evict() {
    while (_pixels > maxPixels && _images.length > 1) {
      final oldest = _images.keys.first;
      final image = _images.remove(oldest)!;
      _pixels -= image.width * image.height;
      image.dispose();
    }
  }
}

/// Renders page [pageIndex] of [document], [pixelWidth] pixels wide, on white.
Future<ui.Image?> renderPdfPage(
  PdfDocument document,
  int pageIndex,
  int pixelWidth,
) async {
  if (pageIndex >= document.pages.length) return null;
  final page = document.pages[pageIndex];
  final scale = pixelWidth / page.width;
  final rendered = await page.render(
    fullWidth: page.width * scale,
    fullHeight: page.height * scale,
    backgroundColor: 0xFFFFFFFF,
  );
  if (rendered == null) return null;
  try {
    return await rendered.createImage();
  } finally {
    rendered.dispose();
  }
}

/// A PDF from the asset store, opened for rendering.
///
/// Closed again once no page of it is on screen.
final pdfDocumentProvider = FutureProvider.autoDispose
    .family<PdfDocument?, String>((ref, assetId) async {
      final file = await ref.watch(assetFileProvider(assetId).future);
      if (file == null) return null;
      await pdfrxFlutterInitialize();
      final document = await PdfDocument.openFile(file.path);
      ref.onDispose(document.dispose);
      return document;
    });

/// A grey stand-in for media that is loading or missing.
class MediaPlaceholder extends StatelessWidget {
  const MediaPlaceholder({required this.label, super.key});

  final String label;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Container(
      alignment: Alignment.center,
      decoration: BoxDecoration(
        color: scheme.surfaceContainerHighest.withValues(alpha: 0.4),
        border: Border.all(color: scheme.outlineVariant),
      ),
      padding: const EdgeInsets.all(8),
      child: Text(
        label,
        textAlign: TextAlign.center,
        style: TextStyle(fontSize: 11, color: scheme.onSurfaceVariant),
      ),
    );
  }
}
