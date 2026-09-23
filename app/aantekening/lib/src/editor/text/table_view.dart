/// A table in a text box, laid out as a ruled grid.
library;

import 'dart:math' as math;

import 'package:flutter/foundation.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';

import 'block_paragraph.dart';

/// The cells of a table, given in reading order, laid out in a grid of
/// [columns] with a line round each.
///
/// A column is as wide as [widths] says where its border has been dragged,
/// and otherwise fitted to what it holds, as a web page lays out a table:
/// as wide as its longest line where there is room, else narrowed toward
/// its longest word, the columns sharing what room there is — and no
/// narrower than [RenderTextTable.fittedWidth] while there is room for that,
/// so a new, empty column can be typed in. Dragged widths
/// give way too, in a box grown too narrow for them. Over a column's
/// right-hand line, the pointer shows that it can be dragged.
class TextTableView extends MultiChildRenderObjectWidget {
  const TextTableView({
    required this.columns,
    required this.widths,
    required this.lineColor,
    required super.children,
    this.selected = const <int>{},
    this.selectionColor = const Color(0x00000000),
    super.key,
  });

  final int columns;

  /// Each column's width in page units, or null to fit it.
  final List<double?> widths;

  final Color lineColor;

  /// The cells drawn selected, whole, each as its place in reading order.
  final Set<int> selected;
  final Color selectionColor;

  @override
  RenderTextTable createRenderObject(BuildContext context) => RenderTextTable(
    columns: columns,
    widths: widths,
    lineColor: lineColor,
    selected: selected,
    selectionColor: selectionColor,
  );

  @override
  void updateRenderObject(BuildContext context, RenderTextTable renderObject) {
    renderObject
      ..columns = columns
      ..widths = widths
      ..lineColor = lineColor
      ..selected = selected
      ..selectionColor = selectionColor;
  }
}

class _CellData extends ContainerBoxParentData<RenderBox> {}

class RenderTextTable extends RenderBox
    with
        ContainerRenderObjectMixin<RenderBox, _CellData>,
        RenderBoxContainerDefaultsMixin<RenderBox, _CellData>
    implements MouseTrackerAnnotation {
  RenderTextTable({
    required this._columns,
    required this._widths,
    required this._lineColor,
    required this._selected,
    required this._selectionColor,
  });

  /// The narrowest a column fitted to its text is drawn where there is room:
  /// about an inch, so a new, empty column has room to be typed in.
  static const double fittedWidth = 96;

  /// Room between a cell's lines and its text.
  static const EdgeInsets cellPadding = EdgeInsets.fromLTRB(6, 3, 6, 3);

  /// How thick the lines are, in page units.
  static const double line = 1;

  /// How near a column's line, in screen pixels, a press takes hold of it.
  static const double edgeReach = 4;

  int _columns;
  set columns(int value) {
    if (value == _columns) return;
    _columns = value;
    markNeedsLayout();
  }

  List<double?> _widths;
  set widths(List<double?> value) {
    if (listEquals(value, _widths)) return;
    _widths = value;
    markNeedsLayout();
  }

  Color _lineColor;
  set lineColor(Color value) {
    if (value == _lineColor) return;
    _lineColor = value;
    markNeedsPaint();
  }

  /// The cells drawn selected, whole, each as its place in reading order.
  Set<int> get selected => _selected;
  Set<int> _selected;
  set selected(Set<int> value) {
    if (setEquals(value, _selected)) return;
    _selected = value;
    markNeedsPaint();
  }

  Color _selectionColor;
  set selectionColor(Color value) {
    if (value == _selectionColor) return;
    _selectionColor = value;
    markNeedsPaint();
  }

  List<double> _columnWidths = const <double>[];
  List<double> _rowHeights = const <double>[];

  /// Where each column's right-hand line runs, from the table's left.
  List<double> get columnEdges {
    var x = line / 2;
    return <double>[for (final width in _columnWidths) x += width + line];
  }

  /// Where each column's left-hand line runs, from the table's left.
  double columnStart(int column) {
    var x = line / 2;
    for (var i = 0; i < column; i++) {
      x += _columnWidths[i] + line;
    }
    return x;
  }

  /// The column [dx], from the table's left, falls in, or the nearest.
  int columnAt(double dx) {
    var x = line;
    for (var column = 0; column < _columnWidths.length - 1; column++) {
      x += _columnWidths[column] + line;
      if (dx < x) return column;
    }
    return math.max(0, _columnWidths.length - 1);
  }

  /// The row [dy], from the table's top, falls in, or the nearest.
  int rowAt(double dy) {
    var y = line;
    for (var row = 0; row < _rowHeights.length - 1; row++) {
      y += _rowHeights[row] + line;
      if (dy < y) return row;
    }
    return math.max(0, _rowHeights.length - 1);
  }

  /// The cell [local] falls in, or null for a point outside the table.
  ({int row, int column})? cellAt(Offset local) =>
      (Offset.zero & size).contains(local)
      ? (row: rowAt(local.dy), column: columnAt(local.dx))
      : null;

  /// How wide column [column] is laid out, its lines left out.
  double columnWidth(int column) => _columnWidths[column];

  /// The column whose right-hand line [local] is on, within [edgeReach]
  /// on screen, or null.
  int? edgeAt(Offset local) {
    if (local.dy < 0 || local.dy > size.height) return null;
    final reach = edgeReach * screenPixelIn(this);
    final edges = columnEdges;
    for (var i = 0; i < edges.length; i++) {
      if ((local.dx - edges[i]).abs() <= reach) return i;
    }
    return null;
  }

  /// On a column's line, the table itself is hit, for its cursor, and the
  /// text box for the drag; elsewhere only its cells are.
  @override
  bool hitTest(BoxHitTestResult result, {required Offset position}) {
    if (edgeAt(position) != null) {
      result.add(BoxHitTestEntry(this, position));
      return true;
    }
    return (Offset.zero & size).contains(position) &&
        hitTestChildren(result, position: position);
  }

  @override
  MouseCursor get cursor => SystemMouseCursors.resizeColumn;

  @override
  PointerEnterEventListener? get onEnter => null;

  @override
  PointerExitEventListener? get onExit => null;

  @override
  bool get validForMouseTracker => attached;

  @override
  void setupParentData(RenderBox child) {
    if (child.parentData is! _CellData) child.parentData = _CellData();
  }

  List<RenderBox> get _cells => getChildrenAsList();

  int get _rows => _columns == 0 ? 0 : (childCount / _columns).ceil();

  double? _fixed(int column) =>
      column < _widths.length ? _widths[column] : null;

  /// The widths of the columns, their lines left out, in a table no wider
  /// than [maxWidth].
  List<double> _fit(double maxWidth) {
    final cells = _cells;
    final padding = cellPadding.horizontal;
    final least = List<double>.filled(_columns, 0);
    final most = List<double>.filled(_columns, 0);
    for (var i = 0; i < cells.length; i++) {
      final column = i % _columns;
      if (_fixed(column) != null) continue;
      least[column] = math.max(
        least[column],
        cells[i].getMinIntrinsicWidth(double.infinity) + padding,
      );
      most[column] = math.max(
        most[column],
        math.max(
          fittedWidth,
          cells[i].getMaxIntrinsicWidth(double.infinity) + padding,
        ),
      );
    }
    var fixedTotal = 0.0;
    var leastTotal = 0.0;
    var mostTotal = 0.0;
    for (var column = 0; column < _columns; column++) {
      final fixed = _fixed(column);
      if (fixed != null) {
        fixedTotal += fixed;
      } else {
        leastTotal += least[column];
        mostTotal += most[column];
      }
    }
    final available = maxWidth - line * (_columns + 1);
    // Dragged widths too wide for the box together are narrowed alike.
    final squeeze = fixedTotal > 0 && available - leastTotal < fixedTotal
        ? math.max(0.0, available - leastTotal) / fixedTotal
        : 1.0;
    final room = available - fixedTotal * squeeze;
    final double share;
    if (!room.isFinite || room >= mostTotal) {
      share = 1;
    } else if (room <= leastTotal || mostTotal <= leastTotal) {
      share = 0;
    } else {
      share = (room - leastTotal) / (mostTotal - leastTotal);
    }
    return <double>[
      for (var column = 0; column < _columns; column++)
        switch (_fixed(column)) {
          final fixed? => fixed * squeeze,
          null => least[column] + (most[column] - least[column]) * share,
        },
    ];
  }

  @override
  double computeMinIntrinsicWidth(double height) =>
      _intrinsicWidth((cell) => cell.getMinIntrinsicWidth(double.infinity));

  @override
  double computeMaxIntrinsicWidth(double height) => _intrinsicWidth(
    (cell) => math.max(
      fittedWidth - cellPadding.horizontal,
      cell.getMaxIntrinsicWidth(double.infinity),
    ),
  );

  double _intrinsicWidth(double Function(RenderBox cell) measure) {
    final widths = List<double>.filled(_columns, 0);
    final cells = _cells;
    for (var i = 0; i < cells.length; i++) {
      final column = i % _columns;
      widths[column] = math.max(
        widths[column],
        _fixed(column) ?? measure(cells[i]) + cellPadding.horizontal,
      );
    }
    return widths.fold(line, (total, width) => total + width + line);
  }

  @override
  double computeMinIntrinsicHeight(double width) => _heightAt(width);

  @override
  double computeMaxIntrinsicHeight(double width) => _heightAt(width);

  double _heightAt(double width) {
    final columns = _fit(width);
    final cells = _cells;
    final heights = List<double>.filled(_rows, 0);
    for (var i = 0; i < cells.length; i++) {
      final inner = math.max(
        0.0,
        columns[i % _columns] - cellPadding.horizontal,
      );
      heights[i ~/ _columns] = math.max(
        heights[i ~/ _columns],
        cells[i].getMinIntrinsicHeight(inner) + cellPadding.vertical,
      );
    }
    return heights.fold(line, (total, height) => total + height + line);
  }

  @override
  Size computeDryLayout(BoxConstraints constraints) {
    final columns = _fit(constraints.maxWidth);
    return constraints.constrain(
      Size(
        columns.fold(line, (total, width) => total + width + line),
        _heightAt(constraints.maxWidth),
      ),
    );
  }

  @override
  void performLayout() {
    _columnWidths = _fit(constraints.maxWidth);
    final cells = _cells;
    final heights = List<double>.filled(_rows, 0);
    for (var i = 0; i < cells.length; i++) {
      final width = math.max(
        0.0,
        _columnWidths[i % _columns] - cellPadding.horizontal,
      );
      cells[i].layout(
        BoxConstraints.tightFor(width: width),
        parentUsesSize: true,
      );
      heights[i ~/ _columns] = math.max(
        heights[i ~/ _columns],
        cells[i].size.height + cellPadding.vertical,
      );
    }
    _rowHeights = heights;

    var y = line;
    for (var row = 0; row < _rows; row++) {
      var x = line;
      for (var column = 0; column < _columns; column++) {
        final index = row * _columns + column;
        if (index < cells.length) {
          (cells[index].parentData! as _CellData).offset = Offset(
            x + cellPadding.left,
            y + cellPadding.top,
          );
        }
        x += _columnWidths[column] + line;
      }
      y += heights[row] + line;
    }
    size = constraints.constrain(
      Size(_columnWidths.fold(line, (total, width) => total + width + line), y),
    );
  }

  @override
  void paint(PaintingContext context, Offset offset) {
    if (_selected.isNotEmpty) {
      final fill = Paint()..color = _selectionColor;
      var y = line;
      for (var row = 0; row < _rows; row++) {
        for (final column in <int>[
          for (var c = 0; c < _columns; c++)
            if (_selected.contains(row * _columns + c)) c,
        ]) {
          context.canvas.drawRect(
            Rect.fromLTWH(
              columnStart(column) + line / 2,
              y,
              _columnWidths[column],
              _rowHeights[row],
            ).shift(offset),
            fill,
          );
        }
        y += _rowHeights[row] + line;
      }
    }
    defaultPaint(context, offset);
    final paint = Paint()
      ..color = _lineColor
      ..strokeWidth = line;
    final canvas = context.canvas;
    var y = line / 2;
    for (var row = 0; row <= _rows; row++) {
      canvas.drawLine(
        offset + Offset(0, y),
        offset + Offset(size.width, y),
        paint,
      );
      if (row < _rows) y += _rowHeights[row] + line;
    }
    for (final x in <double>[line / 2, ...columnEdges]) {
      canvas.drawLine(
        offset + Offset(x, 0),
        offset + Offset(x, size.height),
        paint,
      );
    }
  }

  @override
  bool hitTestChildren(BoxHitTestResult result, {required Offset position}) =>
      defaultHitTestChildren(result, position: position);
}
