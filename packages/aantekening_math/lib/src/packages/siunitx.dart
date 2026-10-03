part of 'latex_packages.dart';

// The siunitx package: numbers, units and quantities, set as it sets them
// by default — digits grouped in threes from five on, units upright and a
// thin space apart, `\per` as a power of −1.

/// The prefixes, by name.
const Map<String, String> _prefixes = <String, String>{
  'quecto': 'q',
  'ronto': 'r',
  'yocto': 'y',
  'zepto': 'z',
  'atto': 'a',
  'femto': 'f',
  'pico': 'p',
  'nano': 'n',
  'micro': r'\mu',
  'milli': 'm',
  'centi': 'c',
  'deci': 'd',
  'deca': 'da',
  'deka': 'da',
  'hecto': 'h',
  'kilo': 'k',
  'mega': 'M',
  'giga': 'G',
  'tera': 'T',
  'peta': 'P',
  'exa': 'E',
  'zetta': 'Z',
  'yotta': 'Y',
  'ronna': 'R',
  'quetta': 'Q',
  'kibi': 'Ki',
  'mebi': 'Mi',
  'gibi': 'Gi',
  'tebi': 'Ti',
};

/// The units, by name, as they are set.
const Map<String, String> _unitNames = <String, String>{
  'metre': 'm',
  'meter': 'm',
  'gram': 'g',
  'kilogram': 'kg',
  'second': 's',
  'ampere': 'A',
  'kelvin': 'K',
  'mole': 'mol',
  'candela': 'cd',
  'becquerel': 'Bq',
  'coulomb': 'C',
  'farad': 'F',
  'gray': 'Gy',
  'hertz': 'Hz',
  'henry': 'H',
  'joule': 'J',
  'katal': 'kat',
  'lumen': 'lm',
  'lux': 'lx',
  'newton': 'N',
  'pascal': 'Pa',
  'radian': 'rad',
  'siemens': 'S',
  'sievert': 'Sv',
  'steradian': 'sr',
  'tesla': 'T',
  'volt': 'V',
  'watt': 'W',
  'weber': 'Wb',
  'day': 'd',
  'hectare': 'ha',
  'hour': 'h',
  'litre': 'L',
  'liter': 'L',
  'minute': 'min',
  'tonne': 't',
  'astronomicalunit': 'au',
  'atomicmassunit': 'u',
  'bel': 'B',
  'dalton': 'Da',
  'decibel': 'dB',
  'electronvolt': 'eV',
  'neper': 'Np',
  'bar': 'bar',
  'barn': 'b',
  'knot': 'kn',
  'mmHg': 'mmHg',
  'nauticalmile': 'M',
  'bit': 'bit',
  'byte': 'B',
};

/// Units set otherwise than in upright letters.
const Map<String, String> _unitSymbols = <String, String>{
  'ohm': r'\Omega',
  'degreeCelsius': r'{}^{\circ}\mathrm{C}',
  'celsius': r'{}^{\circ}\mathrm{C}',
  'degree': r'{}^{\circ}',
  'arcminute': "{}'",
  'arcsecond': "{}''",
  'percent': r'\%',
  'angstrom': r'\text{Å}',
  'planckbar': r'\hbar',
  'elementarycharge': 'e',
};

/// The abbreviations siunitx gives prefixed units: `\km`, `\uA`, `\kHz`.
final RegExp _abbreviation = RegExp(
  '^(f|p|n|u|m|c|d|h|k|M|G|T)?'
  '(g|m|s|mol|A|l|L|Hz|N|Pa|ohm|V|W|J|eV|F|H|C|K|Wh|B)\$',
);

/// [name] — a unit's name, or an abbreviation — as LaTeX, if it is a unit.
String? _unitNamed(String name) {
  final symbol = _unitSymbols[name];
  if (symbol != null) return symbol;
  final letters = _unitNames[name];
  if (letters != null) return '\\mathrm{$letters}';
  final short = _abbreviation.firstMatch(name);
  if (short == null) return null;
  final prefix = short.group(1) ?? '';
  final unit = short.group(2)!;
  return '${prefix == 'u' ? r'\mu' : '\\mathrm{$prefix}'}'
      '${unit == 'ohm' ? r'\Omega' : '\\mathrm{$unit}'}';
}

/// The units [source] gives — by name, `\kilo\metre\per\second\squared`,
/// or as written, `kg.m/s^2` — as LaTeX.
String _units(String source) {
  final units = <String>[];
  var prefix = '';
  String? power;
  var per = false;

  void add(String unit) {
    final exponent = per ? '-${power ?? '1'}' : power;
    units.add('$prefix$unit${exponent == null ? '' : '^{$exponent}'}');
    prefix = '';
    power = null;
    per = false;
  }

  /// Raises the unit added last to [exponent].
  void raise(String exponent) {
    if (units.isEmpty) return;
    final last = units.removeLast();
    final raised = RegExp(r'\^\{(-?)([^{}]*)\}$').firstMatch(last);
    units.add(
      raised == null
          ? '$last^{$exponent}'
          : '${last.substring(0, raised.start)}'
                '^{${raised.group(1)}$exponent}',
    );
  }

  final arguments = _Arguments(source, 0);
  while (true) {
    arguments._skipSpaces();
    final next = arguments._next;
    if (next == null) break;
    if (next == r'\') {
      final name = arguments.group().substring(1);
      switch (name) {
        case 'per':
          per = true;
        case 'square':
          power = '2';
        case 'cubic':
          power = '3';
        case 'raiseto':
          power = arguments.group();
        case 'squared':
          raise('2');
        case 'cubed':
          raise('3');
        case 'tothe':
          raise(arguments.group());
        case 'of':
          if (units.isNotEmpty) {
            units.add('${units.removeLast()}_{\\mathrm{${arguments.group()}}}');
          }
        case 'highlight' || 'cancel':
          arguments.group();
        case _ when _prefixes.containsKey(name):
          final letters = _prefixes[name]!;
          prefix += letters.startsWith(r'\') ? letters : '\\mathrm{$letters}';
        default:
          add(_unitNamed(name) ?? '\\$name');
      }
      continue;
    }
    arguments.at++;
    switch (next) {
      case '.' || '~' || '*':
        break;
      case '/':
        units.add('/');
      case '^':
        raise(arguments.group());
      case '_':
        if (units.isNotEmpty) {
          units.add('${units.removeLast()}_{${arguments.group()}}');
        }
      default:
        // Written out: a run of letters is one unit.
        var end = arguments.at;
        while (end < source.length &&
            RegExp('[A-Za-zµΩ°%]').hasMatch(source[end])) {
          end++;
        }
        final written = source.substring(arguments.at - 1, end);
        arguments.at = end;
        add(switch (written) {
          '%' => r'\%',
          '°' => r'{}^{\circ}',
          '°C' => r'{}^{\circ}\mathrm{C}',
          _ => '\\mathrm{$written}',
        });
    }
  }
  final out = StringBuffer();
  for (var i = 0; i < units.length; i++) {
    final unit = units[i];
    final joined = i == 0 || unit == '/' || units[i - 1] == '/';
    out
      ..write(joined ? '' : r'\,')
      ..write(unit);
  }
  return out.toString();
}

/// The number [source] as siunitx sets it: `1.5e3` as 1.5 × 10³, `+-` as
/// ±, `x` as ×, long runs of digits grouped in threes.
String _number(String source) {
  final text = source.replaceAll(RegExp(r'\s+'), '');
  if (text.isEmpty) return '';
  final product = text.split('x');
  if (product.length > 1) return product.map(_number).join(r' \times ');
  final uncertain = text.indexOf('+-');
  if (uncertain > 0) {
    return '${_number(text.substring(0, uncertain))} \\pm '
        '${_number(text.substring(uncertain + 2))}';
  }
  final exponent = RegExp(r'^(.*?)[eEdD]([-+]?\d+)$').firstMatch(text);
  if (exponent != null) {
    final mantissa = exponent.group(1)!;
    final power = exponent.group(2)!.replaceFirst('+', '');
    return '${mantissa.isEmpty ? '' : '${_digits(mantissa)} \\times '}'
        '10^{$power}';
  }
  return _digits(text);
}

/// [text], a number, with its digits grouped in threes where there are
/// five or more of them, and a comma for its decimal point read as a point.
String _digits(String text) {
  final parts = RegExp(
    r'^([-+]?)(\d*)(?:[.,](\d*))?(\(\d+\))?$',
  ).firstMatch(text);
  if (parts == null) return text;
  String group(String digits, {required bool fromLeft}) {
    if (digits.length < 5) return digits;
    final groups = <String>[];
    if (fromLeft) {
      for (var i = 0; i < digits.length; i += 3) {
        groups.add(digits.substring(i, math.min(i + 3, digits.length)));
      }
    } else {
      for (var end = digits.length; end > 0; end -= 3) {
        groups.insert(0, digits.substring(math.max(0, end - 3), end));
      }
    }
    return groups.join(r'\,');
  }

  final whole = group(parts.group(2)!, fromLeft: false);
  final fraction = parts.group(3);
  return '${parts.group(1)}${whole.isEmpty && fraction != null ? '0' : whole}'
      '${fraction == null ? '' : '.${group(fraction, fromLeft: true)}'}'
      '${parts.group(4) ?? ''}';
}

/// The quantity [number] [units]: a thin space between them, but none
/// before a degree.
String _quantity(String number, String units) {
  final unit = _units(units);
  return '${_number(number)}${unit.startsWith('{}') ? '' : r'\,'}$unit';
}

/// [items] as siunitx lists them: `1, 2 and 3`.
String _listed(List<String> items) => items.length < 2
    ? items.join()
    : '${items.sublist(0, items.length - 1).join(', ')}\\text{ and }'
          '${items.last}';

final Map<String, _Command> _siunitx = <String, _Command>{
  for (final name in <String>['num', 'tablenum'])
    name: (arguments) {
      arguments.optional();
      return _number(arguments.group());
    },
  for (final name in <String>['si', 'unit'])
    name: (arguments) {
      arguments.optional();
      return _units(arguments.group());
    },
  'SI': (arguments) {
    arguments.optional();
    final number = arguments.group();
    final before = arguments.optional();
    final units = arguments.group();
    return '${before == null ? '' : '$before\\,'}${_quantity(number, units)}';
  },
  'ang': (arguments) {
    arguments.optional();
    final parts = arguments.group().split(';');
    const marks = <String>[r'^{\circ}', "'", "''"];
    return <String>[
      for (var i = 0; i < parts.length && i < 3; i++)
        if (parts[i].trim().isNotEmpty) '${_number(parts[i])}${marks[i]}',
    ].join();
  },
  'numrange': (arguments) {
    arguments.optional();
    return '${_number(arguments.group())}\\text{ to }'
        '${_number(arguments.group())}';
  },
  for (final name in <String>['SIrange', 'qtyrange'])
    name: (arguments) {
      arguments.optional();
      final from = arguments.group();
      final to = arguments.group();
      final units = arguments.group();
      return '${_quantity(from, units)}\\text{ to }${_quantity(to, units)}';
    },
  'numlist': (arguments) {
    arguments.optional();
    return _listed(arguments.group().split(';').map(_number).toList());
  },
  for (final name in <String>['SIlist', 'qtylist'])
    name: (arguments) {
      arguments.optional();
      final numbers = arguments.group().split(';');
      final units = arguments.group();
      return _listed(<String>[
        for (final number in numbers) _quantity(number, units),
      ]);
    },
};
