/// Copying and pasting on a page: text, formulas, pictures, whole boxes and
/// drawings.
library;

import 'package:aantekening_core/aantekening_core.dart';
import 'package:flutter/services.dart';

/// Something to paste.
sealed class NoteClip {
  const NoteClip(this.plain);

  /// What other applications receive, and what Paste Text Only pastes.
  final String plain;
}

/// Text from elsewhere, or pasted as text only.
final class PlainClip extends NoteClip {
  const PlainClip(super.plain);
}

/// Part of a text box: its text with its formatting, formulas, pictures and
/// PDF pages.
final class TextClip extends NoteClip {
  const TextClip(super.plain, this.blocks);

  final List<TextBlock> blocks;
}

/// Whole things on the page: text boxes, pictures, PDF pages, drawings.
final class ElementsClip extends NoteClip {
  ElementsClip(List<NoteElement> elements)
    : elements = List<NoteElement>.unmodifiable(elements),
      super(_plainOf(elements));

  final List<NoteElement> elements;

  /// The things as a text box's text, read top to bottom: the text boxes'
  /// text, and pictures and PDF pages as objects in it; null where any of
  /// them cannot go into text, as a drawing cannot.
  List<TextBlock>? get asBlocks {
    final ordered = List<NoteElement>.of(elements)
      ..sort((a, b) {
        final byTop = a.frame.y.compareTo(b.frame.y);
        return byTop != 0 ? byTop : a.frame.x.compareTo(b.frame.x);
      });
    final blocks = <TextBlock>[];
    for (final element in ordered) {
      if (element is TextElement) {
        blocks.addAll(element.blocks);
        continue;
      }
      final embed = element.asEmbed;
      if (embed == null) return null;
      blocks.add(TextBlock.embedded(embed));
    }
    return blocks;
  }

  static String _plainOf(List<NoteElement> elements) {
    final out = StringBuffer();
    for (final element in elements) {
      element.writeSearchText(out);
    }
    return out.toString().trim();
  }
}

/// What was last copied on a page, and the system clipboard.
///
/// The system clipboard carries only text, which is what other applications
/// receive. What was copied here is kept here, and pasted as long as the
/// system clipboard still holds its text; once something else has been
/// copied, that is pasted instead. A copy with no text of its own — a
/// picture — leaves the system clipboard empty, so it pastes until text is
/// copied elsewhere.
abstract final class NoteClipboard {
  static NoteClip? _held;

  /// Copies [clip].
  static Future<void> copy(NoteClip clip) async {
    _held = clip;
    await Clipboard.setData(ClipboardData(text: clip.plain));
  }

  /// What pasting gives, or null where there is nothing to paste.
  static Future<NoteClip?> read() async {
    final text = (await Clipboard.getData(Clipboard.kTextPlain))?.text ?? '';
    final held = _held;
    if (held != null && held.plain == text) return held;
    return text.isEmpty ? null : PlainClip(text);
  }

  /// What pasting as text only gives, or null where there is no text.
  static Future<PlainClip?> readText() async {
    final clip = await read();
    return clip == null || clip.plain.isEmpty ? null : PlainClip(clip.plain);
  }
}
