/// The shortcuts of text being typed in and of the page itself, which are
/// fixed: the same in every text box, so they can be learnt once.
library;

import 'package:flutter/services.dart';

import 'key_chord.dart';

/// A fixed shortcut: what it does, its keys, and what can be typed instead.
enum EditorKey {
  undo('Undo', <KeyChord>[KeyChord(LogicalKeyboardKey.keyZ, control: true)]),
  redo('Redo', <KeyChord>[
    KeyChord(LogicalKeyboardKey.keyZ, control: true, shift: true),
    KeyChord(LogicalKeyboardKey.keyY, control: true),
  ]),
  cut('Cut', <KeyChord>[KeyChord(LogicalKeyboardKey.keyX, control: true)]),
  copy('Copy', <KeyChord>[KeyChord(LogicalKeyboardKey.keyC, control: true)]),
  paste('Paste', <KeyChord>[KeyChord(LogicalKeyboardKey.keyV, control: true)]),
  pasteText('Paste text only', <KeyChord>[
    KeyChord(LogicalKeyboardKey.keyV, control: true, shift: true),
  ]),
  selectAll('Select everything', <KeyChord>[
    KeyChord(LogicalKeyboardKey.keyA, control: true),
  ]),
  bold('Bold', <KeyChord>[KeyChord(LogicalKeyboardKey.keyB, control: true)]),
  italic('Italic', <KeyChord>[
    KeyChord(LogicalKeyboardKey.keyI, control: true),
  ]),
  underline('Underline', <KeyChord>[
    KeyChord(LogicalKeyboardKey.keyU, control: true),
  ]),
  strikethrough('Strikethrough', <KeyChord>[
    KeyChord(LogicalKeyboardKey.minus, control: true),
  ]),
  inlineCode('Inline code', <KeyChord>[
    KeyChord(LogicalKeyboardKey.keyE, control: true),
  ]),
  highlight('Highlight', <KeyChord>[
    KeyChord(LogicalKeyboardKey.keyH, control: true, shift: true),
  ]),
  bullets('Bullets', <KeyChord>[
    KeyChord(LogicalKeyboardKey.period, control: true),
  ], typed: '- '),
  numbering('Numbering', <KeyChord>[
    KeyChord(LogicalKeyboardKey.slash, control: true),
  ], typed: '1. '),
  todo('To-do', <KeyChord>[
    KeyChord(LogicalKeyboardKey.digit1, control: true),
  ], typed: '[] '),
  tick('Tick a to-do', <KeyChord>[
    KeyChord(LogicalKeyboardKey.enter, control: true),
  ]),
  indent('Indent', <KeyChord>[KeyChord(LogicalKeyboardKey.tab)]),
  outdent('Outdent', <KeyChord>[KeyChord(LogicalKeyboardKey.tab, shift: true)]),
  normal('Normal text', <KeyChord>[
    KeyChord(LogicalKeyboardKey.keyN, control: true, shift: true),
  ]),
  heading1('Heading 1', <KeyChord>[
    KeyChord(LogicalKeyboardKey.digit1, control: true, alt: true),
  ], typed: '# '),
  heading2('Heading 2', <KeyChord>[
    KeyChord(LogicalKeyboardKey.digit2, control: true, alt: true),
  ], typed: '## '),
  heading3('Heading 3', <KeyChord>[
    KeyChord(LogicalKeyboardKey.digit3, control: true, alt: true),
  ], typed: '### '),
  quote('Quote', <KeyChord>[], typed: '> '),
  formula('Formula', <KeyChord>[
    KeyChord(LogicalKeyboardKey.equal, alt: true),
    KeyChord(LogicalKeyboardKey.keyM, control: true),
  ]),
  formulaSyntax('Formula syntax: LaTeX or linear', <KeyChord>[
    KeyChord(LogicalKeyboardKey.keyM, control: true, shift: true),
  ]),
  finishFormula('Finish the formula', <KeyChord>[
    KeyChord(LogicalKeyboardKey.enter),
  ]),
  deleteSelection('Delete what is selected', <KeyChord>[
    KeyChord(LogicalKeyboardKey.delete),
  ]),
  nudge(
    'Move what is selected',
    <KeyChord>[],
    written: 'Arrow keys, with Shift ten times as far',
  ),
  deselect('Stop typing, or pick nothing', <KeyChord>[
    KeyChord(LogicalKeyboardKey.escape),
  ]),
  showTab('Show tab 1 to 9', <KeyChord>[
    KeyChord(LogicalKeyboardKey.digit1, alt: true),
    KeyChord(LogicalKeyboardKey.digit2, alt: true),
    KeyChord(LogicalKeyboardKey.digit3, alt: true),
    KeyChord(LogicalKeyboardKey.digit4, alt: true),
    KeyChord(LogicalKeyboardKey.digit5, alt: true),
    KeyChord(LogicalKeyboardKey.digit6, alt: true),
    KeyChord(LogicalKeyboardKey.digit7, alt: true),
    KeyChord(LogicalKeyboardKey.digit8, alt: true),
    KeyChord(LogicalKeyboardKey.digit9, alt: true),
  ], written: 'Alt+1 to Alt+9');

  const EditorKey(this.label, this.chords, {this.typed, this.written});

  final String label;
  final List<KeyChord> chords;

  /// What can be typed at the start of a line instead, or said about the
  /// keys where they are not one chord.
  final String? typed;

  /// How the keys are written where they are not simply [chords].
  final String? written;

  /// The keys as written: "Ctrl+B", "Ctrl+Shift+Z or Ctrl+Y".
  String get keys => written ?? chords.map((chord) => chord.label).join(' or ');

  /// [label] with its keys, as a tooltip gives them: "Bold  (Ctrl+B)".
  String get tooltip => tooltipOf(label);

  /// [text] with this key's shortcut after it.
  String tooltipOf(String text) {
    final typed = this.typed;
    final keys = <String>[
      if (chords.isNotEmpty || written != null) this.keys,
      if (typed != null)
        chords.isEmpty && written == null
            ? 'type "$typed"'
            : 'or type "$typed"',
    ].join('  ');
    return keys.isEmpty ? text : '$text  ($keys)';
  }

  /// Every chord typing and the page take, which a command's shortcut
  /// should not — all but the window's own Alt and a digit.
  static final Set<KeyChord> reserved = <KeyChord>{
    for (final key in values)
      if (key != showTab) ...key.chords,
  };
}
