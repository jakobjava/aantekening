import 'dart:io';

import 'package:aantekening_core/aantekening_core.dart';
import 'package:aantekening_interchange/aantekening_interchange.dart';
import 'package:test/test.dart';

const _document = r'''
\documentclass{article}
\usepackage{amsmath}
\newcommand{\R}{\mathbb{R}}
\newcommand{\norm}[1]{\left\lVert #1 \right\rVert}
\DeclareMathOperator{\tr}{tr}
\title{Lineare Algebra}
\begin{document}
\maketitle
% A comment, left out.
\section{Vektorr\"aume}
Ein \emph{Vektorraum} über $\R$ hat
die Norm $\norm{v}$ -- und mehr.

Die Spur ist \[ \tr A = \sum_i a_{ii}. \]
\begin{align*}
  a &= b \\
  c &= d
\end{align*}
\subsection{Listen}
\begin{itemize}
  \item Erstens, \textbf{fett}
  \item Zweitens
  \begin{enumerate}
    \item innen
  \end{enumerate}
\end{itemize}
\begin{tabular}{|c|c|}
  \hline
  $x$ & $x^2$ \\ \hline
  2 & 4 \\
\end{tabular}
\begin{theorem}[Pythagoras]
  $a^2 + b^2 = c^2$
\end{theorem}
Siehe \href{https://example.org}{hier}.
\end{document}
''';

void main() {
  late LatexDocument read;
  setUp(() => read = LatexText.read(_document));

  test('takes the title from the preamble', () {
    expect(read.title, 'Lineare Algebra');
  });

  test('reads sections as headings, accents as the letters they make', () {
    final heading = read.blocks.first;
    expect(heading.kind, TextBlockKind.heading1);
    expect(heading.plainText, 'Vektorräume');
    expect(
      read.blocks.any((block) => block.plainText.contains('comment')),
      isFalse,
    );
    final listHeading = read.blocks.firstWhere(
      (block) => block.plainText == 'Listen',
    );
    expect(listHeading.kind, TextBlockKind.heading2);
  });

  test('reads a paragraph, its lines joined, its formulas in it', () {
    final paragraph = read.blocks[1];
    expect(paragraph.kind, TextBlockKind.paragraph);
    final runs = paragraph.runs;
    expect(runs[0].text, 'Ein ');
    expect(runs[1].text, 'Vektorraum');
    expect(runs[1].marks.italic, isTrue);
    expect(runs.where((run) => run.isMath).map((run) => run.text), <String>[
      r'\mathbb{R}',
      r'\left\lVert v \right\rVert',
    ], reason: 'commands the document defines, written out');
    expect(runs.last.text, ' – und mehr.');
  });

  test('sets display formulas apart, centred, environments whole', () {
    final formulas = <TextBlock>[
      for (final block in read.blocks)
        if (block.runs.length == 1 &&
            block.runs.single.isMath &&
            block.align == BlockAlign.center)
          block,
    ];
    expect(formulas.map((block) => block.runs.single.text), <String>[
      r'\operatorname{tr}A = \sum_i a_{ii}.',
      '\\begin{align*}\n'
          '  a &= b \\\\\n'
          '  c &= d\n'
          '\\end{align*}',
    ], reason: 'laid out as written');
    expect(
      read.blocks.any((block) => block.plainText == 'Die Spur ist'),
      isTrue,
    );
  });

  test('reads lists, nested ones indented', () {
    final items = <TextBlock>[
      for (final block in read.blocks)
        if (block.kind == TextBlockKind.bulleted ||
            block.kind == TextBlockKind.numbered)
          block,
    ];
    expect(items.map((block) => block.plainText), <String>[
      'Erstens, fett',
      'Zweitens',
      'innen',
    ]);
    expect(items[0].runs.last.marks.bold, isTrue);
    expect(items[2].kind, TextBlockKind.numbered);
    expect(items[2].indent, 1);
  });

  test('reads a table as a table, its cells as text and formulas', () {
    final cells = <TextBlock>[
      for (final block in read.blocks)
        if (block.inTable) block,
    ];
    expect(
      cells.map((cell) => (cell.cell!.row, cell.cell!.column)),
      <(int, int)>[(0, 0), (0, 1), (1, 0), (1, 1)],
    );
    expect(cells[1].runs.single, const TextRun.imported('x^2'));
    expect(cells[3].plainText, '4');
  });

  test('names a theorem in bold, and keeps links', () {
    final theorem = read.blocks.firstWhere(
      (block) => block.plainText.startsWith('Theorem'),
    );
    expect(theorem.runs.first.text, 'Theorem (Pythagoras).');
    expect(theorem.runs.first.marks.bold, isTrue);
    expect(theorem.runs.last.text, 'a^2 + b^2 = c^2');
    final link = read.blocks.last.runs.firstWhere((run) => run.text == 'hier');
    expect(link.marks.link, 'https://example.org');
  });

  test('reads a passage with no preamble, as one typed', () {
    final passage = LatexText.read(r'''
Let $f(x) = x^2$. Then
$$ f'(x) = 2x $$
and \(\int_0^1 f = \tfrac13\).''');
    expect(passage.title, isNull);
    expect(passage.blocks.map((block) => block.runs.length), <int>[3, 1, 3]);
    expect(passage.blocks[0].runs[1], const TextRun.imported('f(x) = x^2'));
    expect(passage.blocks[1].runs.single.text, "f'(x) = 2x");
    expect(passage.blocks[1].align, BlockAlign.center);
    expect(passage.blocks[2].runs[1].text, r'\int_0^1 f = \tfrac13');
  });

  test('lays a formula on lines of its own out as it was written', () {
    final passage = LatexText.read(
      'Then\n'
      '    \\begin{align}\n'
      '      a &= b \\\\\n'
      '\n'
      '        &= c\n'
      '    \\end{align}\n',
    );
    expect(
      passage.blocks.last.runs.single.text,
      '\\begin{align}\n'
      '  a &= b \\\\\n'
      '\n'
      '    &= c\n'
      '\\end{align}',
    );
    expect(LatexText.read(r'\[  x  \]').blocks.single.runs.single.text, 'x');
  });

  test('keeps a TikZ picture whole, with the styles the document sets', () {
    final document = LatexText.read(r'''
\documentclass{article}
\usepackage{tikz}
\usetikzlibrary{arrows}
\tikzset{dot/.style={circle, fill, inner sep=1pt}}
\tikzstyle{axis}=[->, thick]
\begin{document}
A picture:
\begin{figure}
\centering
\begin{tikzpicture}[scale=2]
  \draw[axis] (0,0) -- (1,0);
  \node[dot] at (1,0) {};
\end{tikzpicture}
\end{figure}
\end{document}''');
    final picture = document.blocks
        .singleWhere((block) => block.isEmbed)
        .embed!;
    expect(picture.kind, EmbedKind.tikz, reason: 'a picture in the text');
    expect(
      picture.source,
      '\\begin{tikzpicture}[dot/.style={circle, fill, inner sep=1pt}, '
      'axis/.style={->, thick}, scale=2]\n'
      '  \\draw[axis] (0,0) -- (1,0);\n'
      '  \\node[dot] at (1,0) {};\n'
      '\\end{tikzpicture}',
    );
    expect(
      document.blocks.map((block) => block.plainText).join(),
      isNot(contains('tikzset')),
    );
  });

  test('a file is a page in the section open, its title its own', () async {
    final folder = Directory.systemTemp.createTempSync('latex_import_');
    addTearDown(() => folder.deleteSync(recursive: true));
    final file = File('${folder.path}/la.tex')..writeAsStringSync(_document);
    const importer = LatexImporter();
    expect(importer.target, ImportTarget.section);
    final draft = importer.read(<String>[file.path], ImportWork(folder));
    final page = draft.pages.single;
    expect(page.title, 'Lineare Algebra');
    final box = page.document.elements.single as TextElement;
    expect(box.blocks, read.blocks);
  });
}
