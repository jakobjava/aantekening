part of 'ai_session.dart';

/// The conversations of an [AiSession]: asking in them, writing a part
/// of an answer again, and keeping what was answered.
mixin _Conversations on _AiSessionCore {
  StreamSubscription<AgentProgress>? _answering;

  /// Whether a question is being started: from the click that asks it to
  /// its pending turn, which then keeps a second from being asked.
  bool _asking = false;

  /// Asks [question] in the conversation showing, or a new one — the
  /// question of [action], if it is one. With [searchWeb], the web may be
  /// searched.
  Future<void> ask(
    String question, {
    required bool searchWeb,
    AiAction? action,
  }) async {
    final text = question.trim();
    if (text.isEmpty || state.pending != null || _asking) return;
    // Asked in the conversation showing now, with what was said in it.
    final threadId = state.threadId;
    final history = <ChatMessage>[
      for (final turn in state.turns)
        for (final json in turn.messages)
          ChatMessage.fromJson((json! as Map).cast<String, Object?>()),
    ];
    _asking = true;
    final _Ready? ready;
    final WebSearch? web;
    try {
      ready = await _ready('Choose a model to ask first.');
      web = ready == null ? null : await ref.read(webSearchProvider.future);
    } finally {
      _asking = false;
    }
    if (ready == null) return;
    final (:model, :reader, :info) = ready;

    state = state.copyWith(
      itemId: () => null,
      shownProfile: () => null,
      pending: () => PendingTurn(
        question: text,
        local: model.config.local,
        threadId: threadId,
      ),
      error: () => null,
    );
    await _follow(
      holdingProvider(
        model.provider,
        _agent(model, reader, web: web).ask(
          scope: info,
          history: history,
          question: text,
          searchWeb: searchWeb,
        ),
      ),
      read: () => state.pending,
      write: (pending) => state = state.copyWith(pending: () => pending),
      started: (subscription) => _answering = subscription,
      ended: () => _answering = null,
      onDone: (progress) => _keepTurn(
        text,
        progress,
        model.config,
        threadId: threadId,
        action: action,
      ),
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
    if (state.pending != null || _asking) return;
    final history = <ChatMessage>[
      for (final each in state.turns)
        for (final json in each.messages)
          ChatMessage.fromJson((json! as Map).cast<String, Object?>()),
    ];
    _asking = true;
    final _Ready? ready;
    final WebSearch? web;
    try {
      ready = await _ready('Choose a model to ask first.');
      web = ready == null ? null : await ref.read(webSearchProvider.future);
    } finally {
      _asking = false;
    }
    if (ready == null) return;
    final (:model, :reader, :info) = ready;
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
        threadId: turn.threadId,
        rewriting: turn.id,
      ),
      error: () => null,
    );
    await _follow(
      holdingProvider(
        model.provider,
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
      ),
      read: () => state.pending,
      write: (pending) => state = state.copyWith(pending: () => pending),
      started: (subscription) => _answering = subscription,
      ended: () => _answering = null,
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
    final showing = _showingOnceKept(turn.threadId, turn.threadId);
    state = state.copyWith(pending: () => null);
    await _load(threadId: showing);
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

  /// Stops the answer coming, keeping what came of it — but for a part
  /// being written again, which stays as it was.
  Future<void> stop() async {
    final pending = state.pending;
    final answering = _answering;
    // Come to its end already, and being kept: nothing is left to stop,
    // nor to keep a second time.
    if (answering == null) return;
    _answering = null;
    await answering.cancel();
    if (pending == null) return;
    if (pending.rewriting != null) {
      state = state.copyWith(pending: () => null);
      return;
    }
    final model = await ref.read(aiModelProvider.future);
    if (model == null || pending.answer.isEmpty) {
      state = state.copyWith(pending: () => null);
      return;
    }
    try {
      await _keepTurn(
        pending.question,
        AgentProgress(
          answer: AiAnswer(
            markdown: '${pending.answer.markdown}\n\n*Stopped.*',
            citations: pending.answer.citations,
          ),
        ),
        model.config,
        threadId: pending.threadId,
      );
    } on Object catch (error) {
      state = state.copyWith(
        pending: () => null,
        error: () => 'The answer could not be kept: $error',
      );
    }
  }

  /// Keeps what [progress] answered to [question] in conversation
  /// [threadId], where it was asked, or a new one.
  Future<void> _keepTurn(
    String question,
    AgentProgress progress,
    ProviderConfig config, {
    required String? threadId,
    AiAction? action,
  }) async {
    final store = await _store;
    final took = state.pending == null
        ? null
        : DateTime.now().difference(state.pending!.startedAt);
    final kept =
        threadId ??
        (await store.ai.createThread(scope, title: _titleOf(question))).id;
    await store.ai.addTurn(
      kept,
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
    final showing = _showingOnceKept(threadId, kept);
    state = state.copyWith(pending: () => null);
    await _load(threadId: showing);
  }

  /// The conversation to show once an answer asked in [asked] is kept in
  /// [kept]: that one, unless another was opened meanwhile.
  String _showingOnceKept(String? asked, String kept) {
    final showing = state.threadId;
    return showing == null || showing == asked ? kept : showing;
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

  /// Where a turn's answer says which [AiAction] asked it.
  static const String _actionKey = 'action';

  static String _titleOf(String question) {
    final line = question.trim().split('\n').first;
    return line.length <= 60 ? line : '${line.substring(0, 57).trimRight()}…';
  }
}

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
  /// [question], just asked in conversation [threadId] or a new one — or,
  /// with [profile], a set of it being made; or, with [rewriting], a part
  /// of that turn's answer written again.
  factory PendingTurn({
    required String question,
    required bool local,
    String? threadId,
    StudyProfile? profile,
    String? rewriting,
  }) {
    final now = DateTime.now();
    return PendingTurn._(
      question: question,
      local: local,
      threadId: threadId,
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
    required this.threadId,
    required this.profile,
    required this.rewriting,
    required this.startedAt,
    required this.progress,
    required this.since,
    required this.writtenBefore,
    required this.steps,
  });

  final String question;

  /// The conversation it was asked in, which its answer is kept in — or
  /// null for a new one — whatever shows by the time it comes.
  final String? threadId;

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
      threadId: threadId,
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
