import 'dart:ui';

import 'package:aantekening_math/aantekening_math.dart' show MathView;
import 'package:aantekening_math/src/tikz/tikz_picture.dart';
import 'package:flutter_test/flutter_test.dart';

import 'tikz_test.dart' show boundsOf, cm, drawn;

/// Where the label [index] of [drawing] is, in centimetres, y upwards.
Offset labelAt(TikzDrawing drawing, int index) {
  final centre = drawing.labels[index].centre;
  return Offset(centre.dx / cm, -centre.dy / cm);
}

/// Whether [drawing] draws anything at [point], in centimetres, y upwards.
bool marksAt(TikzDrawing drawing, Offset point) => drawing.marks.any(
  (mark) => mark.path.contains(Offset(point.dx * cm, -point.dy * cm)),
);

void main() {
  test('arrows.meta tips: dots, squares, brackets and open ones', () {
    final plain = drawn(r'\draw (0,0) -- (1,0);').marks;
    for (final tips in <String>[
      '*-o',
      '-Square',
      '-Kite',
      '|-{Bracket}',
      '{Latex[open]}-{Stealth}',
    ]) {
      expect(
        drawn('\\draw[$tips] (0,0) -- (1,0);').marks.length,
        plain.length + 2 - (tips.startsWith('-') ? 1 : 0),
        reason: tips,
      );
    }
    // An open tip leaves the line short of its back, its inside empty.
    final open = drawn(r'\draw[-{Latex[open]}] (0,0) -- (1,0);').marks;
    expect(boundsOf(open.first).right, lessThan(cm - 3));
  });

  test('calc: turned points, feet on lines and lengths along', () {
    const points =
        r'\coordinate (a) at (0,0); \coordinate (b) at (2,0); '
        r'\coordinate (c) at (1,2);';
    Offset at(String calculation) =>
        labelAt(drawn('$points \\node at ($calculation) {};'), 0);
    final turned = at(r'$(a)!0.5!90:(b)$');
    expect(turned.dx, closeTo(0, 1e-6));
    expect(turned.dy, closeTo(1, 1e-6));
    final foot = at(r'$(a)!(c)!(b)$');
    expect(foot.dx, closeTo(1, 1e-6));
    expect(foot.dy, closeTo(0, 1e-6));
    expect(at(r'$(a)!1cm!(b)$').dx, closeTo(1, 1e-6));
  });

  test('sine and cosine waves, and rounded corners', () {
    final wave = drawn(r'\draw (0,0) sin (1,1) cos (2,0);').marks.single;
    expect(boundsOf(wave).width, closeTo(2 * cm, 1e-3));
    expect(boundsOf(wave).height, closeTo(cm, 1e-3));

    final sharp = drawn(r'\fill (0,0) rectangle (1,1);');
    final round = drawn(r'\fill[rounded corners] (0,0) rectangle (1,1);');
    final line = drawn(
      r'\fill[rounded corners=5pt] (0,0) -- (1,0) -- (1,1) -- cycle;',
    );
    const corner = Offset(0.995, 0.005);
    expect(marksAt(sharp, corner), isTrue);
    expect(marksAt(round, corner), isFalse);
    expect(marksAt(line, corner), isFalse);
    expect(marksAt(round, const Offset(0.5, 0.5)), isTrue);
  });

  test('shapes.geometric nodes, their corners as anchors', () {
    const size = <Size>[Size(10, 10), Size.zero];
    final diamond = drawn(
      r'\node[draw, diamond, inner sep=0] at (0,0) {a};',
      labelSizes: size,
    );
    expect(boundsOf(diamond.marks.single).width, closeTo(20, 1e-3));
    final hexagon = drawn(
      r'\node[regular polygon, regular polygon sides=6] (h) at (0,0) {a};'
      r'\node at (h.corner 1) {};',
      labelSizes: size,
    );
    expect(labelAt(hexagon, 1).dy, greaterThan(0));
    for (final shape in <String>[
      'star',
      'isosceles triangle',
      'trapezium',
      'semicircle',
    ]) {
      expect(
        drawn('\\node[draw, $shape] at (0,0) {a};').marks,
        hasLength(1),
        reason: shape,
      );
    }
  });

  test('fit and through size a node round others', () {
    final fitted = drawn(
      r'\node (a) at (0,0) {}; \node (b) at (2,1) {};'
      r'\node[draw, fit=(a)(b), inner sep=0] {};',
    );
    final box = boundsOf(fitted.marks.single);
    expect(box.width, greaterThan(2 * cm));
    expect(box.center.dx, closeTo(cm, 1e-3));
    final circle = drawn(
      r'\coordinate (b) at (1,0); \node[draw, circle through=(b)] at (0,0) {};',
    );
    expect(boundsOf(circle.marks.single).width, closeTo(2 * cm, 1));
  });

  test('patterns fill in place of a colour', () {
    final hatched = drawn(
      r'\fill[pattern=north east lines] (0,0) rectangle (1,1);',
    );
    expect(hatched.marks, hasLength(1));
    expect(marksAt(hatched, const Offset(0.5, 0.5)), isNot(isTrue));
    expect(boundsOf(hatched.marks.single).width, lessThanOrEqualTo(cm + 1e-3));
    final red = drawn(
      r'\draw[pattern=grid, pattern color=red] (0,0) rectangle (1,1);',
    );
    expect(red.marks.first.colour, const Color(0xFFFF0000));
    expect(red.marks, hasLength(2), reason: 'the pattern and the outline');
  });

  test('decorations: waves, braces, borders and marks along a path', () {
    final zigzag = drawn(
      r'\draw[decorate, decoration={zigzag, amplitude=3pt}] (0,0) -- (2,0);',
    ).marks.single;
    expect(boundsOf(zigzag).height, closeTo(6, 0.5));
    expect(boundsOf(zigzag).width, closeTo(2 * cm, 0.5));

    final brace = drawn(
      r'\draw[decorate, decoration={brace, amplitude=5pt}] (0,0) -- (2,0);',
    ).marks.single;
    expect(boundsOf(brace).height, closeTo(5, 0.5));
    expect(boundsOf(brace).bottom, closeTo(0, 0.5), reason: 'above the line');
    final mirrored = drawn(
      r'\draw[decorate, decoration={brace, mirror}] (0,0) -- (2,0);',
    ).marks.single;
    expect(boundsOf(mirrored).top, closeTo(0, 0.5), reason: 'below it');

    for (final name in <String>[
      'snake',
      'coil',
      'saw',
      'bumps',
      'random steps',
      'border',
      'ticks',
    ]) {
      expect(
        drawn('\\draw[decorate, decoration=$name] (0,0) -- (2,0);').marks,
        hasLength(1),
        reason: name,
      );
    }

    final marked = drawn(
      r'\draw[postaction={decorate}, decoration={markings, '
      r'mark=at position 0.5 with {\arrow{>}}}] (0,0) -- (2,0);',
    );
    expect(marked.marks, hasLength(2), reason: 'the line and the arrow');
    expect(boundsOf(marked.marks.last).center.dx, closeTo(cm, 2));
    final spaced = drawn(
      r'\path[decorate, decoration={markings, mark=between positions 0 and 1 '
      r'step 0.25 with {\node {x};}}] (0,0) -- (2,0);',
    );
    expect(spaced.labels, hasLength(5));
  });

  test('intersections are named where paths cross', () {
    final drawing = drawn(
      r'\path[name path=a] (0,0) -- (2,2); \path[name path=b] (0,2) -- (2,0);'
      r'\path[name intersections={of=a and b, by=x}];'
      r'\node at (x) {}; \node at (intersection-1) {};',
    );
    for (final i in <int>[0, 1]) {
      expect(labelAt(drawing, i).dx, closeTo(1, 1e-3));
      expect(labelAt(drawing, i).dy, closeTo(1, 1e-3));
    }
    expect(
      TikzPicture.problemIn(
        r'\begin{tikzpicture}\path[name intersections={of=a and b}];'
        r'\end{tikzpicture}',
      ),
      contains('"a"'),
    );
  });

  test('angles are marked with an arc or a square, and labelled', () {
    final drawing = drawn(
      r'\coordinate (a) at (1,0); \coordinate (b) at (0,0); '
      r'\coordinate (c) at (0,1);'
      r'\pic[draw, "$\alpha$", angle radius=1cm] {angle=a--b--c};'
      r'\pic[draw] {right angle=a--b--c};',
    );
    expect(drawing.marks, hasLength(2));
    final arc = boundsOf(drawing.marks.first);
    expect(arc.width, closeTo(cm, 1e-3));
    expect(arc.height, closeTo(cm, 1e-3));
    expect(drawing.labels.single.latex, r'\alpha');
    final label = labelAt(drawing, 0);
    expect(label.dx, closeTo(label.dy, 1e-6), reason: 'on the bisector');
    expect(label.distance, closeTo(0.6, 1e-6));
  });

  test('commands a picture defines itself are written out where it uses '
      'them, optional arguments and all', () {
    const picture = r'''
\begin{tikzpicture}[scale=4]
  \def\v{6}
  \pgfmathsetmacro{\tGround}{{2*\v*sin(70)/9.8}}
  \newcommand{\Ballx}[1]{{\v*#1*\tGround*cos(70)}}
  \newcommand{\DrawBall}[2][black]{
    \filldraw[ball color=#1!50!] (\Ballx{#2},0) circle(0.1);
  }
  \foreach \t in {0,0.5} { \DrawBall{\t} }
  \DrawBall[red]{1}
\end{tikzpicture}''';
    expect(MathView.problemIn(picture), isNull);
    final drawing = TikzPicture.read(MathView.prepared(picture)).draw();
    final balls = drawing.marks.where((mark) => mark.shading != null);
    expect(balls, hasLength(3));
    expect(balls.last.shading!.to.r, greaterThan(balls.first.shading!.to.r));
  });

  test('a quoted label sits on an edge, and by a node', () {
    final drawing = drawn(
      r'\node (a) at (0,0) {}; \draw (a) edge["$x$"] (2,0);'
      r'\node["$y$" below] at (4,0) {};',
    );
    expect(drawing.labels.map((label) => label.latex), contains('x'));
    expect(labelAt(drawing, drawing.labels.length - 1).dy, lessThan(0));
  });

  test('the background layer is drawn beneath', () {
    final drawing = drawn(
      r'\fill[red] (0,0) circle (1);'
      r'\begin{scope}[on background layer]\fill[blue] (0,0) circle (2);'
      r'\end{scope}',
    );
    expect(drawing.marks.first.colour, const Color(0xFF0000FF));
  });

  test('a matrix sets its nodes out in rows and columns', () {
    final drawing = drawn(
      r'\matrix (m) [matrix of math nodes, column sep=1cm, row sep=1cm]'
      r'{ A & B \\ C & D \\ };'
      r'\node at (m-2-2) {};',
      labelSizes: List<Size>.filled(5, const Size(10, 10)),
    );
    expect(drawing.labels.first.latex, 'A');
    final a = labelAt(drawing, 0);
    final b = labelAt(drawing, 1);
    final c = labelAt(drawing, 2);
    expect(b.dx, greaterThan(a.dx + 1));
    expect(c.dy, lessThan(a.dy - 1));
    expect(labelAt(drawing, 4), labelAt(drawing, 3), reason: 'm-2-2 is D');
  });

  group('pgfplots', () {
    test('plots a function on axes with ticks, its limits its own', () {
      final drawing = drawn(
        r'\begin{axis}[xlabel=$x$] \addplot[blue] {x^2}; \end{axis}',
      );
      final latex = drawing.labels.map((label) => label.latex).toList();
      expect(latex, containsAll(<String>['-4', 'x']));
      expect(latex, contains('25'), reason: 'the highest y tick');
      final plot = drawing.marks.firstWhere(
        (mark) => mark.colour == const Color(0xFF0000FF),
      );
      final box = boundsOf(plot);
      expect(box.width, closeTo(240 - 45, 1e-3));
      expect(box.height, closeTo(207 - 35, 1e-3));
    });

    test('keeps plots within given limits, other TikZ in its data', () {
      final drawing = drawn(
        r'\begin{axis}[xmin=0, xmax=2, ymin=0, ymax=4, width=245pt,'
        'height=207pt, axis lines=middle, ticks=none]'
        r'\addplot[red, domain=-3:3] {x^2};'
        r'\node at (axis cs:1,2) {}; \node at (rel axis cs:0.5,0.5) {};'
        r'\end{axis}',
      );
      final plot = drawing.marks.firstWhere(
        (mark) => mark.colour == const Color(0xFFFF0000),
      );
      expect(boundsOf(plot).left, closeTo(0, 1e-3));
      expect(boundsOf(plot).right, closeTo(200, 1e-3));
      expect(labelAt(drawing, 0) * cm, const Offset(100, 86));
      expect(labelAt(drawing, 1) * cm, const Offset(100, 86));
    });

    test('takes coordinates, tables and curves, closed down to the axis', () {
      final drawing = drawn(
        r'\begin{axis}[ticks=none]'
        r'\addplot coordinates {(0,0) (1,1)};'
        r'\addplot[only marks, mark=x] table {x y \\ 0 1 \\ 1 0 \\};'
        r'\addplot[fill=blue, draw=none, domain=0:1] {x} \closedcycle;'
        r'\addplot[domain=0:360, samples=9] ({cos(x)}, {sin(x)});'
        r'\legend{line, points, area, circle}'
        r'\end{axis}',
      );
      expect(
        drawing.labels.map((label) => label.latex),
        containsAll(<String>[r'\text{line}', r'\text{circle}']),
      );
      expect(
        drawing.marks.where((mark) => mark.colour == const Color(0xFF0000FF)),
        isNotEmpty,
      );
    });

    test('says what it cannot plot', () {
      expect(
        TikzPicture.problemIn(
          r'\begin{tikzpicture}\begin{axis}\addplot {x^};\end{axis}'
          r'\end{tikzpicture}',
        ),
        isNotNull,
      );
      expect(
        TikzPicture.problemIn(
          r'\begin{tikzpicture}\begin{axis}\addplot {x};\end{tikzpicture}',
        ),
        contains(r'\end{axis}'),
      );
    });
  });
}
