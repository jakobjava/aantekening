/// How the window is laid out: the status line and the page.
library;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../editor/page_minimap.dart';
import '../look/controls.dart';
import '../shell/status_line.dart';
import 'settings_view.dart';

/// The layout page of the settings.
class LayoutSettings extends ConsumerWidget {
  const LayoutSettings({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final preview = ref.watch(minimapProvider);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: <Widget>[
        SettingsSection(
          title: 'Status line',
          description:
              'The mode the keys are in, the tabs, and what the page has in '
              'hand, on one line.',
          children: <Widget>[
            SettingRow(
              label: 'Where it lies',
              child: ChoiceRow<StatusLinePlace>(
                choices: StatusLinePlace.values,
                selected: ref.watch(statusLinePlaceProvider),
                labelOf: (place) => place.label,
                onSelected: ref.read(statusLinePlaceProvider.notifier).place,
              ),
            ),
          ],
        ),
        SettingsSection(
          title: 'Page',
          children: <Widget>[
            CheckRow(
              title: 'Page preview',
              description:
                  'The whole page drawn small beside it, in place of its '
                  'scrollbar.',
              value: preview,
              onChanged: (_) => ref.read(minimapProvider.notifier).toggle(),
            ),
          ],
        ),
      ],
    );
  }
}
