/// Where the notes and this computer's settings are kept.
library;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../look/controls.dart';
import '../look/tones.dart';
import '../providers.dart';
import 'settings_view.dart';

/// The about page of the settings.
class AboutSettings extends ConsumerWidget {
  const AboutSettings({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final tones = context.tones;
    final workspace = ref.watch(workspaceDirectoryProvider).value;
    final note = TextStyle(fontSize: 12.5, height: 1.45, color: tones.muted);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: <Widget>[
        SettingsSection(
          title: 'Your notes',
          description:
              'Everything you write is in one folder: its database and the '
              'pictures and PDFs you add. Copy the folder, and the notes go '
              'with it; settings stay with this computer.',
          children: <Widget>[
            if (workspace != null)
              Row(
                children: <Widget>[
                  Expanded(
                    child: SelectableText(
                      workspace,
                      style: const TextStyle(fontSize: 13),
                    ),
                  ),
                  SmallButton(
                    'Copy',
                    tooltip: 'Copy where the folder is',
                    onPressed: () =>
                        Clipboard.setData(ClipboardData(text: workspace)),
                  ),
                ],
              ),
          ],
        ),
        SettingsSection(
          title: 'aantekening',
          children: <Widget>[
            Text(
              'Notes by hand and by keyboard, kept on this computer.',
              style: note,
            ),
            const SizedBox(height: 8),
            Text(
              'The interface is set in IBM Plex Sans and IBM Plex Mono, '
              '© IBM Corp., under the SIL Open Font License 1.1.',
              style: note,
            ),
          ],
        ),
      ],
    );
  }
}
