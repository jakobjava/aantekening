/// Reads LaTeX into the syntax tree the linear syntax uses, so a formula
/// stored as LaTeX can be shown and edited in Simple syntax.
library;

import 'ast.dart';

/// Reads the subset of LaTeX that notes use — fractions, roots, scripts,
/// accents, fences, matrices, cases — into [MathNode]s.
///
/// Like the linear parser it never throws. Anything it does not understand is
/// kept as it is, as a [SymbolNode] for an unknown command or a [RawNode] for
/// an unknown environment, so reading and writing a formula back loses
/// nothing that renders.
class LatexReader {
  LatexReader(this.source);

  final String source;

  int _i = 0;

  /// The environments read as grids of cells.
  static const Set<String> gridEnvironments = <String>{
    'matrix',
    'pmatrix',
    'bmatrix',
    'Bmatrix',
    'vmatrix',
    'Vmatrix',
    'smallmatrix',
    'cases',
  };

  /// Commands that decorate their one argument.
  static const Set<String> _accents = <String>{
    'vec',
    'hat',
    'bar',
    'dot',
    'ddot',
    'tilde',
    'widehat',
    'widetilde',
    'overline',
    'underline',
    'overbrace',
    'underbrace',
    'overrightarrow',
    'overleftarrow',
    'boldsymbol',
    'mathbb',
    'mathcal',
    'mathfrak',
    'mathbf',
    'mathrm',
    'mathit',
    'mathsf',
    'mathtt',
    'bm',
  };

  /// Opening fence commands and the commands that close them.
  static const Map<String, String> _fences = <String, String>{
    r'\lvert': r'\rvert',
    r'\lVert': r'\rVert',
    r'\lfloor': r'\rfloor',
    r'\lceil': r'\rceil',
    r'\langle': r'\rangle',
    r'\{': r'\}',
    r'\|': r'\|',
  };

  /// Reads the whole source.
  MathNode read() {
    final items = <MathNode>[];
    while (_i < source.length) {
      items.addAll(_sequence(const _Stops()));
      // A closing brace or fence with nothing open is skipped.
      if (_i < source.length) _i++;
    }
    return _join(items);
  }

  static MathNode _join(List<MathNode> items) => switch (items.length) {
    0 => const SequenceNode(<MathNode>[]),
    1 => items.single,
    _ => SequenceNode(items),
  };

  bool get _atEnd => _i >= source.length;

  String get _char => source[_i];

  bool _startsWith(String text) => source.startsWith(text, _i);

  void _skipSpace() {
    while (!_atEnd && (_char == ' ' || _char == '\n' || _char == '\t')) {
      _i++;
    }
  }

  /// Reads items up to the end of the source or one of [stops].
  List<MathNode> _sequence(_Stops stops) {
    final items = <MathNode>[];
    while (true) {
      _skipSpace();
      if (_atEnd || _stopsHere(stops)) return items;
      final atom = _atom(stops);
      if (atom != null) items.add(_scripts(atom));
    }
  }

  bool _stopsHere(_Stops stops) {
    if (_char == '}') return true;
    final closer = stops.closer;
    if (closer != null && _startsWith(closer)) return true;
    if (stops.grid &&
        (_char == '&' || _startsWith(r'\\') || _startsWith(r'\end'))) {
      return true;
    }
    if (stops.right && _startsWith(r'\right')) return true;
    return false;
  }

  /// Attaches any subscript, superscript or primes following [base].
  MathNode _scripts(MathNode base) {
    MathNode? subscript;
    MathNode? superscript;
    while (true) {
      _skipSpace();
      if (_atEnd) break;
      if (_char == '_') {
        _i++;
        subscript = _argument();
      } else if (_char == '^') {
        _i++;
        superscript = _argument();
      } else if (_char == "'") {
        var primes = 0;
        while (!_atEnd && _char == "'") {
          primes++;
          _i++;
        }
        superscript = primes == 1
            ? const SymbolNode(r'\prime')
            : SequenceNode(<MathNode>[
                for (var i = 0; i < primes; i++) const SymbolNode(r'\prime'),
              ]);
      } else {
        break;
      }
    }
    if (subscript == null && superscript == null) return base;
    return ScriptNode(base, subscript: subscript, superscript: superscript);
  }

  /// One item, or null for something that stands for nothing, such as a
  /// spacing tilde.
  MathNode? _atom(_Stops stops) {
    final char = _char;
    if (_isDigit(char) ||
        (char == '.' && _i + 1 < source.length && _isDigit(source[_i + 1]))) {
      return _number();
    }
    if (_isLetter(char)) {
      _i++;
      return VariableNode(char);
    }
    switch (char) {
      case '{':
        _i++;
        final items = _sequence(const _Stops());
        if (!_atEnd && _char == '}') _i++;
        return GroupNode(_join(items));
      case '\\':
        return _command(stops);
      case '(':
        return _matched('(', ')', '(', ')', stops, round: true);
      case '[':
        return _matched('[', ']', '[', ']', stops);
      case '|':
        return _matched('|', '|', r'\lvert', r'\rvert', stops);
      case '^':
      case '_':
      case "'":
        // A script with nothing before it hangs on an empty group.
        return const GroupNode(SequenceNode(<MathNode>[]));
      case '~':
        _i++;
        return null;
      case '&':
        _i++;
        return const RawNode('&');
    }
    final code = char.codeUnitAt(0);
    final isHighSurrogate = code >= 0xD800 && code <= 0xDBFF;
    final length = isHighSurrogate && _i + 1 < source.length ? 2 : 1;
    final text = source.substring(_i, _i + length);
    _i += length;
    return code > 0x7F ? VariableNode(text) : SymbolNode(text);
  }

  NumberNode _number() {
    final start = _i;
    while (!_atEnd && _isDigit(_char)) {
      _i++;
    }
    if (!_atEnd &&
        _char == '.' &&
        _i + 1 < source.length &&
        _isDigit(source[_i + 1])) {
      _i++;
      while (!_atEnd && _isDigit(_char)) {
        _i++;
      }
    }
    return NumberNode(source.substring(start, _i));
  }

  /// A fence opened by [open] and closed by [close], or [open] alone if it is
  /// never closed.
  MathNode _matched(
    String open,
    String close,
    String left,
    String right,
    _Stops stops, {
    bool round = false,
  }) {
    final start = _i;
    _i += open.length;
    final items = _sequence(stops.inside(close));
    if (!_atEnd && _startsWith(close)) {
      _i += close.length;
      return FencedNode(left, right, _join(items), isRoundParen: round);
    }
    _i = start + open.length;
    return SymbolNode(open.isEmpty ? left : open);
  }

  /// A command's argument: a braced group, or else a single token, as TeX
  /// takes it (`\frac12`, `x^2`).
  MathNode _argument() {
    _skipSpace();
    if (_atEnd) return const EmptyNode();
    if (_char == '{') {
      _i++;
      final items = _sequence(const _Stops());
      if (!_atEnd && _char == '}') _i++;
      return _join(items);
    }
    if (_char == '\\') return _command(const _Stops()) ?? const EmptyNode();
    final char = _char;
    _i++;
    if (_isDigit(char)) return NumberNode(char);
    if (_isLetter(char)) return VariableNode(char);
    return SymbolNode(char);
  }

  /// The text of a braced argument, taken as it is: `\text{if }`.
  String _bracedText() {
    _skipSpace();
    if (_atEnd || _char != '{') return '';
    final start = ++_i;
    var depth = 1;
    while (!_atEnd) {
      if (_char == '{') depth++;
      if (_char == '}') {
        depth--;
        if (depth == 0) break;
      }
      _i++;
    }
    final text = source.substring(start, _i);
    if (!_atEnd) _i++;
    return text;
  }

  String _commandName() {
    // At the backslash.
    _i++;
    if (_atEnd) return '';
    if (!_isLetter(_char)) {
      return source[_i++];
    }
    final start = _i;
    while (!_atEnd && _isLetter(_char)) {
      _i++;
    }
    return source.substring(start, _i);
  }

  /// The delimiter after `\left` or `\right`.
  String _delimiter() {
    _skipSpace();
    if (_atEnd) return '.';
    if (_char == '\\') return '\\${_commandName()}';
    return source[_i++];
  }

  MathNode? _command(_Stops stops) {
    final start = _i;
    final name = _commandName();
    final command = '\\$name';
    switch (name) {
      case '':
        return const RawNode(r'\');
      case 'frac':
      case 'dfrac':
      case 'tfrac':
      case 'cfrac':
        return FractionNode(_argument(), _argument());
      case 'sqrt':
        _skipSpace();
        MathNode? index;
        if (!_atEnd && _char == '[') {
          _i++;
          index = _join(_sequence(const _Stops(closer: ']')));
          if (!_atEnd && _char == ']') _i++;
        }
        return RootNode(_argument(), index: index);
      case 'binom':
      case 'dbinom':
      case 'tbinom':
        return BinaryConstructNode(r'\binom', _argument(), _argument());
      case 'stackrel':
      case 'overset':
      case 'underset':
        return BinaryConstructNode(command, _argument(), _argument());
      case 'text':
      case 'textrm':
      case 'textnormal':
      case 'mbox':
        return TextNode(_bracedText());
      case 'operatorname':
        return SymbolNode('\\operatorname{${_bracedText()}}');
      case 'left':
        final left = _delimiter();
        final items = _sequence(stops.inRight());
        var right = '.';
        if (_startsWith(r'\right')) {
          _i += r'\right'.length;
          right = _delimiter();
        }
        return FencedNode(
          left,
          right,
          _join(items),
          isRoundParen: left == '(' && right == ')',
        );
      case 'right':
        _delimiter();
        return null;
      case 'begin':
        return _environment(start);
      case 'end':
        _bracedText();
        return null;
      case '\\':
        return const RawNode(r'\\');
    }
    if (_accents.contains(name)) return AccentNode(command, _argument());
    final close = _fences[command];
    if (close != null) {
      return _matched(
        '',
        close,
        command == r'\|' ? r'\lVert' : command,
        command == r'\|' ? r'\rVert' : close,
        stops,
      );
    }
    return SymbolNode(command);
  }

  /// `\begin{...}` to its `\end`: a grid of cells for a matrix or cases, the
  /// LaTeX as it is for anything else.
  MathNode _environment(int start) {
    final environment = _bracedText();
    if (!gridEnvironments.contains(environment)) {
      final end = '\\end{$environment}';
      final at = source.indexOf(end, _i);
      _i = at < 0 ? source.length : at + end.length;
      return RawNode(source.substring(start, _i));
    }
    final rows = <List<MathNode>>[<MathNode>[]];
    while (true) {
      rows.last.add(_join(_sequence(const _Stops(grid: true))));
      if (_atEnd) break;
      if (_char == '&') {
        _i++;
        continue;
      }
      if (_startsWith(r'\\')) {
        _i += 2;
        rows.add(<MathNode>[]);
        continue;
      }
      if (_startsWith(r'\end')) {
        _i += r'\end'.length;
        _bracedText();
        break;
      }
      // A stray closing brace inside a cell.
      _i++;
    }
    // A trailing `\\` leaves an empty last row.
    if (rows.length > 1 && _isBlankRow(rows.last)) rows.removeLast();
    return MatrixNode(environment, rows);
  }

  static bool _isBlankRow(List<MathNode> row) =>
      row.every((cell) => cell is SequenceNode && cell.children.isEmpty);

  static bool _isDigit(String char) =>
      char.codeUnitAt(0) >= 0x30 && char.codeUnitAt(0) <= 0x39;

  static bool _isLetter(String char) {
    final code = char.codeUnitAt(0);
    return (code >= 0x41 && code <= 0x5A) || (code >= 0x61 && code <= 0x7A);
  }
}

/// Where a sequence being read ends, besides the end of the source and a
/// closing brace.
class _Stops {
  const _Stops({this.closer, this.grid = false, this.right = false});

  /// The text closing a fence being read, such as `)` or `\rvert`.
  final String? closer;

  /// Inside a grid, where `&`, `\\` and `\end` end a cell.
  final bool grid;

  /// Inside `\left`, where `\right` ends it.
  final bool right;

  _Stops inside(String closer) =>
      _Stops(closer: closer, grid: grid, right: right);

  _Stops inRight() => _Stops(grid: grid, right: true);
}
