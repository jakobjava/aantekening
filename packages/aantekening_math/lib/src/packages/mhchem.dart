part of 'latex_packages.dart';

// The mhchem package: `\ce{…}` chemical formulas and equations, and
// `\pu{…}` physical units, as mhchem sets them.

final Map<String, _Command> _mhchem = <String, _Command>{
  'ce': (arguments) => _chemistry(arguments.group()),
  'pu': (arguments) => _physicalUnits(arguments.group()),
};

/// mhchem's arrows, the longest first, and the stretching arrow each is.
const List<(String, String)> _reactionArrows = <(String, String)>[
  ('<-->', r'\xrightleftarrows'),
  ('<=>>', r'\xrightequilibrium'),
  ('<<=>', r'\xleftequilibrium'),
  ('<=>', r'\xrightleftharpoons'),
  ('<->', r'\xleftrightarrow'),
  ('->', r'\xrightarrow'),
  ('<-', r'\xleftarrow'),
];

/// The formula or equation [source], in mhchem's syntax, as LaTeX:
/// `2H2 + O2 -> 2H2O`, `SO4^2-`, `Ca2+`, `[Cu(NH3)4]^2+`, `CuSO4*5H2O`,
/// `^{14}_{6}C`, `NaCl(aq)`, `C=C`, `->[\Delta][cat.]`, `CO2 ^`, `AgCl v`.
String _chemistry(String source) {
  final out = StringBuffer();
  var i = 0;
  // Whether what comes next begins a term: may be a number of molecules,
  // a variable one, or an isotope's numbers.
  var termStart = true;
  // Whether what was written last is part of a formula: what follows it
  // may be its subscript, its charge or a bond.
  var inFormula = false;
  // How many elements the term has had: digits and a sign after the only
  // one are its charge, `Ca2+`; after more, `NO3-`, its count and charge.
  var elements = 0;
  // Whether an isotope's mass number was written last, for its atomic
  // number to stand beneath it.
  var prescribed = false;

  bool endsTerm(int at) => at >= source.length || ' )]}'.contains(source[at]);
  bool spaced(int at) => at < 0 || at >= source.length || source[at] == ' ';

  /// The script after `^` or `_` at [at]: a group, or the digits, signs or
  /// numerals written against it; moves past it.
  String script(int at) {
    if (at < source.length && source[at] == '{') {
      final close = LatexSource.closingBrace(source, at);
      i = close;
      return source.substring(at + 1, close - 1);
    }
    final match = RegExp(r'\d*[+\-]*|[IVX]+').matchAsPrefix(source, at);
    final end = match == null || match.end == at ? at + 1 : match.end;
    i = math.min(end, source.length);
    return source.substring(at, i);
  }

  while (i < source.length) {
    final char = source[i];

    if (char != '_') prescribed = false;
    if (char == ' ') {
      i++;
      termStart = true;
      inFormula = false;
      elements = 0;
      continue;
    }

    final arrow = _reactionArrows
        .where((arrow) => source.startsWith(arrow.$1, i))
        .firstOrNull;
    if (arrow != null) {
      final labels = _Arguments(source, i + arrow.$1.length);
      final above = labels.optional();
      final below = labels.optional();
      i = labels.at;
      out.write(
        ' ${arrow.$2}${below == null ? '' : '[${_chemistry(below)}]'}'
        '{${above == null ? '' : _chemistry(above)}} ',
      );
      termStart = true;
      inFormula = false;
      continue;
    }

    if (char == r'$') {
      final close = source.indexOf(r'$', i + 1);
      final end = close < 0 ? source.length : close;
      out.write(source.substring(i + 1, end));
      i = math.min(end + 1, source.length);
      termStart = false;
      inFormula = false;
      continue;
    }

    if (char == r'\') {
      // A command, with the groups written against it, as it is.
      final command = _Arguments(source, i)..group();
      var end = command.at;
      while (end < source.length && source[end] == '{') {
        end = LatexSource.closingBrace(source, end);
      }
      out
        ..write(source.substring(i, end))
        ..write(' ');
      i = end;
      termStart = false;
      inFormula = false;
      continue;
    }

    if (char == '{') {
      final close = LatexSource.closingBrace(source, i);
      out.write('{${_chemistry(source.substring(i + 1, close - 1))}}');
      i = close;
      termStart = false;
      inFormula = true;
      continue;
    }

    // A plus between terms, rather than a charge.
    if (char == '+' && spaced(i - 1) && spaced(i + 1)) {
      out.write(' + ');
      i++;
      termStart = true;
      inFormula = false;
      continue;
    }

    // Gas given off, and a precipitate.
    if ((char == '^' || char == 'v') && spaced(i - 1) && spaced(i + 1)) {
      out.write(char == '^' ? r' \uparrow ' : r' \downarrow ');
      i++;
      continue;
    }

    if (char == '^' || char == '_') {
      final value = script(i + 1);
      // Before the formula, an isotope's mass and atomic numbers.
      final before = termStart && !inFormula;
      out.write('${before && !prescribed ? '{}' : ''}$char{$value}');
      prescribed = before;
      continue;
    }

    if (inFormula && (char == '+' || char == '-')) {
      // Against a formula: a bond to what follows, or its charge.
      if (char == '-' &&
          i + 1 < source.length &&
          RegExp(r'[A-Za-z(\[]').hasMatch(source[i + 1])) {
        out.write('{-}');
        i++;
        inFormula = false;
        continue;
      }
      final charge = RegExp(r'[+\-]+').matchAsPrefix(source, i)!;
      out.write('^{${charge[0]}}');
      i = charge.end;
      continue;
    }

    if (inFormula && (char == '=' || char == '#')) {
      out.write(char == '=' ? '{=}' : r'{\equiv}');
      i++;
      inFormula = false;
      continue;
    }

    if (char == '*' || (char == '.' && inFormula)) {
      out.write(r' \cdot ');
      i++;
      termStart = true;
      inFormula = false;
      elements = 0;
      continue;
    }

    final digits =
        (inFormula ? RegExp(r'\d+') : RegExp(r'\d+(?:[.,]\d+)?(?:/\d+)?'))
            .matchAsPrefix(source, i);
    if (digits != null) {
      final number = digits[0]!;
      i = digits.end;
      if (inFormula) {
        // `Ca2+`: a charge; `H2O`: how many atoms.
        final charge = RegExp(r'[+\-]+').matchAsPrefix(source, i);
        if (charge != null && elements == 1 && endsTerm(charge.end)) {
          out.write('^{$number${charge[0]}}');
          i = charge.end;
        } else {
          out.write('_{$number}');
        }
        continue;
      }
      // How many molecules: a fraction as a fraction.
      final fraction = number.split('/');
      out.write(
        fraction.length == 2
            ? '\\tfrac{${fraction[0]}}{${fraction[1]}}'
            : number,
      );
      termStart = false;
      continue;
    }

    final letters = RegExp('[A-Z][a-z]*|[a-z]+').matchAsPrefix(source, i);
    if (letters != null) {
      final word = letters[0]!;
      i = letters.end;
      // A letter alone before a formula is a variable number of molecules,
      // set in italics: `x Na`, `n H2O`. An `e` before a charge is an
      // electron.
      final variable =
          termStart &&
          word.length == 1 &&
          word.toLowerCase() == word &&
          (i >= source.length || RegExp('[ A-Z]').hasMatch(source[i]));
      out.write(variable ? '$word ' : '\\mathrm{$word}');
      termStart = false;
      inFormula = !variable;
      if (!variable && word.startsWith(RegExp('[A-Z]'))) elements++;
      continue;
    }

    out.write(char);
    i++;
    // A bracket holds more than one element.
    if (char == '(' || char == '[') elements = 2;
    termStart = char == '(' || char == '[';
    inFormula = char == ')' || char == ']';
  }
  return out.toString();
}

/// The quantity [source] in mhchem's units: `123 kJ/mol`, `1.2e3 kJ`,
/// `8.31 J K^-1 mol-1`, `25 °C`.
String _physicalUnits(String source) {
  final words = source.trim().split(RegExp(r'\s+'));
  final number = RegExp(r'^[-+]?[\d.,]+(?:[eE][-+]?\d+)?$');
  final out = StringBuffer();
  var start = 0;
  if (words.isNotEmpty && number.hasMatch(words.first)) {
    final value = RegExp(r'^(.*?)[eE]([-+]?\d+)$').firstMatch(words.first);
    out.write(
      value == null
          ? _digits(words.first)
          : '${_digits(value.group(1)!)}\\cdot 10^{'
                '${value.group(2)!.replaceFirst('+', '')}}',
    );
    start = 1;
  }
  final units = <String>[
    for (final word in words.skip(start))
      if (word.isNotEmpty) _physicalUnit(word),
  ];
  if (units.isNotEmpty) {
    final unit = units.join(r'\,');
    out
      ..write(out.isEmpty || unit.startsWith('{}') ? '' : r'\,')
      ..write(unit);
  }
  return out.toString();
}

/// One word of mhchem's units: `kJ/mol`, `K^-1`, `mol-1`, `m2`, `°C`.
String _physicalUnit(String word) => word.splitMapJoin(
  RegExp('[*.]'),
  onMatch: (_) => r'\cdot ',
  onNonMatch: (part) => part.splitMapJoin(
    '/',
    onMatch: (_) => '/',
    onNonMatch: (unit) {
      if (unit.isEmpty) return '';
      final powered = RegExp(r'^(.*?)\^?\{?(-?\d+)\}?$').firstMatch(unit);
      final name = powered?.group(1) ?? unit;
      final power = powered?.group(2);
      final written = switch (name) {
        '°C' || 'degC' => r'{}^{\circ}\mathrm{C}',
        '°' => r'{}^{\circ}',
        '%' => r'\%',
        _ when name.startsWith(r'\') => name,
        _ => '\\mathrm{$name}',
      };
      return power == null || name.isEmpty
          ? (name.isEmpty ? unit : written)
          : '$written^{$power}';
    },
  ),
);
