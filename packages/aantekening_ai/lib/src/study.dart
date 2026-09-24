/// What the AI makes to study from — a summary, flashcards, a quiz, the key
/// terms — as structured sets rather than prose, each part of them tied to
/// the sentences of the notes it comes from.
library;

import 'dart:convert';
import 'dart:math' as math;

import 'citation_markers.dart';
import 'conversation.dart';

/// A kind of study set.
enum StudyKind {
  summary(
    'Summary',
    'The essentials on one sheet, each point linked to where it is in your '
        'notes.',
  ),
  flashcards(
    'Flashcards',
    'Cards to learn with, each shown again just before you would forget it.',
  ),
  quiz('Quiz', 'Questions to test yourself, each explained once answered.'),
  terms('Key terms', 'The words and symbols that matter, each explained.');

  const StudyKind(this.label, this.purpose);

  final String label;

  /// What it is for, in a sentence.
  final String purpose;

  /// What the model is asked to write for a set of this kind about a
  /// [scope] — "page", "section", "notebook" — as JSON.
  String instructions(String scope) => switch (this) {
    summary =>
      'Write a study summary of this $scope: what a student needs to '
          'understand and remember of it, in the order the notes have it.\n'
          'Answer with JSON alone, in this form:\n'
          '{"title": "…", "gist": "the whole $scope in one or two sentences", '
          '"sections": [{"heading": "…", "points": [{"text": "one idea, in a '
          'short sentence", "sources": ["1.2"]}]}], '
          r'"formulas": [{"latex": "h_{max} = \\frac{v_0^2}{2g}", '
          '"meaning": "what it gives, and what each symbol stands for", '
          '"sources": ["1.4"]}], '
          '"beyond": ["what the notes leave out that helps to understand '
          'them, if anything"]}\n'
          'Two to five sections of two to six points. Every point and '
          'formula names the passages it comes from. Only "beyond" may hold '
          'what the notes do not say.',
    flashcards =>
      'Make flashcards to learn this $scope: one for each definition, law, '
          'formula, cause or step a test would ask about — the essentials, '
          'not every detail, and nothing twice.\n'
          'Answer with JSON alone, in this form:\n'
          '{"cards": [{"front": "a question, answerable in a line", '
          '"back": "the answer, short", "sources": ["1.2"]}]}\n'
          'Five to twenty cards, as many as the notes hold ideas. Each card '
          'names the passages it comes from.',
    quiz =>
      'Write a quiz to test understanding of this $scope: questions that '
          'need the ideas understood, not only remembered, from easy to '
          'hard.\n'
          'Answer with JSON alone, in this form:\n'
          '{"questions": [{"question": "…", "options": ["…", "…", "…", "…"], '
          '"answer": 0, "explanation": "why that option is right, and the '
          'others not", "sources": ["1.2"]}]}\n'
          'Five to ten questions of four options, "answer" the index of the '
          'right one; wrong options are plausible mistakes. Each question '
          'names the passages it comes from.',
    terms =>
      'List the key terms of this $scope — its technical words, symbols '
          'and units — each with what it means here.\n'
          'Answer with JSON alone, in this form:\n'
          r'{"terms": [{"term": "…, or a symbol like $v_0$", "meaning": "in a '
          'sentence or two", "sources": ["1.2"]}]}\n'
          'In the order the notes bring them. Each term names the passages '
          'it comes from.',
  };
}

/// Something a study set says, and the sentences of the notes it comes
/// from.
class Sourced {
  const Sourced(this.text, {this.sources = const <Citation>[]});

  final String text;
  final List<Citation> sources;

  Map<String, Object?> toJson() => <String, Object?>{
    'text': text,
    if (sources.isNotEmpty)
      'sources': <Object?>[for (final s in sources) s.toJson()],
  };

  static Sourced fromJson(Object? json) => switch (json) {
    {'text': final String text} => Sourced(
      text,
      sources: _citations((json as Map)['sources']),
    ),
    final String text => Sourced(text),
    _ => const Sourced(''),
  };
}

/// A set to study from, made by the AI, kept apart from the notes.
sealed class StudySet {
  const StudySet();

  StudyKind get kind;

  /// Whether it holds nothing to study.
  bool get isEmpty;

  /// How many things it holds: cards, questions, terms, points.
  int get size;

  Map<String, Object?> toJson();

  /// Where the set's kind is kept in its JSON.
  static const String kindKey = 'study';

  /// The set kept as [json] by [toJson], or null if it is not one.
  static StudySet? fromJson(Object? json) {
    if (json is! Map) return null;
    final kind = StudyKind.values.asNameMap()[json[kindKey]];
    if (kind == null) return null;
    return _read(kind, json.cast<String, Object?>(), _citations);
  }

  /// The set of [kind] a model wrote as [text], its passage numbers read
  /// as citations of [sources] — or null if nothing of it can be read.
  /// With [draft], text still arriving is read as far as it goes.
  static StudySet? read(
    StudyKind kind,
    String text,
    List<Source> sources, {
    bool draft = false,
  }) {
    final json = StudyJson.decode(text, draft: draft);
    if (json is! Map) return null;
    final set = _read(
      kind,
      json.cast<String, Object?>(),
      (refs) => _cited(refs, sources),
    );
    return set.isEmpty ? null : set;
  }

  static StudySet _read(
    StudyKind kind,
    Map<String, Object?> json,
    List<Citation> Function(Object? refs) cite,
  ) {
    List<Map<String, Object?>> list(String key) => <Map<String, Object?>>[
      for (final entry in (json[key] as List<Object?>?) ?? const [])
        if (entry is Map) entry.cast<String, Object?>(),
    ];
    String text(Object? value) => value is String ? value.trim() : '';
    Sourced sourced(Map<String, Object?> entry, String key) =>
        Sourced(text(entry[key]), sources: cite(entry['sources']));

    switch (kind) {
      case StudyKind.summary:
        return StudySummary(
          title: text(json['title']),
          gist: text(json['gist']),
          sections: <SummarySection>[
            for (final section in list('sections'))
              SummarySection(
                heading: text(section['heading']),
                points: <Sourced>[
                  for (final point
                      in (section['points'] as List<Object?>?) ?? const [])
                    if (point is Map)
                      sourced(point.cast<String, Object?>(), 'text')
                    else if (point is String && point.trim().isNotEmpty)
                      Sourced(point.trim()),
                ].where((p) => p.text.isNotEmpty).toList(),
              ),
          ].where((s) => s.points.isNotEmpty).toList(),
          formulas: <StudyFormula>[
            for (final formula in list('formulas'))
              if (text(formula['latex']).isNotEmpty)
                StudyFormula(
                  latex: _bareLatex(text(formula['latex'])),
                  meaning: text(formula['meaning']),
                  sources: cite(formula['sources']),
                ),
          ],
          beyond: <String>[
            for (final line in (json['beyond'] as List<Object?>?) ?? const [])
              if (line is String && line.trim().isNotEmpty) line.trim(),
          ],
        );
      case StudyKind.flashcards:
        return FlashcardSet(<StudyCard>[
          for (final (i, card) in list('cards').indexed)
            if (text(card['front']).isNotEmpty && text(card['back']).isNotEmpty)
              StudyCard(
                id: card['id'] is String ? card['id']! as String : _id(i),
                front: text(card['front']),
                back: text(card['back']),
                sources: cite(card['sources']),
              ),
        ]);
      case StudyKind.quiz:
        return QuizSet(<QuizQuestion>[
          for (final (i, question) in list('questions').indexed)
            if (question
                case {
                  'question': final String asked,
                  'options': final List<Object?> options,
                  'answer': final int answer,
                }
                when options.length >= 2 &&
                    answer >= 0 &&
                    answer < options.length)
              QuizQuestion(
                id: question['id'] is String
                    ? question['id']! as String
                    : _id(i),
                question: asked.trim(),
                options: <String>[for (final o in options) '$o'.trim()],
                answer: answer,
                explanation: text(question['explanation']),
                sources: cite(question['sources']),
              ),
        ]);
      case StudyKind.terms:
        return Glossary(<GlossaryTerm>[
          for (final term in list('terms'))
            if (text(term['term']).isNotEmpty)
              GlossaryTerm(
                term: text(term['term']),
                meaning: text(term['meaning']),
                sources: cite(term['sources']),
              ),
        ]);
    }
  }

  static final math.Random _random = math.Random();

  /// An identifier for the [index]th thing of a new set, to keep what is
  /// learnt of it by.
  static String _id(int index) =>
      '${DateTime.now().microsecondsSinceEpoch.toRadixString(36)}'
      '${_random.nextInt(1 << 20).toRadixString(36)}$index';

  /// LaTeX without the dollars a model may have put round it.
  static String _bareLatex(String latex) =>
      latex.replaceAll(RegExp(r'^\$+|\$+$'), '').trim();
}

/// A summary: the gist, the ideas under headings, the formulas, and what
/// the notes leave out.
final class StudySummary extends StudySet {
  const StudySummary({
    this.title = '',
    this.gist = '',
    this.sections = const <SummarySection>[],
    this.formulas = const <StudyFormula>[],
    this.beyond = const <String>[],
  });

  final String title;
  final String gist;
  final List<SummarySection> sections;
  final List<StudyFormula> formulas;

  /// What the model adds that the notes do not say, kept apart.
  final List<String> beyond;

  @override
  StudyKind get kind => StudyKind.summary;

  @override
  bool get isEmpty => sections.isEmpty && formulas.isEmpty && gist.isEmpty;

  @override
  int get size =>
      sections.fold(0, (sum, s) => sum + s.points.length) + formulas.length;

  @override
  Map<String, Object?> toJson() => <String, Object?>{
    StudySet.kindKey: kind.name,
    'title': title,
    'gist': gist,
    'sections': <Object?>[
      for (final section in sections)
        <String, Object?>{
          'heading': section.heading,
          'points': <Object?>[for (final p in section.points) p.toJson()],
        },
    ],
    'formulas': <Object?>[
      for (final formula in formulas)
        <String, Object?>{
          'latex': formula.latex,
          'meaning': formula.meaning,
          if (formula.sources.isNotEmpty)
            'sources': <Object?>[for (final s in formula.sources) s.toJson()],
        },
    ],
    'beyond': beyond,
  };
}

class SummarySection {
  const SummarySection({required this.heading, required this.points});

  final String heading;
  final List<Sourced> points;
}

class StudyFormula {
  const StudyFormula({
    required this.latex,
    required this.meaning,
    this.sources = const <Citation>[],
  });

  final String latex;

  /// What it gives, and what its symbols stand for.
  final String meaning;
  final List<Citation> sources;
}

/// A card to learn: a question on the front, its answer on the back.
class StudyCard {
  const StudyCard({
    required this.id,
    required this.front,
    required this.back,
    this.sources = const <Citation>[],
  });

  /// What is learnt of it is kept by.
  final String id;
  final String front;
  final String back;
  final List<Citation> sources;

  StudyCard copyWith({String? front, String? back}) => StudyCard(
    id: id,
    front: front ?? this.front,
    back: back ?? this.back,
    sources: sources,
  );

  Map<String, Object?> toJson() => <String, Object?>{
    'id': id,
    'front': front,
    'back': back,
    if (sources.isNotEmpty)
      'sources': <Object?>[for (final s in sources) s.toJson()],
  };
}

final class FlashcardSet extends StudySet {
  const FlashcardSet(this.cards);

  final List<StudyCard> cards;

  /// This set with the identities of [earlier]'s cards on the cards that
  /// ask the same, so what was learnt of them carries over when a set is
  /// made again or added to.
  FlashcardSet keepingIdsOf(FlashcardSet earlier) {
    final ids = <String, String>{
      for (final card in earlier.cards) _key(card.front): card.id,
    };
    return FlashcardSet(<StudyCard>[
      for (final card in cards)
        switch (ids[_key(card.front)]) {
          final id? => StudyCard(
            id: id,
            front: card.front,
            back: card.back,
            sources: card.sources,
          ),
          null => card,
        },
    ]);
  }

  /// [earlier]'s cards and then this set's that ask something else.
  FlashcardSet addedTo(FlashcardSet earlier) {
    final asked = <String>{for (final card in earlier.cards) _key(card.front)};
    return FlashcardSet(<StudyCard>[
      ...earlier.cards,
      for (final card in cards)
        if (asked.add(_key(card.front))) card,
    ]);
  }

  static String _key(String front) => front.toLowerCase().replaceAll(
    RegExp(r'[^\p{L}\p{N}]+', unicode: true),
    '',
  );

  @override
  StudyKind get kind => StudyKind.flashcards;

  @override
  bool get isEmpty => cards.isEmpty;

  @override
  int get size => cards.length;

  @override
  Map<String, Object?> toJson() => <String, Object?>{
    StudySet.kindKey: kind.name,
    'cards': <Object?>[for (final card in cards) card.toJson()],
  };
}

/// A question of a quiz, and which of its options is right.
class QuizQuestion {
  const QuizQuestion({
    required this.id,
    required this.question,
    required this.options,
    required this.answer,
    this.explanation = '',
    this.sources = const <Citation>[],
  });

  final String id;
  final String question;
  final List<String> options;

  /// The right option, counted from zero.
  final int answer;
  final String explanation;
  final List<Citation> sources;

  Map<String, Object?> toJson() => <String, Object?>{
    'id': id,
    'question': question,
    'options': options,
    'answer': answer,
    'explanation': explanation,
    if (sources.isNotEmpty)
      'sources': <Object?>[for (final s in sources) s.toJson()],
  };
}

final class QuizSet extends StudySet {
  const QuizSet(this.questions);

  final List<QuizQuestion> questions;

  @override
  StudyKind get kind => StudyKind.quiz;

  @override
  bool get isEmpty => questions.isEmpty;

  @override
  int get size => questions.length;

  @override
  Map<String, Object?> toJson() => <String, Object?>{
    StudySet.kindKey: kind.name,
    'questions': <Object?>[for (final q in questions) q.toJson()],
  };
}

/// A key term, and what it means here.
class GlossaryTerm {
  const GlossaryTerm({
    required this.term,
    required this.meaning,
    this.sources = const <Citation>[],
  });

  /// The word, or a symbol as `$v_0$`.
  final String term;
  final String meaning;
  final List<Citation> sources;

  Map<String, Object?> toJson() => <String, Object?>{
    'term': term,
    'meaning': meaning,
    if (sources.isNotEmpty)
      'sources': <Object?>[for (final s in sources) s.toJson()],
  };
}

/// The key terms of what it is about.
final class Glossary extends StudySet {
  const Glossary(this.terms);

  final List<GlossaryTerm> terms;

  @override
  StudyKind get kind => StudyKind.terms;

  @override
  bool get isEmpty => terms.isEmpty;

  @override
  int get size => terms.length;

  @override
  Map<String, Object?> toJson() => <String, Object?>{
    StudySet.kindKey: kind.name,
    'terms': <Object?>[for (final term in terms) term.toJson()],
  };
}

/// The citations kept as [json], or none.
List<Citation> _citations(Object? json) => <Citation>[
  for (final entry in (json as List<Object?>?) ?? const [])
    if (entry is Map) Citation.fromJson(entry.cast<String, Object?>()),
];

/// The citations of passage numbers a model wrote, `["1.2", "3"]` or
/// `"[1.2][1.3]"`, of [sources]; numbers that name nothing are left out.
List<Citation> _cited(Object? refs, List<Source> sources) {
  final text = switch (refs) {
    final List<Object?> list => list.join(','),
    final Object value => '$value',
    null => '',
  };
  final citations = <Citation>[];
  for (final match in RegExp(r'\d{1,4}(?:\.\d{1,4})?').allMatches(text)) {
    final citation = CitationMarkers.resolve(match[0]!, sources);
    if (citation != null && !citations.contains(citation)) {
      citations.add(citation);
    }
  }
  return citations;
}

/// Reading the JSON a model writes: from among what it wraps it in, with
/// LaTeX whose backslashes it did not double, and, while it is still being
/// written, as far as it goes.
abstract final class StudyJson {
  /// The JSON value in [text], or null if there is none. With [draft], an
  /// unfinished value is closed where it breaks off.
  static Object? decode(String text, {bool draft = false}) {
    final start = text.indexOf('{');
    if (start < 0) return null;
    final end = text.lastIndexOf('}');
    var json = draft
        ? close(text.substring(start))
        : text.substring(start, end < start ? text.length : end + 1);
    json = escapeLatex(json);
    try {
      return jsonDecode(json);
    } on FormatException {
      return draft ? null : _lenient(json);
    }
  }

  /// [json] with trailing commas taken out, which models leave in.
  static Object? _lenient(String json) {
    try {
      return jsonDecode(
        json.replaceAllMapped(RegExp(r',(\s*[}\]])'), (m) => m[1]!),
      );
    } on FormatException {
      return null;
    }
  }

  /// LaTeX commands the escapes of JSON would swallow: `\frac` read as a
  /// form feed and "rac", `\theta` as a tab and "heta".
  static const Set<String> _swallowed = <String>{
    'frac',
    'tfrac',
    'dfrac',
    'theta',
    'Theta',
    'tau',
    'times',
    'text',
    'textbf',
    'textit',
    'to',
    'top',
    'tilde',
    'nu',
    'nabla',
    'neq',
    'ne',
    'not',
    'ni',
    'newline',
    'beta',
    'bar',
    'begin',
    'bigl',
    'bigr',
    'big',
    'Big',
    'binom',
    'bmod',
    'boldsymbol',
    'bf',
    'bullet',
    'rho',
    'right',
    'rightarrow',
    'Rightarrow',
    'rangle',
    'rm',
    'rceil',
    'rfloor',
    'forall',
    'frown',
    'flat',
    'triangle',
    'therefore',
    'tan',
    'tanh',
    'textrm',
    'nolimits',
    'neg',
    'nleq',
    'ngeq',
    'notin',
    'nearrow',
    'searrow',
    'rVert',
    'rvert',
    'Rho',
    'boxed',
    'breve',
    'backslash',
    'because',
    'textstyle',
    'displaystyle',
    'mathrm',
    'mathbf',
    'underline',
    'uparrow',
    'Uparrow',
    'upsilon',
    'Upsilon',
  };

  /// [json] with the backslashes of LaTeX in its strings doubled where a
  /// model wrote them single: `"$\frac{a}{b}$"` as `"$\\frac{a}{b}$"`.
  static String escapeLatex(String json) {
    final out = StringBuffer();
    var inString = false;
    for (var i = 0; i < json.length; i++) {
      final char = json[i];
      if (!inString) {
        if (char == '"') inString = true;
        out.write(char);
        continue;
      }
      if (char == '"') {
        inString = false;
        out.write(char);
        continue;
      }
      if (char != r'\' || i + 1 >= json.length) {
        out.write(char);
        continue;
      }
      final next = json[i + 1];
      var word = i + 1;
      while (word < json.length && _isLetter(json.codeUnitAt(word))) {
        word++;
      }
      final command = json.substring(i + 1, word);
      final escape = switch (next) {
        '"' || r'\' || '/' => true,
        'u' => RegExp(r'^u[0-9a-fA-F]{4}').hasMatch(json.substring(i + 1)),
        'b' || 'f' || 'n' || 'r' || 't' => !_swallowed.contains(command),
        _ => false,
      };
      if (escape) {
        // A JSON escape: kept as it is, with what it escapes.
        out
          ..write(char)
          ..write(next);
        i++;
      } else {
        out.write(r'\\');
      }
    }
    return out.toString();
  }

  static bool _isLetter(int unit) =>
      (unit >= 0x41 && unit <= 0x5A) || (unit >= 0x61 && unit <= 0x7A);

  /// [json] broken off part way, closed: an unfinished string, key or
  /// value dropped, and the objects and lists open closed — so what is
  /// there so far can be read.
  static String close(String json) {
    final open = <String>[];
    var inString = false;
    var inKey = false;
    var escaped = false;
    // What came last outside strings and spaces, to tell a key from a value.
    var last = '';
    // Where the text was last whole, after a complete value, and what was
    // open there, to cut it and close it.
    var whole = 0;
    var wholeOpen = const <String>[];
    void mark(int at) {
      if (_endsValue(json, at)) {
        whole = at;
        wholeOpen = List<String>.of(open);
      }
    }

    for (var i = 0; i < json.length; i++) {
      final char = json[i];
      if (inString) {
        if (escaped) {
          escaped = false;
        } else if (char == r'\') {
          escaped = true;
        } else if (char == '"') {
          inString = false;
          last = '"';
          if (!inKey) mark(i + 1);
        }
        continue;
      }
      if (char.trim().isEmpty) continue;
      switch (char) {
        case '"':
          inString = true;
          inKey = open.lastOrNull == '}' && (last == '{' || last == ',');
        case '{':
          open.add('}');
        case '[':
          open.add(']');
        case '}' || ']':
          if (open.isNotEmpty) open.removeLast();
          mark(i + 1);
        default:
          // The last letter of a number, true, false or null.
          if (_valueEnds.contains(char)) mark(i + 1);
      }
      last = char;
    }
    return json.substring(0, whole) + wholeOpen.reversed.join();
  }

  static const Set<String> _valueEnds = <String>{
    '0',
    '1',
    '2',
    '3',
    '4',
    '5',
    '6',
    '7',
    '8',
    '9',
    'e',
    'l',
  };

  /// Whether a value ending before [at] of [json] is followed, past spaces,
  /// by what may follow a value — or nothing yet — and is not a key.
  static bool _endsValue(String json, int at) {
    final rest = json.substring(at).trimLeft();
    return rest.isEmpty || rest[0] == ',' || rest[0] == '}' || rest[0] == ']';
  }
}
