/// Recursive-descent parser for linear math input.
library;

import 'ast.dart';
import 'lexer.dart';
import 'symbols.dart';

/// Parses a token stream into a [MathNode] tree.
///
/// The parser never throws. A half-finished expression is the normal state
/// while someone is typing, so unexpected or missing tokens are recorded as
/// [MathDiagnostic]s and stood in for with [EmptyNode], letting the live
/// preview keep rendering.
class MathParser {
  MathParser(this._tokens, this.diagnostics);

  final List<Token> _tokens;
  final List<MathDiagnostic> diagnostics;

  int _index = 0;

  /// How many `|` fences are currently open within the innermost bracket,
  /// so that a closing bar is not mistaken for the start of another
  /// absolute value.
  int _openBars = 0;

  /// Where the intervals being read end: the brackets that close them,
  /// innermost last, which end what is read before them rather than open
  /// a bracket of their own.
  final List<int> _intervalEnds = <int>[];

  static const Set<String> _relations = relationOperators;
  static const Set<String> _additive = additiveOperators;
  static const Set<String> _multiplicative = multiplicativeOperators;

  /// Operators that may appear as a prefix.
  static const Set<String> _prefixes = <String>{
    '+',
    '-',
    r'\pm',
    r'\mp',
    r'\neg',
    r'\nabla',
  };

  Token get _current => _tokens[_index];

  Token _advance() => _tokens[_index++];

  bool _check(TokenType type) => _current.type == type;

  bool _matched(TokenType type) {
    if (!_check(type)) return false;
    _index++;
    return true;
  }

  /// Parses the whole token stream.
  MathNode parse() {
    if (_check(TokenType.end)) return const EmptyNode();

    // A stray token is reported and shown as it is, and parsing carries on
    // after it, so one slip does not hide the rest of the formula.
    final parts = <MathNode>[];
    while (true) {
      parts.add(_parseTopLevelList());
      if (_check(TokenType.end)) break;
      final stray = _advance();
      diagnostics.add(
        MathDiagnostic(stray.offset, 'Unexpected "${stray.lexeme}"'),
      );
      parts.add(SymbolNode(_asLatex(stray)));
      if (_check(TokenType.end)) break;
    }
    return parts.length == 1 ? parts.single : SequenceNode(parts);
  }

  /// Expressions separated by commas or semicolons, as in `x = 1, 2, 3`.
  MathNode _parseTopLevelList() {
    final items = <MathNode>[_parseExpression()];
    final separators = <String>[];
    for (
      var separator = _separator();
      separator != null;
      separator = _separator()
    ) {
      separators.add(separator);
      items.add(_check(TokenType.end) ? const EmptyNode() : _parseExpression());
    }
    return items.length == 1 ? items.single : ListNode(items, separators);
  }

  /// The comma or semicolon at hand, taken; or null if there is none.
  String? _separator() {
    if (_matched(TokenType.comma)) return ',';
    if (_matched(TokenType.semicolon)) return ';';
    return null;
  }

  /// A token's LaTeX, for showing it where it does not belong.
  static String _asLatex(Token token) => switch (token.lexeme) {
    '{' => r'\{',
    '}' => r'\}',
    ';' => ';',
    _ => token.latex.isNotEmpty ? token.latex : token.lexeme,
  };

  MathNode _parseExpression() => _parseRelation();

  MathNode _parseRelation() {
    var left = _parseAdditive();
    while (_isOperatorIn(_relations) || _atLoneBar) {
      final operator = _advance();
      final right = _parseAdditive();
      left = BinaryNode(
        operator.type == TokenType.bar ? r'\mid' : operator.latex,
        left,
        right,
      );
    }
    return left;
  }

  /// Whether the token at hand is a bar that neither closes an absolute
  /// value nor has another to close one it would open before its bracket
  /// or list item ends: the bar of a point, `S(1|2)`, of a condition,
  /// `P(A|B)`, or of what divides, `3|12`.
  bool get _atLoneBar {
    if (!_check(TokenType.bar) || _openBars > 0) return false;
    var depth = 0;
    for (var i = _index + 1; i < _tokens.length; i++) {
      switch (_tokens[i].type) {
        case TokenType.leftParen:
        case TokenType.leftBracket:
        case TokenType.leftBrace:
          depth++;
        case TokenType.rightParen:
        case TokenType.rightBracket:
        case TokenType.rightBrace:
          if (depth == 0) return true;
          depth--;
        case TokenType.bar when depth == 0:
          return false;
        case TokenType.comma || TokenType.semicolon when depth == 0:
          return true;
        case TokenType.end:
          return true;
        default:
      }
    }
    return true;
  }

  /// [parse] run within a bracket, where the bars of absolute values
  /// outside it are not to be closed: in `|P(A|B)|` the middle bar is
  /// not the last one's partner.
  T _withinBracket<T>(T Function() parse) {
    final outside = _openBars;
    _openBars = 0;
    try {
      return parse();
    } finally {
      _openBars = outside;
    }
  }

  MathNode _parseAdditive() {
    var left = _parseMultiplicative();
    while (_isOperatorIn(_additive)) {
      final operator = _advance();
      final right = _parseMultiplicative();
      left = BinaryNode(operator.latex, left, right);
    }
    return left;
  }

  /// A product: factors written side by side, joined by an operator such as
  /// `*`, or divided by `/`.
  ///
  /// Spacing groups it. Factors typed together, with no space between them,
  /// are one term, and a fraction bar takes the whole term on either side of
  /// it: `4pi^2/2` is four pi squared over two, `x*(a*b)/2` all of it over
  /// two, `d/dx` one over the whole `dx`. A space parts terms, and a bar takes
  /// only the term next to it: `4 pi^2/2` is four times pi squared over two,
  /// `x * (a*b)/2` only `(a*b)` over two, `2 1/2` two and a half, and
  /// `lim f(x)/g(x)` the limit of a fraction.
  MathNode _parseMultiplicative() {
    final factors = <MathNode>[_parseUnary()];
    final joins = <_Join>[];
    while (true) {
      if (_check(TokenType.slash)) {
        final bar = _advance();
        joins.add((operator: null, tight: !bar.spaced && !_current.spaced));
      } else if (_isOperatorIn(_multiplicative)) {
        final operator = _advance();
        joins.add((
          operator: operator.latex,
          tight: !operator.spaced && !_current.spaced,
        ));
      } else if (_startsPrimary(_current)) {
        // Juxtaposition is multiplication: `2x`, `sin x`, `a(b+c)`.
        joins.add((operator: '', tight: !_current.spaced));
      } else {
        break;
      }
      factors.add(_parseUnary());
    }
    if (joins.isEmpty) return factors.single;

    // The terms, each of the factors typed together, and how each is joined
    // to the one before it: a bar to the term next to it alone.
    final terms = <MathNode>[];
    final between = <_Join>[];
    var start = 0;
    for (var i = 0; i <= joins.length; i++) {
      if (i < joins.length && joins[i].tight) continue;
      final term = _term(
        factors.sublist(start, i + 1),
        joins.sublist(start, i),
      );
      if (start > 0 && between.last.operator == null) {
        between.removeLast();
        terms.add(_fraction(terms.removeLast(), term));
      } else {
        terms.add(term);
      }
      if (i < joins.length) between.add(joins[i]);
      start = i + 1;
    }
    return _product(terms, between);
  }

  /// [factors] typed together, joined by [joins]: each bar divides all that
  /// comes before it by all that comes after it, up to the next bar.
  MathNode _term(List<MathNode> factors, List<_Join> joins) {
    MathNode? result;
    var start = 0;
    for (var i = 0; i <= joins.length; i++) {
      if (i < joins.length && joins[i].operator != null) continue;
      final part = _product(
        factors.sublist(start, i + 1),
        joins.sublist(start, i),
      );
      result = result == null ? part : _fraction(result, part);
      start = i + 1;
    }
    return result!;
  }

  /// [factors] multiplied, side by side or by the operators of [joins].
  static MathNode _product(List<MathNode> factors, List<_Join> joins) {
    var left = factors.first;
    for (var i = 0; i < joins.length; i++) {
      final right = factors[i + 1];
      final operator = joins[i].operator!;
      if (operator.isNotEmpty) {
        left = BinaryNode(operator, left, right);
        continue;
      }
      left = SequenceNode(<MathNode>[
        if (left is SequenceNode) ...left.children else left,
        if (right is SequenceNode) ...right.children else right,
      ]);
    }
    return left;
  }

  /// [numerator] over [denominator].
  ///
  /// A fraction bar already groups both sides visually, so parentheses the
  /// user typed around either are dropped: `(a+b)/c` becomes a clean
  /// built-up fraction rather than one with redundant brackets. A sign before
  /// the numerator stands before the whole fraction, as it is written by
  /// hand: `-2/3` is minus two thirds; `(-2)/3` keeps it above the bar.
  static MathNode _fraction(MathNode numerator, MathNode denominator) {
    if (_leadingSign(numerator) case (final sign, final rest)) {
      return UnaryNode(sign, _fraction(rest, denominator));
    }
    return FractionNode(_unwrap(numerator), _unwrap(denominator));
  }

  /// The sign [node] begins with, and the rest of it, or null if it begins
  /// with none.
  static (String, MathNode)? _leadingSign(MathNode node) => switch (node) {
    UnaryNode(:final operatorLatex, :final operand)
        when _signs.contains(operatorLatex) =>
      (operatorLatex, operand),
    SequenceNode(:final children) when children.isNotEmpty =>
      switch (_leadingSign(children.first)) {
        (final sign, final rest) => (
          sign,
          SequenceNode(<MathNode>[rest, ...children.skip(1)]),
        ),
        null => null,
      },
    BinaryNode(:final operatorLatex, :final left, :final right) =>
      switch (_leadingSign(left)) {
        (final sign, final rest) => (
          sign,
          BinaryNode(operatorLatex, rest, right),
        ),
        null => null,
      },
    _ => null,
  };

  static const Set<String> _signs = <String>{'+', '-', r'\pm', r'\mp'};

  MathNode _parseUnary() {
    if (_check(TokenType.operator) && _prefixes.contains(_current.latex)) {
      final operator = _advance();
      return UnaryNode(operator.latex, _parseUnary());
    }
    var node = _parsePostfix();
    // Factorials: `n!`, `(n - k)!`.
    while (_check(TokenType.operator) && _current.latex == '!') {
      _advance();
      node = PostfixNode(node, '!');
    }
    return node;
  }

  /// Parses a primary and any subscripts or superscripts attached to it.
  MathNode _parsePostfix() => _parseScripts(_parsePrimary());

  /// [base] with the subscripts and superscripts typed after it.
  MathNode _parseScripts(MathNode base) {
    if (!_check(TokenType.caret) &&
        !_check(TokenType.underscore) &&
        !_check(TokenType.prime)) {
      return base;
    }

    MathNode? subscript;
    MathNode? superscript;
    while (_check(TokenType.caret) ||
        _check(TokenType.underscore) ||
        _check(TokenType.prime)) {
      if (_check(TokenType.prime)) {
        // f' and f'': primes are superscripts, as TeX reads them.
        final first = _current;
        var primes = 0;
        while (_matched(TokenType.prime)) {
          primes++;
        }
        if (superscript != null) {
          diagnostics.add(MathDiagnostic(first.offset, 'Repeated superscript'));
        }
        superscript = primes == 1
            ? const SymbolNode(r'\prime')
            : SequenceNode(<MathNode>[
                for (var i = 0; i < primes; i++) const SymbolNode(r'\prime'),
              ]);
        continue;
      }
      final marker = _advance();
      final raised = marker.type == TokenType.caret;
      final operand = _parseScriptOperand(
        subscript: subscript != null || !raised,
        superscript: superscript != null || raised,
        raised: raised,
      );
      if (raised) {
        if (superscript != null) {
          diagnostics.add(
            MathDiagnostic(marker.offset, 'Repeated superscript'),
          );
        }
        superscript = operand;
      } else {
        if (subscript != null) {
          diagnostics.add(MathDiagnostic(marker.offset, 'Repeated subscript'));
        }
        subscript = operand;
      }
    }
    return ScriptNode(base, subscript: subscript, superscript: superscript);
  }

  /// Parses what a `^` or `_` applies to: all that is typed straight after
  /// it, up to a space, an operator or a bracket — as a fraction bar takes
  /// what is typed together. `A_SiB` is A with `SiB` below, `x^2y` x to the
  /// `2y`, while `x^2 y` is x squared times y, `x_i+1` is x_i plus one and
  /// `f_n(x)` is f_n of x.
  ///
  /// A script of a kind the base has not got yet ends it, and is the
  /// base's: the `^n` of `sum_(i=1)^n` and `A_SiB^2`. One of a kind it has
  /// — its own [subscript] or [superscript] — is the last letter's: `x^2y^3`
  /// is x to the `2y³`.
  ///
  /// Raised, as a superscript, a number or a letter with a sign straight
  /// after it and nothing straight after that is a charge, as chemistry
  /// writes one: `O^2-`, `Fe^3+`, `M^n+`; `x^2-1` is x squared less one.
  MathNode _parseScriptOperand({
    required bool subscript,
    required bool superscript,
    bool raised = false,
  }) {
    if (_check(TokenType.end)) {
      diagnostics.add(MathDiagnostic(_current.offset, 'Missing script'));
      return const EmptyNode();
    }
    if (_check(TokenType.operator) && _prefixes.contains(_current.latex)) {
      final operator = _advance();
      // A sign with nothing straight after it is the script itself: the
      // charge of `H_3 O^+`, `e^-`.
      return _startsPrimary(_current) && !_current.spaced
          ? UnaryNode(
              operator.latex,
              _parseScriptOperand(
                subscript: subscript,
                superscript: superscript,
                raised: raised,
              ),
            )
          : SymbolNode(operator.latex);
    }
    MathNode atom() {
      final primary = _parsePrimary();
      final again =
          !_current.spaced &&
          (_check(TokenType.caret) && superscript ||
              _check(TokenType.underscore) && subscript);
      return again ? _parseScripts(primary) : primary;
    }

    final parts = <MathNode>[atom()];
    while (!_current.spaced &&
        _startsPrimary(_current) &&
        !_opensBracket(_current)) {
      parts.add(atom());
    }
    if (raised && _atCharge(parts)) {
      return SequenceNode(<MathNode>[
        parts.single,
        SymbolNode(_advance().latex),
      ]);
    }
    return parts.length == 1 ? _unwrap(parts.single) : SequenceNode(parts);
  }

  /// Whether the sign at hand ends the charge [parts] begin: a `+` or `-`
  /// typed straight after a number or a letter, with nothing typed straight
  /// after it that it would take — the end, a space, a closing bracket or a
  /// separator.
  bool _atCharge(List<MathNode> parts) {
    final charged = switch (parts) {
      [NumberNode()] || [VariableNode(name: String(length: 1))] => true,
      _ => false,
    };
    if (!charged ||
        _current.spaced ||
        !_check(TokenType.operator) ||
        (_current.latex != '+' && _current.latex != '-')) {
      return false;
    }
    final next = _tokens[_index + 1];
    return next.spaced ||
        switch (next.type) {
          TokenType.end ||
          TokenType.rightParen ||
          TokenType.rightBracket ||
          TokenType.rightBrace ||
          TokenType.comma ||
          TokenType.semicolon => true,
          _ => false,
        };
  }

  /// Whether [token] opens a bracket, which ends a script: `f_n(x)`.
  static bool _opensBracket(Token token) => switch (token.type) {
    TokenType.leftParen ||
    TokenType.leftBracket ||
    TokenType.leftBrace ||
    TokenType.bar => true,
    _ => false,
  };

  MathNode _parsePrimary() {
    final token = _current;
    // An end of an interval left out, `[a;[`: the bracket closes it.
    if (_atIntervalEnd(token)) {
      diagnostics.add(MathDiagnostic(token.offset, 'Expression is incomplete'));
      return const EmptyNode();
    }
    // An interval open at an end, its bracket turned outward there, as it
    // is written in the Netherlands and France: `[a;+infty[`, `]0;1]`.
    if (token.type == TokenType.leftBracket ||
        token.type == TokenType.rightBracket) {
      final end = _intervalEnd();
      if (end != null &&
          (token.type == TokenType.rightBracket ||
              _tokens[end].type == TokenType.leftBracket)) {
        return _parseInterval(end);
      }
    }

    switch (token.type) {
      case TokenType.number:
        _advance();
        return NumberNode(token.lexeme);

      case TokenType.variable:
        _advance();
        return VariableNode(token.lexeme);

      case TokenType.text:
        _advance();
        return TextNode(token.lexeme);

      case TokenType.symbol:
        return _parseSymbol();

      case TokenType.leftParen:
        _advance();
        final child = _parseListUntil(TokenType.rightParen, ')');
        return FencedNode('(', ')', child, isRoundParen: true);

      case TokenType.leftBracket:
        _advance();
        final child = _parseListUntil(TokenType.rightBracket, ']');
        return FencedNode('[', ']', child);

      case TokenType.leftBrace:
        _advance();
        // `{}` is an empty group, something to hang a script on: `{}^14 C`.
        if (_matched(TokenType.rightBrace)) {
          return const GroupNode(SequenceNode(<MathNode>[]));
        }
        final child = _parseListUntil(TokenType.rightBrace, '}');
        return GroupNode(child);

      case TokenType.command:
        _advance();
        return _parseCommand(token);

      case TokenType.raw:
        _advance();
        return RawNode(token.latex);

      case TokenType.unit:
        _advance();
        return UnitNode(token.lexeme);

      case TokenType.bar:
        _advance();
        _openBars++;
        final child = _parseExpression();
        _openBars--;
        if (!_matched(TokenType.bar)) {
          diagnostics.add(MathDiagnostic(token.offset, 'Unclosed "|"'));
        }
        return FencedNode(r'\lvert', r'\rvert', child);

      case TokenType.operator:
        // A relation or operator with nothing before it, such as a formula
        // beginning with `=`. Emit it so the preview shows what was typed.
        _advance();
        return SymbolNode(token.latex);

      default:
        diagnostics.add(
          MathDiagnostic(
            token.offset,
            token.type == TokenType.end
                ? 'Expression is incomplete'
                : 'Unexpected "${token.lexeme}"',
          ),
        );
        if (token.type != TokenType.end) _advance();
        return const EmptyNode();
    }
  }

  MathNode _parseSymbol() {
    final token = _advance();
    final symbol = token.symbol!;

    switch (symbol.role) {
      case SymbolRole.atom:
        return SymbolNode(symbol.latex);

      case SymbolRole.function:
      case SymbolRole.bigOperator:
        // `sin(x)` is one factor; `sin x` and `sin^2 x` fall back to
        // juxtaposition, which reads the same once typeset.
        if (_check(TokenType.leftParen)) {
          _advance();
          final argument = _parseListUntil(TokenType.rightParen, ')');
          return ApplicationNode(
            SymbolNode(symbol.latex),
            FencedNode('(', ')', argument, isRoundParen: true),
          );
        }
        return SymbolNode(symbol.latex);

      case SymbolRole.unaryConstruct:
        // `vec(1, 2, 3)` is a column vector; `vec(v)` and `vec v` an arrow.
        if (symbol.latex == r'\vec' && _check(TokenType.leftParen)) {
          final grid = _parseGrid(token);
          final cells = <MathNode>[for (final row in grid) ...row];
          if (cells.length > 1) {
            return MatrixNode('pmatrix', <List<MathNode>>[
              for (final cell in cells) <MathNode>[cell],
            ]);
          }
          return AccentNode(symbol.latex, _unwrap(cells.single));
        }
        final argument = _parseConstructArgument(token);
        return symbol.latex == r'\sqrt'
            ? RootNode(argument)
            : AccentNode(symbol.latex, argument);

      case SymbolRole.binaryConstruct:
        final arguments = _parseArgumentPair(token);
        // `root(3, x)` and `nthroot(3, x)` place the degree in the radical.
        return symbol.latex == r'\sqrt'
            ? RootNode(arguments[1], index: arguments[0])
            : BinaryConstructNode(symbol.latex, arguments[0], arguments[1]);

      case SymbolRole.fenceConstruct:
        final delimiters = fenceConstructs[token.lexeme]!;
        final argument = _parseConstructArgument(token);
        return FencedNode(delimiters[0], delimiters[1], argument);

      case SymbolRole.matrixConstruct:
        return MatrixNode(symbol.latex, _parseGrid(token));

      case SymbolRole.braketConstruct:
        final kind = BraketKind.values.byName(token.lexeme);
        if (kind != BraketKind.braket) {
          return BraketNode(kind, <MathNode>[_parseConstructArgument(token)]);
        }
        // `braket(A)` is ⟨A⟩, `braket(phi, psi)` is ⟨φ|ψ⟩ and
        // `braket(phi, A, psi)` is ⟨φ|A|ψ⟩.
        final argument = _parseConstructArgument(token);
        final parts = argument is ListNode
            ? <MathNode>[for (final item in argument.items) _unwrap(item)]
            : <MathNode>[argument];
        if (parts.length > 3) {
          diagnostics.add(
            MathDiagnostic(
              token.offset,
              '"braket" takes one to three parts: braket(phi, A, psi)',
            ),
          );
        }
        return BraketNode(kind, parts);

      case SymbolRole.highlightConstruct:
        // `highlight(x)` in the highlighter's yellow, `highlight(#A8E6B0, x)`
        // in another colour.
        if (!_matched(TokenType.leftParen)) {
          return HighlightNode(_parseConstructArgument(token));
        }
        var color = HighlightNode.defaultColor;
        if (_check(TokenType.color)) {
          color = int.parse(_advance().lexeme.substring(1), radix: 16);
          if (!_matched(TokenType.comma)) {
            diagnostics.add(
              MathDiagnostic(_current.offset, 'Missing "," after the colour'),
            );
          }
        }
        return HighlightNode(
          _parseListUntil(TokenType.rightParen, ')'),
          color: color,
        );
    }
  }

  /// [command], read already, with the groups typed against it, in braces
  /// or brackets, read as its arguments.
  MathNode _parseCommand(Token command) {
    final arguments = <({bool optional, MathNode content})>[];
    var end = command.offset + command.lexeme.length;
    while (_current.offset == end &&
        (_check(TokenType.leftBrace) || _check(TokenType.leftBracket))) {
      final optional = _check(TokenType.leftBracket);
      _advance();
      final MathNode content;
      if (optional) {
        content = _parseListUntil(TokenType.rightBracket, ']');
      } else if (_matched(TokenType.rightBrace)) {
        content = const SequenceNode(<MathNode>[]);
      } else {
        content = _parseListUntil(TokenType.rightBrace, '}');
      }
      arguments.add((optional: optional, content: content));
      final closer = _tokens[_index - 1];
      end = closer.offset + closer.lexeme.length;
    }
    return arguments.isEmpty
        ? SymbolNode(command.latex)
        : CommandNode(command.latex, arguments);
  }

  /// Reads the `(a, b; c, d)` of a grid: cells separated by commas, rows by
  /// semicolons.
  List<List<MathNode>> _parseGrid(Token construct) =>
      _withinBracket(() => _parseGridRows(construct));

  List<List<MathNode>> _parseGridRows(Token construct) {
    if (!_matched(TokenType.leftParen)) {
      diagnostics.add(
        MathDiagnostic(
          construct.offset,
          '"${construct.lexeme}" needs its rows in brackets: '
          '${construct.lexeme}(a, b; c, d)',
        ),
      );
      return <List<MathNode>>[
        <MathNode>[const EmptyNode()],
      ];
    }
    final rows = <List<MathNode>>[<MathNode>[]];
    while (true) {
      rows.last.add(
        _check(TokenType.comma) ||
                _check(TokenType.semicolon) ||
                _check(TokenType.rightParen)
            ? const EmptyNode()
            : _unwrap(_parseExpression()),
      );
      if (_matched(TokenType.comma)) continue;
      if (_matched(TokenType.semicolon)) {
        rows.add(<MathNode>[]);
        continue;
      }
      if (!_matched(TokenType.rightParen)) {
        diagnostics.add(MathDiagnostic(_current.offset, 'Missing ")"'));
      }
      return rows;
    }
  }

  /// Reads the single argument of a construct, with or without brackets.
  ///
  /// Both `sqrt(x)` and `sqrt x` are accepted because both are natural to type.
  MathNode _parseConstructArgument(Token construct) {
    if (_matched(TokenType.leftParen)) {
      final child = _parseListUntil(TokenType.rightParen, ')');
      return child;
    }
    // LaTeX's own form, `\overbrace{a+b}^n`: the group is the argument, and
    // a script after it the construct's.
    if (_check(TokenType.leftBrace)) return _unwrap(_parsePrimary());
    if (_check(TokenType.end)) {
      diagnostics.add(
        MathDiagnostic(
          construct.offset,
          '"${construct.lexeme}" needs an argument',
        ),
      );
      return const EmptyNode();
    }
    // One symbol, and the scripts after it are the construct's: `veca_2^3`
    // is `vec(a)_2^3`, as `\vec a_2^3` is in LaTeX.
    return _unwrap(_parsePrimary());
  }

  /// Reads the `(a, b)` arguments of a two-argument construct.
  List<MathNode> _parseArgumentPair(Token construct) =>
      _withinBracket(() => _parseArguments(construct));

  List<MathNode> _parseArguments(Token construct) {
    // LaTeX's own form, `\frac{a}{b}`, is read too.
    if (_check(TokenType.leftBrace)) {
      final first = _parsePrimary();
      final second = _check(TokenType.leftBrace)
          ? _parsePrimary()
          : const EmptyNode();
      return <MathNode>[_unwrap(first), _unwrap(second)];
    }
    if (!_matched(TokenType.leftParen)) {
      diagnostics.add(
        MathDiagnostic(
          construct.offset,
          '"${construct.lexeme}" needs two arguments in brackets',
        ),
      );
      return <MathNode>[const EmptyNode(), const EmptyNode()];
    }

    final first = _parseExpression();
    if (!_matched(TokenType.comma)) {
      diagnostics.add(
        MathDiagnostic(
          _current.offset,
          '"${construct.lexeme}" needs a second argument',
        ),
      );
      _matched(TokenType.rightParen);
      return <MathNode>[first, const EmptyNode()];
    }

    final second = _parseExpression();
    if (!_matched(TokenType.rightParen)) {
      diagnostics.add(MathDiagnostic(_current.offset, 'Missing ")"'));
    }
    return <MathNode>[_unwrap(first), _unwrap(second)];
  }

  /// Parses expressions separated by commas or semicolons up to [closer]:
  /// the coordinates of a point, `S(1;2)`, among them.
  MathNode _parseListUntil(TokenType closer, String symbol) =>
      _withinBracket(() {
        if (_matched(closer)) return const EmptyNode();

        final items = <MathNode>[_parseExpression()];
        final separators = <String>[];
        for (
          var separator = _separator();
          separator != null;
          separator = _separator()
        ) {
          separators.add(separator);
          items.add(_parseExpression());
        }
        if (!_matched(closer)) {
          diagnostics.add(MathDiagnostic(_current.offset, 'Missing "$symbol"'));
        }
        return items.length == 1 ? items.single : ListNode(items, separators);
      });

  /// Where the interval the bracket at hand opens ends, if it opens one:
  /// the bracket, turned either way, that follows its two ends and the `;`
  /// or `,` between them — `[a;b[`, `]a;b]`, `]a;b[` — outside any round
  /// bracket or brace; null if there is none, or a bracket comes before
  /// the separator, or more than one separator: a list, `[1;2;3]`.
  int? _intervalEnd() {
    var depth = 0;
    var separators = 0;
    for (var i = _index + 1; i < _tokens.length; i++) {
      switch (_tokens[i].type) {
        case TokenType.leftParen || TokenType.leftBrace:
          depth++;
        case TokenType.rightParen || TokenType.rightBrace:
          if (depth == 0) return null;
          depth--;
        case TokenType.comma || TokenType.semicolon when depth == 0:
          if (++separators > 1) return null;
        case TokenType.leftBracket || TokenType.rightBracket when depth == 0:
          return separators == 1 ? i : null;
        case TokenType.end:
          return null;
        default:
      }
    }
    return null;
  }

  /// Whether [token] closes the interval being read.
  bool _atIntervalEnd(Token token) =>
      _intervalEnds.isNotEmpty && identical(token, _tokens[_intervalEnds.last]);

  /// The interval from the bracket at hand to the one at [end]: its two
  /// ends, each brackets as it was typed.
  MathNode _parseInterval(int end) {
    final open = _advance();
    _intervalEnds.add(end);
    try {
      return _withinBracket(() {
        // What does not belong in it, before the separator or the end, is
        // said and left out.
        void skipTo(bool Function() there) {
          while (_index < end && !there()) {
            final stray = _advance();
            diagnostics.add(
              MathDiagnostic(stray.offset, 'Unexpected "${stray.lexeme}"'),
            );
          }
        }

        final from = _parseExpression();
        skipTo(() => _check(TokenType.comma) || _check(TokenType.semicolon));
        final separator = _separator() ?? ';';
        final to = _parseExpression();
        skipTo(() => false);
        final close = _advance();
        return FencedNode(
          open.lexeme,
          close.lexeme,
          ListNode(<MathNode>[from, to], <String>[separator]),
        );
      });
    } finally {
      _intervalEnds.removeLast();
    }
  }

  /// Drops a redundant layer of round brackets or braces.
  static MathNode _unwrap(MathNode node) => switch (node) {
    FencedNode(isRoundParen: true, child: final child) => child,
    GroupNode(child: final child) => child,
    _ => node,
  };

  bool _isOperatorIn(Set<String> operators) {
    final token = _current;
    if (token.type == TokenType.operator) {
      return operators.contains(token.latex);
    }
    // Words like `in`, `to` and `cup` are operators spelled out.
    if (token.type == TokenType.symbol &&
        token.symbol!.role == SymbolRole.atom) {
      return operators.contains(token.latex);
    }
    return false;
  }

  /// Whether [token] could begin a new operand, which is what makes implicit
  /// multiplication work.
  bool _startsPrimary(Token token) {
    if (_atIntervalEnd(token)) return false;
    switch (token.type) {
      case TokenType.number:
      case TokenType.variable:
      case TokenType.text:
      case TokenType.leftParen:
      case TokenType.leftBracket:
      case TokenType.leftBrace:
      case TokenType.command:
      case TokenType.raw:
      case TokenType.unit:
        return true;
      case TokenType.bar:
        // Inside `|...|` the next bar closes the fence rather than opening
        // one, and a bar with none to close it divides rather than opens.
        return _openBars == 0 && !(identical(token, _current) && _atLoneBar);
      case TokenType.symbol:
        // Operator words are not operands, so `a cup b` stays an operation.
        return !_isOperatorIn(_relations) &&
            !_isOperatorIn(_additive) &&
            !_isOperatorIn(_multiplicative);
      default:
        return false;
    }
  }
}

/// How a factor is joined to the one before it: by the LaTeX of an
/// [operator], by nothing — side by side — when it is empty, or by a
/// fraction bar when it is null; and whether it is [tight], typed with no
/// space either side.
typedef _Join = ({String? operator, bool tight});
