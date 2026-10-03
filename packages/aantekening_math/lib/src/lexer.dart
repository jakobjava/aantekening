/// Turns linear math input into a token stream.
library;

import 'symbols.dart';

/// The kind of a lexed token.
enum TokenType {
  number,
  variable,
  symbol,
  operator,
  slash,
  caret,
  underscore,
  comma,
  leftParen,
  rightParen,
  leftBracket,
  rightBracket,
  leftBrace,
  rightBrace,
  bar,
  text,

  /// `;`, which separates the rows of a matrix.
  semicolon,

  /// `'`, a prime: `f'(x)`.
  prime,

  /// A LaTeX command typed as it is, such as `\mathcal`.
  command,

  /// LaTeX quoted in backticks, passed through untouched.
  raw,

  /// A colour, `#` and six hexadecimal digits: `#A8E6B0`.
  color,
  end,
}

/// One token, with the offset it started at so diagnostics can point into the
/// user's own input.
class Token {
  const Token({
    required this.type,
    required this.lexeme,
    required this.offset,
    this.latex = '',
    this.symbol,
  });

  final TokenType type;
  final String lexeme;
  final int offset;

  /// The LaTeX this token stands for, for operators and known symbols.
  final String latex;

  /// The table entry behind a [TokenType.symbol], which tells the parser
  /// whether it takes arguments.
  final MathSymbol? symbol;

  @override
  String toString() => '${type.name}("$lexeme")@$offset';
}

/// A problem found while reading or parsing an expression.
class MathDiagnostic {
  const MathDiagnostic(this.offset, this.message);

  /// Character offset into the source the user typed.
  final int offset;

  final String message;

  @override
  String toString() => '$message (at $offset)';
}

/// Scans linear math input.
///
/// Words are matched greedily against the symbol table, longest first, so
/// `alpha` reads as one Greek letter while an unrecognised run like `xy` reads
/// as the separate variables mathematicians mean by it.
class MathLexer {
  MathLexer(this.source);

  final String source;

  final List<MathDiagnostic> diagnostics = <MathDiagnostic>[];
  int _offset = 0;

  /// Scans the whole input, always ending with a [TokenType.end] token.
  List<Token> tokenize() {
    final tokens = <Token>[];
    while (true) {
      final token = _next();
      tokens.add(token);
      if (token.type == TokenType.end) return tokens;
    }
  }

  Token _next() {
    // Loops rather than recurses so that a run of unrecognised characters
    // costs nothing on the stack.
    while (true) {
      _skipWhitespace();
      if (_offset >= source.length) {
        return Token(type: TokenType.end, lexeme: '', offset: _offset);
      }

      final start = _offset;
      final char = source[start];

      if (_isDigit(char) || (char == '.' && _isDigit(_peek(1)))) {
        return _number();
      }
      if (char == '"') return _text();
      if (char == '`') return _raw();
      if (char == '#') {
        final color = _color();
        if (color != null) return color;
        _offset++;
        diagnostics.add(
          MathDiagnostic(start, 'A colour is "#" and six hex digits: #A8E6B0'),
        );
        continue;
      }
      if (char == r'\') return _command();
      if (_isLetter(char)) return _word();
      if (char.codeUnitAt(0) > 0x7F) return _unicode();

      final structural = _structural(char, start);
      if (structural != null) {
        _offset++;
        return structural;
      }

      final operator = _operator(start);
      if (operator != null) return operator;

      // Skipping keeps the rest of the expression parseable, so one stray
      // keystroke does not blank the preview.
      _offset++;
      diagnostics.add(MathDiagnostic(start, 'Unexpected character "$char"'));
    }
  }

  void _skipWhitespace() {
    while (_offset < source.length && _isWhitespace(source[_offset])) {
      _offset++;
    }
  }

  Token _number() {
    final start = _offset;
    while (_offset < source.length && _isDigit(source[_offset])) {
      _offset++;
    }
    if (_offset < source.length &&
        source[_offset] == '.' &&
        _isDigit(_peek(1))) {
      _offset++;
      while (_offset < source.length && _isDigit(source[_offset])) {
        _offset++;
      }
    }
    return Token(
      type: TokenType.number,
      lexeme: source.substring(start, _offset),
      offset: start,
    );
  }

  Token _text() {
    final start = _offset;
    _offset++; // opening quote
    final buffer = StringBuffer();
    while (_offset < source.length && source[_offset] != '"') {
      buffer.write(source[_offset]);
      _offset++;
    }
    if (_offset >= source.length) {
      diagnostics.add(MathDiagnostic(start, 'Unclosed quoted text'));
    } else {
      _offset++; // closing quote
    }
    return Token(
      type: TokenType.text,
      lexeme: buffer.toString(),
      offset: start,
    );
  }

  /// A colour at the `#` here, or null where six hexadecimal digits do not
  /// follow it.
  Token? _color() {
    final start = _offset;
    final end = start + 7;
    if (end > source.length) return null;
    final digits = source.substring(start + 1, end);
    if (!RegExp(r'^[0-9A-Fa-f]{6}$').hasMatch(digits)) return null;
    _offset = end;
    return Token(
      type: TokenType.color,
      lexeme: source.substring(start, end),
      offset: start,
    );
  }

  /// LaTeX between backticks, for anything the linear syntax cannot say.
  Token _raw() {
    final start = _offset;
    _offset++; // opening backtick
    final end = source.indexOf('`', _offset);
    final String latex;
    if (end < 0) {
      diagnostics.add(MathDiagnostic(start, 'Unclosed "`"'));
      latex = source.substring(_offset);
      _offset = source.length;
    } else {
      latex = source.substring(_offset, end);
      _offset = end + 1;
    }
    return Token(
      type: TokenType.raw,
      lexeme: latex,
      offset: start,
      latex: latex,
    );
  }

  /// A LaTeX command: a backslash and a word, or a backslash and one other
  /// character (`\,`, `\{`).
  Token _command() {
    final start = _offset;
    _offset++;
    if (_offset >= source.length) {
      diagnostics.add(MathDiagnostic(start, 'A command needs a name'));
      return Token(type: TokenType.raw, lexeme: '', offset: start);
    }
    if (_isLetter(source[_offset])) {
      while (_offset < source.length && _isLetter(source[_offset])) {
        _offset++;
      }
    } else {
      _offset++;
    }
    final command = source.substring(start, _offset);
    // LaTeX that is not maths to be read is taken as it is: an environment,
    // text and the names of fonts and operators, and the delimiter a
    // \left or a \big sizes.
    if (command == r'\begin') return _environment(start);
    if (_delimiterCommands.contains(command)) return _delimited(start);
    if (_verbatimCommands[command] case final arguments?) {
      return _verbatim(start, arguments);
    }
    // A command with a word of its own behaves as that word does: `\sqrt`
    // takes an argument as `sqrt` does.
    final word = mathSymbols[command.substring(1)];
    if (word != null && word.latex == command) {
      return Token(
        type: TokenType.symbol,
        lexeme: command,
        offset: start,
        latex: command,
        symbol: word,
      );
    }
    return Token(
      type: TokenType.command,
      lexeme: command,
      offset: start,
      latex: command,
    );
  }

  /// Commands whose arguments are LaTeX, not linear input — text, names of
  /// fonts and operators, labels — and how many each takes. Each is taken
  /// with its arguments as it was typed.
  static const Map<String, int> _verbatimCommands = <String, int>{
    r'\text': 1,
    r'\textbf': 1,
    r'\textit': 1,
    r'\textrm': 1,
    r'\textsf': 1,
    r'\texttt': 1,
    r'\textup': 1,
    r'\textnormal': 1,
    r'\mbox': 1,
    r'\emph': 1,
    r'\intertext': 1,
    r'\shortintertext': 1,
    r'\operatorname': 1,
    r'\DeclareMathOperator': 2,
    r'\mathrm': 1,
    r'\mathbf': 1,
    r'\mathit': 1,
    r'\mathsf': 1,
    r'\mathtt': 1,
    r'\mathbb': 1,
    r'\mathcal': 1,
    r'\mathfrak': 1,
    r'\mathscr': 1,
    r'\boldsymbol': 1,
    r'\bm': 1,
    r'\tag': 1,
    r'\label': 1,
    r'\ref': 1,
    r'\eqref': 1,
    r'\color': 1,
    r'\textcolor': 2,
    r'\colorbox': 2,
    r'\hspace': 1,
    r'\mspace': 1,
    r'\newcommand': 2,
    r'\renewcommand': 2,
  };

  /// Commands taking a delimiter after them, to size: `\left(`, `\bigl[`.
  static const Set<String> _delimiterCommands = <String>{
    r'\left',
    r'\right',
    r'\middle',
    r'\big',
    r'\Big',
    r'\bigg',
    r'\Bigg',
    r'\bigl',
    r'\Bigl',
    r'\biggl',
    r'\Biggl',
    r'\bigr',
    r'\Bigr',
    r'\biggr',
    r'\Biggr',
    r'\bigm',
    r'\Bigm',
    r'\biggm',
    r'\Biggm',
  };

  /// The command begun at [start], its name read, with a star after it and
  /// [arguments] groups in braces — and any in brackets among them — as it
  /// was typed.
  Token _verbatim(int start, int arguments) {
    if (_offset < source.length && source[_offset] == '*') _offset++;
    var left = arguments;
    while (left > 0) {
      final next = _skipSpaces(_offset);
      if (next >= source.length) break;
      final open = source[next];
      if (open != '{' && open != '[') break;
      _offset = _closing(next, open, open == '{' ? '}' : ']');
      if (open == '{') left--;
    }
    return _rawFrom(start);
  }

  /// `\begin{name}` at [start], its name not yet read, up to the
  /// `\end{name}` that closes it, environments of the same name within it
  /// counted: all of it LaTeX, as it was typed.
  Token _environment(int start) {
    final open = _skipSpaces(_offset);
    final close = open < source.length && source[open] == '{'
        ? source.indexOf('}', open)
        : -1;
    if (close < 0) {
      diagnostics.add(
        MathDiagnostic(start, r'"\begin" needs a name: \begin{cases}'),
      );
      return _rawFrom(start);
    }
    final name = source.substring(open + 1, close);
    final begin = '\\begin{$name}';
    final end = '\\end{$name}';
    var depth = 1;
    var at = close + 1;
    while (depth > 0) {
      final nextEnd = source.indexOf(end, at);
      if (nextEnd < 0) {
        diagnostics.add(MathDiagnostic(start, 'Missing "$end"'));
        _offset = source.length;
        return _rawFrom(start);
      }
      final nextBegin = source.indexOf(begin, at);
      if (nextBegin >= 0 && nextBegin < nextEnd) {
        depth++;
        at = nextBegin + begin.length;
      } else {
        depth--;
        at = nextEnd + end.length;
      }
    }
    _offset = at;
    return _rawFrom(start);
  }

  /// The sizing command begun at [start], its name read, with the delimiter
  /// it sizes: a character, or a command such as `\langle`.
  Token _delimited(int start) {
    var at = _skipSpaces(_offset);
    if (at < source.length) {
      if (source[at] == r'\') {
        at++;
        if (at < source.length && _isLetter(source[at])) {
          while (at < source.length && _isLetter(source[at])) {
            at++;
          }
        } else if (at < source.length) {
          at++;
        }
      } else {
        at++;
      }
    }
    _offset = at;
    return _rawFrom(start);
  }

  /// Where the group opened by [open] at [from] closes, groups within it of
  /// the same kind counted and escaped characters skipped: just past its
  /// closing [close], or the end of the source.
  int _closing(int from, String open, String close) {
    var depth = 0;
    for (var i = from; i < source.length; i++) {
      final char = source[i];
      if (char == r'\') {
        i++;
      } else if (char == open) {
        depth++;
      } else if (char == close && --depth == 0) {
        return i + 1;
      }
    }
    diagnostics.add(MathDiagnostic(from, 'Missing "$close"'));
    return source.length;
  }

  int _skipSpaces(int from) {
    var at = from;
    while (at < source.length && _isWhitespace(source[at])) {
      at++;
    }
    return at;
  }

  /// The source from [start] to where reading has got, as LaTeX passed
  /// through.
  Token _rawFrom(int start) {
    final latex = source.substring(start, _offset);
    return Token(
      type: TokenType.raw,
      lexeme: latex,
      offset: start,
      latex: latex,
    );
  }

  /// A letter or symbol beyond ASCII, such as a typed π, taken as it is.
  Token _unicode() {
    final start = _offset;
    final code = source.codeUnitAt(start);
    final isHighSurrogate = code >= 0xD800 && code <= 0xDBFF;
    _offset += isHighSurrogate && start + 1 < source.length ? 2 : 1;
    return Token(
      type: TokenType.variable,
      lexeme: source.substring(start, _offset),
      offset: start,
    );
  }

  Token _word() {
    final start = _offset;
    for (final word in knownWordsByLength) {
      if (source.startsWith(word, start)) {
        _offset = start + word.length;
        return Token(
          type: TokenType.symbol,
          lexeme: word,
          offset: start,
          latex: mathSymbols[word]!.latex,
          symbol: mathSymbols[word],
        );
      }
    }
    _offset = start + 1;
    return Token(
      type: TokenType.variable,
      lexeme: source[start],
      offset: start,
    );
  }

  Token? _structural(String char, int offset) => switch (char) {
    '(' => Token(type: TokenType.leftParen, lexeme: char, offset: offset),
    ')' => Token(type: TokenType.rightParen, lexeme: char, offset: offset),
    '[' => Token(type: TokenType.leftBracket, lexeme: char, offset: offset),
    ']' => Token(type: TokenType.rightBracket, lexeme: char, offset: offset),
    '{' => Token(type: TokenType.leftBrace, lexeme: char, offset: offset),
    '}' => Token(type: TokenType.rightBrace, lexeme: char, offset: offset),
    '|' => Token(type: TokenType.bar, lexeme: char, offset: offset),
    '^' => Token(type: TokenType.caret, lexeme: char, offset: offset),
    '_' => Token(type: TokenType.underscore, lexeme: char, offset: offset),
    ',' => Token(type: TokenType.comma, lexeme: char, offset: offset),
    ';' => Token(type: TokenType.semicolon, lexeme: char, offset: offset),
    "'" => Token(type: TokenType.prime, lexeme: char, offset: offset),
    '/' => Token(type: TokenType.slash, lexeme: char, offset: offset),
    _ => null,
  };

  /// Matches the longest punctuation operator at [start], so `<=` wins over `<`.
  Token? _operator(int start) {
    for (final sequence in _operatorsByLength) {
      if (source.startsWith(sequence, start)) {
        _offset = start + sequence.length;
        return Token(
          type: TokenType.operator,
          lexeme: sequence,
          offset: start,
          latex: operatorSequences[sequence]!,
        );
      }
    }
    return null;
  }

  static final List<String> _operatorsByLength = operatorSequences.keys.toList()
    ..sort((a, b) => b.length.compareTo(a.length));

  String _peek(int ahead) {
    final index = _offset + ahead;
    return index < source.length ? source[index] : '';
  }

  static bool _isDigit(String char) =>
      char.isNotEmpty &&
      char.codeUnitAt(0) >= 0x30 &&
      char.codeUnitAt(0) <= 0x39;

  static bool _isWhitespace(String char) => char.trim().isEmpty;

  static bool _isLetter(String char) {
    if (char.isEmpty) return false;
    final code = char.codeUnitAt(0);
    return (code >= 0x41 && code <= 0x5A) || (code >= 0x61 && code <= 0x7A);
  }
}
