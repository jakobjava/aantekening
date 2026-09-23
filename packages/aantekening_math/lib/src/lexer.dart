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
