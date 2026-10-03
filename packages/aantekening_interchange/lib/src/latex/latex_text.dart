/// LaTeX read as the text of a box: paragraphs, headings, lists and tables,
/// formulas in the text and set apart from it.
library;

import 'dart:math' as math;

import 'package:aantekening_core/aantekening_core.dart';

/// What a piece of LaTeX writes, read as the text of a box.
final class LatexDocument {
  const LatexDocument({required this.blocks, this.title});

  /// What `\title` names, if it names anything.
  final String? title;

  /// The paragraphs, headings, list items, formulas and table cells.
  final List<TextBlock> blocks;
}

/// Reads LaTeX — a whole document, or a passage of one — as text.
///
/// Formulas are kept as the LaTeX they are, an environment (`align`,
/// `cases`) whole, each on one line: `$…$` and `\(…\)` in the text, `$$…$$`,
/// `\[…\]` and the display environments as a line of their own, centred.
/// Commands the document defines (`\newcommand`, `\def`,
/// `\DeclareMathOperator`) are written out where they are used, so each
/// formula stands by itself. Of the text, what notes keep is kept —
/// sections as headings, lists, tables, bold, italic, underlining, code and
/// links — and what only sets out a printed page is left out. A TikZ
/// picture is kept whole, as a picture of its own, with the styles the
/// document gives its pictures (`\tikzset`, `\tikzstyle`) put in it.
abstract final class LatexText {
  static LatexDocument read(String source) {
    final uncommented = _withoutComments(source);
    final preamble = LatexPreamble();
    final begin = uncommented.indexOf(r'\begin{document}');
    final end = uncommented.indexOf(r'\end{document}');
    String body;
    String? title;
    if (begin >= 0) {
      final head = uncommented.substring(0, begin);
      preamble.takeFrom(head);
      title = _argumentOf(head, r'\title');
      body = uncommented.substring(
        begin + r'\begin{document}'.length,
        end > begin ? end : uncommented.length,
      );
    } else {
      body = uncommented;
    }
    body = preamble.expand(preamble.takeFrom(body));
    title ??= _argumentOf(body, r'\title');
    final reader = _Reader(body, preamble: preamble)..read();
    return LatexDocument(
      title: title == null ? null : _plain(preamble.expand(title)),
      blocks: reader.blocks,
    );
  }

  /// [source] without its comments: from a `%` that is not escaped to the
  /// end of its line, and the spaces that begin the next, as TeX reads it.
  static String _withoutComments(String source) =>
      source.replaceAllMapped(RegExp(r'(?<!\\)%[^\n]*\n?[ \t]*'), (_) => '');

  /// The braced argument of the first [command] in [source], if any.
  static String? _argumentOf(String source, String command) {
    final at = RegExp(
      '${RegExp.escape(command)}(?![A-Za-z])',
    ).firstMatch(source);
    if (at == null) return null;
    final open = LatexSource.skipSpaces(source, at.end);
    if (open >= source.length || source[open] != '{') return null;
    final close = LatexSource.closingBrace(source, open);
    return source.substring(open + 1, close - 1);
  }

  /// [latex] as the plain text it reads as, formatting left out.
  static String _plain(String latex) => (_Reader(
    latex,
  )..read()).blocks.map((block) => block.plainText).join(' ').trim();
}

/// Environments set apart as a formula of their own, kept as they are.
const Set<String> _displayEnvironments = <String>{
  'equation',
  'equation*',
  'align',
  'align*',
  'alignat',
  'alignat*',
  'flalign',
  'flalign*',
  'gather',
  'gather*',
  'multline',
  'multline*',
  'eqnarray',
  'eqnarray*',
  'displaymath',
};

/// Environments numbered or named as theorems are, set with their name
/// first, in bold.
const Set<String> _statements = <String>{
  'theorem',
  'lemma',
  'proposition',
  'corollary',
  'definition',
  'example',
  'remark',
  'proof',
  'claim',
  'conjecture',
  'exercise',
  'solution',
  'note',
  'satz',
  'definition*',
  'beweis',
  'beispiel',
  'bemerkung',
};

/// Commands that only set out a printed page, left out with their
/// arguments: how many braced ones each takes.
const Map<String, int> _ignored = <String, int>{
  r'\label': 1,
  r'\index': 1,
  r'\vspace': 1,
  r'\hspace': 1,
  r'\includegraphics': 1,
  r'\usepackage': 1,
  r'\documentclass': 1,
  r'\author': 1,
  r'\date': 1,
  r'\title': 1,
  r'\thanks': 1,
  r'\pagestyle': 1,
  r'\thispagestyle': 1,
  r'\setlength': 2,
  r'\addtolength': 2,
  r'\setcounter': 2,
  r'\addcontentsline': 3,
  r'\bibliographystyle': 1,
  r'\bibliography': 1,
  r'\maketitle': 0,
  r'\tableofcontents': 0,
  r'\noindent': 0,
  r'\indent': 0,
  r'\centering': 0,
  r'\raggedright': 0,
  r'\raggedleft': 0,
  r'\clearpage': 0,
  r'\cleardoublepage': 0,
  r'\newpage': 0,
  r'\pagebreak': 0,
  r'\linebreak': 0,
  r'\bigskip': 0,
  r'\medskip': 0,
  r'\smallskip': 0,
  r'\hfill': 0,
  r'\vfill': 0,
  r'\hline': 0,
  r'\toprule': 0,
  r'\midrule': 0,
  r'\bottomrule': 0,
  r'\appendix': 0,
  r'\normalsize': 0,
  r'\small': 0,
  r'\footnotesize': 0,
  r'\large': 0,
  r'\Large': 0,
  r'\LARGE': 0,
  r'\huge': 0,
  r'\Huge': 0,
  r'\protect': 0,
  r'\relax': 0,
};

/// Commands that stand for a character or a word.
const Map<String, String> _words = <String, String>{
  r'\%': '%',
  r'\&': '&',
  r'\$': r'$',
  r'\#': '#',
  r'\_': '_',
  r'\{': '{',
  r'\}': '}',
  r'\ ': ' ',
  r'\,': '\u2009',
  r'\;': ' ',
  r'\:': ' ',
  r'\quad': '\u2003',
  r'\qquad': '\u2003\u2003',
  r'\textbackslash': r'\',
  r'\ldots': '…',
  r'\dots': '…',
  r'\textellipsis': '…',
  r'\LaTeX': 'LaTeX',
  r'\TeX': 'TeX',
  r'\ss': 'ß',
  r'\o': 'ø',
  r'\O': 'Ø',
  r'\aa': 'å',
  r'\AA': 'Å',
  r'\ae': 'æ',
  r'\AE': 'Æ',
  r'\oe': 'œ',
  r'\OE': 'Œ',
  r'\i': 'ı',
  r'\l': 'ł',
  r'\L': 'Ł',
  r'\S': '§',
  r'\P': '¶',
  r'\copyright': '©',
  r'\textdegree': '°',
  r'\euro': '€',
  r'\textendash': '–',
  r'\textemdash': '—',
  r'\textquotedblleft': '“',
  r'\textquotedblright': '”',
  r'\glqq': '„',
  r'\grqq': '“',
  r'\glq': '‚',
  r'\grq': '‘',
};

/// The marks of accents, by the character after the backslash, as they
/// combine with the letter they are put on.
const Map<String, String> _accents = <String, String>{
  '"': '\u0308',
  "'": '\u0301',
  '`': '\u0300',
  '^': '\u0302',
  '~': '\u0303',
  '=': '\u0304',
  '.': '\u0307',
  'c': '\u0327',
  'v': '\u030C',
  'u': '\u0306',
  'H': '\u030B',
  'r': '\u030A',
  'k': '\u0328',
};

/// The precomposed letters the accents above make most often, so that
/// what is read is what is typed.
const Map<String, String> _composed = <String, String>{
  'a\u0308': 'ä',
  'o\u0308': 'ö',
  'u\u0308': 'ü',
  'A\u0308': 'Ä',
  'O\u0308': 'Ö',
  'U\u0308': 'Ü',
  'e\u0308': 'ë',
  'i\u0308': 'ï',
  'a\u0301': 'á',
  'e\u0301': 'é',
  'i\u0301': 'í',
  'o\u0301': 'ó',
  'u\u0301': 'ú',
  'E\u0301': 'É',
  'a\u0300': 'à',
  'e\u0300': 'è',
  'i\u0300': 'ì',
  'o\u0300': 'ò',
  'u\u0300': 'ù',
  'a\u0302': 'â',
  'e\u0302': 'ê',
  'i\u0302': 'î',
  'o\u0302': 'ô',
  'u\u0302': 'û',
  'n\u0303': 'ñ',
  'a\u0303': 'ã',
  'o\u0303': 'õ',
  'c\u0327': 'ç',
  'C\u0327': 'Ç',
  's\u030C': 'š',
  'c\u030C': 'č',
  'z\u030C': 'ž',
  'S\u030C': 'Š',
  'Z\u030C': 'Ž',
};

/// A list being read: what its items are, and how deep it is.
typedef _List = ({TextBlockKind kind, int depth});

/// Reads the body of a document into blocks.
final class _Reader {
  _Reader(this.source, {LatexPreamble? preamble})
    : preamble = preamble ?? LatexPreamble();

  final String source;

  /// What the document's preamble sets, for its TikZ pictures' styles.
  final LatexPreamble preamble;
  int _at = 0;

  final List<TextBlock> blocks = <TextBlock>[];

  /// The runs of the paragraph being read.
  final List<TextRun> _runs = <TextRun>[];

  /// What the paragraph being read is: a heading, an item, a quotation.
  TextBlockKind _kind = TextBlockKind.paragraph;
  int _indent = 0;
  BlockAlign _align = BlockAlign.start;

  /// The marks text is read in now, a group's own set by `{\bf …}`.
  TextMarks _marks = TextMarks.none;

  final List<_List> _lists = <_List>[];
  int _quotes = 0;

  /// Reads all of [source], or up to [stop] — the `\end` of the
  /// environment being read, or a closing brace.
  void read({String? stop}) {
    while (_at < source.length) {
      if (stop != null && source.startsWith(stop, _at)) {
        _at += stop.length;
        return;
      }
      final char = source[_at];
      switch (char) {
        case r'\':
          _command();
        case r'$':
          _dollar();
        case '{':
          _at++;
          final kept = _marks;
          read(stop: '}');
          _marks = kept;
        case '}':
          // A brace closing a group never opened here.
          _at++;
        case '~':
          _at++;
          _text('\u00A0');
        case '\n':
          final next = LatexSource.skipSpaces(source, _at);
          if (source.substring(_at, next).contains('\n\n') ||
              RegExp(r'\n[ \t]*\n').hasMatch(source.substring(_at, next))) {
            _endParagraph();
          } else {
            _text(' ');
          }
          _at = next;
        case ' ' || '\t' || '\r':
          _at++;
          _text(' ');
        case '-' when source.startsWith('---', _at):
          _at += 3;
          _text('—');
        case '-' when source.startsWith('--', _at):
          _at += 2;
          _text('–');
        case '`' when source.startsWith('``', _at):
          _at += 2;
          _text('“');
        case "'" when source.startsWith("''", _at):
          _at += 2;
          _text('”');
        case '&':
          // An alignment tab outside a table: a gap.
          _at++;
          _text(' ');
        default:
          _at++;
          _text(char);
      }
    }
    _endParagraph();
  }

  // --------------------------------------------------------------- text

  void _text(String text) {
    if (text == ' ' || text == '\u00A0') {
      // No space at the start of a paragraph, and one at most between
      // words.
      if (_runs.isEmpty) return;
      final last = _runs.last;
      if (!last.isMath &&
          (last.text.endsWith(' ') || last.text.endsWith('\u00A0'))) {
        return;
      }
    }
    if (_runs.isNotEmpty && !_runs.last.isMath && _runs.last.marks == _marks) {
      final last = _runs.removeLast();
      _runs.add(TextRun(last.text + text, _marks));
    } else {
      _runs.add(TextRun(text, _marks));
    }
  }

  void _formula(String latex, {required bool display}) {
    final formula = display
        ? _laidOut(latex)
        : latex.replaceAll(RegExp(r'\s+'), ' ').trim();
    if (formula.isEmpty) return;
    if (!display) {
      _runs.add(TextRun.imported(formula, _marks));
      return;
    }
    _endParagraph();
    blocks.add(
      TextBlock(
        runs: <TextRun>[TextRun.imported(formula)],
        align: BlockAlign.center,
        indent: _indent,
      ),
    );
  }

  /// [latex], a formula on a line of its own, laid out as it was written,
  /// for it to be as easy to read and change: on its lines, each indented
  /// as far beyond the least indented as it was, without the blank lines
  /// before and after it or the spaces ending its lines. Its first line
  /// starts where it does.
  static String _laidOut(String latex) {
    final lines = <String>[
      for (final line in latex.split('\n')) line.trimRight(),
    ];
    while (lines.isNotEmpty && lines.first.trim().isEmpty) {
      lines.removeAt(0);
    }
    while (lines.isNotEmpty && lines.last.trim().isEmpty) {
      lines.removeLast();
    }
    if (lines.isEmpty) return '';
    int indentOf(String line) => line.length - line.trimLeft().length;
    final rest = lines.skip(1).where((line) => line.isNotEmpty);
    final least = rest.isEmpty ? 0 : rest.map(indentOf).reduce(math.min);
    return <String>[
      lines.first.trimLeft(),
      for (final line in lines.skip(1))
        line.length < least ? line.trimLeft() : line.substring(least),
    ].join('\n');
  }

  /// Ends the paragraph being read, keeping it if it holds anything, and
  /// starts another of the same kind.
  void _endParagraph() {
    while (_runs.isNotEmpty &&
        !_runs.last.isMath &&
        _runs.last.text.trim().isEmpty) {
      _runs.removeLast();
    }
    if (_runs.isNotEmpty) {
      final last = _runs.removeLast();
      _runs.add(
        last.isMath ? last : TextRun(last.text.trimRight(), last.marks),
      );
      blocks.add(
        TextBlock(
          kind: _quotes > 0 && _kind == TextBlockKind.paragraph
              ? TextBlockKind.quote
              : _kind,
          runs: List<TextRun>.of(_runs),
          indent: _indent,
          align: _align,
        ),
      );
    }
    _runs.clear();
    // Within a list, what follows an item's first paragraph is more of it.
    if (_kind == TextBlockKind.heading1 ||
        _kind == TextBlockKind.heading2 ||
        _kind == TextBlockKind.heading3) {
      _kind = TextBlockKind.paragraph;
    }
  }

  /// Reads a braced argument at the reading point as text in [marks],
  /// added to the paragraph being read.
  void _styled(TextMarks Function(TextMarks marks) marks) {
    final kept = _marks;
    _marks = marks(_marks);
    _argument(read: true);
    _marks = kept;
  }

  /// The braced argument at the reading point: read into the paragraph
  /// where [read] is set, else passed over and returned.
  String? _argument({bool read = false}) {
    final open = LatexSource.skipSpaces(source, _at);
    if (open >= source.length || source[open] != '{') return null;
    _at = open + 1;
    if (read) {
      this.read(stop: '}');
      return null;
    }
    final close = LatexSource.closingBrace(source, open);
    _at = close;
    return source.substring(open + 1, close - 1);
  }

  /// An optional argument in brackets at the reading point, passed over.
  String? _option() {
    final open = LatexSource.skipSpaces(source, _at);
    if (open >= source.length || source[open] != '[') return null;
    final close = source.indexOf(']', open);
    if (close < 0) return null;
    _at = close + 1;
    return source.substring(open + 1, close);
  }

  // ------------------------------------------------------------ commands

  void _command() {
    final start = _at;
    _at++;
    if (_at >= source.length) return;
    // `\\`, `\%` and other one-character commands.
    if (!LatexSource.isLetter(source.codeUnitAt(_at))) {
      final char = source[_at];
      _at++;
      final name = '\\$char';
      if (name == r'\\') {
        _option();
        _endParagraph();
        return;
      }
      if (name == r'\(') return _until(r'\)', display: false);
      if (name == r'\[') return _until(r'\]', display: true);
      if (_accents[char] case final mark?) return _accent(mark);
      _text(_words[name] ?? char);
      return;
    }
    while (_at < source.length &&
        LatexSource.isLetter(source.codeUnitAt(_at))) {
      _at++;
    }
    final name = source.substring(start, _at);
    final starred = _at < source.length && source[_at] == '*';
    if (starred) _at++;

    switch (name) {
      case r'\begin':
        return _environment();
      case r'\end':
        // An `\end` of an environment not read here.
        _argument();
        return;
      case r'\section' || r'\chapter' || r'\part':
        return _heading(TextBlockKind.heading1);
      case r'\subsection':
        return _heading(TextBlockKind.heading2);
      case r'\subsubsection':
        return _heading(TextBlockKind.heading3);
      case r'\paragraph' || r'\subparagraph':
        _endParagraph();
        _option();
        _styled((marks) => marks.copyWith(bold: true));
        _text(' ');
        return;
      case r'\par':
        return _endParagraph();
      case r'\newline':
        return _endParagraph();
      case r'\item':
        return _item();
      case r'\textbf':
        return _styled((marks) => marks.copyWith(bold: true));
      case r'\textit' || r'\emph' || r'\textsl':
        return _styled((marks) => marks.copyWith(italic: !marks.italic));
      case r'\underline' || r'\uline':
        return _styled((marks) => marks.copyWith(underline: true));
      case r'\sout' || r'\st':
        return _styled((marks) => marks.copyWith(strikethrough: true));
      case r'\texttt' || r'\verb':
        return _styled((marks) => marks.copyWith(code: true));
      case r'\textsuperscript':
        return _styled(
          (marks) => marks.copyWith(script: TextScript.superscript),
        );
      case r'\textsubscript':
        return _styled((marks) => marks.copyWith(script: TextScript.subscript));
      case r'\bf' || r'\bfseries':
        _marks = _marks.copyWith(bold: true);
        return;
      case r'\it' || r'\itshape' || r'\em' || r'\sl':
        _marks = _marks.copyWith(italic: true);
        return;
      case r'\tt' || r'\ttfamily':
        _marks = _marks.copyWith(code: true);
        return;
      case r'\rm' || r'\normalfont' || r'\upshape' || r'\mdseries':
        _marks = TextMarks.none;
        return;
      case r'\href':
        final target = _argument();
        return _styled((marks) => marks.copyWith(link: target));
      case r'\url':
        final target = _argument() ?? '';
        final kept = _marks;
        _marks = _marks.copyWith(link: target);
        _text(target);
        _marks = kept;
        return;
      case r'\footnote':
        _text(' (');
        _argument(read: true);
        _text(')');
        return;
      case r'\cite' || r'\citep' || r'\citet':
        _option();
        _text('[${_argument() ?? ''}]');
        return;
      case r'\ref' || r'\autoref' || r'\cref' || r'\pageref':
        _text(_argument() ?? '');
        return;
      case r'\eqref':
        _text('(${_argument() ?? ''})');
        return;
      case r'\ensuremath':
        return _formula(_argument() ?? '', display: false);
      case r'\caption':
        _endParagraph();
        _option();
        _styled((marks) => marks.copyWith(italic: true));
        _endParagraph();
        return;
    }
    if (_words[name] case final word?) {
      // A command written as a word ends at the space after it.
      if (_at < source.length && source[_at] == ' ') _at++;
      _text(word);
      return;
    }
    if (_ignored[name] case final arguments?) {
      _option();
      for (var i = 0; i < arguments; i++) {
        _argument();
      }
      _option();
      return;
    }
    // A command not known here: what it is given is read as text.
    _option();
    while (LatexSource.skipSpaces(source, _at) < source.length &&
        source[LatexSource.skipSpaces(source, _at)] == '{') {
      _argument(read: true);
    }
  }

  void _accent(String mark) {
    // `\"a`, `\"{a}` and `\" a` are all the same letter.
    var at = _at;
    if (at < source.length && source[at] == '{') at++;
    at = LatexSource.skipSpaces(source, at);
    if (at >= source.length) return;
    final letter = source[at];
    at++;
    if (at < source.length && source[at] == '}') at++;
    _at = at;
    final combined = '$letter$mark';
    _text(_composed[combined] ?? combined);
  }

  void _heading(TextBlockKind kind) {
    _endParagraph();
    _option();
    final kept = (kind: _kind, indent: _indent, align: _align);
    _kind = kind;
    _indent = 0;
    _align = BlockAlign.start;
    _argument(read: true);
    _endParagraph();
    _kind = kept.kind == kind ? TextBlockKind.paragraph : kept.kind;
    _indent = kept.indent;
    _align = kept.align;
  }

  void _item() {
    final list = _lists.isEmpty ? null : _lists.last;
    _endParagraph();
    if (list == null) return;
    _kind = list.kind;
    _indent = list.depth;
    final label = _option();
    if (label != null) {
      // A description's term, or an item's own label, in bold before it.
      final kept = _marks;
      _marks = _marks.copyWith(bold: true);
      final reader = _Reader(label)..read();
      for (final block in reader.blocks) {
        for (final run in block.runs) {
          _runs.add(
            run.isMath
                ? run
                : TextRun(run.text, run.marks.copyWith(bold: true)),
          );
        }
      }
      _marks = kept;
      _text(' ');
    }
  }

  // ----------------------------------------------------------- formulas

  void _dollar() {
    if (source.startsWith(r'$$', _at)) {
      _at += 2;
      _until(r'$$', display: true);
    } else {
      _at++;
      _until(r'$', display: false);
    }
  }

  /// Reads a formula up to [end], not counting an escaped one.
  void _until(String end, {required bool display}) {
    var at = _at;
    while (true) {
      final found = source.indexOf(end, at);
      if (found < 0) {
        _formula(source.substring(_at), display: display);
        _at = source.length;
        return;
      }
      if (found > 0 &&
          source[found - 1] == r'\' &&
          end != r'\)' &&
          end != r'\]') {
        at = found + 1;
        continue;
      }
      _formula(source.substring(_at, found), display: display);
      _at = found + end.length;
      return;
    }
  }

  // ------------------------------------------------------- environments

  void _environment() {
    final name = (_argument() ?? '').trim();
    final end = '\\end{$name}';
    if (_displayEnvironments.contains(name)) {
      final close = _environmentEnd(name);
      final body = source.substring(_at, close);
      _at = math.min(source.length, close + end.length);
      if (name == 'displaymath' ||
          name == 'equation*' && !body.contains(r'\\')) {
        _formula(body, display: true);
      } else {
        // eqnarray's three columns are set as align's.
        final shown = name.startsWith('eqnarray')
            ? name.replaceFirst('eqnarray', 'align')
            : name;
        _formula('\\begin{$shown}$body\\end{$shown}', display: true);
      }
      return;
    }
    if (name == 'tikzpicture') {
      final close = _environmentEnd(name);
      final body = source.substring(_at, close);
      _at = math.min(source.length, close + end.length);
      final picture = _laidOut(
        preamble.styled('\\begin{tikzpicture}$body\\end{tikzpicture}'),
      );
      _endParagraph();
      blocks.add(
        TextBlock.embedded(
          BlockEmbed.tikz(picture),
          indent: _indent,
          align: BlockAlign.center,
        ),
      );
      return;
    }
    if (name == 'math') {
      final close = _environmentEnd(name);
      _formula(source.substring(_at, close), display: false);
      _at = math.min(source.length, close + end.length);
      return;
    }
    switch (name) {
      case 'itemize' || 'enumerate' || 'description':
        _endParagraph();
        _lists.add((
          kind: name == 'enumerate'
              ? TextBlockKind.numbered
              : name == 'itemize'
              ? TextBlockKind.bulleted
              : TextBlockKind.paragraph,
          depth: _lists.length,
        ));
        final kept = (kind: _kind, indent: _indent);
        _option();
        read(stop: end);
        _endParagraph();
        _lists.removeLast();
        _kind = kept.kind;
        _indent = kept.indent;
      case 'tabular' || 'tabular*' || 'tabularx' || 'array' || 'longtable':
        _table(name);
      case 'verbatim' || 'lstlisting' || 'minted' || 'Verbatim':
        _verbatim(name);
      case 'quote' || 'quotation' || 'verse':
        _endParagraph();
        _quotes++;
        read(stop: end);
        _endParagraph();
        _quotes--;
      case 'center' || 'flushleft' || 'flushright':
        _endParagraph();
        final kept = _align;
        _align = switch (name) {
          'center' => BlockAlign.center,
          'flushright' => BlockAlign.end,
          _ => BlockAlign.start,
        };
        read(stop: end);
        _endParagraph();
        _align = kept;
      case 'abstract':
        _endParagraph();
        read(stop: end);
        _endParagraph();
      default:
        if (_statements.contains(name)) {
          _endParagraph();
          final label = _option();
          final kept = _marks;
          _marks = _marks.copyWith(bold: true);
          final word = name.replaceAll('*', '');
          _text('${word[0].toUpperCase()}${word.substring(1)}');
          if (label != null) _text(' ($label)');
          _text('.');
          _marks = kept;
          _text(' ');
          read(stop: end);
          _endParagraph();
          return;
        }
        // figure, table, minipage and the rest: what they hold.
        _option();
        read(stop: end);
    }
  }

  /// Where the `\end` closing the environment [name] begun before the
  /// reading point starts, the same environment within it counted.
  int _environmentEnd(String name) {
    final begin = '\\begin{$name}';
    final end = '\\end{$name}';
    var depth = 1;
    var at = _at;
    while (true) {
      final nextEnd = source.indexOf(end, at);
      if (nextEnd < 0) return source.length;
      final nextBegin = source.indexOf(begin, at);
      if (nextBegin >= 0 && nextBegin < nextEnd) {
        depth++;
        at = nextBegin + begin.length;
      } else if (--depth == 0) {
        return nextEnd;
      } else {
        at = nextEnd + end.length;
      }
    }
  }

  void _verbatim(String name) {
    _endParagraph();
    _option();
    if (name == 'minted') _argument();
    final close = _environmentEnd(name);
    final text = source.substring(_at, close);
    _at = math.min(source.length, close + '\\end{$name}'.length);
    final lines = text.split('\n');
    // The lines of the environment, without the empty ones it begins and
    // ends with.
    while (lines.isNotEmpty && lines.first.trim().isEmpty) {
      lines.removeAt(0);
    }
    while (lines.isNotEmpty && lines.last.trim().isEmpty) {
      lines.removeLast();
    }
    for (final line in lines) {
      blocks.add(
        TextBlock(kind: TextBlockKind.code, runs: <TextRun>[TextRun(line)]),
      );
    }
  }

  /// A table: its rows broken by `\\`, its cells by `&`, each cell's text
  /// read as text.
  void _table(String name) {
    _endParagraph();
    if (name == 'tabular*' || name == 'tabularx') _argument();
    _option();
    _argument(); // the columns
    final close = _environmentEnd(name);
    final body = source.substring(_at, close);
    _at = math.min(source.length, close + '\\end{$name}'.length);
    final rows = _split(body, r'\\')
        .map(
          (row) => row.replaceAll(
            RegExp(r'\\(hline|toprule|midrule|bottomrule)'),
            '',
          ),
        )
        .where((row) => row.trim().isNotEmpty)
        .toList();
    final lines = <TextBlock>[];
    for (final (index, row) in rows.indexed) {
      for (final (column, cell) in _split(row, '&').indexed) {
        final reader = _Reader(cell)..read();
        final cellBlocks = reader.blocks.isEmpty
            ? const <TextBlock>[TextBlock()]
            : reader.blocks;
        for (final block in cellBlocks) {
          lines.add(block.inCell(TableCell(index, column)));
        }
      }
    }
    blocks.addAll(lines);
  }

  /// [text] split at each [separator] not within braces or an
  /// environment.
  static List<String> _split(String text, String separator) {
    final parts = <String>[];
    var depth = 0;
    var start = 0;
    for (var i = 0; i < text.length; i++) {
      final char = text[i];
      if (text.startsWith(r'\begin', i)) depth++;
      if (text.startsWith(r'\end', i)) depth--;
      if (char == r'\' && !text.startsWith(separator, i)) {
        i++;
        continue;
      }
      if (char == '{') depth++;
      if (char == '}') depth--;
      if (depth == 0 && text.startsWith(separator, i)) {
        parts.add(text.substring(start, i));
        i += separator.length - 1;
        start = i + 1;
      }
    }
    parts.add(text.substring(start));
    return parts;
  }
}
