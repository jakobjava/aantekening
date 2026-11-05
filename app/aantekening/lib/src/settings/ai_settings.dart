/// Choosing which models to ask, what they are told, what they make to
/// study from, and how the web is searched.
library;

import 'package:aantekening_ai/aantekening_ai.dart';
import 'package:aantekening_core/aantekening_core.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../ai/ai_state.dart';
import '../ai/money.dart';
import '../ai/study_profile_editor.dart';
import '../look/controls.dart';
import '../look/tones.dart';
import 'provider_block.dart';
import 'settings_view.dart';

/// The AI page of the settings: the providers set up — each saying plainly
/// whether the notes stay on this computer or go to a service — which one
/// questions go to and its model; what the person tells every model of
/// themselves; the study profiles; and how the web is searched.
class AiSettingsPage extends ConsumerWidget {
  const AiSettingsPage({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final settings = ref.watch(aiSettingsProvider);
    final controller = ref.read(aiSettingsProvider.notifier);

    void add(ProviderPreset preset) {
      final config = ProviderConfig.of(preset, id: Ulid.generate());
      controller.update(
        settings.withProvider(config).copyWith(activeId: config.id),
      );
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: <Widget>[
        SettingsSection(
          title: 'Models',
          description:
              'Ask about your notes with a model on this computer, or with a '
              'service you choose. Nothing is sent anywhere until you ask '
              'something, and then only the notes it is about, and only to '
              'the model in use. What the AI writes is kept apart from your '
              'notes.',
          children: <Widget>[
            for (final config in settings.providers)
              _ProviderBlock(
                key: ValueKey<String>(config.id),
                config: config,
                active: settings.active?.id == config.id,
                onUse: () =>
                    controller.update(settings.copyWith(activeId: config.id)),
              ),
            const SizedBox(height: 6),
            AddProviderMenu<ProviderPreset>(
              label: 'Add a model provider…',
              presets: ProviderPreset.values,
              ownServer: (preset) => preset.ownServer,
              labelOf: (preset) => preset.label,
              onAdd: add,
            ),
          ],
        ),
        const _AboutYou(),
        const _StudyProfiles(),
        const _WebSettings(),
      ],
    );
  }
}

/// What the person tells every model of themselves.
class _AboutYou extends ConsumerStatefulWidget {
  const _AboutYou();

  @override
  ConsumerState<_AboutYou> createState() => _AboutYouState();
}

class _AboutYouState extends ConsumerState<_AboutYou> {
  late final TextEditingController _about = TextEditingController(
    text: ref.read(aiSettingsProvider).about,
  );

  @override
  void dispose() {
    _about.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => SettingsSection(
    title: 'About you',
    description:
        'Told to the model with every question and study set, so it answers '
        'for you: your school year, your course, the exams you are working '
        'towards.',
    children: <Widget>[
      TextField(
        controller: _about,
        minLines: 2,
        maxLines: 5,
        decoration: const InputDecoration(
          hintText:
              'I am in Q13 at a Gymnasium in Bavaria, with physics and maths '
              'as my Abitur subjects.',
        ),
        onChanged: (about) => ref
            .read(aiSettingsProvider.notifier)
            .change((s) => s.copyWith(about: about.trim())),
      ),
    ],
  );
}

/// The study profiles: what each makes, a way to change it, and a way to
/// make a new one.
class _StudyProfiles extends ConsumerWidget {
  const _StudyProfiles();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final profiles = ref.watch(aiSettingsProvider).studyProfiles;
    return SettingsSection(
      title: 'Study profiles',
      description:
          'What the AI makes to study from, offered in the AI of every '
          'notebook, section and page. Change what each asks for, or '
          'describe something new.',
      children: <Widget>[
        for (final profile in profiles)
          RowTile(
            padding: const EdgeInsets.fromLTRB(0, 6, 0, 6),
            title: Text(profile.name),
            subtitle: Text(
              <String>[
                if (profile.name != profile.form.label) profile.form.label,
                if (profile.isOriginal)
                  profile.isAsMade ? 'As it comes' : 'Changed',
                if (profile.details.isNotEmpty) profile.details,
              ].join('  ·  '),
            ),
            trailing: SmallButton(
              'Edit',
              onPressed: () => editStudyProfile(context, profile: profile),
            ),
            onTap: () => editStudyProfile(context, profile: profile),
          ),
        const SizedBox(height: 8),
        Align(
          alignment: Alignment.centerLeft,
          child: OutlinedButton(
            onPressed: () => editStudyProfile(context),
            child: const Text('New study profile…'),
          ),
        ),
      ],
    );
  }
}

/// One provider: whether it is the one asked, where the notes go, its
/// model, and — opened — its address and key.
class _ProviderBlock extends ConsumerStatefulWidget {
  const _ProviderBlock({
    required this.config,
    required this.active,
    required this.onUse,
    super.key,
  });

  final ProviderConfig config;
  final bool active;
  final VoidCallback onUse;

  @override
  ConsumerState<_ProviderBlock> createState() => _ProviderBlockState();
}

class _ProviderBlockState extends ConsumerState<_ProviderBlock> {
  late final TextEditingController _url = TextEditingController(
    text: widget.config.baseUrl,
  );
  late final TextEditingController _model = TextEditingController(
    text: widget.config.model,
  );
  bool _open = false;

  @override
  void initState() {
    super.initState();
    _open = widget.config.model.isEmpty;
  }

  @override
  void dispose() {
    _url.dispose();
    _model.dispose();
    super.dispose();
  }

  void _save(ProviderConfig config) => ref
      .read(aiSettingsProvider.notifier)
      .change((s) => s.withProvider(config));

  void _chooseModel(String model) {
    _model.text = model;
    _save(widget.config.copyWith(model: model));
  }

  @override
  Widget build(BuildContext context) {
    final tones = context.tones;
    final config = widget.config;
    final note = TextStyle(fontSize: 12, height: 1.4, color: tones.muted);
    return Container(
      margin: const EdgeInsets.only(bottom: 10),
      decoration: BoxDecoration(
        border: Border.all(color: widget.active ? tones.emphasis : tones.line),
      ),
      padding: const EdgeInsets.fromLTRB(14, 10, 10, 12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: <Widget>[
          ProviderHeading(
            name: config.name,
            where: config.local
                ? 'On this computer — your notes stay here'
                : 'Sends the notes you ask about to ${hostOf(config.baseUrl)}',
            actions: <Widget>[
              if (widget.active)
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 6),
                  child: SmallCaps('In use', color: tones.emphasis),
                )
              else
                SmallButton('Use', onPressed: widget.onUse),
              SmallButton(
                _open ? 'Less' : 'More',
                tooltip: _open
                    ? 'Hide the address and key'
                    : 'Show the address and key',
                onPressed: () => setState(() => _open = !_open),
              ),
            ],
          ),
          const SizedBox(height: 10),
          _modelPicker(tones),
          const SizedBox(height: 12),
          _howItRuns(config, note),
          if (_open) ...<Widget>[
            const SizedBox(height: 12),
            TextField(
              controller: _url,
              decoration: const InputDecoration(labelText: 'Address'),
              onSubmitted: (url) => _save(config.copyWith(baseUrl: url.trim())),
            ),
            const SizedBox(height: 10),
            ProviderKeyField(
              name: providerKeyName(config.id),
              needsKey: config.preset.needsKey,
              onSaved: () {
                ref
                  ..invalidate(aiModelProvider)
                  ..invalidate(providerModelsProvider(config.id));
              },
            ),
            const SizedBox(height: 6),
            RemoveProviderButton(
              label: 'Remove this provider',
              keyName: providerKeyName(config.id),
              onRemoved: () => ref
                  .read(aiSettingsProvider.notifier)
                  .change((s) => s.withoutProvider(config.id)),
            ),
          ],
        ],
      ),
    );
  }

  /// How the model is asked: with how much of the notes and, where the
  /// app says or is told it, how much room; and whether a runtime that is
  /// told it thinks first.
  Widget _howItRuns(ProviderConfig config, TextStyle note) {
    final ollama = config.kind == ProviderKind.ollama;
    String tokensLabel(int tokens) => '${tokens ~/ 1024}k';
    Widget explained(String label, Widget control, String explanation) =>
        Padding(
          padding: const EdgeInsets.only(bottom: 10),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: <Widget>[
              Wrap(
                spacing: 12,
                runSpacing: 4,
                crossAxisAlignment: WrapCrossAlignment.center,
                children: <Widget>[
                  SizedBox(
                    width: 130,
                    child: Text(label, style: const TextStyle(fontSize: 13)),
                  ),
                  control,
                ],
              ),
              const SizedBox(height: 4),
              Text(explanation, style: note),
            ],
          ),
        );
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: <Widget>[
        if (ollama)
          explained(
            'Room',
            ChoiceRow<int>(
              choices: OllamaProvider.contextChoices,
              selected:
                  config.contextTokens ?? OllamaProvider.defaultContextTokens,
              labelOf: tokensLabel,
              onSelected: (tokens) =>
                  _save(config.copyWith(contextTokens: () => tokens)),
            ),
            'Tokens for the notes, the model’s thinking and its answer '
                'together. More room fits more notes and longer thinking, '
                'and takes more memory.',
          )
        else if (config.preset.ownServer)
          explained(
            'Room',
            ChoiceRow<int>(
              choices: const <int>[0, ...OpenAiCompatibleProvider.roomChoices],
              selected: config.contextTokens ?? 0,
              labelOf: (tokens) =>
                  tokens == 0 ? 'Automatic' : tokensLabel(tokens),
              onSelected: (tokens) => _save(
                config.copyWith(
                  contextTokens: () => tokens == 0 ? null : tokens,
                ),
              ),
            ),
            'How many tokens the model has where it runs, so that the notes '
                'fit. Automatic takes what the server says, and '
                '${tokensLabel(config.presumedContextTokens)} where it says '
                'nothing.',
          ),
        explained(
          'Notes per question',
          ChoiceRow<int>(
            choices: ContextBudget.notesChoices,
            selected: config.notesTokens,
            labelOf: (tokens) => '${tokens ~/ 1000}k',
            onSelected: (tokens) => _save(config.copyWith(notesTokens: tokens)),
          ),
          'Tokens of your notes sent with a question, at most — and never '
              'more than a third of what the model can take, to leave it '
              'room to read on and answer. More lets it take in a whole '
              'notebook at once, and costs more where each token is paid '
              'for.',
        ),
        if (ollama) ...<Widget>[
          explained(
            'Think for at most',
            ChoiceRow<int>(
              choices: <int>[
                for (final time in OllamaProvider.thinkingChoices)
                  time?.inSeconds ?? 0,
              ],
              selected: config.thinkingTime?.inSeconds ?? 0,
              labelOf: (seconds) =>
                  seconds == 0 ? 'No limit' : '${seconds ~/ 60} min',
              onSelected: (seconds) => _save(
                config.copyWith(
                  thinkingTime: () =>
                      seconds == 0 ? null : Duration(seconds: seconds),
                ),
              ),
            ),
            'Then the model is stopped and answers from what it has worked '
                'out — so a model going round in circles still answers.',
          ),
          CheckRow(
            title: 'Think before answering',
            description:
                'Better answers, but without a graphics card it can take '
                'minutes. Some models always think; an “instruct” model never '
                'does.',
            value: config.think,
            onChanged: (on) => _save(config.copyWith(think: on)),
          ),
        ],
      ],
    );
  }

  Widget _modelPicker(Tones tones) {
    final listed = ref.watch(providerModelsProvider(widget.config.id));
    final models = listed.value ?? const <ModelInfo>[];
    final error = listed.error;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: <Widget>[
        Row(
          children: <Widget>[
            Expanded(
              child: ModelMenu(
                models: models,
                selected: widget.config.model.isEmpty
                    ? null
                    : widget.config.model,
                onSelected: _chooseModel,
                labelOf: (model) => model.capabilities.reasoning
                    ? '${model.name}  · thinks first'
                    : model.name,
                trailingOf: (model) => switch (model.capabilities.price) {
                  final price? when !price.isFree => Text(
                    '${dollars(price.input)} / ${dollars(price.output)}',
                    style: TextStyle(fontSize: 12, color: tones.faint),
                  ),
                  _ => null,
                },
                typed: TextField(
                  controller: _model,
                  decoration: const InputDecoration(labelText: 'Model'),
                  onSubmitted: (model) => _chooseModel(model.trim()),
                ),
              ),
            ),
            const SizedBox(width: 8),
            SizedBox(
              width: 84,
              child: listed.isLoading
                  ? const Center(child: Busy(width: 32))
                  : SmallButton(
                      'Look again',
                      tooltip: 'Ask for the models again',
                      onPressed: () => ref.invalidate(
                        providerModelsProvider(widget.config.id),
                      ),
                    ),
            ),
          ],
        ),
        if (error != null)
          Padding(
            padding: const EdgeInsets.only(top: 4),
            child: Text(
              error is AiException ? error.message : '$error',
              style: TextStyle(fontSize: 12, color: tones.text),
            ),
          )
        else if (models
                .where((model) => model.id == widget.config.model)
                .firstOrNull
            case final chosen?)
          ?_priceNote(chosen.capabilities.price, tones),
      ],
    );
  }

  /// What the chosen model costs, as its provider lists it; nothing for a
  /// model that costs nothing.
  Widget? _priceNote(ModelPrice? price, Tones tones) {
    if (price != null && price.isFree) return null;
    return Padding(
      padding: const EdgeInsets.only(top: 4),
      child: Text(
        price == null
            ? 'Its price is not listed, so what answers cost is not shown.'
            : 'Costs ${dollars(price.input)} a million tokens read, '
                  '${dollars(price.output)} a million written: what each '
                  'answer and study set cost is shown with it.',
        style: TextStyle(fontSize: 12, color: tones.faint),
      ),
    );
  }
}

/// Whether questions search the web, and how, for providers that cannot
/// search it themselves.
class _WebSettings extends ConsumerStatefulWidget {
  const _WebSettings();

  @override
  ConsumerState<_WebSettings> createState() => _WebSettingsState();
}

class _WebSettingsState extends ConsumerState<_WebSettings> {
  late final TextEditingController _searxng;
  final TextEditingController _brave = TextEditingController();

  @override
  void initState() {
    super.initState();
    _searxng = TextEditingController(
      text: ref.read(aiSettingsProvider).searxngUrl,
    );
  }

  @override
  void dispose() {
    _searxng.dispose();
    _brave.dispose();
    super.dispose();
  }

  void _update(AiSettings Function(AiSettings settings) change) =>
      ref.read(aiSettingsProvider.notifier).change(change);

  @override
  Widget build(BuildContext context) {
    final settings = ref.watch(aiSettingsProvider);
    return SettingsSection(
      title: 'The web',
      children: <Widget>[
        CheckRow(
          title: 'Let answers search the web',
          description:
              'What is found is cited as the web, never as your notes. It '
              'can be turned off for any question.',
          value: settings.searchWeb,
          onChanged: (on) => _update((s) => s.copyWith(searchWeb: on)),
        ),
        SettingRow(
          label: 'Search with',
          description: 'Anthropic searches the web itself',
          child: ChoiceRow<WebSearchBackend>(
            choices: WebSearchBackend.values,
            selected: settings.webBackend,
            labelOf: (backend) => switch (backend) {
              WebSearchBackend.none => 'Nothing',
              WebSearchBackend.searxng => 'SearXNG',
              WebSearchBackend.brave => 'Brave Search',
            },
            onSelected: (backend) =>
                _update((s) => s.copyWith(webBackend: backend)),
          ),
        ),
        if (settings.webBackend == WebSearchBackend.searxng)
          Padding(
            padding: const EdgeInsets.only(top: 6),
            child: TextField(
              controller: _searxng,
              decoration: const InputDecoration(
                labelText: 'SearXNG address',
                helperText:
                    'A SearXNG you run yourself, with its JSON output on.',
              ),
              onSubmitted: (url) =>
                  _update((s) => s.copyWith(searxngUrl: url.trim())),
            ),
          ),
        if (settings.webBackend == WebSearchBackend.brave)
          Padding(
            padding: const EdgeInsets.only(top: 6),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: <Widget>[
                Expanded(
                  child: TextField(
                    controller: _brave,
                    obscureText: true,
                    decoration: const InputDecoration(
                      labelText: 'Brave Search API key',
                      helperText: 'Kept in this computer’s keychain.',
                    ),
                  ),
                ),
                const SizedBox(width: 8),
                OutlinedButton(
                  onPressed: () async {
                    await ref
                        .read(aiSecretsProvider)
                        .write(braveKeyName, _brave.text.trim());
                    if (!mounted) return;
                    _brave.clear();
                    ref.invalidate(webSearchProvider);
                  },
                  child: const Text('Save key'),
                ),
              ],
            ),
          ),
      ],
    );
  }
}
