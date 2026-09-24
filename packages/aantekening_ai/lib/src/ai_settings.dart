/// Which models the person has chosen to ask, and how the web is searched.
library;

import 'package:http/http.dart' as http;

import 'anthropic_provider.dart';
import 'ollama_provider.dart';
import 'openai_compatible_provider.dart';
import 'provider.dart';
import 'web_search.dart';

/// The kinds of API a provider speaks.
enum ProviderKind { anthropic, ollama, openAiCompatible }

/// A provider the settings know how to set up: where it is, whether it
/// wants a key, and whether it runs on this machine.
enum ProviderPreset {
  ollama('Ollama', ProviderKind.ollama, 'http://127.0.0.1:11434', local: true),
  lmStudio(
    'LM Studio',
    ProviderKind.openAiCompatible,
    'http://127.0.0.1:1234/v1',
    local: true,
  ),
  anthropic(
    'Anthropic',
    ProviderKind.anthropic,
    AnthropicProvider.defaultBaseUrl,
    needsKey: true,
    model: AnthropicProvider.defaultModel,
  ),
  openAi(
    'OpenAI',
    ProviderKind.openAiCompatible,
    'https://api.openai.com/v1',
    needsKey: true,
  ),
  gemini(
    'Google Gemini',
    ProviderKind.openAiCompatible,
    'https://generativelanguage.googleapis.com/v1beta/openai',
    needsKey: true,
  ),
  openRouter(
    'OpenRouter',
    ProviderKind.openAiCompatible,
    'https://openrouter.ai/api/v1',
    needsKey: true,
  ),
  mistral(
    'Mistral',
    ProviderKind.openAiCompatible,
    'https://api.mistral.ai/v1',
    needsKey: true,
  ),
  groq(
    'Groq',
    ProviderKind.openAiCompatible,
    'https://api.groq.com/openai/v1',
    needsKey: true,
  ),
  deepSeek(
    'DeepSeek',
    ProviderKind.openAiCompatible,
    'https://api.deepseek.com/v1',
    needsKey: true,
  ),
  custom(
    'Another OpenAI-compatible server',
    ProviderKind.openAiCompatible,
    'http://127.0.0.1:8080/v1',
  );

  const ProviderPreset(
    this.label,
    this.kind,
    this.baseUrl, {
    this.needsKey = false,
    this.local = false,
    this.model = '',
  });

  final String label;
  final ProviderKind kind;
  final String baseUrl;
  final bool needsKey;

  /// Whether it runs on this machine, so the notes stay on it.
  final bool local;

  /// The model to start with, where there is an obvious one.
  final String model;
}

/// A provider the person has set up, and the model of it they use.
class ProviderConfig {
  const ProviderConfig({
    required this.id,
    required this.preset,
    required this.name,
    required this.baseUrl,
    this.model = '',
    this.contextTokens,
    this.think = true,
    this.thinkingTime = OllamaProvider.defaultThinkingTime,
  });

  /// A new configuration of [preset], identified by [id].
  factory ProviderConfig.of(ProviderPreset preset, {required String id}) =>
      ProviderConfig(
        id: id,
        preset: preset,
        name: preset.label,
        baseUrl: preset.baseUrl,
        model: preset.model,
      );

  final String id;
  final ProviderPreset preset;
  final String name;
  final String baseUrl;
  final String model;

  /// For a runtime that is told it, how many tokens a model runs with; null
  /// for its own choice.
  final int? contextTokens;

  /// For a runtime that is told it, whether a model that can think before
  /// it answers does.
  final bool think;

  /// For a runtime whose thinking can be stopped, how long a model thinks
  /// before it is made to answer; null for as long as its room lasts.
  final Duration? thinkingTime;

  ProviderKind get kind => preset.kind;

  /// Whether the notes stay on this machine: a runtime on it, or on the
  /// loopback address whatever it is.
  bool get local {
    final host = Uri.tryParse(baseUrl)?.host ?? '';
    return preset.local ||
        host == 'localhost' ||
        host == '127.0.0.1' ||
        host == '::1';
  }

  /// A provider that talks to it, with [apiKey].
  ChatProvider create({String? apiKey, http.Client? client}) => switch (kind) {
    ProviderKind.anthropic => AnthropicProvider(
      apiKey: apiKey ?? '',
      baseUrl: baseUrl,
      client: client,
    ),
    ProviderKind.ollama => OllamaProvider(
      name: name,
      baseUrl: baseUrl,
      contextTokens: contextTokens ?? OllamaProvider.defaultContextTokens,
      think: think,
      thinkingTime: thinkingTime,
      client: client,
    ),
    ProviderKind.openAiCompatible => OpenAiCompatibleProvider(
      name: name,
      baseUrl: baseUrl,
      apiKey: apiKey,
      defaults: ModelCapabilities(
        vision: true,
        tools: true,
        // Runtimes on this machine often run with a short context.
        contextTokens: local ? 8192 : 128000,
      ),
      client: client,
    ),
  };

  ProviderConfig copyWith({
    String? name,
    String? baseUrl,
    String? model,
    int? contextTokens,
    bool? think,
    Duration? Function()? thinkingTime,
  }) => ProviderConfig(
    id: id,
    preset: preset,
    name: name ?? this.name,
    baseUrl: baseUrl ?? this.baseUrl,
    model: model ?? this.model,
    contextTokens: contextTokens ?? this.contextTokens,
    think: think ?? this.think,
    thinkingTime: thinkingTime == null ? this.thinkingTime : thinkingTime(),
  );

  Map<String, Object?> toJson() => <String, Object?>{
    'id': id,
    'preset': preset.name,
    'name': name,
    'baseUrl': baseUrl,
    'model': model,
    if (contextTokens != null) 'contextTokens': contextTokens,
    if (!think) 'think': false,
    'thinkingSeconds': thinkingTime?.inSeconds ?? 0,
  };

  static ProviderConfig? fromJson(Map<String, Object?> json) {
    final preset = ProviderPreset.values.asNameMap()[json['preset']];
    final id = json['id'];
    if (preset == null || id is! String) return null;
    return ProviderConfig(
      id: id,
      preset: preset,
      name: json['name'] as String? ?? preset.label,
      baseUrl: json['baseUrl'] as String? ?? preset.baseUrl,
      model: json['model'] as String? ?? '',
      contextTokens: json['contextTokens'] as int?,
      think: json['think'] as bool? ?? true,
      thinkingTime: switch (json['thinkingSeconds']) {
        0 => null,
        final int seconds => Duration(seconds: seconds),
        _ => OllamaProvider.defaultThinkingTime,
      },
    );
  }
}

/// The AI's settings. Nothing is set up at first: the app talks to no
/// model until the person chooses one.
class AiSettings {
  const AiSettings({
    this.providers = const <ProviderConfig>[],
    this.activeId,
    this.webBackend = WebSearchBackend.none,
    this.searxngUrl = 'http://127.0.0.1:8888',
    this.searchWeb = true,
  });

  final List<ProviderConfig> providers;

  /// The provider questions go to.
  final String? activeId;

  /// Where the web is searched from for a provider that cannot search it.
  final WebSearchBackend webBackend;
  final String searxngUrl;

  /// Whether questions may search the web, where it can be.
  final bool searchWeb;

  ProviderConfig? get active =>
      providers.where((provider) => provider.id == activeId).firstOrNull ??
      providers.firstOrNull;

  /// Whether a question can be asked at all.
  bool get ready => (active?.model ?? '').isNotEmpty;

  AiSettings copyWith({
    List<ProviderConfig>? providers,
    String? activeId,
    WebSearchBackend? webBackend,
    String? searxngUrl,
    bool? searchWeb,
  }) => AiSettings(
    providers: providers ?? this.providers,
    activeId: activeId ?? this.activeId,
    webBackend: webBackend ?? this.webBackend,
    searxngUrl: searxngUrl ?? this.searxngUrl,
    searchWeb: searchWeb ?? this.searchWeb,
  );

  /// With [config] in place of the provider of its id, or added.
  AiSettings withProvider(ProviderConfig config) => copyWith(
    providers: <ProviderConfig>[
      for (final provider in providers)
        if (provider.id == config.id) config else provider,
      if (!providers.any((provider) => provider.id == config.id)) config,
    ],
  );

  AiSettings withoutProvider(String id) => AiSettings(
    providers: <ProviderConfig>[
      for (final provider in providers)
        if (provider.id != id) provider,
    ],
    activeId: activeId == id ? null : activeId,
    webBackend: webBackend,
    searxngUrl: searxngUrl,
    searchWeb: searchWeb,
  );

  Map<String, Object?> toJson() => <String, Object?>{
    'providers': <Object?>[for (final p in providers) p.toJson()],
    if (activeId != null) 'active': activeId,
    'web': webBackend.name,
    'searxng': searxngUrl,
    'searchWeb': searchWeb,
  };

  static AiSettings fromJson(Object? json) {
    if (json is! Map) return const AiSettings();
    return AiSettings(
      providers: <ProviderConfig>[
        for (final entry in (json['providers'] as List<Object?>?) ?? const [])
          if (entry is Map) ?ProviderConfig.fromJson(entry.cast()),
      ],
      activeId: json['active'] as String?,
      webBackend:
          WebSearchBackend.values.asNameMap()[json['web']] ??
          WebSearchBackend.none,
      searxngUrl: json['searxng'] as String? ?? 'http://127.0.0.1:8888',
      searchWeb: json['searchWeb'] as bool? ?? true,
    );
  }
}
