import 'package:aantekening_core/aantekening_core.dart';
import 'package:aantekening_store/aantekening_store.dart';
import 'package:sqlite3/sqlite3.dart';
import 'package:test/test.dart';

import 'support.dart';

void main() {
  late TestWorkspace workspace;
  late AiRepository ai;
  const page = NoteLink.page('p1');
  const section = NoteLink.section('s1');

  setUp(() {
    workspace = TestWorkspace.create();
    ai = workspace.store.ai;
  });
  tearDown(() => workspace.dispose());

  test(
    'a conversation belongs to what it is about, its questions in order',
    () async {
      final thread = await ai.createThread(
        const NoteLink.page('p1', elementId: 'e'),
        title: 'Forces',
      );
      expect(thread.scope, page, reason: 'the page, not a place on it');
      await ai.addTurn(
        thread.id,
        question: 'What is force?',
        answer: <String, Object?>{'markdown': 'Mass times acceleration.'},
        messages: <Object?>[
          <String, Object?>{'role': 'user'},
        ],
        provider: 'Anthropic',
        model: 'claude-opus-5',
        usage: <String, Object?>{'input': 10},
      );
      await ai.addTurn(
        thread.id,
        question: 'And weight?',
        answer: <String, Object?>{'markdown': 'Mass times g.'},
        messages: const <Object?>[],
        provider: 'Anthropic',
        model: 'claude-opus-5',
      );

      final turns = await ai.turnsOf(thread.id);
      expect(turns.map((t) => t.question), <String>[
        'What is force?',
        'And weight?',
      ]);
      expect(turns.first.answer['markdown'], 'Mass times acceleration.');
      expect(turns.first.usage, <String, Object?>{'input': 10});
      expect((await ai.threadsAbout(page)).single.id, thread.id);
      expect(await ai.threadsAbout(section), isEmpty);
    },
  );

  test(
    'kept things come newest first, and outlive their conversation',
    () async {
      final thread = await ai.createThread(page, title: 'Cards');
      final turn = await ai.addTurn(
        thread.id,
        question: 'Flashcards please',
        answer: const <String, Object?>{},
        messages: const <Object?>[],
        provider: 'Ollama',
        model: 'qwen',
      );
      await ai.addItem(
        page,
        kind: 'summary',
        title: 'Summary',
        body: const <String, Object?>{'markdown': 'Short.'},
        provider: 'Ollama',
        model: 'qwen',
      );
      await ai.addItem(
        page,
        kind: 'flashcards',
        title: 'Cards',
        body: const <String, Object?>{'markdown': '```flashcards\n[]\n```'},
        provider: 'Ollama',
        model: 'qwen',
        turnId: turn.id,
      );
      expect((await ai.itemsAbout(page)).map((i) => i.kind), <String>[
        'flashcards',
        'summary',
      ]);
      expect(await ai.countAbout(page), 3);

      await ai.deleteThread(thread.id);
      final items = await ai.itemsAbout(page);
      expect(items, hasLength(2));
      expect(items.first.turnId, isNull, reason: 'its question went, it stays');
    },
  );

  test('nothing of it touches the notes', () async {
    final sectionId = await workspace.seedSection();
    final created = await workspace.store.pages.createPage(
      sectionId: sectionId,
    );
    final thread = await ai.createThread(NoteLink.page(created.id), title: 'x');
    await ai.addItem(
      NoteLink.page(created.id),
      kind: 'answer',
      title: 'x',
      body: const <String, Object?>{},
      provider: 'p',
      model: 'm',
    );
    expect(thread.id, isNotEmpty);
    final document = await workspace.store.pages.loadDocument(created.id);
    expect(document?.elements ?? const <NoteElement>[], isEmpty);
    expect(await workspace.store.search.search('x'), isEmpty);
  });

  test('keeps how each card of a set is learnt apart from the set, and '
      'forgets it with the set or the card', () async {
    const scope = NoteLink.page('p');
    final set = await ai.addItem(
      scope,
      kind: 'flashcards',
      title: 'Cards',
      body: const <String, Object?>{'cards': <Object?>[]},
      provider: 'p',
      model: 'm',
    );
    await ai.saveReview(set.id, 'a', state: const {'due': 1}, dueAt: 1);
    await ai.saveReview(set.id, 'b', state: const {'due': 2}, dueAt: 2);
    await ai.saveReview(set.id, 'a', state: const {'due': 3}, dueAt: 3);
    expect(await ai.reviewsOf(set.id), <String, Object?>{
      'a': {'due': 3},
      'b': {'due': 2},
    });

    await ai.updateItem(set.id, body: const <String, Object?>{'cards': 1});
    expect((await ai.itemsAbout(scope)).single.body['cards'], 1);
    expect(await ai.reviewsOf(set.id), hasLength(2), reason: 'kept');

    await ai.forgetReviews(set.id, keep: const <String>{'b'});
    expect((await ai.reviewsOf(set.id)).keys, <String>['b']);
    await ai.deleteItem(set.id);
    expect(await ai.reviewsOf(set.id), isEmpty);
  });

  test(
    'a workspace from before the AI kept anything is brought up to date',
    () {
      final db = sqlite3.openInMemory();
      addTearDown(db.close);
      db.userVersion = 0;
      Schema.migrate(db);
      db
        ..execute('DROP TABLE ai_reviews')
        ..execute('DROP TABLE ai_items')
        ..execute('DROP TABLE ai_turns')
        ..execute('DROP TABLE ai_threads')
        ..userVersion = 1;

      Schema.migrate(db);

      expect(db.userVersion, Schema.version);
      expect(
        db
            .select(
              "SELECT name FROM sqlite_master WHERE name LIKE 'ai_%' "
              "AND type = 'table' ORDER BY name",
            )
            .map((row) => row['name']),
        <String>['ai_items', 'ai_reviews', 'ai_threads', 'ai_turns'],
      );
    },
  );
}
