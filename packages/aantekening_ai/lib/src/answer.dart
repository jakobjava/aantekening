/// An answer as it is shown and kept: its text, and what it cites where.
library;

import 'conversation.dart';
import 'provider.dart';
import 'study.dart';

/// An answer: Markdown, each stretch drawing on a source followed by a
/// marker naming the citations it draws on, `⟦1,3⟧`, counted from one in
/// [citations].
///
/// One form for streaming, keeping and showing an answer, whichever
/// provider wrote it and however it cites.
class AiAnswer {
  const AiAnswer({this.markdown = '', this.citations = const <Citation>[]});

  static const String markerOpen = '⟦';
  static const String markerClose = '⟧';

  /// A citation marker, `⟦1,3⟧`.
  static final RegExp marker = RegExp('$markerOpen([0-9,]+)$markerClose');

  final String markdown;
  final List<Citation> citations;

  bool get isEmpty => markdown.trim().isEmpty;

  /// The text without its citation markers.
  String get plainText => markdown.replaceAll(marker, '');

  /// The citations of a marker's numbers, `1,3`.
  List<Citation> citationsOf(String numbers) => <Citation>[
    for (final n in numbers.split(','))
      if (int.tryParse(n) case final i? when i >= 1 && i <= citations.length)
        citations[i - 1],
  ];

  /// The sources cited, each once, the person's notes before the web.
  List<Citation> get sources {
    final byPage = <String, Citation>{};
    for (final citation in citations) {
      byPage.putIfAbsent(_withoutPlace(citation.uri), () => citation);
    }
    return byPage.values.toList()
      ..sort((a, b) => a.origin.index.compareTo(b.origin.index));
  }

  static String _withoutPlace(String uri) {
    final hash = uri.indexOf('#');
    return hash < 0 ? uri : uri.substring(0, hash);
  }

  Map<String, Object?> toJson() => <String, Object?>{
    'markdown': markdown,
    'citations': <Object?>[for (final c in citations) c.toJson()],
  };

  static AiAnswer fromJson(Map<String, Object?> json) => AiAnswer(
    markdown: json['markdown'] as String? ?? '',
    citations: <Citation>[
      for (final c in (json['citations'] as List<Object?>?) ?? const [])
        Citation.fromJson((c! as Map).cast<String, Object?>()),
    ],
  );
}

/// Builds an [AiAnswer] from what a provider streams.
class AnswerBuilder {
  final StringBuffer _markdown = StringBuffer();
  final List<Citation> _citations = <Citation>[];

  void add(ChatEvent event) {
    switch (event) {
      case TextDelta(:final text):
        _markdown.write(text);
      case CitedSpan(:final citations) when citations.isNotEmpty:
        final numbers = <int>{
          for (final citation in citations) _number(citation),
        };
        _markdown.write(
          '${AiAnswer.markerOpen}${numbers.join(',')}${AiAnswer.markerClose}',
        );
      case CitedSpan() || Reasoning() || Activity() || MessageDone():
        break;
    }
  }

  /// Adds [text] of the app's own, such as why an answer stopped short.
  void note(String text) => _markdown.write(text);

  int _number(Citation citation) {
    final at = _citations.indexOf(citation);
    if (at >= 0) return at + 1;
    _citations.add(citation);
    return _citations.length;
  }

  AiAnswer get answer => AiAnswer(
    markdown: _markdown.toString(),
    citations: List<Citation>.unmodifiable(_citations),
  );
}

/// The structured things an answer can hold besides its prose: each a
/// fenced block of JSON after a word saying what it is, so an answer stays
/// Markdown a person can read, and a new kind of thing is a new word.
abstract final class AnswerBlocks {
  static const String flashcards = 'flashcards';
  static const String quiz = 'quiz';

  /// A fenced block, its word and its body.
  static final RegExp fence = RegExp(
    r'```(\w+)[ \t]*\n([\s\S]*?)\n?```',
    multiLine: true,
  );

  /// The cards in a `flashcards` block's [body], or null if it holds none.
  static List<StudyCard>? cardsIn(String body) =>
      switch (_read(StudyKind.flashcards, 'cards', body)) {
        FlashcardSet(:final cards) => cards,
        _ => null,
      };

  /// The questions in a `quiz` block's [body], or null if it holds none.
  static List<QuizQuestion>? questionsIn(String body) =>
      switch (_read(StudyKind.quiz, 'questions', body)) {
        QuizSet(:final questions) => questions,
        _ => null,
      };

  /// The set of [kind] a block's [body] holds as a JSON list, under [key],
  /// citation markers left out.
  static StudySet? _read(StudyKind kind, String key, String body) =>
      StudySet.read(
        kind,
        '{"$key": ${body.replaceAll(AiAnswer.marker, '')}}',
        const <Source>[],
      );

  /// The word of the first structured block in [markdown] this build
  /// understands, or null for an answer that is only prose.
  static String? kindOf(String markdown) {
    for (final match in fence.allMatches(markdown)) {
      final word = match.group(1);
      if (word == flashcards && cardsIn(match.group(2)!) != null) return word;
      if (word == quiz && questionsIn(match.group(2)!) != null) return word;
    }
    return null;
  }
}
