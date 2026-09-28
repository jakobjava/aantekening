/// Pictures, PDF pages and attached files, wherever they appear: on the
/// canvas by themselves or inside a text box.
library;

import 'dart:async';
import 'dart:collection';
import 'dart:ui' as ui;

import 'package:aantekening_canvas/aantekening_canvas.dart';
import 'package:aantekening_core/aantekening_core.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:pdfrx/pdfrx.dart';

import '../look/tones.dart';
import '../providers.dart';
import 'text/text_styles.dart';

/// An imported picture, read from the asset store.
///
/// Decoded no larger than it is shown, in steps as a PDF page is rendered:
/// a photograph a few thousand pixels across, shown the width of a column,
/// would otherwise keep all its pixels in memory. Zooming in on it decodes
/// it again, sharper.
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
          : LayoutBuilder(
              builder: (context, constraints) {
                final whole = MemoryImage(data);
                final width = shownPixels(context, constraints.maxWidth);
                final height = shownPixels(context, constraints.maxHeight);
                return Image(
                  image: switch (fit) {
                    // Filling the box, a picture may run past it either way.
                    MediaFit.cover => whole,
                    MediaFit.contain => ResizeImage(
                      whole,
                      width: width,
                      height: height,
                      policy: ResizeImagePolicy.fit,
                    ),
                    MediaFit.stretch => ResizeImage(
                      whole,
                      width: width,
                      height: height,
                    ),
                  },
                  fit: switch (fit) {
                    MediaFit.contain => BoxFit.contain,
                    MediaFit.cover => BoxFit.cover,
                    MediaFit.stretch => BoxFit.fill,
                  },
                  filterQuality: FilterQuality.medium,
                  gaplessPlayback: true,
                );
              },
            ),
    );
  }
}

/// The sizes, in device pixels, pictures and PDF pages are drawn at.
const List<int> _pixelSteps = <int>[
  256,
  512,
  768,
  1024,
  1536,
  2048,
  3072,
  4096,
];

/// How many device pixels to draw something [extent] page units long in, to
/// show it sharply at the zoom and pixel density it is seen at: the next
/// step up, so that panning and small changes of zoom never draw it again.
int shownPixels(BuildContext context, double extent) {
  final zoom = CanvasScope.zoomOf(context);
  final pixelRatio = MediaQuery.maybeDevicePixelRatioOf(context) ?? 1;
  final wanted = extent * zoom * pixelRatio;
  return _pixelSteps.firstWhere(
    (step) => step >= wanted,
    orElse: () => _pixelSteps.last,
  );
}

/// One page of an imported PDF, drawn on white paper.
///
/// The page is rasterised at a resolution chosen from its size on screen, so
/// zooming in re-renders it sharply instead of magnifying a small bitmap.
/// Resolutions come in steps, and rendered pages are cached, so panning and
/// small zoom changes never re-render. Zoomed in further than the whole page
/// can be rendered sharp at, the part of it about the view is rendered sharp
/// over it, where the page knows where it lies ([frame]).
class PdfPageView extends ConsumerWidget {
  const PdfPageView({
    required this.assetId,
    required this.pageIndex,
    this.frame,
    super.key,
  });

  final String assetId;
  final int pageIndex;

  /// Where the page lies on the canvas, in page units, if it lies there by
  /// itself rather than in a text box.
  final Frame? frame;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final document = ref.watch(pdfDocumentProvider(assetId));

    return DecoratedBox(
      // A printed page, edged on the paper it lies on.
      decoration: BoxDecoration(
        color: Tones.paper,
        border: Border.all(color: RichTextStyles.titleRule),
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
              final width = shownPixels(context, constraints.maxWidth);
              final whole = _Rendered(
                cacheKey: '$assetId/$pageIndex/$width',
                render: () => renderPdfPage(doc, pageIndex, width),
                keepWhileRendering: true,
              );
              final detail = _detail(context, doc, constraints.biggest);
              return detail == null
                  ? whole
                  : Stack(
                      fit: StackFit.expand,
                      children: <Widget>[whole, detail],
                    );
            },
          );
        },
      ),
    );
  }

  /// The part of the page about the view, rendered sharp over the whole
  /// of it, where that is too large to be rendered sharp; null otherwise.
  Widget? _detail(BuildContext context, PdfDocument document, Size size) {
    final frame = this.frame;
    final region = CanvasScope.regionOf(context);
    if (frame == null || region == null || frame.rotation != 0) return null;
    final pixelRatio = MediaQuery.maybeDevicePixelRatioOf(context) ?? 1;
    final wanted = size.width * CanvasScope.zoomOf(context) * pixelRatio;
    if (wanted <= _pixelSteps.last) return null;
    var fullWidth = _pixelSteps.last.toDouble();
    while (fullWidth < wanted) {
      fullWidth *= 1.5;
    }
    final page = document.pages[pageIndex];
    final fullHeight = fullWidth * page.height / page.width;
    // What of the page the region takes in, in whole pixels of the page
    // rendered [fullWidth] wide, and so where on the page that lies.
    final pixels = Rect.fromLTRB(
      ((region.left - frame.x) / frame.width * fullWidth).floorToDouble(),
      ((region.top - frame.y) / frame.height * fullHeight).floorToDouble(),
      ((region.right - frame.x) / frame.width * fullWidth).ceilToDouble(),
      ((region.bottom - frame.y) / frame.height * fullHeight).ceilToDouble(),
    ).intersect(Offset.zero & Size(fullWidth, fullHeight));
    if (pixels.isEmpty) return null;
    final scale = size.width / fullWidth;
    return Positioned.fromRect(
      rect: Rect.fromLTRB(
        pixels.left * scale,
        pixels.top * size.height / fullHeight,
        pixels.right * scale,
        pixels.bottom * size.height / fullHeight,
      ),
      child: _Rendered(
        cacheKey: '$assetId/$pageIndex/$fullWidth/$pixels',
        render: () => renderPdfPage(
          document,
          pageIndex,
          fullWidth.round(),
          pixels: pixels,
        ),
        keepWhileRendering: false,
      ),
    );
  }
}

/// The image [render] makes, kept in [RasterCache.pdfPages] as [cacheKey],
/// drawn filling its box.
///
/// Asked for another, it renders it once the change has rested a moment:
/// rendering at every step of a pinch would stall it. Meanwhile it goes on
/// showing the image before, scaled, if [keepWhileRendering] — the same
/// page at another resolution — or nothing, for another part of the page.
class _Rendered extends StatefulWidget {
  const _Rendered({
    required this.cacheKey,
    required this.render,
    required this.keepWhileRendering,
  });

  final String cacheKey;
  final Future<ui.Image?> Function() render;
  final bool keepWhileRendering;

  @override
  State<_Rendered> createState() => _RenderedState();
}

class _RenderedState extends State<_Rendered> {
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
  void didUpdateWidget(_Rendered old) {
    super.didUpdateWidget(old);
    if (old.cacheKey == widget.cacheKey) return;
    _settleTimer?.cancel();
    if (!widget.keepWhileRendering) {
      _image?.dispose();
      _image = null;
    }
    if (_image == null && widget.keepWhileRendering) {
      _load();
    } else {
      _settleTimer = Timer(_settle, _load);
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
    unawaited(
      RasterCache.pdfPages
          .obtain(widget.cacheKey, widget.render)
          .then(
            (image) {
              // A newer one may have been asked for while this one rendered.
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
              debugPrint('PDF page failed to render: $error');
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

/// Renders page [pageIndex] of [document], [pixelWidth] pixels wide, on white:
/// all of it, or only [pixels] of it, in pixels of the page at that width.
Future<ui.Image?> renderPdfPage(
  PdfDocument document,
  int pageIndex,
  int pixelWidth, {
  Rect? pixels,
}) async {
  if (pageIndex >= document.pages.length) return null;
  final page = document.pages[pageIndex];
  final scale = pixelWidth / page.width;
  final rendered = await page.render(
    x: pixels?.left.round() ?? 0,
    y: pixels?.top.round() ?? 0,
    width: pixels?.width.round(),
    height: pixels?.height.round(),
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

/// A file attached to a page: its name, what kind of file it is and how
/// big, on a card of its own. Double-clicking it, or its menu, opens it.
class AttachedFileView extends ConsumerWidget {
  const AttachedFileView({required this.embed, super.key});

  final BlockEmbed embed;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final asset = ref.watch(assetRefProvider(embed.assetId)).value;
    final name = embed.name ?? asset?.originalName ?? 'Attached file';
    final dot = name.lastIndexOf('.');
    final kind = dot > 0 ? name.substring(dot + 1).toUpperCase() : 'FILE';
    final size = asset == null ? '' : '  ·  ${fileSize(asset.byteSize)}';
    final type = RichTextStyles.paperType;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      decoration: BoxDecoration(
        color: Tones.paper,
        border: Border.all(color: RichTextStyles.tableRule),
      ),
      child: FittedBox(
        fit: BoxFit.scaleDown,
        alignment: Alignment.centerLeft,
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: <Widget>[
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 2),
              decoration: BoxDecoration(
                border: Border.all(color: RichTextStyles.inkMuted),
              ),
              child: Text(
                kind,
                style: type.copyWith(
                  fontSize: 10,
                  fontWeight: FontWeight.w600,
                  color: RichTextStyles.inkMuted,
                ),
              ),
            ),
            const SizedBox(width: 10),
            Text(
              name,
              style: type.copyWith(fontSize: 13, color: RichTextStyles.ink),
            ),
            Text(
              size,
              style: type.copyWith(
                fontSize: 12,
                color: RichTextStyles.inkMuted,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// [bytes] as a person reads a file's size: 12 KB, 3.4 MB.
String fileSize(int bytes) {
  if (bytes < 1024) return '$bytes bytes';
  const units = <String>['KB', 'MB', 'GB'];
  var size = bytes / 1024;
  var unit = 0;
  while (size >= 1024 && unit < units.length - 1) {
    size /= 1024;
    unit++;
  }
  return '${size < 10 ? size.toStringAsFixed(1) : size.round()} ${units[unit]}';
}

/// A grey stand-in for media that is loading or missing.
class MediaPlaceholder extends StatelessWidget {
  const MediaPlaceholder({required this.label, super.key});

  final String label;

  @override
  Widget build(BuildContext context) => Container(
    alignment: Alignment.center,
    decoration: BoxDecoration(
      color: RichTextStyles.codeFill,
      border: Border.all(color: RichTextStyles.titleRule),
    ),
    padding: const EdgeInsets.all(8),
    child: Text(
      label,
      textAlign: TextAlign.center,
      style: RichTextStyles.paperType.copyWith(
        fontSize: 11,
        color: RichTextStyles.inkMuted,
      ),
    ),
  );
}
