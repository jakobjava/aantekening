/// Widgets for the elements on a page other than text boxes and ink.
library;

import 'package:aantekening_core/aantekening_core.dart';
import 'package:aantekening_math/aantekening_math.dart';
import 'package:flutter/material.dart';

import 'media_views.dart';
import 'text/block_widgets.dart';
import 'text/text_styles.dart';

/// Renders one free-standing element of a page.
///
/// Text boxes are built by the page editor, which wires them to editing;
/// ink is painted by the canvas, where the sample counts make widgets the wrong
/// tool.
class CanvasElementView extends StatelessWidget {
  const CanvasElementView({required this.element, this.onDrawn, super.key});

  final NoteElement element;

  /// Told how large a TikZ picture is drawn, unscaled, whenever that
  /// changes, for its frame to keep its proportions.
  final ValueChanged<Size>? onDrawn;

  @override
  Widget build(BuildContext context) {
    return switch (element) {
      ImageElement(:final assetId, :final fit) => AssetImageView(
        assetId: assetId,
        fit: fit,
      ),
      PdfElement(:final assetId, :final pageIndex, :final frame) => PdfPageView(
        assetId: assetId,
        pageIndex: pageIndex,
        frame: frame,
      ),
      // Drawn as text draws it, filling its frame as a picture does.
      TikzElement(:final source) => FittedBox(
        child: SizeReporter(
          onSize: onDrawn ?? (_) {},
          child: MathView(
            source: source,
            mode: MathMode.latex,
            textStyle: RichTextStyles.base(context),
          ),
        ),
      ),
      // Text boxes are built by the page editor; ink is painted by the
      // canvas.
      TextElement() || InkElement() => const SizedBox.shrink(),
    };
  }
}
