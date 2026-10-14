/// Podcasts of the notes: the voices that speak them, the kinds of podcast
/// to make and the models that write them, and who speaks.
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
import '../look/controls.dart';
import '../look/glass.dart';
import '../look/marks.dart';
import '../look/motion.dart';
import '../look/tones.dart';
import 'settings_view.dart';

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
            Align(
              alignment: Alignment.centerLeft,
              child: MenuAnchor(
                menuChildren: <Widget>[
                  const _MenuHeading('On this computer'),
                  for (final preset in SpeechPreset.values)
                    if (preset.ownServer)
                      MenuItemButton(
                        onPressed: () => add(preset),
                        child: Text(preset.label),
                      ),
                  const _MenuHeading('Online'),
                  for (final preset in SpeechPreset.values)
                    if (!preset.ownServer)
                      MenuItemButton(
                        onPressed: () => add(preset),
                        child: Text(preset.label),
                      ),
                ],
                builder: (context, menu, _) => OutlinedButton(
                  onPressed: () => menu.isOpen ? menu.close() : menu.open(),
                  child: const Text('Add a voice provider…'),
                ),
              ),
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

class _MenuHeading extends StatelessWidget {
  const _MenuHeading(this.label);

  final String label;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.fromLTRB(12, 8, 12, 4),
    child: SmallCaps(label),
  );
}

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
  final TextEditingController _key = TextEditingController();
  bool _hasKey = false;
  bool _trying = false;
  String? _said;
  AudioPlayer? _player;

  @override
  void initState() {
    super.initState();
    unawaited(_readKey());
  }

  @override
  void dispose() {
    _url.dispose();
    _model.dispose();
    _key.dispose();
    unawaited(_player?.dispose());
    super.dispose();
  }

  AiSecrets get _secrets => ref.read(aiSecretsProvider);

  Future<void> _readKey() async {
    final key = await _secrets.read(voiceKeyName(widget.config.id));
    if (mounted) setState(() => _hasKey = key != null && key.isNotEmpty);
  }

  void _save(VoiceConfig config) => ref
      .read(aiSettingsProvider.notifier)
      .update(ref.read(aiSettingsProvider).withVoice(config));

  Future<void> _saveKey() async {
    final key = _key.text.trim();
    await _secrets.write(
      voiceKeyName(widget.config.id),
      key.isEmpty ? null : key,
    );
    if (!mounted) return;
    _key.clear();
    await _readKey();
  }

  Future<void> _remove() async {
    await _secrets.write(voiceKeyName(widget.config.id), null);
    if (!mounted) return;
    ref
        .read(aiSettingsProvider.notifier)
        .update(ref.read(aiSettingsProvider).withoutVoice(widget.config.id));
  }

  /// Speaks a sentence with the first voice, and plays it.
  Future<void> _try() async {
    setState(() {
      _trying = true;
      _said = null;
    });
    final config = widget.config;
    final speech = config.create(
      apiKey: await _secrets.read(voiceKeyName(config.id)),
    );
    try {
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
      speech.close();
      if (mounted) setState(() => _trying = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final tones = context.tones;
    final config = widget.config;
    final host = Uri.tryParse(config.baseUrl)?.host ?? config.baseUrl;
    final note = TextStyle(fontSize: 12, height: 1.4, color: tones.muted);
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
          Row(
            children: <Widget>[
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: <Widget>[
                    Text(
                      config.name,
                      style: const TextStyle(
                        fontSize: 13.5,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                    Text(
                      config.local
                          ? 'On this computer — what is said stays here'
                          : 'Sends the words to speak to $host',
                      style: note,
                    ),
                  ],
                ),
              ),
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
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: <Widget>[
              Expanded(
                child: TextField(
                  controller: _key,
                  obscureText: true,
                  decoration: InputDecoration(
                    labelText: config.preset.needsKey
                        ? 'API key'
                        : 'API key, if it needs one',
                    helperText: _hasKey
                        ? 'A key is kept in this computer’s keychain. Type a '
                              'new one to replace it.'
                        : 'Kept in this computer’s keychain, never in a file.',
                  ),
                  onSubmitted: (_) => _saveKey(),
                ),
              ),
              const SizedBox(width: 8),
              OutlinedButton(
                onPressed: _saveKey,
                child: const Text('Save key'),
              ),
            ],
          ),
          const SizedBox(height: 6),
          Align(
            alignment: Alignment.centerRight,
            child: SmallButton(
              'Remove this voice provider',
              onPressed: () => unawaited(_remove()),
            ),
          ),
        ],
      ),
    );
  }
}

/// A kind of podcast: its name, what it is to be, how many parts, its
/// language and speakers, and the models that plan and write it.
class _EpisodeEditor extends ConsumerStatefulWidget {
  const _EpisodeEditor({this.episode});

  /// The profile changed, or null for a new one.
  final EpisodeProfile? episode;

  @override
  ConsumerState<_EpisodeEditor> createState() => _EpisodeEditorState();
}

class _EpisodeEditorState extends ConsumerState<_EpisodeEditor> {
  late final String _id = widget.episode?.id ?? Ulid.generate();
  late final TextEditingController _name = TextEditingController(
    text: widget.episode?.name ?? '',
  );
  late final TextEditingController _briefing = TextEditingController(
    text: widget.episode?.briefing ?? '',
  );
  late final TextEditingController _language = TextEditingController(
    text: widget.episode?.language ?? '',
  );
  late int _segments = widget.episode?.segments ?? 4;
  late String _speakers =
      widget.episode?.speakersId ??
      ref.read(aiSettingsProvider).casts.firstOrNull?.id ??
      '';
  late ModelChoice _outline = widget.episode?.outline ?? ModelChoice.inUse;
  late ModelChoice _transcript =
      widget.episode?.transcript ?? ModelChoice.inUse;

  @override
  void initState() {
    super.initState();
    for (final field in <TextEditingController>[_name, _briefing]) {
      field.addListener(() => setState(() {}));
    }
  }

  @override
  void dispose() {
    _name.dispose();
    _briefing.dispose();
    _language.dispose();
    super.dispose();
  }

  EpisodeProfile? get _edited {
    final name = _name.text.trim();
    final briefing = _briefing.text.trim();
    if (name.isEmpty || briefing.isEmpty) return null;
    return EpisodeProfile(
      id: _id,
      name: name,
      briefing: briefing,
      speakersId: _speakers,
      segments: _segments,
      language: _language.text.trim(),
      outline: _outline,
      transcript: _transcript,
    );
  }

  void _settle(AiSettings Function(AiSettings settings) change) {
    ref
        .read(aiSettingsProvider.notifier)
        .update(change(ref.read(aiSettingsProvider)));
    Navigator.of(context).pop();
  }

  @override
  Widget build(BuildContext context) {
    final tones = context.tones;
    final settings = ref.watch(aiSettingsProvider);
    final episode = widget.episode;
    final note = TextStyle(fontSize: 12, height: 1.4, color: tones.muted);
    return GlassDialog(
      title: Text(episode == null ? 'New kind of podcast' : 'Edit the podcast'),
      content: SizedBox(
        width: 580,
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: <Widget>[
              TextField(
                controller: _name,
                autofocus: episode == null,
                decoration: const InputDecoration(
                  labelText: 'Name',
                  hintText: 'Before the test',
                ),
              ),
              const SizedBox(height: 16),
              TextField(
                controller: _briefing,
                minLines: 3,
                maxLines: 8,
                decoration: const InputDecoration(
                  labelText: 'What it is to be',
                  alignLabelWithHint: true,
                  hintText:
                      'A debate between two students about what the notes '
                      'claim, ending with what the exam would ask.',
                  helperText:
                      'The briefing: how it goes, who it is for, what to '
                      'dwell on. What you say about yourself in the AI '
                      'settings goes with it.',
                  helperMaxLines: 2,
                ),
              ),
              const SizedBox(height: 16),
              SmallCaps('Parts', color: tones.muted),
              const SizedBox(height: 6),
              ChoiceRow<int>(
                choices: const <int>[2, 3, 4, 5, 6, 8, 10, 12],
                selected: _segments,
                labelOf: (n) => '$n',
                onSelected: (n) => setState(() => _segments = n),
              ),
              const SizedBox(height: 4),
              Text(
                'Each part is written by a request of its own; a part runs '
                'one to four minutes.',
                style: note,
              ),
              const SizedBox(height: 16),
              TextField(
                controller: _language,
                decoration: const InputDecoration(
                  labelText: 'Language',
                  hintText: 'The language of the notes',
                ),
              ),
              const SizedBox(height: 16),
              DropdownMenu<String>(
                initialSelection: settings.castOf(_speakers)?.id,
                label: const Text('Who speaks'),
                expandedInsets: EdgeInsets.zero,
                trailingIcon: const Mark(MarkShape.chevronDown),
                selectedTrailingIcon: const Mark(MarkShape.chevronUp),
                dropdownMenuEntries: <DropdownMenuEntry<String>>[
                  for (final cast in settings.casts)
                    DropdownMenuEntry<String>(
                      value: cast.id,
                      label:
                          '${cast.name} — '
                          '${cast.speakers.map((s) => s.name).join(', ')}',
                    ),
                ],
                onSelected: (id) {
                  if (id != null) setState(() => _speakers = id);
                },
              ),
              const SizedBox(height: 18),
              _ModelChoiceField(
                label: 'Plans it',
                choice: _outline,
                onChanged: (choice) => setState(() => _outline = choice),
              ),
              const SizedBox(height: 12),
              _ModelChoiceField(
                label: 'Writes what is said',
                choice: _transcript,
                onChanged: (choice) => setState(() => _transcript = choice),
              ),
              const SizedBox(height: 6),
              Text(
                'Any model of a provider set up under AI. The planner reads '
                'your notes once; the writer reads them again for every part.',
                style: note,
              ),
            ],
          ),
        ),
      ),
      actions: <Widget>[
        if (episode != null)
          TextButton(
            onPressed: () => _settle((s) => s.withoutEpisode(episode.id)),
            child: const Text('Delete'),
          ),
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('Cancel'),
        ),
        FilledButton(
          onPressed: _edited == null
              ? null
              : () => _settle((s) => s.withEpisode(_edited!)),
          child: const Text('Save'),
        ),
      ],
    );
  }
}

/// A model to write with: the one in use for questions, or a provider set
/// up and any model it has.
class _ModelChoiceField extends ConsumerStatefulWidget {
  const _ModelChoiceField({
    required this.label,
    required this.choice,
    required this.onChanged,
  });

  final String label;
  final ModelChoice choice;
  final ValueChanged<ModelChoice> onChanged;

  @override
  ConsumerState<_ModelChoiceField> createState() => _ModelChoiceFieldState();
}

class _ModelChoiceFieldState extends ConsumerState<_ModelChoiceField> {
  late final TextEditingController _model = TextEditingController(
    text: widget.choice.model,
  );
  Future<List<ModelInfo>>? _models;
  String? _listed;

  @override
  void dispose() {
    _model.dispose();
    super.dispose();
  }

  /// Asks the provider chosen for its models, once for each provider.
  void _list(ProviderConfig? config) {
    if (config == null || config.id == _listed) return;
    _listed = config.id;
    _models = () async {
      final key = await ref
          .read(aiSecretsProvider)
          .read(providerKeyName(config.id));
      final provider = config.create(apiKey: key);
      try {
        return await provider.listModels();
      } finally {
        provider.close();
      }
    }();
  }

  @override
  Widget build(BuildContext context) {
    final settings = ref.watch(aiSettingsProvider);
    final choice = widget.choice;
    final config = choice.isInUse ? null : settings.providerOf(choice);
    _list(config);
    const inUse = '';
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: <Widget>[
        DropdownMenu<String>(
          initialSelection: choice.providerId,
          label: Text(widget.label),
          expandedInsets: EdgeInsets.zero,
          trailingIcon: const Mark(MarkShape.chevronDown),
          selectedTrailingIcon: const Mark(MarkShape.chevronUp),
          dropdownMenuEntries: <DropdownMenuEntry<String>>[
            DropdownMenuEntry<String>(
              value: inUse,
              label: switch (settings.active) {
                final active? when active.model.isNotEmpty =>
                  'The model in use — ${active.model}',
                _ => 'The model in use',
              },
            ),
            for (final provider in settings.providers)
              DropdownMenuEntry<String>(
                value: provider.id,
                label: provider.name,
              ),
          ],
          onSelected: (id) {
            if (id == null) return;
            _model.clear();
            widget.onChanged(ModelChoice(providerId: id));
          },
        ),
        if (config != null)
          Padding(
            padding: const EdgeInsets.only(top: 8, left: 16),
            child: FutureBuilder<List<ModelInfo>>(
              future: _models,
              builder: (context, snapshot) {
                final models = snapshot.data ?? const <ModelInfo>[];
                void choose(String model) => widget.onChanged(
                  ModelChoice(providerId: config.id, model: model.trim()),
                );
                if (models.isEmpty) {
                  return TextField(
                    controller: _model,
                    decoration: InputDecoration(
                      labelText: 'Model',
                      hintText: config.model.isEmpty
                          ? 'The model’s id'
                          : '${config.model}, as the provider is set',
                    ),
                    onChanged: choose,
                  );
                }
                return DropdownMenu<String>(
                  key: ValueKey<int>(models.length),
                  initialSelection: choice.model.isEmpty
                      ? config.model
                      : choice.model,
                  label: const Text('Model'),
                  expandedInsets: EdgeInsets.zero,
                  enableFilter: true,
                  requestFocusOnTap: true,
                  menuHeight: 320,
                  trailingIcon: const Mark(MarkShape.chevronDown),
                  selectedTrailingIcon: const Mark(MarkShape.chevronUp),
                  dropdownMenuEntries: <DropdownMenuEntry<String>>[
                    for (final model in models)
                      DropdownMenuEntry<String>(
                        value: model.id,
                        label: model.name,
                      ),
                  ],
                  onSelected: (model) {
                    if (model != null) choose(model);
                  },
                );
              },
            ),
          ),
      ],
    );
  }
}

/// Who speaks: a name for them together, the voice provider and model they
/// speak through, and each speaker.
class _CastEditor extends ConsumerStatefulWidget {
  const _CastEditor({this.cast});

  final SpeakerProfile? cast;

  @override
  ConsumerState<_CastEditor> createState() => _CastEditorState();
}

/// The fields of one speaker being edited.
class _SpeakerFields {
  _SpeakerFields(PodcastSpeaker speaker)
    : name = TextEditingController(text: speaker.name),
      voice = TextEditingController(text: speaker.voice),
      backstory = TextEditingController(text: speaker.backstory),
      personality = TextEditingController(text: speaker.personality);

  final TextEditingController name;
  final TextEditingController voice;
  final TextEditingController backstory;
  final TextEditingController personality;

  PodcastSpeaker get speaker => PodcastSpeaker(
    name: name.text.trim(),
    voice: voice.text.trim(),
    backstory: backstory.text.trim(),
    personality: personality.text.trim(),
  );

  void dispose() {
    name.dispose();
    voice.dispose();
    backstory.dispose();
    personality.dispose();
  }
}

class _CastEditorState extends ConsumerState<_CastEditor> {
  late final String _id = widget.cast?.id ?? Ulid.generate();
  late final TextEditingController _name = TextEditingController(
    text: widget.cast?.name ?? '',
  );
  late final TextEditingController _voiceModel = TextEditingController(
    text: widget.cast?.voiceModel ?? '',
  );
  late String _voiceId = widget.cast?.voiceId ?? '';
  late final List<_SpeakerFields> _speakers = <_SpeakerFields>[
    for (final speaker
        in widget.cast?.speakers ??
            const <PodcastSpeaker>[PodcastSpeaker(name: '')])
      _SpeakerFields(speaker),
  ];
  Future<List<VoiceInfo>>? _voices;
  String? _listed;

  @override
  void initState() {
    super.initState();
    _name.addListener(() => setState(() {}));
  }

  @override
  void dispose() {
    _name.dispose();
    _voiceModel.dispose();
    for (final speaker in _speakers) {
      speaker.dispose();
    }
    super.dispose();
  }

  void _list(VoiceConfig? config) {
    if (config == null || config.id == _listed) return;
    _listed = config.id;
    _voices = () async {
      final speech = config.create(
        apiKey: await ref.read(aiSecretsProvider).read(voiceKeyName(config.id)),
      );
      try {
        return await speech.listVoices();
      } on Object {
        return <VoiceInfo>[
          for (final voice in config.preset.voices) VoiceInfo(voice),
        ];
      } finally {
        speech.close();
      }
    }();
  }

  SpeakerProfile? get _edited {
    final name = _name.text.trim();
    final speakers = <PodcastSpeaker>[
      for (final fields in _speakers)
        if (fields.speaker.name.isNotEmpty) fields.speaker,
    ];
    if (name.isEmpty || speakers.isEmpty) return null;
    return SpeakerProfile(
      id: _id,
      name: name,
      speakers: speakers,
      voiceId: _voiceId,
      voiceModel: _voiceModel.text.trim(),
    );
  }

  void _settle(AiSettings Function(AiSettings settings) change) {
    ref
        .read(aiSettingsProvider.notifier)
        .update(change(ref.read(aiSettingsProvider)));
    Navigator.of(context).pop();
  }

  @override
  Widget build(BuildContext context) {
    final tones = context.tones;
    final settings = ref.watch(aiSettingsProvider);
    final cast = widget.cast;
    final voice = settings.voiceOf(_voiceId);
    _list(voice);
    return GlassDialog(
      title: Text(cast == null ? 'New speakers' : 'Edit who speaks'),
      content: SizedBox(
        width: 600,
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: <Widget>[
              TextField(
                controller: _name,
                autofocus: cast == null,
                decoration: const InputDecoration(
                  labelText: 'Name',
                  hintText: 'Two historians',
                ),
              ),
              const SizedBox(height: 16),
              if (settings.voices.isEmpty)
                Text(
                  'Add a voice provider on this page to choose the voices.',
                  style: TextStyle(fontSize: 12, color: tones.muted),
                )
              else
                Row(
                  children: <Widget>[
                    Expanded(
                      child: DropdownMenu<String>(
                        initialSelection: voice?.id,
                        label: const Text('Voice provider'),
                        expandedInsets: EdgeInsets.zero,
                        trailingIcon: const Mark(MarkShape.chevronDown),
                        selectedTrailingIcon: const Mark(MarkShape.chevronUp),
                        dropdownMenuEntries: <DropdownMenuEntry<String>>[
                          for (final voice in settings.voices)
                            DropdownMenuEntry<String>(
                              value: voice.id,
                              label: voice.name,
                            ),
                        ],
                        onSelected: (id) {
                          if (id != null) setState(() => _voiceId = id);
                        },
                      ),
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: TextField(
                        controller: _voiceModel,
                        decoration: InputDecoration(
                          labelText: 'Voice model',
                          hintText: voice?.model ?? '',
                        ),
                      ),
                    ),
                  ],
                ),
              for (final (i, fields) in _speakers.indexed) ...<Widget>[
                const SizedBox(height: 18),
                Row(
                  children: <Widget>[
                    Expanded(
                      child: SmallCaps(
                        'Speaker ${i + 1}',
                        color: tones.emphasis,
                      ),
                    ),
                    if (_speakers.length > 1)
                      SmallButton(
                        'Remove',
                        onPressed: () =>
                            setState(() => _speakers.removeAt(i).dispose()),
                      ),
                  ],
                ),
                const SizedBox(height: 6),
                Row(
                  children: <Widget>[
                    Expanded(
                      child: TextField(
                        controller: fields.name,
                        onChanged: (_) => setState(() {}),
                        decoration: const InputDecoration(labelText: 'Name'),
                      ),
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: _VoicePicker(
                        controller: fields.voice,
                        voices: _voices,
                        fallback: voice?.voiceFor(i) ?? '',
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 8),
                TextField(
                  controller: fields.backstory,
                  minLines: 1,
                  maxLines: 3,
                  decoration: const InputDecoration(
                    labelText: 'Who they are',
                    hintText: 'A physics teacher who loves experiments.',
                  ),
                ),
                const SizedBox(height: 8),
                TextField(
                  controller: fields.personality,
                  minLines: 1,
                  maxLines: 3,
                  decoration: const InputDecoration(
                    labelText: 'How they speak',
                    hintText: 'Calm and precise, with a dry sense of humour.',
                  ),
                ),
              ],
              if (_speakers.length < SpeakerProfile.maxSpeakers)
                Padding(
                  padding: const EdgeInsets.only(top: 12),
                  child: Align(
                    alignment: Alignment.centerLeft,
                    child: OutlinedButton(
                      onPressed: () => setState(
                        () => _speakers.add(
                          _SpeakerFields(const PodcastSpeaker(name: '')),
                        ),
                      ),
                      child: const Text('Add a speaker'),
                    ),
                  ),
                ),
            ],
          ),
        ),
      ),
      actions: <Widget>[
        if (cast != null)
          TextButton(
            onPressed: () => _settle((s) => s.withoutCast(cast.id)),
            child: const Text('Delete'),
          ),
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('Cancel'),
        ),
        FilledButton(
          onPressed: _edited == null
              ? null
              : () => _settle((s) => s.withCast(_edited!)),
          child: const Text('Save'),
        ),
      ],
    );
  }
}

/// A speaker's voice: one the provider lists, or any typed in.
class _VoicePicker extends StatelessWidget {
  const _VoicePicker({
    required this.controller,
    required this.voices,
    required this.fallback,
  });

  final TextEditingController controller;
  final Future<List<VoiceInfo>>? voices;

  /// The voice they get where none is chosen.
  final String fallback;

  @override
  Widget build(BuildContext context) => FutureBuilder<List<VoiceInfo>>(
    future: voices,
    builder: (context, snapshot) {
      final listed = snapshot.data ?? const <VoiceInfo>[];
      final hint = fallback.isEmpty ? 'Its id' : '$fallback, unless chosen';
      if (listed.isEmpty) {
        return TextField(
          controller: controller,
          decoration: InputDecoration(labelText: 'Voice', hintText: hint),
        );
      }
      return DropdownMenu<String>(
        key: ValueKey<int>(listed.length),
        controller: controller,
        initialSelection: controller.text.isEmpty ? null : controller.text,
        label: const Text('Voice'),
        hintText: hint,
        expandedInsets: EdgeInsets.zero,
        enableFilter: true,
        requestFocusOnTap: true,
        menuHeight: 300,
        trailingIcon: const Mark(MarkShape.chevronDown),
        selectedTrailingIcon: const Mark(MarkShape.chevronUp),
        // The menu writes what it shows; the voice is kept by its id.
        onSelected: (id) {
          if (id != null) controller.text = id;
        },
        dropdownMenuEntries: <DropdownMenuEntry<String>>[
          for (final voice in listed)
            DropdownMenuEntry<String>(
              value: voice.id,
              label: voice.name == voice.id
                  ? voice.id
                  : '${voice.name} (${voice.id})',
            ),
        ],
      );
    },
  );
}
