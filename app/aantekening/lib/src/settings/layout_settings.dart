/// How the window is laid out: the status line and the page.
library;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../editor/page_minimap.dart';
import '../look/controls.dart';
import '../look/floating_pane.dart';
import '../look/tones.dart';
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
        SettingsSection(
          title: 'Panes',
          description:
              'The menu, the notebooks, the AI and the rest float over the '
              'page: each is moved by its top and sized by its edges, and '
              'stays where it is left. A double-click on its top edge puts '
              'it back.',
          children: <Widget>[
            for (final pane in Pane.values)
              SettingRow(
                label: pane.label,
                child: Row(
                  children: <Widget>[
                    Expanded(
                      child: Text(
                        switch (ref.watch(panePlacementProvider(pane))) {
                          (at: null, size: null) => 'Where it goes by itself',
                          (at: _, size: null) => 'Moved',
                          (at: null, size: _) => 'Sized',
                          _ => 'Moved and sized',
                        },
                        style: TextStyle(
                          fontSize: 12.5,
                          color: context.tones.muted,
                        ),
                      ),
                    ),
                    SmallButton(
                      'Put back',
                      onPressed:
                          ref.watch(panePlacementProvider(pane)) ==
                              (at: null, size: null)
                          ? null
                          : ref
                                .read(panePlacementProvider(pane).notifier)
                                .reset,
                    ),
                  ],
                ),
              ),
            Align(
              alignment: Alignment.centerLeft,
              child: OutlinedButton(
                onPressed: () => resetPanes(ref),
                child: const Text('Put them all back'),
              ),
            ),
          ],
        ),
      ],
    );
  }
}
