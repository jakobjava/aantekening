import 'package:aantekening_ai/aantekening_ai.dart';
import 'package:test/test.dart';

import 'agent_test.dart' show ScriptedProvider, notes, section;

const Source page = Source(
  uri: 'aantekening://page/p1',
  title: 'Vertical throw',
  origin: SourceOrigin.notes,
  passages: <SourcePassage>[
    SourcePassage(
      'It slows down.',
      uri: 'aantekening://page/p1#element=b&block=0&from=0&to=14',
    ),
    SourcePassage(
      'At the top it stops.',
      uri: 'aantekening://page/p1#element=b&block=0&from=15&to=35',
      follows: true,
    ),
  ],
);

void main() {
  group('study JSON', () {
    test('doubles the backslashes of LaTeX a model wrote single, and keeps '
        'the escapes of JSON', () {
      const written = r'{"a": "$\frac{v^2}{2g}$ and \theta\n\"x\" \alpha"}';
      final json = StudyJson.decode(written)! as Map;
      expect(json['a'], '\$\\frac{v^2}{2g}\$ and \\theta\n"x" \\alpha');
    });

    test('reads what a model wraps its JSON in, and trailing commas', () {
      final json = StudyJson.decode('Here:\n```json\n{"cards": [1, 2,],}\n```');
      expect(json, <String, Object?>{
        'cards': <Object?>[1, 2],
      });
    });

    test('reads a draft as far as it is whole', () {
      const draft =
          '{"cards": [{"front": "Why?", "back": "Because."}, '
          '{"front": "How';
      expect(StudyJson.decode(draft, draft: true), <String, Object?>{
        'cards': <Object?>[
          <String, Object?>{'front': 'Why?', 'back': 'Because.'},
        ],
      });
      // A key without its value yet is left out.
      expect(
        StudyJson.decode('{"title": "T", "gi', draft: true),
        <String, Object?>{'title': 'T'},
      );
    });
  });

  group('study sets', () {
    test('tie each thing to the sentences it comes from', () {
      final set =
          StudySet.read(
                StudyKind.flashcards,
                '{"cards": [{"front": "What happens at the top?", '
                '"back": "It stops.", "sources": ["1.2", "9.9"]}]}',
                const <Source>[page],
              )!
              as FlashcardSet;
      final card = set.cards.single;
      expect(card.sources.single.uri, page.passages[1].uri);
      expect(card.sources.single.quote, 'At the top it stops.');
      expect(card.id, isNotEmpty);

      // Kept and read back as it was.
      final kept = StudySet.fromJson(set.toJson())! as FlashcardSet;
      expect(kept.cards.single.id, card.id);
      expect(kept.cards.single.sources.single.uri, page.passages[1].uri);
    });

    test('a summary keeps its sections, formulas and what goes beyond the '
        'notes apart', () {
      final summary =
          StudySet.read(
                StudyKind.summary,
                r'''
{"title": "Throw", "gist": "Up and down.",
 "sections": [{"heading": "Motion", "points": [{"text": "It slows.", "sources": ["1.1"]}, "It stops."]}],
 "formulas": [{"latex": "$h = \frac{v^2}{2g}$", "meaning": "height", "sources": ["1.2"]}],
 "beyond": ["Air slows it more."]}''',
                const <Source>[page],
              )!
              as StudySummary;
      expect(summary.sections.single.points.map((p) => p.text), <String>[
        'It slows.',
        'It stops.',
      ]);
      expect(summary.formulas.single.latex, r'h = \frac{v^2}{2g}');
      expect(summary.beyond, <String>['Air slows it more.']);
      final kept = StudySet.fromJson(summary.toJson())! as StudySummary;
      expect(kept.formulas.single.sources.single.quote, 'At the top it stops.');
    });

    test('are made from the notes, shown as they are written', () async {
      final provider = ScriptedProvider(<List<ChatEvent>>[
        <ChatEvent>[
          const TextDelta('{"terms": [{"term": "Force", "meaning": "mass '),
          const TextDelta(
            'times acceleration", "sources": ["1.1"]}, {"term": "Spe',
          ),
          const TextDelta('ed", "meaning": "distance over time"}]}'),
          const MessageDone(
            ChatMessage(ChatRole.assistant, <ChatPart>[]),
            stop: StopReason.done,
          ),
        ],
      ]);
      final progress = await NoteAgent(
        provider: provider,
        model: 'm',
        reader: notes,
      ).make(StudyKind.terms, scope: section).toList();
      final drafts = progress
          .map((p) => p.study?.size)
          .whereType<int>()
          .toSet();
      expect(drafts, containsAll(<int>[1, 2]), reason: 'shown as it came');
      final terms = (progress.last.study! as Glossary).terms;
      expect(terms.map((t) => t.term), <String>['Force', 'Speed']);
      expect(terms.first.sources.single.title, 'Speed');
      final asked = provider.asked.single;
      expect(asked.tools, isEmpty);
      expect(asked.messages.single.text, contains('[1.1] Speed is distance'));
    });
  });

  group('spaced repetition', () {
    final now = DateTime(2026, 9, 1, 12);

    test('learns a new card in minutes, then reviews it in days, further '
        'apart each time it is remembered', () {
      var card = CardReview.fresh(now);
      expect(card.next(Grade.again), const Duration(minutes: 1));
      card = card.after(Grade.good, now);
      expect(card.learning, isTrue);
      expect(card.due, now.add(const Duration(minutes: 10)));
      card = card.after(Grade.good, now);
      expect(card.learning, isFalse);
      expect(card.interval, const Duration(days: 1));
      card = card.after(Grade.good, now);
      expect(card.interval.inHours, 60, reason: 'a day times the ease');
      expect(card.next(Grade.easy) > card.next(Grade.good), isTrue);
    });

    test('a card forgotten is learnt again, and comes more often', () {
      var card = CardReview.fresh(now).after(Grade.easy, now);
      expect(card.interval, const Duration(days: 4));
      card = card.after(Grade.again, now);
      expect(card.learning, isTrue);
      expect(card.lapses, 1);
      expect(card.ease, lessThan(CardReview.startingEase));
      expect(CardReview.fromJson(card.toJson()).ease, card.ease);
    });

    test('says a gap as a person would', () {
      expect(describeGap(const Duration(minutes: 10)), '10 min');
      expect(describeGap(const Duration(days: 1)), '1 day');
      expect(describeGap(const Duration(days: 60)), '2 mo');
    });
  });
}
