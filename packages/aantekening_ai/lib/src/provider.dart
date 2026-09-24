/// What every model provider offers, whoever runs the model.
library;

import 'dart:convert';

import 'conversation.dart';

/// What a model can do, which decides how it is asked.
class ModelCapabilities {
  const ModelCapabilities({
    this.vision = false,
    this.tools = false,
    this.nativeCitations = false,
    this.nativeWebSearch = false,
    this.reasoning = false,
    this.contextTokens = 32000,
  });

  /// Whether it can look at images: a PDF page with writing over it.
  final bool vision;

  /// Whether it can ask for tools to be run — to search the notes, read a
  /// page, look at a drawing. Without, it gets what it needs up front.
  final bool tools;

  /// Whether the provider cites sources itself, down to the passage;
  /// without, the model cites with markers the app reads.
  final bool nativeCitations;

  /// Whether the provider can search the web itself.
  final bool nativeWebSearch;

  /// Whether it can think before it answers — better answers, and, on a
  /// slow computer, many minutes before the first word.
  final bool reasoning;

  /// How much it can be given at once, in tokens: what it is given, what
  /// it thinks and what it answers, together.
  final int contextTokens;
}

/// A model a provider has, and what it can do.
class ModelInfo {
  const ModelInfo({required this.id, required this.capabilities, String? name})
    : name = name ?? id;

  final String id;
  final String name;
  final ModelCapabilities capabilities;

  @override
  String toString() => name;
}

/// A tool the app runs when a model asks for it.
class ToolSpec {
  const ToolSpec({
    required this.name,
    required this.description,
    required this.parameters,
    this.required = const <String>[],
  });

  final String name;

  /// When to use it, and what it gives back.
  final String description;

  /// Each parameter's JSON Schema, by name.
  final Map<String, Map<String, Object?>> parameters;
  final List<String> required;

  Map<String, Object?> get schema => <String, Object?>{
    'type': 'object',
    'properties': parameters,
    'required': required,
    'additionalProperties': false,
  };
}

class ChatRequest {
  const ChatRequest({
    required this.model,
    required this.system,
    required this.messages,
    this.tools = const <ToolSpec>[],
    this.webSearch = false,
    this.maxTokens,
    this.stop,
  });

  final String model;

  /// Standing instructions, kept apart from what the person asks.
  final String system;
  final List<ChatMessage> messages;
  final List<ToolSpec> tools;

  /// Whether the provider may search the web itself, where it can.
  final bool webSearch;
  final int? maxTokens;

  /// Completes once the answer is no longer wanted, which breaks the
  /// request off at once — even while the model is still reading it, and
  /// sends nothing back to notice it by.
  final Future<void>? stop;
}

/// Roughly how much a model is given to read: tokens, reckoned at four
/// characters each, and pictures, which cost what the provider says.
class PromptSize {
  const PromptSize({this.tokens = 0, this.images = 0});

  /// How much of [messages] there is, with [system] and [tools] if given.
  factory PromptSize.of(
    Iterable<ChatMessage> messages, {
    String system = '',
    List<ToolSpec> tools = const <ToolSpec>[],
  }) {
    var characters = system.length;
    var images = 0;
    void count(ChatPart part) {
      switch (part) {
        case ImagePart():
          images++;
        case ToolResultPart(:final content):
          content.forEach(count);
        default:
          characters += jsonEncode(part.toJson()).length;
      }
    }

    for (final message in messages) {
      message.parts.forEach(count);
    }
    for (final tool in tools) {
      characters += tool.description.length + jsonEncode(tool.schema).length;
    }
    return PromptSize(tokens: (characters / 4).ceil(), images: images);
  }

  final int tokens;
  final int images;

  bool get isEmpty => tokens == 0 && images == 0;
}

/// Something that happened while a model answered.
sealed class ChatEvent {
  const ChatEvent();
}

/// More of the answer's text.
final class TextDelta extends ChatEvent {
  const TextDelta(this.text);
  final String text;
}

/// The answer's text since the last such event draws on [citations] —
/// none, for text drawing on nothing given, or where only a boundary is
/// meant.
final class CitedSpan extends ChatEvent {
  const CitedSpan(this.citations);
  final List<Citation> citations;
}

/// More of what the model reasons before it answers — shown while it
/// thinks, and no part of the answer.
final class Reasoning extends ChatEvent {
  const Reasoning(this.text);
  final String text;
}

/// What the model is doing that is not writing: searching the web, say.
final class Activity extends ChatEvent {
  const Activity(this.description);
  final String description;
}

/// The answer is done: here it is whole, as the provider gave it, to be
/// kept and handed back, and why it stopped.
final class MessageDone extends ChatEvent {
  const MessageDone(this.message, {required this.stop, this.usage});
  final ChatMessage message;
  final StopReason stop;
  final Usage? usage;
}

/// Why a model stopped.
enum StopReason {
  /// It finished.
  done,

  /// It wants tools run.
  toolUse,

  /// It ran out of room to write.
  maxTokens,

  /// It declined.
  refusal,

  /// The provider paused a long turn, to be sent back as it is to go on.
  paused,
}

/// What a request cost, in tokens.
class Usage {
  const Usage({
    this.input = 0,
    this.output = 0,
    this.cacheRead = 0,
    this.webSearches = 0,
  });

  final int input;
  final int output;
  final int cacheRead;
  final int webSearches;

  Usage operator +(Usage other) => Usage(
    input: input + other.input,
    output: output + other.output,
    cacheRead: cacheRead + other.cacheRead,
    webSearches: webSearches + other.webSearches,
  );
}

/// A provider failing: unreachable, refusing the key, overloaded.
class AiException implements Exception {
  const AiException(this.message, {this.retryable = false, this.cause});

  final String message;

  /// Whether trying again later may work.
  final bool retryable;
  final Object? cause;

  @override
  String toString() => message;
}

/// Something that runs models: a service on the web, or a runtime on this
/// machine. Everything else in the app talks to models through this, so a
/// provider is one class and the features are written once.
abstract interface class ChatProvider {
  /// A short name for what it talks to, for the notes it keeps with an
  /// answer.
  String get name;

  /// The models it has.
  Future<List<ModelInfo>> listModels();

  /// What [model] can do.
  Future<ModelCapabilities> capabilitiesOf(String model);

  /// Answers [request], as it is written.
  Stream<ChatEvent> chat(ChatRequest request);

  void close();
}

/// Every source given in [messages] with something in it to cite, in the
/// order given: how both kinds of citation — a provider's own, by index,
/// and markers, by number — find the source they mean. A source with no
/// passages is not given at all.
List<Source> sourcesIn(List<ChatMessage> messages) => <Source>[
  for (final message in messages)
    for (final part in message.parts)
      ...switch (part) {
        SourcesPart(:final sources) => sources,
        ToolResultPart(:final content) => <Source>[
          for (final inner in content)
            if (inner is SourcesPart) ...inner.sources,
        ],
        _ => const <Source>[],
      }.where((source) => source.passages.isNotEmpty),
];
