/// What the ribbon holds and where: its tabs, the sections of each tab, and
/// which buttons sit in which section, in what order.
///
/// The sections are fixed; the buttons can be dragged anywhere among them,
/// and the arrangement is saved, see [RibbonLayout].
library;

import 'package:flutter/foundation.dart';

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
  mathOther('Other', large: true);

  const RibbonItem(this.label, {this.large = false});

  final String label;

  /// Takes the full height of the ribbon — a tall button with its name under
  /// the icon, or a gallery — rather than one of the two rows that small
  /// buttons are stacked in.
  final bool large;
}

/// A section of a tab, and the buttons it starts out with.
enum RibbonGroup {
  history(RibbonTab.home, 'Undo', <RibbonItem>[
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
  math(RibbonTab.home, 'Formula', <RibbonItem>[RibbonItem.formula]),
  text(RibbonTab.insert, 'Text', <RibbonItem>[RibbonItem.textBox]),
  files(RibbonTab.insert, 'Files', <RibbonItem>[
    RibbonItem.picture,
    RibbonItem.pdf,
  ]),
  symbols(RibbonTab.insert, 'Formula', <RibbonItem>[RibbonItem.insertFormula]),
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
  zoom(RibbonTab.view, 'Zoom', <RibbonItem>[
    RibbonItem.zoomIn,
    RibbonItem.zoomOut,
    RibbonItem.zoomLevel,
    RibbonItem.fitPage,
  ]),
  ribbon(RibbonTab.view, 'Ribbon', <RibbonItem>[RibbonItem.resetRibbon]);

  const RibbonGroup(this.tab, this.label, this.defaults);

  final RibbonTab tab;
  final String label;

  /// The buttons this section holds before anything is moved.
  final List<RibbonItem> defaults;

  /// The sections of [tab], in order.
  static List<RibbonGroup> of(RibbonTab tab) => <RibbonGroup>[
    for (final group in values)
      if (group.tab == tab) group,
  ];
}

/// Which buttons each section holds, in order.
///
/// Every [RibbonItem] is in exactly one section, so moving buttons around can
/// never lose one or show one twice.
@immutable
class RibbonLayout {
  RibbonLayout._(Map<RibbonGroup, List<RibbonItem>> items)
    : _items = Map<RibbonGroup, List<RibbonItem>>.unmodifiable(
        <RibbonGroup, List<RibbonItem>>{
          for (final group in RibbonGroup.values)
            group: List<RibbonItem>.unmodifiable(
              items[group] ?? const <RibbonItem>[],
            ),
        },
      );

  /// Every button where it starts out.
  static final RibbonLayout defaults = RibbonLayout._(
    <RibbonGroup, List<RibbonItem>>{
      for (final group in RibbonGroup.values) group: group.defaults,
    },
  );

  final Map<RibbonGroup, List<RibbonItem>> _items;

  /// The buttons in [group], in order.
  List<RibbonItem> itemsIn(RibbonGroup group) => _items[group]!;

  /// The section holding [item].
  RibbonGroup groupOf(RibbonItem item) =>
      RibbonGroup.values.firstWhere((group) => itemsIn(group).contains(item));

  bool get isDefault => this == defaults;

  /// [item] moved into [group], in front of the button now at [index] there,
  /// or at the end for an index past the last.
  RibbonLayout move(RibbonItem item, RibbonGroup group, int index) {
    final from = groupOf(item);
    final items = <RibbonGroup, List<RibbonItem>>{
      for (final entry in _items.entries) entry.key: List.of(entry.value),
    };
    var at = index.clamp(0, items[group]!.length);
    // Taking the button out first shifts everything after it along by one.
    if (from == group && items[from]!.indexOf(item) < at) at--;
    items[from]!.remove(item);
    items[group]!.insert(at, item);
    return RibbonLayout._(items);
  }

  Map<String, Object?> toJson() => <String, Object?>{
    'version': 1,
    'groups': <String, Object?>{
      for (final group in RibbonGroup.values)
        group.name: <String>[for (final item in itemsIn(group)) item.name],
    },
  };

  /// The layout saved by [toJson], or the defaults if [json] is not one.
  ///
  /// Unknown names are skipped and a button named twice keeps its first
  /// place. Buttons the saved layout does not mention — added in a later
  /// version — appear where they start out.
  static RibbonLayout fromJson(Object? json) {
    if (json is! Map || json['groups'] is! Map) return defaults;
    final stored = json['groups'] as Map;
    final names = RibbonItem.values.asNameMap();
    final placed = <RibbonItem>{};
    final items = <RibbonGroup, List<RibbonItem>>{
      for (final group in RibbonGroup.values) group: <RibbonItem>[],
    };
    for (final group in RibbonGroup.values) {
      final saved = stored[group.name];
      if (saved is! List) continue;
      for (final name in saved) {
        final item = names[name];
        if (item != null && placed.add(item)) items[group]!.add(item);
      }
    }
    for (final group in RibbonGroup.values) {
      for (final item in group.defaults) {
        if (placed.add(item)) items[group]!.add(item);
      }
    }
    return RibbonLayout._(items);
  }

  @override
  bool operator ==(Object other) =>
      other is RibbonLayout &&
      RibbonGroup.values.every(
        (group) => listEquals(other.itemsIn(group), itemsIn(group)),
      );

  @override
  int get hashCode => Object.hashAll(<Object>[
    for (final group in RibbonGroup.values) Object.hashAll(itemsIn(group)),
  ]);
}
