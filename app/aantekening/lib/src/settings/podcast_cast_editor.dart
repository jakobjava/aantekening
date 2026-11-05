part of 'podcast_settings.dart';

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
            onPressed: () =>
                settleAiSettings(context, ref, (s) => s.withoutCast(cast.id)),
            child: const Text('Delete'),
          ),
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('Cancel'),
        ),
        FilledButton(
          onPressed: _edited == null
              ? null
              : () =>
                    settleAiSettings(context, ref, (s) => s.withCast(_edited!)),
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
