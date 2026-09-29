/// What the AI makes to study from — a summary, flashcards, a quiz, the key
/// terms — as structured sets rather than prose, each part of them tied to
/// the sentences of the notes it comes from.
library;

import 'dart:math' as math;

import 'answer.dart';
import 'citation_markers.dart';
import 'conversation.dart';
import 'loose_json.dart';

/// A kind of study set: the form it takes, and the view it is shown in.
enum StudyKind {
  summary(
    'Summary',
    'The essentials on one sheet, each point linked to where it is in your '
        'notes.',
    'A study summary: what a student needs to understand and remember of '
        'the notes, in the order the notes have it.',
  ),
  flashcards(
    'Flashcards',
    'Cards to learn with, each shown again just before you would forget it.',
    'Flashcards to learn the notes by: one for each definition, law, '
        'formula, cause or step a test would ask about — the essentials, not '
        'every detail, and nothing twice.',
  ),
  quiz(
    'Quiz',
    'Questions to test yourself, each explained once answered.',
    'A quiz to test understanding of the notes: questions that need the '
        'ideas understood, not only remembered, from easy to hard.',
  ),
  terms(
    'Key terms',
    'The words and symbols that matter, each explained.',
    'The key terms of the notes — their technical words, symbols and units '
        '— each with what it means here.',
  ),
  text(
    'Free text',
    'Written as you describe it — prose, lists, tables — each part linked '
        'to your notes.',
    'A page to study the notes from.',
  );

  const StudyKind(this.label, this.purpose, this.idea);

  final String label;

  /// What it is for, in a sentence.
  final String purpose;

  /// What the model is asked to make, before [form] says how to write it:
  /// where a [StudyProfile] says nothing else.
  final String idea;

  /// Whether the model writes it as JSON, held to [schema], rather than
  /// as Markdown citing the notes as an answer does.
  bool get structured => this != text;

  /// How the model is asked to write a set of this kind about a [scope] —
  /// "page", "section", "notebook".
  String form(String scope) => switch (this) {
    summary =>
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
      'Answer with JSON alone, in this form:\n'
          '{"cards": [{"front": "a question, answerable in a line", '
          '"back": "the answer, short", "sources": ["1.2"]}]}\n'
          'Five to twenty cards, as many as the notes hold ideas. Each card '
          'names the passages it comes from.',
    quiz =>
      'Answer with JSON alone, in this form:\n'
          '{"questions": [{"question": "…", "options": ["…", "…", "…", "…"], '
          '"answer": 0, "explanation": "why that option is right, and the '
          'others not", "sources": ["1.2"]}]}\n'
          'Five to ten questions of four options, "answer" the index of the '
          'right one; wrong options are plausible mistakes. Each question '
          'names the passages it comes from.',
    terms =>
      'Answer with JSON alone, in this form:\n'
          r'{"terms": [{"term": "…, or a symbol like $v_0$", "meaning": "in a '
          'sentence or two", "sources": ["1.2"]}]}\n'
          'In the order the notes bring them. Each term names the passages '
          'it comes from.',
    text =>
      'Write it about this $scope in Markdown, with headings, lists and '
          'tables where they help, and cite the passages each part draws '
          'on. Say plainly where it goes beyond what the notes say.',
  };

  /// The JSON Schema of what [form] asks for, for a provider that can
  /// hold a model to it; null for [text], which is not JSON.
  Map<String, Object?>? get schema {
    Map<String, Object?> object(Map<String, Object?> properties) =>
        <String, Object?>{
          'type': 'object',
          'properties': properties,
          'required': properties.keys.toList(),
        };
    Map<String, Object?> list(Map<String, Object?> items) => <String, Object?>{
      'type': 'array',
      'items': items,
    };
    const string = <String, Object?>{'type': 'string'};
    final sources = list(string);
    return switch (this) {
      summary => object(<String, Object?>{
        'title': string,
        'gist': string,
        'sections': list(
          object(<String, Object?>{
            'heading': string,
            'points': list(
              object(<String, Object?>{'text': string, 'sources': sources}),
            ),
          }),
        ),
        'formulas': list(
          object(<String, Object?>{
            'latex': string,
            'meaning': string,
            'sources': sources,
          }),
        ),
        'beyond': list(string),
      }),
      flashcards => object(<String, Object?>{
        'cards': list(
          object(<String, Object?>{
            'front': string,
            'back': string,
            'sources': sources,
          }),
        ),
      }),
      quiz => object(<String, Object?>{
        'questions': list(
          object(<String, Object?>{
            'question': string,
            'options': list(string),
            'answer': const <String, Object?>{'type': 'integer'},
            'explanation': string,
            'sources': sources,
          }),
        ),
      }),
      terms => object(<String, Object?>{
        'terms': list(
          object(<String, Object?>{
            'term': string,
            'meaning': string,
            'sources': sources,
          }),
        ),
      }),
      StudyKind.text => null,
    };
  }
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
}

/// A set to study from, made by the AI, kept apart from the notes.
sealed class StudySet {
  const StudySet();

  StudyKind get kind;

  /// Whether it holds nothing to study.
  bool get isEmpty;

  /// How many things it holds: cards, questions, terms, points, words.
  int get size;

  Map<String, Object?> toJson();

  /// Where the set's kind is kept in its JSON.
  static const String kindKey = 'study';

  /// The set kept as [json] by [toJson], or null if it is not one.
  static StudySet? fromJson(Object? json) {
    if (json is! Map) return null;
    final kind = StudyKind.values.asNameMap()[json[kindKey]];
    if (kind == null) return null;
    return _read(kind, json, _citations);
  }

  /// The set of [kind] a model wrote as [text], its passage numbers read
  /// as citations of [sources] — or null if nothing of it can be read.
  static StudySet? read(StudyKind kind, String text, List<Source> sources) =>
      reading(kind, text, sources)?.set;

  /// The set of [kind] a model wrote as [text], as [read] has it, and
  /// whether some of it was [lost]: it could not all be read. Text still
  /// arriving, or broken off, is read as far as it goes.
  ///
  /// However the model wrote it: among prose, in a fence, wrapped in
  /// another object, its fields named its own way — the most that any
  /// JSON in the text holds of a set.
  static ({StudySet set, bool lost})? reading(
    StudyKind kind,
    String text,
    List<Source> sources,
  ) {
    // Free text is not JSON, and is read as an answer is.
    if (!kind.structured) return null;
    ({StudySet set, bool lost})? best;
    for (final (:value, :lost) in LooseJson.valuesIn(text)) {
      final set = _within(kind, value, (refs) => _cited(refs, sources));
      if (set == null) continue;
      // The fullest; of two as full, one read whole.
      final fuller = best == null || set.holdsMoreThan(best.set);
      final asFull = best != null && !best.set.holdsMoreThan(set);
      if (fuller || (asFull && best.lost && !lost)) {
        best = (set: set, lost: lost);
      }
    }
    return best;
  }

  /// Whether it holds more to study than [other]: to keep the fullest of
  /// several readings.
  bool holdsMoreThan(StudySet? other) => _weight > (other?._weight ?? 0);

  /// How much it holds, to choose the fullest of several readings by.
  int get _weight => isEmpty ? 0 : size + 1;

  /// The fullest set of [kind] that [json] reads as: itself, or what it
  /// wraps — `{"summary": {…}}` — a level or two down.
  static StudySet? _within(
    StudyKind kind,
    Object? json,
    List<Citation> Function(Object? refs) cite, {
    int depth = 0,
  }) {
    var best = _read(kind, json, cite);
    if (depth < 2) {
      final inner = switch (json) {
        final Map<Object?, Object?> map => map.values,
        final List<Object?> list => list,
        _ => const <Object?>[],
      };
      for (final value in inner) {
        if (value is! Map && value is! List) continue;
        final set = _within(kind, value, cite, depth: depth + 1);
        if (set != null && set.holdsMoreThan(best)) best = set;
      }
    }
    return best.isEmpty ? null : best;
  }

  /// The set of [kind] that [json] holds, as it is kept or as a model
  /// wrote it: a list alone for its cards, questions or terms.
  static StudySet _read(
    StudyKind kind,
    Object? json,
    List<Citation> Function(Object? refs) cite,
  ) {
    final set = _Fields.of(json, items: _Names.itemsOf(kind));
    Sourced sourced(_Fields entry, List<String> names) =>
        Sourced(entry.text(names), sources: cite(entry(_Names.sources)));
    String id(_Fields entry, int index) => switch (entry(const ['id'])) {
      final String id when id.isNotEmpty => id,
      _ => _id(index),
    };

    switch (kind) {
      case StudyKind.summary:
        List<Sourced> points(_Fields section) => <Sourced>[
          for (final point in section.list(_Names.points))
            sourced(point, _Names.text),
        ].where((p) => p.text.isNotEmpty).toList();
        return StudySummary(
          title: set.text(_Names.title),
          gist: set.text(_Names.gist),
          sections: <SummarySection>[
            for (final section in set.list(
              _Names.sections,
              bare: 'heading',
              value: 'points',
            ))
              SummarySection(
                heading: section.text(_Names.title),
                points: points(section),
              ),
            // Points with no sections round them.
            SummarySection(heading: '', points: points(set)),
          ].where((s) => s.points.isNotEmpty).toList(),
          formulas: <StudyFormula>[
            for (final formula in set.list(
              _Names.formulas,
              bare: 'latex',
              value: 'meaning',
            ))
              if (formula.text(_Names.latex) case final latex
                  when latex.isNotEmpty)
                StudyFormula(
                  latex: _bareLatex(latex),
                  meaning: formula.text(_Names.meaning),
                  sources: cite(formula(_Names.sources)),
                ),
          ],
          beyond: <String>[
            for (final line in set.list(_Names.beyond))
              if (line.text(_Names.text) case final text when text.isNotEmpty)
                text,
          ],
        );
      case StudyKind.flashcards:
        return FlashcardSet(<StudyCard>[
          for (final (i, card)
              in set
                  .list(_Names.itemsOf(kind), bare: 'front', value: 'back')
                  .indexed)
            if ((card.text(_Names.front), card.text(_Names.back)) case (
              final front,
              final back,
            ) when front.isNotEmpty && back.isNotEmpty)
              StudyCard(
                id: id(card, i),
                front: front,
                back: back,
                sources: cite(card(_Names.sources)),
              ),
        ]);
      case StudyKind.quiz:
        return QuizSet(<QuizQuestion>[
          for (final (i, question) in set.list(_Names.itemsOf(kind)).indexed)
            if (_choiceOf(question) case final choice?)
              QuizQuestion(
                id: id(question, i),
                question: choice.question,
                options: choice.options,
                answer: choice.answer,
                explanation: question.text(_Names.explanation),
                sources: cite(question(_Names.sources)),
              ),
        ]);
      case StudyKind.terms:
        return Glossary(<GlossaryTerm>[
          for (final term in set.list(
            _Names.itemsOf(kind),
            bare: 'term',
            value: 'meaning',
          ))
            if (term.text(_Names.term) case final name when name.isNotEmpty)
              GlossaryTerm(
                term: name,
                meaning: term.text(_Names.meaning),
                sources: cite(term(_Names.sources)),
              ),
        ]);
      case StudyKind.text:
        return StudyText(AiAnswer.fromJson(set._map));
    }
  }

  static final math.Random _random = math.Random();

  /// An identifier for the [index]th thing of a new set, to keep what is
  /// learnt of it by.
  static String _id(int index) =>
      '${DateTime.now().microsecondsSinceEpoch.toRadixString(36)}'
      '${_random.nextInt(1 << 20).toRadixString(36)}$index';

  /// LaTeX without the dollars or brackets a model may have put round it.
  static String _bareLatex(String latex) =>
      latex.replaceAll(RegExp(r'^(\$+|\\[(\[])|(\$+|\\[)\]])$'), '').trim();
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

/// A page written as its profile describes it: Markdown citing the notes,
/// as an answer is.
final class StudyText extends StudySet {
  const StudyText(this.answer);

  final AiAnswer answer;

  @override
  StudyKind get kind => StudyKind.text;

  @override
  bool get isEmpty => answer.isEmpty;

  /// How many words it has.
  @override
  int get size => _word.allMatches(answer.plainText).length;

  static final RegExp _word = RegExp(r'[\p{L}\p{N}]+', unicode: true);

  @override
  Map<String, Object?> toJson() => <String, Object?>{
    StudySet.kindKey: kind.name,
    ...answer.toJson(),
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

/// An object of a study set as it is kept, or as a model wrote it: each
/// field found by any of the names a model may give it — the back of a
/// card as `"back"`, `"Answer"` or `"a"` — however it cased and spaced
/// them.
extension type const _Fields._(Map<String, Object?> _map) {
  /// [json] as fields: an object's own; a list alone as the value of the
  /// first of [items]; a string or number alone as the field [bare].
  factory _Fields.of(
    Object? json, {
    String bare = 'text',
    List<String> items = const <String>[],
  }) => switch (json) {
    final Map<Object?, Object?> map => _Fields._(<String, Object?>{
      for (final MapEntry(:key, :value) in map.entries) _name('$key'): value,
    }),
    final List<Object?> list when items.isNotEmpty => _Fields._(
      <String, Object?>{items.first: list},
    ),
    String() || num() => _Fields._(<String, Object?>{bare: json}),
    _ => const _Fields._(<String, Object?>{}),
  };

  static String _name(String key) =>
      key.toLowerCase().replaceAll(RegExp(r'[^\p{L}\p{N}]', unicode: true), '');

  /// The value of the first of [names] it has.
  Object? call(List<String> names) {
    for (final name in names) {
      if (_map.containsKey(name)) return _map[name];
    }
    return null;
  }

  /// The text of the first of [names] it has, or empty.
  String text(List<String> names) => _text(this(names));

  static String _text(Object? value) => switch (value) {
    final String text => text.trim(),
    num() || bool() => '$value',
    final List<Object?> list =>
      list.map(_text).where((t) => t.isNotEmpty).join(' '),
    final Map<Object?, Object?> map => _Fields.of(map).text(_Names.text),
    _ => '',
  };

  /// The objects listed under the first of [names] it has: each a string
  /// alone as the field [bare]; and, listed as `{"Force": "mass times
  /// acceleration"}` or `[["Force", "mass times …"]]`, each name as the
  /// field [bare] and what it is given as the field [value].
  List<_Fields> list(
    List<String> names, {
    String bare = 'text',
    String? value,
  }) {
    _Fields pair(Object? name, Object? given) => switch (given) {
      final Map<Object?, Object?> map => _Fields._(<String, Object?>{
        bare: name,
        ..._Fields.of(map)._map,
      }),
      _ => _Fields._(<String, Object?>{bare: name, value!: given}),
    };
    return switch (this(names)) {
      final List<Object?> list => <_Fields>[
        for (final item in list)
          if (item case [final name, final given] when value != null)
            pair(name, given)
          else
            _Fields.of(item, bare: bare),
      ],
      final Map<Object?, Object?> map when value != null => <_Fields>[
        for (final MapEntry(:key, :value) in map.entries) pair(key, value),
      ],
      null => const <_Fields>[],
      final Object one => <_Fields>[_Fields.of(one, bare: bare)],
    };
  }
}

/// The names a model may give each field of a study set, as [_Fields]
/// writes them: the app's own first.
abstract final class _Names {
  static List<String> _words(String words) => words.split(' ');

  static final List<String> text = _words(
    'text point content statement idea description value',
  );
  static final List<String> sources = _words(
    'sources source refs references citations cites passages',
  );
  static final List<String> title = _words('title name topic subject heading');
  static final List<String> gist = _words(
    'gist overview summary tldr abstract essence introduction intro',
  );
  static final List<String> sections = _words(
    'sections parts topics chapters headings',
  );
  static final List<String> points = _words(
    'points bullets items keypoints ideas facts notes content',
  );
  static final List<String> formulas = _words('formulas formulae equations');
  static final List<String> latex = _words(
    'latex formula equation tex expression math',
  );
  static final List<String> meaning = _words(
    'meaning definition description explanation means explains',
  );
  static final List<String> beyond = _words(
    'beyond extra additional outsidenotes notinnotes furtherreading background',
  );
  static final List<String> front = _words('front question q prompt cue term');
  static final List<String> back = _words(
    'back answer a response definition explanation',
  );
  static final List<String> question = _words('question q prompt stem text');
  static final List<String> options = _words(
    'options choices answers alternatives',
  );
  static final List<String> answer = _words(
    'answer correct correctanswer correctindex correctoption '
    'answerindex solution right key',
  );
  static final List<String> explanation = _words(
    'explanation why rationale reason feedback',
  );
  static final List<String> term = _words('term word name symbol concept');

  /// The names of the list a set of [kind] is made of.
  static List<String> itemsOf(StudyKind kind) => switch (kind) {
    StudyKind.summary => sections,
    StudyKind.flashcards => _words('cards flashcards items deck'),
    StudyKind.quiz => _words('questions quiz items'),
    StudyKind.terms => _words('terms glossary keyterms items words vocabulary'),
    StudyKind.text => const <String>[],
  };
}

/// A question of a quiz, its options, and which is right.
typedef _Choice = ({String question, List<String> options, int answer});

/// The question of a quiz [entry] is, as a model wrote it: its options
/// however listed — `["…"]`, `{"A": "…"}`, `["A) …"]`, `[{"text": "…",
/// "correct": true}]` — and the right one however given: its index, its
/// letter, or its words. Null if it is not a question with options.
_Choice? _choiceOf(_Fields entry) {
  final question = entry.text(_Names.question);
  final listed = switch (entry(_Names.options)) {
    final List<Object?> list => list,
    final Map<Object?, Object?> map => map.values.toList(),
    _ => const <Object?>[],
  };
  var options = <String>[];
  int? marked;
  for (final (i, option) in listed.indexed) {
    final fields = _Fields.of(option);
    options.add(fields.text(_Names.text));
    if (fields(const ['correct', 'iscorrect', 'right']) == true) marked = i;
  }
  if (question.isEmpty || options.length < 2 || options.contains('')) {
    return null;
  }
  // Letters before the options, "A) …", only where every one has its own.
  final lettered = RegExp(r'^\(?([A-Ha-h])[).:]\s+');
  if (options.indexed.every(
    (o) => lettered.firstMatch(o.$2)?[1]?.toUpperCase() == _letter(o.$1),
  )) {
    options = <String>[
      for (final option in options) option.replaceFirst(lettered, ''),
    ];
  }
  final answer = marked ?? _answerAmong(entry(_Names.answer), options);
  return answer == null
      ? null
      : (question: question, options: options, answer: answer);
}

String _letter(int index) => String.fromCharCode(0x41 + index);

/// Which of [options] [answer] names, counted from zero: by its index —
/// from one, if it names one past the last — its letter, or its words.
int? _answerAmong(Object? answer, List<String> options) {
  int? index(int n) => n >= 0 && n < options.length
      ? n
      : n == options.length
      ? n - 1
      : null;
  switch (answer) {
    case final int n:
      return index(n);
    case [final first, ...]:
      return _answerAmong(first, options);
    case final Map<Object?, Object?> map:
      return _answerAmong(
        _Fields.of(map)(_Names.answer + _Names.text),
        options,
      );
    case final String text:
      final said = text.trim();
      if (int.tryParse(said) case final n?) return index(n);
      // "B", "b)", "Option B: …" — not the "a" of "a force".
      final letter = RegExp(
        r'^(?:[Oo]ption\s*)?\(?([A-Ha-h])(?:[).:](?:\s|$)|$)',
      ).firstMatch(said);
      if (letter != null) {
        final n = letter[1]!.toUpperCase().codeUnitAt(0) - 0x41;
        if (n < options.length) return n;
      }
      String plain(String s) => _Fields._name(s);
      final words = plain(said);
      final exact = options.indexWhere((o) => plain(o) == words);
      if (exact >= 0) return exact;
      final within = options.indexWhere(
        (o) => words.isNotEmpty && plain(o).startsWith(words),
      );
      return within >= 0 ? within : null;
    default:
      return null;
  }
}
