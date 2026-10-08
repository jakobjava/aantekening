/// The modes the window is in, as in vim: what the keys do depends on
/// whether the page is being moved about, typed on, drawn on, selected
/// from, or asked about.
library;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../look/appearance.dart';
import '../look/tones.dart';
import '../shell/tabs.dart';

/// What the keys do just now.
enum EditorMode {
  /// Moving about the page and from page to page, every letter a command.
  normal('Normal', null),

  /// Typing in a text box: the keys type.
  insert('Insert', Color(0xFF2E7BFF)),

  /// Drawing with the pen, the highlighter, shapes or the eraser.
  draw('Draw', Color(0xFFFF9500)),

  /// Picking out what is on the page, by lasso or by the keys.
  select('Select', Color(0xFF9B51FF)),

  /// Asking the AI about what is open, and studying it.
  ai('AI', Color(0xFF00C27A));

  const EditorMode(this.label, this._hue);

  final String label;

  /// The mode's own colour, or null for normal, which has none but the
  /// interface's.
  final Color? _hue;

  /// The mode's colour, as it shows against [tones]' base: normal mode's is
  /// the interface's own emphasis.
  Color colourOn(Tones tones) => switch (_hue) {
    final hue? => readableOn(hue, tones.base),
    null => tones.emphasis,
  };
}

/// The mode the page is in, as the page editor reports it: typing while a
/// text box has the caret, drawing while a pen is in hand, and so on.
class PageMode extends Notifier<EditorMode> {
  @override
  EditorMode build() => EditorMode.normal;

  // A setter would read as a field; this is the page saying what it is in.
  // ignore: use_setters_to_change_properties
  void report(EditorMode mode) => state = mode;
}

final pageModeProvider = NotifierProvider<PageMode, EditorMode>(PageMode.new);

/// The mode the window is in: the AI's while the tab shows it, else the
/// page's.
final editorModeProvider = Provider<EditorMode>(
  (ref) => ref.watch(tabsProvider.select((tabs) => tabs.current.ai))
      ? EditorMode.ai
      : ref.watch(pageModeProvider),
);
