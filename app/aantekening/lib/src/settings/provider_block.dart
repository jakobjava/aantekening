/// What a provider set up in the settings is made of, alike for the models
/// that answer and the voices that speak: a menu to add one, its name and
/// where what it is given goes, its key in the keychain, a way to remove
/// it, and the models it lists to choose from.
library;

import 'dart:async';

import 'package:aantekening_ai/aantekening_ai.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../ai/ai_state.dart';
import '../look/controls.dart';
import '../look/marks.dart';
import '../look/tones.dart';

/// A button opening a menu of the [presets] to add a provider of: those
/// run on this computer first, as [ownServer] tells, then those online.
class AddProviderMenu<T> extends StatelessWidget {
  const AddProviderMenu({
    required this.label,
    required this.presets,
    required this.ownServer,
    required this.labelOf,
    required this.onAdd,
    super.key,
  });

  final String label;
  final List<T> presets;
  final bool Function(T preset) ownServer;
  final String Function(T preset) labelOf;
  final ValueChanged<T> onAdd;

  @override
  Widget build(BuildContext context) {
    Iterable<Widget> items(bool own) => <Widget>[
      for (final preset in presets)
        if (ownServer(preset) == own)
          MenuItemButton(
            onPressed: () => onAdd(preset),
            child: Text(labelOf(preset)),
          ),
    ];
    return Align(
      alignment: Alignment.centerLeft,
      child: MenuAnchor(
        menuChildren: <Widget>[
          const _MenuHeading('On this computer'),
          ...items(true),
          const _MenuHeading('Online'),
          ...items(false),
        ],
        builder: (context, menu, _) => OutlinedButton(
          onPressed: () => menu.isOpen ? menu.close() : menu.open(),
          child: Text(label),
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
    child: SmallCaps(label),
  );
}

/// The host of [baseUrl], as a provider's block names where it sends what
/// it is given.
String hostOf(String baseUrl) => Uri.tryParse(baseUrl)?.host ?? baseUrl;

/// A provider's [name], and [where] what it is given goes, with [actions]
/// beside them.
class ProviderHeading extends StatelessWidget {
  const ProviderHeading({
    required this.name,
    required this.where,
    this.actions = const <Widget>[],
    super.key,
  });

  final String name;
  final String where;
  final List<Widget> actions;

  @override
  Widget build(BuildContext context) => Row(
    children: <Widget>[
      Expanded(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: <Widget>[
            Text(
              name,
              style: const TextStyle(
                fontSize: 13.5,
                fontWeight: FontWeight.w600,
              ),
            ),
            Text(
              where,
              style: TextStyle(
                fontSize: 12,
                height: 1.4,
                color: context.tones.muted,
              ),
            ),
          ],
        ),
      ),
      ...actions,
    ],
  );
}

/// A provider's API key, typed in and kept in this computer's keychain as
/// [name], never in a file: saying whether one is kept, and why not where
/// the keychain would not keep it. Once one is saved, [onSaved].
class ProviderKeyField extends ConsumerStatefulWidget {
  const ProviderKeyField({
    required this.name,
    required this.needsKey,
    this.onSaved,
    super.key,
  });

  final String name;

  /// Whether the provider is asked nothing without a key.
  final bool needsKey;
  final VoidCallback? onSaved;

  @override
  ConsumerState<ProviderKeyField> createState() => _ProviderKeyFieldState();
}

class _ProviderKeyFieldState extends ConsumerState<ProviderKeyField> {
  final TextEditingController _key = TextEditingController();
  bool _hasKey = false;

  /// Why the keychain would not read or keep the key, if it would not.
  String? _trouble;

  AiSecrets get _secrets => ref.read(aiSecretsProvider);

  @override
  void initState() {
    super.initState();
    unawaited(_read());
  }

  @override
  void dispose() {
    _key.dispose();
    super.dispose();
  }

  Future<void> _read() async {
    try {
      final key = await _secrets.read(widget.name);
      if (!mounted) return;
      setState(() {
        _hasKey = key != null && key.isNotEmpty;
        _trouble = null;
      });
    } on Object catch (error) {
      if (mounted) setState(() => _trouble = keychainTrouble(error));
    }
  }

  Future<void> _save() async {
    final key = _key.text.trim();
    try {
      await _secrets.write(widget.name, key.isEmpty ? null : key);
    } on Object catch (error) {
      if (mounted) setState(() => _trouble = keychainTrouble(error));
      return;
    }
    if (!mounted) return;
    _key.clear();
    widget.onSaved?.call();
    await _read();
  }

  @override
  Widget build(BuildContext context) => Row(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: <Widget>[
      Expanded(
        child: TextField(
          controller: _key,
          obscureText: true,
          decoration: InputDecoration(
            labelText: widget.needsKey ? 'API key' : 'API key, if it needs one',
            errorText: _trouble,
            errorMaxLines: 4,
            helperText: _hasKey
                ? 'A key is kept in this computer’s keychain. Type a new one '
                      'to replace it.'
                : 'Kept in this computer’s keychain, never in a file.',
          ),
          onSubmitted: (_) => _save(),
        ),
      ),
      const SizedBox(width: 8),
      OutlinedButton(onPressed: _save, child: const Text('Save key')),
    ],
  );
}

/// A button, [label], that removes a provider: its key kept as [keyName]
/// forgotten, then [onRemoved].
class RemoveProviderButton extends ConsumerWidget {
  const RemoveProviderButton({
    required this.label,
    required this.keyName,
    required this.onRemoved,
    super.key,
  });

  final String label;
  final String keyName;
  final VoidCallback onRemoved;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    Future<void> remove() async {
      try {
        await ref.read(aiSecretsProvider).write(keyName, null);
      } on Object {
        // A keychain not reached keeps no key to forget.
      }
      if (context.mounted) onRemoved();
    }

    return Align(
      alignment: Alignment.centerRight,
      child: SmallButton(label, onPressed: () => unawaited(remove())),
    );
  }
}

/// The models the provider of the settings with id [providerId] lists,
/// asked with its key: once while anything shows them, again as its
/// address changes, and when made to — its key saved, or asked again.
final providerModelsProvider = FutureProvider.autoDispose
    .family<List<ModelInfo>, String>(
      (ref, providerId) async {
        bool same(ProviderConfig config) => config.id == providerId;
        ref.watch(
          aiSettingsProvider.select(
            (s) => s.providers.where(same).firstOrNull?.baseUrl,
          ),
        );
        final config = ref
            .read(aiSettingsProvider)
            .providers
            .where(same)
            .firstOrNull;
        if (config == null) return const <ModelInfo>[];
        final key = await ref
            .read(aiSecretsProvider)
            .read(providerKeyName(config.id));
        final provider = ref.read(chatMakerProvider)(config, key);
        try {
          return await provider.listModels();
        } finally {
          provider.close();
        }
      },
      // A provider that cannot be reached is said so, not asked again
      // unseen.
      retry: (_, _) => null,
    );

/// A model to choose of the [models] a provider lists, [selected] at
/// first, each as [labelOf] names it with [trailingOf] beside — or, where
/// it lists none, [typed]: a field to type the model's id in.
class ModelMenu extends StatelessWidget {
  const ModelMenu({
    required this.models,
    required this.selected,
    required this.onSelected,
    required this.typed,
    this.labelOf,
    this.trailingOf,
    super.key,
  });

  final List<ModelInfo> models;
  final String? selected;
  final ValueChanged<String> onSelected;
  final Widget typed;
  final String Function(ModelInfo model)? labelOf;
  final Widget? Function(ModelInfo model)? trailingOf;

  @override
  Widget build(BuildContext context) {
    if (models.isEmpty) return typed;
    return DropdownMenu<String>(
      key: ValueKey<int>(models.length),
      initialSelection: selected,
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
            label: labelOf?.call(model) ?? model.name,
            trailingIcon: trailingOf?.call(model),
          ),
      ],
      onSelected: (model) {
        if (model != null) onSelected(model);
      },
    );
  }
}
