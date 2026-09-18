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

  /// How many `|` fences are currently open, so that a closing bar is not
  /// mistaken for the start of another absolute value.
  int _openBars = 0;

  /// Operators that separate the two sides of a statement.
  static const Set<String> _relations = <String>{
    '=',
    '<',
    '>',
    r'\leq',
    r'\geq',
    r'\neq',
    r'\approx',
    r'\equiv',
    r'\simeq',
    r'\cong',
    r'\sim',
    r'\propto',
    r'\to',
    r'\mapsto',
    r'\iff',
    r'\implies',
    r'\impliedby',
    r'\Rightarrow',
    r'\leftarrow',
    r'\in',
    r'\notin',
    r'\ni',
    r'\subset',
    r'\subseteq',
    r'\supset',
    r'\supseteq',
    r'\ll',
    r'\gg',
    r'\perp',
    r'\parallel',
    r'\therefore',
    r'\because',
  };

  /// Operators at addition's precedence level.
  static const Set<String> _additive = <String>{
    '+',
    '-',
    r'\pm',
    r'\mp',
    r'\cup',
    r'\cap',
    r'\setminus',
    r'\oplus',
    r'\wedge',
    r'\vee',
  };

  /// Operators at multiplication's precedence level.
  static const Set<String> _multiplicative = <String>{
    r'\cdot',
    r'\times',
    r'\div',
    r'\otimes',
    r'\circ',
    r'\star',
    r'\bullet',
    '.',
  };

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

    final node = _parseExpression();
    if (!_check(TokenType.end)) {
      diagnostics.add(
        MathDiagnostic(_current.offset, 'Unexpected "${_current.lexeme}"'),
      );
    }
    return node;
  }

  MathNode _parseExpression() => _parseRelation();

  MathNode _parseRelation() {
    var left = _parseAdditive();
    while (_isOperatorIn(_relations)) {
      final operator = _advance();
      final right = _parseAdditive();
      left = BinaryNode(operator.latex, left, right);
    }
    return left;
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

  MathNode _parseMultiplicative() {
    var left = _parseUnary();
    while (true) {
      if (_check(TokenType.slash)) {
        _advance();
        final right = _parseUnary();
        // A fraction bar already groups both sides visually, so parentheses the
        // user typed around either are dropped: `(a+b)/c` becomes a clean
        // built-up fraction rather than one with redundant brackets.
        //
        // Division binds only the factor immediately before it, so `2 1/2`
        // reads as two and a half and `lim f(x)/g(x)` puts the fraction inside
        // the limit rather than the limit inside the fraction.
        if (left is SequenceNode && left.children.length > 1) {
          final factors = List<MathNode>.of(left.children);
          final numerator = factors.removeLast();
          factors.add(FractionNode(_unwrap(numerator), _unwrap(right)));
          left = SequenceNode(factors);
        } else {
          left = FractionNode(_unwrap(left), _unwrap(right));
        }
        continue;
      }
      if (_isOperatorIn(_multiplicative)) {
        final operator = _advance();
        left = BinaryNode(operator.latex, left, _parseUnary());
        continue;
      }
      if (_startsPrimary(_current)) {
        // Juxtaposition is multiplication: `2x`, `sin x`, `a(b+c)`.
        final right = _parseUnary();
        left = left is SequenceNode
            ? SequenceNode(<MathNode>[...left.children, right])
            : SequenceNode(<MathNode>[left, right]);
        continue;
      }
      return left;
    }
  }

  MathNode _parseUnary() {
    if (_check(TokenType.operator) && _prefixes.contains(_current.latex)) {
      final operator = _advance();
      return UnaryNode(operator.latex, _parseUnary());
    }
    return _parsePostfix();
  }

  /// Parses a primary and any subscripts or superscripts attached to it.
  MathNode _parsePostfix() {
    final base = _parsePrimary();
    if (!_check(TokenType.caret) && !_check(TokenType.underscore)) {
      return base;
    }

    MathNode? subscript;
    MathNode? superscript;
    while (_check(TokenType.caret) || _check(TokenType.underscore)) {
      final marker = _advance();
      final operand = _parseScriptOperand();
      if (marker.type == TokenType.caret) {
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

  /// Parses what a `^` or `_` applies to: one atom, not a whole product.
  ///
  /// This is why `x^2y` is `x²·y` rather than `x^(2y)`, matching how the same
  /// input behaves in OneNote and in TeX.
  MathNode _parseScriptOperand() {
    if (_check(TokenType.end)) {
      diagnostics.add(MathDiagnostic(_current.offset, 'Missing script'));
      return const EmptyNode();
    }
    if (_check(TokenType.operator) && _prefixes.contains(_current.latex)) {
      final operator = _advance();
      return UnaryNode(operator.latex, _parseScriptOperand());
    }
    // Deliberately a primary rather than a full postfix: consuming further
    // scripts here would swallow the `^n` of `sum_(i=1)^n` into the subscript.
    return _unwrap(_parsePrimary());
  }

  MathNode _parsePrimary() {
    final token = _current;

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
        final child = _parseListUntil(TokenType.rightBrace, '}');
        return GroupNode(child);

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
    if (_check(TokenType.end)) {
      diagnostics.add(
        MathDiagnostic(
          construct.offset,
          '"${construct.lexeme}" needs an argument',
        ),
      );
      return const EmptyNode();
    }
    return _unwrap(_parsePostfix());
  }

  /// Reads the `(a, b)` arguments of a two-argument construct.
  List<MathNode> _parseArgumentPair(Token construct) {
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

  /// Parses comma-separated expressions up to [closer].
  MathNode _parseListUntil(TokenType closer, String symbol) {
    if (_matched(closer)) return const EmptyNode();

    final items = <MathNode>[_parseExpression()];
    while (_matched(TokenType.comma)) {
      items.add(_parseExpression());
    }
    if (!_matched(closer)) {
      diagnostics.add(MathDiagnostic(_current.offset, 'Missing "$symbol"'));
    }
    return items.length == 1 ? items.single : ListNode(items);
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
    switch (token.type) {
      case TokenType.number:
      case TokenType.variable:
      case TokenType.text:
      case TokenType.leftParen:
      case TokenType.leftBracket:
      case TokenType.leftBrace:
        return true;
      case TokenType.bar:
        // Inside `|...|` the next bar closes the fence rather than opening one.
        return _openBars == 0;
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
