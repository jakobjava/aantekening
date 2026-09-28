/// Any provider speaking the OpenAI chat completions API: runtimes on this
/// machine — Ollama, LM Studio, llama.cpp, vLLM — and services on the web.
library;

import 'dart:async';
import 'dart:convert';

import 'package:http/http.dart' as http;
import 'package:meta/meta.dart';

import 'citation_markers.dart';
import 'conversation.dart';
import 'provider.dart';
import 'sse.dart';
import 'streamed_answer.dart';

/// Talks to an OpenAI-compatible chat completions endpoint, streaming.
///
/// This API is what nearly every runtime and service offers, so one class
/// reaches them all. It has no citations of its own: sources are numbered
/// in the text, and the numbers the model writes are read back
/// ([MarkerReader]).
class OpenAiCompatibleProvider implements ChatProvider {
  OpenAiCompatibleProvider({
    required this.name,
    required this.baseUrl,
    this.apiKey,
    this.defaults = const ModelCapabilities(vision: true, tools: true),
    this.room,
    http.Client? client,
  }) : client = client ?? http.Client(),
       _ownsClient = client == null;

  @override
  final String name;

  /// The API's root, with its version: `http://127.0.0.1:11434/v1`.
  final String baseUrl;
  final String? apiKey;

  /// What a model is taken to be able to do, where the provider does not
  /// say.
  final ModelCapabilities defaults;

  /// How many tokens a model takes, as the person set it: over what the
  /// provider says, which is what the model could take, not how a server
  /// of one's own runs it. Null for what the provider says.
  final int? room;

  /// The room a model on a server of one's own can be set to have.
  static const List<int> roomChoices = <int>[8192, 16384, 32768, 65536, 131072];

  /// What requests go through.
  @protected
  final http.Client client;
  final bool _ownsClient;

  static const String providerId = 'openai';

  Uri _uri(String path) =>
      Uri.parse('${baseUrl.replaceFirst(RegExp(r'/+$'), '')}$path');

  /// The headers of every request: the key, if there is one.
  @protected
  Map<String, String> get headers => <String, String>{
    'content-type': 'application/json',
    if (apiKey != null && apiKey!.isNotEmpty) 'authorization': 'Bearer $apiKey',
  };

  @override
  Future<List<ModelInfo>> listModels() async {
    final http.Response response;
    try {
      response = await client
          .get(_uri('/models'), headers: headers)
          .timeout(const Duration(seconds: 10));
    } on Object catch (error) {
      throw unreachable(error);
    }
    refuse(response.statusCode, response.body);
    final body = jsonDecode(response.body) as Map<String, Object?>;
    return <ModelInfo>[
      for (final entry in (body['data'] as List<Object?>?) ?? const [])
        if (entry
            case final Map<String, Object?> model && {'id': final String id})
          ModelInfo(id: id, capabilities: _capabilities(model)),
    ]..sort((a, b) => a.id.compareTo(b.id));
  }

  /// What each model is listed as able to do, once asked; none if the
  /// list could not be had.
  Future<Map<String, ModelCapabilities>>? _listed;

  @override
  Future<ModelCapabilities> capabilitiesOf(String model) async {
    final listed = _listed ??= listModels().then(
      (models) => <String, ModelCapabilities>{
        for (final model in models) model.id: model.capabilities,
      },
      onError: (Object _) => const <String, ModelCapabilities>{},
    );
    return (await listed)[model] ?? _capabilities(const <String, Object?>{});
  }

  /// What the model listed as [entry] can do: what the listing says, and
  /// [defaults] where it does not — in [room], if it is set.
  ///
  /// Each service says it its own way: Requesty with `supports_…` flags
  /// and prices, OpenRouter with the parameters and inputs a model takes
  /// and its pricing, Mistral with its capabilities; and how many tokens a
  /// model takes as
  /// `context_window` (Requesty, Groq), `context_length` (OpenRouter),
  /// `max_context_length` (Mistral) or `max_model_len` (vLLM).
  ModelCapabilities _capabilities(Map<String, Object?> entry) {
    bool? said(Object? answer) => answer is bool ? answer : null;
    bool? among(Object? list, String item) =>
        list is List ? list.contains(item) : null;
    final parameters = entry['supported_parameters'];
    final modalities = switch (entry['architecture']) {
      {'input_modalities': final Object? list} => list,
      _ => null,
    };
    bool takes(String flag, String parameter) =>
        said(entry[flag]) ?? among(parameters, parameter) ?? false;
    final abilities = switch (entry['capabilities']) {
      final Map<String, Object?> map => map,
      _ => const <String, Object?>{},
    };
    return ModelCapabilities(
      vision:
          said(entry['supports_vision']) ??
          among(modalities, 'image') ??
          said(abilities['vision']) ??
          defaults.vision,
      tools:
          said(entry['supports_tool_calling']) ??
          among(parameters, 'tools') ??
          said(abilities['function_calling']) ??
          defaults.tools,
      reasoning:
          said(entry['supports_reasoning']) ??
          among(parameters, 'reasoning') ??
          defaults.reasoning,
      structuredOutput:
          takes('supports_output_json_schema', 'structured_outputs')
          ? StructuredOutput.schema
          : takes('supports_output_json_object', 'response_format')
          ? StructuredOutput.json
          : defaults.structuredOutput,
      nativeCitations: defaults.nativeCitations,
      nativeWebSearch: defaults.nativeWebSearch,
      price: _priceOf(entry) ?? defaults.price,
      contextTokens:
          room ??
          <Object?>[
            entry['context_window'],
            entry['context_length'],
            entry['max_context_length'],
            entry['max_model_len'],
          ].whereType<int>().firstOrNull ??
          defaults.contextTokens,
    );
  }

  /// What the model listed as [entry] costs, where the listing says: in
  /// dollars a token, as Requesty's `input_price` and `output_price`, or
  /// OpenRouter's `pricing` — dollars a search for its `web_search`.
  static ModelPrice? _priceOf(Map<String, Object?> entry) {
    double? dollars(Object? price) => switch (price) {
      final num n => n.toDouble(),
      final String s => double.tryParse(s),
      _ => null,
    };
    double? perMillion(Object? price) => switch (dollars(price)) {
      final perToken? => perToken * 1e6,
      null => null,
    };
    final pricing = switch (entry['pricing']) {
      final Map<Object?, Object?> map => map,
      _ => const <Object?, Object?>{},
    };
    final input = perMillion(entry['input_price'] ?? pricing['prompt']);
    final output = perMillion(entry['output_price'] ?? pricing['completion']);
    if (input == null || output == null) return null;
    return ModelPrice(
      input: input,
      output: output,
      cacheRead: perMillion(
        entry['cached_price'] ?? pricing['input_cache_read'],
      ),
      cacheWrite: perMillion(pricing['input_cache_write']),
      webSearch: dollars(pricing['web_search']) ?? 0,
    );
  }

  /// The request body for [request]: its sources numbered to be cited by,
  /// its messages as [userMessage], [toolCall] and [toolMessage] write
  /// them, and the form of its answer as [answerFormat] asks for it, held
  /// to it as [structuredOutput] can be.
  Map<String, Object?> body(
    ChatRequest request, {
    StructuredOutput structuredOutput = StructuredOutput.none,
  }) {
    var next = 1;
    String numbered(List<Source> sources) {
      final given = sources.where((s) => s.passages.isNotEmpty).toList();
      final text = CitationMarkers.write(given, first: next);
      next += given.length;
      return text;
    }

    final names = <String, String>{};
    final messages = <Map<String, Object?>>[
      <String, Object?>{
        'role': 'system',
        // How to cite, only where there is something to cite.
        'content': sourcesIn(request.messages).isEmpty
            ? request.system
            : '${request.system}\n\n${CitationMarkers.instructions}',
      },
    ];
    for (final message in request.messages) {
      if (message.role == ChatRole.assistant) {
        final calls = message.toolCalls;
        for (final call in calls) {
          names[call.id] = call.name;
        }
        messages.add(<String, Object?>{
          'role': 'assistant',
          'content': message.text,
          if (calls.isNotEmpty)
            'tool_calls': <Object?>[for (final call in calls) toolCall(call)],
        });
        continue;
      }
      final images = <ImagePart>[];
      for (final result in message.parts.whereType<ToolResultPart>()) {
        final out = StringBuffer(result.isError ? 'Error: ' : '');
        for (final inner in result.content) {
          switch (inner) {
            case TextPart(:final text):
              out.writeln(text);
            case SourcesPart(:final sources):
              out.write(numbered(sources));
            case ImagePart(:final label):
              // A tool's answer here is text alone; its images follow.
              images.add(inner);
              out.writeln('[$label: shown in the next message]');
            case ToolCallPart() || ToolResultPart() || NativePart():
              break;
          }
        }
        messages.add(
          toolMessage(result, '$out', name: names[result.callId] ?? ''),
        );
      }
      final content = <ChatPart>[
        for (final part in message.parts)
          ...switch (part) {
            TextPart(:final text) when text.isNotEmpty => <ChatPart>[part],
            SourcesPart(:final sources) => <ChatPart>[
              TextPart(numbered(sources)),
            ],
            ImagePart() => <ChatPart>[part],
            _ => const <ChatPart>[],
          },
        ...images,
      ];
      if (content.isNotEmpty) messages.add(userMessage(content));
    }
    return <String, Object?>{
      ...requestBody(request, messages, <Map<String, Object?>>[
        for (final tool in request.tools)
          <String, Object?>{
            'type': 'function',
            'function': <String, Object?>{
              'name': tool.name,
              'description': tool.description,
              'parameters': tool.schema,
            },
          },
      ]),
      if (request.answerSchema case final schema?)
        ...?answerFormat(schema, structuredOutput),
    };
  }

  /// What asks for an answer following [schema], as closely as [how]
  /// allows; null to ask in words alone.
  @protected
  Map<String, Object?>? answerFormat(
    Map<String, Object?> schema,
    StructuredOutput how,
  ) => switch (how) {
    StructuredOutput.none => null,
    StructuredOutput.json => <String, Object?>{
      'response_format': <String, Object?>{'type': 'json_object'},
    },
    StructuredOutput.schema => <String, Object?>{
      'response_format': <String, Object?>{
        'type': 'json_schema',
        'json_schema': <String, Object?>{'name': 'answer', 'schema': schema},
      },
    },
  };

  /// The body of a request for [request], of [messages] and [tools].
  @protected
  Map<String, Object?> requestBody(
    ChatRequest request,
    List<Map<String, Object?>> messages,
    List<Map<String, Object?>> tools,
  ) => <String, Object?>{
    'model': request.model,
    'stream': true,
    'stream_options': <String, Object?>{'include_usage': true},
    'messages': messages,
    if (tools.isNotEmpty) 'tools': tools,
  };

  /// A message of the person's, of [content]: text and images.
  @protected
  Map<String, Object?> userMessage(List<ChatPart> content) {
    // Plain text as a string, which every server takes.
    if (content.every((part) => part is TextPart)) {
      return <String, Object?>{
        'role': 'user',
        'content': content.map((part) => (part as TextPart).text).join('\n\n'),
      };
    }
    return <String, Object?>{
      'role': 'user',
      'content': <Object?>[
        for (final part in content)
          switch (part) {
            TextPart(:final text) => <String, Object?>{
              'type': 'text',
              'text': text,
            },
            ImagePart(:final mediaType, :final bytes) => <String, Object?>{
              'type': 'image_url',
              'image_url': <String, Object?>{
                'url': 'data:$mediaType;base64,${base64Encode(bytes)}',
              },
            },
            _ => throw ArgumentError.value(part, 'content'),
          },
      ],
    };
  }

  /// The model's asking for [call], as it is handed back.
  @protected
  Map<String, Object?> toolCall(ToolCallPart call) => <String, Object?>{
    'id': call.id,
    'type': 'function',
    'function': <String, Object?>{
      'name': call.name,
      'arguments': jsonEncode(call.input),
    },
  };

  /// What the tool [name] gave back for [result], written as [content].
  @protected
  Map<String, Object?> toolMessage(
    ToolResultPart result,
    String content, {
    required String name,
  }) => <String, Object?>{
    'role': 'tool',
    'tool_call_id': result.callId,
    'content': content,
  };

  @override
  Stream<ChatEvent> chat(ChatRequest request) async* {
    final answer = StreamedAnswer(sourcesIn(request.messages));
    final capabilities = await capabilitiesOf(request.model);
    final response = await send(
      _uri('/chat/completions'),
      body(request, structuredOutput: capabilities.structuredOutput),
      stop: request.stop,
    );

    final calls =
        <int, ({StringBuffer id, StringBuffer name, StringBuffer args})>{};
    var stop = StopReason.done;
    var usage = const Usage();
    await for (final event in serverEvents(response.stream)) {
      if (event.data.trim() == '[DONE]') break;
      final data = jsonDecode(event.data) as Map<String, Object?>;
      if (data['error'] case final Map<Object?, Object?> error) {
        throw AiException('$name stopped: ${error['message']}');
      }
      if (data['usage'] case final Map<Object?, Object?> used) {
        usage = _usage(used);
      }
      final choices = data['choices'] as List<Object?>?;
      if (choices == null || choices.isEmpty) continue;
      final choice = (choices.first! as Map).cast<String, Object?>();
      final delta =
          (choice['delta'] as Map?)?.cast<String, Object?>() ??
          const <String, Object?>{};
      final reasoning = delta['reasoning_content'] ?? delta['reasoning'];
      if (reasoning is String && reasoning.isNotEmpty) {
        yield Reasoning(withoutThinkTags(reasoning));
      }
      if (delta['content'] case final String piece when piece.isNotEmpty) {
        yield* Stream<ChatEvent>.fromIterable(answer.add(piece));
      }
      for (final call in (delta['tool_calls'] as List<Object?>?) ?? const []) {
        final json = (call! as Map).cast<String, Object?>();
        final index = json['index'] as int? ?? calls.length;
        final entry = calls[index] ??= (
          id: StringBuffer(),
          name: StringBuffer(),
          args: StringBuffer(),
        );
        if (json['id'] case final String id) entry.id.write(id);
        final function = (json['function'] as Map?)?.cast<String, Object?>();
        if (function?['name'] case final String part) entry.name.write(part);
        if (function?['arguments'] case final String part) {
          entry.args.write(part);
        }
      }
      stop = switch (choice['finish_reason']) {
        'tool_calls' || 'function_call' => StopReason.toolUse,
        'length' => StopReason.maxTokens,
        'content_filter' => StopReason.refusal,
        _ => stop,
      };
    }
    yield* Stream<ChatEvent>.fromIterable(answer.close());
    yield const CitedSpan(<Citation>[]);

    final toolCalls = <ToolCallPart>[
      for (final entry in calls.entries)
        ToolCallPart(
          id: entry.value.id.isEmpty
              ? 'call_${entry.key}'
              : '${entry.value.id}',
          name: '${entry.value.name}',
          input: _parseArguments('${entry.value.args}'),
        ),
    ];
    if (toolCalls.isNotEmpty) stop = StopReason.toolUse;
    yield MessageDone(
      ChatMessage.assistant(<ChatPart>[
        if (answer.text.isNotEmpty) TextPart(answer.text),
        ...toolCalls,
      ]),
      stop: stop,
      usage: usage,
    );
  }

  /// What a request took, as [used] says: its prompt's tokens, of them
  /// those read from what was kept (`prompt_tokens_details`), its
  /// completion's, and what it cost, where the service says (OpenRouter's
  /// `cost`).
  static Usage _usage(Map<Object?, Object?> used) {
    final prompt = used['prompt_tokens'] as int? ?? 0;
    final kept = switch (used['prompt_tokens_details']) {
      {'cached_tokens': final int tokens} => tokens,
      _ => 0,
    };
    return Usage(
      input: prompt - kept,
      cacheRead: kept,
      output: used['completion_tokens'] as int? ?? 0,
      cost: (used['cost'] as num?)?.toDouble(),
    );
  }

  static Map<String, Object?> _parseArguments(String json) {
    if (json.trim().isEmpty) return const <String, Object?>{};
    try {
      final parsed = jsonDecode(json);
      if (parsed is Map) return parsed.cast<String, Object?>();
    } on FormatException {
      // Answered below.
    }
    return <String, Object?>{invalidInputKey: json};
  }

  /// Where a tool's input that could not be read is kept.
  static const String invalidInputKey = '__invalid_json';

  /// Posts [body] to [uri], for the response streamed back — the request
  /// broken off as soon as [stop] completes. A server that will not hold
  /// the model to the form of answer [body] asks for, whatever its
  /// listing said, is asked again without, the form asked for in words
  /// alone.
  @protected
  Future<http.StreamedResponse> send(
    Uri uri,
    Map<String, Object?> body, {
    Future<void>? stop,
  }) async {
    try {
      return await _post(uri, body, stop: stop);
    } on AiException catch (error) {
      // Where the body asks for the form of its answer, as [answerFormat]
      // writes it.
      final format = <String>{
        for (final how in StructuredOutput.values)
          ...?answerFormat(const <String, Object?>{}, how)?.keys,
      };
      if (!format.any(body.containsKey) ||
          !(error.status == 400 || error.status == 422)) {
        rethrow;
      }
      return _post(uri, <String, Object?>{
        for (final entry in body.entries)
          if (!format.contains(entry.key)) entry.key: entry.value,
      }, stop: stop);
    }
  }

  Future<http.StreamedResponse> _post(
    Uri uri,
    Map<String, Object?> body, {
    Future<void>? stop,
  }) async {
    final request = http.AbortableRequest('POST', uri, abortTrigger: stop)
      ..headers.addAll(headers)
      ..body = jsonEncode(body);
    final http.StreamedResponse response;
    try {
      response = await client.send(request);
    } on Object catch (error) {
      throw unreachable(error);
    }
    if (response.statusCode != 200) {
      refuse(response.statusCode, await response.stream.bytesToString());
    }
    return response;
  }

  /// Why [baseUrl] could not be reached, from [error].
  @protected
  AiException unreachable(Object error) => AiException(
    '$name could not be reached at $baseUrl. Is it running?',
    retryable: true,
    cause: error,
  );

  /// Throws why the server refused a request, with [status] and [body],
  /// unless it did not.
  @protected
  void refuse(int status, String body) {
    if (status == 200) return;
    String? message;
    try {
      final error = (jsonDecode(body) as Map)['error'];
      message = error is Map ? error['message'] as String? : error?.toString();
    } on Object {
      // The status says enough.
    }
    throw switch (status) {
      401 || 403 => AiException(
        '$name refused the API key. Check it in the AI settings.',
      ),
      404 => AiException(
        '$name does not have that model${message == null ? '' : ': $message'}',
      ),
      429 => AiException(
        'Too many requests to $name just now. Try again in a moment.',
        retryable: true,
      ),
      >= 500 => AiException(
        '$name had a problem${message == null ? '' : ': $message'}',
        retryable: true,
      ),
      _ => AiException(
        '$name refused the request: ${message ?? status}',
        status: status,
      ),
    };
  }

  @override
  void close() {
    if (_ownsClient) client.close();
  }
}
