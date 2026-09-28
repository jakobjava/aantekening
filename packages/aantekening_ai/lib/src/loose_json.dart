/// Reading JSON as models write it, rather than as the standard has it:
/// among prose and fences, with LaTeX's backslashes left single, quotes
/// inside strings left bare, commas left out or left over, and, while it
/// is still being written, as far as it goes.
library;

/// A value read out of what a model wrote, and whether some of it was
/// [lost]: reading stopped short at something it could not read, before
/// the text ended.
typedef LooseValue = ({Object? value, bool lost});

/// Reads the JSON in what a model writes, however it wrote it.
///
/// One reading for text still arriving and text complete, so what was
/// shown while it came is there once it has: a value broken off keeps
/// what it holds so far, and only a string, number or word not yet ended
/// is left out.
abstract final class LooseJson {
  /// Every object and list written in [text], outermost ones only, in
  /// order: the prose round them passed over.
  ///
  /// Numbers with a fraction or exponent are kept as they were written,
  /// as strings, since a passage number like `1.10` is not the number
  /// 1.1; whole numbers are [int]s.
  static List<LooseValue> valuesIn(String text) {
    final values = <LooseValue>[];
    var at = 0;
    while (at < text.length) {
      final start = text.indexOf(_opening, at);
      if (start < 0) break;
      final reader = _Reader(text, start);
      final value = reader.value();
      if (identical(value, _nothing)) {
        at = start + 1;
        continue;
      }
      values.add((value: value, lost: reader.broken && !reader._atEnd));
      at = reader.at > start ? reader.at : start + 1;
    }
    return values;
  }

  static final RegExp _opening = RegExp(r'[{\[]');
}

/// What stands for no value: a string not yet ended, or what could not be
/// read as one.
const Object _nothing = Object();

/// Reads one value from [at] in [text], leaving [at] past it.
class _Reader {
  _Reader(this.text, this.at);

  final String text;
  int at;

  /// Whether reading stopped short: at the end of the text, or at
  /// something it could not read. Everything open is closed there, with
  /// what it holds so far.
  bool broken = false;

  bool get _atEnd => at >= text.length;

  /// Where each quote a string may open with is closed.
  static const Map<String, String> _quotes = <String, String>{
    '"': '"',
    "'": "'",
    '“': '”',
    '„': '“',
    '‘': '’',
  };

  /// The value at [at], or [_nothing].
  Object? value() {
    _space();
    if (_atEnd) {
      broken = true;
      return _nothing;
    }
    final char = text[at];
    if (char == '{') return _object();
    if (char == '[') return _array();
    if (_quotes[char] case final close?) return _string(close);
    return _word();
  }

  Object? _object() {
    at++;
    final map = <String, Object?>{};
    while (true) {
      _space();
      if (_atEnd) return _brokenOff(map);
      final char = text[at];
      if (char == '}') {
        at++;
        return map;
      }
      if (char == ',') {
        at++;
        continue;
      }
      final key = _key();
      _space();
      final colon = !_atEnd && (text[at] == ':' || text[at] == '=');
      if (key == null || !colon) {
        // Braces in prose, not an object at all; or one broken off.
        if (map.isEmpty && !_atEnd) return _nothing;
        return _brokenOff(map);
      }
      at++;
      final value = this.value();
      if (identical(value, _nothing)) return _brokenOff(map);
      map[key] = value;
      if (broken) return map;
    }
  }

  Object? _array() {
    at++;
    final list = <Object?>[];
    while (true) {
      _space();
      if (_atEnd) return _brokenOff(list);
      final char = text[at];
      if (char == ']') {
        at++;
        return list;
      }
      if (char == ',') {
        at++;
        continue;
      }
      if (char == '}') {
        // Brackets in prose, or a list its writer forgot to close.
        if (list.isEmpty) return _nothing;
        return _brokenOff(list);
      }
      final value = this.value();
      if (identical(value, _nothing)) {
        if (list.isEmpty && !_atEnd) return _nothing;
        return _brokenOff(list);
      }
      list.add(value);
      if (broken) return list;
    }
  }

  /// [value], as far as it goes, where reading stopped short.
  Object? _brokenOff(Object? value) {
    broken = true;
    return value;
  }

  /// A key: a string, or a bare name.
  String? _key() {
    final char = text[at];
    if (_quotes[char] case final close?) {
      final key = _string(close);
      return key is String ? key : null;
    }
    final name = _name.matchAsPrefix(text, at);
    if (name == null) return null;
    at = name.end;
    return name[0];
  }

  static final RegExp _name = RegExp(r'[A-Za-z_$][\w$-]*');

  /// A string, from its opening quote to its [close]: a quote that could
  /// close it only does where what follows can follow a string — so
  /// `„so-called"` and `don't` inside one are kept as they are.
  Object? _string(String close) {
    final open = text[at];
    at++;
    final out = StringBuffer();
    // Whether in mathematics, between dollars or \( and \), where every
    // backslash is LaTeX's.
    var math = false;
    while (true) {
      if (_atEnd) {
        broken = true;
        return _nothing;
      }
      final char = text[at];
      if ((char == close || (open == '"' && char == '”')) && _closes(at + 1)) {
        at++;
        return out.toString();
      }
      if (char == r'$') math = !math;
      if (char != r'\') {
        out.write(char);
        at++;
        continue;
      }
      if (at + 1 >= text.length) {
        broken = true;
        return _nothing;
      }
      final next = text[at + 1];
      if (next == '(' || next == '[') math = true;
      if (next == ')' || next == ']') math = false;
      final escaped = _escape(next, at + 1, math: math);
      if (escaped == null) {
        // LaTeX's, not an escape: the backslash kept, the rest read on.
        out.write(r'\');
        at++;
        continue;
      }
      if (escaped.isEmpty) {
        broken = true;
        return _nothing;
      }
      out.write(escaped);
      at += next == 'u' ? 6 : 2;
    }
  }

  /// What the escape `\` [next], at [from], stands for — or null where
  /// the backslash is LaTeX's, `\frac` or `\alpha`, and empty for one not
  /// yet all there, at the end of the text.
  String? _escape(String next, int from, {required bool math}) {
    switch (next) {
      case '"' || r'\' || '/' || "'":
        return next;
      case 'u':
        if (_hex.matchAsPrefix(text, from + 1) case final hex?) {
          return String.fromCharCode(int.parse(hex[0]!, radix: 16));
        }
        final rest = text.substring(from + 1);
        return rest.length < 4 && _hexStart.hasMatch(rest) ? '' : null;
      case 'b' || 'f' || 'n' || 'r' || 't':
        final word = _letters.matchAsPrefix(text, from)![0]!;
        if (from + word.length >= text.length) return '';
        if (word.length > 1 && (math || _latex.contains(word))) return null;
        return switch (next) {
          'b' => '\b',
          'f' => '\f',
          'n' => '\n',
          'r' => '\r',
          _ => '\t',
        };
      default:
        return null;
    }
  }

  static final RegExp _hex = RegExp('[0-9a-fA-F]{4}');
  static final RegExp _hexStart = RegExp(r'^[0-9a-fA-F]*$');
  static final RegExp _letters = RegExp('[A-Za-z]*');

  /// LaTeX commands whose first letter would make an escape of JSON, read
  /// as LaTeX even outside dollars: `\frac` as a form feed and "rac",
  /// `\theta` as a tab and "heta", otherwise.
  static final Set<String> _latex = _words(
    'frac tfrac dfrac theta Theta tau times text textbf textit '
    'textrm textstyle to top tilde tan tanh triangle therefore nu '
    'nabla neq ne not ni newline nolimits neg nleq ngeq notin '
    'nearrow beta bar begin bigl bigr big Big binom bmod boldsymbol '
    'bf bullet boxed breve backslash because bmatrix rho right '
    'rightarrow Rightarrow rangle rm rceil rfloor rVert rvert Rho '
    'forall frown flat frak fbox',
  );

  static Set<String> _words(String words) => words.split(' ').toSet();

  /// Whether a quote ending before [from] closes its string: followed by
  /// what ends a list or object, a key's colon, another string, or a comma
  /// or line and then the start of something else. At the end of text
  /// still arriving, that is not yet known, and the string is left
  /// unfinished.
  bool _closes(int from) {
    var i = from;
    while (i < text.length && (text[i] == ' ' || text[i] == '\t')) {
      i++;
    }
    if (i >= text.length) return false;
    final char = text[i];
    // A string after it, the comma between them left out.
    if (char == '"') return i > from;
    if (char == '}' || char == ']' || char == ':') return true;
    if (char != ',' && char != '\n' && char != '\r') return false;
    i++;
    while (i < text.length && text[i].trim().isEmpty) {
      i++;
    }
    if (i >= text.length) return false;
    return _startsNext.hasMatch(text[i]) ||
        (char == ',' && _nameThenColon.matchAsPrefix(text, i) != null);
  }

  static final RegExp _startsNext = RegExp('["“„\'{\\[\\]}]');
  static final RegExp _nameThenColon = RegExp(r'[A-Za-z_]\w*\s*:');

  /// A number, a word — true, false, null, or theirs in Python — or a
  /// bare word taken as a string, up to what ends a value.
  Object? _word() {
    final match = _bare.matchAsPrefix(text, at);
    final word = match?[0]?.trim() ?? '';
    if (word.isEmpty) {
      broken = true;
      return _nothing;
    }
    at = match!.end;
    // A word at the end of the text may be the start of a longer one.
    if (_atEnd) {
      broken = true;
      return _nothing;
    }
    return switch (word) {
      'true' || 'True' => true,
      'false' || 'False' => false,
      'null' || 'None' || 'undefined' => null,
      _ when _integer.hasMatch(word) => int.parse(word),
      _ => word,
    };
  }

  static final RegExp _bare = RegExp(r'[^,}\]\n]+');
  static final RegExp _integer = RegExp(r'^[-+]?\d{1,15}$');

  /// Past spaces and comments.
  void _space() {
    while (!_atEnd) {
      final char = text[at];
      if (char.trim().isEmpty) {
        at++;
      } else if (text.startsWith('//', at)) {
        final end = text.indexOf('\n', at);
        at = end < 0 ? text.length : end;
      } else if (text.startsWith('/*', at)) {
        final end = text.indexOf('*/', at + 2);
        at = end < 0 ? text.length : end + 2;
      } else {
        return;
      }
    }
  }
}
