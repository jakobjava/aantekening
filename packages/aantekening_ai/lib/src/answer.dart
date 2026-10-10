/// An answer as it is shown and kept: its text, and what it cites where.
library;

import 'package:meta/meta.dart';

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

  /// The whole blocks of the answer that [selected] — text selected where
  /// the answer is shown, its formulas drawn and its markers turned to
  /// numbers — lies in: from the block it starts in to the one it ends in.
  /// Null if it cannot be found in the answer.
  AnswerSection? sectionOf(String selected) {
    final blocks = AnswerSection.blocksOf(markdown);
    if (blocks.isEmpty) return null;
    // The blocks' letters, one after another, and the block each is of:
    // what the selection and the Markdown share, however each writes it.
    final letters = StringBuffer();
    final blockAt = <int>[];
    for (final (i, block) in blocks.indexed) {
      final text = _letters(
        markdown
            .substring(block.start, block.end)
            .replaceAll(marker, '')
            .replaceAll(_command, ''),
      );
      letters.write(text);
      blockAt.addAll(List<int>.filled(text.length, i));
    }
    final all = letters.toString();
    final wanted = _letters(selected);
    if (wanted.isEmpty) return null;
    final width = wanted.length < _window ? wanted.length : _window;
    // Where the selection starts: the first stretch of it that is found,
    // since a formula drawn may be selected as other letters than its
    // source; and where it ends, the last found after that.
    int? first;
    for (var at = 0; at + width <= wanted.length; at += width ~/ 2 + 1) {
      final found = all.indexOf(wanted.substring(at, at + width));
      if (found >= 0) {
        first = found;
        break;
      }
    }
    if (first == null) return null;
    var last = first + width - 1;
    for (var at = wanted.length - width; at >= 0; at -= width ~/ 2 + 1) {
      final found = all.indexOf(wanted.substring(at, at + width), first);
      if (found >= 0) {
        last = found + width - 1;
        break;
      }
    }
    return AnswerSection(
      blocks[blockAt[first]].start,
      blocks[blockAt[last]].end,
    );
  }

  /// How many letters of a selection are looked for at once.
  static const int _window = 16;

  /// A LaTeX command, whose name is not drawn.
  static final RegExp _command = RegExp(r'\\[a-zA-Z]+');

  static final RegExp _letter = RegExp(r'\p{L}', unicode: true);

  /// The letters of [text], in lower case: what it says, without how.
  static String _letters(String text) =>
      _letter.allMatches(text.toLowerCase()).map((m) => m[0]).join();

  /// [section] as the model reads it: its Markdown, without the markers.
  String textOf(AnswerSection section) =>
      markdown.substring(section.start, section.end).replaceAll(marker, '');

  /// The answer with [section] written as [part] has it instead, the
  /// citations of both numbered again from one, in the order they come,
  /// and those cited no more left out.
  AiAnswer replacing(AnswerSection section, AiAnswer part) {
    final cited = <Citation>[];
    String numbered(String text, AiAnswer of) =>
        text.replaceAllMapped(marker, (match) {
          final numbers = <int>{
            for (final citation in of.citationsOf(match[1]!))
              switch (cited.indexOf(citation)) {
                -1 => (cited..add(citation)).length,
                final i => i + 1,
              },
          };
          return numbers.isEmpty
              ? ''
              : '$markerOpen${numbers.join(',')}$markerClose';
        });
    return AiAnswer(
      markdown:
          numbered(markdown.substring(0, section.start), this) +
          numbered(part.markdown.trim(), part) +
          numbered(markdown.substring(section.end), this),
      citations: List<Citation>.unmodifiable(cited),
    );
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

/// A stretch of an answer's Markdown, from [start] to [end]: whole blocks,
/// to be written again.
@immutable
class AnswerSection {
  const AnswerSection(this.start, this.end);

  final int start;
  final int end;

  /// The blocks of [markdown], each from where it starts to where it
  /// ends: paragraphs, list items, headings, formulas on lines of their
  /// own, tables and fenced blocks — each as it would be written again.
  static List<AnswerSection> blocksOf(String markdown) {
    final blocks = <AnswerSection>[];
    int? start;
    var end = 0;
    String? closing;
    var heading = false;
    void close() {
      if (start != null) blocks.add(AnswerSection(start!, end));
      start = null;
    }

    var offset = 0;
    for (final line in markdown.split('\n')) {
      final from = offset;
      final to = from + line.length;
      offset = to + 1;
      final trimmed = line.trim();
      if (closing != null) {
        // Inside a fenced block or a formula, to its closing line.
        end = to;
        if (trimmed.startsWith(closing)) {
          closing = null;
          close();
        }
        continue;
      }
      if (trimmed.isEmpty) {
        close();
        continue;
      }
      final fence = trimmed.startsWith('```')
          ? '```'
          : trimmed == r'$$'
          ? r'$$'
          : null;
      final starts =
          fence != null ||
          heading ||
          trimmed.startsWith('#') ||
          _listItem.hasMatch(line) ||
          (trimmed.startsWith('|') && !_inTable(markdown, start));
      if (starts) close();
      start ??= from;
      end = to;
      heading = trimmed.startsWith('#');
      if (fence != null) closing = fence;
    }
    close();
    return blocks;
  }

  static final RegExp _listItem = RegExp(r'^\s*([-*+]|\d+[.)])\s');

  /// Whether the block from [start] is a table, which goes on line by line.
  static bool _inTable(String markdown, int? start) =>
      start != null && markdown.substring(start).trimLeft().startsWith('|');

  @override
  bool operator ==(Object other) =>
      other is AnswerSection && other.start == start && other.end == end;

  @override
  int get hashCode => Object.hash(start, end);

  @override
  String toString() => 'AnswerSection($start, $end)';
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
      switch (_read(StudyKind.flashcards, body)) {
        FlashcardSet(:final cards) => cards,
        _ => null,
      };

  /// The questions in a `quiz` block's [body], or null if it holds none.
  static List<QuizQuestion>? questionsIn(String body) =>
      switch (_read(StudyKind.quiz, body)) {
        QuizSet(:final questions) => questions,
        _ => null,
      };

  /// The set of [kind] a block's [body] holds, citation markers left
  /// out.
  static StudySet? _read(StudyKind kind, String body) => StudySet.read(
    kind,
    body.replaceAll(AiAnswer.marker, ''),
    const <Source>[],
  );
}
