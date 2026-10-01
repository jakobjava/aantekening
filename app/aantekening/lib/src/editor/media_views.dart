/// Pictures, PDF pages and attached files, wherever they appear: on the
/// canvas by themselves or inside a text box.
library;

import 'dart:async';
import 'dart:collection';
import 'dart:math' as math;
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

/// The sizes, in device pixels, pictures are decoded at.
const List<int> _pictureSteps = <int>[
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
int shownPixels(BuildContext context, double extent) =>
    _stepFor(_wantedPixels(context, extent), _pictureSteps);

/// How many device pixels [extent] page units come to as they are seen.
double _wantedPixels(BuildContext context, double extent) =>
    extent *
    CanvasScope.zoomOf(context) *
    (MediaQuery.maybeDevicePixelRatioOf(context) ?? 1);

/// The first of [steps] at least [wanted], or the last.
int _stepFor(double wanted, List<int> steps) =>
    steps.firstWhere((step) => step >= wanted, orElse: () => steps.last);

/// The widths, in device pixels, a whole PDF page is drawn at. Seen wider
/// than the last, it is drawn in tiles about the view as well: a page drawn
/// whole that wide would take a hundred megabytes, and as long to hand to
/// the screen as several frames.
const List<int> _pdfWidths = <int>[256, 512, 768, 1024, 1536, 2048];

/// The width a PDF page coming into view while the view zooms is sketched
/// at, until the zoom it comes to is known.
const int _pdfSketch = 512;

/// The side of a tile of a PDF page, in device pixels.
const int _tileSide = 1024;

/// One page of an imported PDF, drawn on white paper.
///
/// The page is drawn in pixels as sharp as it is seen: the whole of it at
/// one of a few widths, and zoomed in further than that, the tiles of it
/// about the view as well, where the page knows where it lies ([frame]).
/// What is drawn is shared by every view of the page ([PdfRasters]), so a
/// page scrolled back to, or shown again, is there at once. Until what it
/// asks for is drawn it shows the nearest it has, scaled: once drawn it
/// never goes blank, and a new zoom sharpens it rather than flashing it.
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
    final doc = document.value;
    final missing =
        !document.isLoading && (doc == null || pageIndex >= doc.pages.length);
    return DecoratedBox(
      // A printed page, edged on the paper it lies on.
      decoration: BoxDecoration(
        color: Tones.paper,
        border: Border.all(color: RichTextStyles.titleRule),
      ),
      child: document.hasError
          ? MediaPlaceholder(label: 'PDF failed: ${document.error}')
          : missing
          ? const MediaPlaceholder(label: 'PDF is missing')
          // While the document opens, what was drawn of the page before
          // is shown.
          : _PdfPage(
              id: '$assetId/$pageIndex',
              document: doc,
              pageIndex: pageIndex,
              frame: frame,
            ),
    );
  }
}

class _PdfPage extends StatefulWidget {
  const _PdfPage({
    required this.id,
    required this.document,
    required this.pageIndex,
    required this.frame,
  });

  /// What the page's pictures are shared under.
  final String id;

  /// The document, or null while it opens.
  final PdfDocument? document;
  final int pageIndex;
  final Frame? frame;

  PdfPage? get page => document?.pages[pageIndex];

  @override
  State<_PdfPage> createState() => _PdfPageState();
}

class _PdfPageState extends State<_PdfPage> {
  /// How long a new zoom rests before the page is drawn for it: drawing it
  /// at every step of a zoom would keep the renderer busy with pictures
  /// that are never seen.
  static const Duration _settle = Duration(milliseconds: 180);

  late PageRasters _rasters = PdfRasters.shared.of(widget.id);

  /// The pictures asked for, which are kept while they are, and the plan
  /// they were asked for by.
  Set<PdfRaster> _asked = const <PdfRaster>{};
  _PdfPlan? _askedPlan;

  /// A plan for a new zoom, waiting for it to rest.
  _PdfPlan? _waiting;
  Timer? _settleTimer;

  @override
  void didUpdateWidget(_PdfPage old) {
    super.didUpdateWidget(old);
    if (old.id == widget.id) return;
    _askFor(const <PdfRaster>{});
    _askedPlan = null;
    _rasters = PdfRasters.shared.of(widget.id);
  }

  @override
  void dispose() {
    _settleTimer?.cancel();
    _askFor(const <PdfRaster>{});
    super.dispose();
  }

  /// What to draw of the page, [size] page units in its box, and how
  /// sharply, as it is seen now.
  _PdfPlan _plan(BuildContext context, Size size) {
    final wanted = _wantedPixels(context, size.width);
    final width = _stepFor(wanted, _pdfWidths);
    final page = widget.page;
    final frame = widget.frame;
    final region = CanvasScope.regionOf(context);
    if (page == null ||
        frame == null ||
        region == null ||
        frame.rotation != 0 ||
        wanted <= _pdfWidths.last) {
      return _PdfPlan(width: width);
    }
    var level = _pdfWidths.last.toDouble();
    while (level < wanted) {
      level *= 1.5;
    }
    final plan = _PdfPlan(
      width: width,
      level: level.round(),
      aspect: page.height / page.width,
      box: size,
      seen: Rect.fromLTRB(
        region.left - frame.x,
        region.top - frame.y,
        region.right - frame.x,
        region.bottom - frame.y,
      ).intersect(Offset.zero & size),
    );
    return plan.seen.isEmpty ? _PdfPlan(width: width) : plan;
  }

  /// Asks for what [plan] draws, once a change of zoom has rested; while
  /// the view zooms, for nothing new, but a sketch of a page that has
  /// nothing drawn yet.
  void _ask(_PdfPlan plan, {required bool zooming}) {
    if (widget.document == null) return;
    if (zooming) {
      if (_rasters.isEmpty && _asked.isEmpty) {
        _askFor(<PdfRaster>{_wholePage(math.min(plan.width, _pdfSketch))});
      }
      return;
    }
    final asked = _askedPlan;
    if (asked == null || plan.sharpAs(asked) || _rasters.isEmpty) {
      _settleTimer?.cancel();
      _waiting = null;
      _askFor(plan.rasters);
      _askedPlan = plan;
      return;
    }
    // Scrolling on while it waits, it waits on with where the view is now.
    final waiting = _waiting;
    _waiting = plan;
    if (waiting != null && plan.sharpAs(waiting)) return;
    _settleTimer?.cancel();
    _settleTimer = Timer(_settle, () {
      final ready = _waiting;
      _waiting = null;
      if (!mounted || ready == null) return;
      _askFor(ready.rasters);
      _askedPlan = ready;
    });
  }

  void _askFor(Set<PdfRaster> rasters) {
    final before = _asked;
    _asked = rasters;
    for (final raster in rasters) {
      if (!before.contains(raster)) {
        _rasters.want(raster, () => _render(raster));
      }
    }
    for (final raster in before) {
      if (!rasters.contains(raster)) _rasters.unwant(raster);
    }
  }

  RasterRender _render(PdfRaster raster) {
    final document = widget.document!;
    final page = document.pages[widget.pageIndex];
    final cancellation = page.createCancellationToken();
    return (
      image: renderPdfPage(
        document,
        widget.pageIndex,
        raster.width,
        pixels: raster.isTile
            ? _tilePixels(raster, page.height / page.width)
            : null,
        cancellation: cancellation,
      ),
      cancel: cancellation.cancel,
    );
  }

  @override
  Widget build(BuildContext context) => LayoutBuilder(
    builder: (context, constraints) {
      final plan = _plan(context, constraints.biggest);
      _ask(plan, zooming: CanvasScope.zoomingOf(context));
      return SizedBox.expand(
        child: CustomPaint(painter: _PdfPainter(_rasters, plan)),
      );
    },
  );
}

/// A picture of a PDF page: the whole of it drawn [width] pixels wide, or
/// the tile at [column] and [row] of it drawn that wide.
typedef PdfRaster = ({int width, int column, int row});

PdfRaster _wholePage(int width) => (width: width, column: -1, row: -1);

extension on PdfRaster {
  bool get isTile => column >= 0;
}

/// The pixels of the page [tile] covers, of the page drawn [tile]'s width
/// and [aspect] times as high; the last row of them may lie only partly on
/// the page.
Rect _tilePixels(PdfRaster tile, double aspect) {
  final side = _tileSide.toDouble();
  final width = tile.width.toDouble();
  final pixels = Rect.fromLTWH(
    tile.column * side,
    tile.row * side,
    side,
    side,
  ).intersect(Offset.zero & Size(width, width * aspect));
  return Rect.fromLTRB(
    pixels.left,
    pixels.top,
    pixels.right,
    pixels.bottom.ceilToDouble(),
  );
}

/// What of a PDF page to draw, and how sharply: the whole of it [width]
/// pixels wide, and where the view is zoomed in further than that, the
/// tiles of it drawn [level] pixels wide over the part of its box [seen].
@immutable
class _PdfPlan {
  const _PdfPlan({
    required this.width,
    this.level = 0,
    this.aspect = 0,
    this.box = Size.zero,
    this.seen = Rect.zero,
  });

  final int width;

  /// The width the tiles are drawn at, or 0 for none.
  final int level;

  /// The page's height over its width.
  final double aspect;

  /// The page's box, and the part of it laid out about the view, in page
  /// units.
  final Size box;
  final Rect seen;

  /// Where [tile] lies in the box.
  Rect place(PdfRaster tile) {
    final pixels = _tilePixels(tile, aspect);
    final across = box.width / tile.width;
    final down = box.height / (tile.width * aspect);
    return Rect.fromLTRB(
      pixels.left * across,
      pixels.top * down,
      pixels.right * across,
      pixels.bottom * down,
    );
  }

  /// Whether this draws the page as sharp as [other] does.
  bool sharpAs(_PdfPlan other) => width == other.width && level == other.level;

  /// The whole page, and the tiles over what is seen, the nearest the
  /// middle of it first.
  Set<PdfRaster> get rasters {
    final rasters = <PdfRaster>{_wholePage(width)};
    if (level == 0) return rasters;
    final across = level / box.width;
    final down = level * aspect / box.height;
    final pixels = Rect.fromLTRB(
      seen.left * across,
      seen.top * down,
      seen.right * across,
      seen.bottom * down,
    );
    final middle = pixels.center;
    final tiles = <PdfRaster>[
      for (
        var row = pixels.top ~/ _tileSide;
        row * _tileSide < pixels.bottom;
        row++
      )
        for (
          var column = pixels.left ~/ _tileSide;
          column * _tileSide < pixels.right;
          column++
        )
          (width: level, column: column, row: row),
    ];
    double away(PdfRaster tile) =>
        (_tilePixels(tile, aspect).center - middle).distanceSquared;
    return rasters..addAll(tiles..sort((a, b) => away(a).compareTo(away(b))));
  }

  @override
  bool operator ==(Object other) =>
      other is _PdfPlan &&
      other.width == width &&
      other.level == level &&
      other.aspect == aspect &&
      other.box == box &&
      other.seen == seen;

  @override
  int get hashCode => Object.hash(width, level, aspect, box, seen);
}

/// Draws a PDF page from what is drawn of it: the whole page as sharp as
/// [plan] asks, or the nearest drawn, and over it the tiles drawn about the
/// view — at the level asked, over those drawn coarser before, which go on
/// showing where the sharper are not drawn yet.
class _PdfPainter extends CustomPainter {
  _PdfPainter(this.rasters, this.plan) : super(repaint: rasters);

  final PageRasters rasters;
  final _PdfPlan plan;

  static final Paint _paint = Paint()..filterQuality = FilterQuality.medium;

  @override
  void paint(Canvas canvas, Size size) {
    final whole = rasters.whole(plan.width);
    if (whole != null) _draw(canvas, whole, Offset.zero & size);
    if (plan.level == 0) return;
    for (final (tile, image) in rasters.tiles(upTo: plan.level)) {
      final place = plan.place(tile);
      if (place.overlaps(plan.seen)) _draw(canvas, image, place);
    }
  }

  static void _draw(Canvas canvas, ui.Image image, Rect place) =>
      canvas.drawImageRect(
        image,
        Offset.zero & Size(image.width.toDouble(), image.height.toDouble()),
        place,
        _paint,
      );

  @override
  bool shouldRepaint(_PdfPainter old) =>
      !identical(old.rasters, rasters) || old.plan != plan;
}

/// A render of a picture under way: the picture it comes to, or null if it
/// was called off, and what calls it off if it has not begun.
typedef RasterRender = ({Future<ui.Image?> image, VoidCallback cancel});

/// The pictures PDF pages are drawn as, shared by every view of them.
///
/// A picture is drawn once however many views ask for it, and kept while
/// any of them wants it. Once none does it is kept a while longer, in case
/// it is wanted again — a page scrolled back to — those wanted least
/// recently let go first once all the pictures come to more than
/// [maxPixels]: bounded by pixels rather than by count, as one
/// poster-sized page costs as much as fifty slides.
class PdfRasters {
  PdfRasters({this.maxPixels = 48 * 1024 * 1024});

  /// The pictures of every PDF page shown: about 200 MB of them, at most,
  /// besides those in view.
  static final PdfRasters shared = PdfRasters();

  final int maxPixels;

  final Map<String, PageRasters> _pages = <String, PageRasters>{};

  /// The pictures no view wants, the least recently wanted first.
  final LinkedHashSet<(PageRasters, PdfRaster)> _spare =
      LinkedHashSet<(PageRasters, PdfRaster)>();

  /// How many pixels all the pictures held come to.
  int get pixels => _pixels;
  int _pixels = 0;

  /// The pictures of the page [id].
  PageRasters of(String id) => _pages[id] ??= PageRasters._(this);

  void _held(ui.Image image) => _pixels += image.width * image.height;

  void _spared(PageRasters page, PdfRaster raster) {
    _spare.add((page, raster));
    while (_pixels > maxPixels && _spare.isNotEmpty) {
      final oldest = _spare.first;
      _spare.remove(oldest);
      final image = oldest.$1._pictures.remove(oldest.$2)!.image!;
      _pixels -= image.width * image.height;
      image.dispose();
    }
  }
}

/// The pictures of one PDF page: told when one more is drawn.
class PageRasters extends ChangeNotifier {
  PageRasters._(this._all);

  final PdfRasters _all;
  final Map<PdfRaster, _Picture> _pictures = <PdfRaster, _Picture>{};

  /// Whether nothing of the page is drawn.
  bool get isEmpty => !_pictures.values.any((picture) => picture.image != null);

  /// The whole page as drawn [width] pixels wide, or else as drawn nearest
  /// that: the narrowest wider, or failing that the widest narrower.
  ui.Image? whole(int width) {
    PdfRaster? best;
    ui.Image? image;
    for (final MapEntry(key: raster, value: picture) in _pictures.entries) {
      final drawn = picture.image;
      if (drawn == null || raster.isTile) continue;
      if (best == null || _nearer(raster.width, best.width, width)) {
        best = raster;
        image = drawn;
      }
    }
    return image;
  }

  /// Whether a picture [a] wide is nearer [width] than one [b] wide: the
  /// sharper wins, unless it is sharper than need be.
  static bool _nearer(int a, int b, int width) =>
      a >= width ? b < width || a < b : b < width && a > b;

  /// The tiles drawn no wider than [upTo], the coarsest first.
  List<(PdfRaster, ui.Image)> tiles({required int upTo}) =>
      <(PdfRaster, ui.Image)>[
        for (final MapEntry(key: raster, value: picture) in _pictures.entries)
          if (raster.isTile && raster.width <= upTo && picture.image != null)
            (raster, picture.image!),
      ]..sort((a, b) => a.$1.width.compareTo(b.$1.width));

  /// Asks for [raster], drawn by [render] unless it is drawn or being drawn
  /// already: it is kept until [unwant] is asked as often as this.
  void want(PdfRaster raster, RasterRender Function() render) {
    final picture = _pictures[raster] ??= _Picture();
    picture.wanters++;
    _all._spare.remove((this, raster));
    if (picture.image == null && picture.cancel == null && !picture.failed) {
      _render(raster, picture, render);
    }
  }

  /// No longer asks for [raster]: what is drawn of it is kept a while, and
  /// what is not, not drawn, if it has not begun to be.
  void unwant(PdfRaster raster) {
    final picture = _pictures[raster];
    if (picture == null || --picture.wanters > 0) return;
    if (picture.cancel case final cancel?) {
      picture.calledOff = true;
      cancel();
    } else if (picture.image == null) {
      _pictures.remove(raster);
    } else {
      _all._spared(this, raster);
    }
  }

  void _render(
    PdfRaster raster,
    _Picture picture,
    RasterRender Function() render,
  ) {
    final rendering = render();
    picture
      ..cancel = rendering.cancel
      ..calledOff = false;
    void done(ui.Image? image) {
      picture.cancel = null;
      if (!identical(_pictures[raster], picture)) {
        image?.dispose();
        return;
      }
      if (image == null) {
        // Called off, then wanted again before it could be.
        if (picture.calledOff && picture.wanters > 0) {
          _render(raster, picture, render);
        } else if (picture.wanters == 0) {
          _pictures.remove(raster);
        } else {
          picture.failed = true;
        }
        return;
      }
      picture.image = image;
      _all._held(image);
      if (picture.wanters == 0) _all._spared(this, raster);
      notifyListeners();
    }

    unawaited(
      rendering.image.then(
        done,
        onError: (Object error) {
          debugPrint('PDF page failed to render: $error');
          done(null);
        },
      ),
    );
  }
}

/// A picture of a PDF page: drawn, or being drawn.
class _Picture {
  ui.Image? image;

  /// How many times it is asked for.
  int wanters = 0;

  /// What calls off drawing it, while it is being drawn; and whether that
  /// was asked for.
  VoidCallback? cancel;
  bool calledOff = false;

  /// Whether it could not be drawn: it is not tried again.
  bool failed = false;
}

/// Renders page [pageIndex] of [document], [pixelWidth] pixels wide, on white:
/// all of it, or only [pixels] of it, in pixels of the page at that width;
/// nothing, if [cancellation] calls it off before it begins.
Future<ui.Image?> renderPdfPage(
  PdfDocument document,
  int pageIndex,
  int pixelWidth, {
  Rect? pixels,
  PdfPageRenderCancellationToken? cancellation,
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
    cancellationToken: cancellation,
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
/// Closed again a while after no page of it is on screen.
final pdfDocumentProvider = FutureProvider.autoDispose
    .family<PdfDocument?, String>((ref, assetId) async {
      ref.keepAWhile();
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
