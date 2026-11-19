/// Text boxes drawn off the screen, as the page draws them, and their
/// lines read where they were laid out.
library;

import 'dart:ui' as ui;

import 'package:aantekening_canvas/aantekening_canvas.dart';
import 'package:aantekening_core/aantekening_core.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';

import '../editor/element_views.dart';
import '../editor/text/block_paragraph.dart';
import '../editor/text/block_view.dart';
import '../editor/text/block_widgets.dart';
import '../editor/text/text_box_editor.dart';
import '../look/theme.dart';

/// Text boxes drawn as a picture, and where the pictures and PDF pages in
/// them came to lie, to be drawn in.
typedef TextLayer = ({ui.Image image, List<(BlockEmbed, Rect)> objects});

/// A line of text as it was laid out: its words — a formula in it as its
/// LaTeX, between dollar signs — where it lies on the page, in page units,
/// and the element it is in, or null for the page's title.
typedef LaidOutLine = ({String text, Aabb box, String? elementId});

/// Draws [boxes] as they lie in [region] of their page, [scale] pixels to a
/// page unit, on nothing, with the page's own text box — so formulas,
/// lists and tables look as they do on the page — and any TikZ pictures
/// among them as the page draws those. The pictures and PDF pages in the
/// boxes are left out, and where each was laid out is told instead, in
/// page units from the region's corner. A [header], if given, is drawn
/// beneath them, as the page draws its title.
///
/// Laid out and painted in a tree of its own, apart from the window's.
Future<TextLayer> drawTextBoxes(
  List<NoteElement> boxes, {
  required Rect region,
  required double scale,
  CanvasHeader? header,
}) => _offscreen(boxes, region: region, header: header, (root, boundary) async {
  final objects = <(BlockEmbed, Rect)>[];
  void find(Element element) {
    if (element.widget case EmbedStandIn(:final embed)) {
      final box = element.renderObject! as RenderBox;
      objects.add((
        embed,
        MatrixUtils.transformRect(
          box.getTransformTo(boundary),
          Offset.zero & box.size,
        ),
      ));
    }
    element.visitChildren(find);
  }

  root.visitChildren(find);
  return (image: await boundary.toImage(pixelRatio: scale), objects: objects);
});

/// The lines of [boxes] and of [header] as the page lays them out, each
/// with where it lies: in each box, top down and each read across, the
/// marks of its lists with the lines they mark, a formula as its LaTeX.
/// Laid out alone, nothing drawn.
Future<List<LaidOutLine>> layOutLines(
  List<NoteElement> boxes, {
  CanvasHeader? header,
}) async {
  final frames = <Aabb>[
    for (final box in boxes) box.bounds,
    if (header != null)
      Aabb.fromLTWH(
        header.frame.x,
        header.frame.y,
        header.frame.width,
        header.frame.height * 2,
      ),
  ];
  if (frames.isEmpty) return const <LaidOutLine>[];
  final around = Aabb.around(frames);
  final region = Rect.fromLTRB(
    around.left,
    around.top,
    around.right,
    around.bottom,
  );
  return _offscreen(boxes, region: region, header: header, paint: false, (
    root,
    boundary,
  ) async {
    final out = <LaidOutLine>[];
    Aabb onPage(RenderBox box, Rect rect) {
      final placed = MatrixUtils.transformRect(
        box.getTransformTo(boundary),
        rect,
      );
      return Aabb(
        placed.left + region.left,
        placed.top + region.top,
        placed.right + region.left,
        placed.bottom + region.top,
      );
    }

    void find(Element element, String? within) {
      final widget = element.widget;
      final id = widget.key is _BoxKey
          ? (widget.key! as _BoxKey).value
          : within;
      if (widget is BlockParagraph) {
        final render = element.renderObject;
        if (render is RenderBlockParagraph && render.hasSize) {
          for (final (text, rect) in _lines(render.paragraph, widget.view)) {
            out.add((
              text: text,
              box: onPage(render.paragraph, rect),
              elementId: id,
            ));
          }
        }
        // What is in it — its formulas — is said by it.
        return;
      }
      final render = element.renderObject;
      if (widget is RichText &&
          render is RenderParagraph &&
          render.hasSize &&
          element.findAncestorWidgetOfExactType<BlockParagraph>() == null) {
        for (final (text, rect) in _lines(render, null)) {
          out.add((text: text, box: onPage(render, rect), elementId: id));
        }
        return;
      }
      element.visitChildren((child) => find(child, id));
    }

    root.visitChildren((child) => find(child, null));
    // In each box, and in the title, top down and each read across:
    // the mark of a list beside the line it marks.
    final byBox = <String?, List<LaidOutLine>>{};
    for (final line in out) {
      (byBox[line.elementId] ??= <LaidOutLine>[]).add(line);
    }
    return <LaidOutLine>[
      for (final lines in byBox.values) ...lines..sort(_readingOrder),
    ];
  });
}

/// Down, and across for what shares a line.
int _readingOrder(LaidOutLine a, LaidOutLine b) {
  final shared =
      (a.box.centerY - b.box.centerY).abs() <
      (a.box.height < b.box.height ? a.box.height : b.box.height) / 2;
  if (!shared) return a.box.centerY.compareTo(b.box.centerY);
  return a.box.left.compareTo(b.box.left);
}

/// The lines [paragraph] was laid out in, each its text and the box round
/// it in the paragraph's own units: with [view], each formula in it as
/// its LaTeX, between dollar signs.
List<(String, Rect)> _lines(RenderParagraph paragraph, BlockView? view) {
  final laidOut = paragraph.text.toPlainText(includeSemanticsLabels: false);
  if (laidOut.isEmpty) return const <(String, Rect)>[];
  // Where its text lies, a box to each run of a line, each as tall as its
  // line: those of one height are one line.
  final boxes =
      paragraph
          .getBoxesForSelection(
            TextSelection(baseOffset: 0, extentOffset: laidOut.length),
            boxHeightStyle: ui.BoxHeightStyle.max,
          )
          .map((box) => box.toRect())
          .toList()
        ..sort((a, b) => a.top.compareTo(b.top));
  final lines = <Rect>[];
  for (final box in boxes) {
    final on = lines.indexWhere(
      (line) => box.center.dy > line.top && box.center.dy < line.bottom,
    );
    if (on < 0) {
      lines.add(box);
    } else {
      lines[on] = lines[on].expandToInclude(box);
    }
  }
  // A formula alone, laid out with no box of text: the paragraph whole.
  if (lines.isEmpty) lines.add(Offset.zero & paragraph.size);
  final out = <(String, Rect)>[];
  for (final line in lines) {
    // What lies on it, from its one end to its other, at its middle.
    final start = paragraph
        .getPositionForOffset(Offset(-1e6, line.center.dy))
        .offset
        .clamp(0, laidOut.length);
    final end = lines.length == 1
        ? laidOut.length
        : paragraph
              .getPositionForOffset(Offset(1e6, line.center.dy))
              .offset
              .clamp(start, laidOut.length);
    if (end <= start) continue;
    final text =
        (view == null
                ? laidOut.substring(start, end)
                : _modelText(view, start, end))
            .trim();
    if (text.isNotEmpty) out.add((text, line));
  }
  return out;
}

/// What lies from [from] up to [to] of [view]'s laid-out text, as it was
/// written: a formula, one character laid out, as its source between
/// dollar signs — two, for a formula alone in its paragraph.
String _modelText(BlockView view, int from, int to) {
  final out = StringBuffer();
  final display = view.isDisplayFormula;
  for (final run in view.runs) {
    if (run.viewEnd <= from || run.viewStart >= to) continue;
    final text = view.block.runs[run.index].text;
    if (run.collapsed) {
      final sign = display ? r'$$' : r'$';
      out.write('$sign$text$sign');
      continue;
    }
    final a = (from - run.viewStart).clamp(0, text.length);
    final b = (to - run.viewStart).clamp(0, text.length);
    out.write(text.substring(a, b));
  }
  return '$out'.replaceAll('\n', ' ');
}

/// Marks what is laid out for a box as that box's.
class _BoxKey extends ValueKey<String> {
  const _BoxKey(super.value);
}

/// [boxes] and [header] laid out in a tree of their own, in [region], and
/// painted, unless not [paint]; then [use]d, and the tree taken down.
Future<T> _offscreen<T>(
  List<NoteElement> boxes,
  Future<T> Function(Element root, RenderRepaintBoundary boundary) use, {
  required Rect region,
  CanvasHeader? header,
  bool paint = true,
}) async {
  final boundary = RenderRepaintBoundary();
  final dispatcher = WidgetsBinding.instance.platformDispatcher;
  final renderView = RenderView(
    view: dispatcher.implicitView ?? dispatcher.views.first,
    child: RenderPositionedBox(alignment: Alignment.topLeft, child: boundary),
    configuration: ViewConfiguration(
      logicalConstraints: BoxConstraints.tight(region.size),
      physicalConstraints: BoxConstraints.tight(region.size),
    ),
  );
  final pipeline = PipelineOwner()..rootNode = renderView;
  renderView.prepareInitialFrame();
  final focus = FocusManager();
  final build = BuildOwner(focusManager: focus);

  final tree = MediaQuery(
    data: const MediaQueryData(),
    child: Directionality(
      textDirection: TextDirection.ltr,
      child: Theme(
        data: AppTheme.light(),
        child: EmbedStandIns(
          child: SizedBox.fromSize(
            size: region.size,
            child: Stack(
              clipBehavior: Clip.none,
              children: <Widget>[
                if (header != null)
                  Positioned(
                    left: header.frame.x - region.left,
                    top: header.frame.y - region.top,
                    width: header.frame.width,
                    child: header.child,
                  ),
                for (final box in boxes)
                  Positioned(
                    key: _BoxKey(box.id),
                    left: box.frame.x - region.left,
                    top: box.frame.y - region.top,
                    width: box.frame.width,
                    height: box.frame.height,
                    child: Transform.rotate(
                      angle: box.frame.rotation,
                      child: switch (box) {
                        TextElement() => TextBoxEditor(
                          element: box,
                          isEditing: false,
                          interactive: false,
                        ),
                        _ => CanvasElementView(element: box),
                      },
                    ),
                  ),
              ],
            ),
          ),
        ),
      ),
    ),
  );

  final root = RenderObjectToWidgetAdapter<RenderBox>(
    container: boundary,
    child: tree,
  ).attachToRenderTree(build);
  try {
    build
      ..buildScope(root)
      ..finalizeTree();
    pipeline.flushLayout();
    if (paint) {
      pipeline
        ..flushCompositingBits()
        ..flushPaint();
    }
    return await use(root, boundary);
  } finally {
    // Taken down again: nothing of it stays.
    RenderObjectToWidgetAdapter<RenderBox>(container: boundary)
        .attachToRenderTree(build, root);
    build.finalizeTree();
    focus.dispose();
    pipeline.rootNode = null;
    renderView.dispose();
    pipeline.dispose();
  }
}
