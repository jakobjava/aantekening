/// Podcasts of the notes: the voices that speak them, the kinds of podcast
/// to make and the models that write them, and who speaks.
///
/// The page and its voices here; editing a kind of podcast, and who
/// speaks, each a part of its own.
library;

import 'dart:async';
import 'dart:io';

import 'package:aantekening_ai/aantekening_ai.dart';
import 'package:aantekening_core/aantekening_core.dart';
import 'package:audioplayers/audioplayers.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:path/path.dart' as p;

import '../ai/ai_state.dart';
import '../ai/podcast_view.dart' show playbackTrouble;
import '../ai/study_profile_editor.dart' show settleAiSettings;
import '../look/controls.dart';
import '../look/glass.dart';
import '../look/marks.dart';
import '../look/motion.dart';
import '../look/tones.dart';
import 'provider_block.dart';
import 'settings_view.dart';

part 'podcast_cast_editor.dart';
part 'podcast_episode_editor.dart';

/// Opens the settings at the podcasts' page.
Future<void> openPodcastSettings(BuildContext context) =>
    showSettings(context, page: SettingsPage.podcasts);

/// The podcasts' page of the settings.
class PodcastSettingsPage extends ConsumerWidget {
  const PodcastSettingsPage({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final settings = ref.watch(aiSettingsProvider);
    final controller = ref.read(aiSettingsProvider.notifier);

    void add(SpeechPreset preset) => controller.update(
      settings.withVoice(VoiceConfig.of(preset, id: Ulid.generate())),
    );

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: <Widget>[
        SettingsSection(
          title: 'Voices',
          description:
              'What speaks a podcast once a model has written it. A speech '
              'server on this computer, such as Kokoro, keeps what is said '
              'here; a service is sent the words to speak, never your notes.',
          children: <Widget>[
            for (final voice in settings.voices)
              _VoiceBlock(key: ValueKey<String>(voice.id), config: voice),
            const SizedBox(height: 6),
            AddProviderMenu<SpeechPreset>(
              label: 'Add a voice provider…',
              presets: SpeechPreset.values,
              ownServer: (preset) => preset.ownServer,
              labelOf: (preset) => preset.label,
              onAdd: add,
            ),
          ],
        ),
        SettingsSection(
          title: 'Kinds of podcast',
          description:
              'Offered in the AI of every notebook, section and page. Each '
              'says what the episode is to be, how many parts it has, who '
              'speaks, and which model plans it and which writes what is '
              'said — a strong model to plan, a quick one to write, say.',
          children: <Widget>[
            for (final episode in settings.episodes)
              RowTile(
                padding: const EdgeInsets.fromLTRB(0, 6, 0, 6),
                title: Text(episode.name),
                subtitle: Text(
                  <String>[
                    '${episode.segments} parts',
                    ?settings.castOf(episode.speakersId)?.name,
                    if (episode.language.isNotEmpty) episode.language,
                    _modelsOf(settings, episode),
                  ].join('  ·  '),
                ),
                trailing: SmallButton(
                  'Edit',
                  onPressed: () => _editEpisode(context, episode),
                ),
                onTap: () => _editEpisode(context, episode),
              ),
            const SizedBox(height: 8),
            Align(
              alignment: Alignment.centerLeft,
              child: OutlinedButton(
                onPressed: () => _editEpisode(context, null),
                child: const Text('New kind of podcast…'),
              ),
            ),
          ],
        ),
        SettingsSection(
          title: 'Who speaks',
          description:
              'One to four speakers: their names, voices, and who they are — '
              'which the model writes them as.',
          children: <Widget>[
            for (final cast in settings.casts)
              RowTile(
                padding: const EdgeInsets.fromLTRB(0, 6, 0, 6),
                title: Text(cast.name),
                subtitle: Text(
                  <String>[
                    cast.speakers.map((s) => s.name).join(', '),
                    ?settings.voiceOf(cast.voiceId)?.name,
                  ].join('  ·  '),
                ),
                trailing: SmallButton(
                  'Edit',
                  onPressed: () => _editCast(context, cast),
                ),
                onTap: () => _editCast(context, cast),
              ),
            const SizedBox(height: 8),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: <Widget>[
                OutlinedButton(
                  onPressed: () => _editCast(context, null),
                  child: const Text('New speakers…'),
                ),
                if (settings.podcastsChanged)
                  TextButton(
                    onPressed: () =>
                        controller.update(settings.withPodcastsAsMade()),
                    child: const Text('Bring back the app’s own'),
                  ),
              ],
            ),
          ],
        ),
      ],
    );
  }

  static String _modelsOf(AiSettings settings, EpisodeProfile episode) {
    String name(ModelChoice choice) {
      if (choice.isInUse) return 'the model in use';
      final config = settings.providerOf(choice);
      if (config == null) return 'a provider no longer set up';
      return choice.model.isEmpty ? config.model : choice.model;
    }

    final outline = name(episode.outline);
    final transcript = name(episode.transcript);
    return outline == transcript
        ? 'written by $outline'
        : 'planned by $outline, written by $transcript';
  }
}

void _editEpisode(BuildContext context, EpisodeProfile? episode) => unawaited(
  showAppDialog<void>(
    context: context,
    builder: (context) => _EpisodeEditor(episode: episode),
  ),
);

void _editCast(BuildContext context, SpeakerProfile? cast) => unawaited(
  showAppDialog<void>(
    context: context,
    builder: (context) => _CastEditor(cast: cast),
  ),
);

/// One voice provider: where it is, its model and key — and a way to hear
/// it.
class _VoiceBlock extends ConsumerStatefulWidget {
  const _VoiceBlock({required this.config, super.key});

  final VoiceConfig config;

  @override
  ConsumerState<_VoiceBlock> createState() => _VoiceBlockState();
}

class _VoiceBlockState extends ConsumerState<_VoiceBlock> {
  late final TextEditingController _url = TextEditingController(
    text: widget.config.baseUrl,
  );
  late final TextEditingController _model = TextEditingController(
    text: widget.config.model,
  );
  bool _trying = false;
  String? _said;
  AudioPlayer? _player;

  @override
  void dispose() {
    _url.dispose();
    _model.dispose();
    unawaited(_player?.dispose());
    super.dispose();
  }

  void _save(VoiceConfig config) =>
      ref.read(aiSettingsProvider.notifier).change((s) => s.withVoice(config));

  /// Speaks a sentence with the first voice, and plays it.
  Future<void> _try() async {
    setState(() {
      _trying = true;
      _said = null;
    });
    final config = widget.config;
    SpeechProvider? speech;
    try {
      speech = config.create(
        apiKey: await ref.read(aiSecretsProvider).read(voiceKeyName(config.id)),
      );
      final sound = await speech.speak(
        'Hello! This is how I sound reading your notes.',
        voice: config.voiceFor(0),
      );
      final file = File(
        p.join(Directory.systemTemp.path, 'aantekening-voice-${config.id}.wav'),
      );
      await file.writeAsBytes(sound.toWav(), flush: true);
      try {
        final player = _player ??= AudioPlayer();
        await player.play(DeviceFileSource(file.path));
      } on Object catch (error) {
        // The voice spoke; this computer could not play it.
        _said = playbackTrouble(error);
      }
    } on Object catch (error) {
      _said = error is AiException ? error.message : '$error';
    } finally {
      speech?.close();
      if (mounted) setState(() => _trying = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final tones = context.tones;
    final config = widget.config;
    return Container(
      margin: const EdgeInsets.only(bottom: 10),
      decoration: BoxDecoration(
        border: Border.all(color: tones.line),
        borderRadius: Corners.controlRadius,
      ),
      padding: const EdgeInsets.fromLTRB(14, 10, 10, 12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: <Widget>[
          ProviderHeading(
            name: config.name,
            where: config.local
                ? 'On this computer — what is said stays here'
                : 'Sends the words to speak to ${hostOf(config.baseUrl)}',
            actions: <Widget>[
              if (_trying)
                const Busy(width: 32)
              else
                SmallButton(
                  'Try it',
                  tooltip: 'Hear the first voice say a sentence',
                  onPressed: () => unawaited(_try()),
                ),
            ],
          ),
          if (_said case final said?)
            Padding(
              padding: const EdgeInsets.only(top: 6),
              child: Text(
                said,
                style: TextStyle(fontSize: 12, color: tones.text),
              ),
            ),
          const SizedBox(height: 10),
          TextField(
            controller: _model,
            decoration: InputDecoration(
              labelText: 'Model',
              helperText: switch (config.preset) {
                SpeechPreset.openAi =>
                  'gpt-4o-mini-tts speaks each speaker in their manner; '
                      'tts-1 is quicker and cheaper.',
                SpeechPreset.requesty =>
                  'openai/gpt-4o-mini-tts speaks each speaker in their '
                      'manner; openai/tts-1 is a little cheaper.',
                SpeechPreset.gemini =>
                  'A Gemini model that speaks, such as '
                      'gemini-2.5-flash-preview-tts.',
                SpeechPreset.elevenLabs =>
                  'eleven_multilingual_v2 speaks many languages; '
                      'eleven_flash_v2_5 is quicker.',
                SpeechPreset.kokoro =>
                  'Kokoro-FastAPI, run with Docker, answers on port 8880.',
                SpeechPreset.custom =>
                  'Any server with OpenAI’s /audio/speech: Speaches, '
                      'openedai-speech, LocalAI.',
              },
              helperMaxLines: 2,
            ),
            onSubmitted: (model) => _save(config.copyWith(model: model.trim())),
            onTapOutside: (_) {
              if (_model.text.trim() != config.model) {
                _save(config.copyWith(model: _model.text.trim()));
              }
            },
          ),
          const SizedBox(height: 10),
          TextField(
            controller: _url,
            decoration: const InputDecoration(labelText: 'Address'),
            onSubmitted: (url) => _save(config.copyWith(baseUrl: url.trim())),
          ),
          const SizedBox(height: 10),
          ProviderKeyField(
            name: voiceKeyName(config.id),
            needsKey: config.preset.needsKey,
          ),
          const SizedBox(height: 6),
          RemoveProviderButton(
            label: 'Remove this voice provider',
            keyName: voiceKeyName(config.id),
            onRemoved: () => ref
                .read(aiSettingsProvider.notifier)
                .change((s) => s.withoutVoice(config.id)),
          ),
        ],
      ),
    );
  }
}
