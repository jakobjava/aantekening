/// Choosing which models to ask, and how the web is searched.
library;

import 'dart:async';

import 'package:aantekening_ai/aantekening_ai.dart';
import 'package:aantekening_core/aantekening_core.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'ai_state.dart';

/// Opens the AI's settings.
Future<void> showAiSettings(BuildContext context) => showDialog<void>(
  context: context,
  builder: (context) => const AiSettingsDialog(),
);

/// The providers the person has set up — each saying plainly whether the
/// notes stay on this computer or go to a service — which one questions go
/// to and its model, and how the web is searched.
class AiSettingsDialog extends ConsumerWidget {
  const AiSettingsDialog({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final settings = ref.watch(aiSettingsProvider);
    final controller = ref.read(aiSettingsProvider.notifier);
    final scheme = Theme.of(context).colorScheme;

    void add(ProviderPreset preset) {
      final config = ProviderConfig.of(preset, id: Ulid.generate());
      controller.update(
        settings.withProvider(config).copyWith(activeId: config.id),
      );
    }

    return Dialog(
      insetPadding: const EdgeInsets.all(24),
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 640, maxHeight: 760),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: <Widget>[
            Padding(
              padding: const EdgeInsets.fromLTRB(24, 20, 12, 8),
              child: Row(
                children: <Widget>[
                  Icon(Icons.auto_awesome_rounded, color: scheme.tertiary),
                  const SizedBox(width: 10),
                  Text(
                    'AI models',
                    style: Theme.of(context).textTheme.titleLarge,
                  ),
                  const Spacer(),
                  IconButton(
                    icon: const Icon(Icons.close_rounded),
                    tooltip: 'Close',
                    onPressed: () => Navigator.of(context).pop(),
                  ),
                ],
              ),
            ),
            Flexible(
              child: ListView(
                padding: const EdgeInsets.fromLTRB(24, 0, 24, 24),
                shrinkWrap: true,
                children: <Widget>[
                  Text(
                    'Ask about your notes with a model on this computer, or '
                    'with a service you choose. Nothing is sent anywhere until '
                    'you ask something, and then only the notes it is about, '
                    'and only to the model you picked. What the AI writes is '
                    'kept apart from your notes.',
                    style: TextStyle(
                      color: scheme.onSurfaceVariant,
                      height: 1.4,
                    ),
                  ),
                  const SizedBox(height: 16),
                  RadioGroup<String>(
                    groupValue: settings.active?.id,
                    onChanged: (id) =>
                        controller.update(settings.copyWith(activeId: id)),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: <Widget>[
                        for (final config in settings.providers)
                          _ProviderCard(
                            key: ValueKey<String>(config.id),
                            config: config,
                            active: settings.active?.id == config.id,
                          ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 4),
                  Align(
                    alignment: Alignment.centerLeft,
                    child: MenuAnchor(
                      menuChildren: <Widget>[
                        const _MenuHeading('On this computer'),
                        for (final preset in ProviderPreset.values)
                          if (preset.local || preset == ProviderPreset.custom)
                            MenuItemButton(
                              leadingIcon: const Icon(
                                Icons.computer_rounded,
                                size: 18,
                              ),
                              onPressed: () => add(preset),
                              child: Text(preset.label),
                            ),
                        const _MenuHeading('Online'),
                        for (final preset in ProviderPreset.values)
                          if (!preset.local && preset != ProviderPreset.custom)
                            MenuItemButton(
                              leadingIcon: const Icon(
                                Icons.cloud_outlined,
                                size: 18,
                              ),
                              onPressed: () => add(preset),
                              child: Text(preset.label),
                            ),
                      ],
                      builder: (context, menu, _) => OutlinedButton.icon(
                        icon: const Icon(Icons.add_rounded),
                        label: const Text('Add a model provider'),
                        onPressed: () =>
                            menu.isOpen ? menu.close() : menu.open(),
                      ),
                    ),
                  ),
                  const SizedBox(height: 24),
                  const _WebSettings(),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _MenuHeading extends StatelessWidget {
  const _MenuHeading(this.label);

  final String label;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.fromLTRB(12, 8, 12, 4),
    child: Text(
      label.toUpperCase(),
      style: TextStyle(
        fontSize: 11,
        letterSpacing: 0.6,
        fontWeight: FontWeight.w700,
        color: Theme.of(context).colorScheme.onSurfaceVariant,
      ),
    ),
  );
}

/// One provider: whether it is the one asked, where the notes go, its
/// model, and — opened — its address and key.
class _ProviderCard extends ConsumerStatefulWidget {
  const _ProviderCard({required this.config, required this.active, super.key});

  final ProviderConfig config;
  final bool active;

  @override
  ConsumerState<_ProviderCard> createState() => _ProviderCardState();
}

class _ProviderCardState extends ConsumerState<_ProviderCard> {
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

  void _chooseModel(String model) {
    _model.text = model;
    _save(widget.config.copyWith(model: model));
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final config = widget.config;
    final host = Uri.tryParse(config.baseUrl)?.host ?? config.baseUrl;
    final local = config.local;
    return Card(
      margin: const EdgeInsets.only(bottom: 10),
      elevation: 0,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(12),
        side: BorderSide(
          color: widget.active ? scheme.primary : scheme.outlineVariant,
          width: widget.active ? 1.5 : 1,
        ),
      ),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(8, 6, 8, 10),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: <Widget>[
            Row(
              children: <Widget>[
                Radio<String>(value: config.id),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: <Widget>[
                      Text(
                        config.name,
                        style: const TextStyle(fontWeight: FontWeight.w600),
                      ),
                      Row(
                        children: <Widget>[
                          Icon(
                            local
                                ? Icons.verified_user_outlined
                                : Icons.cloud_upload_outlined,
                            size: 14,
                            color: local
                                ? const Color(0xFF2E8B57)
                                : scheme.tertiary,
                          ),
                          const SizedBox(width: 4),
                          Flexible(
                            child: Text(
                              local
                                  ? 'On this computer — your notes stay here'
                                  : 'Sends the notes you ask about to $host',
                              style: TextStyle(
                                fontSize: 12,
                                color: scheme.onSurfaceVariant,
                              ),
                            ),
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
                IconButton(
                  icon: Icon(
                    _open
                        ? Icons.expand_less_rounded
                        : Icons.expand_more_rounded,
                  ),
                  tooltip: _open ? 'Hide details' : 'Show details',
                  onPressed: () => setState(() => _open = !_open),
                ),
              ],
            ),
            Padding(
              padding: const EdgeInsets.only(left: 12, right: 8),
              child: _modelPicker(scheme),
            ),
            if (config.kind == ProviderKind.ollama)
              Padding(
                padding: const EdgeInsets.fromLTRB(12, 10, 8, 0),
                child: _howItRuns(config, scheme),
              ),
            if (_open)
              Padding(
                padding: const EdgeInsets.fromLTRB(12, 10, 8, 0),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: <Widget>[
                    TextField(
                      controller: _url,
                      decoration: const InputDecoration(
                        labelText: 'Address',
                        isDense: true,
                      ),
                      onSubmitted: (url) {
                        _save(config.copyWith(baseUrl: url.trim()));
                        _loadModels();
                      },
                    ),
                    const SizedBox(height: 10),
                    Row(
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
                                  ? 'A key is kept in this computer’s keychain. Type a new one to replace it.'
                                  : 'Kept in this computer’s keychain, never in a file.',
                              isDense: true,
                            ),
                            onSubmitted: (_) => _saveKey(),
                          ),
                        ),
                        const SizedBox(width: 8),
                        FilledButton.tonal(
                          onPressed: _saveKey,
                          child: const Text('Save key'),
                        ),
                      ],
                    ),
                    const SizedBox(height: 8),
                    Align(
                      alignment: Alignment.centerRight,
                      child: TextButton.icon(
                        icon: Icon(
                          Icons.delete_outline_rounded,
                          color: scheme.error,
                        ),
                        label: Text(
                          'Remove',
                          style: TextStyle(color: scheme.error),
                        ),
                        onPressed: () async {
                          await _secrets.write(
                            providerKeyName(config.id),
                            null,
                          );
                          final settings = ref.read(aiSettingsProvider);
                          ref
                              .read(aiSettingsProvider.notifier)
                              .update(settings.withoutProvider(config.id));
                        },
                      ),
                    ),
                  ],
                ),
              ),
          ],
        ),
      ),
    );
  }

  /// How a runtime that is told it runs the model: with how much room,
  /// and whether it thinks first.
  Widget _howItRuns(ProviderConfig config, ColorScheme scheme) {
    final room = config.contextTokens ?? OllamaProvider.defaultContextTokens;
    final note = TextStyle(fontSize: 12, color: scheme.onSurfaceVariant);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: <Widget>[
        Row(
          children: <Widget>[
            const Expanded(child: Text('Room')),
            SegmentedButton<int>(
              showSelectedIcon: false,
              style: const ButtonStyle(visualDensity: VisualDensity.compact),
              segments: <ButtonSegment<int>>[
                for (final tokens in OllamaProvider.contextChoices)
                  ButtonSegment<int>(
                    value: tokens,
                    label: Text('${tokens ~/ 1024}k'),
                  ),
              ],
              selected: <int>{room},
              onSelectionChanged: (choice) =>
                  _save(config.copyWith(contextTokens: choice.single)),
            ),
          ],
        ),
        Padding(
          padding: const EdgeInsets.only(top: 4),
          child: Text(
            'Tokens for the notes, the model’s thinking and its answer '
            'together. More room fits more notes and longer thinking, and '
            'takes more memory.',
            style: note,
          ),
        ),
        const SizedBox(height: 10),
        Row(
          children: <Widget>[
            const Expanded(child: Text('Think for at most')),
            SegmentedButton<int>(
              showSelectedIcon: false,
              style: const ButtonStyle(visualDensity: VisualDensity.compact),
              segments: <ButtonSegment<int>>[
                for (final time in OllamaProvider.thinkingChoices)
                  ButtonSegment<int>(
                    value: time?.inSeconds ?? 0,
                    label: Text(
                      time == null ? 'No limit' : '${time.inMinutes} min',
                    ),
                  ),
              ],
              selected: <int>{config.thinkingTime?.inSeconds ?? 0},
              onSelectionChanged: (choice) => _save(
                config.copyWith(
                  thinkingTime: () => choice.single == 0
                      ? null
                      : Duration(seconds: choice.single),
                ),
              ),
            ),
          ],
        ),
        Padding(
          padding: const EdgeInsets.only(top: 4),
          child: Text(
            'Then the model is stopped and answers from what it has worked '
            'out — so a model going round in circles still answers.',
            style: note,
          ),
        ),
        SwitchListTile(
          contentPadding: EdgeInsets.zero,
          dense: true,
          title: const Text('Think before answering'),
          subtitle: Text(
            'Better answers, but without a graphics card it can take '
            'minutes. Some models always think; an “instruct” model never '
            'does.',
            style: note,
          ),
          value: config.think,
          onChanged: (on) => _save(config.copyWith(think: on)),
        ),
      ],
    );
  }

  Widget _modelPicker(ColorScheme scheme) => FutureBuilder<List<ModelInfo>>(
    future: _models,
    builder: (context, snapshot) {
      final models = snapshot.data ?? const <ModelInfo>[];
      final error = snapshot.error;
      return Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: <Widget>[
          Row(
            children: <Widget>[
              Expanded(
                child: models.isEmpty
                    ? TextField(
                        controller: _model,
                        decoration: const InputDecoration(
                          labelText: 'Model',
                          isDense: true,
                        ),
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
              IconButton(
                icon: snapshot.connectionState == ConnectionState.waiting
                    ? const SizedBox.square(
                        dimension: 16,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                    : const Icon(Icons.refresh_rounded),
                tooltip: 'Look for models again',
                onPressed: _loadModels,
              ),
            ],
          ),
          if (error != null)
            Padding(
              padding: const EdgeInsets.only(top: 4),
              child: Text(
                error is AiException ? error.message : '$error',
                style: TextStyle(fontSize: 12, color: scheme.error),
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
    final scheme = Theme.of(context).colorScheme;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: <Widget>[
        Text('The web', style: Theme.of(context).textTheme.titleMedium),
        const SizedBox(height: 4),
        SwitchListTile(
          contentPadding: EdgeInsets.zero,
          title: const Text('Let answers search the web'),
          subtitle: const Text(
            'What is found is cited as the web, never as your notes. '
            'It can be turned off for any question.',
          ),
          value: settings.searchWeb,
          onChanged: (on) => _update((s) => s.copyWith(searchWeb: on)),
        ),
        Text(
          'Anthropic searches the web itself. Other providers search it '
          'through one of these:',
          style: TextStyle(fontSize: 13, color: scheme.onSurfaceVariant),
        ),
        const SizedBox(height: 6),
        SegmentedButton<WebSearchBackend>(
          segments: const <ButtonSegment<WebSearchBackend>>[
            ButtonSegment(value: WebSearchBackend.none, label: Text('None')),
            ButtonSegment(
              value: WebSearchBackend.searxng,
              label: Text('SearXNG'),
            ),
            ButtonSegment(
              value: WebSearchBackend.brave,
              label: Text('Brave Search'),
            ),
          ],
          selected: <WebSearchBackend>{settings.webBackend},
          onSelectionChanged: (choice) =>
              _update((s) => s.copyWith(webBackend: choice.single)),
        ),
        const SizedBox(height: 10),
        if (settings.webBackend == WebSearchBackend.searxng)
          TextField(
            controller: _searxng,
            decoration: const InputDecoration(
              labelText: 'SearXNG address',
              helperText:
                  'A SearXNG you run yourself, with its JSON output on.',
              isDense: true,
            ),
            onSubmitted: (url) {
              _update((s) => s.copyWith(searxngUrl: url.trim()));
              ref.invalidate(webSearchProvider);
            },
          ),
        if (settings.webBackend == WebSearchBackend.brave)
          Row(
            children: <Widget>[
              Expanded(
                child: TextField(
                  controller: _brave,
                  obscureText: true,
                  decoration: const InputDecoration(
                    labelText: 'Brave Search API key',
                    helperText: 'Kept in this computer’s keychain.',
                    isDense: true,
                  ),
                ),
              ),
              const SizedBox(width: 8),
              FilledButton.tonal(
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
      ],
    );
  }
}
