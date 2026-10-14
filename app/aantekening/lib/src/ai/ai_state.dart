/// The AI's settings, its keys, and the provider questions go to.
library;

import 'dart:io';

import 'package:aantekening_ai/aantekening_ai.dart';
import 'package:aantekening_core/aantekening_core.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:path/path.dart' as p;

import '../files/notes_location.dart';
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

/// The name a voice provider's API key is kept under.
String voiceKeyName(String voiceId) => 'voice.$voiceId';

/// Makes what speaks through voice provider [voice], with [apiKey], in
/// [model] or its own.
typedef SpeechMaker = SpeechProvider Function(
  VoiceConfig voice,
  String? apiKey,
  String model,
);

/// What speaks podcasts: a voice provider as the settings have it.
final speechMakerProvider = Provider<SpeechMaker>(
  (ref) =>
      (voice, apiKey, model) => voice.create(apiKey: apiKey, model: model),
);

/// Where podcasts' sound is kept: in this computer's own folder for the
/// app, as the index is, never in the notes folder — a sound file is large,
/// and can be spoken again from its transcript wherever it is missing.
final podcastFolderProvider = FutureProvider<String>(
  (ref) async =>
      p.join(await ref.watch(supportFolderProvider.future), 'podcasts'),
);

/// The file podcast sound [audio] is kept in.
Future<File> podcastFile(Ref ref, String audio) async =>
    File(p.join(await ref.read(podcastFolderProvider.future), audio));

/// Keeps [sound] as a podcast's, returning the name it is kept by.
///
/// Written at once rather than in the background: it is written once, at
/// the end of making a podcast, and is a few megabytes.
Future<String> savePodcastAudio(Ref ref, Sound sound) async {
  final name = '${Ulid.generate()}.wav';
  final file = await podcastFile(ref, name);
  file.parent.createSync(recursive: true);
  file.writeAsBytesSync(sound.toWav(), flush: true);
  return name;
}

/// Forgets podcast sound [audio], if it is there.
Future<void> deletePodcastAudio(Ref ref, String audio) async {
  final file = await podcastFile(ref, audio);
  if (file.existsSync()) file.deleteSync();
}

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
  final (backend, searxngUrl) = ref.watch(
    aiSettingsProvider.select((s) => (s.webBackend, s.searxngUrl)),
  );
  final WebSearch? search;
  switch (backend) {
    case WebSearchBackend.none:
      return null;
    case WebSearchBackend.searxng:
      search = SearxngSearch(searxngUrl);
    case WebSearchBackend.brave:
      final key = await ref.watch(aiSecretsProvider).read(braveKeyName);
      search = key == null || key.isEmpty ? null : BraveSearch(key);
  }
  if (search != null) ref.onDispose(search.close);
  return search;
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
