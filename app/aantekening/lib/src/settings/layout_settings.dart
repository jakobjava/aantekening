/// How the window is laid out: the ribbon, the sidebar and the page.
library;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../editor/page_minimap.dart';
import '../editor/ribbon/ribbon.dart';
import '../look/controls.dart';
import '../shell/sidebar_state.dart';
import 'settings_view.dart';

/// The layout page of the settings.
class LayoutSettings extends ConsumerWidget {
  const LayoutSettings({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final collapsed = ref.watch(ribbonProvider.select((r) => r.collapsed));
    final ribbonMoved = !ref.watch(
      ribbonLayoutProvider.select((layout) => layout.isDefault),
    );
    final sidebarMoved = !ref.watch(
      sidebarLayoutProvider.select((layout) => layout.isDefault),
    );
    final preview = ref.watch(minimapProvider);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: <Widget>[
        SettingsSection(
          title: 'Ribbon',
          description:
              'Any button on the ribbon can be dragged to another place, '
              'section or tab.',
          children: <Widget>[
            CheckRow(
              title: 'Collapse the ribbon to its tabs',
              description:
                  'A tab opens it again while it is clicked. Ctrl+F1 '
                  'switches.',
              value: collapsed,
              onChanged: (_) =>
                  ref.read(ribbonProvider.notifier).toggleCollapsed(),
            ),
            const SizedBox(height: 6),
            Align(
              alignment: Alignment.centerLeft,
              child: OutlinedButton(
                onPressed: ribbonMoved
                    ? ref.read(ribbonLayoutProvider.notifier).reset
                    : null,
                child: const Text('Put every ribbon button back'),
              ),
            ),
          ],
        ),
        SettingsSection(
          title: 'Sidebar',
          description:
              'The sidebar’s buttons can be dragged up or down it, and to '
              'its foot. Each panel is widened by dragging its edge.',
          children: <Widget>[
            Align(
              alignment: Alignment.centerLeft,
              child: OutlinedButton(
                onPressed: sidebarMoved
                    ? ref.read(sidebarLayoutProvider.notifier).reset
                    : null,
                child: const Text('Put the sidebar’s buttons back'),
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
