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
  group('loose JSON', () {
    Object? read(String text) => LooseJson.valuesIn(text).single.value;

    test('keeps the backslashes of LaTeX a model wrote single, and the '
        'escapes of JSON', () {
      const written = r'{"a": "$\frac{v^2}{2g}$ and \theta\n\"x\" \alpha"}';
      expect(read(written), <String, Object?>{
        'a': '\$\\frac{v^2}{2g}\$ and \\theta\n"x" \\alpha',
      });
      // In mathematics every backslash is LaTeX's; outside, a newline.
      expect(read(r'{"a": "$\nabla \neq \tau$\nNext"}'), <String, Object?>{
        'a': '\$\\nabla \\neq \\tau\$\nNext',
      });
    });

    test('reads it from among prose, fences and what comes after', () {
      final values = LooseJson.valuesIn(
        'Here it is:\n```json\n{"cards": [1, 2,],}\n```\n'
        'I hope {this} helps. {"more": true}',
      );
      expect(values.map((v) => v.value), <Object?>[
        <String, Object?>{
          'cards': <Object?>[1, 2],
        },
        <String, Object?>{'more': true},
      ]);
    });

    test('keeps quotes inside strings that do not end them', () {
      expect(
        read('{"a": "der sogenannte „Luftwiderstand" bremst", "b": "don\'t"}'),
        <String, Object?>{
          'a': 'der sogenannte „Luftwiderstand" bremst',
          'b': "don't",
        },
      );
      expect(
        read('{"a": "he said "no", then left", "b": 1}'),
        <String, Object?>{'a': 'he said "no", then left', 'b': 1},
      );
    });

    test('reads what is not quite JSON', () {
      expect(
        read('''
{
  // a comment
  title: 'Throw',
  "items": ["a" "b"]
  "done": True, "none": None, "letter": B,
  "ref": [1.10, 2]
}'''),
        <String, Object?>{
          'title': 'Throw',
          'items': <Object?>['a', 'b'],
          'done': true,
          'none': null,
          'letter': 'B',
          // As written: passage 10, not 1.1.
          'ref': <Object?>['1.10', 2],
        },
      );
    });

    test('reads what is still coming as far as it goes', () {
      const draft =
          '{"cards": [{"front": "Why?", "back": "Because."}, '
          '{"front": "How';
      final (:value, :lost) = LooseJson.valuesIn(draft).single;
      expect(value, <String, Object?>{
        'cards': <Object?>[
          <String, Object?>{'front': 'Why?', 'back': 'Because.'},
          <String, Object?>{},
        ],
      });
      expect(lost, isFalse, reason: 'only not all there yet');
      // A key without its value yet, or a LaTeX command half there, is
      // left out.
      expect(read('{"title": "T", "gi'), <String, Object?>{'title': 'T'});
      expect(read(r'{"title": "T", "latex": "\fr'), <String, Object?>{
        'title': 'T',
      });
    });

    test('says when something could not be read', () {
      final (:value, :lost) = LooseJson.valuesIn('{"a": [1, 2} and on').first;
      expect(value, <String, Object?>{
        'a': <Object?>[1, 2],
      });
      expect(lost, isTrue);
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

    test('are read however a model wrote them', () {
      StudySet? read(StudyKind kind, String text) =>
          StudySet.read(kind, text, const <Source>[page]);

      // A list alone, other names, a fence, and prose after with braces.
      final cards =
          read(StudyKind.flashcards, '''
Sure! Here are your cards:
```json
[{"Question": "Why?", "Answer": "Because.", "source": "[1.2]"}]
```
Let me know if you want {more}.''')!
              as FlashcardSet;
      expect(cards.cards.single.back, 'Because.');
      expect(cards.cards.single.sources.single.quote, 'At the top it stops.');

      // Options by letter, the answer as a letter; labelled options, the
      // answer as words; an option marked right; an answer counted from
      // one.
      final quiz =
          read(StudyKind.quiz, '''
{"quiz": {"questions": [
  {"question": "One?", "options": {"A": "x", "B": "y"}, "answer": "B"},
  {"q": "Two?", "choices": ["A) up", "B) down"], "correct": "down"},
  {"question": "Three?", "options": [{"text": "a"}, {"text": "b", "correct": true}]},
  {"question": "Four?", "options": ["a", "b", "c"], "answer": 3}
]}}''')!
              as QuizSet;
      expect(quiz.questions.map((q) => q.answer), <int>[1, 1, 1, 2]);
      expect(quiz.questions[1].options, <String>['up', 'down']);

      // Terms as an object of what each means.
      final terms =
          read(
                StudyKind.terms,
                '{"terms": {"Force": "Mass times '
                'acceleration.", "Work": "Force along a way."}}',
              )!
              as Glossary;
      expect(terms.terms.map((t) => t.meaning), <String>[
        'Mass times acceleration.',
        'Force along a way.',
      ]);

      // Wrapped, its keys cased their own way, points and a formula as
      // bare strings.
      final summary =
          read(
                StudyKind.summary,
                r'''
{"Summary": {"Title": "Throw", "Sections": [{"Heading": "Motion",
 "Points": ["It slows.", "It stops."]}], "Formulas": ["\(h = \frac{v^2}{2g}\)"]}}''',
              )!
              as StudySummary;
      expect(summary.title, 'Throw');
      expect(summary.sections.single.points.length, 2);
      expect(summary.formulas.single.latex, r'h = \frac{v^2}{2g}');
    });

    test('as it streams, never shows less than it did', () {
      const written = r'''
```json
{"title": "Wurf", "gist": "Zwei Bewegungen, überlagert.",
 "sections": [
  {"heading": "Waagerecht", "points": [
    {"text": "In $x$ gleichförmig mit $v_0$.", "sources": ["1.1"]},
    {"text": "Der sogenannte „Luftwiderstand" bremst.", "sources": ["1.2"]}]},
  {"heading": "Senkrecht", "points": [
    {"text": "Freier Fall: $y = \frac{1}{2} g t^2$.", "sources": [1.2]},
    "Die Bahn ist eine Parabel."]}],
 "formulas": [{"latex": "h = \frac{v_0^2 \sin^2\alpha}{2g}", "meaning": "Wurfhöhe", "sources": ["1.2"]}],
 "beyond": ["Mit Luftwiderstand ist die Bahn keine Parabel."]}
```
Viel Erfolg beim Lernen! {Ende}''';
      var shown = 0;
      for (var end = 1; end <= written.length; end++) {
        final size =
            StudySet.read(
              StudyKind.summary,
              written.substring(0, end),
              const <Source>[page],
            )?.size ??
            0;
        expect(size, greaterThanOrEqualTo(shown), reason: 'at $end');
        shown = size;
      }
      final summary =
          StudySet.read(StudyKind.summary, written, const <Source>[page])!
              as StudySummary;
      expect(shown, 5);
      expect(
        summary.sections.first.points.last.text,
        'Der sogenannte „Luftwiderstand" bremst.',
      );
      expect(summary.sections.last.points.first.text, contains(r'\frac{1}{2}'));
      expect(summary.formulas.single.latex, contains(r'\sin^2\alpha'));
    });

    test('of several, the fullest is read', () {
      final set =
          StudySet.read(
                StudyKind.terms,
                '{"terms": [{"term": "A", "meaning": "a"}]}\n'
                'Or, better:\n'
                '{"terms": [{"term": "A", "meaning": "a"}, '
                '{"term": "B", "meaning": "b"}]}',
                const <Source>[],
              )!
              as Glossary;
      expect(set.terms.length, 2);
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
      ).make(StudyProfile.original(StudyKind.terms), scope: section).toList();
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
      expect(asked.answerSchema, StudyKind.terms.schema);
    });

    test('says what they cost as they come, and once made', () async {
      const price = ModelPrice(input: 1, output: 10);
      final provider = ScriptedProvider(
        <List<ChatEvent>>[
          <ChatEvent>[
            const TextDelta('{"terms": [{"term": "Force", "meaning": "m a"}]}'),
            const MessageDone(
              ChatMessage(ChatRole.assistant, <ChatPart>[]),
              stop: StopReason.done,
              usage: Usage(input: 2000000, output: 100000),
            ),
          ],
        ],
        capabilities: const ModelCapabilities(
          contextTokens: 100000,
          price: price,
        ),
      );
      final progress = await NoteAgent(
        provider: provider,
        model: 'm',
        reader: notes,
      ).make(StudyProfile.original(StudyKind.terms), scope: section).toList();
      final writing = progress.firstWhere((p) => p.stage == AgentStage.writing);
      expect(writing.cost, greaterThan(0), reason: 'reckoned while it comes');
      expect(
        progress.last.cost,
        closeTo(3, 1e-9),
        reason: r'$2 read, $1 written',
      );
    });

    /// What making terms comes to when the model writes [first], and
    /// [then] when asked again: the progress, and what it was asked.
    Future<(List<AgentProgress>, List<ChatRequest>)> make(
      List<ChatEvent> first, [
      List<ChatEvent> then = const <ChatEvent>[],
    ]) async {
      const done = MessageDone(
        ChatMessage(ChatRole.assistant, <ChatPart>[]),
        stop: StopReason.done,
      );
      final provider = ScriptedProvider(<List<ChatEvent>>[
        <ChatEvent>[...first, done],
        <ChatEvent>[...then, done],
      ]);
      final progress = await NoteAgent(
        provider: provider,
        model: 'm',
        reader: notes,
      ).make(StudyProfile.original(StudyKind.terms), scope: section).toList();
      return (progress, provider.asked);
    }

    const force = '{"term": "Force", "meaning": "mass times acceleration"}';
    const speed = '{"term": "Speed", "meaning": "distance over time"}';

    test('what a model writes after the set leaves it whole', () async {
      final (progress, asked) = await make(<ChatEvent>[
        const TextDelta('{"terms": [$force, $speed]}\n\n'),
        const TextDelta('Hope this helps! {"note": "none"}'),
      ]);
      expect(progress.last.study!.size, 2);
      expect(asked.length, 1);
    });

    test('a set written into the reasoning is found there', () async {
      final (progress, asked) = await make(<ChatEvent>[
        const Reasoning('Let me see.\n{"terms": [$force]}'),
      ]);
      expect(progress.last.study!.size, 1);
      expect(asked.length, 1);
    });

    test('what cannot be read, the model is asked to put in order', () async {
      final (progress, asked) = await make(
        <ChatEvent>[const TextDelta('- **Force**: mass times acceleration')],
        <ChatEvent>[const TextDelta('{"terms": [$force]}')],
      );
      expect((progress.last.study! as Glossary).terms.single.term, 'Force');
      expect(asked.length, 2);
      expect(asked.last.messages.single.text, contains('**Force**'));
      expect(asked.last.answerSchema, StudyKind.terms.schema);
      expect(
        progress.map((p) => p.activity),
        contains('m is putting the key terms in order'),
      );
    });

    test('what was shown is kept, whatever comes of asking again', () async {
      final (progress, asked) = await make(
        <ChatEvent>[const TextDelta('{"terms": [$force, $speed} oops ]}')],
        <ChatEvent>[const TextDelta('I cannot do that.')],
      );
      expect(asked.length, 2, reason: 'not all of it could be read');
      expect(progress.last.study!.size, 2);
    });

    test('a model that writes nothing says so', () async {
      await expectLater(
        make(const <ChatEvent>[]),
        throwsA(
          isA<AiException>().having(
            (e) => e.message,
            'message',
            contains('answered with nothing'),
          ),
        ),
      );
    });
  });

  group('study profiles', () {
    const abitur = StudyProfile(
      id: 'p1',
      name: 'Abitur tasks',
      form: StudyKind.text,
      idea: 'Tasks as the Abitur sets them, each with a worked solution.',
      details: 'Three tasks, the last one hard.',
    );

    test('ask for their idea, in their form, and what the person adds '
        'last', () {
      final asked = abitur.instructions('section');
      expect(asked, startsWith(abitur.idea));
      expect(asked, contains(StudyKind.text.form('section')));
      expect(
        asked,
        endsWith(
          'do as they ask, in the form asked for:\n'
          'Three tasks, the last one hard.',
        ),
      );
      expect(
        StudyProfile.original(StudyKind.quiz).instructions('page'),
        '${StudyKind.quiz.idea}\n\n${StudyKind.quiz.form('page')}',
      );
    });

    test('keep only what was changed, the app’s own first', () {
      final quiz = StudyProfile.original(
        StudyKind.quiz,
      ).copyWith(details: 'I am in Q13 in Bavaria.', form: StudyKind.text);
      expect(quiz.form, StudyKind.quiz, reason: 'the app’s own keep theirs');
      var settings = const AiSettings()
          .withProfile(abitur)
          .withProfile(quiz)
          .withProfile(StudyProfile.original(StudyKind.terms));
      expect(settings.profiles.map((p) => p.id), <String>['p1', 'quiz']);
      settings = AiSettings.fromJson(settings.toJson());
      expect(settings.studyProfiles.map((p) => p.name), <String>[
        'Summary',
        'Flashcards',
        'Quiz',
        'Key terms',
        'Abitur tasks',
      ]);
      expect(settings.studyProfiles[2].details, 'I am in Q13 in Bavaria.');
      expect(settings.studyProfiles.last.form, StudyKind.text);
      // Changed back, one of the app's own is no longer kept.
      settings = settings.withProfile(StudyProfile.original(StudyKind.quiz));
      expect(settings.profiles.single.id, 'p1');
      expect(settings.withoutProfile('p1').profiles, isEmpty);
    });

    test('free text is written as an answer, citing the notes', () async {
      final provider = ScriptedProvider(<List<ChatEvent>>[
        <ChatEvent>[
          const TextDelta('## Task 1\n\nHow fast is it?'),
          const CitedSpan(<Citation>[
            Citation(
              uri: 'aantekening://page/p#element=a',
              title: 'Speed',
              origin: SourceOrigin.notes,
            ),
          ]),
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
        about: 'I am in Q13 in Bavaria.',
      ).make(abitur, scope: section).toList();
      final text = progress.last.study! as StudyText;
      expect(text.answer.markdown, startsWith('## Task 1'));
      expect(text.answer.citations.single.title, 'Speed');
      expect(text.size, 6);
      final asked = provider.asked.single;
      expect(asked.answerSchema, isNull);
      expect(sourcesIn(asked.messages), isNotEmpty, reason: 'cited natively');
      expect(asked.messages.single.text, contains(abitur.idea));
      expect(asked.system, contains('I am in Q13 in Bavaria.'));
      expect(asked.system, isNot(contains('JSON')));
      expect(
        StudySet.fromJson(text.toJson()),
        isA<StudyText>().having((t) => t.answer.citations, 'citations', [
          text.answer.citations.single,
        ]),
      );
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
