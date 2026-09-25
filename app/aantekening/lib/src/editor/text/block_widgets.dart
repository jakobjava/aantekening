/// The pieces a text box is drawn with besides its text: list markers, the
/// band along its top, pictures and PDF pages, and the measure of its size.
library;

import 'dart:math' as math;

import 'package:aantekening_canvas/aantekening_canvas.dart';
import 'package:aantekening_core/aantekening_core.dart';
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
      return _Bullet(
        level: block.indent,
        style: block.bullet,
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

/// A list bullet, drawn rather than typed so it looks the same whatever fonts
/// are installed: a disc, then a circle, then a square as lists nest, or a
/// dash at every level for a list started with one.
class _Bullet extends StatelessWidget {
  const _Bullet({
    required this.level,
    required this.style,
    required this.color,
    required this.fontSize,
    required this.lineHeight,
  });

  final int level;
  final BulletStyle style;
  final Color color;
  final double fontSize;
  final double lineHeight;

  @override
  Widget build(BuildContext context) => SizedBox(
    height: lineHeight,
    child: CustomPaint(
      painter: _BulletPainter(
        level: level,
        style: style,
        color: color,
        size: fontSize * 0.34,
      ),
    ),
  );
}

class _BulletPainter extends CustomPainter {
  const _BulletPainter({
    required this.level,
    required this.style,
    required this.color,
    required this.size,
  });

  final int level;
  final BulletStyle style;
  final Color color;
  final double size;

  @override
  void paint(Canvas canvas, Size area) {
    final center = Offset(size, area.height / 2);
    final paint = Paint()..color = color;
    if (style == BulletStyle.dash) {
      canvas.drawRect(
        Rect.fromCenter(
          center: center,
          width: size * 1.4,
          height: math.max(1, size * 0.2),
        ),
        paint,
      );
      return;
    }
    switch (level % 3) {
      case 0:
        canvas.drawCircle(center, size / 2, paint);
      case 1:
        canvas.drawCircle(
          center,
          size / 2 - 0.5,
          paint
            ..style = PaintingStyle.stroke
            ..strokeWidth = 1.1,
        );
      default:
        canvas.drawRect(
          Rect.fromCenter(
            center: center,
            width: size * 0.85,
            height: size * 0.85,
          ),
          paint,
        );
    }
  }

  @override
  bool shouldRepaint(_BulletPainter old) =>
      old.level != level ||
      old.style != style ||
      old.color != color ||
      old.size != size;
}

/// The strip along the top of a text box that moves it when dragged.
class GrabBand extends StatelessWidget {
  const GrabBand({
    required this.height,
    required this.visible,
    required this.active,
    super.key,
  });

  final double height;
  final bool visible;

  /// Whether the box is the one being typed in or picked, drawn a shade
  /// stronger.
  final bool active;

  @override
  Widget build(BuildContext context) {
    // Drawn on the paper, so in the paper's colours rather than the theme's.
    return MouseRegion(
      cursor: SystemMouseCursors.move,
      child: SizedBox(
        height: height,
        child: visible
            ? DecoratedBox(
                decoration: BoxDecoration(
                  color: active
                      ? RichTextStyles.boxBandActive
                      : RichTextStyles.boxBand,
                ),
                child: Center(
                  child: Container(
                    width: 28,
                    height: 3,
                    color: RichTextStyles.boxGrip,
                  ),
                ),
              )
            : null,
      ),
    );
  }
}

/// A corner of an object in a text box, which resizes it when dragged.
///
/// An object keeps its proportions, as a picture on the page does, so every
/// corner sets the width and the height follows.
enum EmbedCorner {
  topLeft(-1, -1),
  topRight(1, -1),
  bottomLeft(-1, 1),
  bottomRight(1, 1);

  const EmbedCorner(this.x, this.y);

  /// Which way this corner lies from the middle of the object: -1 towards the
  /// left or the top, 1 towards the right or the bottom.
  final int x;
  final int y;

  /// Where the handle's centre sits on an object of [size].
  Offset centerIn(Size size) =>
      Offset(x < 0 ? 0 : size.width, y < 0 ? 0 : size.height);

  MouseCursor get cursor => x == y
      ? SystemMouseCursors.resizeUpLeftDownRight
      : SystemMouseCursors.resizeUpRightDownLeft;

  /// How much wider the object becomes as this corner is dragged by [drag]:
  /// away from the object's middle widens it, and both directions count, so a
  /// corner dragged along its diagonal follows the pointer.
  double widening(Offset drag, double aspectRatio) =>
      (drag.dx * x + drag.dy * aspectRatio * y) / 2;
}

/// Where the handles of an object in a text box are, shared by the object
/// that draws them and the editor that takes hold of them.
///
/// They are the page's own handles, in the page's sizes: drawn in screen
/// pixels, so they stay the same size however far the page is zoomed, and
/// grabbed from the same distance.
abstract final class EmbedHandles {
  static const double size = SelectionHandles.size;
  static const double reach = SelectionHandles.mouseReach;

  /// Line width of the outline round a picked object and of the ring round
  /// each of its handles.
  static const double stroke = 1.5;

  /// The corner a press at [local] takes hold of on an object of [object],
  /// or null where it takes hold of none. [pixel] is a screen pixel in the
  /// object's own units.
  static EmbedCorner? at(Size object, Offset local, {required double pixel}) {
    EmbedCorner? found;
    var nearest = reach * pixel;
    for (final corner in EmbedCorner.values) {
      final distance = (corner.centerIn(object) - local).distance;
      if (distance <= nearest) {
        nearest = distance;
        found = corner;
      }
    }
    return found;
  }
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
    required this.selected,
    required this.caretSide,
    required this.caretVisible,
    required this.caretColor,
    required this.caretWidth,
    this.objectKey,
    super.key,
  });

  final BlockEmbed embed;

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

  @override
  Widget build(BuildContext context) {
    final mark = context.tones.paperEmphasis;
    // A picked object's frame and handles are drawn in screen pixels, as the
    // page draws them round an element, so zooming does not change them.
    final pixel = selected ? 1 / CanvasScope.zoomOf(context) : 1.0;
    return LayoutBuilder(
      builder: (context, constraints) {
        final width = math.min(embed.width, constraints.maxWidth);
        final height = width / embed.aspectRatio;
        final side = caretSide;
        return Align(
          alignment: Alignment.centerLeft,
          child: SizedBox(
            key: objectKey,
            width: width,
            height: height,
            child: Stack(
              clipBehavior: Clip.none,
              children: <Widget>[
                Positioned.fill(
                  child: EmbedStandIns.within(context)
                      ? EmbedStandIn(embed: embed)
                      : switch (embed.kind) {
                          EmbedKind.image => AssetImageView(
                            assetId: embed.assetId,
                          ),
                          EmbedKind.pdfPage => PdfPageView(
                            assetId: embed.assetId,
                            pageIndex: embed.pageIndex,
                          ),
                        },
                ),
                if (selected) ...<Widget>[
                  Positioned.fill(
                    child: DecoratedBox(
                      decoration: BoxDecoration(
                        color: mark.withValues(alpha: 0.18),
                        border: Border.all(
                          color: mark,
                          width: EmbedHandles.stroke * pixel,
                        ),
                      ),
                    ),
                  ),
                  for (final corner in EmbedCorner.values)
                    _CornerHandle(
                      corner: corner,
                      object: Size(width, height),
                      color: mark,
                      pixel: pixel,
                    ),
                ],
                if (side != null)
                  Positioned(
                    left: side == 0 ? -caretWidth - 1 : null,
                    right: side == 1 ? -caretWidth - 1 : null,
                    top: 0,
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
            ),
          ),
        );
      },
    );
  }
}

/// The grab point at one corner of a selected object. The press that drags it
/// is handled by the text box, which owns the object's size.
class _CornerHandle extends StatelessWidget {
  const _CornerHandle({
    required this.corner,
    required this.object,
    required this.color,
    required this.pixel,
  });

  final EmbedCorner corner;
  final Size object;
  final Color color;

  /// A screen pixel in the object's own units.
  final double pixel;

  @override
  Widget build(BuildContext context) {
    final size = EmbedHandles.size * pixel;
    final center = corner.centerIn(object);
    return Positioned(
      left: center.dx - size / 2,
      top: center.dy - size / 2,
      child: MouseRegion(
        cursor: corner.cursor,
        child: Container(
          width: size,
          height: size,
          decoration: BoxDecoration(
            color: color,
            border: Border.all(
              color: const Color(0xFFFFFFFF),
              width: EmbedHandles.stroke * pixel,
            ),
          ),
        ),
      ),
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
