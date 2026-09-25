/// Spelling: whether it is checked, in which languages, the dictionaries on
/// this computer, and the words added to them.
library;

import 'package:file_selector/file_selector.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:path/path.dart' as p;

import '../look/controls.dart';
import '../look/tones.dart';
import '../spelling/dictionaries.dart';
import '../spelling/spelling.dart';
import 'settings_view.dart';

/// The spelling page of the settings: the one place dictionaries are
/// downloaded, added and removed.
class SpellingSettingsPage extends ConsumerWidget {
  const SpellingSettingsPage({super.key});

  static const XTypeGroup _hunspell = XTypeGroup(
    label: 'Hunspell dictionaries',
    extensions: <String>['aff', 'dic'],
  );

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final tones = context.tones;
    final settings = ref.watch(spellingProvider);
    final spelling = ref.read(spellingProvider.notifier);
    final reading = ref.watch(installedDictionariesProvider);
    final installed = reading.value ?? const <InstalledDictionary>[];
    final downloading = ref.watch(dictionariesProvider);
    final dictionaries = ref.read(dictionariesProvider.notifier);
    final installedCodes = <String>{
      for (final dictionary in installed) dictionary.code,
    };
    final available = <CatalogDictionary>[
      for (final dictionary in DictionaryCatalog.languages)
        if (!installedCodes.contains(dictionary.code)) dictionary,
    ];

    /// Carries out [action], saying what went wrong if it fails.
    Future<void> attempt(Future<void> Function() action) async {
      final messenger = ScaffoldMessenger.maybeOf(context);
      try {
        await action();
      } on Object catch (error) {
        messenger?.showSnackBar(SnackBar(content: Text('$error')));
      }
    }

    Future<void> addFromFiles() => attempt(() async {
      final files = await openFiles(
        acceptedTypeGroups: const <XTypeGroup>[_hunspell],
      );
      if (files.isEmpty) return;
      // Either file will do: the other is beside it, named the same.
      final chosen = p.withoutExtension(files.first.path);
      await dictionaries.import('$chosen.aff', '$chosen.dic');
    });

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: <Widget>[
        SettingsSection(
          title: 'Checking',
          children: <Widget>[
            CheckRow(
              title: 'Underline words spelled wrongly',
              description:
                  'A word is right if any language ticked below has it, or '
                  'it is one of your words.',
              value: settings.enabled,
              onChanged: spelling.setEnabled,
            ),
          ],
        ),
        SettingsSection(
          title: 'Languages',
          description:
              'The dictionaries on this computer. Tick those to '
              'check against.',
          children: <Widget>[
            if (installed.isEmpty)
              Padding(
                padding: const EdgeInsets.symmetric(vertical: 6),
                child: Text(
                  reading.isLoading
                      ? 'Looking for dictionaries…'
                      : 'No dictionaries yet. Download one below, or add '
                            'one from files.',
                  style: TextStyle(fontSize: 12.5, color: tones.muted),
                ),
              ),
            for (final dictionary in installed)
              Row(
                children: <Widget>[
                  Expanded(
                    child: CheckRow(
                      title: dictionary.name,
                      value: settings.languages.contains(dictionary.code),
                      onChanged: (used) =>
                          spelling.useLanguage(dictionary.code, used: used),
                    ),
                  ),
                  SmallButton(
                    'Remove',
                    tooltip: 'Delete this dictionary from this computer',
                    onPressed: () =>
                        attempt(() => dictionaries.remove(dictionary.code)),
                  ),
                ],
              ),
          ],
        ),
        SettingsSection(
          title: 'More languages',
          description:
              'Hunspell dictionaries, each checked against what was '
              'expected before it is installed. Or add one of your own: the '
              '.aff and .dic files LibreOffice uses.',
          children: <Widget>[
            for (final dictionary in available)
              Padding(
                padding: const EdgeInsets.symmetric(vertical: 3),
                child: Row(
                  children: <Widget>[
                    Expanded(
                      child: Text(
                        dictionary.name,
                        style: const TextStyle(fontSize: 13),
                      ),
                    ),
                    if (downloading.contains(dictionary.code))
                      const Padding(
                        padding: EdgeInsets.symmetric(horizontal: 12),
                        child: Busy(width: 40),
                      )
                    else
                      SmallButton(
                        'Download',
                        onPressed: () =>
                            attempt(() => dictionaries.download(dictionary)),
                      ),
                  ],
                ),
              ),
            const SizedBox(height: 8),
            Align(
              alignment: Alignment.centerLeft,
              child: OutlinedButton(
                onPressed: addFromFiles,
                child: const Text('Add a dictionary from files…'),
              ),
            ),
          ],
        ),
        SettingsSection(
          title: 'Your words',
          description: 'Words added from a misspelling’s menu, always right.',
          children: <Widget>[
            if (settings.personalWords.isEmpty)
              Text(
                'None yet.',
                style: TextStyle(fontSize: 12.5, color: tones.muted),
              ),
            for (final word in settings.personalWords)
              Row(
                children: <Widget>[
                  Expanded(
                    child: Text(word, style: const TextStyle(fontSize: 13)),
                  ),
                  SmallButton(
                    'Remove',
                    tooltip: 'Check this word again',
                    onPressed: () => spelling.removeWord(word),
                  ),
                ],
              ),
          ],
        ),
      ],
    );
  }
}
