/// Copying rich text between text boxes.
library;

import 'package:aantekening_core/aantekening_core.dart';

/// Rich text copied from a text box, kept so that pasting it back keeps its
/// formatting, formulas and embeds. The system clipboard carries only the
/// plain text, which is what other applications receive.
abstract final class RichClipboard {
  static String? _plain;
  static List<TextBlock>? _fragment;

  static void store(String plain, List<TextBlock> fragment) {
    _plain = plain;
    _fragment = fragment;
  }

  /// The rich fragment matching [plain], if it was copied from here.
  static List<TextBlock>? match(String plain) =>
      plain == _plain ? _fragment : null;
}
