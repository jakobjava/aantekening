/// Claude, through Anthropic's Messages API.
library;

import 'dart:async';
import 'dart:convert';

import 'package:aantekening_core/aantekening_core.dart';
import 'package:http/http.dart' as http;

import 'conversation.dart';
import 'provider.dart';
import 'sse.dart';

/// Talks to Anthropic's Messages API over HTTP, streaming.
///
/// Notes are given as search results, which Claude cites itself, down to
/// the passage; the web is searched by Anthropic's own search tool, cited
/// the same way. What Claude gives back is kept block for block, to be
/// handed back as it came: its reasoning, its searches.
class AnthropicProvider implements ChatProvider {
  AnthropicProvider({
    required this.apiKey,
    this.baseUrl = defaultBaseUrl,
    http.Client? client,
  }) : _http = client ?? http.Client(),
       _ownsClient = client == null;

  static const String defaultBaseUrl = 'https://api.anthropic.com';

  /// The model used unless another is chosen.
  static const String defaultModel = 'claude-opus-5';

  static const String providerId = 'anthropic';

  final String apiKey;
  final String baseUrl;
  final http.Client _http;
  final bool _ownsClient;

  @override
  String get name => 'Anthropic';

  Map<String, String> _headers({bool fallbacks = false}) => <String, String>{
    'content-type': 'application/json',
    'x-api-key': apiKey,
    'anthropic-version': '2023-06-01',
    if (fallbacks) 'anthropic-beta': 'server-side-fallback-2026-07-01',
  };

  Uri _uri(String path) => Uri.parse('$baseUrl$path');

  @override
  Future<List<ModelInfo>> listModels() async {
    final response = await _http
        .get(_uri('/v1/models?limit=100'), headers: _headers())
        .timeout(const Duration(seconds: 20));
    _check(response.statusCode, response.body);
    final body = jsonDecode(response.body) as Map<String, Object?>;
    return <ModelInfo>[
      for (final entry in (body['data'] as List<Object?>?) ?? const [])
        if (entry case final Map<String, Object?> model)
          ModelInfo(
            id: model['id']! as String,
            name: model['display_name'] as String?,
            capabilities: _capabilities(
              model['id']! as String,
              model['max_input_tokens'] as int?,
            ),
          ),
    ];
  }

  @override
  Future<ModelCapabilities> capabilitiesOf(String model) async =>
      _capabilities(model, null);

  static ModelCapabilities _capabilities(String model, int? context) =>
      ModelCapabilities(
        vision: true,
        tools: true,
        nativeCitations: true,
        nativeWebSearch: true,
        contextTokens:
            context ?? (model.startsWith('claude-haiku') ? 200000 : 1000000),
      );

  /// Whether [model] declines by refusal, and so is asked with a fallback
  /// to another model that may answer instead.
  static bool _refuses(String model) =>
      model.startsWith('claude-opus-5') ||
      model.startsWith('claude-fable-5') ||
      model.startsWith('claude-mythos-5');

  /// The web search tool [model] takes: filtering results with code on the
  /// models that can, plain on the others.
  static String _webSearchTool(String model) => model.startsWith('claude-haiku')
      ? 'web_search_20250305'
      : 'web_search_20260209';

  /// The request body for [request].
  Map<String, Object?> body(ChatRequest request) => <String, Object?>{
    'model': request.model,
    'max_tokens': request.maxTokens ?? 64000,
    'stream': true,
    // Everything before the newest message is cached: the instructions, the
    // tools, and the notes given with the first question.
    'cache_control': <String, Object?>{'type': 'ephemeral'},
    if (_refuses(request.model)) 'fallbacks': 'default',
    'system': <Object?>[
      <String, Object?>{'type': 'text', 'text': request.system},
    ],
    'tools': <Object?>[
      for (final tool in request.tools)
        <String, Object?>{
          'name': tool.name,
          'description': tool.description,
          'input_schema': tool.schema,
          'eager_input_streaming': true,
        },
      if (request.webSearch)
        <String, Object?>{
          'type': _webSearchTool(request.model),
          'name': 'web_search',
          'max_uses': 5,
        },
    ],
    'messages': <Object?>[
      for (final message in request.messages) _message(message),
    ],
  };

  Map<String, Object?> _message(ChatMessage message) {
    final native = message.parts
        .whereType<NativePart>()
        .where((part) => part.provider == providerId)
        .firstOrNull;
    // A turn Claude wrote goes back exactly as it came.
    if (message.role == ChatRole.assistant && native != null) {
      return <String, Object?>{
        'role': 'assistant',
        'content': native.block['content'],
      };
    }
    return <String, Object?>{
      'role': message.role.name,
      'content': <Object?>[
        // Tool results come first in a message, as the API has them.
        for (final part in message.parts)
          if (part is ToolResultPart) _toolResult(part),
        for (final part in message.parts)
          if (part is! ToolResultPart) ...?_block(part),
      ],
    };
  }

  Map<String, Object?> _toolResult(ToolResultPart part) {
    assert(
      part.content.every((p) => p is SourcesPart) ||
          part.content.every((p) => p is! SourcesPart),
      'a tool result gives sources alone, or no sources',
    );
    return _toolResultBlock(part);
  }

  Map<String, Object?> _toolResultBlock(
    ToolResultPart part,
  ) => <String, Object?>{
    'type': 'tool_result',
    'tool_use_id': part.callId,
    'content': <Object?>[for (final inner in part.content) ...?_block(inner)],
    if (part.isError) 'is_error': true,
  };

  List<Map<String, Object?>>? _block(ChatPart part) => switch (part) {
    TextPart(:final text) when text.isNotEmpty => <Map<String, Object?>>[
      <String, Object?>{'type': 'text', 'text': text},
    ],
    TextPart() => null,
    ImagePart(:final bytes, :final mediaType) => <Map<String, Object?>>[
      <String, Object?>{
        'type': 'image',
        'source': <String, Object?>{
          'type': 'base64',
          'media_type': mediaType,
          'data': base64Encode(bytes),
        },
      },
    ],
    SourcesPart(:final sources) => <Map<String, Object?>>[
      for (final source in sources)
        if (source.passages.isNotEmpty)
          <String, Object?>{
            'type': 'search_result',
            'source': source.uri,
            'title': source.context == null
                ? source.title
                : '${source.title} — ${source.context}',
            'content': <Object?>[
              for (final passage in source.passages)
                <String, Object?>{'type': 'text', 'text': passage.text},
            ],
            'citations': <String, Object?>{'enabled': true},
          },
    ],
    ToolCallPart(:final id, :final name, :final input) =>
      <Map<String, Object?>>[
        <String, Object?>{
          'type': 'tool_use',
          'id': id,
          'name': name,
          'input': input,
        },
      ],
    // Results are placed by [_message]; another provider's own parts mean
    // nothing here.
    ToolResultPart() || NativePart() => null,
  };

  @override
  Stream<ChatEvent> chat(ChatRequest request) async* {
    final sources = sourcesIn(request.messages);
    final httpRequest =
        http.AbortableRequest(
            'POST',
            _uri('/v1/messages'),
            abortTrigger: request.stop,
          )
          ..headers.addAll(_headers(fallbacks: _refuses(request.model)))
          ..body = jsonEncode(body(request));
    final http.StreamedResponse response;
    try {
      response = await _http.send(httpRequest);
    } on Object catch (error) {
      throw AiException(
        'Anthropic could not be reached. Check the connection.',
        retryable: true,
        cause: error,
      );
    }
    if (response.statusCode != 200) {
      _check(response.statusCode, await response.stream.bytesToString());
    }

    final blocks = <Map<String, Object?>>[];
    final partialJson = <int, StringBuffer>{};
    var usage = const Usage();
    var stop = StopReason.done;
    await for (final event in serverEvents(response.stream)) {
      final data = jsonDecode(event.data) as Map<String, Object?>;
      switch (data['type']) {
        case 'message_start':
          final message = data['message']! as Map<String, Object?>;
          usage = usage + _usage(message['usage']);
        case 'content_block_start':
          final block = Map<String, Object?>.of(
            (data['content_block']! as Map).cast<String, Object?>(),
          );
          blocks.add(block);
          if (block['type'] == 'web_search_tool_result') {
            final results = block['content'];
            if (results is List && results.isNotEmpty) {
              yield Activity('Read ${results.length} results from the web');
            }
          }
        case 'content_block_delta':
          final index = data['index']! as int;
          final block = blocks[index];
          final delta = (data['delta']! as Map).cast<String, Object?>();
          switch (delta['type']) {
            case 'text_delta':
              final text = delta['text']! as String;
              block['text'] = '${block['text'] ?? ''}$text';
              yield TextDelta(text);
            case 'input_json_delta':
              (partialJson[index] ??= StringBuffer()).write(
                delta['partial_json'],
              );
            case 'citations_delta':
              block['citations'] = <Object?>[
                ...?(block['citations'] as List<Object?>?),
                delta['citation'],
              ];
            case 'thinking_delta':
              final thought = delta['thinking']! as String;
              block['thinking'] = '${block['thinking'] ?? ''}$thought';
              yield Reasoning(thought);
            case 'signature_delta':
              block['signature'] = delta['signature'];
          }
        case 'content_block_stop':
          final index = data['index']! as int;
          final block = blocks[index];
          final json = partialJson.remove(index)?.toString();
          if (json != null) block['input'] = _parseInput(json);
          switch (block['type']) {
            case 'text':
              yield CitedSpan(<Citation>[
                for (final c
                    in (block['citations'] as List<Object?>?) ?? const [])
                  ?_citation((c! as Map).cast<String, Object?>(), sources),
              ]);
            case 'server_tool_use' when block['name'] == 'web_search':
              final query = (block['input'] as Map?)?['query'];
              yield Activity(
                query is String
                    ? 'Searching the web for “$query”'
                    : 'Searching the web',
              );
          }
        case 'message_delta':
          final delta = (data['delta']! as Map).cast<String, Object?>();
          stop = _stop(delta['stop_reason'] as String?);
          usage = usage + _usage(data['usage']);
        case 'error':
          final error = (data['error']! as Map).cast<String, Object?>();
          throw AiException(
            error['type'] == 'overloaded_error'
                ? 'Anthropic is busy just now. Try again in a moment.'
                : 'Anthropic stopped: ${error['message']}',
            retryable: error['type'] == 'overloaded_error',
          );
      }
    }

    final content = _echoable(blocks);
    yield MessageDone(
      ChatMessage.assistant(<ChatPart>[
        for (final block in content) ...?_neutral(block, sources),
        NativePart(providerId, <String, Object?>{'content': content}),
      ]),
      stop: stop,
      usage: usage,
    );
  }

  /// [blocks] as they can be handed back. After a fallback to another model
  /// part way through, what the declining model began — its reasoning, its
  /// tool calls — is left out, as the API has it.
  static List<Map<String, Object?>> _echoable(
    List<Map<String, Object?>> blocks,
  ) {
    final last = blocks.lastIndexWhere((block) => block['type'] == 'fallback');
    if (last < 0) return blocks;
    final answered = <Object?>{
      for (final block in blocks)
        if (block['tool_use_id'] != null) block['tool_use_id'],
    };
    return <Map<String, Object?>>[
      for (var i = 0; i < blocks.length; i++)
        if (i > last ||
            switch (blocks[i]['type']) {
              'thinking' || 'redacted_thinking' || 'tool_use' => false,
              'server_tool_use' => answered.contains(blocks[i]['id']),
              _ => true,
            })
          blocks[i],
    ];
  }

  /// [block] in the terms every provider shares, or null for one only
  /// Claude understands.
  static List<ChatPart>? _neutral(
    Map<String, Object?> block,
    List<Source> sources,
  ) => switch (block['type']) {
    'text' => <ChatPart>[
      TextPart(
        block['text'] as String? ?? '',
        citations: <Citation>[
          for (final c in (block['citations'] as List<Object?>?) ?? const [])
            ?_citation((c! as Map).cast<String, Object?>(), sources),
        ],
      ),
    ],
    'tool_use' => <ChatPart>[
      ToolCallPart(
        id: block['id']! as String,
        name: block['name']! as String,
        input:
            (block['input'] as Map?)?.cast<String, Object?>() ??
            const <String, Object?>{},
      ),
    ],
    _ => null,
  };

  static Citation? _citation(Map<String, Object?> json, List<Source> sources) {
    switch (json['type']) {
      case 'search_result_location':
        final index = json['search_result_index'] as int?;
        final source = index != null && index < sources.length
            ? sources[index]
            : null;
        if (source == null) return null;
        final block = json['start_block_index'] as int? ?? 0;
        final last = (json['end_block_index'] as int? ?? block + 1) - 1;
        return Citation(
          uri: block < source.passages.length
              ? _span(source.passages, block, last)
              : source.uri,
          title: source.title,
          origin: source.origin,
          quote: json['cited_text'] as String?,
        );
      case 'web_search_result_location':
        return Citation(
          uri: json['url']! as String,
          title: json['title'] as String? ?? json['url']! as String,
          origin: SourceOrigin.web,
          quote: json['cited_text'] as String?,
        );
    }
    return null;
  }

  /// Where passages [first] to [last] of [passages] are: the words from
  /// the one to the other where they are sentences of one paragraph, else
  /// the first.
  static String _span(List<SourcePassage> passages, int first, int last) {
    final start = passages[first].uri;
    if (last <= first || last >= passages.length) return start;
    final from = NoteLink.tryParse(start);
    final to = NoteLink.tryParse(passages[last].uri);
    final a = from?.words;
    final b = to?.words;
    if (from == null || to == null || a == null || b == null) return start;
    final same =
        from.id == to.id &&
        from.elementId == to.elementId &&
        from.block == to.block;
    return same ? from.toWords(a.from, b.to).toString() : start;
  }

  /// A tool's input as streamed, or, where it came through broken, what
  /// arrived, for the model to be told so.
  static Map<String, Object?> _parseInput(String json) {
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

  static StopReason _stop(String? reason) => switch (reason) {
    'tool_use' => StopReason.toolUse,
    'max_tokens' || 'model_context_window_exceeded' => StopReason.maxTokens,
    'refusal' => StopReason.refusal,
    'pause_turn' => StopReason.paused,
    _ => StopReason.done,
  };

  static Usage _usage(Object? json) {
    if (json is! Map) return const Usage();
    final server = json['server_tool_use'];
    return Usage(
      input: json['input_tokens'] as int? ?? 0,
      output: json['output_tokens'] as int? ?? 0,
      cacheRead: json['cache_read_input_tokens'] as int? ?? 0,
      webSearches: server is Map
          ? server['web_search_requests'] as int? ?? 0
          : 0,
    );
  }

  static void _check(int status, String body) {
    if (status == 200) return;
    String? message;
    try {
      final error = (jsonDecode(body) as Map)['error'];
      if (error is Map) message = error['message'] as String?;
    } on Object {
      // The status says enough.
    }
    throw switch (status) {
      401 || 403 => const AiException(
        'Anthropic refused the API key. Check it in the AI settings.',
      ),
      429 => const AiException(
        'Too many requests to Anthropic just now. Try again in a moment.',
        retryable: true,
      ),
      529 || >= 500 => const AiException(
        'Anthropic is busy just now. Try again in a moment.',
        retryable: true,
      ),
      _ => AiException('Anthropic refused the request: ${message ?? status}'),
    };
  }

  @override
  void close() {
    if (_ownsClient) _http.close();
  }
}
