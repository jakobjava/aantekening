/// Turning OneNote's formulas — Office math, as OneNote keeps it in the
/// runs of a paragraph — into LaTeX.
library;

import 'model.dart';

/// Office math object types ([MS-ONE] 2.3.? MathInlineObject).
abstract final class _MathType {
  static const accent = 10;
  static const box = 11;
  static const boxedFormula = 12;
  static const brackets = 13;
  static const bracketsWithSeparators = 14;
  static const equationArray = 15;
  static const fraction = 16;
  static const functionApply = 17;
  static const leftSubSup = 18;
  static const lowerLimit = 19;
  static const matrix = 20;
  static const nary = 21;
  static const opChar = 22;
  static const overbar = 23;
  static const phantom = 24;
  static const radical = 25;
  static const slashedFraction = 26;
  static const stack = 27;
  static const stretchStack = 28;
  static const subscript = 29;
  static const subSup = 30;
  static const superscript = 31;
  static const underbar = 32;
  static const upperLimit = 33;
}

/// The characters that mark a formula's structure in its text.
const int _objectStart = 0xFDD0;
const int _argumentBreak = 0xFDEE;
const int _objectEnd = 0xFDEF;

sealed class _Node {}

final class _Text extends _Node {
  _Text(this.text);
  final String text;
}

final class _Object extends _Node {
  _Object(this.math);
  final OneMathObject? math;
  final List<List<_Node>> arguments = <List<_Node>>[<_Node>[]];
}

/// The LaTeX of the formulas in [runs] — consecutive runs of math, each
/// carrying the object that starts in it — as OneNote would break them over
/// lines: after each `;` and at each line break between structures, a
/// break shown as null.
///
/// Each structure is written from what its object says it is — a fraction
/// and a power have the same two arguments, and only the object tells them
/// apart. Markers of a structure that is damaged are dropped, keeping its
/// text.
List<String?> officeMathToLatex(List<OneRun> runs) {
  final root = <_Node>[];
  var current = root;
  final open = <(_Object, List<_Node>)>[];
  for (final run in runs) {
    final buffer = StringBuffer();
    void flush() {
      if (buffer.isEmpty) return;
      current.add(_Text(buffer.toString()));
      buffer.clear();
    }

    for (final rune in run.text.runes) {
      switch (rune) {
        case _objectStart:
          flush();
          final object = _Object(run.math);
          current.add(object);
          open.add((object, current));
          current = object.arguments.first;
        case _argumentBreak when open.isNotEmpty:
          flush();
          final arguments = open.last.$1.arguments;
          arguments.add(<_Node>[]);
          current = arguments.last;
        case _objectEnd when open.isNotEmpty:
          flush();
          current = open.removeLast().$2;
        case _argumentBreak || _objectEnd:
          break;
        default:
          buffer.writeCharCode(rune);
      }
    }
    flush();
  }
  return _pieces(root);
}

/// [nodes] split after each `;` outside any structure, and at each line
/// break there.
List<String?> _pieces(List<_Node> nodes) {
  final pieces = <String?>[];
  var piece = <_Node>[];
  void finish() {
    // Spaces around a piece are the gaps between the formulas.
    final latex = _latex(
      piece,
    ).replaceAll(RegExp(r'^(\\ |\s)+|(\\ |\s)+$'), '');
    if (latex.isNotEmpty) pieces.add(latex);
    piece = <_Node>[];
  }

  for (final node in nodes) {
    if (node is! _Text) {
      piece.add(node);
      continue;
    }
    final buffer = StringBuffer();
    for (final rune in node.text.runes) {
      if (rune == 0x0B || rune == 0x0A || rune == 0x0D) {
        piece.add(_Text(buffer.toString()));
        buffer.clear();
        finish();
        pieces.add(null);
      } else {
        buffer.writeCharCode(rune);
        if (rune == 0x3B) {
          piece.add(_Text(buffer.toString()));
          buffer.clear();
          finish();
        }
      }
    }
    if (buffer.isNotEmpty) piece.add(_Text(buffer.toString()));
  }
  finish();
  return pieces;
}

String _latex(List<_Node> nodes) {
  final out = StringBuffer();
  for (final node in nodes) {
    switch (node) {
      case _Text(:final text):
        out.write(mathText(text));
      case _Object():
        out.write(_objectLatex(node));
    }
  }
  return out.toString();
}

String _objectLatex(_Object object) {
  final math = object.math;
  final arguments = <String>[for (final list in object.arguments) _latex(list)];
  String argument(int index) =>
      index < arguments.length ? arguments[index] : '';
  final type = math?.type ?? 0;
  final char = math?.char;
  switch (type) {
    case _MathType.fraction:
      return '\\frac{${argument(0)}}{${argument(1)}}';
    case _MathType.slashedFraction:
      return '{${argument(0)}}/{${argument(1)}}';
    case _MathType.stack:
      return '\\genfrac{}{}{0pt}{}{${argument(0)}}{${argument(1)}}';
    case _MathType.superscript:
      return '{${argument(0)}}^{${argument(1)}}';
    case _MathType.subscript:
      return '{${argument(0)}}_{${argument(1)}}';
    case _MathType.subSup:
      return '{${argument(0)}}_{${argument(1)}}^{${argument(2)}}';
    case _MathType.leftSubSup:
      return '{}_{${argument(0)}}^{${argument(1)}}{${argument(2)}}';
    case _MathType.radical:
      final index = argument(0);
      return '\\sqrt${index.isEmpty ? '' : '[$index]'}{${argument(1)}}';
    case _MathType.brackets || _MathType.bracketsWithSeparators:
      final separator = _delimiter(math?.char2, fallback: '|');
      final body = arguments.join('\\middle$separator ');
      return '\\left${_delimiter(char, fallback: '(')} $body'
          '\\right${_delimiter(math?.char1, fallback: ')')} ';
    case _MathType.matrix:
      final columns = (math?.columns ?? 1).clamp(1, 1 << 16);
      final rows = <String>[
        for (var i = 0; i < arguments.length; i += columns)
          arguments
              .sublist(i, (i + columns).clamp(0, arguments.length))
              .join(' & '),
      ];
      return '\\begin{matrix}${rows.join(r' \\ ')}\\end{matrix}';
    case _MathType.equationArray:
      final aligned = arguments.any((row) => row.contains('&'));
      final environment = aligned ? 'aligned' : 'gathered';
      return '\\begin{$environment}'
          '${arguments.map(_numbered).join(r' \\ ')}'
          '\\end{$environment}';
    case _MathType.nary:
      final operator = char == null
          ? r'\int'
          : mathText(String.fromCharCode(char));
      final lower = argument(0);
      final upper = argument(1);
      return '$operator${lower.isEmpty ? '' : '_{$lower}'}'
          '${upper.isEmpty ? '' : '^{$upper}'}{${argument(2)}}';
    case _MathType.functionApply:
      return '${argument(0)}{${argument(1)}}';
    case _MathType.lowerLimit:
      final base = argument(0);
      return _isLimitOperator(base)
          ? '$base\\limits_{${argument(1)}}'
          : '\\underset{${argument(1)}}{$base}';
    case _MathType.upperLimit:
      final base = argument(0);
      return _isLimitOperator(base)
          ? '$base\\limits^{${argument(1)}}'
          : '\\overset{${argument(1)}}{$base}';
    case _MathType.accent || _MathType.stretchStack:
      return _accent(char, argument(0));
    case _MathType.overbar:
      return '\\overline{${argument(0)}}';
    case _MathType.underbar:
      return '\\underline{${argument(0)}}';
    case _MathType.boxedFormula:
      return '\\boxed{${argument(0)}}';
    case _MathType.phantom:
      return '\\phantom{${argument(0)}}';
    case _MathType.opChar:
      return '${char == null ? '' : mathText(String.fromCharCode(char))}'
          '${arguments.join()}';
    case _MathType.box:
    default:
      return '{${arguments.join()}}';
  }
}

/// A row of an equation array as it is set: in OneNote's linear format a
/// `#` ends the equation and begins its number, `E=mc^2#(1)`, which is set
/// to its right; a `#` with nothing after it is not shown.
String _numbered(String row) {
  const mark = r'\#';
  final at = row.lastIndexOf(mark);
  if (at < 0) return row;
  final number = row.substring(at + mark.length).trim();
  final equation = row.substring(0, at);
  return number.isEmpty ? equation : '$equation\\qquad $number';
}

bool _isLimitOperator(String latex) => RegExp(
  r'^\\(lim|max|min|sup|inf|limsup|liminf|sum|prod|bigcup|bigcap)\s*$',
).hasMatch(latex.trim());

String _accent(int? char, String body) {
  final command = switch (char) {
    0x0302 => 'hat',
    0x0303 => 'tilde',
    0x0304 => 'bar',
    0x0305 || 0x00AF => 'overline',
    0x0307 => 'dot',
    0x0308 => 'ddot',
    0x20DB => 'dddot',
    0x20D7 || 0x2192 => 'vec',
    0x20D6 || 0x2190 => 'overleftarrow',
    0x20E1 || 0x2194 => 'overleftrightarrow',
    0x030C => 'check',
    0x0306 => 'breve',
    0x0301 => 'acute',
    0x0300 => 'grave',
    0x030A => 'mathring',
    0x23DE => 'overbrace',
    0x23DF => 'underbrace',
    0x0332 => 'underline',
    _ => null,
  };
  if (command != null) return '\\$command{$body}';
  if (char == null) return '{$body}';
  return '\\overset{${mathText(String.fromCharCode(char))}}{$body}';
}

String _delimiter(int? char, {required String fallback}) => switch (char) {
  null => fallback,
  0 => '.',
  0x28 => '(',
  0x29 => ')',
  0x5B => '[',
  0x5D => ']',
  0x7B => r'\{',
  0x7D => r'\}',
  0x7C => '|',
  0x2016 => r'\Vert',
  0x27E8 || 0x2329 => r'\langle',
  0x27E9 || 0x232A => r'\rangle',
  0x2308 => r'\lceil',
  0x2309 => r'\rceil',
  0x230A => r'\lfloor',
  0x230B => r'\rfloor',
  0x27E6 => r'[\![',
  0x27E7 => r']\!]',
  _ => '.',
};

/// The LaTeX of the characters of a formula outside its structures.
///
/// OneNote writes a formula's letters as mathematical italic characters,
/// and what it sets upright — function names, units — as ordinary letters;
/// LaTeX sets letters in italic by itself, so the italic ones become
/// letters and the upright ones are set upright.
String mathText(String text) {
  final out = StringBuffer();
  final runes = text.runes.toList();
  var i = 0;
  while (i < runes.length) {
    final rune = runes[i];
    // A word of upright letters: a function's name, or text.
    if (_isAsciiLetter(rune)) {
      final start = i;
      while (i < runes.length && _isAsciiLetter(runes[i])) {
        i++;
      }
      final word = String.fromCharCodes(runes.sublist(start, i));
      out.write(_functions.contains(word) ? '\\$word ' : '\\mathrm{$word}');
      continue;
    }
    // A decimal comma between digits, which LaTeX would space as a comma.
    if (rune == 0x2C &&
        i > 0 &&
        i + 1 < runes.length &&
        _isDigit(runes[i - 1]) &&
        _isDigit(runes[i + 1])) {
      out.write('{,}');
      i++;
      continue;
    }
    out.write(_character(rune));
    i++;
  }
  return out.toString();
}

bool _isAsciiLetter(int rune) =>
    (rune >= 0x41 && rune <= 0x5A) || (rune >= 0x61 && rune <= 0x7A);

bool _isDigit(int rune) => rune >= 0x30 && rune <= 0x39;

const Set<String> _functions = <String>{
  'sin', 'cos', 'tan', 'cot', 'sec', 'csc', 'arcsin', 'arccos', 'arctan', //
  'sinh', 'cosh', 'tanh', 'coth', 'log', 'ln', 'lg', 'exp', 'lim', 'max',
  'min', 'sup', 'inf', 'det', 'dim', 'ker', 'deg', 'gcd', 'arg', 'Pr', 'hom',
};

String _character(int rune) {
  final symbol = _symbols[rune];
  if (symbol != null) return symbol;
  if (rune < 0x80) {
    return switch (rune) {
      0x20 => r'\ ',
      0x5C => r'\backslash ',
      0x7B => r'\{',
      0x7D => r'\}',
      0x26 => r'\&',
      0x25 => r'\%',
      0x24 => r'\$',
      0x23 => r'\#',
      0x5F => r'\_',
      0x5E => r'\hat{}',
      0x7E => r'\sim ',
      0x0B || 0x0A || 0x0D => ' ',
      _ => String.fromCharCode(rune),
    };
  }
  final styled = _styledLetter(rune);
  if (styled != null) return styled;
  if (_greek.containsKey(rune)) return _greek[rune]!;
  final char = String.fromCharCode(rune);
  // Other letters, as in a word written in the formula: set as text.
  if (RegExp(r'\p{L}', unicode: true).hasMatch(char)) return '\\text{$char}';
  return char;
}

/// A mathematical alphanumeric character ([Unicode] U+1D400–1D7FF, and
/// the letterlike symbols standing in its gaps) as a letter or digit in
/// the style it is drawn in.
String? _styledLetter(int rune) {
  final letterlike = _letterlike[rune];
  if (letterlike != null) {
    return _styled(letterlike.$2, _mathLetter(letterlike.$1));
  }
  if (rune >= 0x1D400 && rune < 0x1D6A4) {
    final style = (rune - 0x1D400) ~/ 52;
    final index = (rune - 0x1D400) % 52;
    final letter = String.fromCharCode(
      index < 26 ? 0x41 + index : 0x61 + index - 26,
    );
    return _styled(_letterStyles[style], letter);
  }
  if (rune >= 0x1D6A8 && rune < 0x1D7CA) {
    final style = (rune - 0x1D6A8) ~/ 58;
    final index = (rune - 0x1D6A8) % 58;
    final greek = _greekOrder[index];
    final latex = _greek[greek] ?? String.fromCharCode(greek);
    return _styled(_greekStyles[style], latex);
  }
  if (rune >= 0x1D7CE && rune <= 0x1D7FF) {
    final style = (rune - 0x1D7CE) ~/ 10;
    final digit = String.fromCharCode(0x30 + (rune - 0x1D7CE) % 10);
    return _styled(_digitStyles[style], digit);
  }
  return null;
}

String _mathLetter(int rune) => _greek[rune] ?? String.fromCharCode(rune);

String _styled(String? command, String letter) =>
    command == null ? letter : '\\$command{$letter}';

/// The styles of the letter blocks of Mathematical Alphanumeric Symbols,
/// in order, each 52 letters long; null for italic, LaTeX's own.
const List<String?> _letterStyles = <String?>[
  'mathbf', null, 'boldsymbol', 'mathcal', 'mathcal', 'mathfrak', //
  'mathbb', 'mathfrak', 'mathsf', 'mathsf', 'mathsf', 'mathsf', 'mathtt',
];

const List<String?> _greekStyles = <String?>[
  'boldsymbol',
  null,
  'boldsymbol',
  'boldsymbol',
  'boldsymbol',
];

const List<String?> _digitStyles = <String?>[
  'mathbf',
  'mathbb',
  'mathsf',
  'mathsf',
  'mathtt',
];

/// The Greek letters of each Greek block, in order.
final List<int> _greekOrder = <int>[
  for (var c = 0x391; c <= 0x3A9; c++) c == 0x3A2 ? 0x3F4 : c,
  0x2207,
  for (var c = 0x3B1; c <= 0x3C9; c++) c,
  0x2202,
  0x3F5,
  0x3D1,
  0x3F0,
  0x3D5,
  0x3F1,
  0x3D6,
];

/// Letterlike symbols filling the gaps of the alphanumeric blocks: the
/// letter each stands for, and its style.
const Map<int, (int, String?)> _letterlike = <int, (int, String?)>{
  0x210E: (0x68, null), // italic h
  0x212C: (0x42, 'mathcal'), 0x2130: (0x45, 'mathcal'),
  0x2131: (0x46, 'mathcal'), 0x210B: (0x48, 'mathcal'),
  0x2110: (0x49, 'mathcal'), 0x2112: (0x4C, 'mathcal'),
  0x2133: (0x4D, 'mathcal'), 0x211B: (0x52, 'mathcal'),
  0x212F: (0x65, 'mathcal'), 0x210A: (0x67, 'mathcal'),
  0x2134: (0x6F, 'mathcal'),
  0x212D: (0x43, 'mathfrak'), 0x210C: (0x48, 'mathfrak'),
  0x2111: (0x49, 'mathfrak'), 0x211C: (0x52, 'mathfrak'),
  0x2128: (0x5A, 'mathfrak'),
  0x2102: (0x43, 'mathbb'), 0x210D: (0x48, 'mathbb'),
  0x2115: (0x4E, 'mathbb'), 0x2119: (0x50, 'mathbb'),
  0x211A: (0x51, 'mathbb'), 0x211D: (0x52, 'mathbb'),
  0x2124: (0x5A, 'mathbb'),
};

final Map<int, String> _greek = () {
  const lower = <String>[
    'alpha', 'beta', 'gamma', 'delta', 'epsilon', 'zeta', 'eta', 'theta', //
    'iota', 'kappa', 'lambda', 'mu', 'nu', 'xi', 'o', 'pi', 'rho',
    'varsigma', 'sigma', 'tau', 'upsilon', 'phi', 'chi', 'psi', 'omega',
  ];
  const upper = <String>[
    'A', 'B', 'Gamma', 'Delta', 'E', 'Z', 'H', 'Theta', 'I', 'K', //
    'Lambda', 'M', 'N', 'Xi', 'O', 'Pi', 'P', '', 'Sigma', 'T', 'Upsilon',
    'Phi', 'X', 'Psi', 'Omega',
  ];
  String command(String name) => name.length == 1 ? name : '\\$name ';
  return <int, String>{
    for (var i = 0; i < lower.length; i++) 0x3B1 + i: command(lower[i]),
    for (var i = 0; i < upper.length; i++)
      if (upper[i].isNotEmpty) 0x391 + i: command(upper[i]),
    // OneNote's ϕ is the straight phi, φ the curly one LaTeX calls varphi.
    0x3C6: r'\varphi ', 0x3D5: r'\phi ',
    0x3B5: r'\varepsilon ', 0x3F5: r'\epsilon ',
    0x3D1: r'\vartheta ', 0x3F0: r'\varkappa ', 0x3F1: r'\varrho ',
    0x3D6: r'\varpi ', 0x3F4: r'\Theta ', 0x2207: r'\nabla ',
    0x2202: r'\partial ',
  };
}();

const Map<int, String> _symbols = <int, String>{
  0x2212: '-', 0x22C5: r'\cdot ', 0x2219: r'\cdot ', 0x00B7: r'\cdot ', //
  0x00D7: r'\times ', 0x00F7: r'\div ', 0x00B1: r'\pm ', 0x2213: r'\mp ',
  0x00B0: r'^{\circ}', 0x2218: r'\circ ', 0x2217: '*', 0x2032: "'",
  0x2033: "''", 0x2034: "'''",
  0x2208: r'\in ', 0x2209: r'\notin ', 0x220B: r'\ni ', 0x221E: r'\infty ',
  0x2260: r'\ne ', 0x2248: r'\approx ', 0x2261: r'\equiv ', 0x2264: r'\le ',
  0x2265: r'\ge ', 0x226A: r'\ll ', 0x226B: r'\gg ', 0x221D: r'\propto ',
  0x223C: r'\sim ', 0x2245: r'\cong ', 0x2243: r'\simeq ', 0x2259: r'\hat{=}',
  0x2254: r'\coloneqq ', 0x225D: r'\stackrel{\text{def}}{=}',
  0x21D2: r'\Rightarrow ', 0x21D0: r'\Leftarrow ', 0x21D4: r'\Leftrightarrow ',
  0x27F9: r'\implies ', 0x27FA: r'\iff ', 0x2192: r'\to ',
  0x2190: r'\leftarrow ', 0x2194: r'\leftrightarrow ', 0x21A6: r'\mapsto ',
  0x2191: r'\uparrow ', 0x2193: r'\downarrow ',
  0x2229: r'\cap ', 0x222A: r'\cup ', 0x2282: r'\subset ',
  0x2283: r'\supset ', 0x2286: r'\subseteq ', 0x2287: r'\supseteq ',
  0x2284: r'\not\subset ', 0x2205: r'\varnothing ', 0x2216: r'\setminus ',
  0x2200: r'\forall ', 0x2203: r'\exists ', 0x2204: r'\nexists ',
  0x2227: r'\wedge ', 0x2228: r'\vee ', 0x00AC: r'\neg ', 0x22A5: r'\perp ',
  0x2225: r'\parallel ', 0x2220: r'\angle ', 0x25B3: r'\triangle ',
  0x2206: r'\Delta ', 0x2211: r'\sum ', 0x220F: r'\prod ', 0x2210: r'\coprod ',
  0x222B: r'\int ', 0x222C: r'\iint ', 0x222D: r'\iiint ', 0x222E: r'\oint ',
  0x22C3: r'\bigcup ', 0x22C2: r'\bigcap ', 0x221A: r'\surd ',
  0x2026: r'\ldots ', 0x22EF: r'\cdots ', 0x22EE: r'\vdots ',
  0x22F1: r'\ddots ', 0x00B5: r'\mu ', 0x2113: r'\ell ', 0x210F: r'\hbar ',
  0x2135: r'\aleph ', 0x211C: r'\Re ', 0x2111: r'\Im ', 0x2118: r'\wp ',
  0x2016: r'\Vert ', 0x27E8: r'\langle ', 0x27E9: r'\rangle ',
  0x2308: r'\lceil ', 0x2309: r'\rceil ', 0x230A: r'\lfloor ',
  0x230B: r'\rfloor ', 0x1D6A4: r'\imath ', 0x1D6A5: r'\jmath ',
  // Invisible operators: function application, invisible times and comma.
  0x2061: '', 0x2062: '', 0x2063: '', 0x2064: '+', 0x200B: '',
  0x2009: r'\,', 0x200A: r'\,', 0x2005: r'\:', 0x2004: r'\;',
  0x2002: r'\enspace ', 0x2003: r'\quad ', 0x00A0: r'\ ',
  0x2070: '^{0}', 0x00B9: '^{1}', 0x00B2: '^{2}', 0x00B3: '^{3}',
  0x2074: '^{4}', 0x2075: '^{5}', 0x2076: '^{6}', 0x2077: '^{7}',
  0x2078: '^{8}', 0x2079: '^{9}', 0x2080: '_{0}', 0x2081: '_{1}',
  0x2082: '_{2}', 0x2083: '_{3}', 0x2084: '_{4}', 0x2085: '_{5}',
  0x2086: '_{6}', 0x2087: '_{7}', 0x2088: '_{8}', 0x2089: '_{9}',
  // Office's placeholder for an empty argument.
  0x2B1A: '', 0x25A1: r'\square ',
};
