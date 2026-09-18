/// Configuration for the optional local-AI features.
library;

import 'package:aantekening_ai/aantekening_ai.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../providers.dart';
import '../shell/library_pane.dart';
import '../theme.dart';

/// The local AI's settings, in the sidebar: whether it is on, where the model
/// runtime is, and which of its models to use.
class AiPanel extends ConsumerStatefulWidget {
  const AiPanel({super.key});

  @override
  ConsumerState<AiPanel> createState() => _AiPanelState();
}

class _AiPanelState extends ConsumerState<AiPanel> {
  late final TextEditingController _baseUrl = TextEditingController(
    text: ref.read(aiSettingsProvider).baseUrl,
  );

  @override
  void dispose() {
    _baseUrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final settings = ref.watch(aiSettingsProvider);
    final available = ref.watch(modelAvailabilityProvider);
    final models = ref.watch(availableModelsProvider);

    return Material(
      color: AppTheme.paneColor(scheme),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: <Widget>[
          PaneHeader(
            title: 'Local AI',
            actionIcon: Icons.refresh_rounded,
            actionTooltip: 'Check the runtime again',
            onAction: () => ref.invalidate(modelAvailabilityProvider),
          ),
          Expanded(
            child: ListView(
              padding: const EdgeInsets.fromLTRB(14, 0, 14, 14),
              children: <Widget>[
                Text(
                  'Summaries, semantic search and question answering run '
                  'against a model on this machine. Nothing is sent anywhere '
                  'else, and the app is fully usable with this switched off.',
                  style: TextStyle(
                    fontSize: 12,
                    color: scheme.onSurfaceVariant,
                  ),
                ),
                const SizedBox(height: 8),
                SwitchListTile(
                  contentPadding: EdgeInsets.zero,
                  title: const Text('Enable local AI features'),
                  value: settings.enabled,
                  onChanged: (value) =>
                      _update(settings.copyWith(enabled: value)),
                ),
                const Divider(height: 20),
                TextField(
                  controller: _baseUrl,
                  enabled: settings.enabled,
                  decoration: const InputDecoration(
                    labelText: 'Runtime address',
                    helperText: 'Ollama listens on 127.0.0.1:11434 by default',
                  ),
                  onSubmitted: (value) =>
                      _update(settings.copyWith(baseUrl: value.trim())),
                ),
                const SizedBox(height: 12),
                _StatusRow(state: available),
                const SizedBox(height: 12),
                models.when(
                  loading: () => const LinearProgressIndicator(minHeight: 2),
                  error: (error, _) => Text(
                    '$error',
                    style: TextStyle(fontSize: 12, color: scheme.error),
                  ),
                  data: (installed) => installed.isEmpty
                      ? Text(
                          'No models found. Install one with, for example, '
                          '"ollama pull llama3.2" and '
                          '"ollama pull nomic-embed-text".',
                          style: TextStyle(
                            fontSize: 12,
                            color: scheme.onSurfaceVariant,
                          ),
                        )
                      : Column(
                          children: <Widget>[
                            _ModelPicker(
                              label: 'Chat model',
                              helper: 'Used for summaries and answers',
                              models: installed,
                              selected: settings.chatModel,
                              onChanged: (value) =>
                                  _update(settings.copyWith(chatModel: value)),
                            ),
                            const SizedBox(height: 10),
                            _ModelPicker(
                              label: 'Embedding model',
                              helper:
                                  'Used for semantic search; changing it '
                                  'rebuilds the index',
                              models: installed,
                              selected: settings.embeddingModel,
                              onChanged: (value) => _update(
                                settings.copyWith(embeddingModel: value),
                              ),
                            ),
                          ],
                        ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  void _update(AiSettings settings) {
    ref.read(aiSettingsProvider.notifier).update(settings);
    ref.invalidate(modelAvailabilityProvider);
  }
}

class _StatusRow extends StatelessWidget {
  const _StatusRow({required this.state});

  final AsyncValue<bool> state;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final (IconData icon, String label, Color color) = switch (state) {
      AsyncData<bool>(value: true) => (
        Icons.check_circle_outline_rounded,
        'Runtime reachable',
        scheme.primary,
      ),
      AsyncData<bool>() => (
        Icons.cloud_off_rounded,
        'No local runtime found',
        scheme.onSurfaceVariant,
      ),
      AsyncError<bool>() => (
        Icons.error_outline_rounded,
        'Could not check the runtime',
        scheme.error,
      ),
      _ => (
        Icons.hourglass_empty_rounded,
        'Checking…',
        scheme.onSurfaceVariant,
      ),
    };

    return Row(
      children: <Widget>[
        Icon(icon, size: 16, color: color),
        const SizedBox(width: 8),
        Text(label, style: TextStyle(fontSize: 12, color: color)),
      ],
    );
  }
}

class _ModelPicker extends StatelessWidget {
  const _ModelPicker({
    required this.label,
    required this.helper,
    required this.models,
    required this.selected,
    required this.onChanged,
  });

  final String label;
  final String helper;
  final List<ModelInfo> models;
  final String selected;
  final ValueChanged<String> onChanged;

  @override
  Widget build(BuildContext context) {
    final names = <String>[for (final model in models) model.name];
    return DropdownButtonFormField<String>(
      initialValue: names.contains(selected) ? selected : null,
      isExpanded: true,
      decoration: InputDecoration(labelText: label, helperText: helper),
      items: <DropdownMenuItem<String>>[
        for (final model in models)
          DropdownMenuItem<String>(
            value: model.name,
            child: Text(
              model.parameterSize == null
                  ? model.name
                  : '${model.name}  ·  ${model.parameterSize}',
              overflow: TextOverflow.ellipsis,
            ),
          ),
      ],
      onChanged: (value) {
        if (value != null) onChanged(value);
      },
    );
  }
}
