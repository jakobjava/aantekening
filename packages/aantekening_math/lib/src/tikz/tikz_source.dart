/// Reading TikZ source: its brackets, its options and colours, and the
/// loops written out.
library;

import 'dart:math' as math;
import 'dart:ui' show Color;

import 'tikz_expression.dart';

/// One option from a `[…]` list: its key, and its value if it has one.
typedef TikzOption = ({String key, String? value});

/// A cursor over TikZ source.
class TikzScanner {
  TikzScanner(this.source, [this.at = 0]);

  final String source;
  int at;

  /// Moves past spaces and comments.
  void skipSpaces() {
    while (at < source.length) {
      final char = source[at];
      if (char == '%') {
        final end = source.indexOf('\n', at);
        at = end < 0 ? source.length : end + 1;
      } else if (char.trim().isEmpty) {
        at++;
      } else {
        return;
      }
    }
  }

  /// Whether there is nothing but spaces left.
  bool get done {
    skipSpaces();
    return at >= source.length;
  }

  /// Whether [text] comes next, after any spaces.
  bool sees(String text) {
    skipSpaces();
    return source.startsWith(text, at);
  }

  /// Moves past [text] if it comes next.
  bool take(String text) {
    if (!sees(text)) return false;
    at += text.length;
    return true;
  }

  /// Moves past the word [word] if it comes next, whole.
  bool takeWord(String word) {
    if (!sees(word)) return false;
    final end = at + word.length;
    if (end < source.length && _isLetter(source.codeUnitAt(end))) return false;
    at = end;
    return true;
  }

  /// The command (`\name`) that comes next, moving past it; null if none
  /// does.
  String? command() {
    skipSpaces();
    final match = RegExp(r'\\([a-zA-Z@]+|.)').matchAsPrefix(source, at);
    if (match == null) return null;
    at = match.end;
    return match.group(1);
  }

  /// What is between [open] and its matching [close], which must come next;
  /// the cursor is left after the close.
  String group(String open, String close) {
    skipSpaces();
    if (!source.startsWith(open, at)) {
      throw FormatException('Expected "$open" in "${_around()}"');
    }
    final end = matching(source, at, open, close);
    if (end < 0) throw FormatException('Missing "$close" in "${_around()}"');
    final inner = source.substring(at + open.length, end);
    at = end + close.length;
    return inner;
  }

  /// [group] if [open] comes next, otherwise null.
  String? optional(String open, String close) =>
      sees(open) ? group(open, close) : null;

  /// The source up to the next `;` at this level, moving past the `;`.
  String statement() {
    final end = TikzSource.topLevel(source, ';', at);
    if (end < 0) throw FormatException('Missing ";" after "${_around()}"');
    final text = source.substring(at, end);
    at = end + 1;
    return text;
  }

  String _around() {
    final end = (at + 30).clamp(0, source.length);
    return source.substring(at, end).trim();
  }

  static bool _isLetter(int unit) =>
      (unit >= 0x41 && unit <= 0x5A) || (unit >= 0x61 && unit <= 0x7A);

  /// Where the [close] matching the [open] at [start] in [source] is, or -1.
  /// Braces inside are skipped whole.
  static int matching(String source, int start, String open, String close) {
    var depth = 0;
    var i = start;
    while (i < source.length) {
      if (source.startsWith(r'\', i)) {
        i += 2;
        continue;
      }
      if (open != '{' && source[i] == '{') {
        final end = matching(source, i, '{', '}');
        if (end < 0) return -1;
        i = end + 1;
        continue;
      }
      if (source.startsWith(open, i)) {
        depth++;
        i += open.length;
        continue;
      }
      if (source.startsWith(close, i)) {
        depth--;
        if (depth == 0) return i;
        i += close.length;
        continue;
      }
      i++;
    }
    return -1;
  }
}

abstract final class TikzSource {
  /// Where the first [separator] in [source] from [start] is that is not
  /// inside brackets of any kind, or quotes, or -1.
  static int topLevel(String source, String separator, [int start = 0]) {
    var i = start;
    while (i < source.length) {
      if (source.startsWith(separator, i)) return i;
      final char = source[i];
      if (char == r'\') {
        i += 2;
        continue;
      }
      // The quotes library's labels: `"$\alpha$"`, commas and all.
      if (char == '"') {
        final end = source.indexOf('"', i + 1);
        if (end < 0) return -1;
        i = end + 1;
        continue;
      }
      final close = switch (char) {
        '{' => '}',
        '(' => ')',
        '[' => ']',
        _ => null,
      };
      if (close != null) {
        final end = TikzScanner.matching(source, i, char, close);
        if (end < 0) return -1;
        i = end + 1;
        continue;
      }
      i++;
    }
    return -1;
  }

  /// [source] cut at each [separator] that is not inside brackets.
  static List<String> split(String source, String separator) {
    final parts = <String>[];
    var start = 0;
    while (true) {
      final at = topLevel(source, separator, start);
      if (at < 0) break;
      parts.add(source.substring(start, at));
      start = at + separator.length;
    }
    parts.add(source.substring(start));
    return parts;
  }

  /// [text] without the one pair of braces round all of it, if it has one.
  static String unbraced(String text) {
    final trimmed = text.trim();
    if (trimmed.startsWith('{') &&
        TikzScanner.matching(trimmed, 0, '{', '}') == trimmed.length - 1) {
      return trimmed.substring(1, trimmed.length - 1).trim();
    }
    return trimmed;
  }

  /// The options written between the brackets of a `[…]` list.
  static List<TikzOption> options(String source) => <TikzOption>[
    for (final part in split(source, ','))
      if (part.trim().isNotEmpty) _option(part.trim()),
  ];

  static TikzOption _option(String part) {
    // A quoted label keeps what is in its quotes whole.
    if (part.startsWith('"')) return (key: part, value: null);
    final equals = topLevel(part, '=');
    if (equals < 0) return (key: _normalKey(part), value: null);
    return (
      key: _normalKey(part.substring(0, equals)),
      value: unbraced(part.substring(equals + 1)),
    );
  }

  static String _normalKey(String key) =>
      key.trim().replaceAll(RegExp(r'\s+'), ' ');

  /// The most a picture's loops may write out, so a mistyped one cannot
  /// write without end.
  static const int _maxExpanded = 400000;

  /// [source] with each `\foreach` written out: its body once for each value
  /// in its list, the value in place of its variable.
  static String expandLoops(String source) {
    var text = source;
    var from = 0;
    while (true) {
      final at = text.indexOf(r'\foreach', from);
      if (at < 0) return text;
      final scanner = TikzScanner(text, at + r'\foreach'.length);
      final (:options, :variables, :list, :body) = _loop(scanner);
      final values = _listValues(list);
      final count = _counter(options);
      final written = StringBuffer();
      for (var i = 0; i < values.length; i++) {
        final parts = values[i].split('/');
        final copy = substitute(body, <String, String>{
          for (var v = 0; v < variables.length; v++)
            variables[v]: parts[math.min(v, parts.length - 1)].trim(),
          if (count != null) count.name: TikzExpression.format(count.from + i),
        });
        written
          ..write(copy)
          ..write(' ');
        if (written.length > _maxExpanded) {
          throw const FormatException('The loops write out too much');
        }
      }
      text = text.replaceRange(at, scanner.at, written.toString());
      if (text.length > _maxExpanded) {
        throw const FormatException('The loops write out too much');
      }
      from = at;
    }
  }

  /// The loop [scanner] is at, just after its `\foreach`, moving past it:
  /// its options, variables, list and body. A body not in braces is the one
  /// statement after the list, or the loop that is.
  static ({String options, List<String> variables, String list, String body})
  _loop(TikzScanner scanner) {
    final options = scanner.optional('[', ']');
    final variables = <String>[];
    while (true) {
      scanner.skipSpaces();
      final match = RegExp(
        r'\\([a-zA-Z]+)',
      ).matchAsPrefix(scanner.source, scanner.at);
      if (match == null) break;
      variables.add(match.group(1)!);
      scanner.at = match.end;
      if (!scanner.take('/')) break;
    }
    // Its options can come after its variables too.
    final after = scanner.optional('[', ']');
    if (variables.isEmpty || !scanner.takeWord('in')) {
      throw const FormatException(r'A \foreach needs "\x in {…}"');
    }
    final list = scanner.group('{', '}');
    final String body;
    if (scanner.sees('{')) {
      body = scanner.group('{', '}');
    } else if (scanner.sees(r'\foreach')) {
      final start = scanner.at;
      scanner.at += r'\foreach'.length;
      _loop(scanner);
      body = scanner.source.substring(start, scanner.at);
    } else {
      body = '${scanner.statement()};';
    }
    return (
      options: <String>[?options, ?after].join(','),
      variables: variables,
      list: list,
      body: body,
    );
  }

  /// [source] with each `\name` standing alone written as [values] has it,
  /// all at once, so one written out never runs into the next.
  static String substitute(String source, Map<String, String> values) =>
      source.replaceAllMapped(
        RegExp('\\\\(${values.keys.join('|')})(?![a-zA-Z])'),
        (match) => values[match.group(1)]!,
      );

  /// The counter a loop's options ask for: `count=\i` or `count=\i from 0`.
  static ({String name, double from})? _counter(String options) {
    for (final option in TikzSource.options(options)) {
      if (option.key != 'count' || option.value == null) continue;
      final match = RegExp(
        r'^\\([a-zA-Z]+)(?:\s+from\s+(.+))?$',
      ).firstMatch(option.value!.trim());
      if (match == null) continue;
      final from = match.group(2);
      return (
        name: match.group(1)!,
        from: from == null ? 1 : TikzExpression.evaluate(from).value,
      );
    }
    return null;
  }

  /// The values a loop's list stands for, `…` written out.
  static List<String> _listValues(String list) {
    final items = <String>[for (final item in split(list, ',')) item.trim()]
      ..removeWhere((item) => item.isEmpty);
    final values = <String>[];
    for (var i = 0; i < items.length; i++) {
      final item = items[i];
      if (item != '...' && item != r'\dots') {
        values.add(item);
        continue;
      }
      if (values.isEmpty || i + 1 >= items.length) {
        throw const FormatException('"..." needs a value before and after');
      }
      final end = TikzExpression.evaluate(items[i + 1]).value;
      final last = TikzExpression.evaluate(values.last).value;
      final step = values.length >= 2
          ? last - TikzExpression.evaluate(values[values.length - 2]).value
          : (end >= last ? 1.0 : -1.0);
      if (step == 0 || (end - last) * step < 0) continue;
      final count = ((end - last) / step + 1e-9).floor();
      if (count > 2000) {
        throw const FormatException('The loop runs too many times');
      }
      for (var n = 1; n <= count; n++) {
        values.add(TikzExpression.format(last + n * step));
      }
      // The end, given after the dots, is among those written out if the
      // steps reach it.
      i++;
    }
    return values;
  }
}

/// The colours TikZ knows by name, mixed as xcolor mixes them.
abstract final class TikzColours {
  static const Map<String, Color> named = <String, Color>{
    'black': Color(0xFF000000),
    'white': Color(0xFFFFFFFF),
    'red': Color(0xFFFF0000),
    'green': Color(0xFF00FF00),
    'blue': Color(0xFF0000FF),
    'cyan': Color(0xFF00FFFF),
    'magenta': Color(0xFFFF00FF),
    'yellow': Color(0xFFFFFF00),
    'gray': Color(0xFF808080),
    'grey': Color(0xFF808080),
    'darkgray': Color(0xFF404040),
    'lightgray': Color(0xFFBFBFBF),
    'brown': Color(0xFFBF8040),
    'lime': Color(0xFFBFFF00),
    'olive': Color(0xFF808000),
    'orange': Color(0xFFFF8000),
    'pink': Color(0xFFFFBFBF),
    'purple': Color(0xFFBF0040),
    'teal': Color(0xFF008080),
    'violet': Color(0xFF800080),
  };

  /// The colour [spec] names — `red`, `blue!30`, `red!50!blue` — with
  /// [current] for `.`; null where it names none.
  static Color? parse(String spec, {required Color current}) {
    final parts = spec.trim().split('!');
    Color? base(String name) =>
        name.trim() == '.' ? current : named[name.trim().toLowerCase()];
    var colour = base(parts.first);
    if (colour == null) return null;
    for (var i = 1; i < parts.length; i += 2) {
      final share = double.tryParse(parts[i].trim());
      if (share == null) return null;
      // Mixed with white where no colour follows: `red!50`, and `red!50!`.
      final other = i + 1 < parts.length && parts[i + 1].trim().isNotEmpty
          ? base(parts[i + 1])
          : named['white'];
      if (other == null) return null;
      colour = Color.lerp(other, colour, (share / 100).clamp(0.0, 1.0))!;
    }
    return colour;
  }
}
