/// The arithmetic TikZ coordinates and options are written in, worked out
/// as its `pgfmath` does: angles in degrees, lengths in points.
library;

import 'dart:math' as math;

/// A number worked out from TikZ source, and whether it was a length: given
/// in units, and so in points, rather than a bare number to be scaled.
typedef TikzValue = ({double value, bool length});

abstract final class TikzExpression {
  /// Points in a centimetre, as TeX measures them.
  static const double pointsPerCm = 72.27 / 2.54;

  /// Points in each unit a length can be given in. A picture is set as if
  /// in ten-point type, as LaTeX sets one by default.
  static const Map<String, double> units = <String, double>{
    'pt': 1,
    'cm': pointsPerCm,
    'mm': pointsPerCm / 10,
    'in': 72.27,
    'bp': 72.27 / 72,
    'pc': 12,
    'sp': 1 / 65536,
    'em': 10,
    'ex': 4.3,
  };

  /// [source] worked out, its `\name`s taken from [variables]. Throws a
  /// [FormatException] where it is not arithmetic.
  static TikzValue evaluate(
    String source, [
    Map<String, double> variables = const <String, double>{},
  ]) {
    final reader = _Reader(source.trim(), variables);
    final value = reader.sum();
    reader.skipSpaces();
    if (!reader.done) {
      throw FormatException('Cannot work out "${source.trim()}"');
    }
    return (value: value, length: reader.length);
  }

  /// [source] as a length in points: a bare number is taken as [bare] each.
  static double length(
    String source, {
    double bare = 1,
    Map<String, double> variables = const <String, double>{},
  }) {
    final (:value, :length) = evaluate(source, variables);
    return length ? value : value * bare;
  }

  /// [value] written as TikZ source: whole numbers without a point.
  static String format(double value) {
    if (value == value.roundToDouble()) return value.round().toString();
    final fixed = value.toStringAsFixed(5);
    return fixed.replaceFirst(RegExp(r'\.?0+$'), '');
  }
}

class _Reader {
  _Reader(this.source, this.variables);

  final String source;
  final Map<String, double> variables;
  int at = 0;

  /// Whether a unit was met, making the value a length.
  bool length = false;

  bool get done => at >= source.length;

  String? get _next => done ? null : source[at];

  void skipSpaces() {
    while (!done && source[at].trim().isEmpty) {
      at++;
    }
  }

  bool _take(String text) {
    skipSpaces();
    if (!source.startsWith(text, at)) return false;
    at += text.length;
    return true;
  }

  Never _fail() => throw FormatException('Cannot work out "$source"');

  double sum() {
    var value = _product();
    while (true) {
      if (_take('+')) {
        value += _product();
      } else if (_take('-')) {
        value -= _product();
      } else {
        return value;
      }
    }
  }

  double _product() {
    var value = _power();
    while (true) {
      if (_take('*')) {
        value *= _power();
      } else if (_take('/')) {
        value /= _power();
      } else {
        return value;
      }
    }
  }

  double _power() {
    final base = _unary();
    return _take('^') ? math.pow(base, _power()).toDouble() : base;
  }

  double _unary() {
    if (_take('-')) return -_unary();
    if (_take('+')) return _unary();
    return _postfix(_primary());
  }

  /// [value] in the unit written after it, if one is.
  double _postfix(double value) {
    skipSpaces();
    final word = _wordAt(at);
    if (word == null) return value;
    final unit = TikzExpression.units[word];
    if (unit != null) {
      at += word.length;
      length = true;
      return value * unit;
    }
    if (word == 'r') {
      at += 1;
      return value * 180 / math.pi;
    }
    return value;
  }

  /// The run of letters starting at [index], if any.
  String? _wordAt(int index) {
    var end = index;
    while (end < source.length && _isLetter(source.codeUnitAt(end))) {
      end++;
    }
    return end == index ? null : source.substring(index, end);
  }

  static bool _isLetter(int unit) =>
      (unit >= 0x41 && unit <= 0x5A) || (unit >= 0x61 && unit <= 0x7A);

  double _primary() {
    skipSpaces();
    final next = _next;
    if (next == null) _fail();
    if (next == '(' || next == '{') {
      at++;
      final value = sum();
      if (!_take(next == '(' ? ')' : '}')) _fail();
      return value;
    }
    if (next == r'\') {
      final name = _wordAt(at + 1);
      if (name == null) _fail();
      at += 1 + name.length;
      final value = variables[name];
      return value ?? (throw FormatException('Nothing is called \\$name'));
    }
    final number = RegExp(
      r'(\d+\.?\d*|\.\d+)([eE][-+]?\d+)?',
    ).matchAsPrefix(source, at);
    if (number != null) {
      at = number.end;
      return double.parse(number.group(0)!);
    }
    final name = _wordAt(at);
    if (name == null) _fail();
    at += name.length;
    switch (name) {
      case 'pi':
        return math.pi;
      case 'e':
        return math.e;
      case 'true':
        return 1;
      case 'false':
        return 0;
    }
    final arguments = _arguments();
    double one() => arguments.length == 1 ? arguments.single : _fail();
    double radians() => one() * math.pi / 180;
    double degrees(double value) => value * 180 / math.pi;
    return switch (name) {
      'sin' => math.sin(radians()),
      'cos' => math.cos(radians()),
      'tan' => math.tan(radians()),
      'asin' => degrees(math.asin(one())),
      'acos' => degrees(math.acos(one())),
      'atan' => degrees(math.atan(one())),
      'atan2' when arguments.length == 2 => degrees(
        math.atan2(arguments[0], arguments[1]),
      ),
      'sqrt' => math.sqrt(one()),
      'exp' => math.exp(one()),
      'ln' => math.log(one()),
      'log10' => math.log(one()) / math.ln10,
      'log2' => math.log(one()) / math.ln2,
      'abs' => one().abs(),
      'sign' => one().sign,
      'floor' => one().floorToDouble(),
      'ceil' => one().ceilToDouble(),
      'round' => one().roundToDouble(),
      'int' => one().truncateToDouble(),
      'deg' => degrees(one()),
      'rad' => radians(),
      'sinh' => _sinh(one()),
      'cosh' => _cosh(one()),
      'tanh' => _sinh(one()) / _cosh(one()),
      'pow' when arguments.length == 2 =>
        math.pow(arguments[0], arguments[1]).toDouble(),
      'mod' when arguments.length == 2 => arguments[0].remainder(arguments[1]),
      'veclen' when arguments.length == 2 => math.sqrt(
        arguments[0] * arguments[0] + arguments[1] * arguments[1],
      ),
      'min' when arguments.isNotEmpty => arguments.reduce(math.min),
      'max' when arguments.isNotEmpty => arguments.reduce(math.max),
      _ => throw FormatException('"$name" is not a function TikZ knows'),
    };
  }

  static double _sinh(double x) => (math.exp(x) - math.exp(-x)) / 2;
  static double _cosh(double x) => (math.exp(x) + math.exp(-x)) / 2;

  /// The bracketed, comma-separated values after a function's name.
  List<double> _arguments() {
    if (!_take('(')) _fail();
    final values = <double>[sum()];
    while (_take(',')) {
      values.add(sum());
    }
    if (!_take(')')) _fail();
    return values;
  }
}
