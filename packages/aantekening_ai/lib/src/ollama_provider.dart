/// Ollama, spoken to in its own API, which says what each model can do and
/// takes how much room the model is run with.
library;

import 'dart:async';
import 'dart:convert';

import 'conversation.dart';
import 'openai_compatible_provider.dart';
import 'provider.dart';
import 'streamed_answer.dart';

/// Talks to Ollama through its own chat API rather than its OpenAI one,
/// which cannot say how much room a model runs with: left to itself,
/// Ollama runs a model with a few thousand tokens, and a model that thinks
/// first runs out of them before it answers. Here each model runs with
/// [contextTokens], and thinks first only if [think].
///
/// The messages are those of the OpenAI API, written Ollama's way.
class OllamaProvider extends OpenAiCompatibleProvider {
  OllamaProvider({
    required super.name,
    required String baseUrl,
    this.contextTokens = defaultContextTokens,
    this.think = true,
    this.thinkingTime = defaultThinkingTime,
    DateTime Function()? clock,
    super.client,
  }) : clock = clock ?? DateTime.now,
       root = baseUrl.replaceFirst(RegExp(r'(/v1)?/*$'), ''),
       super(
         baseUrl: '${baseUrl.replaceFirst(RegExp(r'(/v1)?/*$'), '')}/v1',
         defaults: ModelCapabilities(contextTokens: contextTokens),
       );

  /// Room enough for a page or two of notes, a model's thinking, and its
  /// answer, without taking much of a computer's memory.
  static const int defaultContextTokens = 16384;

  /// The room a model can be run with, to choose from.
  static const List<int> contextChoices = <int>[8192, 16384, 32768, 65536];

  /// How many tokens of a prompt a model reads at a time. A request
  /// stopped while the model reads ends only once the chunk under way is
  /// read, which without a graphics card can take half a minute for a
  /// chunk of 1024; chunks this size are read hardly slower, and let it
  /// stop in half the time.
  static const int promptChunk = 512;

  /// Where Ollama is: `http://127.0.0.1:11434`.
  final String root;

  /// How many tokens a model runs with: what it is given, what it thinks,
  /// and what it answers, together.
  final int contextTokens;

  /// Whether a model that can think before it answers does. Some models
  /// always do.
  final bool think;

  /// How long a model thinks before it is stopped to answer, or null for
  /// as long as its room lasts.
  final Duration? thinkingTime;

  /// Long enough for a good deal of thought on a fast computer, and to
  /// keep a slow one from thinking in circles for half an hour.
  static const Duration defaultThinkingTime = Duration(minutes: 3);

  /// The times to choose from for [thinkingTime], and null for no limit.
  static const List<Duration?> thinkingChoices = <Duration?>[
    Duration(minutes: 1),
    Duration(minutes: 3),
    Duration(minutes: 10),
    null,
  ];

  /// What tells the time, for [thinkingTime].
  final DateTime Function() clock;

  /// What each model asked about can do.
  final Map<String, ModelCapabilities> _known = <String, ModelCapabilities>{};

  Uri _api(String path) => Uri.parse('$root/api$path');

  @override
  Future<List<ModelInfo>> listModels() async {
    final Map<String, Object?> body;
    try {
      final response = await client
          .get(_api('/tags'), headers: headers)
          .timeout(const Duration(seconds: 10));
      refuse(response.statusCode, response.body);
      body = jsonDecode(response.body) as Map<String, Object?>;
    } on Object catch (error) {
      if (error is AiException) rethrow;
      throw unreachable(error);
    }
    return <ModelInfo>[
      for (final entry in (body['models'] as List<Object?>?) ?? const [])
        if (entry case {'name': final String id})
          ModelInfo(
            id: id,
            capabilities: _capabilities(
              entry['capabilities'] as List<Object?>?,
              ((entry['details'] as Map?)?['context_length']) as int?,
            ),
          ),
    ]..sort((a, b) => a.id.compareTo(b.id));
  }

  @override
  Future<ModelCapabilities> capabilitiesOf(String model) async {
    final known = _known[model];
    if (known != null) return known;
    try {
      final response = await client
          .post(
            _api('/show'),
            headers: headers,
            body: jsonEncode(<String, Object?>{'model': model}),
          )
          .timeout(const Duration(seconds: 10));
      if (response.statusCode != 200) return defaults;
      final body = jsonDecode(response.body) as Map<String, Object?>;
      final info = (body['model_info'] as Map?)?.cast<String, Object?>();
      return _known[model] = _capabilities(
        body['capabilities'] as List<Object?>?,
        info?.entries
            .where((entry) => entry.key.endsWith('.context_length'))
            .map((entry) => entry.value)
            .whereType<int>()
            .firstOrNull,
      );
    } on Object {
      return defaults;
    }
  }

  /// What a model with [abilities], trained for [trained] tokens, can do
  /// as it is run here.
  ModelCapabilities _capabilities(List<Object?>? abilities, int? trained) {
    final can = <Object?>{...?abilities};
    return ModelCapabilities(
      vision: can.contains('vision'),
      tools: can.contains('tools'),
      reasoning: can.contains('thinking'),
      contextTokens: trained == null || trained > contextTokens
          ? contextTokens
          : trained,
    );
  }

  @override
  Map<String, Object?> requestBody(
    ChatRequest request,
    List<Map<String, Object?>> messages,
    List<Map<String, Object?>> tools,
  ) => <String, Object?>{
    'model': request.model,
    'stream': true,
    'messages': messages,
    if (tools.isNotEmpty) 'tools': tools,
    'options': <String, Object?>{
      'num_ctx': contextTokens,
      'num_batch': promptChunk,
      if (request.maxTokens != null) 'num_predict': request.maxTokens,
    },
    // Said only to a model that thinks: any other refuses to be told.
    if (_known[request.model]?.reasoning ?? false) 'think': think,
  };

  @override
  Map<String, Object?> userMessage(List<ChatPart> content) => <String, Object?>{
    'role': 'user',
    'content': content.whereType<TextPart>().map((p) => p.text).join('\n\n'),
    if (content.whereType<ImagePart>().isNotEmpty)
      'images': <String>[
        for (final image in content.whereType<ImagePart>())
          base64Encode(image.bytes),
      ],
  };

  @override
  Map<String, Object?> toolCall(ToolCallPart call) => <String, Object?>{
    'function': <String, Object?>{'name': call.name, 'arguments': call.input},
  };

  @override
  Map<String, Object?> toolMessage(
    ToolResultPart result,
    String content, {
    required String name,
  }) => <String, Object?>{
    'role': 'tool',
    'content': content,
    'tool_name': name,
  };

  /// How much of the room is kept for the answer, however long the model
  /// thinks.
  static const int answerRoom = 2048;

  /// Said for the model, after what it has thought, when its thinking is
  /// stopped: so it ends it and answers.
  static const String _enough =
      '\n\nI have thought about this long enough. I will now write the '
      'answer from what I have worked out, without thinking further.';

  /// Streams the answer to [request]. A model that thinks longer than
  /// [thinkingTime], or into the room its answer needs, is stopped and
  /// handed back what it thought, closed, with its answer begun — so it
  /// answers from there, and a small model going round in circles still
  /// answers.
  @override
  Stream<ChatEvent> chat(ChatRequest request) async* {
    await capabilitiesOf(request.model);
    final answer = StreamedAnswer(sourcesIn(request.messages));
    final body = this.body(request);
    final reply = _Reply();
    final room =
        contextTokens -
        answerRoom -
        PromptSize.of(
          request.messages,
          system: request.system,
          tools: request.tools,
        ).tokens;
    yield* _read(
      body,
      answer,
      reply,
      stop: request.stop,
      thoughtMax: room < 512 ? 512 : room,
    );
    if (reply.stopped) {
      yield const Activity('Stopping its thinking, to answer');
      yield* _read(
        <String, Object?>{
          ...body,
          'messages': <Object?>[
            ...body['messages']! as List<Object?>,
            // The answer begun, so the thinking is over: Ollama closes
            // it, and the model can only go on with the answer.
            <String, Object?>{
              'role': 'assistant',
              'content': '\n',
              'thinking': '${reply.thought}$_enough',
            },
          ],
          'options': <String, Object?>{
            ...body['options']! as Map<String, Object?>,
            'num_predict': answerRoom * 2,
          },
        },
        answer,
        reply,
        stop: request.stop,
      );
    }
    yield* Stream<ChatEvent>.fromIterable(answer.close());
    yield const CitedSpan(<Citation>[]);
    yield MessageDone(
      ChatMessage.assistant(<ChatPart>[
        if (answer.text.isNotEmpty) TextPart(answer.text),
        ...reply.calls,
      ]),
      stop: reply.calls.isNotEmpty ? StopReason.toolUse : reply.stop,
      usage: reply.usage,
    );
  }

  /// The events of one request of [body], into [answer] and [reply] — its
  /// thinking stopped, with [thoughtMax] tokens, once it is too long, and
  /// all of it once [stop] completes.
  Stream<ChatEvent> _read(
    Map<String, Object?> body,
    StreamedAnswer answer,
    _Reply reply, {
    required Future<void>? stop,
    int? thoughtMax,
  }) async* {
    final response = await send(_api('/chat'), body, stop: stop);

    DateTime? thinkingSince;
    // Leaving the loop early closes the connection, which stops the model.
    await for (final line
        in response.stream
            .transform(utf8.decoder)
            .transform(const LineSplitter())) {
      if (line.trim().isEmpty) continue;
      final data = jsonDecode(line) as Map<String, Object?>;
      if (data['error'] case final Object error) {
        throw AiException('$name stopped: $error');
      }
      final message =
          (data['message'] as Map?)?.cast<String, Object?>() ??
          const <String, Object?>{};
      if (message['thinking'] case final String thought
          when thought.isNotEmpty) {
        final text = withoutThinkTags(thought);
        reply.thought.write(text);
        if (text.isNotEmpty) yield Reasoning(text);
        if (thoughtMax != null) {
          final since = thinkingSince ??= clock();
          final limit = thinkingTime;
          if (reply.thought.length / 4 > thoughtMax ||
              (limit != null && clock().difference(since) > limit)) {
            reply.stopped = true;
            return;
          }
        }
      }
      if (message['content'] case final String piece when piece.isNotEmpty) {
        yield* Stream<ChatEvent>.fromIterable(answer.add(piece));
      }
      for (final call
          in (message['tool_calls'] as List<Object?>?) ?? const []) {
        final function = ((call! as Map)['function'] as Map?)
            ?.cast<String, Object?>();
        if (function?['name'] case final String name) {
          reply.calls.add(
            ToolCallPart(
              id: 'call_${reply.calls.length}',
              name: name,
              input: switch (function!['arguments']) {
                final Map<Object?, Object?> input => input.cast(),
                _ => const <String, Object?>{},
              },
            ),
          );
        }
      }
      if (data['done'] == true) {
        reply
          ..stop = data['done_reason'] == 'length'
              ? StopReason.maxTokens
              : StopReason.done
          ..usage =
              reply.usage +
              Usage(
                input: data['prompt_eval_count'] as int? ?? 0,
                output: data['eval_count'] as int? ?? 0,
              );
      }
    }
  }
}

/// What has come of a reply so far, over the requests it takes.
class _Reply {
  final StringBuffer thought = StringBuffer();
  final List<ToolCallPart> calls = <ToolCallPart>[];
  StopReason stop = StopReason.done;
  Usage usage = const Usage();

  /// Whether its thinking was stopped, to be ended and answered.
  bool stopped = false;
}
