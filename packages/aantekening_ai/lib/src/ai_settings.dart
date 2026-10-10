/// Which models the person has chosen to ask, and how the web is searched.
library;

import 'package:http/http.dart' as http;

import 'anthropic_provider.dart';
import 'note_context.dart';
import 'ollama_provider.dart';
import 'openai_compatible_provider.dart';
import 'provider.dart';
import 'study_profile.dart';
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
  requesty(
    'Requesty',
    ProviderKind.openAiCompatible,
    'https://router.requesty.ai/v1',
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

  /// Whether it is a server of one's own: a runtime on this machine, or
  /// one set up anywhere.
  bool get ownServer => local || this == custom;
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
    this.notesTokens = ContextBudget.defaultNotesTokens,
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

  /// How many tokens a model has: for a runtime that is told it, what it
  /// runs with; for another server of one's own, what it takes, over what
  /// the server says. Null for the runtime's choice, or what the server
  /// says.
  final int? contextTokens;

  /// How many tokens of the notes go with a question, at most.
  final int notesTokens;

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

  /// How many tokens a model on an OpenAI-compatible server is taken to
  /// have where neither the person nor the server says: runtimes on this
  /// machine often run with a short context.
  int get presumedContextTokens => local ? 8192 : 128000;

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
        contextTokens: presumedContextTokens,
        price: local ? ModelPrice.free : null,
      ),
      room: contextTokens,
      promptCache: switch (preset) {
        ProviderPreset.requesty => PromptCache.requesty,
        ProviderPreset.openRouter => PromptCache.openRouter,
        ProviderPreset.openAi => PromptCache.openAi,
        _ => PromptCache.implicit,
      },
      client: client,
    ),
  };

  ProviderConfig copyWith({
    String? name,
    String? baseUrl,
    String? model,
    int? Function()? contextTokens,
    int? notesTokens,
    bool? think,
    Duration? Function()? thinkingTime,
  }) => ProviderConfig(
    id: id,
    preset: preset,
    name: name ?? this.name,
    baseUrl: baseUrl ?? this.baseUrl,
    model: model ?? this.model,
    contextTokens: contextTokens == null ? this.contextTokens : contextTokens(),
    notesTokens: notesTokens ?? this.notesTokens,
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
    if (notesTokens != ContextBudget.defaultNotesTokens)
      'notesTokens': notesTokens,
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
      notesTokens:
          json['notesTokens'] as int? ?? ContextBudget.defaultNotesTokens,
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
    this.about = '',
    this.profiles = const <StudyProfile>[],
  });

  final List<ProviderConfig> providers;

  /// The provider questions go to.
  final String? activeId;

  /// Where the web is searched from for a provider that cannot search it.
  final WebSearchBackend webBackend;
  final String searxngUrl;

  /// Whether questions may search the web, where it can be.
  final bool searchWeb;

  /// What the person says of themselves, told to the model with every
  /// question and study set: their school year, their course, their exams.
  final String about;

  /// The app's own study profiles the person changed, and those they made,
  /// in the order made; see [studyProfiles].
  final List<StudyProfile> profiles;

  /// The study profiles to make sets with: the app's own, as the person
  /// has them, then their own.
  List<StudyProfile> get studyProfiles {
    final changed = <String, StudyProfile>{
      for (final profile in profiles) profile.id: profile,
    };
    return <StudyProfile>[
      for (final original in StudyProfile.originals)
        changed[original.id] ?? original,
      for (final profile in profiles)
        if (!profile.isOriginal) profile,
    ];
  }

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
    String? about,
    List<StudyProfile>? profiles,
  }) => AiSettings(
    providers: providers ?? this.providers,
    activeId: activeId ?? this.activeId,
    webBackend: webBackend ?? this.webBackend,
    searxngUrl: searxngUrl ?? this.searxngUrl,
    searchWeb: searchWeb ?? this.searchWeb,
    about: about ?? this.about,
    profiles: profiles ?? this.profiles,
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
    about: about,
    profiles: profiles,
  );

  /// With [profile] in place of the profile of its id, or added — and one
  /// of the app's own, changed back to as it came, no longer kept.
  AiSettings withProfile(StudyProfile profile) {
    final keep = !profile.isAsMade;
    return copyWith(
      profiles: <StudyProfile>[
        for (final kept in profiles)
          if (kept.id != profile.id) kept else if (keep) profile,
        if (keep && !profiles.any((kept) => kept.id == profile.id)) profile,
      ],
    );
  }

  /// Without profile [id]: one the person made is gone, one of the app's
  /// own is as it came.
  AiSettings withoutProfile(String id) => copyWith(
    profiles: <StudyProfile>[
      for (final profile in profiles)
        if (profile.id != id) profile,
    ],
  );

  Map<String, Object?> toJson() => <String, Object?>{
    'providers': <Object?>[for (final p in providers) p.toJson()],
    if (activeId != null) 'active': activeId,
    'web': webBackend.name,
    'searxng': searxngUrl,
    'searchWeb': searchWeb,
    if (about.isNotEmpty) 'about': about,
    if (profiles.isNotEmpty)
      'profiles': <Object?>[for (final p in profiles) p.toJson()],
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
      about: json['about'] as String? ?? '',
      profiles: <StudyProfile>[
        for (final entry in (json['profiles'] as List<Object?>?) ?? const [])
          if (entry is Map) ?StudyProfile.fromJson(entry.cast()),
      ],
    );
  }
}
