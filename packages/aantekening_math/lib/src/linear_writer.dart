/// Writes a syntax tree in the linear syntax, so a formula stored as LaTeX
/// can be edited in Simple syntax.
library;

import 'ast.dart';
import 'symbols.dart';

/// Writes [MathNode]s as linear input that parses back to the same LaTeX.
///
/// It puts in only the brackets the parser needs — `(a+b)/c` but `x^2/3` —
/// and spaces only where two words would otherwise run together, so what it
/// writes reads the way a person would type it. Anything the linear syntax
/// has no spelling for is written as LaTeX: a backslash command as it is, and
/// anything else in backticks.
abstract final class LinearWriter {
  static String write(MathNode node) => _join(_pieces(node));

  // ------------------------------------------------------------ vocabulary

  /// Words for LaTeX symbols, the most familiar spelling winning.
  static final Map<String, String> _words = () {
    final words = <String, String>{};
    void add(String latex, String word) => words.putIfAbsent(latex, () => word);
    add(r'\infty', 'infty');
    for (final entry in greekLetters.entries) {
      if (entry.value.startsWith(r'\')) add(entry.value, entry.key);
    }
    for (final entry in wordSymbols.entries) {
      add(entry.value, entry.key);
    }
    for (final name in namedFunctions) {
      add('\\$name', name);
    }
    for (final entry in bigOperators.entries) {
      add(entry.value, entry.key);
    }
    return words;
  }();

  /// Operators typed with punctuation, preferred over their words.
  static const Map<String, String> _punctuation = <String, String>{
    r'\leq': '<=',
    r'\le': '<=',
    r'\geq': '>=',
    r'\ge': '>=',
    r'\neq': '!=',
    r'\ne': '!=',
    r'\to': '->',
    r'\rightarrow': '->',
    r'\leftarrow': '<-',
    r'\gets': '<-',
    r'\Rightarrow': '=>',
    r'\iff': '<=>',
    r'\Leftrightarrow': '<=>',
    r'\implies': '==>',
    r'\impliedby': '<==',
    r'\approx': '~~',
    r'\pm': '+-',
    r'\mp': '-+',
    r'\cdot': '*',
    r'\ldots': '...',
    r'\colon': '::',
  };

  /// Accents and styles with a word of their own.
  static final Map<String, String> _accentWords = <String, String>{
    for (final entry in unaryConstructs.entries)
      if (entry.value != r'\sqrt') entry.value: entry.key,
  };

  static const Map<String, String> _gridWords = <String, String>{
    'pmatrix': 'mat',
    'bmatrix': 'bmat',
    'Bmatrix': 'Bmat',
    'vmatrix': 'vmat',
    'Vmatrix': 'Vmat',
    'matrix': 'matrix',
    'cases': 'cases',
  };

  /// Single characters the linear syntax reads as themselves.
  static const Set<String> _plainCharacters = <String>{
    ',',
    '.',
    '!',
    '=',
    '<',
    '>',
    '+',
    '-',
    ':',
    '/',
  };

  static bool _isOperator(String latex) =>
      relationOperators.contains(latex) ||
      additiveOperators.contains(latex) ||
      multiplicativeOperators.contains(latex) ||
      _punctuation.containsKey(latex) && latex != r'\ldots';

  // ---------------------------------------------------------------- pieces

  /// [node] as the pieces the joiner separates with spaces where needed.
  static List<_Piece> _pieces(MathNode node) => switch (node) {
    NumberNode(:final text) => <_Piece>[_Piece(text)],
    VariableNode(:final name) => <_Piece>[_Piece(name)],
    SymbolNode(:final latex) => <_Piece>[_symbol(latex)],
    TextNode(:final text) => <_Piece>[_Piece('"$text"', apart: true)],
    SequenceNode(:final children) => _sequence(children),
    BinaryNode(:final operatorLatex, :final left, :final right) => <_Piece>[
      ..._pieces(left),
      _operator(operatorLatex),
      ..._pieces(right),
    ],
    UnaryNode(:final operatorLatex, :final operand) => <_Piece>[
      _Piece(_spelling(operatorLatex), prefix: true),
      ..._pieces(operand),
    ],
    FractionNode(:final numerator, :final denominator) => <_Piece>[
      _Piece(
        '${_fractionPart(numerator)}/${_fractionPart(denominator)}',
        apart: true,
      ),
    ],
    ScriptNode(:final subscript, :final superscript) => <_Piece>[
      _Piece(
        _script(node),
        // Primes stay on what they mark: f'(x).
        apart:
            subscript != null || superscript != null && !_isPrimes(superscript),
      ),
    ],
    PostfixNode(:final operand, :final operatorLatex) => <_Piece>[
      _Piece(
        '${_isAtom(operand) ? write(operand) : '{${write(operand)}}'}'
        '$operatorLatex',
      ),
    ],
    RootNode(:final radicand, :final index) => <_Piece>[
      _Piece(
        index == null
            ? 'sqrt(${write(radicand)})'
            : 'root(${write(index)}, ${write(radicand)})',
      ),
    ],
    AccentNode(:final command, :final operand) => <_Piece>[
      _Piece(_accent(command, operand)),
    ],
    BinaryConstructNode(:final command, :final first, :final second) =>
      <_Piece>[_Piece(_binaryConstruct(command, first, second))],
    FencedNode() => <_Piece>[_Piece(_fenced(node))],
    GroupNode(:final child) => <_Piece>[_Piece('{${write(child)}}')],
    EmptyNode() => const <_Piece>[],
    ListNode(:final items) => <_Piece>[_Piece(items.map(write).join(', '))],
    ApplicationNode(:final function, :final argument) => <_Piece>[
      _Piece('${write(function)}${write(argument)}'),
    ],
    MatrixNode() => <_Piece>[_Piece(_matrix(node))],
    RawNode(:final latex) => <_Piece>[_raw(latex)],
  };

  static List<_Piece> _sequence(List<MathNode> children) {
    final pieces = <_Piece>[];
    for (final child in children) {
      if (child is SymbolNode && child.latex == ',') {
        pieces.add(const _Piece(',', comma: true));
        continue;
      }
      if (child is SymbolNode && child.latex == '!' && pieces.isNotEmpty) {
        // A factorial belongs to what comes before it.
        final last = pieces.removeLast();
        pieces.add(_Piece('${last.text}!', apart: last.apart));
        continue;
      }
      if (child is SymbolNode && _isOperator(child.latex)) {
        // A sign at the start, or after another operator, is a prefix.
        final prefix =
            (pieces.isEmpty || pieces.last.isOperator) &&
            (child.latex == '-' ||
                child.latex == '+' ||
                child.latex == r'\pm' ||
                child.latex == r'\mp');
        pieces.add(
          prefix
              ? _Piece(_spelling(child.latex), prefix: true)
              : _operator(child.latex),
        );
        continue;
      }
      pieces.addAll(_pieces(child));
    }
    return pieces;
  }

  static _Piece _operator(String latex) {
    final spelling = _spelling(latex);
    if (latex == ',' || latex == '.') return _Piece(spelling, comma: true);
    return _Piece(spelling, isOperator: true);
  }

  /// How [latex] is typed: punctuation, a word, the command itself, or the
  /// character.
  static String _spelling(String latex) =>
      _punctuation[latex] ?? _words[latex] ?? latex;

  static _Piece _symbol(String latex) {
    if (latex == r'\prime') return const _Piece("'");
    final spelling = _punctuation[latex] ?? _words[latex];
    if (spelling != null) return _Piece(spelling);
    if (latex.startsWith(r'\') && latex.length > 1) return _Piece(latex);
    if (_plainCharacters.contains(latex)) return _Piece(latex);
    // `*`, `|`, `;` and brackets that do not pair up mean something else
    // in the linear syntax.
    return _raw(latex);
  }

  static _Piece _raw(String latex) => _Piece('`$latex`');

  // ------------------------------------------------------------- structure

  /// A fraction's numerator or denominator: bare if the parser reads it as
  /// one factor, bracketed otherwise.
  static String _fractionPart(MathNode node) {
    if (node is FencedNode && node.isRoundParen) return '(${write(node)})';
    if (_isAtom(node) || node is ScriptNode || node is PostfixNode) {
      return write(node);
    }
    return '(${write(node)})';
  }

  /// A script: bare if it is one token, bracketed otherwise.
  static String _scriptPart(MathNode node) {
    if (node is FencedNode && node.isRoundParen) return '(${write(node)})';
    if (_isAtom(node)) return write(node);
    return '(${write(node)})';
  }

  /// Whether the parser reads [node]'s spelling as a single primary.
  static bool _isAtom(MathNode node) => switch (node) {
    NumberNode() || VariableNode() || TextNode() => true,
    SymbolNode(:final latex) =>
      !_isOperator(latex) && latex != r'\prime' && latex.isNotEmpty,
    RootNode() ||
    AccentNode() ||
    BinaryConstructNode() ||
    FencedNode() ||
    GroupNode() ||
    MatrixNode() ||
    RawNode() ||
    ApplicationNode() => true,
    SequenceNode(:final children) =>
      children.length == 1 && _isAtom(children.single),
    _ => false,
  };

  static bool _isPrimes(MathNode node) =>
      node is SymbolNode && node.latex == r'\prime' ||
      node is SequenceNode &&
          node.children.isNotEmpty &&
          node.children.every(
            (child) => child is SymbolNode && child.latex == r'\prime',
          );

  static String _script(ScriptNode node) {
    final base = node.base;
    final out = StringBuffer(
      _isAtom(base) && base is! SequenceNode
          ? write(base)
          : base is SequenceNode && base.children.isEmpty
          ? '{}'
          : '{${write(base)}}',
    );
    final subscript = node.subscript;
    if (subscript != null) out.write('_${_scriptPart(subscript)}');
    final superscript = node.superscript;
    if (superscript != null) {
      if (_isPrimes(superscript)) {
        out.write(
          "'" * (superscript is SequenceNode ? superscript.children.length : 1),
        );
      } else {
        out.write('^${_scriptPart(superscript)}');
      }
    }
    return out.toString();
  }

  static String _accent(String command, MathNode operand) {
    final word = _accentWords[command];
    if (word != null) return '$word(${write(operand)})';
    return '$command{${write(operand)}}';
  }

  static String _binaryConstruct(
    String command,
    MathNode first,
    MathNode second,
  ) => switch (command) {
    r'\frac' => '${_fractionPart(first)}/${_fractionPart(second)}',
    r'\binom' => 'binom(${write(first)}, ${write(second)})',
    r'\stackrel' => 'stackrel(${write(first)}, ${write(second)})',
    _ => '$command{${write(first)}}{${write(second)}}',
  };

  static String _fenced(FencedNode node) {
    final inner = write(node.child);
    final left = node.left;
    final right = node.right;
    bool isOneOf(String delimiter, Set<String> set) => set.contains(delimiter);
    if (left == '(' && right == ')') return '($inner)';
    if (left == '[' && right == ']') return '[$inner]';
    if (isOneOf(left, const <String>{'|', r'\vert', r'\lvert'}) &&
        isOneOf(right, const <String>{'|', r'\vert', r'\rvert'})) {
      return inner.contains('|') ? 'abs($inner)' : '|$inner|';
    }
    if (isOneOf(left, const <String>{r'\|', r'\Vert', r'\lVert'}) &&
        isOneOf(right, const <String>{r'\|', r'\Vert', r'\rVert'})) {
      return 'norm($inner)';
    }
    if (left == r'\lfloor' && right == r'\rfloor') return 'floor($inner)';
    if (left == r'\lceil' && right == r'\rceil') return 'ceil($inner)';
    if (left == r'\langle' && right == r'\rangle') return 'inner($inner)';
    if (left == r'\{' && right == r'\}') return 'set($inner)';
    return '`${node.toLatex()}`';
  }

  static String _matrix(MatrixNode node) {
    final rows = node.rows;
    final isColumn =
        node.environment == 'pmatrix' &&
        rows.length > 1 &&
        rows.every((row) => row.length == 1);
    if (isColumn) {
      return 'vec(${rows.map((row) => write(row.single)).join(', ')})';
    }
    final word = _gridWords[node.environment];
    if (word == null) return '`${node.toLatex()}`';
    final cells = rows.map((row) => row.map(write).join(', ')).join('; ');
    return '$word($cells)';
  }

  // ---------------------------------------------------------------- joining

  static String _join(List<_Piece> pieces) {
    final out = StringBuffer();
    // What was last written, or empty after a space.
    var previous = '';
    var previousApart = false;
    for (final piece in pieces) {
      if (piece.text.isEmpty) continue;
      if (piece.isOperator) {
        out.write(out.isEmpty ? '${piece.text} ' : ' ${piece.text} ');
        previous = '';
        continue;
      }
      if (piece.comma) {
        out.write('${piece.text} ');
        previous = '';
        continue;
      }
      if (previous.isNotEmpty &&
          (piece.apart ||
              previousApart ||
              _runTogether(previous, piece.text))) {
        out.write(' ');
      }
      out.write(piece.text);
      previous = piece.text;
      previousApart = piece.apart;
    }
    return out.toString().trim();
  }

  /// Whether writing [next] straight after [previous] would read as one
  /// token: two words becoming one, or two numbers.
  static bool _runTogether(String previous, String next) {
    final a = previous.codeUnitAt(previous.length - 1);
    final b = next.codeUnitAt(0);
    if (_isLetter(a) && _isLetter(b)) return true;
    return _isDigit(a) && (_isDigit(b) || b == 0x2E);
  }

  static bool _isLetter(int code) =>
      (code >= 0x41 && code <= 0x5A) || (code >= 0x61 && code <= 0x7A);

  static bool _isDigit(int code) => code >= 0x30 && code <= 0x39;
}

class _Piece {
  const _Piece(
    this.text, {
    this.isOperator = false,
    this.prefix = false,
    this.comma = false,
    this.apart = false,
  });

  final String text;

  /// An infix operator, written with a space either side.
  final bool isOperator;

  /// A sign written straight before what it applies to.
  final bool prefix;

  /// A comma or full stop, followed by a space.
  final bool comma;

  /// Set off from its neighbours by spaces, for reading: a fraction, a
  /// script, quoted text.
  final bool apart;
}
