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
/// made to study from — a summary, flashcards — is a [StudyProfile]
/// instead.
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
  /// [question], just asked — or, with [profile], a set of it being made;
  /// or, with [rewriting], a part of that turn's answer written again.
  factory PendingTurn({
    required String question,
    required bool local,
    StudyProfile? profile,
    String? rewriting,
  }) {
    final now = DateTime.now();
    return PendingTurn._(
      question: question,
      local: local,
      profile: profile,
      rewriting: rewriting,
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
    required this.profile,
    required this.rewriting,
    required this.startedAt,
    required this.progress,
    required this.since,
    required this.writtenBefore,
    required this.steps,
  });

  final String question;

  /// The profile of the study set being made, if it is one rather than an
  /// answer.
  final StudyProfile? profile;

  /// The id of the turn a part of whose answer is being written again, if
  /// that is what this is.
  final String? rewriting;

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
      profile: profile,
      rewriting: rewriting,
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
    this.making = const <String, PendingTurn>{},
    this.shownProfile,
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

  /// The study sets being made, by the id of their profile, each as far as
  /// it has got. They are made alongside each other and the question, while
  /// anything else is looked at.
  final Map<String, PendingTurn> making;

  /// The id of the profile whose page shows, where its set is being made
  /// or not made yet; once made, its kept set shows as [itemId].
  final String? shownProfile;

  /// Why the last question went unanswered.
  final String? error;

  AiItem? get item => items.where((item) => item.id == itemId).firstOrNull;

  /// Whether the overview shows: nothing opened, nothing under way.
  bool get atOverview =>
      itemId == null &&
      threadId == null &&
      shownProfile == null &&
      pending == null;

  /// The kept set of profile [id], if one was made.
  AiItem? setOf(String id) => items
      .where((item) => item.kind == id && StudySet.fromJson(item.body) != null)
      .firstOrNull;

  /// The profiles to study by: [configured], then one for each set kept
  /// whose own profile is gone, to see it and make it again by.
  List<StudyProfile> profilesWith(List<StudyProfile> configured) {
    final ids = <String>{for (final profile in configured) profile.id};
    return <StudyProfile>[
      ...configured,
      for (final item in items)
        if (StudySet.fromJson(item.body) case final set?
            when ids.add(item.kind))
          StudyProfile(
            id: item.kind,
            name: item.title,
            form: set.kind,
            idea: set.kind.idea,
          ),
    ];
  }

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
    Map<String, PendingTurn>? making,
    String? Function()? shownProfile,
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
    shownProfile: shownProfile == null ? this.shownProfile : shownProfile(),
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

  /// What makes each set being made, by the id of its profile.
  final Map<String, StreamSubscription<AgentProgress>> _makers =
      <String, StreamSubscription<AgentProgress>>{};

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
      shownProfile: () => null,
      turns: await store.ai.turnsOf(id),
      error: () => null,
    );
  }

  /// Shows the overview, where a new conversation starts.
  void newThread() => state = state.copyWith(
    threadId: () => null,
    itemId: () => null,
    shownProfile: () => null,
    turns: const <AiTurn>[],
    error: () => null,
  );

  /// Shows kept thing [id].
  void openItem(String id) =>
      state = state.copyWith(itemId: () => id, shownProfile: () => null);

  /// Shows the study set of profile [id]: as it is being made, as it was
  /// kept, or, not made yet, what it would be and a way to make it.
  void openProfile(String id) {
    final item = state.setOf(id);
    if (item != null && !state.making.containsKey(id)) {
      openItem(item.id);
      return;
    }
    state = state.copyWith(
      itemId: () => null,
      threadId: () => null,
      shownProfile: () => id,
    );
  }

  /// A model to answer with, as the settings have it: what it is asked
  /// bears in mind what the person says of themselves.
  NoteAgent _agent(AiModel model, WorkspaceReader reader, {WebSearch? web}) =>
      NoteAgent(
        provider: model.provider,
        model: model.config.model,
        reader: reader,
        webSearch: web,
        notesTokens: model.config.notesTokens,
        about: ref.read(aiSettingsProvider).about,
      );

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
      shownProfile: () => null,
      pending: () => PendingTurn(question: text, local: model.config.local),
      error: () => null,
    );
    await _follow(
      _agent(model, reader, web: web).ask(
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

  /// Writes [section] of the answer to [turn] again — as [instruction]
  /// says, where it says anything — in its place, the rest of the answer
  /// as it was. With [searchWeb], the web may be searched.
  ///
  /// The model is asked in the conversation, after all of it, so it knows
  /// what it wrote and why; and what it was asked and wrote is added at the
  /// conversation's end, never between what was said before, so the next
  /// question goes on from the answer as it now is, and what the provider
  /// kept of the conversation still holds.
  Future<void> rewrite(
    AiTurn turn,
    AnswerSection section, {
    String instruction = '',
    required bool searchWeb,
  }) async {
    if (state.pending != null) return;
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
      for (final each in state.turns)
        for (final json in each.messages)
          ChatMessage.fromJson((json! as Map).cast<String, Object?>()),
    ];
    final answer = AiAnswer.fromJson(turn.answer);
    final part = answer.textOf(section);
    final how = instruction.trim();

    state = state.copyWith(
      itemId: () => null,
      shownProfile: () => null,
      pending: () => PendingTurn(
        question: how.isEmpty
            ? 'Write this again: “${_excerpt(part)}”'
            : 'Write this again — $how: “${_excerpt(part)}”',
        local: model.config.local,
        rewriting: turn.id,
      ),
      error: () => null,
    );
    await _follow(
      _agent(model, reader, web: web).ask(
        scope: info,
        history: history,
        question: NoteAgent.rewriteRequest(
          part,
          question: turn.question,
          instruction: how,
        ),
        searchWeb: searchWeb,
      ),
      read: () => state.pending,
      write: (pending) => state = state.copyWith(pending: () => pending),
      started: (subscription) => _answering = subscription,
      onDone: (progress) => _keepRewrite(turn, section, progress),
    );
  }

  /// Keeps what [progress] wrote of [section] of the answer to [turn] in
  /// its place, and what was asked and written at the conversation's end.
  Future<void> _keepRewrite(
    AiTurn asked,
    AnswerSection section,
    AgentProgress progress,
  ) async {
    if (progress.answer.isEmpty) {
      state = state.copyWith(
        pending: () => null,
        error: () => 'The model wrote nothing in its place. Try again.',
      );
      return;
    }
    final store = await _store;
    // As they are now, whichever conversation shows.
    final turns = await store.ai.turnsOf(asked.threadId);
    final turn = turns.where((each) => each.id == asked.id).firstOrNull;
    final last = turns.lastOrNull;
    if (turn == null || last == null) {
      state = state.copyWith(pending: () => null);
      return;
    }
    final answer = AiAnswer.fromJson(turn.answer)
        .replacing(section, progress.answer);
    final added = <Object?>[for (final m in progress.messages) m.toJson()];
    await store.ai.updateTurn(
      turn.id,
      answer: <String, Object?>{...turn.answer, ...answer.toJson()},
      messages: last.id == turn.id
          ? <Object?>[...turn.messages, ...added]
          : null,
      usage: _added(turn.usage, _usageOf(progress)),
    );
    if (last.id != turn.id) {
      await store.ai.updateTurn(
        last.id,
        messages: <Object?>[...last.messages, ...added],
      );
    }
    state = state.copyWith(pending: () => null);
    await _load(threadId: turn.threadId);
  }

  /// [usage] with [more] added to it: the tokens and what they cost; how
  /// long it took stays as it was.
  static Map<String, Object?> _added(
    Map<String, Object?>? usage,
    Map<String, Object?> more,
  ) => <String, Object?>{
    ...?usage,
    for (final MapEntry(:key, :value) in more.entries)
      if (key != _tookKey)
        key: switch ((usage?[key], value)) {
          (final num a, final num b) => a + b,
          _ => value,
        },
  };

  /// The start of [text], to say in a line what it is.
  static String _excerpt(String text) {
    final line = text.replaceAll(RegExp(r'\s+'), ' ').trim();
    return line.length <= 60 ? line : '${line.substring(0, 57)}…';
  }

  /// Makes a study set as [profile] describes it from the notes of the
  /// scope, shown as it is written, and keeps it — in place of the one made
  /// before, what was learnt of its cards carried over. Made alongside
  /// anything else going on; its page shows it coming, and anything else
  /// can be looked at meanwhile.
  Future<void> make(StudyProfile profile) async {
    final id = profile.id;
    if (state.making.containsKey(id)) {
      openProfile(id);
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
    void write(PendingTurn? pending) => _setMaking(id, pending);
    write(
      PendingTurn(
        question: profile.name,
        local: model.config.local,
        profile: profile,
      ),
    );
    state = state.copyWith(
      itemId: () => null,
      threadId: () => null,
      shownProfile: () => id,
      error: () => null,
    );
    StreamSubscription<AgentProgress>? making;
    await _follow(
      _agent(model, reader).make(profile, scope: info),
      read: () => state.making[id],
      write: write,
      started: (subscription) => _makers[id] = making = subscription,
      onDone: (progress) async {
        if (progress.study case final set?) {
          await _keepSet(
            set,
            profile: profile,
            provider: model.config.name,
            model: model.config.model,
            usage: _usageOf(progress),
          );
        }
      },
    );
    // Another may have been started once this one was kept.
    if (identical(_makers[id], making)) _makers.remove(id);
  }

  /// Stops making the set of profile [id], keeping the one made before, if
  /// any.
  Future<void> stopMaking(String id) async {
    _setMaking(id, null);
    await _makers.remove(id)?.cancel();
  }

  /// Keeps how far making the set of profile [id] has got, or with null
  /// that it is no longer being made.
  void _setMaking(String id, PendingTurn? pending) => state = state.copyWith(
    making: <String, PendingTurn>{
      for (final entry in state.making.entries)
        if (entry.key != id) entry.key: entry.value,
      id: ?pending,
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
          final profile = read()?.profile;
          write(null);
          final why = error is AiException
              ? error.message
              : 'it broke off: $error';
          state = state.copyWith(
            error: () => switch (profile?.called) {
              null =>
                error is AiException ? why : 'The answer broke off: $error',
              final called =>
                '${called[0].toUpperCase()}${called.substring(1)} could not '
                    'be made: $why',
            },
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

  /// Keeps [set] as the scope's set of [profile], and shows it if its page
  /// is showing.
  Future<void> _keepSet(
    StudySet set, {
    required StudyProfile profile,
    required String provider,
    required String model,
    Map<String, Object?>? usage,
  }) async {
    final store = await _store;
    final earlier = state.setOf(profile.id);
    var kept = set;
    if (earlier == null) {
      final item = await store.ai.addItem(
        scope,
        kind: profile.id,
        title: profile.name,
        body: set.toJson(),
        provider: provider,
        model: model,
        usage: usage,
      );
      await _shown(profile.id, item.id);
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
    await store.ai.updateItem(
      earlier.id,
      body: kept.toJson(),
      title: profile.name,
      usage: usage,
    );
    ref.invalidate(cardReviewsProvider(earlier.id));
    await _shown(profile.id, earlier.id);
  }

  /// Once the set of profile [id] is kept as [itemId]: shown in place of
  /// its page, if that is showing.
  Future<void> _shown(String id, String itemId) async {
    _setMaking(id, null);
    await _load();
    if (state.shownProfile == id) {
      state = state.copyWith(itemId: () => itemId, shownProfile: () => null);
    }
  }

  /// Adds [cards] — from an answer, say — to the scope's flashcards.
  Future<void> addCards(List<StudyCard> cards) async {
    final model = await ref.read(aiModelProvider.future);
    final profile = ref
        .read(aiSettingsProvider)
        .studyProfiles
        .firstWhere((profile) => profile.id == StudyKind.flashcards.name);
    final earlier = state.setOf(profile.id);
    final before = earlier == null ? null : StudySet.fromJson(earlier.body);
    final set = FlashcardSet(cards);
    if (earlier == null || before is! FlashcardSet) {
      await _keepSet(
        set,
        profile: profile,
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

  /// Stops the answer coming, keeping what came of it — but for a part
  /// being written again, which stays as it was.
  Future<void> stop() async {
    final pending = state.pending;
    await _answering?.cancel();
    _answering = null;
    if (pending == null) return;
    if (pending.rewriting != null) {
      state = state.copyWith(pending: () => null);
      return;
    }
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
      usage: _usageOf(progress, took: took),
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

  /// What [progress] took, done — and what it cost, and how long it
  /// [took], where that is known — as a turn or a kept set keeps it.
  static Map<String, Object?> _usageOf(
    AgentProgress progress, {
    Duration? took,
  }) => <String, Object?>{
    'input': progress.usage.input,
    'output': progress.usage.output,
    'cacheRead': progress.usage.cacheRead,
    'cacheWrite': progress.usage.cacheWrite,
    'webSearches': progress.usage.webSearches,
    _costKey: ?progress.cost,
    if (took != null) _tookKey: took.inMilliseconds,
  };

  /// How long [turn] took to answer, if that was kept.
  static Duration? tookOf(AiTurn turn) => switch (turn.usage?[_tookKey]) {
    final int ms => Duration(milliseconds: ms),
    _ => null,
  };

  /// What a turn or a kept set with [usage] cost, in US dollars, if that
  /// was kept.
  static double? costOf(Map<String, Object?>? usage) =>
      (usage?[_costKey] as num?)?.toDouble();

  static const String _tookKey = 'milliseconds';
  static const String _costKey = 'dollars';

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

/// The profiles to study the scope of [state] by, as [AiSessionState.
/// profilesWith] has them.
List<StudyProfile> studyProfilesOf(WidgetRef ref, AiSessionState state) =>
    state.profilesWith(ref.watch(aiSettingsProvider).studyProfiles);

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

/// How many cards not yet studied a session brings in, besides those due.
const int newCardsPerSession = 20;

/// How many of kept set [item]'s cards a session would study now — those
/// due, and new ones up to [newCardsPerSession] — or 0 for a set that is
/// not flashcards.
int cardsToStudy(WidgetRef ref, AiItem? item) {
  if (item == null) return 0;
  final set = StudySet.fromJson(item.body);
  if (set is! FlashcardSet) return 0;
  final status = deckStatus(
    set.cards,
    ref.watch(cardReviewsProvider(item.id)).value ??
        const <String, CardReview>{},
    DateTime.now(),
  );
  return status.due + status.fresh.clamp(0, newCardsPerSession);
}

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
