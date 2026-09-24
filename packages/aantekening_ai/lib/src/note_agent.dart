/// Answering questions about the notes: what goes with a question, the
/// model's turns and the tools it runs, and the answer that comes of them.
library;

import 'dart:async';

import 'conversation.dart';
import 'answer.dart';
import 'citation_markers.dart';
import 'note_context.dart';
import 'note_reader.dart';
import 'note_tools.dart';
import 'provider.dart';
import 'study.dart';
import 'web_search.dart';

/// Where an answer has got to.
enum AgentStage {
  /// Gathering the notes that go with the question.
  gathering,

  /// The model has been sent the question and has not begun to answer: it
  /// is reading what it was given — for a model on this computer, what
  /// takes longest.
  reading,

  /// The model is reasoning before it answers.
  thinking,

  /// The model is writing.
  writing,

  /// Something is being done for the model: its notes searched, a page
  /// read, the web searched.
  working,

  /// The answer is there.
  done,
}

/// How an answer is coming along.
class AgentProgress {
  const AgentProgress({
    required this.answer,
    this.stage = AgentStage.done,
    this.activity = '',
    this.reasoning = '',
    this.written = 0,
    this.messages = const <ChatMessage>[],
    this.usage = const Usage(),
    this.study,
  });

  /// The answer so far.
  final AiAnswer answer;

  /// For a study set being made, as much of it as is written.
  final StudySet? study;

  final AgentStage stage;

  /// What is being done, in words, for the person watching.
  final String activity;

  /// What the model has reasoned since it was last asked, while it thinks.
  final String reasoning;

  /// How many characters the model has written for this question, its
  /// reasoning with its answer: for how fast it writes.
  final int written;

  /// Once [done], what this question added to the conversation, to keep
  /// for the next.
  final List<ChatMessage> messages;
  final Usage usage;

  bool get done => stage == AgentStage.done;
}

/// Answers questions about a notebook, section or page as someone who has
/// read every note would: from the notes first, the rest of the notes when
/// the question reaches beyond them, and the web and its own knowledge
/// after — each kept apart and cited.
class NoteAgent {
  NoteAgent({
    required this.provider,
    required this.model,
    required this.reader,
    this.webSearch,
  });

  final ChatProvider provider;
  final String model;
  final NoteReader reader;

  /// The web, searched by the app, for a provider that cannot search it.
  final WebSearch? webSearch;

  /// The most rounds of tools one question runs before answering with
  /// what it has.
  static const int maxRounds = 10;

  /// The progress of [answer], which ends the moment it is no longer
  /// listened to: [answer] is handed what says so, for each request it
  /// makes, and the model is stopped then — not once it next sends
  /// something, which a model reading a long prompt may not for minutes.
  static Stream<AgentProgress> _stoppable(
    Stream<AgentProgress> Function(Future<void> stop) answer,
  ) {
    final stop = Completer<void>();
    StreamSubscription<AgentProgress>? answering;
    late final StreamController<AgentProgress> progress;
    progress = StreamController<AgentProgress>(
      sync: true,
      onListen: () => answering = answer(stop.future).listen(
        progress.add,
        onError: progress.addError,
        onDone: progress.close,
      ),
      onPause: () => answering?.pause(),
      onResume: () => answering?.resume(),
      onCancel: () {
        if (!stop.isCompleted) stop.complete();
        // Not waited for: the answer ends at its next step, which the
        // request broken off brings at once.
        answering?.cancel().ignore();
      },
    );
    return progress.stream;
  }

  /// Answers [question] about [scope], after [history] — the conversation
  /// so far, empty for its first question. With [searchWeb], the web may be
  /// searched.
  Stream<AgentProgress> ask({
    required ScopeInfo scope,
    required List<ChatMessage> history,
    required String question,
    bool searchWeb = false,
  }) => _stoppable(
    (stop) => _ask(
      scope: scope,
      history: history,
      question: question,
      searchWeb: searchWeb,
      stop: stop,
    ),
  );

  Stream<AgentProgress> _ask({
    required ScopeInfo scope,
    required List<ChatMessage> history,
    required String question,
    required bool searchWeb,
    required Future<void> stop,
  }) async* {
    final answering = _Answering();
    final builder = answering.builder;
    final progress = answering.progress;

    yield progress(AgentStage.gathering, 'Gathering your notes');
    final capabilities = await provider.capabilitiesOf(model);
    final context = NoteContext(reader);
    final web = searchWeb && !capabilities.nativeWebSearch ? webSearch : null;
    final tools = NoteTools(
      reader: reader,
      scope: scope,
      vision: capabilities.vision,
      webSearch: web,
    );

    // The notes go with the first question; a model that cannot search them
    // itself is given the passages about each question after.
    final given = history.isEmpty
        ? await context.build(
            scope,
            budget: ContextBudget.forModel(capabilities),
            question: question,
          )
        : null;
    final found = history.isNotEmpty && !capabilities.tools
        ? await _passagesAbout(question, scope)
        : const <Source>[];
    final messages = <ChatMessage>[
      ...history,
      ChatMessage.user(<ChatPart>[
        if (given != null && given.sources.isNotEmpty)
          SourcesPart(given.sources),
        if (found.isNotEmpty) SourcesPart(found),
        ...?given?.images,
        TextPart(
          given == null
              ? question
              : '<overview>\n${given.overview}</overview>\n\n$question',
        ),
      ]),
    ];

    var usage = const Usage();
    // What the model was sent before: most runtimes keep what they read of
    // it, so only what is new is read again.
    var sent = 0;
    for (var round = 0; round < maxRounds; round++) {
      final request = ChatRequest(
        model: model,
        system: systemPrompt(scope, tools: capabilities.tools),
        // The conversation as it stands, not as it will grow.
        messages: List<ChatMessage>.unmodifiable(messages),
        tools: capabilities.tools ? tools.specs : const <ToolSpec>[],
        webSearch: searchWeb && capabilities.nativeWebSearch,
        stop: stop,
      );
      yield progress(
        AgentStage.reading,
        _reading(
          round == 0
              ? PromptSize.of(
                  messages,
                  system: request.system,
                  tools: request.tools,
                )
              : PromptSize.of(messages.skip(sent)),
          pages: round == 0 ? given?.sources.length : null,
          again: round > 0,
        ),
      );
      yield* answering.run(provider, request);
      final done = answering.done!;
      usage = usage + (done.usage ?? const Usage());
      messages.add(done.message);
      sent = messages.length;

      switch (done.stop) {
        case StopReason.paused:
          continue;
        case StopReason.toolUse:
          final calls = done.message.toolCalls;
          final results = <ChatPart>[];
          for (final call in calls) {
            yield progress(AgentStage.working, tools.describe(call));
            results.add(await tools.run(call));
          }
          messages.add(ChatMessage.user(results));
          // A space between what was written before the tools and after.
          if (!builder.answer.isEmpty) builder.note('\n\n');
          continue;
        case StopReason.maxTokens:
          builder.note(
            _cutOff(
              answered: !builder.answer.isEmpty,
              thought: answering.reasoning.isNotEmpty,
              room: capabilities.contextTokens,
            ),
          );
        case StopReason.refusal:
          builder.note(
            builder.answer.isEmpty
                ? '*The model declined to answer this.*'
                : '\n\n*The model stopped answering here.*',
          );
        case StopReason.done:
          break;
      }
      break;
    }

    yield AgentProgress(
      answer: builder.answer,
      written: answering.written,
      messages: messages.sublist(history.length),
      usage: usage,
    );
  }

  /// Makes a study set of [kind] from the notes of [scope]: the notes
  /// given whole, their passages numbered, the set asked for as JSON — and
  /// shown as far as it is written, while it is written.
  Stream<AgentProgress> make(StudyKind kind, {required ScopeInfo scope}) =>
      _stoppable((stop) => _make(kind, scope: scope, stop: stop));

  Stream<AgentProgress> _make(
    StudyKind kind, {
    required ScopeInfo scope,
    required Future<void> stop,
  }) async* {
    var sources = const <Source>[];
    final answering = _Answering(
      draft: (text) => StudySet.read(kind, text, sources, draft: true),
    );
    yield answering.progress(AgentStage.gathering, 'Gathering your notes');
    final capabilities = await provider.capabilitiesOf(model);
    final given = await NoteContext(
      reader,
    ).build(scope, budget: ContextBudget.forModel(capabilities));
    sources = given.sources;
    if (sources.isEmpty) {
      throw AiException(
        'There is nothing in this ${scope.kindName} to make '
        '${kind.label.toLowerCase()} from yet.',
      );
    }
    final request = ChatRequest(
      model: model,
      system: studyPrompt(scope),
      messages: <ChatMessage>[
        ChatMessage.user(<ChatPart>[
          TextPart(CitationMarkers.write(sources, first: 1)),
          ...given.images,
          TextPart(
            '<overview>\n${given.overview}</overview>\n\n'
            '${kind.instructions(scope.kindName)}',
          ),
        ]),
      ],
      stop: stop,
    );
    yield answering.progress(
      AgentStage.reading,
      _reading(
        PromptSize.of(request.messages, system: request.system),
        pages: sources.length,
        what: 'your notes',
      ),
    );
    yield* answering.run(provider, request);

    final done = answering.done!;
    final text = answering.builder.answer.markdown;
    final cutOff = done.stop == StopReason.maxTokens;
    // A set cut off is kept as far as it goes.
    final set =
        StudySet.read(kind, text, sources) ??
        (cutOff ? StudySet.read(kind, text, sources, draft: true) : null);
    if (set == null) {
      throw AiException(
        cutOff
            ? _cutOff(
                answered: false,
                thought: answering.reasoning.isNotEmpty,
                room: capabilities.contextTokens,
              ).replaceAll('*', '')
            : 'The model did not write the ${kind.label.toLowerCase()} in a '
                  'form the app can read. Try again, or choose another model.',
      );
    }
    yield AgentProgress(
      answer: answering.builder.answer,
      written: answering.written,
      usage: done.usage ?? const Usage(),
      study: set,
    );
  }

  /// Why an answer stopped short, when the model ran out of [room]: long
  /// as it was, or, before it [answered], all of it [thought] away.
  static String _cutOff({
    required bool answered,
    required bool thought,
    required int room,
  }) {
    if (answered) return '\n\n*The answer was too long and was cut off here.*';
    final tokens = '${_tokens(room)} tokens';
    return thought
        ? '*The model thought until its room ran out — $tokens for the '
              'question, its thinking and its answer — and did not get to '
              'answer.* Give it more room in the AI settings, turn its '
              'thinking off there, or choose a model that answers without '
              'thinking first, such as an “instruct” one.'
        : '*The model ran out of room — $tokens — before it could answer.* '
              'Give it more room in the AI settings, or ask about less at '
              'once.';
  }

  /// What the model is doing while it reads [size] — [pages] of the notes
  /// with the question, or, [again], what it asked for.
  String _reading(
    PromptSize size, {
    int? pages,
    bool again = false,
    String what = 'your question',
  }) {
    if (size.isEmpty) return '$model is going on';
    final parts = <String>[
      if (pages != null && pages > 0) '$pages ${pages == 1 ? 'page' : 'pages'}',
      if (size.images > 0)
        '${size.images} ${size.images == 1 ? 'picture' : 'pictures'}',
      'about ${_tokens(size.tokens)} tokens',
    ];
    return '$model is reading ${again ? 'what it found' : what}'
        ' — ${parts.join(', ')}';
  }

  static String _tokens(int tokens) => tokens < 1000
      ? '$tokens'
      : '${(tokens / 1000).toStringAsFixed(tokens < 10000 ? 1 : 0)}k';

  Future<List<Source>> _passagesAbout(String question, ScopeInfo scope) async {
    final tools = NoteTools(reader: reader, scope: scope);
    final result = await tools.run(
      ToolCallPart(
        id: 'prefetch',
        name: NoteTools.searchNotes,
        input: <String, Object?>{'query': question, 'everywhere': false},
      ),
    );
    return <Source>[
      for (final part in result.content)
        if (part is SourcesPart) ...part.sources,
    ];
  }

  /// The standing instructions for making study sets about [scope].
  static String studyPrompt(ScopeInfo scope) {
    final where = scope.path.isEmpty ? '' : ' (in ${scope.path.join(' › ')})';
    return '''
You make study material from a student's own notes, in aantekening, a note-taking app. The notes of the ${scope.kindName} "${scope.title}"$where are given as passages, each numbered like [1.2]; the pictures show their handwriting and drawings over printouts.

- Use what the notes say, in their terms and notation. Name the passages each thing comes from by their numbers, as "sources": ["1.2", "1.3"].
- Write in the language the notes are written in.
- Write mathematics in LaTeX between dollar signs, like \$v = \\frac{s}{t}\$; in JSON a backslash is written twice.
- Answer with the JSON asked for and nothing else: no Markdown fence, no words before or after it.''';
  }

  /// The standing instructions for questions about [scope].
  ///
  /// Kept the same for every question about it, so providers that cache
  /// what they were given before can reuse it.
  static String systemPrompt(ScopeInfo scope, {required bool tools}) {
    final where = scope.path.isEmpty ? '' : ' (in ${scope.path.join(' › ')})';
    return '''
You are the study companion built into aantekening, a note-taking app. You have the person's notes to hand — every notebook, section and page they have written: typed text, formulas, tables, pictures, PDF printouts, and their own handwriting and drawings over them. Answer as someone who has read all of it and knows the subject well.

They are working in the ${scope.kindName} "${scope.title}"$where. Its notes come with their first question, as sources, with an overview of what it holds. Start from those.${tools ? ' When a question reaches beyond them, search the rest of the notes, and read or look at what you need.' : ''}

How to answer:
- Their notes come first. Say what the notes say, in their terms and notation, and cite it.
- Keep three kinds of knowledge visibly apart. What their notes say: cite the passage. What you found on the web: cite the web page. What you know yourself: say so plainly — for example "Beyond your notes, …" — and cite nothing for it. Never present your own knowledge, or the web's, as something the notes say.
- Where the notes do not cover something, or seem mistaken, say so rather than quietly filling the gap.
- Handwriting and drawings are only in the visuals, never in the text.${tools ? ' Look at a visual before saying what it shows.' : ''} If you could not see one, say so.
- Write mathematics in LaTeX: \$…\$ in a sentence, \$\$…\$\$ on a line of its own.
- Answer in the language the person writes in. Be clear, and no longer than the question needs; use headings and lists where they help.
- Flashcards and quizzes are for learning the subject: the ideas, definitions, laws and formulas that matter, each once. Never about the notes themselves — their titles, layout, dates or where things are.
- Flashcards go in a fenced block marked flashcards, holding a JSON array of {"front": "…", "back": "…"}. A quiz goes in a fenced block marked quiz, holding a JSON array of {"question": "…", "options": ["…"], "answer": <index of the right option>, "explanation": "…"}. Cite their sources in a sentence before the block.''';
  }
}

/// An answer being written, over the requests it takes: what came of it,
/// and how it is coming along.
class _Answering {
  _Answering({this.draft});

  final AnswerBuilder builder = AnswerBuilder();

  /// Reads a study set from what is written so far, for a set being made.
  final StudySet? Function(String text)? draft;

  /// What the model has reasoned in the request going on.
  StringBuffer reasoning = StringBuffer();

  /// How much the model has written, its reasoning with its answer.
  int written = 0;

  /// The study set as far as it is written.
  StudySet? study;

  /// How the last request ended, once it has.
  MessageDone? done;

  AgentProgress progress(AgentStage stage, String activity) => AgentProgress(
    answer: builder.answer,
    stage: stage,
    activity: activity,
    reasoning: '$reasoning',
    written: written,
    study: study,
  );

  /// What is being written, in words.
  String get _writing => switch (study) {
    null => 'Writing',
    final set => 'Writing — ${set.size} so far',
  };

  /// The progress of [request] to [provider]; [done] once it is done.
  Stream<AgentProgress> run(ChatProvider provider, ChatRequest request) async* {
    reasoning = StringBuffer();
    done = null;
    await for (final event in provider.chat(request)) {
      builder.add(event);
      switch (event) {
        case Reasoning(:final text):
          reasoning.write(text);
          written += text.length;
          yield progress(AgentStage.thinking, 'Thinking');
        case TextDelta(:final text):
          written += text.length;
          if (draft case final read?) {
            study = read(builder.answer.markdown) ?? study;
          }
          yield progress(AgentStage.writing, _writing);
        case CitedSpan():
          yield progress(AgentStage.writing, _writing);
        case Activity(:final description):
          yield progress(AgentStage.working, description);
        case MessageDone():
          done = event;
      }
    }
    if (done == null) {
      throw const AiException('The answer broke off. Try again.');
    }
  }
}
