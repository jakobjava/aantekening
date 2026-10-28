/// Text lying on a page that the canvas does not lay out itself — a PDF
/// page's — for the select tool to select and to follow the links of.
library;

import 'package:aantekening_core/aantekening_core.dart';
import 'package:flutter/widgets.dart';

/// Text on a page beneath what the canvas picks up, as a reader shows it:
/// dragged across with the select tool it is selected, a word of it by a
/// double-click, and a link in it opened by a click with Ctrl held. A
/// press on it that does not move does what it would have without it.
///
/// Each point is in page units; [hit] is what the press would otherwise
/// pick up, if anything: text beneath something else lying over it is not
/// pressed on.
abstract interface class CanvasText {
  /// Whether there is text at [page], beneath [hit], to select from.
  bool selectsAt(Offset page, NoteElement? hit);

  /// Selects the text from where a drag began, [from], to where it has
  /// got, [to].
  void select(Offset from, Offset to);

  /// Selects the word at [page].
  void selectWord(Offset page);

  /// Whether a link lies at [page], beneath [hit].
  bool linkAt(Offset page, NoteElement? hit);

  /// Opens the link at [page].
  void openLink(Offset page);
}
