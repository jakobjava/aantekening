/// The pieces a text box is drawn with besides its text: list markers, the
/// band along its top, pictures, PDF pages and TikZ pictures, and the
/// measure of its size.
library;

import 'dart:math' as math;

import 'package:aantekening_canvas/aantekening_canvas.dart';
import 'package:aantekening_core/aantekening_core.dart';
import 'package:aantekening_math/aantekening_math.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';

import '../../look/marks.dart';
import '../../look/tones.dart';
import '../media_views.dart';
import 'list_numbering.dart';
import 'text_styles.dart';

/// The bullet, number or checkbox before a list item, or null for a block
/// that has none. Drawn in [style], the block's text style, a ticked box
/// in [mark] — the interface's mark on paper.
Widget? blockMarker(TextBlock block, TextStyle style, Color mark, int ordinal) {
  final fontSize = style.fontSize ?? RichTextStyles.bodySize;
  final lineHeight = fontSize * (style.height ?? 1.4);
  switch (block.kind) {
    case TextBlockKind.bulleted:
      final marker = block.marker;
      final shape = marker == null
          ? _BulletShape.of(block.bullet, block.indent)
          : _BulletShape.drawing(marker);
      // A mark written elsewhere that is none of the shapes is set as it
      // was written.
      if (shape == null) {
        return Text(
          marker!,
          style: style.copyWith(color: RichTextStyles.inkMuted),
          textScaler: TextScaler.noScaling,
        );
      }
      return _Bullet(
        shape: shape,
        color: RichTextStyles.inkMuted,
        fontSize: fontSize,
        lineHeight: lineHeight,
      );
    case TextBlockKind.numbered:
      return Text(
        '${ListNumbering.label(ordinal, block.indent)}.',
        style: style.copyWith(color: RichTextStyles.inkMuted),
        textScaler: TextScaler.noScaling,
      );
    case TextBlockKind.todo:
      final size = fontSize * 1.1;
      return Padding(
        padding: EdgeInsets.only(top: math.max(0, (lineHeight - size) / 2)),
        child: Align(
          alignment: Alignment.topLeft,
          child: Mark(
            block.checked ? MarkShape.boxTicked : MarkShape.box,
            size: size,
            color: block.checked ? mark : RichTextStyles.inkMuted,
          ),
        ),
      );
    case TextBlockKind.paragraph:
    case TextBlockKind.heading1:
    case TextBlockKind.heading2:
    case TextBlockKind.heading3:
    case TextBlockKind.code:
    case TextBlockKind.quote:
      return null;
  }
}

/// The shapes a bullet is drawn in.
enum _BulletShape {
  disc,
  circle,
  square,
  box,
  dash;

  /// The shape of a list of [style] at depth [level]: discs turn into
  /// circles and then squares as lists nest; dashes stay dashes.
  static _BulletShape of(BulletStyle style, int level) =>
      style == BulletStyle.dash
      ? dash
      : const <_BulletShape>[disc, circle, square][level % 3];

  /// The shape of a mark written elsewhere as [marker], if it is one of
  /// them — drawn, so it looks the same whatever fonts are installed.
  static _BulletShape? drawing(String marker) => switch (marker) {
    '•' || '●' || '·' => disc,
    '○' || '◦' || 'o' => circle,
    '▪' || '■' || '◾' => square,
    '□' || '◻' || '❑' => box,
    '-' || '–' || '—' || '−' => dash,
    _ => null,
  };
}

/// A list bullet, drawn rather than typed so it looks the same whatever fonts
/// are installed.
class _Bullet extends StatelessWidget {
  const _Bullet({
    required this.shape,
    required this.color,
    required this.fontSize,
    required this.lineHeight,
  });

  final _BulletShape shape;
  final Color color;
  final double fontSize;
  final double lineHeight;

  @override
  Widget build(BuildContext context) => SizedBox(
    height: lineHeight,
    child: CustomPaint(
      painter: _BulletPainter(
        shape: shape,
        color: color,
        size: fontSize * 0.34,
      ),
    ),
  );
}

class _BulletPainter extends CustomPainter {
  const _BulletPainter({
    required this.shape,
    required this.color,
    required this.size,
  });

  final _BulletShape shape;
  final Color color;
  final double size;

  @override
  void paint(Canvas canvas, Size area) {
    final center = Offset(size, area.height / 2);
    final fill = Paint()..color = color;
    final line = Paint()
      ..color = color
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.1;
    switch (shape) {
      case _BulletShape.disc:
        canvas.drawCircle(center, size / 2, fill);
      case _BulletShape.circle:
        canvas.drawCircle(center, size / 2 - 0.5, line);
      case _BulletShape.square:
        canvas.drawRect(
          Rect.fromCenter(
            center: center,
            width: size * 0.85,
            height: size * 0.85,
          ),
          fill,
        );
      case _BulletShape.box:
        canvas.drawRect(
          Rect.fromCenter(
            center: center,
            width: size * 0.9,
            height: size * 0.9,
          ),
          line,
        );
      case _BulletShape.dash:
        canvas.drawRect(
          Rect.fromCenter(
            center: center,
            width: size * 1.4,
            height: math.max(1, size * 0.2),
          ),
          fill,
        );
    }
  }

  @override
  bool shouldRepaint(_BulletPainter old) =>
      old.shape != shape || old.color != color || old.size != size;
}

/// The strip along the top of a text box that moves it when dragged: drawn
/// as nothing — a box shows nothing of itself until it is clicked, when it
/// is framed as anything picked is — but the pointer over it says it moves.
class GrabBand extends StatelessWidget {
  const GrabBand({required this.height, this.movable = true, super.key});

  final double height;

  /// Whether a drag on it would move the box, which only the selecting tool
  /// does: a pen over it shows its own nib.
  final bool movable;

  @override
  Widget build(BuildContext context) => MouseRegion(
    cursor: movable ? SystemMouseCursors.move : MouseCursor.defer,
    child: SizedBox(height: height),
  );
}

/// Where the handles of an object in a text box are, shared by the object
/// that draws them and the editor that takes hold of them.
///
/// They are the page's own (`SelectionHandles`): the outline pushed out
/// round the object and the handles as large, at its corners and the middles
/// of its sides, in screen pixels, so they stay the same size however far
/// the page is zoomed, and are grabbed from the same distance.
abstract final class EmbedHandles {
  /// The corners of the outline round an object [object] large, clockwise
  /// from the top-left, in screen pixels from its own top-left corner;
  /// [pixel] is a screen pixel in its units.
  static List<Offset> outline(Size object, double pixel) {
    final box = (Offset.zero & object / pixel).inflate(
      SelectionHandles.outlineInset,
    );
    return <Offset>[box.topLeft, box.topRight, box.bottomRight, box.bottomLeft];
  }

  /// Where each handle of an object [object] large is, in screen pixels.
  static Map<SelectionHandle, Offset> positions(Size object, double pixel) =>
      SelectionHandles.positionsOn(
        outline(object, pixel),
        SelectionHandles.resizing,
      );

  /// The handle a press at [local] takes hold of on an object [object]
  /// large, or null where it takes hold of none: a handle, or a side
  /// anywhere along it.
  static SelectionHandle? at(
    Size object,
    Offset local, {
    required double pixel,
  }) {
    final box = outline(object, pixel);
    return SelectionHandles.hitTestOn(
      positions(object, pixel),
      SelectionHandles.sidesOn(box, SelectionHandles.resizing),
      local / pixel,
    );
  }

  /// How much wider an object [aspectRatio] wide to its height becomes as
  /// [handle] is dragged by [drag]: away from its middle widens it. A corner
  /// follows the pointer along its diagonal, both directions counting; a
  /// side, across itself. The object keeps its proportions either way.
  static double widening(
    SelectionHandle handle,
    Offset drag,
    double aspectRatio,
  ) {
    final across = drag.dx * (handle.movesLeft ? -1 : 1);
    final down = drag.dy * aspectRatio * (handle.movesTop ? -1 : 1);
    return switch (handle) {
      SelectionHandle.left || SelectionHandle.right => across,
      SelectionHandle.top || SelectionHandle.bottom => down,
      _ => (across + down) / 2,
    };
  }
}

/// Draws the outline and handles round a picked object, as the page draws
/// them round an element.
class _PickedPainter extends CustomPainter {
  const _PickedPainter({required this.pixel, required this.accent});

  /// A screen pixel in the object's units.
  final double pixel;
  final Color accent;

  @override
  void paint(Canvas canvas, Size size) {
    canvas
      ..save()
      ..scale(pixel);
    SelectionHandles.paintOutline(
      canvas,
      EmbedHandles.outline(size, pixel),
      accent,
    );
    SelectionHandles.paintHandles(
      canvas,
      EmbedHandles.positions(size, pixel),
      accent,
    );
    canvas.restore();
  }

  @override
  bool shouldRepaint(_PickedPainter oldDelegate) =>
      oldDelegate.pixel != pixel || oldDelegate.accent != accent;
}

/// A picture or PDF page on its own line inside a text box.
/// Marks text boxes drawn for a machine to look at, off the screen: the
/// pictures and PDF pages in them are left as [EmbedStandIn]s of their size,
/// to be drawn in afterwards where the stand-ins were laid out.
class EmbedStandIns extends InheritedWidget {
  const EmbedStandIns({required super.child, super.key});

  /// Whether [context] is within such text boxes.
  static bool within(BuildContext context) =>
      context.getInheritedWidgetOfExactType<EmbedStandIns>() != null;

  @override
  bool updateShouldNotify(EmbedStandIns oldWidget) => false;
}

/// Where the picture or PDF page [embed] was laid out, in text boxes marked
/// with [EmbedStandIns]; it draws nothing itself.
class EmbedStandIn extends StatelessWidget {
  const EmbedStandIn({required this.embed, super.key});

  final BlockEmbed embed;

  @override
  Widget build(BuildContext context) => const SizedBox.expand();
}

class EmbedBlock extends StatelessWidget {
  const EmbedBlock({
    required this.embed,
    required this.style,
    required this.selected,
    required this.caretSide,
    required this.caretVisible,
    required this.caretColor,
    required this.caretWidth,
    required this.caretHeight,
    this.align = BlockAlign.start,
    this.objectKey,
    super.key,
  });

  final BlockEmbed embed;

  /// The style of the text round it, which a TikZ picture is drawn in: at
  /// its size, in its colour.
  final TextStyle style;

  /// Where across the box the object sits.
  final BlockAlign align;

  /// Keys the object itself, whose size is what it is drawn at, so the text
  /// box can find where its corners are.
  final Key? objectKey;

  /// Whether the object is picked, drawn framed and with the handles that
  /// resize it.
  final bool selected;

  /// 0 or 1 when the caret sits before or after the object.
  final int? caretSide;
  final ValueListenable<bool> caretVisible;
  final Color caretColor;
  final double caretWidth;

  /// How tall the caret is: as tall as a line of text, standing on the
  /// object's lower edge as on a line's, rather than as tall as the object.
  final double caretHeight;

  @override
  Widget build(BuildContext context) {
    final mark = context.tones.paperEmphasis;
    // A picked object's frame and handles are drawn in screen pixels, as the
    // page draws them round an element, so zooming does not change them.
    final pixel = selected ? 1 / CanvasScope.zoomOf(context) : 1.0;
    return LayoutBuilder(
      builder: (context, constraints) => Align(
        alignment: switch (align) {
          BlockAlign.start => Alignment.centerLeft,
          BlockAlign.center => Alignment.center,
          BlockAlign.end => Alignment.centerRight,
        },
        // The object sets the size; what is drawn round it fits that.
        child: Stack(
          key: objectKey,
          clipBehavior: Clip.none,
          children: <Widget>[
            _object(context, constraints.maxWidth),
            Positioned.fill(
              child: LayoutBuilder(
                builder: (context, drawn) => _marks(drawn.biggest, mark, pixel),
              ),
            ),
          ],
        ),
      ),
    );
  }

  /// The object, at most [widest] wide.
  Widget _object(BuildContext context, double widest) {
    if (embed.source case final source?) return _picture(source, widest);
    final width = math.min(embed.width, widest);
    return SizedBox(
      width: width,
      height: width / embed.aspectRatio,
      child: EmbedStandIns.within(context)
          ? EmbedStandIn(embed: embed)
          : switch (embed.kind) {
              EmbedKind.image => AssetImageView(assetId: embed.assetId),
              EmbedKind.pdfPage => PdfPageView(
                assetId: embed.assetId,
                pageIndex: embed.pageIndex,
              ),
              EmbedKind.file => AttachedFileView(embed: embed),
              EmbedKind.tikz => const SizedBox.shrink(),
            },
    );
  }

  /// The TikZ picture [source] draws, as tall as it makes it: as large as
  /// it is drawn in [style] until it is resized, and never wider than
  /// [widest].
  Widget _picture(String source, double widest) {
    final drawn = MathView(
      source: source,
      mode: MathMode.latex,
      textStyle: style,
    );
    if (embed.width <= 0) {
      return ConstrainedBox(
        constraints: BoxConstraints(maxWidth: widest),
        child: FittedBox(fit: BoxFit.scaleDown, child: drawn),
      );
    }
    return SizedBox(
      width: math.min(embed.width, widest),
      child: FittedBox(fit: BoxFit.fitWidth, child: drawn),
    );
  }

  /// The frame and handles round the object, [size] large, while it is
  /// picked, and the caret beside it.
  Widget _marks(Size size, Color mark, double pixel) {
    final side = caretSide;
    return Stack(
      clipBehavior: Clip.none,
      children: <Widget>[
        if (selected)
          Positioned.fill(
            child: CustomPaint(
              painter: _PickedPainter(pixel: pixel, accent: mark),
            ),
          ),
        if (side != null)
          Positioned(
            left: side == 0 ? -caretWidth - 1 : null,
            right: side == 1 ? -caretWidth - 1 : null,
            height: math.min(caretHeight, size.height),
            bottom: 0,
            child: ValueListenableBuilder<bool>(
              valueListenable: caretVisible,
              builder: (context, visible, _) => Container(
                width: caretWidth,
                color: visible ? caretColor : Colors.transparent,
              ),
            ),
          ),
      ],
    );
  }
}

/// Reports its child's laid-out size after each layout that changes it.
class SizeReporter extends SingleChildRenderObjectWidget {
  const SizeReporter({required this.onSize, required super.child, super.key});

  final ValueChanged<Size> onSize;

  @override
  RenderSizeReporter createRenderObject(BuildContext context) =>
      RenderSizeReporter(onSize);

  @override
  void updateRenderObject(
    BuildContext context,
    RenderSizeReporter renderObject,
  ) {
    renderObject.onSize = onSize;
  }
}

class RenderSizeReporter extends RenderProxyBox {
  RenderSizeReporter(this.onSize);

  ValueChanged<Size> onSize;
  Size? _last;

  @override
  void performLayout() {
    super.performLayout();
    final measured = size;
    if (_last == measured) return;
    _last = measured;
    // Reported after the frame: resizing the box is a state change, which
    // must not happen in the middle of layout.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (attached) onSize(measured);
    });
  }
}
