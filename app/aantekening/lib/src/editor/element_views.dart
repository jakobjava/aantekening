/// Widgets for the elements on a page other than text boxes and ink.
library;

import 'package:aantekening_core/aantekening_core.dart';
import 'package:flutter/material.dart';

import 'media_views.dart';

/// Renders one free-standing element of a page.
///
/// Text boxes are built by the page editor, which wires them to editing;
/// ink is painted by the canvas, where the sample counts make widgets the wrong
/// tool.
class CanvasElementView extends StatelessWidget {
  const CanvasElementView({required this.element, super.key});

  final NoteElement element;

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
      // Text boxes are built by the page editor; ink is painted by the
      // canvas.
      TextElement() || InkElement() => const SizedBox.shrink(),
    };
  }
}
