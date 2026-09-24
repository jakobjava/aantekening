/// A notebook's, section's or page's AI: its conversations, what was kept,
/// and the question being answered.
library;

import 'dart:async';

import 'package:aantekening_ai/aantekening_ai.dart';
import 'package:aantekening_core/aantekening_core.dart';
import 'package:aantekening_store/aantekening_store.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../providers.dart';
import 'ai_state.dart';
import 'workspace_reader.dart';

/// Reads the workspace for the AI, one reader for the workspace open.
final workspaceReaderProvider = FutureProvider<WorkspaceReader>((ref) async {
  final store = await ref.watch(storeProvider.future);
  return WorkspaceReader(store);
});

/// What a notebook, section or page is called and where it is, for the AI
/// view to say what it is about.
final aiScopeInfoProvider = FutureProvider.family<ScopeInfo?, NoteLink>((
  ref,
  link,
) async {
  ref.watch(libraryRevisionProvider);
  final reader = await ref.watch(workspaceReaderProvider.future);
  return reader.scope(link);
});

/// A question asked often, offered to start a conversation with. What is
/// made to study from — a summary, flashcards — is a [StudyKind] instead.
enum AiAction {
  explain(
    'Explain the hardest part',
    'Which idea in this {kind} is the hardest? Explain it simply, with an '
        'example.',
  ),
  test(
    'What would a test ask?',
    'What would a test on this {kind} most likely ask? Give the likely '
        'questions, and how to answer each well.',
  ),
  tutor(
    'Check my understanding',
    'Check my understanding of this {kind}: ask me one question at a time, '
        'wait for my answer, then tell me what was right and what to look '
        'at again.',
  ),
  connect(
    'How does it connect?',
    'How does this {kind} connect to the rest of my notes? Point out where '
        'the same ideas come up.',
  );

  const AiAction(this.label, this._prompt);

  final String label;
  final String _prompt;

  /// What is asked about a [kind] — a page, a section, a notebook.
  String promptFor(String kind) => _prompt.replaceAll('{kind}', kind);
}

/// A step an answer took, done with: the model reading, thinking, a
/// search of the notes.
@immutable
class AiStep {
  const AiStep({
    required this.stage,
    required this.activity,
    required this.took,
    this.reasoning = '',
  });

  final AgentStage stage;
  final String activity;
  final Duration took;

  /// What the model reasoned, for a step of thinking.
  final String reasoning;
}

/// The question being answered, as far as it has got, and the steps it
/// took to get there.
@immutable
class PendingTurn {
  /// [question], just asked — or, with [study], a set of that kind being
  /// made.
  factory PendingTurn({
    required String question,
    required bool local,
    StudyKind? study,
  }) {
    final now = DateTime.now();
    return PendingTurn._(
      question: question,
      local: local,
      study: study,
      startedAt: now,
      progress: const AgentProgress(
        answer: AiAnswer(),
        stage: AgentStage.gathering,
        activity: 'Gathering your notes',
      ),
      since: now,
      writtenBefore: 0,
      steps: const <AiStep>[],
    );
  }

  const PendingTurn._({
    required this.question,
    required this.local,
    required this.study,
    required this.startedAt,
    required this.progress,
    required this.since,
    required this.writtenBefore,
    required this.steps,
  });

  final String question;

  /// The kind of study set being made, if it is one rather than an answer.
  final StudyKind? study;

  /// Whether the model runs on this computer, where reading is slow.
  final bool local;
  final DateTime startedAt;

  /// Where the answer is now.
  final AgentProgress progress;

  /// When the step it is on began.
  final DateTime since;

  /// How much the model had written when the step it is on began: for how
  /// fast it writes in it.
  final int writtenBefore;

  /// The steps done with, first first.
  final List<AiStep> steps;

  AiAnswer get answer => progress.answer;

  /// Moved on to [next], at [now]: a step of its own if it does something
  /// else.
  PendingTurn moved(AgentProgress next, DateTime now) {
    final same =
        next.stage == progress.stage && next.activity == progress.activity;
    return PendingTurn._(
      question: question,
      local: local,
      study: study,
      startedAt: startedAt,
      progress: next,
      since: same ? since : now,
      writtenBefore: same ? writtenBefore : progress.written,
      steps: same
          ? steps
          : <AiStep>[
              ...steps,
              AiStep(
                stage: progress.stage,
                activity: progress.activity,
                took: now.difference(since),
                reasoning: progress.stage == AgentStage.thinking
                    ? progress.reasoning
                    : '',
              ),
            ],
    );
  }
}

@immutable
class AiSessionState {
  const AiSessionState({
    this.loaded = false,
    this.threads = const <AiThread>[],
    this.items = const <AiItem>[],
    this.threadId,
    this.itemId,
    this.turns = const <AiTurn>[],
    this.pending,
    this.making = const <StudyKind, PendingTurn>{},
    this.shownKind,
    this.error,
  });

  final bool loaded;

  /// The conversations about it, the latest first.
  final List<AiThread> threads;

  /// What was kept about it.
  final List<AiItem> items;

  /// The conversation showing, or null for a new one.
  final String? threadId;

  /// The kept thing showing in place of a conversation, if one is.
  final String? itemId;

  /// The questions of the conversation showing.
  final List<AiTurn> turns;

  /// The question being answered, if one is.
  final PendingTurn? pending;

  /// The study sets being made, each as far as it has got. They are made
  /// alongside each other and the question, while anything else is looked
  /// at.
  final Map<StudyKind, PendingTurn> making;

  /// The kind of study set whose page shows, where it is being made or not
  /// made yet; once made, its kept set shows as [itemId].
  final StudyKind? shownKind;

  /// Why the last question went unanswered.
  final String? error;

  AiItem? get item => items.where((item) => item.id == itemId).firstOrNull;

  /// Whether the overview shows: nothing opened, nothing under way.
  bool get atOverview =>
      itemId == null &&
      threadId == null &&
      shownKind == null &&
      pending == null;

  /// The kept set of [kind], if one was made.
  AiItem? setOf(StudyKind kind) => items
      .where(
        (item) =>
            item.kind == kind.name && StudySet.fromJson(item.body) != null,
      )
      .firstOrNull;

  /// The answers kept from conversations.
  List<AiItem> get savedAnswers => <AiItem>[
    for (final item in items)
      if (StudySet.fromJson(item.body) == null) item,
  ];

  AiSessionState copyWith({
    bool? loaded,
    List<AiThread>? threads,
    List<AiItem>? items,
    String? Function()? threadId,
    String? Function()? itemId,
    List<AiTurn>? turns,
    PendingTurn? Function()? pending,
    Map<StudyKind, PendingTurn>? making,
    StudyKind? Function()? shownKind,
    String? Function()? error,
  }) => AiSessionState(
    loaded: loaded ?? this.loaded,
    threads: threads ?? this.threads,
    items: items ?? this.items,
    threadId: threadId == null ? this.threadId : threadId(),
    itemId: itemId == null ? this.itemId : itemId(),
    turns: turns ?? this.turns,
    pending: pending == null ? this.pending : pending(),
    making: making ?? this.making,
    shownKind: shownKind == null ? this.shownKind : shownKind(),
    error: error == null ? this.error : error(),
  );
}

/// The AI of the notebook, section or page [scope].
///
/// Kept while the app runs, so an answer goes on arriving while another
/// tab is showing.
class AiSession extends Notifier<AiSessionState> {
  AiSession(this.scope);

  final NoteLink scope;
  StreamSubscription<AgentProgress>? _answering;
  final Map<StudyKind, StreamSubscription<AgentProgress>> _makers =
      <StudyKind, StreamSubscription<AgentProgress>>{};

  Future<AantekeningStore> get _store => ref.read(storeProvider.future);

  @override
  AiSessionState build() {
    ref.onDispose(() {
      unawaited(_answering?.cancel());
      for (final maker in _makers.values) {
        unawaited(maker.cancel());
      }
    });
    unawaited(_load());
    return const AiSessionState();
  }

  Future<void> _load({String? threadId}) async {
    final store = await _store;
    final threads = await store.ai.threadsAbout(scope);
    final items = await store.ai.itemsAbout(scope);
    final open = threadId ?? state.threadId;
    state = state.copyWith(
      loaded: true,
      threads: threads,
      items: items,
      threadId: () => open,
      turns: open == null ? const <AiTurn>[] : await store.ai.turnsOf(open),
    );
  }

  /// Shows conversation [id].
  Future<void> openThread(String id) async {
    final store = await _store;
    state = state.copyWith(
      threadId: () => id,
      itemId: () => null,
      shownKind: () => null,
      turns: await store.ai.turnsOf(id),
      error: () => null,
    );
  }

  /// Shows the overview, where a new conversation starts.
  void newThread() => state = state.copyWith(
    threadId: () => null,
    itemId: () => null,
    shownKind: () => null,
    turns: const <AiTurn>[],
    error: () => null,
  );

  /// Shows kept thing [id].
  void openItem(String id) =>
      state = state.copyWith(itemId: () => id, shownKind: () => null);

  /// Shows the study set of [kind]: as it is being made, as it was kept,
  /// or, not made yet, what it would be and a way to make it.
  void openKind(StudyKind kind) {
    final item = state.setOf(kind);
    if (item != null && !state.making.containsKey(kind)) {
      openItem(item.id);
      return;
    }
    state = state.copyWith(
      itemId: () => null,
      threadId: () => null,
      shownKind: () => kind,
    );
  }

  /// Asks [question] in the conversation showing, or a new one — the
  /// question of [action], if it is one. With [searchWeb], the web may be
  /// searched.
  Future<void> ask(
    String question, {
    required bool searchWeb,
    AiAction? action,
  }) async {
    final text = question.trim();
    if (text.isEmpty || state.pending != null) return;
    final model = await ref.read(aiModelProvider.future);
    if (model == null) {
      state = state.copyWith(error: () => 'Choose a model to ask first.');
      return;
    }
    final reader = await ref.read(workspaceReaderProvider.future);
    final info = await reader.scope(scope);
    if (info == null) return;
    final web = await ref.read(webSearchProvider.future);
    final history = <ChatMessage>[
      for (final turn in state.turns)
        for (final json in turn.messages)
          ChatMessage.fromJson((json! as Map).cast<String, Object?>()),
    ];

    state = state.copyWith(
      itemId: () => null,
      shownKind: () => null,
      pending: () => PendingTurn(question: text, local: model.config.local),
      error: () => null,
    );
    final agent = NoteAgent(
      provider: model.provider,
      model: model.config.model,
      reader: reader,
      webSearch: web,
    );
    await _follow(
      agent.ask(
        scope: info,
        history: history,
        question: text,
        searchWeb: searchWeb,
      ),
      read: () => state.pending,
      write: (pending) => state = state.copyWith(pending: () => pending),
      started: (subscription) => _answering = subscription,
      onDone: (progress) =>
          _keepTurn(text, progress, model.config, action: action),
    );
  }

  /// Makes a study set of [kind] from the notes of the scope, shown as it
  /// is written, and keeps it — in place of the one made before, what was
  /// learnt of its cards carried over. Made alongside anything else going
  /// on; its page shows it coming, and anything else can be looked at
  /// meanwhile.
  Future<void> make(StudyKind kind) async {
    if (state.making.containsKey(kind)) {
      openKind(kind);
      return;
    }
    final model = await ref.read(aiModelProvider.future);
    if (model == null) {
      state = state.copyWith(error: () => 'Choose a model first.');
      return;
    }
    final reader = await ref.read(workspaceReaderProvider.future);
    final info = await reader.scope(scope);
    if (info == null) return;
    void write(PendingTurn? pending) => _setMaking(kind, pending);
    write(
      PendingTurn(question: kind.label, local: model.config.local, study: kind),
    );
    state = state.copyWith(
      itemId: () => null,
      threadId: () => null,
      shownKind: () => kind,
      error: () => null,
    );
    final agent = NoteAgent(
      provider: model.provider,
      model: model.config.model,
      reader: reader,
    );
    await _follow(
      agent.make(kind, scope: info),
      read: () => state.making[kind],
      write: write,
      started: (subscription) => _makers[kind] = subscription,
      onDone: (progress) async {
        if (progress.study case final set?) {
          await _keepSet(
            set,
            provider: model.config.name,
            model: model.config.model,
          );
        }
      },
    );
    _makers.remove(kind);
  }

  /// Stops making the set of [kind], keeping the one made before, if any.
  Future<void> stopMaking(StudyKind kind) async {
    _setMaking(kind, null);
    await _makers.remove(kind)?.cancel();
  }

  /// Keeps how far making the set of [kind] has got, or with null that it
  /// is no longer being made.
  void _setMaking(StudyKind kind, PendingTurn? pending) =>
      state = state.copyWith(
        making: <StudyKind, PendingTurn>{
          for (final entry in state.making.entries)
            if (entry.key != kind) entry.key: entry.value,
          kind: ?pending,
        },
      );

  /// Follows [answer] into what [read] and [write] keep of it — the
  /// question's pending turn, or a set's — handing its subscription to
  /// [started], and [onDone] with how it ended.
  Future<void> _follow(
    Stream<AgentProgress> answer, {
    required PendingTurn? Function() read,
    required void Function(PendingTurn? pending) write,
    required void Function(StreamSubscription<AgentProgress>) started,
    required Future<void> Function(AgentProgress last) onDone,
  }) {
    final done = Completer<void>();
    AgentProgress? last;
    started(
      answer.listen(
        (progress) {
          last = progress;
          final pending = read();
          if (pending != null) write(pending.moved(progress, DateTime.now()));
        },
        onError: (Object error) {
          final kind = read()?.study;
          write(null);
          final why = error is AiException
              ? error.message
              : 'it broke off: $error';
          state = state.copyWith(
            error: () => kind == null
                ? (error is AiException ? why : 'The answer broke off: $error')
                : 'The ${kind.label.toLowerCase()} could not be made: $why',
          );
          if (!done.isCompleted) done.complete();
        },
        onDone: () async {
          final progress = last;
          if (progress != null && progress.done) await onDone(progress);
          if (read() != null) write(null);
          if (!done.isCompleted) done.complete();
        },
        cancelOnError: true,
      ),
    );
    return done.future;
  }

  /// Keeps [set] as the scope's set of its kind, and shows it if its page
  /// is showing.
  Future<void> _keepSet(
    StudySet set, {
    required String provider,
    required String model,
  }) async {
    final store = await _store;
    final earlier = state.setOf(set.kind);
    var kept = set;
    if (earlier == null) {
      final item = await store.ai.addItem(
        scope,
        kind: set.kind.name,
        title: set.kind.label,
        body: set.toJson(),
        provider: provider,
        model: model,
      );
      await _shown(set.kind, item.id);
      return;
    }
    if ((set, StudySet.fromJson(earlier.body)) case (
      final FlashcardSet made,
      final FlashcardSet before,
    )) {
      final cards = made.keepingIdsOf(before);
      kept = cards;
      await store.ai.forgetReviews(
        earlier.id,
        keep: <String>{for (final card in cards.cards) card.id},
      );
    }
    await store.ai.updateItem(earlier.id, body: kept.toJson());
    ref.invalidate(cardReviewsProvider(earlier.id));
    await _shown(set.kind, earlier.id);
  }

  /// Once the set of [kind] is kept as [itemId]: shown in place of its
  /// page, if that is showing.
  Future<void> _shown(StudyKind kind, String itemId) async {
    _setMaking(kind, null);
    await _load();
    if (state.shownKind == kind) {
      state = state.copyWith(itemId: () => itemId, shownKind: () => null);
    }
  }

  /// Adds [cards] — from an answer, say — to the scope's flashcards.
  Future<void> addCards(List<StudyCard> cards) async {
    final model = await ref.read(aiModelProvider.future);
    final earlier = state.setOf(StudyKind.flashcards);
    final before = earlier == null ? null : StudySet.fromJson(earlier.body);
    final set = FlashcardSet(cards);
    if (earlier == null || before is! FlashcardSet) {
      await _keepSet(
        set,
        provider: model?.config.name ?? '',
        model: model?.config.model ?? '',
      );
      return;
    }
    final store = await _store;
    await store.ai.updateItem(earlier.id, body: set.addedTo(before).toJson());
    await _load();
  }

  /// Keeps [set] as what kept thing [id] holds: a card edited or taken out.
  Future<void> updateSet(String id, StudySet set) async {
    final store = await _store;
    await store.ai.updateItem(id, body: set.toJson());
    if (set is FlashcardSet) {
      await store.ai.forgetReviews(
        id,
        keep: <String>{for (final card in set.cards) card.id},
      );
      ref.invalidate(cardReviewsProvider(id));
    }
    await _load();
  }

  /// Stops the answer coming, keeping what came of it.
  Future<void> stop() async {
    final pending = state.pending;
    await _answering?.cancel();
    _answering = null;
    if (pending == null) return;
    final model = await ref.read(aiModelProvider.future);
    if (model != null && !pending.answer.isEmpty) {
      await _keepTurn(
        pending.question,
        AgentProgress(
          answer: AiAnswer(
            markdown: '${pending.answer.markdown}\n\n*Stopped.*',
            citations: pending.answer.citations,
          ),
        ),
        model.config,
      );
    } else {
      state = state.copyWith(pending: () => null);
    }
  }

  Future<void> _keepTurn(
    String question,
    AgentProgress progress,
    ProviderConfig config, {
    AiAction? action,
  }) async {
    final store = await _store;
    final took = state.pending == null
        ? null
        : DateTime.now().difference(state.pending!.startedAt);
    final threadId =
        state.threadId ??
        (await store.ai.createThread(scope, title: _titleOf(question))).id;
    await store.ai.addTurn(
      threadId,
      question: question,
      answer: <String, Object?>{
        ...progress.answer.toJson(),
        if (action != null) _actionKey: action.name,
      },
      messages: <Object?>[for (final m in progress.messages) m.toJson()],
      provider: config.name,
      model: config.model,
      usage: <String, Object?>{
        'input': progress.usage.input,
        'output': progress.usage.output,
        'cacheRead': progress.usage.cacheRead,
        'webSearches': progress.usage.webSearches,
        if (took != null) _tookKey: took.inMilliseconds,
      },
    );
    state = state.copyWith(pending: () => null);
    await _load(threadId: threadId);
  }

  /// Keeps the answer to [turn], to come back to.
  Future<void> keep(AiTurn turn) async {
    final store = await _store;
    final item = await store.ai.addItem(
      scope,
      kind: 'answer',
      title: _titleOf(turn.question),
      body: AiAnswer.fromJson(turn.answer).toJson(),
      provider: turn.provider,
      model: turn.model,
      turnId: turn.id,
    );
    await _load();
    state = state.copyWith(itemId: () => item.id);
  }

  /// Whether the answer to [turn] is kept already.
  bool isKept(AiTurn turn) => state.items.any((item) => item.turnId == turn.id);

  /// How long [turn] took to answer, if that was kept.
  static Duration? tookOf(AiTurn turn) => switch (turn.usage?[_tookKey]) {
    final int ms => Duration(milliseconds: ms),
    _ => null,
  };

  static const String _tookKey = 'milliseconds';

  /// Where a turn's answer says which [AiAction] asked it.
  static const String _actionKey = 'action';

  Future<void> renameItem(String id, String title) async {
    await (await _store).ai.renameItem(id, title);
    await _load();
  }

  Future<void> deleteItem(String id) async {
    await (await _store).ai.deleteItem(id);
    if (state.itemId == id) state = state.copyWith(itemId: () => null);
    await _load();
  }

  Future<void> deleteThread(String id) async {
    await (await _store).ai.deleteThread(id);
    if (state.threadId == id) newThread();
    await _load();
  }

  static String _titleOf(String question) {
    final line = question.trim().split('\n').first;
    return line.length <= 60 ? line : '${line.substring(0, 57).trimRight()}…';
  }
}

final aiSessionProvider =
    NotifierProvider.family<AiSession, AiSessionState, NoteLink>(AiSession.new);

/// How each card of kept set [itemId] is learnt, and grading them.
class CardReviews extends AsyncNotifier<Map<String, CardReview>> {
  CardReviews(this.itemId);

  final String itemId;

  @override
  Future<Map<String, CardReview>> build() async {
    final store = await ref.watch(storeProvider.future);
    return <String, CardReview>{
      for (final entry in (await store.ai.reviewsOf(itemId)).entries)
        entry.key: CardReview.fromJson(entry.value),
    };
  }

  /// How card [cardId] is learnt now: as it was, or new.
  CardReview of(String cardId, DateTime now) =>
      state.value?[cardId] ?? CardReview.fresh(now);

  /// Keeps that card [cardId] was remembered as [grade] at [now], and
  /// returns what it comes to.
  Future<CardReview> grade(String cardId, Grade grade, DateTime now) async {
    final next = of(cardId, now).after(grade, now);
    state = AsyncData(<String, CardReview>{...?state.value, cardId: next});
    final store = await ref.read(storeProvider.future);
    await store.ai.saveReview(
      itemId,
      cardId,
      state: next.toJson(),
      dueAt: next.due.millisecondsSinceEpoch,
    );
    return next;
  }
}

final cardReviewsProvider =
    AsyncNotifierProvider.family<CardReviews, Map<String, CardReview>, String>(
      CardReviews.new,
    );

/// How far along [cards] are, by [reviews], at [now].
({int due, int fresh, int learnt}) deckStatus(
  List<StudyCard> cards,
  Map<String, CardReview> reviews,
  DateTime now,
) {
  var due = 0;
  var fresh = 0;
  var learnt = 0;
  for (final card in cards) {
    final review = reviews[card.id];
    if (review == null) {
      fresh++;
    } else if (review.isDue(now)) {
      due++;
    } else if (!review.learning) {
      learnt++;
    }
  }
  return (due: due, fresh: fresh, learnt: learnt);
}
