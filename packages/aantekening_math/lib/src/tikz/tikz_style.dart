part of 'tikz_picture.dart';

/// A transformation of the plane: (x, y) to (ax + cy + e, bx + dy + f).
class _Affine {
  const _Affine(this.a, this.b, this.c, this.d, this.e, this.f);

  static const _Affine identity = _Affine(1, 0, 0, 1, 0, 0);

  factory _Affine.rotation(double degrees) {
    final r = degrees * math.pi / 180;
    return _Affine(math.cos(r), math.sin(r), -math.sin(r), math.cos(r), 0, 0);
  }

  final double a;
  final double b;
  final double c;
  final double d;
  final double e;
  final double f;

  Offset apply(Offset p) =>
      Offset(a * p.dx + c * p.dy + e, b * p.dx + d * p.dy + f);

  Offset linear(Offset p) => Offset(a * p.dx + c * p.dy, b * p.dx + d * p.dy);

  /// This after [inner]: points go through [inner] first.
  _Affine after(_Affine inner) => _Affine(
    a * inner.a + c * inner.b,
    b * inner.a + d * inner.b,
    a * inner.c + c * inner.d,
    b * inner.c + d * inner.d,
    a * inner.e + c * inner.f + e,
    b * inner.e + d * inner.f + f,
  );

  _Affine get inverse {
    final det = a * d - b * c;
    if (det == 0) throw const FormatException('A scale of 0 hides it all');
    final ia = d / det;
    final ib = -b / det;
    final ic = -c / det;
    final id = a / det;
    return _Affine(ia, ib, ic, id, -(ia * e + ic * f), -(ib * e + id * f));
  }
}

/// The options in force, as scopes, paths and nodes set them.
class _Style {
  _Style(this.colour);

  static const double _cm = TikzExpression.pointsPerCm;

  // How a path is drawn.
  Color colour;
  Color? drawColour;
  Color? fillColour;
  Color? textColour;
  bool draws = false;
  bool fills = false;
  double lineWidth = 0.4;
  List<double>? dashes;
  String? startTip;
  String? endTip;

  /// The tip `>` stands for.
  String tip = 'to';
  double opacity = 1;
  double drawOpacity = 1;
  double fillOpacity = 1;
  StrokeCap cap = StrokeCap.butt;
  StrokeJoin join = StrokeJoin.miter;
  bool evenOdd = false;
  TikzShading? shading;

  /// How round the corners of lines and rectangles are, if they are.
  double? rounded;

  /// Whether the path is drawn decorated, as [decoration] says.
  bool decorate = false;
  List<TikzOption> decoration = const <TikzOption>[];

  /// The options the path is drawn with again, before and after it is
  /// drawn as it is.
  List<List<TikzOption>> preactions = const <List<TikzOption>>[];
  List<List<TikzOption>> postactions = const <List<TikzOption>>[];

  /// The pattern the path is filled with, and its colour, if it is.
  String? pattern;
  Color? patternColour;

  /// The name the path is known by to `name intersections`, and the
  /// intersections it asks for: `of=a and b`.
  String? namePath;
  String? intersections;

  /// What the `quotes` library's labels say: `"$\alpha$"`, with options
  /// after them.
  List<String> quotes = const <String>[];

  /// Whether what is drawn goes beneath everything else
  /// (`on background layer`).
  bool onBackground = false;

  /// The `angles` library's sizes: how far out an angle's arc is, and its
  /// label, as a share of that.
  double angleRadius = 5 * TikzExpression.pointsPerCm / 10;
  double angleEccentricity = 0.6;

  /// A matrix's options: whether its cells are nodes of their own, in
  /// maths, and the space between its rows and columns.
  String? matrixOf;
  double rowSep = 0;
  double columnSep = 0;
  String ampersand = '&';

  // Where things go.
  _Affine transform = _Affine.identity;
  Offset xUnit = const Offset(_cm, 0);
  Offset yUnit = const Offset(0, _cm);
  String? radius;
  String? xRadius;
  String? yRadius;
  double? startAngle;
  double? endAngle;
  double? deltaAngle;
  String step = '1';
  ({double from, double to}) domain = (from: -5, to: 5);
  int samples = 25;
  String variable = 'x';
  bool smooth = false;
  double? bend;
  double? outAngle;
  double? inAngle;
  double looseness = 1;

  // Nodes.
  String shape = 'rectangle';
  String? anchor;
  ({String side, String? of, double distance})? placement;
  double innerSep = 3.333;
  double minWidth = 0;
  double minHeight = 0;
  double? outerSep;
  double? pos;
  double nodeDistance = _cm;
  double fontScale = 1;
  bool bold = false;
  bool italic = false;
  String align = 'center';
  List<TikzOption> nodeOptions = const <TikzOption>[];
  List<String> labels = const <String>[];

  // The shapes of `shapes.geometric`, and nodes fitted round others or
  // through a point.
  int polygonSides = 5;
  int starPoints = 5;
  double starRatio = 1.5;
  double borderRotate = 0;
  double apexAngle = 30;
  double trapeziumLeft = 60;
  double trapeziumRight = 60;
  String? fit;
  String? through;

  /// Styles defined by name, with `every node` among them.
  Map<String, List<TikzOption>> styles = <String, List<TikzOption>>{};

  _Style copy() => _Style(colour)
    ..drawColour = drawColour
    ..fillColour = fillColour
    ..textColour = textColour
    ..draws = draws
    ..fills = fills
    ..lineWidth = lineWidth
    ..dashes = dashes
    ..startTip = startTip
    ..endTip = endTip
    ..tip = tip
    ..opacity = opacity
    ..drawOpacity = drawOpacity
    ..fillOpacity = fillOpacity
    ..cap = cap
    ..join = join
    ..evenOdd = evenOdd
    ..shading = shading
    ..rounded = rounded
    ..decorate = decorate
    ..decoration = decoration
    ..preactions = preactions
    ..postactions = postactions
    ..pattern = pattern
    ..patternColour = patternColour
    ..namePath = namePath
    ..intersections = intersections
    ..quotes = quotes
    ..onBackground = onBackground
    ..angleRadius = angleRadius
    ..angleEccentricity = angleEccentricity
    ..matrixOf = matrixOf
    ..rowSep = rowSep
    ..columnSep = columnSep
    ..ampersand = ampersand
    ..transform = transform
    ..xUnit = xUnit
    ..yUnit = yUnit
    ..radius = radius
    ..xRadius = xRadius
    ..yRadius = yRadius
    ..startAngle = startAngle
    ..endAngle = endAngle
    ..deltaAngle = deltaAngle
    ..step = step
    ..domain = domain
    ..samples = samples
    ..variable = variable
    ..smooth = smooth
    ..bend = bend
    ..outAngle = outAngle
    ..inAngle = inAngle
    ..looseness = looseness
    ..shape = shape
    ..anchor = anchor
    ..placement = placement
    ..innerSep = innerSep
    ..minWidth = minWidth
    ..minHeight = minHeight
    ..outerSep = outerSep
    ..pos = pos
    ..nodeDistance = nodeDistance
    ..fontScale = fontScale
    ..bold = bold
    ..italic = italic
    ..align = align
    ..nodeOptions = nodeOptions
    ..labels = labels
    ..polygonSides = polygonSides
    ..starPoints = starPoints
    ..starRatio = starRatio
    ..borderRotate = borderRotate
    ..apexAngle = apexAngle
    ..trapeziumLeft = trapeziumLeft
    ..trapeziumRight = trapeziumRight
    ..fit = fit
    ..through = through
    ..styles = Map<String, List<TikzOption>>.of(styles);

  /// The style a node on a path drawn in this one starts from: its colours
  /// and lines, but not the path's own drawing, tips or placing.
  _Style forNode() => copy()
    ..draws = false
    ..fills = false
    ..shading = null
    ..startTip = null
    ..endTip = null
    ..pos = null
    ..anchor = null
    ..placement = null
    ..labels = const <String>[]
    ..fit = null
    ..through = null
    ..decorate = false
    ..preactions = const <List<TikzOption>>[]
    ..postactions = const <List<TikzOption>>[]
    ..pattern = null
    ..namePath = null
    ..intersections = null
    ..quotes = const <String>[]
    ..matrixOf = null;

  Color get stroke => _faded(drawColour ?? colour, opacity * drawOpacity);
  Color get patternInk =>
      _faded(patternColour ?? const Color(0xFF000000), opacity * fillOpacity);
  Color get filling => _faded(fillColour ?? colour, opacity * fillOpacity);
  Color get text => _faded(textColour ?? colour, opacity);

  static Color _faded(Color colour, double opacity) =>
      colour.withValues(alpha: colour.a * opacity.clamp(0.0, 1.0));

  static const Map<String, double> _widths = <String, double>{
    'ultra thin': 0.1,
    'very thin': 0.2,
    'thin': 0.4,
    'semithick': 0.6,
    'thick': 0.8,
    'very thick': 1.2,
    'ultra thick': 1.6,
  };

  static const Map<String, List<double>?> _dashes = <String, List<double>?>{
    'solid': null,
    'dashed': <double>[3, 3],
    'densely dashed': <double>[3, 2],
    'loosely dashed': <double>[3, 6],
    'dotted': <double>[0.4, 2],
    'densely dotted': <double>[0.4, 1],
    'loosely dotted': <double>[0.4, 4],
    'dash dot': <double>[3, 2, 0.4, 2],
    'dashdotted': <double>[3, 2, 0.4, 2],
  };

  static const Map<String, double> _fontScales = <String, double>{
    'tiny': 0.5,
    'scriptsize': 0.7,
    'footnotesize': 0.8,
    'small': 0.9,
    'normalsize': 1,
    'large': 1.2,
    'Large': 1.44,
    'LARGE': 1.728,
    'huge': 2.074,
    'Huge': 2.488,
  };

  static const Set<String> _sides = <String>{
    'above',
    'below',
    'left',
    'right',
    'above left',
    'above right',
    'below left',
    'below right',
  };

  /// Applies [options] in turn. On a path or node, [onPath], a colour given
  /// to `draw` or `fill` also has it drawn or filled.
  void apply(List<TikzOption> options, {required bool onPath, int depth = 0}) {
    if (depth > 16) throw const FormatException('A style is made of itself');
    for (final (:key, :value) in options) {
      final style = styles[key];
      if (style != null && value == null) {
        apply(style, onPath: onPath, depth: depth + 1);
      } else {
        _applyOne(key, value, onPath);
      }
    }
  }

  void _applyOne(String key, String? value, bool onPath) {
    if (key.startsWith('"')) {
      quotes = <String>[...quotes, key];
      return;
    }
    if (key.endsWith('/.style') || key.endsWith('/.append style')) {
      final name = key.substring(0, key.indexOf('/.')).trim();
      final defined = TikzSource.options(value ?? '');
      styles[name] = key.endsWith('/.style')
          ? defined
          : <TikzOption>[...?styles[name], ...defined];
      return;
    }
    if (value == null) {
      final tips = _tips(key);
      if (tips != null) {
        startTip = tips.$1;
        endTip = tips.$2;
        return;
      }
      if (_widths[key] case final width?) {
        lineWidth = width;
        return;
      }
      if (_dashes.containsKey(key)) {
        dashes = _dashes[key];
        return;
      }
      if (_sides.contains(key)) {
        placement = (side: key, of: null, distance: 0);
        return;
      }
    }
    double number() => TikzExpression.evaluate(value ?? '').value;
    double length({double bare = 1}) =>
        TikzExpression.length(value ?? '', bare: bare);
    Color? colourOf(String spec) => TikzColours.parse(spec, current: colour);
    switch (key) {
      case 'color' when value != null:
        colour = colourOf(value) ?? colour;
        drawColour = fillColour = textColour = null;
      case 'draw':
        if (value == 'none') {
          draws = false;
        } else {
          if (value != null) drawColour = colourOf(value) ?? drawColour;
          if (onPath) draws = true;
        }
      case 'fill':
        if (value == 'none') {
          fills = false;
        } else {
          if (value != null) fillColour = colourOf(value) ?? fillColour;
          if (onPath) fills = true;
        }
      case 'text' when value != null:
        textColour = colourOf(value) ?? textColour;
      case 'line width' when value != null:
        lineWidth = length();
      case 'help lines':
        colour = TikzColours.named['gray']!;
        drawColour = null;
        lineWidth = 0.2;
      case 'dash pattern' when value != null:
        dashes = <double>[
          for (final match in RegExp(
            r'(on|off)\s+([^\s]+(?:\s*[a-z]{2})?)',
          ).allMatches(value))
            TikzExpression.length(match.group(2)!),
        ];
      case 'arrows' when value != null:
        final tips = _tips(value);
        if (tips != null) {
          startTip = tips.$1;
          endTip = tips.$2;
        }
      case '>' when value != null:
        tip = _tip(value) ?? tip;
      case 'opacity':
        opacity = number();
      case 'draw opacity':
        drawOpacity = number();
      case 'fill opacity':
        fillOpacity = number();
      case 'line cap' when value != null:
        cap = switch (value) {
          'round' => StrokeCap.round,
          'rect' => StrokeCap.square,
          _ => StrokeCap.butt,
        };
      case 'line join' when value != null:
        join = switch (value) {
          'round' => StrokeJoin.round,
          'bevel' => StrokeJoin.bevel,
          _ => StrokeJoin.miter,
        };
      case 'decorate':
        decorate = value != 'false';
      case 'decoration' when value != null:
        decoration = <TikzOption>[...decoration, ...TikzSource.options(value)];
      case 'preaction' when value != null:
        preactions = <List<TikzOption>>[
          ...preactions,
          TikzSource.options(value),
        ];
      case 'postaction' when value != null:
        postactions = <List<TikzOption>>[
          ...postactions,
          TikzSource.options(value),
        ];
      case 'name path' || 'name path global' when value != null:
        namePath = value;
      case 'name intersections' when value != null:
        intersections = value;
      case 'on background layer':
        onBackground = true;
      case 'angle radius' when value != null:
        angleRadius = length(bare: _cm);
      case 'angle eccentricity':
        angleEccentricity = number();
      case 'matrix of nodes' || 'matrix of math nodes':
        matrixOf = key;
      case 'row sep' when value != null:
        rowSep = length();
      case 'column sep' when value != null:
        columnSep = length();
      case 'ampersand replacement' when value != null:
        ampersand = value;
      case 'pattern' when value != null:
        pattern = value;
      case 'pattern color' when value != null:
        patternColour = colourOf(value) ?? patternColour;
      case 'rounded corners':
        rounded = value == null ? 4 : length();
      case 'sharp corners':
        rounded = null;
      case 'even odd rule':
        evenOdd = true;
      case 'nonzero rule':
        evenOdd = false;
      case 'left color' || 'right color' when value != null:
        _shade(
          colourOf(value),
          key == 'left color',
          TikzShadingKind.horizontal,
        );
      case 'top color' || 'bottom color' when value != null:
        _shade(colourOf(value), key == 'top color', TikzShadingKind.vertical);
      case 'ball color' when value != null:
        final ball = colourOf(value) ?? colour;
        shading = TikzShading(
          Color.lerp(ball, const Color(0xFFFFFFFF), 0.75)!,
          Color.lerp(ball, const Color(0xFF000000), 0.35)!,
          TikzShadingKind.ball,
        );
        fills = true;
      case 'shift' when value != null:
        transform = transform.after(_translation(vector(_inner(value))));
      case 'xshift':
        transform = transform.after(_translation(Offset(length(), 0)));
      case 'yshift':
        transform = transform.after(_translation(Offset(0, length())));
      case 'scale':
        final s = number();
        transform = transform.after(_Affine(s, 0, 0, s, 0, 0));
      case 'xscale':
        transform = transform.after(_Affine(number(), 0, 0, 1, 0, 0));
      case 'yscale':
        transform = transform.after(_Affine(1, 0, 0, number(), 0, 0));
      case 'rotate':
        transform = transform.after(_Affine.rotation(number()));
      case 'x' when value != null:
        xUnit = value.trim().startsWith('(')
            ? _lengths(_inner(value))
            : Offset(length(bare: _cm), 0);
      case 'y' when value != null:
        yUnit = value.trim().startsWith('(')
            ? _lengths(_inner(value))
            : Offset(0, length(bare: _cm));
      case 'radius':
        radius = value;
      case 'x radius':
        xRadius = value;
      case 'y radius':
        yRadius = value;
      case 'start angle':
        startAngle = number();
      case 'end angle':
        endAngle = number();
      case 'delta angle':
        deltaAngle = number();
      case 'step' when value != null:
        step = value;
      case 'domain' when value != null:
        final parts = value.split(':');
        if (parts.length != 2) {
          throw FormatException('A domain is "from:to", not "$value"');
        }
        domain = (
          from: TikzExpression.evaluate(parts[0]).value,
          to: TikzExpression.evaluate(parts[1]).value,
        );
      case 'samples':
        samples = number().round().clamp(2, 1000);
      case 'variable' when value != null:
        variable = value.trim().replaceFirst(r'\', '');
      case 'smooth':
        smooth = true;
      case 'sharp plot':
        smooth = false;
      case 'bend left':
        bend = value == null ? 30.0 : number();
      case 'bend right':
        bend = -(value == null ? 30.0 : number());
      case 'out':
        outAngle = number();
      case 'in':
        inAngle = number();
      case 'looseness':
        looseness = number();
      case 'circle' ||
          'rectangle' ||
          'ellipse' ||
          'coordinate' ||
          'diamond' ||
          'regular polygon' ||
          'star' ||
          'isosceles triangle' ||
          'trapezium' ||
          'semicircle':
        shape = key;
      case 'regular polygon sides':
        polygonSides = number().round();
      case 'star points':
        starPoints = number().round();
      case 'star point ratio':
        starRatio = number();
      case 'shape border rotate':
        borderRotate = number();
      case 'isosceles triangle apex angle':
        apexAngle = number();
      case 'trapezium left angle':
        trapeziumLeft = number();
      case 'trapezium right angle':
        trapeziumRight = number();
      case 'trapezium angle':
        trapeziumLeft = trapeziumRight = number();
      case 'fit' when value != null:
        fit = value;
      case 'circle through' when value != null:
        through = _inner(value);
      case 'shape' when value != null:
        shape = value;
      case 'anchor' when value != null:
        anchor = value;
        placement = null;
      case 'inner sep':
        innerSep = length();
      case 'outer sep':
        outerSep = length();
      case 'minimum size':
        minWidth = minHeight = length(bare: _cm);
      case 'minimum width':
        minWidth = length(bare: _cm);
      case 'minimum height':
        minHeight = length(bare: _cm);
      case 'node distance':
        nodeDistance = length(bare: _cm);
      case 'midway':
        pos = 0.5;
      case 'near start':
        pos = 0.25;
      case 'near end':
        pos = 0.75;
      case 'very near start':
        pos = 0.125;
      case 'very near end':
        pos = 0.875;
      case 'at start':
        pos = 0;
      case 'at end':
        pos = 1;
      case 'pos':
        pos = number();
      case 'font' when value != null:
        for (final match in RegExp(r'\\([a-zA-Z]+)').allMatches(value)) {
          final name = match.group(1)!;
          fontScale = _fontScales[name] ?? fontScale;
          if (name == 'bfseries') bold = true;
          if (name == 'itshape') italic = true;
        }
      case 'align' when value != null:
        align = value;
      case 'nodes' when value != null:
        nodeOptions = <TikzOption>[
          ...nodeOptions,
          ...TikzSource.options(value),
        ];
      case 'label' || 'pin' when value != null:
        labels = <String>[...labels, value];
      case _ when _sides.contains(key) && value != null:
        final of = RegExp(r'^(.*?)\bof\s+(.+)$').firstMatch(value);
        final distance = of?.group(1)?.trim() ?? value;
        placement = (
          side: key,
          of: of?.group(2)?.trim(),
          distance: distance.isEmpty
              ? (of == null ? 0 : nodeDistance)
              : TikzExpression.length(distance, bare: _cm),
        );
      case _ when value == null:
        // A colour on its own is the colour of everything.
        final named = colourOf(key);
        if (named != null) {
          colour = named;
          drawColour = fillColour = textColour = null;
        }
      default:
      // An option this drawing has no use for changes nothing.
    }
  }

  void _shade(Color? colour, bool first, TikzShadingKind kind) {
    if (colour == null) return;
    final current = shading;
    final other = current != null && current.kind == kind
        ? (first ? current.to : current.from)
        : const Color(0xFFFFFFFF);
    shading = TikzShading(first ? colour : other, first ? other : colour, kind);
    fills = true;
  }

  static _Affine _translation(Offset by) => _Affine(1, 0, 0, 1, by.dx, by.dy);

  /// The coordinate inside `(…)`.
  static String _inner(String value) {
    final trimmed = value.trim();
    return trimmed.startsWith('(') && trimmed.endsWith(')')
        ? trimmed.substring(1, trimmed.length - 1)
        : trimmed;
  }

  /// `a,b` as lengths, centimetres where they are bare.
  static Offset _lengths(String pair) {
    final parts = TikzSource.split(pair, ',');
    if (parts.length != 2) throw FormatException('"$pair" is not a vector');
    return Offset(
      TikzExpression.length(parts[0], bare: _cm),
      TikzExpression.length(parts[1], bare: _cm),
    );
  }

  /// The point `x,y` or `angle:radius` names, in points, before the
  /// transformation.
  Offset vector(
    String inner, [
    Map<String, double> variables = const <String, double>{},
  ]) {
    final comma = TikzSource.split(inner, ',');
    if (comma.length == 2) {
      final x = TikzExpression.evaluate(comma[0], variables);
      final y = TikzExpression.evaluate(comma[1], variables);
      return (x.length ? Offset(x.value, 0) : xUnit * x.value) +
          (y.length ? Offset(0, y.value) : yUnit * y.value);
    }
    final colon = TikzSource.split(inner, ':');
    if (colon.length == 2) {
      final angle = TikzExpression.evaluate(colon[0], variables).value;
      final radii = colon[1].split(RegExp(r'\s+and\s+'));
      final rx = TikzExpression.evaluate(radii.first, variables);
      final ry = TikzExpression.evaluate(radii.last, variables);
      final r = angle * math.pi / 180;
      return (rx.length
              ? Offset(rx.value * math.cos(r), 0)
              : xUnit * (rx.value * math.cos(r))) +
          (ry.length
              ? Offset(0, ry.value * math.sin(r))
              : yUnit * (ry.value * math.sin(r)));
    }
    throw FormatException('"$inner" is not a coordinate');
  }

  /// [spec] as a length along x, or along y if [vertical]: bare numbers in
  /// the picture's units.
  double radiusOf(String spec, {required bool vertical}) =>
      TikzExpression.length(
        spec,
        bare: vertical ? yUnit.distance : xUnit.distance,
      );

  /// The tip at each end that [key] asks for, if it is a tip
  /// specification: `->`, `<->`, `-stealth`, `|-latex`.
  (String?, String?)? _tips(String key) {
    for (var i = 0; i < key.length; i++) {
      if (key[i] != '-') continue;
      final start = key.substring(0, i).trim();
      final end = key.substring(i + 1).trim();
      final first = start.isEmpty ? null : _tip(start);
      final last = end.isEmpty ? null : _tip(end);
      if ((start.isEmpty || first != null) && (end.isEmpty || last != null)) {
        return (first, last);
      }
    }
    return null;
  }

  /// The kind of tip [spec] names: the `arrows` library's and
  /// `arrows.meta`'s, `open` among the latter's options.
  String? _tip(String spec) {
    final unbraced = TikzSource.unbraced(spec);
    final name = unbraced.replaceAll(RegExp(r'\[.*\]'), '').trim();
    final open = RegExp(r'\[[^\]]*\bopen\b').hasMatch(unbraced);
    final kind = switch (name) {
      '>' || '<' => tip,
      '>>' || '<<' => 'double $tip',
      '|' || 'Bar' => 'bar',
      'to' || 'To' || 'Straight Barb' || 'Classical TikZ Rightarrow' => 'to',
      'stealth' || 'Stealth' || 'triangle 45' => 'stealth',
      'latex' || 'Latex' || 'triangle 90' || 'Triangle' => 'latex',
      '*' || 'Circle' || 'circle' => 'dot',
      'o' => 'open dot',
      'Square' || 'Rectangle' || 'square' => 'square',
      ']' || '[' || 'Bracket' => 'bracket',
      'Kite' || 'diamond' => 'kite',
      _ => null,
    };
    return kind != null && open && !kind.startsWith('open ')
        ? 'open $kind'
        : kind;
  }
}
