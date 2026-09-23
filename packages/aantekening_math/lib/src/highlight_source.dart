/// Highlights in the source of a formula, as it is typed.
library;

import 'package:aantekening_core/aantekening_core.dart';
import 'package:flutter_math_fork/tex.dart' show TexParser, TexParserSettings;

import 'ast.dart';
import 'linear_math.dart';
import 'renderer_latex.dart';
import 'symbols.dart';

/// Where a highlight lies in a formula's source: the whole of it, from its
/// command to its closing bracket, the part it marks, and its colour.
typedef HighlightSpan = ({
  int start,
  int end,
  int bodyStart,
  int bodyEnd,
  int color,
});

/// Marking part of a formula's source with a highlighter, and finding the
/// marks already there, in whichever syntax it is typed.
///
/// A highlight is the syntax's own construct — `highlight(…)` in the linear
/// syntax, `\colorbox{#FFEF9D}{$…$}` in LaTeX — so what is highlighted is
/// part of the formula, typeset with it, and kept as it is written.
abstract final class HighlightSource {
  static final RegExp _linear = RegExp(
    r'highlight\s*\(\s*(?:(#[0-9A-Fa-f]{6})\s*,\s*)?',
  );
  static final RegExp _latex = RegExp(r'\\colorbox\{(#[0-9A-Fa-f]{6})\}\{\$');

  /// [body], part of a formula's source in [syntax], highlighted in
  /// [color], and where [body] starts in what is returned.
  static ({String text, int body}) wrap(
    String body,
    MathMode syntax,
    int color,
  ) {
    final text = switch (syntax) {
      MathMode.latex => HighlightNode.latexOf(body, color),
      MathMode.linear => HighlightNode.linearOf(body, color),
    };
    return (
      text: text,
      body: text.length - body.length - (syntax == MathMode.latex ? 2 : 1),
    );
  }

  /// The innermost highlight in [source], typed in [syntax], whose marked
  /// part holds [start]..[end] — or which is [start]..[end] itself, or, for a
  /// caret, which it is anywhere in, the brackets included — or null where
  /// none does.
  static HighlightSpan? around(
    String source,
    int start,
    int end,
    MathMode syntax,
  ) {
    HighlightSpan? innermost;
    for (final span in all(source, syntax)) {
      final holds = start == end
          ? span.start <= start && end <= span.end
          : (span.bodyStart <= start && end <= span.bodyEnd) ||
                (span.start == start && span.end == end);
      if (holds && (innermost == null || span.start > innermost.start)) {
        innermost = span;
      }
    }
    return innermost;
  }

  /// [source] with every highlight in it taken off, what each marked left in
  /// its place.
  static String unwrapAll(String source, MathMode syntax) {
    var text = source;
    while (true) {
      // The highlight that starts last holds no other.
      final last = all(text, syntax).lastOrNull;
      if (last == null) return text;
      text = text.replaceRange(
        last.start,
        last.end,
        text.substring(last.bodyStart, last.bodyEnd),
      );
    }
  }

  /// The highlight that is the whole of [source] but for space around it, if
  /// [source] is one.
  static HighlightSpan? whole(String source, MathMode syntax) {
    final (start, end) = _trim(source, 0, source.length);
    return start < end ? around(source, start, end, syntax) : null;
  }

  /// The part of [source], typed in [syntax], to highlight for a selection
  /// of [start]..[end]; null where it holds nothing to highlight.
  ///
  /// A selection is whatever the pointer passed over: half a word, one
  /// bracket of a pair, an operator with nothing after it. Highlighted as it
  /// is, it would break the formula, leaving empty boxes where its parts
  /// were. So it is widened to whole words, both brackets of a pair — with
  /// the function they belong to — and whole highlights, and an operator
  /// left hanging at either end is let go. Where that is still not a part of
  /// the formula that reads on its own and leaves the rest reading as before,
  /// the smallest bracketed part around the selection is taken, or else the
  /// whole formula.
  static ({int start, int end})? fit(
    String source,
    int start,
    int end,
    MathMode syntax,
  ) {
    final reads = _Reading(source, syntax);
    var (s, e) = _trim(source, start, end);
    if (s >= e) return null;
    (s, e) = _widen(source, s, e, syntax);
    // An operator at either end joins the part to what is beside it: marked
    // with it, the part would be set as a sign, not as a term.
    final (us, ue) = _unjoined(source, s, e);
    if (us < ue) {
      (s, e) = (us, ue);
    } else if (!reads.whole(s, e)) {
      // Only operators were selected, which mean nothing on their own.
      return null;
    }
    if (reads.whole(s, e)) return (start: s, end: e);

    final groups =
        _pairs(
            source,
            syntax,
          ).where((pair) => pair.$1 < start && end <= pair.$2).toList()
          ..sort((a, b) => (a.$2 - a.$1).compareTo(b.$2 - b.$1));
    for (final (open, close) in groups) {
      for (final (from, to) in <(int, int)>[
        (open + 1, close),
        (_functionBefore(source, open, syntax), close + 1),
      ]) {
        final (ts, te) = _trim(source, from, to);
        if (ts < te && reads.whole(ts, te)) return (start: ts, end: te);
      }
    }
    final (ts, te) = _trim(source, 0, source.length);
    return ts < te && reads.whole(ts, te) ? (start: ts, end: te) : null;
  }

  /// Characters that join the parts of a formula rather than being one.
  static const String _joiners = r'+-*/^_=<>,;~:&|\';

  /// [start]..[end] without the operators joining it to what is beside it:
  /// any at its end, and one at its start that follows something, where it
  /// is not a sign.
  static (int, int) _unjoined(String source, int start, int end) {
    var (s, e) = (start, end);
    while (s < e) {
      if (_joiners.contains(source[e - 1])) {
        (s, e) = _trim(source, s, e - 1);
      } else if (_joiners.contains(source[s]) && _follows(source, s)) {
        (s, e) = _trim(source, s + 1, e);
      } else {
        break;
      }
    }
    return (s, e);
  }

  /// Whether a term comes before [index], making an operator there one that
  /// joins rather than a sign.
  static bool _follows(String source, int index) {
    var i = index - 1;
    while (i >= 0 && source[i].trim().isEmpty) {
      i--;
    }
    return i >= 0 &&
        !_joiners.contains(source[i]) &&
        !'([{'.contains(source[i]);
  }

  static (int, int) _trim(String source, int start, int end) {
    var s = start;
    var e = end;
    while (s < e && source[s].trim().isEmpty) {
      s++;
    }
    while (e > s && source[e - 1].trim().isEmpty) {
      e--;
    }
    return (s, e);
  }

  /// [start]..[end] widened until it cuts through no word, no pair of
  /// brackets and no highlight.
  static (int, int) _widen(String source, int start, int end, MathMode syntax) {
    final latex = syntax == MathMode.latex;
    final pairs = _pairs(source, syntax);
    final highlights = all(source, syntax).toList();
    var s = start;
    var e = end;
    while (true) {
      final (was, wasEnd) = (s, e);
      // Whole words, and in LaTeX whole commands.
      while (s > 0 && _isLetter(source[s - 1]) && _isLetter(source[s])) {
        s--;
      }
      if (latex && s > 0 && source[s - 1] == r'\') s--;
      while (e < source.length &&
          _isLetter(source[e - 1]) &&
          _isLetter(source[e])) {
        e++;
      }
      if (latex && source[e - 1] == r'\' && e < source.length) {
        e++;
        while (e < source.length &&
            _isLetter(source[e - 1]) &&
            _isLetter(source[e])) {
          e++;
        }
      }
      // Both brackets of a pair, and the function whose they are.
      for (final (open, close) in pairs) {
        final opens = s <= open && open < e;
        final closes = s <= close && close < e;
        if (!opens && !closes) continue;
        // A function's brackets belong to it: `sqrt` highlighted without its
        // brackets would show them under the root.
        if (!opens || s == open) s = _functionBefore(source, open, syntax);
        if (!closes) e = close + 1;
      }
      // Whole highlights, unless the selection lies within what one marks.
      for (final highlight in highlights) {
        final overlaps = s < highlight.end && e > highlight.start;
        final within = highlight.bodyStart <= s && e <= highlight.bodyEnd;
        final holds = s <= highlight.start && highlight.end <= e;
        if (!overlaps || within || holds) continue;
        s = s < highlight.start ? s : highlight.start;
        e = e > highlight.end ? e : highlight.end;
      }
      if (s == was && e == wasEnd) return (s, e);
    }
  }

  /// Where the brackets in [source] pair up, each as the offsets of its
  /// opening and closing bracket; in the linear syntax quoted text and LaTeX
  /// in backticks too, which are read whole.
  static List<(int, int)> _pairs(String source, MathMode syntax) {
    final latex = syntax == MathMode.latex;
    const openers = <String, String>{')': '(', ']': '[', '}': '{'};
    final pairs = <(int, int)>[];
    final open = <(int, String)>[];
    for (var i = 0; i < source.length; i++) {
      final char = source[i];
      if (latex && char == r'\') {
        // An escaped brace is not a bracket.
        i++;
        continue;
      }
      if (!latex && (char == '"' || char == '`')) {
        final close = source.indexOf(char, i + 1);
        if (close < 0) break;
        pairs.add((i, close));
        i = close;
        continue;
      }
      if (latex ? char == '{' : '([{'.contains(char)) {
        open.add((i, char));
      } else if (openers.containsKey(char) && (!latex || char == '}')) {
        if (open.isNotEmpty && open.last.$2 == openers[char]) {
          pairs.add((open.removeLast().$1, i));
        }
      }
    }
    return pairs;
  }

  /// Where the function or command whose bracket opens at [open] starts —
  /// `sqrt(`, `\frac{` — or [open] itself where no such word is before it.
  static int _functionBefore(String source, int open, MathMode syntax) {
    var start = open;
    while (start > 0 && _isLetter(source[start - 1])) {
      start--;
    }
    if (start == open) return open;
    if (syntax == MathMode.latex) {
      return start > 0 && source[start - 1] == r'\' ? start - 1 : open;
    }
    final symbol = mathSymbols[source.substring(start, open)];
    return symbol != null && symbol.role != SymbolRole.atom ? start : open;
  }

  static bool _isLetter(String char) {
    final code = char.codeUnitAt(0);
    return (code >= 0x41 && code <= 0x5A) || (code >= 0x61 && code <= 0x7A);
  }

  /// Every complete highlight in [source], typed in [syntax], in order.
  static Iterable<HighlightSpan> all(String source, MathMode syntax) sync* {
    final latex = syntax == MathMode.latex;
    for (final match in (latex ? _latex : _linear).allMatches(source)) {
      final bodyStart = match.end;
      final close = latex
          ? _closingBrace(source, bodyStart)
          : _closingParen(source, bodyStart);
      if (close == null) continue;
      // LaTeX's mark ends `$}`, the linear syntax's `)`.
      if (latex && (close == bodyStart || source[close - 1] != r'$')) {
        continue;
      }
      final hex = match.group(1);
      yield (
        start: match.start,
        end: close + 1,
        bodyStart: bodyStart,
        bodyEnd: latex ? close - 1 : close,
        color: hex == null
            ? HighlightNode.defaultColor
            : int.parse(hex.substring(1), radix: 16),
      );
    }
  }

  /// Where the brace closing the group that [from] is inside is, or null
  /// where it is never closed.
  static int? _closingBrace(String source, int from) {
    var depth = 0;
    for (var i = from; i < source.length; i++) {
      switch (source[i]) {
        case r'\':
          i++;
        case '{':
          depth++;
        case '}':
          if (depth == 0) return i;
          depth--;
      }
    }
    return null;
  }

  /// Where the bracket closing the one opened before [from] is, or null
  /// where it is never closed. Quoted text and LaTeX in backticks are passed
  /// over, as the parser passes over them.
  static int? _closingParen(String source, int from) {
    var depth = 0;
    for (var i = from; i < source.length; i++) {
      switch (source[i]) {
        case '"' || '`':
          final quote = source.indexOf(source[i], i + 1);
          if (quote < 0) return null;
          i = quote;
        case '(':
          depth++;
        case ')':
          if (depth == 0) return i;
          depth--;
      }
    }
    return null;
  }
}

/// Whether a part of a formula's source reads, measured against how the whole
/// of it reads as it is.
class _Reading {
  _Reading(this.source, this.syntax) : _before = _problems(source, syntax);

  final String source;
  final MathMode syntax;
  final int _before;

  /// Whether [start]..[end] of the source reads on its own, and highlighting
  /// it leaves the formula reading no worse than before.
  bool whole(int start, int end) {
    final part = source.substring(start, end);
    final marked = source.replaceRange(
      start,
      end,
      HighlightSource.wrap(part, syntax, HighlightNode.defaultColor).text,
    );
    return _problems(part, syntax) == 0 && _problems(marked, syntax) <= _before;
  }

  /// How many things are wrong with [source]: the complaints about it in
  /// the linear syntax, and in LaTeX whether the typesetter reads it at all.
  static int _problems(String source, MathMode syntax) {
    switch (syntax) {
      case MathMode.linear:
        return LinearMath.translate(source).diagnostics.length;
      case MathMode.latex:
        try {
          TexParser(
            RendererLatex.of(source),
            const TexParserSettings(),
          ).parse();
          return 0;
        } on Object {
          return 1;
        }
    }
  }
}
