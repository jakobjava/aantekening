part of 'podcast_settings.dart';

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
            onPressed: () => settleAiSettings(
              context,
              ref,
              (s) => s.withoutEpisode(episode.id),
            ),
            child: const Text('Delete'),
          ),
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('Cancel'),
        ),
        FilledButton(
          onPressed: _edited == null
              ? null
              : () => settleAiSettings(
                  context,
                  ref,
                  (s) => s.withEpisode(_edited!),
                ),
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

  @override
  void dispose() {
    _model.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final settings = ref.watch(aiSettingsProvider);
    final choice = widget.choice;
    final config = choice.isInUse ? null : settings.providerOf(choice);
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
            child: ModelMenu(
              models:
                  ref.watch(providerModelsProvider(config.id)).value ??
                  const <ModelInfo>[],
              selected: choice.model.isEmpty ? config.model : choice.model,
              onSelected: (model) => widget.onChanged(
                ModelChoice(providerId: config.id, model: model.trim()),
              ),
              typed: TextField(
                controller: _model,
                decoration: InputDecoration(
                  labelText: 'Model',
                  hintText: config.model.isEmpty
                      ? 'The model’s id'
                      : '${config.model}, as the provider is set',
                ),
                onChanged: (model) => widget.onChanged(
                  ModelChoice(providerId: config.id, model: model.trim()),
                ),
              ),
            ),
          ),
      ],
    );
  }
}
