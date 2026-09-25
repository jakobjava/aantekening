/// Choosing which models to ask, and how the web is searched.
library;

import 'dart:async';

import 'package:aantekening_ai/aantekening_ai.dart';
import 'package:aantekening_core/aantekening_core.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../ai/ai_state.dart';
import '../look/controls.dart';
import '../look/marks.dart';
import '../look/tones.dart';
import 'settings_view.dart';

/// The AI page of the settings: the providers set up — each saying plainly
/// whether the notes stay on this computer or go to a service — which one
/// questions go to and its model, and how the web is searched.
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
            Align(
              alignment: Alignment.centerLeft,
              child: MenuAnchor(
                menuChildren: <Widget>[
                  const _MenuHeading('On this computer'),
                  for (final preset in ProviderPreset.values)
                    if (preset.local || preset == ProviderPreset.custom)
                      MenuItemButton(
                        onPressed: () => add(preset),
                        child: Text(preset.label),
                      ),
                  const _MenuHeading('Online'),
                  for (final preset in ProviderPreset.values)
                    if (!preset.local && preset != ProviderPreset.custom)
                      MenuItemButton(
                        onPressed: () => add(preset),
                        child: Text(preset.label),
                      ),
                ],
                builder: (context, menu, _) => OutlinedButton(
                  onPressed: () => menu.isOpen ? menu.close() : menu.open(),
                  child: const Text('Add a model provider…'),
                ),
              ),
            ),
          ],
        ),
        const _WebSettings(),
      ],
    );
  }
}

class _MenuHeading extends StatelessWidget {
  const _MenuHeading(this.label);

  final String label;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.fromLTRB(12, 8, 12, 4),
    child: SmallCaps(label),
  );
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
  final TextEditingController _key = TextEditingController();
  late final TextEditingController _model = TextEditingController(
    text: widget.config.model,
  );
  bool _open = false;
  bool _hasKey = false;
  Future<List<ModelInfo>>? _models;

  @override
  void initState() {
    super.initState();
    _open = widget.config.model.isEmpty;
    unawaited(_readKey());
    _loadModels();
  }

  @override
  void dispose() {
    _url.dispose();
    _key.dispose();
    _model.dispose();
    super.dispose();
  }

  AiSecrets get _secrets => ref.read(aiSecretsProvider);

  Future<void> _readKey() async {
    final key = await _secrets.read(providerKeyName(widget.config.id));
    if (mounted) setState(() => _hasKey = key != null && key.isNotEmpty);
  }

  void _loadModels() {
    setState(() {
      _models = () async {
        final key = await _secrets.read(providerKeyName(widget.config.id));
        final provider = widget.config.create(apiKey: key);
        try {
          return await provider.listModels();
        } finally {
          provider.close();
        }
      }();
    });
  }

  void _save(ProviderConfig config) {
    final settings = ref.read(aiSettingsProvider);
    ref.read(aiSettingsProvider.notifier).update(settings.withProvider(config));
  }

  Future<void> _saveKey() async {
    final key = _key.text.trim();
    await _secrets.write(
      providerKeyName(widget.config.id),
      key.isEmpty ? null : key,
    );
    _key.clear();
    ref.invalidate(aiModelProvider);
    await _readKey();
    _loadModels();
  }

  Future<void> _remove() async {
    await _secrets.write(providerKeyName(widget.config.id), null);
    final settings = ref.read(aiSettingsProvider);
    ref
        .read(aiSettingsProvider.notifier)
        .update(settings.withoutProvider(widget.config.id));
  }

  void _chooseModel(String model) {
    _model.text = model;
    _save(widget.config.copyWith(model: model));
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
        border: Border.all(color: widget.active ? tones.emphasis : tones.line),
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
                          ? 'On this computer — your notes stay here'
                          : 'Sends the notes you ask about to $host',
                      style: note,
                    ),
                  ],
                ),
              ),
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
          if (config.kind == ProviderKind.ollama) ...<Widget>[
            const SizedBox(height: 12),
            _howItRuns(config, note),
          ],
          if (_open) ...<Widget>[
            const SizedBox(height: 12),
            TextField(
              controller: _url,
              decoration: const InputDecoration(labelText: 'Address'),
              onSubmitted: (url) {
                _save(config.copyWith(baseUrl: url.trim()));
                _loadModels();
              },
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
                          ? 'A key is kept in this computer’s keychain. '
                                'Type a new one to replace it.'
                          : 'Kept in this computer’s keychain, never in a '
                                'file.',
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
                'Remove this provider',
                onPressed: () => unawaited(_remove()),
              ),
            ),
          ],
        ],
      ),
    );
  }

  /// How a runtime that is told it runs the model: with how much room,
  /// and whether it thinks first.
  Widget _howItRuns(ProviderConfig config, TextStyle note) {
    final room = config.contextTokens ?? OllamaProvider.defaultContextTokens;
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
        explained(
          'Room',
          ChoiceRow<int>(
            choices: OllamaProvider.contextChoices,
            selected: room,
            labelOf: (tokens) => '${tokens ~/ 1024}k',
            onSelected: (tokens) =>
                _save(config.copyWith(contextTokens: tokens)),
          ),
          'Tokens for the notes, the model’s thinking and its answer '
              'together. More room fits more notes and longer thinking, and '
              'takes more memory.',
        ),
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
    );
  }

  Widget _modelPicker(Tones tones) => FutureBuilder<List<ModelInfo>>(
    future: _models,
    builder: (context, snapshot) {
      final models = snapshot.data ?? const <ModelInfo>[];
      final error = snapshot.error;
      final looking = snapshot.connectionState == ConnectionState.waiting;
      return Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: <Widget>[
          Row(
            children: <Widget>[
              Expanded(
                child: models.isEmpty
                    ? TextField(
                        controller: _model,
                        decoration: const InputDecoration(labelText: 'Model'),
                        onSubmitted: (model) => _chooseModel(model.trim()),
                      )
                    : DropdownMenu<String>(
                        key: ValueKey<int>(models.length),
                        initialSelection: widget.config.model.isEmpty
                            ? null
                            : widget.config.model,
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
                              label: model.capabilities.reasoning
                                  ? '${model.name}  · thinks first'
                                  : model.name,
                            ),
                        ],
                        onSelected: (model) {
                          if (model != null) _chooseModel(model);
                        },
                      ),
              ),
              const SizedBox(width: 8),
              SizedBox(
                width: 84,
                child: looking
                    ? const Center(child: Busy(width: 32))
                    : SmallButton(
                        'Look again',
                        tooltip: 'Ask for the models again',
                        onPressed: _loadModels,
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
            ),
        ],
      );
    },
  );
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

  void _update(AiSettings Function(AiSettings settings) change) => ref
      .read(aiSettingsProvider.notifier)
      .update(change(ref.read(aiSettingsProvider)));

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
              onSubmitted: (url) {
                _update((s) => s.copyWith(searxngUrl: url.trim()));
                ref.invalidate(webSearchProvider);
              },
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
