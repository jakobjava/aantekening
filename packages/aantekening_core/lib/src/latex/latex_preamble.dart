/// What a LaTeX preamble sets for the formulas after it: commands, and
/// styles for TikZ pictures.
library;

import 'latex_source.dart';

/// The commands a preamble defines — `\newcommand`, `\def`,
/// `\DeclareMathOperator` — and the styles it gives TikZ pictures —
/// `\tikzset`, `\tikzstyle` — kept to be written into each formula,
/// so that each stands by itself.
final class LatexPreamble {
  /// A preamble that sets nothing, to be filled with [takeFrom].
  LatexPreamble();

  /// The preamble [source], what is in it that is not a definition or a
  /// style left in [leftOver].
  LatexPreamble.read(String source) {
    leftOver = takeFrom(source).trim();
  }

  /// What [LatexPreamble.read] found that sets nothing for formulas.
  String leftOver = '';

  /// The styles TikZ pictures are given, as picture options.
  String get tikzStyles => _styles.join(', ');
  final List<String> _styles = <String>[];

  bool get isEmpty => _macros.isEmpty && _styles.isEmpty;

  /// [source] with the definitions and the TikZ styles in it — those set
  /// outside a picture — taken out, and kept.
  String takeFrom(String source) => _takeStyles(_takeDefinitions(source));

  /// [formula] as it stands by itself: the commands kept written out, and a
  /// picture given the styles kept, first among its options.
  String apply(String formula) => styled(expand(formula));

  static final RegExp _picture = RegExp(
    r'^\s*(\\begin\s*\{tikzpicture\}|\\tikz(?![A-Za-z]))',
  );

  /// [formula], if it is a TikZ picture, with the styles kept put first
  /// among its options.
  String styled(String formula) {
    if (_styles.isEmpty) return formula;
    final begin = _picture.firstMatch(formula);
    if (begin == null) return formula;
    final open = LatexSource.skipSpaces(formula, begin.end);
    final options = open < formula.length && formula[open] == '[';
    final close = options ? LatexSource.closingBracket(formula, open) : open;
    final own = options ? formula.substring(open + 1, close - 1).trim() : '';
    return '${formula.substring(0, begin.end)}'
        '[${<String>[tikzStyles, if (own.isNotEmpty) own].join(', ')}]'
        '${formula.substring(close)}';
  }

  static final RegExp _style = RegExp(
    r'\\tikzset\s*\{|\\tikzstyle\s*\{([^{}]*)\}\s*=\s*\[',
  );
  static final RegExp _begins = RegExp(r'\\begin\s*\{tikzpicture\}');
  static final RegExp _ends = RegExp(r'\\end\s*\{tikzpicture\}');

  /// [source] without the TikZ styles set outside pictures, which are kept.
  String _takeStyles(String source) {
    final out = StringBuffer();
    var at = 0;
    for (final match in _style.allMatches(source)) {
      if (match.start < at) continue;
      // Inside a picture, a style is the picture's own.
      final before = source.substring(0, match.start);
      if (_begins.allMatches(before).length > _ends.allMatches(before).length) {
        continue;
      }
      final name = match.group(1);
      final close = name == null
          ? LatexSource.closingBrace(source, match.end - 1)
          : LatexSource.closingBracket(source, match.end - 1);
      final inner = source.substring(match.end, close - 1).trim();
      if (inner.isNotEmpty) {
        _styles.add(name == null ? inner : '${name.trim()}/.style={$inner}');
      }
      out.write(source.substring(at, match.start));
      at = close;
    }
    out.write(source.substring(at));
    return out.toString();
  }

  /// The commands defined: how many arguments each takes, its body, and
  /// the default of its first argument where that is optional.
  final Map<String, ({int arguments, String body, String? optional})> _macros =
      <String, ({int arguments, String body, String? optional})>{};

  static final RegExp _defining = RegExp(
    r'\\(?:(?:re)?newcommand|providecommand)\*?\s*'
    r'|\\DeclareMathOperator(\*?)\s*'
    r'|\\[gex]?def\s*',
  );

  /// [source] with the definitions in it taken out, and kept.
  String _takeDefinitions(String source) {
    final out = StringBuffer();
    var at = 0;
    for (final match in _defining.allMatches(source)) {
      if (match.start < at) continue;
      final defined = _read(source, match);
      if (defined == null) continue;
      out.write(source.substring(at, match.start));
      at = defined;
    }
    out.write(source.substring(at));
    return out.toString();
  }

  /// Reads the definition [match] begins, keeping it; returns where it
  /// ends, or null where it is not one this can read.
  int? _read(String source, RegExpMatch match) {
    final text = match[0]!;
    var at = match.end;
    // The name: `{\name}`, or `\name` by itself.
    String name;
    if (at < source.length && source[at] == '{') {
      final close = LatexSource.closingBrace(source, at);
      name = source.substring(at + 1, close - 1).trim();
      at = close;
    } else {
      final start = at;
      if (at < source.length && source[at] == r'\') at++;
      while (at < source.length &&
          LatexSource.isLetter(source.codeUnitAt(at))) {
        at++;
      }
      name = source.substring(start, at);
    }
    if (!name.startsWith(r'\') || name.length < 2) return null;
    at = LatexSource.skipSpaces(source, at);

    if (text.startsWith(r'\DeclareMathOperator')) {
      if (at >= source.length || source[at] != '{') return null;
      final close = LatexSource.closingBrace(source, at);
      final operator = source.substring(at + 1, close - 1);
      final starred = (match[1] ?? '').isNotEmpty;
      _macros[name] = (
        arguments: 0,
        body: '\\operatorname${starred ? '*' : ''}{$operator}',
        optional: null,
      );
      return close;
    }

    var arguments = 0;
    String? optional;
    if (text.startsWith(r'\def') ||
        text.startsWith(r'\gdef') ||
        text.startsWith(r'\edef') ||
        text.startsWith(r'\xdef')) {
      // Parameters as TeX writes them: `#1#2`.
      while (at + 1 < source.length && source[at] == '#') {
        arguments++;
        at += 2;
      }
    } else if (at < source.length && source[at] == '[') {
      final close = source.indexOf(']', at);
      if (close < 0) return null;
      arguments = int.tryParse(source.substring(at + 1, close).trim()) ?? 0;
      at = LatexSource.skipSpaces(source, close + 1);
      // A default for the first argument, which is then optional, given
      // in brackets where it is given.
      if (at < source.length && source[at] == '[') {
        final end = LatexSource.closingBracket(source, at);
        if (end > source.length || source[end - 1] != ']') return null;
        optional = source.substring(at + 1, end - 1);
        at = LatexSource.skipSpaces(source, end);
      }
    }
    if (at >= source.length || source[at] != '{') return null;
    final close = LatexSource.closingBrace(source, at);
    _macros[name] = (
      arguments: arguments,
      body: source.substring(at + 1, close - 1),
      optional: optional,
    );
    return close;
  }

  /// Whether [latex] is one thing to TeX: a character, or a command and the
  /// groups it takes.
  static bool _isUnit(String latex) =>
      latex.length == 1 ||
      RegExp(r'^\\[A-Za-z]+\*?(\{[^{}]*\})*$').hasMatch(latex);

  /// [source] with every use of a command defined written out, until none
  /// is left — or, for a definition that uses itself, a few rounds on.
  String expand(String source) {
    if (_macros.isEmpty) return source;
    final names = _macros.keys.toList()
      ..sort((a, b) => b.length.compareTo(a.length));
    final use = RegExp('(?:${names.map(RegExp.escape).join('|')})(?![A-Za-z])');
    var text = source;
    for (var round = 0; round < 16; round++) {
      var changed = false;
      final out = StringBuffer();
      var at = 0;
      for (final match in use.allMatches(text)) {
        if (match.start < at) continue;
        // `\\R` is a line break and an R, not a command named R.
        if (match.start > 0 && text[match.start - 1] == r'\') continue;
        final macro = _macros[match[0]]!;
        var end = match.end;
        final values = <String>[];
        if (macro.optional case final fallback? when macro.arguments > 0) {
          final open = LatexSource.skipSpaces(text, end);
          if (open < text.length && text[open] == '[') {
            final close = LatexSource.closingBracket(text, open);
            values.add(text.substring(open + 1, close - 1));
            end = close;
          } else {
            values.add(fallback);
          }
        }
        for (var i = values.length; i < macro.arguments; i++) {
          end = LatexSource.skipSpaces(text, end);
          if (end >= text.length) break;
          if (text[end] == '{') {
            final close = LatexSource.closingBrace(text, end);
            values.add(text.substring(end + 1, close - 1));
            end = close;
          } else if (text[end] == r'\') {
            var stop = end + 1;
            while (stop < text.length &&
                LatexSource.isLetter(text.codeUnitAt(stop))) {
              stop++;
            }
            if (stop == end + 1) stop++;
            values.add(text.substring(end, stop));
            end = stop;
          } else {
            values.add(text[end]);
            end++;
          }
        }
        var body = macro.body;
        for (var i = values.length; i >= 1; i--) {
          body = body.replaceAll('#$i', values[i - 1]);
        }
        out
          ..write(text.substring(at, match.start))
          // A command's body is a group of its own, so `\\R^n` raises the
          // whole of it, unless it is one already: a command and its
          // arguments, or one character.
          ..write(macro.arguments == 0 && !_isUnit(body) ? '{$body}' : body);
        // A command written as a word ends at the space after it; that
        // space was TeX's, not the text's.
        if (macro.arguments == 0 &&
            end < text.length &&
            text[end] == ' ' &&
            RegExp(r'[A-Za-z]$').hasMatch(match[0]!)) {
          end++;
        }
        at = end;
        changed = true;
      }
      out.write(text.substring(at));
      text = out.toString();
      if (!changed) break;
    }
    return text;
  }
}
