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
        if (entry case {'id': final String id})
          ModelInfo(id: id, capabilities: defaults),
    ]..sort((a, b) => a.id.compareTo(b.id));
  }

  @override
  Future<ModelCapabilities> capabilitiesOf(String model) async => defaults;

  /// The request body for [request]: its sources numbered to be cited by,
  /// and its messages as [userMessage], [toolCall] and [toolMessage] write
  /// them.
  Map<String, Object?> body(ChatRequest request) {
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
    return requestBody(request, messages, <Map<String, Object?>>[
      for (final tool in request.tools)
        <String, Object?>{
          'type': 'function',
          'function': <String, Object?>{
            'name': tool.name,
            'description': tool.description,
            'parameters': tool.schema,
          },
        },
    ]);
  }

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
    final response = await send(
      _uri('/chat/completions'),
      body(request),
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
        usage = Usage(
          input: used['prompt_tokens'] as int? ?? 0,
          output: used['completion_tokens'] as int? ?? 0,
        );
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
  /// broken off as soon as [stop] completes.
  @protected
  Future<http.StreamedResponse> send(
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
      _ => AiException('$name refused the request: ${message ?? status}'),
    };
  }

  @override
  void close() {
    if (_ownsClient) client.close();
  }
}
