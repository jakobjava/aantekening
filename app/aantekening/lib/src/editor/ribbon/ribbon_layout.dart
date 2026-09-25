/// What the ribbon holds and where: its tabs, the sections of each tab, and
/// which buttons sit in which section, in what order.
///
/// The sections are fixed; the buttons can be dragged anywhere among them,
/// and the arrangement is saved, see [RibbonLayout].
library;

import '../../arrangement/arrangement.dart';

/// A ribbon tab.
enum RibbonTab {
  /// What is used most: undo, and formatting text.
  home('Home'),

  /// Adding things to the page.
  insert('Insert'),

  /// Handwriting: the pens, their colours and widths, and the eraser.
  draw('Draw'),

  /// Writing formulas: structures and symbols to put in, and the syntax.
  /// Brought forward while a formula is being edited.
  math('Math'),

  /// Checking the text: spelling, in the languages chosen.
  review('Review'),

  /// Zoom, and the ribbon itself.
  view('View');

  const RibbonTab(this.label);

  final String label;
}

/// A button, menu or gallery on the ribbon.
enum RibbonItem {
  undo('Undo'),
  redo('Redo'),
  fontSize('Font size'),
  bold('Bold'),
  italic('Italic'),
  underline('Underline'),
  strikethrough('Strikethrough'),
  inlineCode('Inline code'),
  highlight('Highlight'),
  textColor('Text colour'),
  bullets('Bullets'),
  numbering('Numbering'),
  todo('To-do'),
  outdent('Outdent'),
  indent('Indent'),
  paragraphStyle('Paragraph style'),
  formula('Formula'),
  formulaSyntax('Formula syntax'),
  mathCheatSheet('Cheat sheet', large: true),
  textBox('Text box', large: true),
  picture('Picture', large: true),
  pdf('PDF printout', large: true),
  insertFormula('Formula', large: true),
  select('Select', large: true),
  eraser('Eraser', large: true),
  pen('Pen', large: true),
  highlighter('Highlighter', large: true),
  inkColour('Ink colour', large: true),
  inkThickness('Thickness', large: true),
  zoomIn('Zoom in'),
  zoomOut('Zoom out'),
  zoomLevel('Actual size', large: true),
  fitPage('Fit page', large: true),
  pagePreview('Page preview', large: true),
  resetRibbon('Reset ribbon', large: true),
  mathFraction('Fraction', large: true),
  mathScript('Script', large: true),
  mathRadical('Radical', large: true),
  mathIntegral('Integral', large: true),
  mathLargeOperator('Large operator', large: true),
  mathBracket('Bracket', large: true),
  mathAccent('Accent', large: true),
  mathFunction('Function', large: true),
  mathMatrix('Matrix', large: true),
  mathGreek('Greek', large: true),
  mathOperators('Operators', large: true),
  mathRelations('Relations', large: true),
  mathArrows('Arrows', large: true),
  mathOther('Other', large: true),
  spelling('Spelling', large: true),
  spellingLanguages('Languages', large: true);

  const RibbonItem(this.label, {this.large = false});

  final String label;

  /// Takes the full height of the ribbon — a tall button with its name under
  /// the icon, or a gallery — rather than one of the two rows that small
  /// buttons are stacked in.
  final bool large;
}

/// A section of a tab, and the buttons it starts out with.
enum RibbonGroup implements ArrangementGroup<RibbonItem> {
  history(RibbonTab.home, 'History', <RibbonItem>[
    RibbonItem.undo,
    RibbonItem.redo,
  ]),
  font(RibbonTab.home, 'Font', <RibbonItem>[
    RibbonItem.fontSize,
    RibbonItem.bold,
    RibbonItem.italic,
    RibbonItem.underline,
    RibbonItem.strikethrough,
    RibbonItem.inlineCode,
    RibbonItem.highlight,
    RibbonItem.textColor,
  ]),
  paragraph(RibbonTab.home, 'Paragraph', <RibbonItem>[
    RibbonItem.bullets,
    RibbonItem.numbering,
    RibbonItem.todo,
    RibbonItem.outdent,
    RibbonItem.indent,
  ]),
  styles(RibbonTab.home, 'Styles', <RibbonItem>[RibbonItem.paragraphStyle]),
  math(RibbonTab.home, 'Formulas', <RibbonItem>[RibbonItem.formula]),
  text(RibbonTab.insert, 'Text', <RibbonItem>[RibbonItem.textBox]),
  files(RibbonTab.insert, 'Files', <RibbonItem>[
    RibbonItem.picture,
    RibbonItem.pdf,
  ]),
  symbols(RibbonTab.insert, 'Formulas', <RibbonItem>[RibbonItem.insertFormula]),
  tools(RibbonTab.draw, 'Tools', <RibbonItem>[
    RibbonItem.select,
    RibbonItem.eraser,
  ]),
  pens(RibbonTab.draw, 'Pens', <RibbonItem>[
    RibbonItem.pen,
    RibbonItem.highlighter,
  ]),
  colour(RibbonTab.draw, 'Colour', <RibbonItem>[RibbonItem.inkColour]),
  thickness(RibbonTab.draw, 'Thickness', <RibbonItem>[RibbonItem.inkThickness]),
  formulaSyntax(RibbonTab.math, 'Syntax', <RibbonItem>[
    RibbonItem.formulaSyntax,
    RibbonItem.mathCheatSheet,
  ]),
  structures(RibbonTab.math, 'Structures', <RibbonItem>[
    RibbonItem.mathFraction,
    RibbonItem.mathScript,
    RibbonItem.mathRadical,
    RibbonItem.mathIntegral,
    RibbonItem.mathLargeOperator,
    RibbonItem.mathBracket,
    RibbonItem.mathAccent,
    RibbonItem.mathFunction,
    RibbonItem.mathMatrix,
  ]),
  mathSymbols(RibbonTab.math, 'Symbols', <RibbonItem>[
    RibbonItem.mathGreek,
    RibbonItem.mathOperators,
    RibbonItem.mathRelations,
    RibbonItem.mathArrows,
    RibbonItem.mathOther,
  ]),
  proofing(RibbonTab.review, 'Proofing', <RibbonItem>[
    RibbonItem.spelling,
    RibbonItem.spellingLanguages,
  ]),
  zoom(RibbonTab.view, 'Zoom', <RibbonItem>[
    RibbonItem.zoomIn,
    RibbonItem.zoomOut,
    RibbonItem.zoomLevel,
    RibbonItem.fitPage,
  ]),
  page(RibbonTab.view, 'Page', <RibbonItem>[RibbonItem.pagePreview]),
  ribbon(RibbonTab.view, 'Ribbon', <RibbonItem>[RibbonItem.resetRibbon]);

  const RibbonGroup(this.tab, this.label, this.defaults);

  final RibbonTab tab;
  final String label;

  @override
  final List<RibbonItem> defaults;

  /// The sections of [tab], in order.
  static List<RibbonGroup> of(RibbonTab tab) => <RibbonGroup>[
    for (final group in values)
      if (group.tab == tab) group,
  ];
}

/// Which buttons each section of the ribbon holds, in order.
typedef RibbonLayout = Arrangement<RibbonGroup, RibbonItem>;
