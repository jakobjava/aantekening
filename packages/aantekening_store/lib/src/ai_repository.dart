/// What the AI makes, stored apart from the notes.
library;

import 'dart:convert';

import 'package:aantekening_core/aantekening_core.dart';
import 'package:sqlite3/sqlite3.dart';

import 'database.dart';
import 'row_read.dart';

/// A conversation about a notebook, section or page.
class AiThread {
  const AiThread({
    required this.id,
    required this.scope,
    required this.title,
    required this.createdAt,
    required this.updatedAt,
  });

  final String id;

  /// What it is about.
  final NoteLink scope;
  final String title;
  final int createdAt;
  final int updatedAt;
}

/// One question in a conversation, and its answer.
class AiTurn {
  const AiTurn({
    required this.id,
    required this.threadId,
    required this.position,
    required this.question,
    required this.answer,
    required this.messages,
    required this.provider,
    required this.model,
    required this.createdAt,
    this.usage,
  });

  final String id;
  final String threadId;
  final int position;
  final String question;

  /// The answer as it was shown, as JSON.
  final Map<String, Object?> answer;

  /// The turn as the model had it, as JSON, to go on from.
  final List<Object?> messages;

  /// Who answered: the provider and its model.
  final String provider;
  final String model;
  final Map<String, Object?>? usage;
  final int createdAt;
}

/// Something the AI made that was kept: a summary, flashcards, an answer.
class AiItem {
  const AiItem({
    required this.id,
    required this.scope,
    required this.kind,
    required this.title,
    required this.body,
    required this.provider,
    required this.model,
    required this.position,
    required this.createdAt,
    required this.updatedAt,
    this.turnId,
  });

  final String id;

  /// What it is about.
  final NoteLink scope;

  /// What it is: `answer`, `summary`, `flashcards`, `quiz`, or a kind a
  /// later build knows.
  final String kind;
  final String title;

  /// What it holds, as JSON.
  final Map<String, Object?> body;

  /// The question it answered, if it came of one still kept.
  final String? turnId;
  final String provider;
  final String model;
  final double position;
  final int createdAt;
  final int updatedAt;
}

/// Stores conversations with the AI and what of them was kept, never in a
/// page: the notes are what the person wrote and nothing else.
class AiRepository {
  AiRepository(this._db, {DateTime Function()? clock})
    : _clock = clock ?? DateTime.now;

  final AantekeningDatabase _db;
  final DateTime Function() _clock;

  int get _now => _clock().millisecondsSinceEpoch;

  static List<Object?> _scopeArgs(NoteLink scope) => <Object?>[
    scope.kind.name,
    scope.id,
  ];

  static NoteLink _scope(Row row) => NoteLink(
    NoteLinkKind.values.byName(str(row, 'scope_kind')),
    str(row, 'scope_id'),
  );

  // ----------------------------------------------------------------- threads

  /// The conversations about [scope], the latest first.
  Future<List<AiThread>> threadsAbout(NoteLink scope) async => <AiThread>[
    for (final row in _db.select(
      'SELECT * FROM ai_threads WHERE scope_kind = ? AND scope_id = ? '
      'ORDER BY updated_at DESC, id DESC',
      _scopeArgs(scope.whole),
    ))
      _thread(row),
  ];

  Future<AiThread?> findThread(String id) async {
    final rows = _db.select('SELECT * FROM ai_threads WHERE id = ?', <Object?>[
      id,
    ]);
    return rows.isEmpty ? null : _thread(rows.first);
  }

  /// Starts a conversation about [scope], titled [title].
  Future<AiThread> createThread(NoteLink scope, {required String title}) async {
    final now = _now;
    final thread = AiThread(
      id: Ulid.generate(),
      scope: scope.whole,
      title: title,
      createdAt: now,
      updatedAt: now,
    );
    _db.run(
      'INSERT INTO ai_threads (id, scope_kind, scope_id, title, created_at, '
      'updated_at) VALUES (?, ?, ?, ?, ?, ?)',
      <Object?>[thread.id, ..._scopeArgs(thread.scope), title, now, now],
    );
    return thread;
  }

  Future<void> renameThread(String id, String title) async => _db.run(
    'UPDATE ai_threads SET title = ? WHERE id = ?',
    <Object?>[title, id],
  );

  /// Deletes a conversation and its questions. What was kept of it stays.
  Future<void> deleteThread(String id) async =>
      _db.run('DELETE FROM ai_threads WHERE id = ?', <Object?>[id]);

  AiThread _thread(Row row) => AiThread(
    id: str(row, 'id'),
    scope: _scope(row),
    title: str(row, 'title'),
    createdAt: integer(row, 'created_at'),
    updatedAt: integer(row, 'updated_at'),
  );

  // ------------------------------------------------------------------- turns

  /// The questions of conversation [threadId], in order.
  Future<List<AiTurn>> turnsOf(String threadId) async => <AiTurn>[
    for (final row in _db.select(
      'SELECT * FROM ai_turns WHERE thread_id = ? ORDER BY position',
      <Object?>[threadId],
    ))
      _turn(row),
  ];

  /// Adds a question and its answer to conversation [threadId].
  Future<AiTurn> addTurn(
    String threadId, {
    required String question,
    required Map<String, Object?> answer,
    required List<Object?> messages,
    required String provider,
    required String model,
    Map<String, Object?>? usage,
  }) async {
    final now = _now;
    return _db.transaction(() {
      final position = integer(
        _db.select(
          'SELECT COALESCE(MAX(position) + 1, 0) AS next FROM ai_turns '
          'WHERE thread_id = ?',
          <Object?>[threadId],
        ).first,
        'next',
      );
      final turn = AiTurn(
        id: Ulid.generate(),
        threadId: threadId,
        position: position,
        question: question,
        answer: answer,
        messages: messages,
        provider: provider,
        model: model,
        usage: usage,
        createdAt: now,
      );
      _db
        ..run(
          'INSERT INTO ai_turns (id, thread_id, position, question, answer, '
          'messages, provider, model, usage, created_at) '
          'VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?)',
          <Object?>[
            turn.id,
            threadId,
            position,
            question,
            jsonEncode(answer),
            jsonEncode(messages),
            provider,
            model,
            usage == null ? null : jsonEncode(usage),
            now,
          ],
        )
        ..run('UPDATE ai_threads SET updated_at = ? WHERE id = ?', <Object?>[
          now,
          threadId,
        ]);
      return turn;
    });
  }

  AiTurn _turn(Row row) => AiTurn(
    id: str(row, 'id'),
    threadId: str(row, 'thread_id'),
    position: integer(row, 'position'),
    question: str(row, 'question'),
    answer: (jsonDecode(str(row, 'answer')) as Map).cast<String, Object?>(),
    messages: jsonDecode(str(row, 'messages')) as List<Object?>,
    provider: str(row, 'provider'),
    model: str(row, 'model'),
    usage: switch (strOrNull(row, 'usage')) {
      final String json => (jsonDecode(json) as Map).cast<String, Object?>(),
      null => null,
    },
    createdAt: integer(row, 'created_at'),
  );

  // ------------------------------------------------------------------- items

  /// What was kept about [scope], in the order it is shown.
  Future<List<AiItem>> itemsAbout(NoteLink scope) async => <AiItem>[
    for (final row in _db.select(
      'SELECT * FROM ai_items WHERE scope_kind = ? AND scope_id = ? '
      'ORDER BY position, id',
      _scopeArgs(scope.whole),
    ))
      _item(row),
  ];

  /// Keeps something the AI made about [scope], first in its list.
  Future<AiItem> addItem(
    NoteLink scope, {
    required String kind,
    required String title,
    required Map<String, Object?> body,
    required String provider,
    required String model,
    String? turnId,
  }) async {
    final now = _now;
    final whole = scope.whole;
    final first = _db
        .select(
          'SELECT MIN(position) AS first FROM ai_items '
          'WHERE scope_kind = ? AND scope_id = ?',
          _scopeArgs(whole),
        )
        .first['first'];
    final item = AiItem(
      id: Ulid.generate(),
      scope: whole,
      kind: kind,
      title: title,
      body: body,
      turnId: turnId,
      provider: provider,
      model: model,
      position: first == null ? 0 : (first as num).toDouble() - 1,
      createdAt: now,
      updatedAt: now,
    );
    _db.run(
      'INSERT INTO ai_items (id, scope_kind, scope_id, kind, title, body, '
      'turn_id, provider, model, position, created_at, updated_at) '
      'VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)',
      <Object?>[
        item.id,
        ..._scopeArgs(whole),
        kind,
        title,
        jsonEncode(body),
        turnId,
        provider,
        model,
        item.position,
        now,
        now,
      ],
    );
    return item;
  }

  /// Replaces what kept thing [id] holds with [body], and, if given, its
  /// [title] — when a card of it is edited, say.
  Future<void> updateItem(
    String id, {
    required Map<String, Object?> body,
    String? title,
  }) async => _db.run(
    'UPDATE ai_items SET body = ?, title = COALESCE(?, title), '
    'updated_at = ? WHERE id = ?',
    <Object?>[jsonEncode(body), title, _now, id],
  );

  Future<void> renameItem(String id, String title) async => _db.run(
    'UPDATE ai_items SET title = ?, updated_at = ? WHERE id = ?',
    <Object?>[title, _now, id],
  );

  Future<void> deleteItem(String id) async =>
      _db.run('DELETE FROM ai_items WHERE id = ?', <Object?>[id]);

  // ----------------------------------------------------------------- reviews

  /// How each card of kept set [itemId] is learnt, by card, as the JSON it
  /// was saved as.
  Future<Map<String, Map<String, Object?>>> reviewsOf(String itemId) async =>
      <String, Map<String, Object?>>{
        for (final row in _db.select(
          'SELECT card_id, state FROM ai_reviews WHERE item_id = ?',
          <Object?>[itemId],
        ))
          str(row, 'card_id'): (jsonDecode(str(row, 'state')) as Map)
              .cast<String, Object?>(),
      };

  /// Keeps how card [cardId] of set [itemId] is learnt: [state], due at
  /// [dueAt], in milliseconds since the epoch.
  Future<void> saveReview(
    String itemId,
    String cardId, {
    required Map<String, Object?> state,
    required int dueAt,
  }) async => _db.run(
    'INSERT INTO ai_reviews (item_id, card_id, state, due_at, updated_at) '
    'VALUES (?, ?, ?, ?, ?) ON CONFLICT (item_id, card_id) DO UPDATE SET '
    'state = excluded.state, due_at = excluded.due_at, '
    'updated_at = excluded.updated_at',
    <Object?>[itemId, cardId, jsonEncode(state), dueAt, _now],
  );

  /// Forgets how the cards of set [itemId] not among [keep] were learnt,
  /// once they are no longer in it.
  Future<void> forgetReviews(String itemId, {required Set<String> keep}) async {
    final kept = keep.toList();
    _db.run(
      'DELETE FROM ai_reviews WHERE item_id = ? AND card_id NOT IN '
      '(${List<String>.filled(kept.length, '?').join(', ')})',
      <Object?>[itemId, ...kept],
    );
  }

  /// How many conversations and kept things there are about [scope], for
  /// showing whether it has any.
  Future<int> countAbout(NoteLink scope) async => integer(
    _db
        .select(
          'SELECT (SELECT COUNT(*) FROM ai_items WHERE scope_kind = ?1 AND '
          'scope_id = ?2) + (SELECT COUNT(*) FROM ai_threads WHERE '
          'scope_kind = ?1 AND scope_id = ?2) AS n',
          _scopeArgs(scope.whole),
        )
        .first,
    'n',
  );

  AiItem _item(Row row) => AiItem(
    id: str(row, 'id'),
    scope: _scope(row),
    kind: str(row, 'kind'),
    title: str(row, 'title'),
    body: (jsonDecode(str(row, 'body')) as Map).cast<String, Object?>(),
    turnId: strOrNull(row, 'turn_id'),
    provider: str(row, 'provider'),
    model: str(row, 'model'),
    position: real(row, 'position'),
    createdAt: integer(row, 'created_at'),
    updatedAt: integer(row, 'updated_at'),
  );
}
