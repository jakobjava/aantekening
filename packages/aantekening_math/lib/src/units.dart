/// Units written after a number, as a quantity is: `5 m/s`, `9,81 m/s^2`,
/// `20 kg`, `25 °C`, `8,31 J/(mol K)`.
library;

/// What a quantity's units are read as, and written as.
///
/// A number with a space after it and then units is a quantity: the units
/// set upright, a thin space before them. Typed against the number, `2m`
/// is two times m, as ever. A unit of one letter by itself is a unit only
/// where nothing it would multiply follows it — `l = 2 m`, but `F = 2 m a`
/// — and only for the letters seldom meant as variables after a number;
/// the rest, `t`, `h`, `d`, `l`, are units with a prefix or among others
/// only: `km/h`.
abstract final class Units {
  /// The units, as they are written.
  static const Set<String> _named = <String>{
    // The SI's, and those used with it.
    'm', 'g', 's', 'A', 'K', 'mol', 'cd', //
    'Hz', 'N', 'Pa', 'J', 'W', 'C', 'V', 'F', 'Ω', 'S', 'Wb', 'T', 'H', //
    'lm', 'lx', 'Bq', 'Gy', 'Sv', 'kat', 'rad', 'sr', //
    'L', 'l', 'min', 'h', 'd', 't', 'eV', 'u', 'Da', 'M', //
    'bar', 'atm', 'mmHg', 'cal', 'kWh', 'ppm', 'dB', //
    '°C', '°', '%',
  };

  /// The units a prefix goes before.
  static const Set<String> _prefixed = <String>{
    'm', 'g', 's', 'A', 'K', 'mol', 'Hz', 'N', 'Pa', 'J', 'W', 'C', 'V', //
    'F', 'Ω', 'S', 'T', 'H', 'Bq', 'Gy', 'Sv', 'L', 'l', 'eV', 'bar', //
    'cal', 'M', 'Wh',
  };

  /// The SI's prefixes, the two-letter one first.
  static const List<String> _prefixes = <String>[
    'da', 'Q', 'R', 'Y', 'Z', 'E', 'P', 'T', 'G', 'M', 'k', 'h', 'd', //
    'c', 'm', 'µ', 'μ', 'n', 'p', 'f', 'a', 'z', 'y',
  ];

  /// The units of one letter that are a unit by themselves after a number:
  /// those seldom meant as a variable there.
  static const Set<String> _alone = <String>{
    'm',
    'g',
    's',
    'A',
    'K',
    'N',
    'J',
    'W',
    'V',
    'L',
    'C',
    'T',
    'M',
    'Ω',
  };

  /// Whether [word] is a unit: one of them, or one with a prefix.
  static bool isUnit(String word) {
    if (_named.contains(word)) return true;
    for (final prefix in _prefixes) {
      if (word.length > prefix.length &&
          word.startsWith(prefix) &&
          _prefixed.contains(word.substring(prefix.length))) {
        return true;
      }
    }
    return false;
  }

  /// Where the units at [at] in [source] end, after a number and a space:
  /// units, each perhaps raised to a power, joined by `/`, `*` or a space,
  /// with brackets after a `/` — `J/(mol K)` — and nothing typed straight
  /// after them. Null where there are none, or what is there is more
  /// likely a variable: a letter alone that something follows to multiply.
  static int? read(String source, int at) {
    var i = at;
    var count = 0;
    var plain = true;
    String? first;

    // A unit at [i], and its power: moves past it if there is one.
    bool unit() {
      final word = _wordAt(source, i);
      if (word == null || !isUnit(word)) return false;
      i += word.length;
      final power = RegExp(r'\^(\(-?\d+\)|-?\d+)').matchAsPrefix(source, i);
      if (power != null) {
        i = power.end;
        plain = false;
      }
      count++;
      first ??= word;
      return true;
    }

    // Units in brackets, after a `/`: `(mol K)`, `(mol*K)`.
    bool group() {
      if (i >= source.length || source[i] != '(') return false;
      final start = i;
      i++;
      if (!unit()) {
        i = start;
        return false;
      }
      while (i < source.length && source[i] != ')') {
        final before = i;
        while (i < source.length && ' *·'.contains(source[i])) {
          i++;
        }
        if (i == before || !unit()) {
          i = start;
          return false;
        }
      }
      if (i >= source.length) {
        i = start;
        return false;
      }
      i++;
      return true;
    }

    if (!unit()) return null;
    while (i < source.length) {
      final before = i;
      final char = source[i];
      if (char == '/' || char == '*' || char == '·') {
        i++;
        if (char == '/' && group() || unit()) {
          plain = false;
          continue;
        }
        i = before;
        break;
      }
      if (char == ' ') {
        // Another unit after a space, `kg m/s^2`, if one ends there.
        while (i < source.length && source[i] == ' ') {
          i++;
        }
        final next = _wordAt(source, i);
        if (next != null && isUnit(next) && _endsAt(source, i + next.length)) {
          if (unit()) {
            plain = false;
            continue;
          }
        }
        i = before;
        break;
      }
      break;
    }
    if (!_endsAt(source, i)) return null;
    if (count == 1 &&
        plain &&
        first!.length == 1 &&
        RegExp('[A-Za-zµμΩ]').hasMatch(first!)) {
      if (!_alone.contains(first)) return null;
      // A letter alone with something after it to multiply is a variable:
      // `F = 2 m a`.
      var next = i;
      while (next < source.length && source[next] == ' ') {
        next++;
      }
      if (next < source.length &&
          RegExp(r'[\w(\\"|µμΩ]').hasMatch(source[next])) {
        return null;
      }
    }
    return i;
  }

  /// The letters of a unit's name at [at], or null for none.
  static String? _wordAt(String source, int at) =>
      RegExp('°C|[%°]|[A-Za-zµμΩ]+').matchAsPrefix(source, at)?[0];

  /// Whether units may end at [at]: at the end, a space, a closing bracket
  /// or a separator, an operator or a relation — not against more letters
  /// or digits, or a bracket opening.
  static bool _endsAt(String source, int at) =>
      at >= source.length ||
      RegExp(r'[\s)\]},;|+\-=<>!~:]').hasMatch(source[at]);

  /// [unit], as typed, as the LaTeX it is set in: upright, a power raised,
  /// a `*` a dot and a space a thin one.
  static String latexOf(String unit) {
    final out = StringBuffer(r'\mathrm{');
    var i = 0;
    while (i < unit.length) {
      final power = RegExp(r'\^\(?(-?\d+)\)?').matchAsPrefix(unit, i);
      if (power != null) {
        out.write('^{${power[1]}}');
        i = power.end;
        continue;
      }
      final char = unit[i];
      out.write(switch (char) {
        'µ' || 'μ' => r'\mu ',
        'Ω' => r'\Omega ',
        '°' => r'{}^{\circ}',
        '%' => r'\%',
        '*' || '·' => r'\cdot ',
        ' ' => r'\,',
        _ => char,
      });
      i++;
      // A run of spaces is one.
      while (char == ' ' && i < unit.length && unit[i] == ' ') {
        i++;
      }
    }
    out.write('}');
    return '$out';
  }

  /// The units [latex] — what is inside `\mathrm{…}` — sets, as they are
  /// typed; null if it is not units.
  static String? fromLatex(String latex) {
    final unit = latex
        .replaceAll(r'\mu ', 'µ')
        .replaceAll(r'\mu', 'µ')
        .replaceAll(r'\Omega ', 'Ω')
        .replaceAll(r'\Omega', 'Ω')
        .replaceAll(r'{}^{\circ}', '°')
        .replaceAll(r'\%', '%')
        .replaceAll(r'\cdot ', '*')
        .replaceAll(r'\cdot', '*')
        .replaceAll(r'\,', ' ')
        .replaceAllMapped(RegExp(r'\^\{(-?\d+)\}'), (match) => '^${match[1]}');
    if (unit.contains(RegExp(r'[\\{}]'))) return null;
    return read(unit, 0) == unit.length ? unit : null;
  }
}
