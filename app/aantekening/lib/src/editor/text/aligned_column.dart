/// Rows one beneath another, each placed across the widest as it is
/// aligned.
library;

import 'package:flutter/rendering.dart';
import 'package:flutter/widgets.dart';

/// Its children one beneath another, as wide as the widest of them, each
/// laid out as wide as it needs and placed across that width by its
/// [AlignedRow.across].
///
/// A box that sizes itself to its text lays its paragraphs out this way: a
/// centred paragraph is as wide as its own longest line, and centred in the
/// box, so each of its lines is centred in the box.
class AlignedColumn extends MultiChildRenderObjectWidget {
  const AlignedColumn({this.minWidth = 0, super.children, super.key});

  /// The narrowest it is, however narrow its rows.
  final double minWidth;

  @override
  RenderAlignedColumn createRenderObject(BuildContext context) =>
      RenderAlignedColumn(minWidth);

  @override
  void updateRenderObject(
    BuildContext context,
    RenderAlignedColumn renderObject,
  ) {
    renderObject.minWidth = minWidth;
  }
}

/// Places [child] in an [AlignedColumn]: at its start for an [across] of 0,
/// in its middle for 0.5, at its end for 1.
class AlignedRow extends ParentDataWidget<AlignedRowData> {
  const AlignedRow({required this.across, required super.child, super.key});

  final double across;

  @override
  void applyParentData(RenderObject renderObject) {
    final data = renderObject.parentData! as AlignedRowData;
    if (data.across == across) return;
    data.across = across;
    renderObject.parent?.markNeedsLayout();
  }

  @override
  Type get debugTypicalAncestorWidgetClass => AlignedColumn;
}

class AlignedRowData extends ContainerBoxParentData<RenderBox> {
  double across = 0;
}

class RenderAlignedColumn extends RenderBox
    with
        ContainerRenderObjectMixin<RenderBox, AlignedRowData>,
        RenderBoxContainerDefaultsMixin<RenderBox, AlignedRowData> {
  RenderAlignedColumn(this._minWidth);

  double _minWidth;
  set minWidth(double value) {
    if (value == _minWidth) return;
    _minWidth = value;
    markNeedsLayout();
  }

  @override
  void setupParentData(RenderBox child) {
    if (child.parentData is! AlignedRowData) {
      child.parentData = AlignedRowData();
    }
  }

  double _widest(double Function(RenderBox child) width) {
    var widest = 0.0;
    for (var child = firstChild; child != null; child = childAfter(child)) {
      final each = width(child);
      if (each > widest) widest = each;
    }
    return widest;
  }

  double _total(double Function(RenderBox child) height) {
    var total = 0.0;
    for (var child = firstChild; child != null; child = childAfter(child)) {
      total += height(child);
    }
    return total;
  }

  @override
  double computeMinIntrinsicWidth(double height) =>
      _widest((child) => child.getMinIntrinsicWidth(double.infinity));

  @override
  double computeMaxIntrinsicWidth(double height) =>
      _widest((child) => child.getMaxIntrinsicWidth(double.infinity));

  @override
  double computeMinIntrinsicHeight(double width) =>
      _total((child) => child.getMinIntrinsicHeight(width));

  @override
  double computeMaxIntrinsicHeight(double width) =>
      _total((child) => child.getMaxIntrinsicHeight(width));

  @override
  void performLayout() {
    final rows = BoxConstraints(maxWidth: constraints.maxWidth);
    var width = constraints.constrainWidth(_minWidth);
    var child = firstChild;
    while (child != null) {
      child.layout(rows, parentUsesSize: true);
      if (child.size.width > width) width = child.size.width;
      child = childAfter(child);
    }
    var y = 0.0;
    child = firstChild;
    while (child != null) {
      final data = child.parentData! as AlignedRowData;
      data.offset = Offset((width - child.size.width) * data.across, y);
      y += child.size.height;
      child = data.nextSibling;
    }
    size = constraints.constrain(Size(width, y));
  }

  @override
  void paint(PaintingContext context, Offset offset) =>
      defaultPaint(context, offset);

  @override
  bool hitTestChildren(BoxHitTestResult result, {required Offset position}) =>
      defaultHitTestChildren(result, position: position);
}
