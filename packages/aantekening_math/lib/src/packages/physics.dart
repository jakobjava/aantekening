part of 'latex_packages.dart';

// The physics package: brackets sized to what they hold, vectors,
// derivatives, Dirac's notation, matrices and words set between quads.

/// `\name{x}` written as [open] x [close], sized unless starred.
_Command _fence(String open, String close) => (arguments) {
  final sized = !arguments.star();
  final inner = arguments.group();
  return sized ? '\\left$open $inner \\right$close' : '$open $inner $close';
};

/// `\name` written as [symbol], and what is bracketed right after it — as
/// `\grad(f)` — sized; a braced group after it is what it applies to.
_Command _operator(String symbol) => (arguments) {
  final bracket = arguments._next == '(' || arguments._next == '['
      ? arguments.delimited()
      : null;
  if (bracket != null) return '$symbol${_between(bracket.open, bracket.inner)}';
  final applied = arguments._next == '{' ? arguments.group() : null;
  return applied == null ? '$symbol ' : '$symbol{$applied}';
};

/// `\qq{words}`, or one of the words physics sets between quads.
_Command _quad(String? words) => (arguments) {
  final starred = arguments.star();
  final text = words ?? arguments.group();
  return '${starred ? '' : r'\quad'}\\text{$text}\\quad ';
};

/// A derivative, `d` (or ∂, δ) [d]: `\dv{f}{x}`, `\dv[n]{f}{x}`, `\dv{x}`,
/// and for partial ones `\pdv{f}{x}{y}`; starred, written in the line.
_Command _derivative(String d) => (arguments) {
  final inline = arguments.star();
  final order = arguments.optional();
  final first = arguments.group();
  final second = arguments.groupIfAny();
  final third = d == r'\partial' ? arguments.groupIfAny() : null;
  final power = order == null ? '' : '^{$order}';
  if (second == null) {
    // Only what it is taken with respect to.
    return inline ? '$d/$d $first$power' : '\\frac{$d$power}{$d $first$power}';
  }
  if (third != null) {
    final top = '$d^{2} $first';
    final bottom = '$d $second\\,$d $third';
    return inline ? '$top/$bottom' : '\\frac{$top}{$bottom}';
  }
  final top = '$d$power $first';
  final bottom = '$d $second$power';
  return inline ? '$top/$bottom' : '\\frac{$top}{$bottom}';
};

/// Dirac's notation: up to [most] braced groups, of which only the first
/// is needed, set between ⟨ and ⟩ as [write] says.
_Command _dirac(
  int most,
  String Function(List<String> parts, bool sized) write,
) => (arguments) {
  final sized = !arguments.star();
  final parts = <String>[arguments.group()];
  while (parts.length < most && arguments.seesGroup) {
    parts.add(arguments.group());
  }
  return write(parts, sized);
};

String _angled(List<String> inside, {required bool sized}) {
  final bar = sized ? r'\middle|' : '|';
  return sized
      ? '\\left\\langle ${inside.join(' $bar ')} \\right\\rangle'
      : '\\langle ${inside.join(' $bar ')} \\rangle';
}

/// A matrix in the environment [environment], its brackets [around] —
/// `(`, `[`, `|` or `{` — or, for `\mqty`, as its own brackets say.
_Command _matrix(String environment, {String? around, bool small = false}) =>
    (arguments) {
      arguments.star();
      final bracket = around == null ? arguments.delimited() : null;
      final body = bracket?.inner ?? arguments.group();
      final open = around ?? bracket?.open;
      if (small) {
        final matrix = '\\begin{smallmatrix}$body\\end{smallmatrix}';
        return open == null || open == '{' ? matrix : _between(open, matrix);
      }
      final named = switch (open) {
        '(' => 'pmatrix',
        '[' => 'bmatrix',
        '|' => 'vmatrix',
        _ => environment,
      };
      return '\\begin{$named}$body\\end{$named}';
    };

/// The rows of a matrix [rows] by [columns], each entry as [entry] says.
String _entries(int rows, int columns, String Function(int i, int j) entry) {
  if (rows > 24 || columns > 24) return '';
  return <String>[
    for (var i = 1; i <= rows; i++)
      <String>[for (var j = 1; j <= columns; j++) entry(i, j)].join(' & '),
  ].join(r' \\ ');
}

int _count(String text) => int.tryParse(text.trim()) ?? 0;

final Map<String, _Command> _physics = <String, _Command>{
  // Brackets.
  'qty': (arguments) {
    if (arguments.seesGroup) {
      // `\qty{3}{m}`, two groups, is siunitx's quantity.
      final value = arguments.group();
      if (arguments.seesGroup) return _quantity(value, arguments.group());
      return _between('{', value);
    }
    final sized = !arguments.star();
    final bracket = arguments.delimited();
    return bracket == null
        ? null
        : _between(bracket.open, bracket.inner, sized: sized);
  },
  'pqty': _fence('(', ')'),
  'bqty': _fence('[', ']'),
  'Bqty': _fence(r'\{', r'\}'),
  'vqty': _fence('|', '|'),
  'abs': _fence(r'\lvert', r'\rvert'),
  'absolutevalue': _fence(r'\lvert', r'\rvert'),
  'norm': _fence(r'\lVert', r'\rVert'),
  'eval': (arguments) {
    final bracket = arguments.delimited();
    if (bracket == null) return null;
    final open = switch (bracket.open) {
      '(' => '(',
      '[' => '[',
      _ => '.',
    };
    return '\\left$open ${bracket.inner} \\right|';
  },
  'order': (arguments) => '\\mathcal{O}${_between('(', arguments.group())}',
  'comm': (arguments) =>
      _between('[', '${arguments.group()}, ${arguments.group()}'),
  'commutator': (arguments) =>
      _between('[', '${arguments.group()}, ${arguments.group()}'),
  'acomm': (arguments) =>
      _between('{', '${arguments.group()}, ${arguments.group()}'),
  'anticommutator': (arguments) =>
      _between('{', '${arguments.group()}, ${arguments.group()}'),
  'pb': (arguments) =>
      _between('{', '${arguments.group()}, ${arguments.group()}'),
  'poissonbracket': (arguments) =>
      _between('{', '${arguments.group()}, ${arguments.group()}'),

  // Vectors.
  for (final name in <String>['vb', 'vectorbold'])
    name: (arguments) => arguments.star()
        ? '\\boldsymbol{${arguments.group()}}'
        : '\\mathbf{${arguments.group()}}',
  for (final name in <String>['va', 'vectorarrow'])
    name: (arguments) => arguments.star()
        ? '\\vec{${arguments.group()}}'
        : '\\vec{\\mathrm{${arguments.group()}}}',
  for (final name in <String>['vu', 'vectorunit'])
    name: (arguments) => arguments.star()
        ? '\\hat{\\boldsymbol{${arguments.group()}}}'
        : '\\hat{\\mathbf{${arguments.group()}}}',
  for (final name in <String>['vdot', 'dotproduct']) name: (_) => r'\cdot ',
  for (final name in <String>['cross', 'cp', 'crossproduct'])
    name: (_) => r'\times ',
  for (final name in <String>['grad', 'gradient']) name: _operator(r'\nabla'),
  for (final name in <String>['div', 'divergence'])
    name: _operator(r'\nabla\cdot'),
  'curl': _operator(r'\nabla\times'),
  'laplacian': _operator(r'\nabla^2'),

  // Operators.
  for (final (names, written) in <(List<String>, String)>[
    (<String>['tr', 'trace'], r'\operatorname{tr}'),
    (<String>['Tr', 'Trace'], r'\operatorname{Tr}'),
    (<String>['rank'], r'\operatorname{rank}'),
    (<String>['erf'], r'\operatorname{erf}'),
    (<String>['Res', 'Residue'], r'\operatorname{Res}'),
    (<String>['pv', 'principalvalue'], r'\mathcal{P}'),
    (<String>['PV'], r'\operatorname{P.V.}'),
    (<String>['Re', 'real'], r'\operatorname{Re}'),
    (<String>['Im', 'imaginary'], r'\operatorname{Im}'),
  ])
    for (final name in names) name: (_) => '$written ',

  // Words between quads.
  'qq': _quad(null),
  'qc': (_) => r',\quad ',
  'qcomma': (_) => r',\quad ',
  'qcc': _quad('c.c.'),
  for (final word in <String>[
    'if',
    'then',
    'else',
    'otherwise',
    'unless',
    'given',
    'using',
    'assume',
    'since',
    'let',
    'for',
    'all',
    'even',
    'odd',
    'integer',
    'and',
    'or',
    'as',
    'in',
  ])
    'q$word': _quad(word),

  // Derivatives.
  'dd': (arguments) {
    final order = arguments.optional();
    final power = order == null ? '' : '^{$order}';
    final bracket = arguments._next == '(' ? arguments.delimited() : null;
    if (bracket != null) {
      return '\\,\\mathrm{d}$power${_between('(', bracket.inner)}';
    }
    return '\\,\\mathrm{d}$power ${arguments.group()}';
  },
  for (final name in <String>['dv', 'derivative'])
    name: _derivative(r'\mathrm{d}'),
  for (final name in <String>['pdv', 'partialderivative', 'pderivative'])
    name: _derivative(r'\partial'),
  for (final name in <String>['fdv', 'functionalderivative'])
    name: _derivative(r'\delta'),
  'var': (arguments) =>
      arguments.seesGroup ? '\\delta ${arguments.group()}' : r'\delta ',

  // Dirac's notation.
  'bra': _dirac(
    1,
    (parts, sized) => sized
        ? '\\left\\langle ${parts.first} \\right|'
        : '\\langle ${parts.first} |',
  ),
  'ket': _dirac(
    1,
    (parts, sized) => sized
        ? '\\left| ${parts.first} \\right\\rangle'
        : '| ${parts.first} \\rangle',
  ),
  for (final name in <String>['braket', 'ip', 'innerproduct'])
    name: _dirac(
      2,
      (parts, sized) => _angled(<String>[
        parts.first,
        parts.length > 1 ? parts[1] : parts.first,
      ], sized: sized),
    ),
  for (final name in <String>['ketbra', 'op', 'outerproduct'])
    name: _dirac(2, (parts, sized) {
      final right = parts.length > 1 ? parts[1] : parts.first;
      return sized
          ? '\\left| ${parts.first} \\right\\rangle\\!'
                '\\left\\langle $right \\right|'
          : '| ${parts.first} \\rangle\\!\\langle $right |';
    }),
  for (final name in <String>['expval', 'ev', 'expectationvalue'])
    name: _dirac(
      2,
      (parts, sized) => parts.length > 1
          ? _angled(<String>[parts[1], parts[0], parts[1]], sized: sized)
          : _angled(<String>[parts.first], sized: sized),
    ),
  for (final name in <String>['mel', 'matrixel', 'matrixelement'])
    name: _dirac(3, (parts, sized) => _angled(parts, sized: sized)),

  // Matrices.
  for (final name in <String>['mqty', 'matrixquantity'])
    name: _matrix('matrix'),
  'pmqty': _matrix('pmatrix', around: '('),
  'bmqty': _matrix('bmatrix', around: '['),
  'vmqty': _matrix('vmatrix', around: '|'),
  'Pmqty': (arguments) =>
      _between('(', '\\begin{matrix}${arguments.group()}\\end{matrix}'),
  'smqty': _matrix('matrix', small: true),
  'spmqty': _matrix('matrix', around: '(', small: true),
  'sbmqty': _matrix('matrix', around: '[', small: true),
  'svmqty': _matrix('matrix', around: '|', small: true),
  'imat': (arguments) {
    final n = _count(arguments.group());
    return _entries(n, n, (i, j) => i == j ? '1' : '0');
  },
  'zmat': (arguments) {
    final rows = _count(arguments.group());
    final columns = _count(arguments.group());
    return _entries(rows, columns, (_, _) => '0');
  },
  'xmat': (arguments) {
    final star = arguments.star();
    final entry = arguments.group();
    final rows = _count(arguments.group());
    final columns = _count(arguments.group());
    return _entries(
      rows,
      columns,
      (i, j) => star ? '${entry}_{$j$i}' : '${entry}_{$i$j}',
    );
  },
  'dmat': (arguments) {
    final diagonal = arguments.group().split(',');
    final n = diagonal.length;
    return _entries(n, n, (i, j) => i == j ? diagonal[i - 1].trim() : '');
  },
  'admat': (arguments) {
    final diagonal = arguments.group().split(',');
    final n = diagonal.length;
    return _entries(
      n,
      n,
      (i, j) => i + j == n + 1 ? diagonal[i - 1].trim() : '',
    );
  },
};
