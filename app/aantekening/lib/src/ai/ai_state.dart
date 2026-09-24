/// The AI's settings, its keys, and the provider questions go to.
library;

import 'package:aantekening_ai/aantekening_ai.dart';
import 'package:aantekening_core/aantekening_core.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';

import '../preferences.dart';

/// Where the API keys for providers and web search are kept: the system's
/// keychain — the Secret Service on Linux, the Credential Manager on
/// Windows, the Keystore on Android — never the preferences file.
abstract interface class AiSecrets {
  Future<String?> read(String name);

  /// Keeps [value] as [name], or forgets it for null.
  Future<void> write(String name, String? value);
}

/// Secrets in the system's keychain.
class KeychainSecrets implements AiSecrets {
  const KeychainSecrets();

  static const FlutterSecureStorage _storage = FlutterSecureStorage();
  static const String _prefix = 'aantekening.ai.';

  @override
  Future<String?> read(String name) => _storage.read(key: '$_prefix$name');

  @override
  Future<void> write(String name, String? value) => value == null
      ? _storage.delete(key: '$_prefix$name')
      : _storage.write(key: '$_prefix$name', value: value);
}

/// Secrets kept only while the app runs: for tests, and where the system
/// keeps none.
class MemorySecrets implements AiSecrets {
  final Map<String, String> _values = <String, String>{};

  @override
  Future<String?> read(String name) async => _values[name];

  @override
  Future<void> write(String name, String? value) async {
    if (value == null) {
      _values.remove(name);
    } else {
      _values[name] = value;
    }
  }
}

final aiSecretsProvider = Provider<AiSecrets>((ref) => const KeychainSecrets());

/// The name a provider's API key is kept under.
String providerKeyName(String providerId) => 'provider.$providerId';

/// The name Brave Search's key is kept under.
const String braveKeyName = 'web.brave';

/// The AI's settings, remembered between sessions.
class AiSettingsController extends Notifier<AiSettings> {
  static const String _key = 'ai';

  @override
  AiSettings build() => AiSettings.fromJson(ref.preference(_key));

  void update(AiSettings settings) {
    state = settings;
    ref.savePreference(_key, settings.toJson());
  }
}

final aiSettingsProvider = NotifierProvider<AiSettingsController, AiSettings>(
  AiSettingsController.new,
);

/// Who answers questions: the provider chosen, with its key, and its
/// model — or null until one is chosen.
typedef AiModel = ({ChatProvider provider, ProviderConfig config});

final aiModelProvider = FutureProvider<AiModel?>((ref) async {
  final config = ref.watch(aiSettingsProvider.select((s) => s.active));
  if (config == null || config.model.isEmpty) return null;
  final key = await ref
      .watch(aiSecretsProvider)
      .read(providerKeyName(config.id));
  final provider = config.create(apiKey: key);
  ref.onDispose(provider.close);
  return (provider: provider, config: config);
});

/// Where the web is searched from for a provider that cannot, or null.
final webSearchProvider = FutureProvider<WebSearch?>((ref) async {
  final settings = ref.watch(aiSettingsProvider);
  switch (settings.webBackend) {
    case WebSearchBackend.none:
      return null;
    case WebSearchBackend.searxng:
      return SearxngSearch(settings.searxngUrl);
    case WebSearchBackend.brave:
      final key = await ref.watch(aiSecretsProvider).read(braveKeyName);
      return key == null || key.isEmpty ? null : BraveSearch(key);
  }
});

/// What the AI is being asked about in a tab: the page it has open, or else
/// its section, or else its notebook.
NoteLink? aiScopeOf({String? notebookId, String? sectionId, String? pageId}) =>
    pageId != null
    ? NoteLink.page(pageId)
    : sectionId != null
    ? NoteLink.section(sectionId)
    : notebookId != null
    ? NoteLink.notebook(notebookId)
    : null;
