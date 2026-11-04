/// The AI's settings, its keys, and the provider questions go to.
library;

import 'dart:io';

import 'package:aantekening_ai/aantekening_ai.dart';
import 'package:aantekening_core/aantekening_core.dart';
import 'package:flutter/services.dart';
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

/// What to say where the keychain would not read or keep a key, as
/// [error] says why.
String keychainTrouble(Object error) =>
    'This computer’s keychain could not be reached, so no key is kept'
    '${Platform.isLinux ? ' — it needs a Secret Service, such as GNOME '
              'Keyring or KWallet' : ''}: '
    '${error is PlatformException ? error.message ?? error.code : error}';

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

/// Makes what asks the provider [config] describes, with [apiKey].
typedef ChatMaker = ChatProvider Function(
  ProviderConfig config,
  String? apiKey,
);

/// What asks a model: a provider as the settings have it.
final chatMakerProvider = Provider<ChatMaker>(
  (ref) =>
      (config, apiKey) => config.create(apiKey: apiKey),
);

final aiModelProvider = FutureProvider<AiModel?>((ref) async {
  final config = ref.watch(aiSettingsProvider.select((s) => s.active));
  if (config == null || config.model.isEmpty) return null;
  final String? key;
  try {
    key = await ref.watch(aiSecretsProvider).read(providerKeyName(config.id));
  } on Object catch (error) {
    throw AiException(keychainTrouble(error));
  }
  final provider = ref.read(chatMakerProvider)(config, key);
  // Made again whenever the settings or a key change, under an answer
  // still coming through this one, which is closed once it is done.
  ref.onDispose(() => closeProviderWhenDone(provider));
  return (provider: provider, config: config);
});

/// How many answers, sets and podcasts are still asked through each
/// provider; and those let go of meanwhile, to close once none is.
final Map<ChatProvider, int> _held = Map<ChatProvider, int>.identity();
final Set<ChatProvider> _letGo = Set<ChatProvider>.identity();

/// Keeps [provider] open, though let go of, until [releaseProvider] as often.
void holdProvider(ChatProvider provider) =>
    _held[provider] = (_held[provider] ?? 0) + 1;

/// Lets go of a [holdProvider] on [provider]: closed with the last, if it was let
/// go of meanwhile.
void releaseProvider(ChatProvider provider) {
  final left = (_held[provider] ?? 1) - 1;
  if (left > 0) {
    _held[provider] = left;
    return;
  }
  _held.remove(provider);
  if (_letGo.remove(provider)) provider.close();
}

/// Closes [provider] now, or once nothing asked through it is still
/// coming.
void closeProviderWhenDone(ChatProvider provider) {
  if (_held.containsKey(provider)) {
    _letGo.add(provider);
  } else {
    provider.close();
  }
}

/// [stream], asked through [provider], which is held open until it ends
/// or is stopped.
Stream<T> holdingProvider<T>(ChatProvider provider, Stream<T> stream) async* {
  holdProvider(provider);
  try {
    yield* stream;
  } finally {
    releaseProvider(provider);
  }
}

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
