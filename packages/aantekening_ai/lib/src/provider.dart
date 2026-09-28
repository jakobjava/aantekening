/// What every model provider offers, whoever runs the model.
library;

import 'dart:convert';

import 'conversation.dart';

/// How closely a provider can hold a model to the form of answer asked
/// for.
enum StructuredOutput {
  /// Not at all: the model is only asked, in words.
  none,

  /// To JSON, of whatever shape.
  json,

  /// To JSON of the shape a schema gives.
  schema,
}

/// What a model costs, in US dollars: per million tokens it reads and
/// writes, and per web search.
class ModelPrice {
  const ModelPrice({
    required this.input,
    required this.output,
    double? cacheRead,
    double? cacheWrite,
    this.webSearch = 0,
  }) : cacheRead = cacheRead ?? input,
       cacheWrite = cacheWrite ?? input;

  /// What a model on this computer, or one's own server, costs.
  static const ModelPrice free = ModelPrice(input: 0, output: 0);

  /// Per million tokens read afresh.
  final double input;

  /// Per million tokens written, its reasoning with its answer.
  final double output;

  /// Per million tokens read from what the provider kept of an earlier
  /// request: as [input], where it is not said.
  final double cacheRead;

  /// Per million tokens kept for a later request to read: as [input],
  /// where it is not said.
  final double cacheWrite;

  /// Per search of the web.
  final double webSearch;

  bool get isFree => input == 0 && output == 0 && webSearch == 0;

  /// What [usage] costs at these prices.
  double of(Usage usage) =>
      (usage.input * input +
              usage.output * output +
              usage.cacheRead * cacheRead +
              usage.cacheWrite * cacheWrite) /
          1e6 +
      usage.webSearches * webSearch;
}

/// What a model can do, which decides how it is asked.
class ModelCapabilities {
  const ModelCapabilities({
    this.vision = false,
    this.tools = false,
    this.nativeCitations = false,
    this.nativeWebSearch = false,
    this.reasoning = false,
    this.structuredOutput = StructuredOutput.none,
    this.contextTokens = 32000,
    this.price,
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

  /// How closely it can be held to the JSON asked for.
  final StructuredOutput structuredOutput;

  /// How much it can be given at once, in tokens: what it is given, what
  /// it thinks and what it answers, together.
  final int contextTokens;

  /// What it costs, or null where the provider does not say.
  final ModelPrice? price;
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
    this.answerSchema,
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

  /// The JSON Schema the answer is to follow, or null for prose. The
  /// system prompt asks for it in words as well: a provider holds the
  /// model to it only as closely as it can ([StructuredOutput]).
  final Map<String, Object?>? answerSchema;
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

/// What a request cost: the tokens it took, and, where the provider says,
/// the money.
class Usage {
  const Usage({
    this.input = 0,
    this.output = 0,
    this.cacheRead = 0,
    this.cacheWrite = 0,
    this.webSearches = 0,
    this.cost,
  });

  /// Tokens read afresh.
  final int input;
  final int output;

  /// Tokens read from what the provider kept of an earlier request.
  final int cacheRead;

  /// Tokens kept for a later request to read.
  final int cacheWrite;
  final int webSearches;

  /// What the provider charged, in US dollars, where it says.
  final double? cost;

  bool get isEmpty => input + output + cacheRead + cacheWrite == 0;

  /// What it cost: as the provider said, or at [price] — null where
  /// neither is known.
  double? costAt(ModelPrice? price) => cost ?? price?.of(this);

  Usage operator +(Usage other) => Usage(
    input: input + other.input,
    output: output + other.output,
    cacheRead: cacheRead + other.cacheRead,
    cacheWrite: cacheWrite + other.cacheWrite,
    webSearches: webSearches + other.webSearches,
    cost: cost == null && other.cost == null
        ? null
        : (cost ?? 0) + (other.cost ?? 0),
  );
}

/// A provider failing: unreachable, refusing the key, overloaded.
class AiException implements Exception {
  const AiException(
    this.message, {
    this.retryable = false,
    this.cause,
    this.status,
  });

  final String message;

  /// The HTTP status the provider refused the request with, if it did.
  final int? status;

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
