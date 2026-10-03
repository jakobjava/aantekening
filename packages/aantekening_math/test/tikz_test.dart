import 'dart:math' as math;

import 'package:aantekening_core/aantekening_core.dart' show MathMode;
import 'package:aantekening_math/aantekening_math.dart';
import 'package:aantekening_math/src/tikz/tikz_expression.dart';
import 'package:aantekening_math/src/tikz/tikz_picture.dart';
import 'package:aantekening_math/src/tikz/tikz_source.dart';
import 'package:flutter/material.dart' show MaterialApp, Scaffold;
import 'package:flutter/widgets.dart' hide Path;
import 'package:flutter_test/flutter_test.dart';

const double cm = TikzExpression.pointsPerCm;

TikzDrawing drawn(String body, {List<Size>? labelSizes}) => TikzPicture.read(
  '\\begin{tikzpicture}$body\\end{tikzpicture}',
).draw(labelSizes: labelSizes);

/// Where [path] starts and ends, by its outline.
Rect boundsOf(TikzMark mark) => mark.path.getBounds();

void main() {
  group('arithmetic', () {
    double value(String source, [Map<String, double>? variables]) =>
        TikzExpression.evaluate(
          source,
          variables ?? const <String, double>{},
        ).value;

    test('works out sums, powers and functions, angles in degrees', () {
      expect(value('1 + 2*3'), 7);
      expect(value('2^3^2'), 512);
      expect(value('-(1+2)/3'), -1);
      expect(value('sin(30)'), closeTo(0.5, 1e-12));
      expect(value('cos(pi r)'), closeTo(-1, 1e-12), reason: 'r for radians');
      expect(value('sqrt(16) + max(1, 5, 3)'), 9);
      expect(value(r'2*\x', <String, double>{'x': 4}), 8);
    });

    test('gives lengths in points', () {
      final cmLength = TikzExpression.evaluate('1cm');
      expect(cmLength.length, isTrue);
      expect(cmLength.value, closeTo(cm, 1e-9));
      expect(TikzExpression.evaluate('3').length, isFalse);
      expect(TikzExpression.length('2', bare: cm), closeTo(2 * cm, 1e-9));
    });

    test('says what it cannot work out', () {
      expect(() => value('2 +'), throwsFormatException);
      expect(() => value(r'\y'), throwsFormatException);
      expect(() => value('frob(2)'), throwsFormatException);
    });
  });

  group('source', () {
    test('reads options, braces and all', () {
      expect(
        TikzSource.options('->, thick, fill=red!20, label={[red]a,b}'),
        <TikzOption>[
          (key: '->', value: null),
          (key: 'thick', value: null),
          (key: 'fill', value: 'red!20'),
          (key: 'label', value: '[red]a,b'),
        ],
      );
    });

    test('writes loops out, ranges and pairs included', () {
      expect(
        TikzSource.expandLoops(r'\foreach \x in {0,...,3} {(\x,0)}'),
        '(0,0) (1,0) (2,0) (3,0) ',
      );
      expect(
        TikzSource.expandLoops(r'\foreach \x in {1,3,...,8} \fill (\x,0);'),
        r'\fill (1,0); \fill (3,0); \fill (5,0); \fill (7,0); ',
      );
      expect(
        TikzSource.expandLoops(r'\foreach \a/\b in {1/x, 2/y} {\b\a}'),
        'x1 y2 ',
      );
      expect(
        TikzSource.expandLoops(
          r'\foreach \x in {1,2} \foreach \y in {a,b} {\x\y}',
        ),
        '1a 1b  2a 2b  ',
        reason: 'nested, the outer variable written first',
      );
      expect(
        TikzSource.expandLoops(r'\foreach \x [count=\i] in {a,b} {\i\x}'),
        '1a 2b ',
      );
    });

    test('mixes colours as xcolor does', () {
      const black = Color(0xFF000000);
      expect(TikzColours.parse('red', current: black), const Color(0xFFFF0000));
      final pink = TikzColours.parse('red!50', current: black)!;
      expect(TikzColours.parse('red!50!', current: black), pink);
      expect(pink.r, closeTo(1, 1e-3));
      expect(pink.g, closeTo(0.5, 1e-2));
      final purple = TikzColours.parse('red!50!blue', current: black)!;
      expect(purple.r, closeTo(0.5, 1e-2));
      expect(purple.b, closeTo(0.5, 1e-2));
      expect(TikzColours.parse('nonsense', current: black), isNull);
    });
  });

  group('drawing', () {
    test('a line from one point to another, in centimetres', () {
      final drawing = drawn(r'\draw (0,0) -- (2,1);');
      final line = drawing.marks.single;
      expect(line.width, 0.4);
      expect(boundsOf(line).width, closeTo(2 * cm, 1e-3));
      expect(boundsOf(line).height, closeTo(cm, 1e-3));
      // Upwards in TikZ is up on the page.
      expect(drawing.bounds.top, closeTo(-cm - 0.2, 1e-3));
    });

    test('a filled and drawn shape is one fill and one line', () {
      final drawing = drawn(
        r'\filldraw[fill=blue!20, draw=red, very thick] (0,0) rectangle (1,1);',
      );
      expect(drawing.marks, hasLength(2));
      expect(drawing.marks.first.width, isNull);
      expect(drawing.marks.last.width, 1.2);
      expect(drawing.marks.last.colour, const Color(0xFFFF0000));
    });

    test('circles, arcs and grids land where TikZ puts them', () {
      final circle = drawn(r'\draw (1,1) circle (1);').marks.single;
      expect(boundsOf(circle).center.dx, closeTo(cm, 1e-3));
      expect(boundsOf(circle).width, closeTo(2 * cm, 1e-3));

      // A quarter of a circle of radius 1 from (1,0) ends at (0,1).
      final arc = drawn(r'\draw (1,0) arc (0:90:1);').marks.single;
      expect(boundsOf(arc).left, closeTo(0, 1e-3));
      expect(boundsOf(arc).top, closeTo(-cm, 1e-3));

      final grid = drawn(r'\draw[step=0.5] (0,0) grid (1,1);').marks.single;
      // Three lines each way.
      expect(grid.path.computeMetrics().length, 6);
    });

    test('scaling, shifting and rotating move what is drawn', () {
      final scaled = drawn(r'\draw[scale=2] (0,0) -- (1,0);').marks.single;
      expect(boundsOf(scaled).width, closeTo(2 * cm, 1e-3));
      final shifted = drawn(
        r'\begin{scope}[xshift=1cm] \draw (0,0) -- (1,0); \end{scope}',
      ).marks.single;
      expect(boundsOf(shifted).left, closeTo(cm, 1e-3));
      final turned = drawn(r'\draw[rotate=90] (0,0) -- (1,0);').marks.single;
      expect(boundsOf(turned).width, closeTo(0, 1e-3));
      expect(boundsOf(turned).height, closeTo(cm, 1e-3));
    });

    test('a plot follows its function', () {
      final plot = drawn(
        r'\draw[domain=0:2, samples=11] plot (\x, {\x*\x});',
      ).marks.single;
      expect(boundsOf(plot).width, closeTo(2 * cm, 1e-3));
      expect(boundsOf(plot).height, closeTo(4 * cm, 1e-3));
    });

    test('arrow tips are drawn at the ends they are asked for', () {
      final plain = drawn(r'\draw (0,0) -- (1,0);').marks;
      final arrowed = drawn(r'\draw[->] (0,0) -- (1,0);').marks;
      final both = drawn(r'\draw[<->] (0,0) -- (1,0);').marks;
      expect(arrowed.length, plain.length + 1);
      expect(both.length, plain.length + 2);
      final stealth = drawn(r'\draw[-stealth] (0,0) -- (1,0);').marks;
      // The line stops short of the point of the tip, which fills it.
      expect(boundsOf(stealth.first).right, lessThan(cm));
      expect(boundsOf(stealth.last).right, closeTo(cm, 1e-3));
    });

    test('a dashed line is broken into dashes', () {
      final dashed = drawn(r'\draw[dashed] (0,0) -- (1,0);').marks.single;
      expect(dashed.path.computeMetrics().length, greaterThan(3));
    });
  });

  group('nodes', () {
    test('a node is labelled where it is put, its text as LaTeX', () {
      final drawing = drawn(r'\node at (1,2) {Point $P$};');
      final label = drawing.labels.single;
      expect(label.latex, r'\text{Point $P$}');
      expect(label.centre.dx, closeTo(cm, 1e-3));
      expect(label.centre.dy, closeTo(-2 * cm, 1e-3));
      expect(drawn(r'\node at (0,0) {$x^2$};').labels.single.latex, 'x^2');
    });

    test('lines between nodes stop at their borders', () {
      const size = Size(20, 10);
      final drawing = drawn(
        r'\node[draw] (a) at (0,0) {A}; \node[draw] (b) at (3,0) {B};'
        r'\draw[->] (a) -- (b);',
        labelSizes: const <Size>[size, size],
      );
      // Two outlines, the line and its tip.
      expect(drawing.marks, hasLength(4));
      final line = boundsOf(drawing.marks[2]);
      // Half the label, the inner sep and the outer sep.
      const border = 10 + 3.333 + 0.2;
      expect(line.left, closeTo(border, 1e-3));
      expect(line.right, closeTo(3 * cm - border, 1e-3));
    });

    test('a node above a point hangs from its south side', () {
      final drawing = drawn(
        r'\fill (0,0) circle (2pt) node[above] {top};',
        labelSizes: const <Size>[Size(20, 10)],
      );
      final label = drawing.labels.single;
      expect(label.centre.dx, closeTo(0, 1e-3));
      expect(label.centre.dy, closeTo(-(5 + 3.333 + 0.2), 1e-3));
    });

    test('nodes go midway along what they are written on', () {
      final drawing = drawn(r'\draw (0,0) -- node[above] {a} (2,0);');
      expect(drawing.labels.single.centre.dx, closeTo(cm, 1e-3));
      final along = drawn(r'\draw (0,0) -- (2,0) node[pos=0.25] {b};');
      expect(along.labels.single.centre.dx, closeTo(0.5 * cm, 1e-3));
    });

    test('positioning, labels and named anchors', () {
      final drawing = drawn(
        r'\node[draw, label=below:L] (a) at (0,0) {A};'
        r'\node[right=of a] (b) {B};'
        r'\draw (a.north) -- (b.west);',
      );
      expect(drawing.labels, hasLength(3));
      expect(drawing.labels[1].latex, r'\text{L}');
      expect(drawing.labels[1].centre.dy, greaterThan(0), reason: 'below');
      expect(drawing.labels[2].centre.dx, greaterThan(cm));
    });

    test('styles are applied by name', () {
      final drawing = drawn(
        '[dot/.style={circle, fill=red, inner sep=1pt}]'
        r'\node[dot] at (0,0) {};',
      );
      expect(drawing.marks.single.colour, const Color(0xFFFF0000));
      expect(drawing.labels.single.latex, isEmpty);
    });

    test('loops draw a node for each value', () {
      final drawing = drawn(
        r'\foreach \x in {0,...,4} \node at (\x,0) {$\x$};',
      );
      expect(drawing.labels.map((label) => label.latex), <String>[
        '0',
        '1',
        '2',
        '3',
        '4',
      ]);
    });
  });

  group('problems', () {
    String? problem(String body) =>
        TikzPicture.problemIn('\\begin{tikzpicture}$body\\end{tikzpicture}');

    test('none in a picture that draws', () {
      expect(problem(r'\draw (0,0) -- (1,1);'), isNull);
    });

    test('are said plainly', () {
      expect(problem(r'\draw (0,0) -- (1,1)'), contains(';'));
      expect(problem(r'\draw (a) -- (1,1);'), contains('"a"'));
      expect(problem(r'\frob;'), contains(r'\frob'));
      expect(
        TikzPicture.problemIn(r'\begin{tikzpicture}\draw (0,0);'),
        contains(r'\end{tikzpicture}'),
      );
    });

    test(r'a \tikz command is a picture too', () {
      expect(TikzPicture.holds(r'\tikz \draw (0,0) -- (1,0);'), isTrue);
      expect(TikzPicture.holds(r'\begin{tikzpicture}'), isTrue);
      expect(TikzPicture.holds(r'\frac{a}{b}'), isFalse);
      expect(MathView.problemIn(r'\tikz \draw (0,0) -- (1,0);'), isNull);
    });
  });

  testWidgets('a formula holding a picture draws it', (tester) async {
    await tester.pumpWidget(
      const MaterialApp(
        home: Scaffold(
          body: Center(
            child: MathView(
              source:
                  r'\begin{tikzpicture}\draw[->] (0,0) -- (2,0) '
                  r'node[right] {$x$};\end{tikzpicture}',
              mode: MathMode.latex,
              textStyle: TextStyle(fontSize: 20, color: Color(0xFF000000)),
            ),
          ),
        ),
      ),
    );
    expect(find.byType(TikzView), findsOneWidget);
    expect(
      find.descendant(
        of: find.byType(TikzView),
        matching: find.byType(MathView),
      ),
      findsOneWidget,
      reason: 'the label',
    );
    final size = tester.getSize(find.byType(TikzView));
    // Two centimetres at twenty-point type, and the label beyond.
    expect(size.width, greaterThan(2 * cm * 2));
    expect(size.height, greaterThan(0));
    expect(math.max(size.width, size.height), lessThan(400));
  });
}
