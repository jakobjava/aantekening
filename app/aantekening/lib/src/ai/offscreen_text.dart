/// Text boxes drawn off the screen, as the page draws them.
library;

import 'dart:ui' as ui;

import 'package:aantekening_core/aantekening_core.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';

import '../editor/text/block_widgets.dart';
import '../editor/text/text_box_editor.dart';
import '../theme.dart';

/// Text boxes drawn as a picture, and where the pictures and PDF pages in
/// them came to lie, to be drawn in.
typedef TextLayer = ({ui.Image image, List<(BlockEmbed, Rect)> objects});

/// Draws [boxes] as they lie in [region] of their page, [scale] pixels to a
/// page unit, on nothing, with the page's own text box — so formulas,
/// lists and tables look as they do on the page. The pictures and PDF pages
/// in them are left out, and where each was laid out is told instead, in
/// page units from the region's corner.
///
/// Laid out and painted in a tree of its own, apart from the window's.
Future<TextLayer> drawTextBoxes(
  List<TextElement> boxes, {
  required Rect region,
  required double scale,
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
                for (final box in boxes)
                  Positioned(
                    left: box.frame.x - region.left,
                    top: box.frame.y - region.top,
                    width: box.frame.width,
                    height: box.frame.height,
                    child: Transform.rotate(
                      angle: box.frame.rotation,
                      child: TextBoxEditor(
                        element: box,
                        isEditing: false,
                        interactive: false,
                      ),
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
    pipeline
      ..flushLayout()
      ..flushCompositingBits()
      ..flushPaint();

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
