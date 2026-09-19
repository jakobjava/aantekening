/// The pieces a text box is drawn with besides its text: list markers, the
/// band along its top, pictures and PDF pages, and the measure of its size.
library;

import 'dart:math' as math;

import 'package:aantekening_core/aantekening_core.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';

import '../media_views.dart';
import 'list_numbering.dart';
import 'text_styles.dart';

/// The bullet, number or checkbox before a list item, or null for a block
/// that has none. Drawn in [style], the block's text style.
Widget? blockMarker(
  TextBlock block,
  TextStyle style,
  ColorScheme scheme,
  int ordinal,
) {
  final fontSize = style.fontSize ?? RichTextStyles.bodySize;
  final lineHeight = fontSize * (style.height ?? 1.4);
  switch (block.kind) {
    case TextBlockKind.bulleted:
      return _Bullet(
        level: block.indent,
        color: scheme.onSurfaceVariant,
        fontSize: fontSize,
        lineHeight: lineHeight,
      );
    case TextBlockKind.numbered:
      return Text(
        '${ListNumbering.label(ordinal, block.indent)}.',
        style: style.copyWith(color: scheme.onSurfaceVariant),
        textScaler: TextScaler.noScaling,
      );
    case TextBlockKind.todo:
      final size = fontSize * 1.1;
      return Padding(
        padding: EdgeInsets.only(top: math.max(0, (lineHeight - size) / 2)),
        child: Align(
          alignment: Alignment.topLeft,
          child: Icon(
            block.checked
                ? Icons.check_box_rounded
                : Icons.check_box_outline_blank_rounded,
            size: size,
            color: block.checked ? scheme.primary : scheme.onSurfaceVariant,
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
/// are installed: a disc, then a circle, then a square as lists nest.
class _Bullet extends StatelessWidget {
  const _Bullet({
    required this.level,
    required this.color,
    required this.fontSize,
    required this.lineHeight,
  });

  final int level;
  final Color color;
  final double fontSize;
  final double lineHeight;

  @override
  Widget build(BuildContext context) => SizedBox(
    height: lineHeight,
    child: CustomPaint(
      painter: _BulletPainter(
        level: level,
        color: color,
        size: fontSize * 0.34,
      ),
    ),
  );
}

class _BulletPainter extends CustomPainter {
  const _BulletPainter({
    required this.level,
    required this.color,
    required this.size,
  });

  final int level;
  final Color color;
  final double size;

  @override
  void paint(Canvas canvas, Size area) {
    final center = Offset(size, area.height / 2);
    final paint = Paint()..color = color;
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
      old.level != level || old.color != color || old.size != size;
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
                    decoration: BoxDecoration(
                      color: RichTextStyles.boxGrip,
                      borderRadius: BorderRadius.circular(2),
                    ),
                  ),
                ),
              )
            : null,
      ),
    );
  }
}

/// A picture or PDF page on its own line inside a text box.
class EmbedBlock extends StatelessWidget {
  const EmbedBlock({
    required this.embed,
    required this.selected,
    required this.caretSide,
    required this.caretVisible,
    required this.caretColor,
    required this.caretWidth,
    super.key,
  });

  final BlockEmbed embed;
  final bool selected;

  /// 0 or 1 when the caret sits before or after the object.
  final int? caretSide;
  final ValueListenable<bool> caretVisible;
  final Color caretColor;
  final double caretWidth;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return LayoutBuilder(
      builder: (context, constraints) {
        final width = math.min(embed.width, constraints.maxWidth);
        final height = width / embed.aspectRatio;
        final side = caretSide;
        return Align(
          alignment: Alignment.centerLeft,
          child: SizedBox(
            width: width,
            height: height,
            child: Stack(
              clipBehavior: Clip.none,
              children: <Widget>[
                Positioned.fill(
                  child: switch (embed.kind) {
                    EmbedKind.image => AssetImageView(assetId: embed.assetId),
                    EmbedKind.pdfPage => PdfPageView(
                      assetId: embed.assetId,
                      pageIndex: embed.pageIndex,
                    ),
                  },
                ),
                if (selected)
                  Positioned.fill(
                    child: DecoratedBox(
                      decoration: BoxDecoration(
                        color: scheme.primary.withValues(alpha: 0.18),
                        border: Border.all(color: scheme.primary, width: 2),
                      ),
                    ),
                  ),
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
