/// TikZ pictures: read from their source and worked out into what they
/// draw.
///
/// What is read is the part of TikZ that notes are drawn with: `\draw`,
/// `\fill`, `\filldraw`, `\path`, `\shade`, `\node`, `\coordinate`, scopes,
/// `\foreach` and styles; lines, curves, rectangles, circles, ellipses,
/// arcs, grids, parabolas and plots; nodes placed on paths, beside each
/// other and labelled; colours, line widths, dashes, arrow tips, opacity,
/// shading and transformations.
library;

import 'dart:math' as math;
import 'dart:typed_data';
import 'dart:ui';

import 'package:aantekening_core/aantekening_core.dart' show LatexSource;

import 'tikz_expression.dart';
import 'tikz_source.dart';

part 'tikz_axis.dart';
part 'tikz_decorations.dart';
part 'tikz_ink.dart';
part 'tikz_intersections.dart';
part 'tikz_matrix.dart';
part 'tikz_nodes.dart';
part 'tikz_node_shapes.dart';
part 'tikz_pics.dart';
part 'tikz_shapes.dart';
part 'tikz_style.dart';

/// What a picture draws, in points, with y running downwards.
class TikzDrawing {
  const TikzDrawing({
    required this.marks,
    required this.labels,
    required this.bounds,
  });

  /// The lines and fills, in the order they are drawn.
  final List<TikzMark> marks;

  /// The text of each node, drawn over the marks.
  final List<TikzLabel> labels;

  /// What the marks and labels cover.
  final Rect bounds;
}

/// A path filled or stroked.
class TikzMark {
  const TikzMark.fill(this.path, this.colour, {this.shading})
    : width = null,
      cap = StrokeCap.butt,
      join = StrokeJoin.miter;

  const TikzMark.stroke(
    this.path,
    this.colour, {
    required double this.width,
    this.cap = StrokeCap.butt,
    this.join = StrokeJoin.miter,
  }) : shading = null;

  final Path path;
  final Color colour;

  /// How wide the line is, or null for a fill.
  final double? width;
  final StrokeCap cap;
  final StrokeJoin join;

  /// The colours a fill runs between, if it is shaded.
  final TikzShading? shading;
}

/// A fill running from one colour to another.
class TikzShading {
  const TikzShading(this.from, this.to, this.kind);

  final Color from;
  final Color to;
  final TikzShadingKind kind;
}

enum TikzShadingKind { horizontal, vertical, ball }

/// The text of a node: LaTeX, typeset in [colour] at [scale] times the
/// size of the text around the picture, centred at [centre].
class TikzLabel {
  const TikzLabel({
    required this.latex,
    required this.colour,
    required this.scale,
    required this.centre,
  });

  final String latex;
  final Color colour;
  final double scale;
  final Offset centre;
}

/// A TikZ picture, read from its source.
class TikzPicture {
  TikzPicture._(this._options, this._body);

  final String _options;
  final String _body;

  static final RegExp _begin = RegExp(r'^\\begin\s*\{tikzpicture\}');
  static final RegExp _end = RegExp(r'\\end\s*\{tikzpicture\}');
  static final RegExp _inline = RegExp(r'^\\tikz(?![a-zA-Z])');

  /// Whether [latex] is a TikZ picture: a `tikzpicture` environment, or a
  /// `\tikz` command.
  static bool holds(String latex) => LatexSource.isPicture(latex);

  /// The picture [latex] holds. Throws a [FormatException] where it cannot
  /// be read or drawn.
  static TikzPicture read(String latex) => _read(latex)..draw();

  static TikzPicture _read(String latex) {
    final source = latex.trim();
    final inline = _inline.matchAsPrefix(source);
    final scanner = TikzScanner(source, inline?.end ?? 0);
    final String body;
    if (inline != null) {
      final options = scanner.optional('[', ']') ?? '';
      body = scanner.sees('{')
          ? scanner.group('{', '}')
          : source.substring(scanner.at);
      return TikzPicture._(options, TikzSource.expandLoops(body));
    }
    final begin = _begin.matchAsPrefix(source);
    if (begin == null) {
      throw const FormatException(r'A picture starts \begin{tikzpicture}');
    }
    scanner.at = begin.end;
    final options = scanner.optional('[', ']') ?? '';
    final end = _end.allMatches(source, scanner.at).lastOrNull;
    if (end == null) throw const FormatException(r'Missing \end{tikzpicture}');
    if (source.substring(end.end).trim().isNotEmpty) {
      throw const FormatException('Only the picture goes in its formula');
    }
    body = source.substring(scanner.at, end.start);
    return TikzPicture._(options, TikzSource.expandLoops(body));
  }

  /// What keeps [latex] from being drawn, or null where nothing does.
  static String? problemIn(String latex) {
    try {
      read(latex);
      return null;
    } on FormatException catch (e) {
      return e.message;
    }
  }

  /// What the picture draws, black lines and text drawn in [ink]. Each
  /// node's label is as large as [labelSizes] says, in points, if it is
  /// given; without them the labels are placed as if empty.
  TikzDrawing draw({List<Size>? labelSizes, Color ink = _black}) =>
      _Painter(ink, labelSizes).run(_options, _body);

  static const Color _black = Color(0xFF000000);
}

/// Works a picture's statements out into a [TikzDrawing].
class _Painter {
  _Painter(this.ink, this.labelSizes);

  final Color ink;
  final List<Size>? labelSizes;

  final List<TikzMark> _marks = <TikzMark>[];
  final List<TikzLabel> _labels = <TikzLabel>[];
  final Map<String, _Node> _nodes = <String, _Node>{};
  final Map<String, double> _variables = <String, double>{};

  /// The paths named for `name intersections`, as drawn.
  final Map<String, Path> _namedPaths = <String, Path>{};

  /// The limits of the axis being drawn, for `rel axis cs:`.
  Rect? _axisLimits;

  /// What is drawn on the background layer, beneath everything else.
  final List<TikzMark> _background = <TikzMark>[];
  late _Style _scope;

  /// Where what is drawn in [style] goes: on the background layer, or
  /// above what is already drawn.
  List<TikzMark> _layerOf(_Style style) =>
      style.onBackground ? _background : _marks;

  TikzDrawing run(String options, String body) {
    _scope = _Style(ink)..apply(TikzSource.options(options), onPath: false);
    _statements(TikzScanner(body), inScope: false);
    _marks.insertAll(0, _background);
    var bounds = Rect.zero;
    var first = true;
    void cover(Rect rect) {
      bounds = first ? rect : bounds.expandToInclude(rect);
      first = false;
    }

    for (final mark in _marks) {
      final rect = mark.path.getBounds();
      if (rect.isEmpty && mark.width == null) continue;
      cover(rect.inflate((mark.width ?? 0) / 2));
    }
    for (var i = 0; i < _labels.length; i++) {
      final size = _labelSize(i);
      cover(
        Rect.fromCenter(
          center: _labels[i].centre,
          width: size.width,
          height: size.height,
        ),
      );
    }
    return TikzDrawing(marks: _marks, labels: _labels, bounds: bounds);
  }

  Size _labelSize(int index) {
    final sizes = labelSizes;
    return sizes != null && index < sizes.length ? sizes[index] : Size.zero;
  }

  /// Works out the statements [scanner] reads, to the end of the scope
  /// they are in when [inScope].
  void _statements(TikzScanner scanner, {required bool inScope}) {
    while (!scanner.done) {
      if (scanner.take(';')) continue;
      final command = scanner.command();
      switch (command) {
        case 'begin':
          final environment = scanner.group('{', '}').trim();
          if (environment == 'axis') {
            _axis(scanner);
            continue;
          }
          final outer = _scope;
          _scope = outer.copy();
          switch (environment) {
            case 'scope':
              _scope.apply(
                TikzSource.options(scanner.optional('[', ']') ?? ''),
                onPath: false,
              );
            case 'pgfonlayer':
              _scope.onBackground =
                  scanner.group('{', '}').trim() == 'background';
            default:
              throw FormatException(
                'A picture cannot hold a $environment environment',
              );
          }
          _statements(scanner, inScope: true);
          _scope = outer;
        case 'end':
          scanner.group('{', '}');
          if (!inScope) throw const FormatException(r'An \end without \begin');
          return;
        case 'draw' ||
            'fill' ||
            'filldraw' ||
            'path' ||
            'shade' ||
            'shadedraw' ||
            'clip' ||
            'useasboundingbox':
          _path(command!, scanner.statement());
        case 'node' || 'coordinate' || 'pic':
          _path('path', '$command ${scanner.statement()}');
        case 'matrix':
          _matrix(scanner.statement());
        case 'pgfdeclarelayer' ||
            'pgfsetlayers' ||
            'pgfplotsset' ||
            'usepgfplotslibrary':
          scanner.group('{', '}');
        case 'tikzset':
          _scope.apply(
            TikzSource.options(scanner.group('{', '}')),
            onPath: false,
          );
        case 'tikzstyle':
          final name = scanner.group('{', '}').trim();
          scanner.take('=');
          _scope.styles[name] = TikzSource.options(scanner.group('[', ']'));
        case 'usetikzlibrary':
          scanner.group('{', '}');
        case 'pgfmathsetmacro' || 'def':
          final name = command == 'def'
              ? scanner.command()
              : scanner.group('{', '}').trim().replaceFirst(r'\', '');
          if (name == null) throw const FormatException(r'\def needs a name');
          _variables[name] = TikzExpression.evaluate(
            scanner.group('{', '}'),
            _variables,
          ).value;
        case null:
          throw FormatException('Cannot read "${_start(scanner)}"');
        default:
          throw FormatException('TikZ here has no \\$command');
      }
    }
    if (inScope) throw const FormatException(r'Missing \end{scope}');
  }

  static String _start(TikzScanner scanner) {
    final rest = scanner.source.substring(scanner.at);
    return rest.length > 24 ? '${rest.substring(0, 24)}…' : rest;
  }

  /// Works out the path statement [command] starts, [text] being the rest
  /// of it.
  void _path(String command, String text) {
    final style = _scope.copy()
      ..draws = command.contains('draw')
      ..fills = command.contains('fill');
    if (command.startsWith('shade')) {
      style
        ..shading = const TikzShading(
          Color(0xFF808080),
          Color(0xFFFFFFFF),
          TikzShadingKind.vertical,
        )
        ..fills = true;
    }
    final path = _Path(style);
    _items(TikzScanner(text), path);
    _finish(path);
  }

  /// Works out the items of a path, one after another.
  void _items(TikzScanner scanner, _Path path) {
    final style = path.style;
    while (!scanner.done) {
      if (scanner.sees('[')) {
        style.apply(TikzSource.options(scanner.group('[', ']')), onPath: true);
        if (style.intersections case final spec?) {
          style.intersections = null;
          _intersect(spec);
        }
      } else if (scanner.takeWord('pic')) {
        final pic = style.copy()..quotes = const <String>[];
        final options = scanner.optional('[', ']');
        if (options != null) {
          pic.apply(TikzSource.options(options), onPath: true);
        }
        _pic(scanner.group('{', '}'), pic);
      } else if (scanner.sees('{')) {
        _items(TikzScanner(scanner.group('{', '}')), path);
      } else if (scanner.take('--')) {
        path.connector = '--';
      } else if (scanner.take('-|')) {
        path.connector = '-|';
      } else if (scanner.take('|-')) {
        path.connector = '|-';
      } else if (scanner.take('..')) {
        _curve(scanner, path);
      } else if (scanner.sees('(') || scanner.sees('+')) {
        final target = _coordinate(scanner, path);
        if (path.connector == null) {
          _moveTo(path, target);
        } else {
          _connect(path, target);
        }
      } else if (scanner.takeWord('cycle')) {
        _close(path);
      } else if (scanner.takeWord('rectangle')) {
        _rectangle(path, _coordinate(scanner, path));
      } else if (scanner.takeWord('circle') || scanner.takeWord('ellipse')) {
        _ellipse(scanner, path);
      } else if (scanner.takeWord('arc')) {
        _arc(scanner, path);
      } else if (scanner.takeWord('grid')) {
        final options = scanner.optional('[', ']');
        final grid = style.copy();
        if (options != null) {
          grid.apply(TikzSource.options(options), onPath: true);
        }
        _grid(path, grid, _coordinate(scanner, path));
      } else if (scanner.takeWord('sin')) {
        _wave(path, _coordinate(scanner, path), sine: true);
      } else if (scanner.takeWord('cos')) {
        _wave(path, _coordinate(scanner, path), sine: false);
      } else if (scanner.takeWord('parabola')) {
        _parabola(scanner, path);
      } else if (scanner.takeWord('plot')) {
        _plot(scanner, path);
      } else if (scanner.takeWord('to')) {
        _to(scanner, path, edge: false);
      } else if (scanner.takeWord('edge')) {
        _to(scanner, path, edge: true);
      } else if (scanner.takeWord('node')) {
        final spec = _nodeSpec(scanner);
        if (path.connector != null) {
          path.pending.add(spec);
        } else {
          _node(spec, path, stretch: path.lastStretch, along: null);
        }
      } else if (scanner.takeWord('coordinate')) {
        final spec = _nodeSpec(scanner, text: false);
        final at = spec.at == null
            ? path.current
            : _point(spec.at!, path, relative: 0).point;
        if (spec.name != null && at != null) {
          _nodes[spec.name!] = _Node.point(at);
        }
      } else {
        throw FormatException('Cannot read "${_start(scanner)}"');
      }
    }
  }

  // Coordinates.

  /// The coordinate that comes next, and what `+` and `++` make of it.
  ({Offset point, _Node? node}) _coordinate(TikzScanner scanner, _Path path) {
    final relative = scanner.take('++')
        ? 2
        : scanner.take('+')
        ? 1
        : 0;
    final found = _point(scanner.group('(', ')'), path, relative: relative);
    if (relative != 1) path.reference = found.point;
    return found;
  }

  /// The point [inner], from inside `(…)`: `x,y`, `angle:radius`, a node or
  /// one of its anchors, or a calculation `$…$`; taken from the path's
  /// reference point when [relative].
  ({Offset point, _Node? node}) _point(
    String inner,
    _Path? path, {
    required int relative,
  }) {
    var text = inner.trim();
    // Options for the coordinate alone are not drawn with.
    if (text.startsWith('[')) {
      text = text.substring(TikzScanner.matching(text, 0, '[', ']') + 1).trim();
    }
    if (text.startsWith(r'$') && text.endsWith(r'$') && text.length > 1) {
      return (
        point: _calculated(text.substring(1, text.length - 1), path),
        node: null,
      );
    }
    if (text.startsWith('axis cs:')) text = text.substring(8).trim();
    if (text.startsWith('rel axis cs:')) {
      final limits = _axisLimits;
      final parts = TikzSource.split(text.substring(12), ',');
      if (limits == null || parts.length != 2) {
        throw const FormatException('"rel axis cs:" is in an axis, x,y');
      }
      double share(String part) =>
          TikzExpression.evaluate(part, _variables).value;
      text =
          '${TikzExpression.format(limits.left + limits.width * share(parts[0]))},'
          '${TikzExpression.format(limits.top + limits.height * share(parts[1]))}';
    }
    final style = path?.style ?? _scope;
    if (TikzSource.topLevel(text, ',') >= 0 ||
        TikzSource.topLevel(text, ':') >= 0) {
      final vector = style.vector(text, _variables);
      if (relative == 0) {
        return (point: style.transform.apply(vector), node: null);
      }
      final from = path?.reference ?? path?.current ?? Offset.zero;
      return (point: from + style.transform.linear(vector), node: null);
    }
    final node = _nodes[text];
    if (node != null) {
      return (
        point: node.centre,
        node: node.shape == 'coordinate' ? null : node,
      );
    }
    final dot = text.lastIndexOf('.');
    final named = dot < 0 ? null : _nodes[text.substring(0, dot)];
    if (named == null) {
      throw FormatException('Nothing in the picture is called "$text"');
    }
    return (point: named.anchor(text.substring(dot + 1)), node: null);
  }

  /// The point a calculation such as `(a)!0.5!(b)` or `(a) + (1,2)` comes
  /// to: partway points, `(a)!1cm!(b)` a length along, `(a)!0.5!90:(b)`
  /// turned about `(a)`, and `(a)!(c)!(b)` the foot of `(c)` on the line.
  Offset _calculated(String text, _Path? path) {
    final scanner = TikzScanner(text);
    var total = Offset.zero;
    while (!scanner.done) {
      var sign = 1.0;
      if (scanner.take('-')) {
        sign = -1;
      } else {
        scanner.take('+');
      }
      var factor = 1.0;
      if (!scanner.sees('(')) {
        final star = text.indexOf('*', scanner.at);
        if (star < 0) throw FormatException('Cannot work out "$text"');
        factor = TikzExpression.evaluate(
          text.substring(scanner.at, star),
          _variables,
        ).value;
        scanner.at = star + 1;
      }
      var point = _point(scanner.group('(', ')'), path, relative: 0).point;
      while (scanner.take('!')) {
        if (scanner.sees('(')) {
          final foot = _point(scanner.group('(', ')'), path, relative: 0);
          if (!scanner.take('!')) {
            throw FormatException('Cannot work out "$text"');
          }
          final to = _point(scanner.group('(', ')'), path, relative: 0).point;
          final d = to - point;
          final square = d.dx * d.dx + d.dy * d.dy;
          final from = foot.point - point;
          point += square == 0
              ? Offset.zero
              : d * ((from.dx * d.dx + from.dy * d.dy) / square);
          continue;
        }
        final bang = text.indexOf('!', scanner.at);
        if (bang < 0) throw FormatException('Cannot work out "$text"');
        final along = TikzExpression.evaluate(
          text.substring(scanner.at, bang),
          _variables,
        );
        scanner.at = bang + 1;
        var turn = 0.0;
        if (!scanner.sees('(')) {
          final colon = text.indexOf(':', scanner.at);
          if (colon < 0) throw FormatException('Cannot work out "$text"');
          turn = TikzExpression.evaluate(
            text.substring(scanner.at, colon),
            _variables,
          ).value;
          scanner.at = colon + 1;
        }
        final to = _point(scanner.group('(', ')'), path, relative: 0).point;
        final d = _Affine.rotation(turn).apply(to - point);
        point = along.length
            ? point + d / math.max(d.distance, 1e-9) * along.value
            : point + d * along.value;
      }
      total += point * (sign * factor);
    }
    return total;
  }

  // Finishing a path.

  void _finish(_Path path) {
    _Shapes._flushCorner(path);
    if (path.connector != null && path.pending.isNotEmpty) {
      throw const FormatException('A path ends waiting for a coordinate');
    }
    final style = path.style;
    if (path.hasDrawn) {
      for (final options in style.preactions) {
        _act(path, _actionStyle(style, options));
      }
      if (style.draws ||
          style.fills ||
          style.pattern != null ||
          style.decorate) {
        _act(path, style);
      }
      for (final options in style.postactions) {
        _act(path, _actionStyle(style, options));
      }
    }
    if (style.namePath case final name?) _namedPaths[name] = path.drawn;
    _layerOf(style).addAll(path.above);
  }

  /// [style] with the options of a `preaction` or `postaction` added.
  static _Style _actionStyle(_Style style, List<TikzOption> options) =>
      style.copy()
        ..decorate = false
        ..preactions = const <List<TikzOption>>[]
        ..postactions = const <List<TikzOption>>[]
        ..apply(options, onPath: true);

  /// Draws [path] as [style] says: as it is, or decorated.
  void _act(_Path path, _Style style) {
    final into = _layerOf(style);
    if (!style.decorate) {
      _emit(
        path.drawn,
        style,
        closed: path.closedAtEnd,
        into: into,
        tips: true,
        ends: path,
      );
      return;
    }
    final morphed = _Decorations.morph(path.drawn, style.decoration);
    if (morphed == null) {
      _markAlong(path.drawn, style);
    } else {
      _emit(morphed, style, closed: path.closedAtEnd, into: into, tips: false);
    }
  }

  /// Puts what the `markings` decoration in [style] marks along [drawn]:
  /// arrow tips, `\arrow{>}`, and nodes, `\node{…};`.
  void _markAlong(Path drawn, _Style style) {
    for (final (:at, :what) in _Decorations.marks(drawn, style.decoration)) {
      final scanner = TikzScanner(TikzSource.unbraced(what));
      while (!scanner.done) {
        if (scanner.take(';')) continue;
        final command = scanner.command();
        final mark = style.copy();
        if (command == 'arrow' || command == 'arrowreversed') {
          final options = scanner.optional('[', ']');
          if (options != null) {
            mark.apply(TikzSource.options(options), onPath: true);
          }
          final kind = mark._tip(scanner.group('{', '}')) ?? mark.tip;
          final d = at.vector * (command == 'arrow' ? 1.0 : -1.0);
          final heads = <Path>[];
          _tip(
            heads,
            kind,
            at.position + d * (_tipLength(kind, mark.lineWidth) / 2),
            d,
            mark.lineWidth,
          );
          for (final head in heads) {
            _layerOf(style).add(TikzMark.fill(head, mark.stroke));
          }
        } else if (command == 'node') {
          final spec = _nodeSpec(scanner);
          final node = mark.forNode()
            ..apply(TikzSource.options(spec.options), onPath: true);
          final placed = _place(
            spec.text,
            node,
            _out(at.position),
            into: _layerOf(style),
          );
          if (spec.name != null) _nodes[spec.name!] = placed;
        } else {
          throw const FormatException(r'A mark is an \arrow or a \node');
        }
      }
    }
  }

  /// Adds the marks that fill and stroke [drawn] as [style] says, with the
  /// arrow tips at the [ends] of an open path when [tips].
  void _emit(
    Path drawn,
    _Style style, {
    required bool closed,
    required List<TikzMark> into,
    required bool tips,
    _Path? ends,
  }) {
    // A pattern fills in place of the colour.
    if (style.fills && style.pattern == null) {
      drawn.fillType = style.evenOdd
          ? PathFillType.evenOdd
          : PathFillType.nonZero;
      into.add(TikzMark.fill(drawn, style.filling, shading: style.shading));
    }
    if (style.pattern case final name?) {
      final pattern = _Decorations.pattern(drawn, name);
      if (pattern != null) into.add(TikzMark.fill(pattern, style.patternInk));
    }
    if (!style.draws) return;
    final width = style.lineWidth;
    final start = tips && !closed ? style.startTip : null;
    final end = tips && !closed ? style.endTip : null;
    var stroked = drawn;
    final List<Path> heads = <Path>[];
    if (ends != null && (start != null || end != null)) {
      final first = ends.firstPoint;
      final toward = ends.firstToward;
      final last = ends.lastPoint;
      final from = ends.lastFrom;
      var trimStart = 0.0;
      var trimEnd = 0.0;
      if (start != null && first != null && toward != null) {
        trimStart = _tip(
          heads,
          start,
          _out(first),
          _out(first) - _out(toward),
          width,
        );
      }
      if (end != null && last != null && from != null) {
        trimEnd = _tip(heads, end, _out(last), _out(last) - _out(from), width);
      }
      stroked = _trimmed(drawn, trimStart, trimEnd);
    }
    final dashes = style.dashes;
    if (dashes != null && dashes.isNotEmpty) {
      stroked = _dashed(stroked, dashes);
    }
    into.add(
      TikzMark.stroke(
        stroked,
        style.stroke,
        width: width,
        cap: dashes != null && dashes.first < 1 ? StrokeCap.round : style.cap,
        join: style.join,
      ),
    );
    for (final head in heads) {
      into.add(TikzMark.fill(head, style.stroke));
    }
  }
}

/// [p], with y upwards, as it is drawn, with y downwards.
Offset _out(Offset p) => Offset(p.dx, -p.dy);
