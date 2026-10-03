part of 'tikz_picture.dart';

/// The `matrix` library: nodes set out in rows and columns, as a
/// commutative diagram is.
extension _Matrix on _Painter {
  /// `\matrix (m) [matrix of math nodes, …] at (x,y) { a & b \\ c & d \\ };`:
  /// each cell's node named `m-row-column`, or what a `\node` in it is
  /// called; rows as tall and columns as wide as their largest node.
  void _matrix(String text) {
    final spec = _nodeSpec(TikzScanner(text));
    final style = _scope.copy()
      ..apply(TikzSource.options(spec.options), onPath: true);
    final cellStyle = style.forNode()
      ..draws = false
      ..fills = false;
    final every = cellStyle.styles['every node'];
    if (every != null) cellStyle.apply(every, onPath: true);
    cellStyle.apply(style.nodeOptions, onPath: true);

    // What each cell holds, in reading order.
    final cells = <({int row, int column, _NodeSpec node, _Style style})>[];
    final rows = TikzSource.split(spec.text, r'\\');
    if (rows.isNotEmpty && rows.last.trim().isEmpty) rows.removeLast();
    for (var r = 0; r < rows.length; r++) {
      final columns = TikzSource.split(rows[r], style.ampersand);
      for (var c = 0; c < columns.length; c++) {
        final cell = _cell(columns[c], style);
        if (cell == null) continue;
        final own = cellStyle.copy()
          ..apply(TikzSource.options(cell.options), onPath: true);
        cells.add((row: r, column: c, node: cell, style: own));
      }
    }
    if (cells.isEmpty) return;

    final widths = <int, double>{};
    final heights = <int, double>{};
    for (var i = 0; i < cells.length; i++) {
      final (:row, :column, node: _, style: own) = cells[i];
      final half = _halfSize(_labels.length + i, own);
      widths[column] = math.max(widths[column] ?? 0, half.width * 2);
      heights[row] = math.max(heights[row] ?? 0, half.height * 2);
    }
    double sum(Map<int, double> sizes, int before, double gap) {
      var total = 0.0;
      for (var i = 0; i < before; i++) {
        total += (sizes[i] ?? 0) + gap;
      }
      return total;
    }

    final columnCount = widths.keys.reduce(math.max) + 1;
    final width = sum(widths, columnCount, style.columnSep) - style.columnSep;
    final height = sum(heights, rows.length, style.rowSep) - style.rowSep;
    final centre = spec.at == null
        ? Offset.zero
        : _point(spec.at!, null, relative: 0).point;
    final topLeft = centre + Offset(-width / 2, height / 2);
    final into = _layerOf(style);

    for (final (:row, :column, :node, style: own) in cells) {
      final at =
          topLeft +
          Offset(
            sum(widths, column, style.columnSep) + widths[column]! / 2,
            -sum(heights, row, style.rowSep) - heights[row]! / 2,
          );
      final placed = _place(node.text, own..anchor = 'center', at, into: into);
      final name =
          node.name ??
          (spec.name == null ? null : '${spec.name}-${row + 1}-${column + 1}');
      if (name != null) _nodes[name] = placed;
    }
    if (spec.name case final name?) {
      _nodes[name] = _Node(
        centre,
        width / 2 + style.innerSep,
        height / 2 + style.innerSep,
        'rectangle',
        0,
      );
    }
  }

  /// The node the cell [source] of a matrix in [style] holds: its text, in a matrix of nodes, after `|[options]|` if it
  /// has them, or else a `\node` in it; null for an empty one.
  _NodeSpec? _cell(String source, _Style style) {
    var text = source.trim();
    if (text.isEmpty) return null;
    if (style.matrixOf != null) {
      var options = '';
      final marked = RegExp(r'^\|\[(.*?)\]\|', dotAll: true).firstMatch(text);
      if (marked != null) {
        options = marked.group(1)!;
        text = text.substring(marked.end).trim();
      }
      if (text.isEmpty) return null;
      return (
        options: options,
        name: null,
        at: null,
        text: style.matrixOf == 'matrix of math nodes' ? '\$$text\$' : text,
      );
    }
    final scanner = TikzScanner(text);
    if (scanner.command() != 'node') {
      throw const FormatException(r'A cell of a matrix holds a \node');
    }
    return _nodeSpec(scanner);
  }
}
