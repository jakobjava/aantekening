import 'package:aantekening_core/aantekening_core.dart';
import 'package:aantekening_math/aantekening_math.dart';
import 'package:flutter_test/flutter_test.dart';

PageDocument _page(List<NoteElement> elements) =>
    PageDocument.empty(id: 'page').copyWith(elements: elements);

void main() {
  const marks = TextMarks(bold: true);

  test('translates formulas held in Simple syntax to LaTeX', () {
    final page = _page(const <NoteElement>[
      TextElement(
        id: 'text',
        frame: Frame(x: 0, y: 0, width: 100, height: 40),
        createdAt: 0,
        updatedAt: 0,
        blocks: <TextBlock>[
          TextBlock(
            runs: <TextRun>[
              TextRun('so '),
              TextRun.math('x^2/3', MathMode.linear, marks),
            ],
          ),
        ],
      ),
      TableElement(
        id: 'table',
        frame: Frame(x: 0, y: 50, width: 100, height: 40),
        createdAt: 0,
        updatedAt: 0,
        columnWidths: <double>[100],
        rows: <List<TextBlock>>[
          <TextBlock>[
            TextBlock(
              runs: <TextRun>[TextRun.math('sqrt(2)', MathMode.linear)],
            ),
          ],
        ],
      ),
    ]);

    final stored = MathStorage.withLatexFormulas(page);

    final text = stored.elementById('text')! as TextElement;
    expect(
      text.blocks.single.runs.last,
      const TextRun.math(r'\frac{x^2}{3}', MathMode.latex, marks),
    );
    expect(text.blocks.single.runs.first, const TextRun('so '));
    final table = stored.elementById('table')! as TableElement;
    expect(
      table.rows.single.single.runs.single,
      const TextRun.math(r'\sqrt{2}', MathMode.latex),
    );
  });

  test('leaves a page already in LaTeX untouched', () {
    final page = _page(const <NoteElement>[
      TextElement(
        id: 'text',
        frame: Frame(x: 0, y: 0, width: 100, height: 40),
        createdAt: 0,
        updatedAt: 0,
        blocks: <TextBlock>[
          TextBlock(runs: <TextRun>[TextRun.math(r'\pi', MathMode.latex)]),
        ],
      ),
    ]);
    expect(identical(MathStorage.withLatexFormulas(page), page), isTrue);
  });
}
