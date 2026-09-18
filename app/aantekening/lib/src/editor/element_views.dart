/// Widgets for the elements on a page other than text boxes and ink.
library;

import 'package:aantekening_core/aantekening_core.dart';
import 'package:aantekening_math/aantekening_math.dart';
import 'package:flutter/material.dart';

import 'media_views.dart';
import 'text/text_styles.dart';

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
      MathElement() => _MathBox(element: element as MathElement),
      ImageElement(:final assetId, :final fit) => AssetImageView(
        assetId: assetId,
        fit: fit,
      ),
      PdfElement(:final assetId, :final pageIndex) => PdfPageView(
        assetId: assetId,
        pageIndex: pageIndex,
      ),
      TableElement() => _TableBox(element: element as TableElement),
      // Text boxes are built by the page editor; groups have no appearance of
      // their own; ink is painted by the canvas.
      TextElement() ||
      GroupElement() ||
      InkElement() => const SizedBox.shrink(),
    };
  }
}

/// A formula placed on the canvas by itself, as earlier builds made them.
/// New formulas are written inside text boxes.
class _MathBox extends StatelessWidget {
  const _MathBox({required this.element});

  final MathElement element;

  @override
  Widget build(BuildContext context) => Align(
    alignment: Alignment.topLeft,
    child: Padding(
      padding: const EdgeInsets.all(4),
      child: FittedBox(
        fit: BoxFit.scaleDown,
        alignment: Alignment.topLeft,
        child: MathView.element(element),
      ),
    ),
  );
}

/// A grid of rich-text cells.
class _TableBox extends StatelessWidget {
  const _TableBox({required this.element});

  final TableElement element;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final base = RichTextStyles.base(context).copyWith(fontSize: 13);

    return Table(
      border: TableBorder.all(color: scheme.outlineVariant),
      columnWidths: <int, TableColumnWidth>{
        for (var i = 0; i < element.columnWidths.length; i++)
          i: FixedColumnWidth(element.columnWidths[i]),
      },
      children: <TableRow>[
        for (var r = 0; r < element.rows.length; r++)
          TableRow(
            decoration: r == 0 && element.headerRow
                ? BoxDecoration(color: scheme.surfaceContainerHigh)
                : null,
            children: <Widget>[
              for (var c = 0; c < element.columnWidths.length; c++)
                Padding(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 6,
                    vertical: 4,
                  ),
                  child: c < element.rows[r].length
                      ? Text.rich(
                          RichTextStyles.plainSpanFor(element.rows[r][c], base),
                          textScaler: TextScaler.noScaling,
                        )
                      : const SizedBox.shrink(),
                ),
            ],
          ),
      ],
    );
  }
}
