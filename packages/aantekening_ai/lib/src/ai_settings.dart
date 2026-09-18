/// User-configurable settings for the local AI features.
library;

/// Which runtime to talk to and which models to use.
///
/// Defaults point at Ollama on the loopback interface, the most common way to
/// run open-weight models locally on all three target platforms.
class AiSettings {
  const AiSettings({
    this.enabled = false,
    this.baseUrl = defaultBaseUrl,
    this.chatModel = '',
    this.embeddingModel = '',
    this.requestTimeout = const Duration(seconds: 120),
  });

  static const String defaultBaseUrl = 'http://127.0.0.1:11434';

  /// Whether the AI features are switched on at all.
  ///
  /// Off by default: the app must be fully usable, and must not reach for a
  /// network socket, before anyone opts in.
  final bool enabled;

  final String baseUrl;

  /// Model used for summarising and answering questions.
  final String chatModel;

  /// Model used for embeddings that back semantic search.
  ///
  /// Kept separate from [chatModel] because embedding models are far smaller
  /// and a workspace's stored vectors are only comparable within one model.
  final String embeddingModel;

  final Duration requestTimeout;

  /// Whether enough is configured to run a chat request.
  bool get canChat => enabled && chatModel.isNotEmpty;

  /// Whether enough is configured to build the semantic index.
  bool get canEmbed => enabled && embeddingModel.isNotEmpty;

  AiSettings copyWith({
    bool? enabled,
    String? baseUrl,
    String? chatModel,
    String? embeddingModel,
    Duration? requestTimeout,
  }) => AiSettings(
    enabled: enabled ?? this.enabled,
    baseUrl: baseUrl ?? this.baseUrl,
    chatModel: chatModel ?? this.chatModel,
    embeddingModel: embeddingModel ?? this.embeddingModel,
    requestTimeout: requestTimeout ?? this.requestTimeout,
  );

  Map<String, Object?> toJson() => <String, Object?>{
    'enabled': enabled,
    'baseUrl': baseUrl,
    'chatModel': chatModel,
    'embeddingModel': embeddingModel,
    'requestTimeoutMs': requestTimeout.inMilliseconds,
  };

  static AiSettings fromJson(Map<String, Object?> json) => AiSettings(
    enabled: json['enabled'] is bool ? json['enabled']! as bool : false,
    baseUrl: json['baseUrl'] is String
        ? json['baseUrl']! as String
        : defaultBaseUrl,
    chatModel: json['chatModel'] is String ? json['chatModel']! as String : '',
    embeddingModel: json['embeddingModel'] is String
        ? json['embeddingModel']! as String
        : '',
    requestTimeout: Duration(
      milliseconds: json['requestTimeoutMs'] is num
          ? (json['requestTimeoutMs']! as num).toInt()
          : 120000,
    ),
  );
}
