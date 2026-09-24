/// A conversation with a model, the same whichever provider runs it.
library;

import 'dart:typed_data';

/// Who said something.
enum ChatRole { user, assistant }

/// Where a source comes from: the person's own notes, or the web. Kept
/// apart all the way to the screen, so an answer never passes off what it
/// found on the web as something the person wrote.
enum SourceOrigin { notes, web }

/// A unit of a [Source] that can be cited on its own: a paragraph, a row of
/// a table, a search result's snippet.
class SourcePassage {
  const SourcePassage(this.text, {required this.uri, this.follows = false});

  final String text;

  /// Where the passage is: a link to the place on a page — to the very
  /// sentence, where it is one — or a web address.
  final String uri;

  /// Whether it goes on from the passage before, in the same paragraph: a
  /// sentence after the first.
  final bool follows;

  Map<String, Object?> toJson() => <String, Object?>{
    'text': text,
    'uri': uri,
    if (follows) 'follows': true,
  };

  static SourcePassage fromJson(Map<String, Object?> json) => SourcePassage(
    json['text']! as String,
    uri: json['uri']! as String,
    follows: json['follows'] == true,
  );
}

/// Material a model is given to draw on, and to cite: a page of notes, or a
/// web page it found.
class Source {
  const Source({
    required this.uri,
    required this.title,
    required this.origin,
    required this.passages,
    this.context,
  });

  /// A link to the page, or a web address.
  final String uri;
  final String title;
  final SourceOrigin origin;
  final List<SourcePassage> passages;

  /// A line saying where it sits: the notebook and section a page is in,
  /// when it was written.
  final String? context;

  Map<String, Object?> toJson() => <String, Object?>{
    'uri': uri,
    'title': title,
    'origin': origin.name,
    'passages': <Object?>[for (final p in passages) p.toJson()],
    if (context != null) 'context': context,
  };

  static Source fromJson(Map<String, Object?> json) => Source(
    uri: json['uri']! as String,
    title: json['title']! as String,
    origin: SourceOrigin.values.byName(json['origin']! as String),
    passages: <SourcePassage>[
      for (final p in json['passages']! as List<Object?>)
        SourcePassage.fromJson((p! as Map).cast<String, Object?>()),
    ],
    context: json['context'] as String?,
  );
}

/// What an answer cites: which source, and where in it.
class Citation {
  const Citation({
    required this.uri,
    required this.title,
    required this.origin,
    this.quote,
  });

  /// The passage cited — a place on a page, or a web address.
  final String uri;
  final String title;
  final SourceOrigin origin;

  /// The words cited, where the provider says what they are.
  final String? quote;

  Map<String, Object?> toJson() => <String, Object?>{
    'uri': uri,
    'title': title,
    'origin': origin.name,
    if (quote != null) 'quote': quote,
  };

  static Citation fromJson(Map<String, Object?> json) => Citation(
    uri: json['uri']! as String,
    title: json['title']! as String,
    origin: SourceOrigin.values.byName(json['origin']! as String),
    quote: json['quote'] as String?,
  );

  @override
  bool operator ==(Object other) =>
      other is Citation && other.uri == uri && other.origin == origin;

  @override
  int get hashCode => Object.hash(uri, origin);
}

/// One part of a message.
sealed class ChatPart {
  const ChatPart();

  Map<String, Object?> toJson();

  static ChatPart fromJson(Map<String, Object?> json) => switch (json['type']) {
    'text' => TextPart(
      json['text']! as String,
      citations: <Citation>[
        for (final c in (json['citations'] as List<Object?>?) ?? const [])
          Citation.fromJson((c! as Map).cast<String, Object?>()),
      ],
    ),
    'sources' => SourcesPart(<Source>[
      for (final s in json['sources']! as List<Object?>)
        Source.fromJson((s! as Map).cast<String, Object?>()),
    ]),
    'tool_call' => ToolCallPart(
      id: json['id']! as String,
      name: json['name']! as String,
      input: (json['input']! as Map).cast<String, Object?>(),
    ),
    'tool_result' => ToolResultPart(
      callId: json['callId']! as String,
      content: <ChatPart>[
        for (final c in json['content']! as List<Object?>)
          ChatPart.fromJson((c! as Map).cast<String, Object?>()),
      ],
      isError: json['isError'] == true,
    ),
    'native' => NativePart(
      json['provider']! as String,
      (json['block']! as Map).cast<String, Object?>(),
    ),
    // An image is not kept (see [ImagePart.toJson]); a placeholder is.
    _ => TextPart(json['text'] as String? ?? ''),
  };
}

/// Text, and what it cites.
final class TextPart extends ChatPart {
  const TextPart(this.text, {this.citations = const <Citation>[]});

  final String text;
  final List<Citation> citations;

  @override
  Map<String, Object?> toJson() => <String, Object?>{
    'type': 'text',
    'text': text,
    if (citations.isNotEmpty)
      'citations': <Object?>[for (final c in citations) c.toJson()],
  };
}

/// A picture to look at: a PDF page drawn with the writing over it, say.
final class ImagePart extends ChatPart {
  const ImagePart(this.bytes, {required this.mediaType, required this.label});

  final Uint8List bytes;
  final String mediaType;

  /// What it is, said in words: kept when the image is not.
  final String label;

  /// Images are not kept with a conversation — they can be drawn again
  /// from the page — so they are written as what they showed.
  @override
  Map<String, Object?> toJson() => <String, Object?>{
    'type': 'text',
    'text': '[Image shown earlier: $label]',
  };
}

/// Sources to draw on and cite.
final class SourcesPart extends ChatPart {
  const SourcesPart(this.sources);

  final List<Source> sources;

  @override
  Map<String, Object?> toJson() => <String, Object?>{
    'type': 'sources',
    'sources': <Object?>[for (final s in sources) s.toJson()],
  };
}

/// The model asking for a tool to be run.
final class ToolCallPart extends ChatPart {
  const ToolCallPart({
    required this.id,
    required this.name,
    required this.input,
  });

  final String id;
  final String name;
  final Map<String, Object?> input;

  @override
  Map<String, Object?> toJson() => <String, Object?>{
    'type': 'tool_call',
    'id': id,
    'name': name,
    'input': input,
  };
}

/// What a tool gave back.
final class ToolResultPart extends ChatPart {
  const ToolResultPart({
    required this.callId,
    required this.content,
    this.isError = false,
  });

  final String callId;

  /// Text, images, or sources — sources on their own, since some providers
  /// take them in no other company.
  final List<ChatPart> content;
  final bool isError;

  @override
  Map<String, Object?> toJson() => <String, Object?>{
    'type': 'tool_result',
    'callId': callId,
    'content': <Object?>[for (final c in content) c.toJson()],
    if (isError) 'isError': true,
  };
}

/// Something only one provider understands — its reasoning, its own web
/// searches — kept as it came, to be handed back to that provider as it
/// was, and ignored by any other.
final class NativePart extends ChatPart {
  const NativePart(this.provider, this.block);

  final String provider;
  final Map<String, Object?> block;

  @override
  Map<String, Object?> toJson() => <String, Object?>{
    'type': 'native',
    'provider': provider,
    'block': block,
  };
}

class ChatMessage {
  const ChatMessage(this.role, this.parts);

  ChatMessage.user(List<ChatPart> parts) : this(ChatRole.user, parts);

  ChatMessage.assistant(List<ChatPart> parts) : this(ChatRole.assistant, parts);

  final ChatRole role;
  final List<ChatPart> parts;

  /// All the text in it.
  String get text => parts.whereType<TextPart>().map((p) => p.text).join();

  List<ToolCallPart> get toolCalls => parts.whereType<ToolCallPart>().toList();

  Map<String, Object?> toJson() => <String, Object?>{
    'role': role.name,
    'parts': <Object?>[for (final p in parts) p.toJson()],
  };

  static ChatMessage fromJson(Map<String, Object?> json) =>
      ChatMessage(ChatRole.values.byName(json['role']! as String), <ChatPart>[
        for (final p in json['parts']! as List<Object?>)
          ChatPart.fromJson((p! as Map).cast<String, Object?>()),
      ]);
}
