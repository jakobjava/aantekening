/// What the app is, and whose work it is set in.
library;

import 'package:flutter/material.dart';

import '../look/tones.dart';
import 'settings_view.dart';

/// The about page of the settings.
class AboutSettings extends StatelessWidget {
  const AboutSettings({super.key});

  @override
  Widget build(BuildContext context) {
    final tones = context.tones;
    final note = TextStyle(fontSize: 12.5, height: 1.45, color: tones.muted);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: <Widget>[
        SettingsSection(
          title: 'aantekening',
          children: <Widget>[
            Text(
              'Notes by hand and by keyboard, kept in a folder of your '
              'choosing.',
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
