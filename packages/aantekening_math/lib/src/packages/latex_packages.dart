/// The packages LaTeX documents use for physics, chemistry and units —
/// physics, mhchem and siunitx — written out as the LaTeX the typesetter
/// reads.
///
/// They are read only in formulas brought in as LaTeX: a formula typed here
/// can be switched to Simple syntax and back, which has no words for them.
library;

import 'dart:math' as math;

import 'package:aantekening_core/aantekening_core.dart' show LatexSource;

part 'mhchem.dart';
part 'physics.dart';
part 'siunitx.dart';

/// What a package's command is written out as, given what follows it; null
/// to leave it as it is.
typedef _Command = String? Function(_Arguments arguments);

abstract final class LatexPackages {
  static final Map<String, _Command> _commands = <String, _Command>{
    ..._physics,
    ..._siunitx,
    ..._mhchem,
  };

  /// The most commands one formula has written out, so that one written in
  /// terms of itself cannot go on for ever.
  static const int _maxSteps = 4000;

  /// [latex] with the packages' commands written out.
  static String expand(String latex) {
    var text = latex;
    var at = 0;
    var steps = 0;
    while (at < text.length) {
      final slash = text.indexOf(r'\', at);
      if (slash < 0) break;
      var end = slash + 1;
      while (end < text.length && LatexSource.isLetter(text.codeUnitAt(end))) {
        end++;
      }
      // `\\`, `\{` and the like are a character, not a command.
      if (end == slash + 1) {
        at = slash + 2;
        continue;
      }
      final command = _commands[text.substring(slash + 1, end)];
      final arguments = _Arguments(text, end);
      final written = command?.call(arguments);
      if (written == null || ++steps > _maxSteps) {
        at = end;
        continue;
      }
      // What it is written as is read again, for the commands in it.
      text = text.replaceRange(slash, arguments.at, written);
      at = slash;
    }
    return text;
  }
}

/// What follows a command, read as the command asks.
class _Arguments {
  _Arguments(this.source, this.at);

  final String source;
  int at;

  void _skipSpaces() => at = LatexSource.skipSpaces(source, at);

  String? get _next => at < source.length ? source[at] : null;

  /// Whether a `*` comes straight after the command, moving past it.
  bool star() {
    if (_next != '*') return false;
    at++;
    return true;
  }

  /// What is in the `[…]` that comes next, if one does.
  String? optional() {
    _skipSpaces();
    if (_next != '[') return null;
    final close = LatexSource.closingBracket(source, at);
    final inner = source.substring(at + 1, close - 1);
    at = close;
    return inner;
  }

  /// Whether a braced group comes next.
  bool get seesGroup {
    _skipSpaces();
    return _next == '{';
  }

  /// The argument that comes next: what is in a braced group, or one
  /// command or character.
  String group() {
    _skipSpaces();
    final next = _next;
    if (next == null) return '';
    if (next == '{') {
      final close = LatexSource.closingBrace(source, at);
      final inner = source.substring(at + 1, close - 1);
      at = close;
      return inner;
    }
    var end = at + 1;
    if (next == r'\') {
      while (end < source.length &&
          LatexSource.isLetter(source.codeUnitAt(end))) {
        end++;
      }
      if (end == at + 1) end++;
    }
    final token = source.substring(at, math.min(end, source.length));
    at = math.min(end, source.length);
    return token;
  }

  /// The braced group that comes next, if one does.
  String? groupIfAny() => seesGroup ? group() : null;

  static const Map<String, String> _closing = <String, String>{
    '(': ')',
    '[': ']',
    '{': '}',
    '|': '|',
  };

  /// What comes next between brackets of any kind — `(…)`, `[…]`, `{…}`
  /// or `|…|` — and which they are; null if no bracket comes next.
  ({String open, String inner})? delimited() {
    _skipSpaces();
    final open = _next;
    final close = _closing[open];
    if (open == null || close == null) return null;
    if (open == '{') {
      final end = LatexSource.closingBrace(source, at);
      final inner = source.substring(at + 1, end - 1);
      at = end;
      return (open: open, inner: inner);
    }
    var depth = 0;
    for (var i = at; i < source.length; i++) {
      final char = source[i];
      if (char == r'\') {
        i++;
      } else if (char == '{') {
        i = LatexSource.closingBrace(source, i) - 1;
      } else if (i > at && char == close && (open == close || depth == 1)) {
        final inner = source.substring(at + 1, i);
        at = i + 1;
        return (open: open, inner: inner);
      } else if (char == open) {
        depth++;
      } else if (char == close) {
        depth--;
      }
    }
    return null;
  }
}

/// [inner] between [open] and its closing bracket, sized to it unless
/// [sized] is false.
String _between(String open, String inner, {bool sized = true}) {
  final (left, right) = switch (open) {
    '[' => ('[', ']'),
    '{' => (r'\{', r'\}'),
    '|' => (r'\lvert', r'\rvert'),
    _ => ('(', ')'),
  };
  return sized ? '\\left$left $inner \\right$right' : '$left $inner $right';
}
