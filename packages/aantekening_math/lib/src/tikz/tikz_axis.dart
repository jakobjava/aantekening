part of 'tikz_picture.dart';

/// One `\addplot` of an axis: what it plots, the options it is drawn with,
/// whether it takes its colour and marks from the cycle list, and whether
/// it is closed down to the x-axis (`\closedcycle`).
typedef _Plot = ({
  String spec,
  List<TikzOption> options,
  bool cycled,
  bool closed,
});

/// The pgfplots `axis` environment: functions, parametric curves and data
/// plotted on axes with ticks, labels, a grid and a legend; the rest of
/// TikZ inside it drawn in its data's coordinates.
extension _Axes on _Painter {
  /// The colours and marks plots take in turn when given no options of
  /// their own, as pgfplots' default cycle list has them.
  static const List<(String, String)> _cycle = <(String, String)>[
    ('blue', '*'),
    ('red', 'square*'),
    ('brown!60!black', 'o'),
    ('black', 'star'),
    ('blue', 'diamond*'),
    ('red', 'triangle*'),
  ];

  /// How far a tick reaches, in points.
  static const double _tickLength = 4;

  /// About how far apart ticks are, in points.
  static const double _tickRoom = 45;

  /// Draws the axis whose options and body [scanner] reads, up to its
  /// `\end{axis}`.
  void _axis(TikzScanner scanner) {
    final options = <String, String?>{
      for (final (:key, :value) in TikzSource.options(
        scanner.optional('[', ']') ?? '',
      ))
        key: value,
    };
    final end = scanner.source.indexOf(r'\end{axis}', scanner.at);
    if (end < 0) throw const FormatException(r'Missing \end{axis}');
    final body = TikzSource.expandLoops(
      scanner.source.substring(scanner.at, end),
    );
    scanner.at = end + r'\end{axis}'.length;
    final (:plots, :legend, :rest) = _axisBody(body);
    final allLegend = <String>[
      if (options['legend entries'] case final entries?)
        ...TikzSource.split(entries, ',').map((e) => e.trim()),
      ...legend,
    ];

    double? number(String key) {
      final value = options[key];
      return value == null ? null : TikzExpression.evaluate(value).value;
    }

    // The data, first: the limits are where it reaches, unless they are
    // given.
    final data = <List<List<Offset>>>[
      for (final plot in plots) _plotted(plot, options),
    ];
    final points = <Offset>[
      for (final plot in data)
        for (final run in plot) ...run,
    ];
    double limit(String key, double Function(Offset p) of, bool lowest) {
      final given = number(key);
      if (given != null) return given;
      if (points.isEmpty) return lowest ? -5 : 5;
      return points.map(of).reduce(lowest ? math.min : math.max);
    }

    var xmin = limit('xmin', (p) => p.dx, true);
    var xmax = limit('xmax', (p) => p.dx, false);
    var ymin = limit('ymin', (p) => p.dy, true);
    var ymax = limit('ymax', (p) => p.dy, false);
    if (xmax - xmin < 1e-12) (xmin, xmax) = (xmin - 1, xmax + 1);
    if (ymax - ymin < 1e-12) (ymin, ymax) = (ymin - 1, ymax + 1);
    if (options.containsKey('enlargelimits') &&
        options['enlargelimits'] != 'false') {
      final share = double.tryParse(options['enlargelimits'] ?? '') ?? 0.1;
      final dx = (xmax - xmin) * share;
      final dy = (ymax - ymin) * share;
      (xmin, xmax, ymin, ymax) = (xmin - dx, xmax + dx, ymin - dy, ymax + dy);
    }

    // The plotting area, in points from its lower left corner.
    final scaleOnly = options.containsKey('scale only axis');
    double side(String key, double fallback, double labels) {
      final value = options[key];
      final whole = value == null ? fallback : TikzExpression.length(value);
      return math.max(scaleOnly ? whole : whole - labels, 30);
    }

    final width = side('width', 240, 45);
    final height = side('height', 207, 35);
    var sx = width / (xmax - xmin);
    var sy = height / (ymax - ymin);
    if (options.containsKey('axis equal') ||
        options.containsKey('axis equal image')) {
      sx = sy = math.min(sx, sy);
    }
    // With y upwards: its top is its lower edge, its bottom its upper one.
    final area = Rect.fromLTRB(0, 0, (xmax - xmin) * sx, (ymax - ymin) * sy);
    Offset toArea(Offset p) => Offset((p.dx - xmin) * sx, (p.dy - ymin) * sy);
    final outer = _scope;
    Offset placed(Offset p) => outer.transform.apply(p);
    final into = _layerOf(outer);

    final lines = options['axis lines'] ?? options['axis x line'] ?? 'box';
    final hidden = options.containsKey('hide axis') || lines == 'none';
    final middle = lines == 'middle' || lines == 'center';
    // Where the axes cross in the middle: at 0, or the nearest edge.
    final origin = toArea(
      Offset(0.clamp(xmin, xmax).toDouble(), 0.clamp(ymin, ymax).toDouble()),
    );

    final xticks = _ticks(
      options['xtick'],
      options['xticklabels'],
      xmin,
      xmax,
      area.width,
    );
    final yticks = _ticks(
      options['ytick'],
      options['yticklabels'],
      ymin,
      ymax,
      area.height,
    );
    final noTicks = options['ticks'] == 'none' || hidden;

    // The grid, beneath everything.
    final grid = options['grid'] ?? options['xmajorgrids'];
    if (grid != null && grid != 'none' && !hidden) {
      final gridStyle = outer.copy()
        ..draws = true
        ..fills = false
        ..lineWidth = 0.4
        ..drawColour = TikzColours.parse('black!25', current: outer.colour);
      for (final (x, _) in xticks) {
        final at = toArea(Offset(x, ymin)).dx;
        _segment(gridStyle, <Offset>[
          placed(Offset(at, area.top)),
          placed(Offset(at, area.bottom)),
        ]);
      }
      for (final (y, _) in yticks) {
        final at = toArea(Offset(xmin, y)).dy;
        _segment(gridStyle, <Offset>[
          placed(Offset(area.left, at)),
          placed(Offset(area.right, at)),
        ]);
      }
    }

    // The plots, kept within the area.
    final drawnPlots = <_Style>[];
    for (var i = 0; i < plots.length; i++) {
      final plot = plots[i];
      final style = _plotStyle(plot, i);
      drawnPlots.add(style);
      final runs = <List<Offset>>[
        for (final run in data[i]) <Offset>[for (final p in run) toArea(p)],
      ];
      final onlyMarks = _has(plot.options, 'only marks');
      if (plot.closed) {
        final base = origin.dy;
        for (final run in runs) {
          final kept = <Offset>[
            for (final p in run)
              if (p.dx >= area.left - 1e-6 && p.dx <= area.right + 1e-6)
                Offset(p.dx, p.dy.clamp(area.top, area.bottom)),
          ];
          if (kept.isEmpty) continue;
          final closedPath = _Path(style);
          _moveTo(closedPath, (point: placed(kept.first), node: null));
          for (final p in <Offset>[
            ...kept.skip(1),
            Offset(kept.last.dx, base),
            Offset(kept.first.dx, base),
          ]) {
            _line(closedPath, (point: placed(p), node: null));
          }
          _close(closedPath);
          _finish(closedPath);
        }
      } else if (!onlyMarks) {
        final drawn = _Path(style.copy()..fills = false);
        for (final run in runs) {
          for (final piece in _clipped(run, area)) {
            _moveTo(drawn, (point: placed(piece.first), node: null));
            for (final p in piece.skip(1)) {
              _line(drawn, (point: placed(p), node: null));
            }
          }
        }
        _finish(drawn);
      }
      final mark = _markOf(plot, i);
      if (mark != null) {
        for (final run in runs) {
          for (final p in run) {
            if (area.inflate(0.01).contains(p)) {
              _mark(mark, placed(p), style, plot.options, into);
            }
          }
        }
      }
    }

    // The axes, their ticks and the labels at them.
    final axisStyle = outer.copy()
      ..draws = true
      ..fills = false
      ..startTip = null
      ..endTip = null
      ..dashes = null;
    if (!hidden) {
      if (lines == 'box') {
        final box = _Path(axisStyle);
        _moveTo(box, (point: placed(area.topLeft), node: null));
        for (final corner in <Offset>[
          area.topRight,
          area.bottomRight,
          area.bottomLeft,
        ]) {
          _line(box, (point: placed(corner), node: null));
        }
        _close(box);
        _finish(box);
      } else {
        final arrows = axisStyle.copy()..endTip = 'stealth';
        final y = middle ? origin.dy : area.top;
        final x = middle ? origin.dx : area.left;
        _segment(arrows, <Offset>[
          placed(Offset(area.left, y)),
          placed(Offset(area.right + 6, y)),
        ]);
        _segment(arrows, <Offset>[
          placed(Offset(x, area.top)),
          placed(Offset(x, area.bottom + 6)),
        ]);
      }
    }
    final xAxis = middle ? origin.dy : area.top;
    final yAxis = middle ? origin.dx : area.left;
    final labelStyle = outer.forNode()
      ..draws = false
      ..fills = false;
    var tickHeight = 0.0;
    var tickWidth = 0.0;
    if (!noTicks) {
      for (final (value, label) in xticks) {
        final at = toArea(Offset(value, ymin)).dx;
        final reach = middle ? _tickLength / 2 : _tickLength;
        _segment(axisStyle, <Offset>[
          placed(Offset(at, xAxis - (middle ? reach : 0))),
          placed(Offset(at, xAxis + reach)),
        ]);
        if (middle && value == 0 && origin.dx > area.left) continue;
        tickHeight = math.max(tickHeight, _labelSize(_labels.length).height);
        _place(
          label,
          labelStyle.copy()..anchor = 'north',
          placed(Offset(at, xAxis - (middle ? reach : 0))),
          into: into,
        );
      }
      for (final (value, label) in yticks) {
        final at = toArea(Offset(xmin, value)).dy;
        final reach = middle ? _tickLength / 2 : _tickLength;
        _segment(axisStyle, <Offset>[
          placed(Offset(yAxis - (middle ? reach : 0), at)),
          placed(Offset(yAxis + reach, at)),
        ]);
        if (middle && value == 0 && origin.dy > area.top) continue;
        tickWidth = math.max(tickWidth, _labelSize(_labels.length).width);
        _place(
          label,
          labelStyle.copy()..anchor = 'east',
          placed(Offset(yAxis - (middle ? reach : 0), at)),
          into: into,
        );
      }
    }
    final gap = 2 * labelStyle.innerSep;
    if (options['xlabel'] case final xlabel?) {
      _place(
        xlabel,
        labelStyle.copy()..anchor = middle ? 'west' : 'north',
        placed(
          middle
              ? Offset(area.right + 6, origin.dy)
              : Offset(area.center.dx, area.top - tickHeight - gap),
        ),
        into: into,
      );
    }
    if (options['ylabel'] case final ylabel?) {
      _place(
        ylabel,
        labelStyle.copy()..anchor = middle ? 'south' : 'east',
        placed(
          middle
              ? Offset(origin.dx, area.bottom + 6)
              : Offset(area.left - tickWidth - gap, area.center.dy),
        ),
        into: into,
      );
    }
    if (options['title'] case final title?) {
      _place(
        title,
        labelStyle.copy()..anchor = 'south',
        placed(Offset(area.center.dx, area.bottom + (middle ? 10 : 2))),
        into: into,
      );
    }
    if (allLegend.isNotEmpty) {
      _legend(
        allLegend,
        <({_Style style, String? mark, List<TikzOption> options})>[
          for (var i = 0; i < plots.length; i++)
            (
              style: drawnPlots[i],
              mark: _markOf(plots[i], i),
              options: plots[i].options,
            ),
        ],
        area,
        options['legend pos'] ?? 'north east',
        placed,
        into,
      );
    }

    // What else is drawn in it, in its data's coordinates.
    _scope = outer.copy()
      ..xUnit = const Offset(1, 0)
      ..yUnit = const Offset(0, 1)
      ..transform = outer.transform.after(
        _Affine(sx, 0, 0, sy, -xmin * sx, -ymin * sy),
      );
    final enclosing = _axisLimits;
    _axisLimits = Rect.fromLTRB(xmin, ymin, xmax, ymax);
    _statements(TikzScanner(rest), inScope: false);
    _axisLimits = enclosing;
    _scope = outer;
  }

  /// Splits an axis' [body] into its plots, the legend entries it adds,
  /// and the rest of what it draws.
  ({List<_Plot> plots, List<String> legend, String rest}) _axisBody(
    String body,
  ) {
    final plots = <_Plot>[];
    final legend = <String>[];
    final rest = StringBuffer();
    final scanner = TikzScanner(body);
    while (!scanner.done) {
      if (scanner.take(';')) continue;
      final command = scanner.command();
      switch (command) {
        case 'addplot' || 'addplot+':
          final cycled = command == 'addplot+' || scanner.take('+');
          final options = scanner.optional('[', ']');
          var spec = scanner.statement().trim();
          final closed = spec.endsWith(r'\closedcycle');
          if (closed) {
            spec = spec.substring(0, spec.length - r'\closedcycle'.length);
          }
          plots.add((
            spec: spec,
            options: TikzSource.options(options ?? ''),
            cycled: cycled || options == null,
            closed: closed,
          ));
        case 'addlegendentry':
          legend.add(scanner.group('{', '}'));
        case 'legend':
          legend.addAll(
            TikzSource.split(scanner.group('{', '}'), ',').map((e) => e.trim()),
          );
        case 'pgfplotsset':
          scanner.group('{', '}');
        case 'begin' || 'end':
          rest.write('\\$command{${scanner.group('{', '}')}}');
          if (command == 'begin' && scanner.sees('[')) {
            rest.write('[${scanner.group('[', ']')}]');
          }
        case null:
          throw FormatException('Cannot read "${_Painter._start(scanner)}"');
        default:
          rest.write('\\$command ${scanner.statement()};');
      }
    }
    return (plots: plots, legend: legend, rest: rest.toString());
  }

  /// The points [plot] plots, in its data's coordinates: runs of them,
  /// broken where its function cannot be worked out.
  List<List<Offset>> _plotted(_Plot plot, Map<String, String?> axis) {
    final scanner = TikzScanner(plot.spec);
    final style = _Style(ink)
      ..samples = 25
      ..domain = (from: -5, to: 5);
    for (final key in <String>['domain', 'samples']) {
      if (axis[key] case final value?) {
        style.apply(<TikzOption>[(key: key, value: value)], onPath: true);
      }
    }
    style.apply(plot.options, onPath: true);
    final variable = style.variable;
    if (scanner.takeWord('coordinates')) {
      final list = TikzScanner(scanner.group('{', '}'));
      final run = <Offset>[];
      while (!list.done) {
        final parts = TikzSource.split(list.group('(', ')'), ',');
        if (parts.length != 2) throw const FormatException('A point is (x,y)');
        run.add(
          Offset(
            TikzExpression.evaluate(parts[0], _variables).value,
            TikzExpression.evaluate(parts[1], _variables).value,
          ),
        );
      }
      return <List<Offset>>[run];
    }
    if (scanner.takeWord('table')) {
      scanner.optional('[', ']');
      return <List<Offset>>[_table(scanner.group('{', '}'))];
    }
    scanner.takeWord('expression');
    final List<String> expressions;
    if (scanner.sees('(')) {
      expressions = <String>[
        for (final part in TikzSource.split(scanner.group('(', ')'), ','))
          TikzSource.unbraced(part),
      ];
      if (expressions.length != 2) {
        throw const FormatException('A curve is (x(t), y(t))');
      }
    } else if (scanner.sees('{')) {
      expressions = <String>[variable, scanner.group('{', '}')];
    } else {
      throw FormatException('Cannot plot "${plot.spec}"');
    }
    final written = <String>[
      for (final expression in expressions) _withVariable(expression, variable),
    ];
    final (:from, :to) = style.domain;
    final runs = <List<Offset>>[<Offset>[]];
    for (var i = 0; i < style.samples; i++) {
      final values = <String, double>{
        ..._variables,
        variable: from + (to - from) * i / (style.samples - 1),
      };
      final x = TikzExpression.evaluate(written[0], values).value;
      final y = TikzExpression.evaluate(written[1], values).value;
      if (x.isFinite && y.isFinite) {
        runs.last.add(Offset(x, y));
      } else if (runs.last.isNotEmpty) {
        // A point the function has no value at breaks the line there.
        runs.add(<Offset>[]);
      }
    }
    return runs.where((run) => run.isNotEmpty).toList();
  }

  /// [expression] with its plain [variable] — `x^2` — written as TikZ
  /// writes one, `\x^2`.
  static String _withVariable(String expression, String variable) =>
      expression.replaceAllMapped(
        RegExp('(?<![\\\\A-Za-z])${RegExp.escape(variable)}(?![A-Za-z])'),
        (_) => '\\$variable',
      );

  /// The points of an inline table: its first two columns, rows on lines
  /// of their own or ended with `\\`, a heading row passed over.
  static List<Offset> _table(String source) {
    final points = <Offset>[];
    for (final row in source.split(RegExp(r'\\\\|\n'))) {
      final cells = row.trim().split(RegExp(r'[\s,]+'));
      if (cells.length < 2) continue;
      final x = double.tryParse(cells[0]);
      final y = double.tryParse(cells[1]);
      if (x != null && y != null) points.add(Offset(x, y));
    }
    return points;
  }

  /// The style [plot], the [index]th, is drawn in: its colour from the
  /// cycle list unless it gives its own options alone.
  _Style _plotStyle(_Plot plot, int index) {
    final style = _scope.copy()
      ..draws = true
      ..fills = false
      ..startTip = null
      ..endTip = null;
    if (plot.cycled) {
      final colour = _cycle[index % _cycle.length].$1;
      style.apply(<TikzOption>[(key: colour, value: null)], onPath: true);
    }
    style.apply(plot.options, onPath: true);
    if (!plot.closed) style.fills = false;
    return style;
  }

  /// The mark [plot], the [index]th, puts at its points, if any.
  static String? _markOf(_Plot plot, int index) {
    if (_has(plot.options, 'no marks') || _has(plot.options, 'no markers')) {
      return null;
    }
    for (final (:key, :value) in plot.options.reversed) {
      if (key == 'mark' && value != null) return value == 'none' ? null : value;
    }
    if (_has(plot.options, 'only marks') || plot.cycled) {
      return _cycle[index % _cycle.length].$2;
    }
    return null;
  }

  static bool _has(List<TikzOption> options, String key) =>
      options.any((option) => option.key == key);

  /// Puts the mark [kind] at [at] in [style], as large as [options] say.
  void _mark(
    String kind,
    Offset at,
    _Style style,
    List<TikzOption> options,
    List<TikzMark> into,
  ) {
    var radius = 2.0;
    for (final (:key, :value) in options) {
      if (key == 'mark size' && value != null) {
        radius = TikzExpression.length(value);
      }
    }
    final c = _out(at);
    final filled = kind.endsWith('*');
    final shape = filled ? kind.substring(0, kind.length - 1) : kind;
    final path = Path();
    Offset p(double x, double y) => c + Offset(x, -y) * radius;
    var closed = true;
    switch (shape) {
      case '' || 'o' || 'circle':
        path.addOval(Rect.fromCircle(center: c, radius: radius));
      case 'square':
        path.addPolygon(<Offset>[p(-1, -1), p(1, -1), p(1, 1), p(-1, 1)], true);
      case 'triangle':
        path.addPolygon(<Offset>[p(0, 1), p(-0.87, -0.5), p(0.87, -0.5)], true);
      case 'diamond':
        path.addPolygon(<Offset>[
          p(0, 1),
          p(0.75, 0),
          p(0, -1),
          p(-0.75, 0),
        ], true);
      case 'x' || '+' || 'star' || '|' || '-':
        closed = false;
        final arms = switch (shape) {
          'x' => <double>[45, 135],
          '+' => <double>[0, 90],
          '|' => <double>[90],
          '-' => <double>[0],
          _ => <double>[90, 18, 162, 234, 306],
        };
        for (final degrees in arms) {
          final d = Offset.fromDirection(degrees * math.pi / 180);
          final full = shape == 'star' ? 0 : 1;
          path
            ..moveTo(c.dx - d.dx * radius * full, c.dy + d.dy * radius * full)
            ..lineTo(c.dx + d.dx * radius, c.dy - d.dy * radius);
        }
      default:
        throw FormatException('No mark here is called "$kind"');
    }
    final markStyle = style.copy()
      ..dashes = null
      ..draws = true
      ..fills = filled && closed
      ..fillColour = style.drawColour ?? style.colour
      ..pattern = null
      ..decorate = false;
    _emit(path, markStyle, closed: closed, into: into, tips: false);
  }

  /// Draws a line through [points] in [style].
  void _segment(_Style style, List<Offset> points) {
    final path = _Path(style);
    _moveTo(path, (point: points.first, node: null));
    for (final point in points.skip(1)) {
      _line(path, (point: point, node: null));
    }
    _finish(path);
  }

  /// The ticks between [min] and [max], along an axis [length] points
  /// long, and their labels: where [given] lists, none for `\empty`, or at
  /// round values, as many as there is room for; labelled as [labels]
  /// lists, or with their values.
  List<(double, String)> _ticks(
    String? given,
    String? labels,
    double min,
    double max,
    double length,
  ) {
    final values = _tickValues(given, min, max, length);
    final listed = labels == null
        ? const <String>[]
        : TikzSource.split(labels, ',').map((e) => e.trim()).toList();
    final slack = (max - min) * 1e-9;
    return <(double, String)>[
      for (var i = 0; i < values.length; i++)
        if (values[i] >= min - slack && values[i] <= max + slack)
          (
            values[i],
            i < listed.length
                ? listed[i]
                : '\$${TikzExpression.format(values[i])}\$',
          ),
    ];
  }

  /// Where ticks go: where [given] lists, none for `\empty`, or at round
  /// values between [min] and [max], about one in every [_tickRoom] points
  /// of the axis' [length].
  List<double> _tickValues(
    String? given,
    double min,
    double max,
    double length,
  ) {
    if (given != null) {
      if (given.trim() == r'\empty' || given.trim().isEmpty) {
        return const <double>[];
      }
      final values = TikzSource.expandLoops(
        r'\foreach \t in {'
        '$given'
        r'} {\t,}',
      );
      return <double>[
        for (final value in values.split(','))
          if (value.trim().isNotEmpty)
            TikzExpression.evaluate(value, _variables).value,
      ];
    }
    final raw = (max - min) / math.max(2, length / _tickRoom);
    final power = math
        .pow(10, (math.log(raw) / math.ln10).floorToDouble())
        .toDouble();
    final f = raw / power;
    final step =
        (f < 1.5
            ? 1
            : f < 3
            ? 2
            : f < 7
            ? 5
            : 10) *
        power;
    return <double>[
      for (
        var k = (min / step - 1e-9).ceil();
        k * step <= max + step * 1e-9;
        k++
      )
        k * step,
    ];
  }

  /// [run], in the area's points, cut to the parts that lie within [area].
  static List<List<Offset>> _clipped(List<Offset> run, Rect area) {
    final pieces = <List<Offset>>[];
    var piece = <Offset>[];
    for (var i = 0; i + 1 < run.length; i++) {
      final kept = _clip(run[i], run[i + 1], area);
      if (kept == null) {
        if (piece.length > 1) pieces.add(piece);
        piece = <Offset>[];
        continue;
      }
      if (piece.isEmpty || (piece.last - kept.$1).distance > 1e-6) {
        if (piece.length > 1) pieces.add(piece);
        piece = <Offset>[kept.$1];
      }
      piece.add(kept.$2);
    }
    if (piece.length > 1) pieces.add(piece);
    if (run.length == 1 && area.contains(run.single)) {
      pieces.add(<Offset>[run.single, run.single]);
    }
    return pieces;
  }

  /// The part of the segment from [a] to [b] within [area], if any.
  static (Offset, Offset)? _clip(Offset a, Offset b, Rect area) {
    var t0 = 0.0;
    var t1 = 1.0;
    final d = b - a;
    bool edge(double p, double q) {
      if (p == 0) return q >= 0;
      final t = q / p;
      if (p < 0) {
        if (t > t1) return false;
        if (t > t0) t0 = t;
      } else {
        if (t < t0) return false;
        if (t < t1) t1 = t;
      }
      return true;
    }

    if (!edge(-d.dx, a.dx - area.left) ||
        !edge(d.dx, area.right - a.dx) ||
        !edge(-d.dy, a.dy - area.top) ||
        !edge(d.dy, area.bottom - a.dy)) {
      return null;
    }
    return (a + d * t0, a + d * t1);
  }

  /// The legend of [entries], each beside a sample of its plot, in a box
  /// at [position] in [area].
  void _legend(
    List<String> entries,
    List<({_Style style, String? mark, List<TikzOption> options})> plots,
    Rect area,
    String position,
    Offset Function(Offset p) placed,
    List<TikzMark> into,
  ) {
    const sample = 15.0;
    const pad = 3.0;
    final textStyle = _scope.forNode()
      ..draws = false
      ..fills = false
      ..anchor = 'west';
    final count = math.min(entries.length, plots.length);
    if (count == 0) return;
    final sizes = <Size>[
      for (var i = 0; i < count; i++)
        _halfSize(_labels.length + i, textStyle) * 2,
    ];
    final rowHeight = sizes.map((s) => s.height).reduce(math.max);
    final width = sample + pad * 3 + sizes.map((s) => s.width).reduce(math.max);
    final height = rowHeight * count + pad * 2;
    final inset = 4.0;
    final outside = position.startsWith('outer');
    final east = position.contains('east');
    final north = position.contains('north');
    final left = outside
        ? area.right + inset * 2
        : east
        ? area.right - inset - width
        : area.left + inset;
    final top = north || outside
        ? area.bottom - inset
        : area.top + inset + height;
    final frame = _scope.copy()
      ..draws = true
      ..fills = true
      ..fillColour = const Color(0xFFFFFFFF)
      ..drawColour = TikzColours.parse('black', current: _scope.colour)
      ..lineWidth = 0.4
      ..dashes = null
      ..startTip = null
      ..endTip = null;
    final box = _Path(frame);
    _moveTo(box, (point: placed(Offset(left, top)), node: null));
    for (final corner in <Offset>[
      Offset(left + width, top),
      Offset(left + width, top - height),
      Offset(left, top - height),
    ]) {
      _line(box, (point: placed(corner), node: null));
    }
    _close(box);
    _finish(box);
    for (var i = 0; i < count; i++) {
      final y = top - pad - rowHeight * (i + 0.5);
      final plot = plots[i];
      final line = plot.style.copy()
        ..fills = false
        ..startTip = null
        ..endTip = null;
      if (!_has(plot.options, 'only marks')) {
        _segment(line, <Offset>[
          placed(Offset(left + pad, y)),
          placed(Offset(left + pad + sample, y)),
        ]);
      }
      if (plot.mark case final mark?) {
        _mark(
          mark,
          placed(Offset(left + pad + sample / 2, y)),
          plot.style,
          plot.options,
          into,
        );
      }
      _place(
        entries[i],
        textStyle.copy(),
        placed(Offset(left + pad * 2 + sample, y)),
        into: into,
      );
    }
  }
}
