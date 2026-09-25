/// The settings: how the app looks, how it is laid out, its shortcuts, the
/// languages spelling is checked in and the AI's models, each on a page of
/// its own.
library;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../look/controls.dart';
import '../look/marks.dart';
import '../look/tones.dart';
import 'about_settings.dart';
import 'ai_settings.dart';
import 'appearance_settings.dart';
import 'keyboard_settings.dart';
import 'layout_settings.dart';
import 'spelling_settings.dart';

/// A page of the settings.
enum SettingsPage {
  appearance('Appearance', 'Light and dark, colours, typeface and size'),
  layout('Layout', 'The ribbon, the sidebar and the page'),
  keyboard('Keyboard', 'Every shortcut, and changing them'),
  spelling('Spelling', 'Languages, dictionaries and your own words'),
  ai('AI models', 'Which models questions go to, and the web'),
  about('About', 'Where your notes are kept');

  const SettingsPage(this.label, this.description);

  final String label;
  final String description;
}

/// Opens the settings at [page], over the window.
Future<void> showSettings(
  BuildContext context, {
  SettingsPage page = SettingsPage.appearance,
}) => showGeneralDialog<void>(
  context: context,
  barrierDismissible: true,
  barrierLabel: 'Close the settings',
  barrierColor: context.tones.text.withValues(alpha: 0.12),
  transitionDuration: const Duration(milliseconds: 110),
  transitionBuilder: (context, animation, _, child) =>
      FadeTransition(opacity: animation, child: child),
  pageBuilder: (context, _, _) => SettingsView(initial: page),
);

/// The settings: their pages down the left, the page open beside them.
class SettingsView extends StatefulWidget {
  const SettingsView({this.initial = SettingsPage.appearance, super.key});

  final SettingsPage initial;

  @override
  State<SettingsView> createState() => _SettingsViewState();
}

class _SettingsViewState extends State<SettingsView> {
  late SettingsPage _page = widget.initial;

  void _step(int by) {
    const pages = SettingsPage.values;
    setState(
      () => _page = pages[(_page.index + by).clamp(0, pages.length - 1)],
    );
  }

  @override
  Widget build(BuildContext context) {
    final tones = context.tones;
    return CallbackShortcuts(
      bindings: <ShortcutActivator, VoidCallback>{
        const SingleActivator(LogicalKeyboardKey.escape): () =>
            Navigator.of(context).pop(),
        const SingleActivator(LogicalKeyboardKey.pageDown, control: true): () =>
            _step(1),
        const SingleActivator(LogicalKeyboardKey.pageUp, control: true): () =>
            _step(-1),
      },
      child: FocusScope(
        autofocus: true,
        child: Padding(
          padding: const EdgeInsets.all(28),
          child: Center(
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 980, maxHeight: 780),
              child: Material(
                color: tones.base,
                shape: RoundedRectangleBorder(
                  side: BorderSide(color: tones.strongLine),
                ),
                clipBehavior: Clip.hardEdge,
                child: LayoutBuilder(
                  builder: (context, constraints) {
                    final narrow = constraints.maxWidth < 640;
                    return Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: <Widget>[
                        _TitleBar(page: _page),
                        const Divider(),
                        Expanded(
                          child: narrow
                              ? Column(
                                  crossAxisAlignment:
                                      CrossAxisAlignment.stretch,
                                  children: <Widget>[
                                    _PageTabs(
                                      page: _page,
                                      onPicked: (page) =>
                                          setState(() => _page = page),
                                    ),
                                    const Divider(),
                                    Expanded(child: _PageBody(page: _page)),
                                  ],
                                )
                              : Row(
                                  crossAxisAlignment:
                                      CrossAxisAlignment.stretch,
                                  children: <Widget>[
                                    SizedBox(
                                      width: 216,
                                      child: ColoredBox(
                                        color: tones.pane,
                                        child: _PageList(
                                          page: _page,
                                          onPicked: (page) =>
                                              setState(() => _page = page),
                                        ),
                                      ),
                                    ),
                                    const VerticalDivider(width: 1),
                                    Expanded(child: _PageBody(page: _page)),
                                  ],
                                ),
                        ),
                      ],
                    );
                  },
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _TitleBar extends StatelessWidget {
  const _TitleBar({required this.page});

  final SettingsPage page;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.fromLTRB(20, 10, 10, 10),
    child: Row(
      children: <Widget>[
        Text('Settings', style: Theme.of(context).textTheme.titleMedium),
        const Spacer(),
        const KeyHint('Ctrl+Page Up/Down  pages    Esc  close'),
        const SizedBox(width: 12),
        MarkButton(
          MarkShape.close,
          tooltip: 'Close  (Esc)',
          onPressed: () => Navigator.of(context).pop(),
        ),
      ],
    ),
  );
}

class _PageList extends StatelessWidget {
  const _PageList({required this.page, required this.onPicked});

  final SettingsPage page;
  final ValueChanged<SettingsPage> onPicked;

  @override
  Widget build(BuildContext context) => ListView(
    padding: const EdgeInsets.symmetric(vertical: 8),
    children: <Widget>[
      for (final each in SettingsPage.values)
        RowTile(
          selected: each == page,
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 7),
          title: Text(each.label),
          onTap: () => onPicked(each),
        ),
    ],
  );
}

/// The pages as a row, where the window is too narrow for a list beside.
class _PageTabs extends StatelessWidget {
  const _PageTabs({required this.page, required this.onPicked});

  final SettingsPage page;
  final ValueChanged<SettingsPage> onPicked;

  @override
  Widget build(BuildContext context) => SingleChildScrollView(
    scrollDirection: Axis.horizontal,
    padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
    child: ChoiceRow<SettingsPage>(
      choices: SettingsPage.values,
      selected: page,
      labelOf: (page) => page.label,
      onSelected: onPicked,
    ),
  );
}

class _PageBody extends StatelessWidget {
  const _PageBody({required this.page});

  final SettingsPage page;

  @override
  Widget build(BuildContext context) => ListView(
    key: PageStorageKey<SettingsPage>(page),
    padding: const EdgeInsets.fromLTRB(28, 22, 28, 32),
    children: <Widget>[
      Text(page.label, style: Theme.of(context).textTheme.headlineSmall),
      const SizedBox(height: 4),
      Text(
        page.description,
        style: TextStyle(fontSize: 13, color: context.tones.muted),
      ),
      const SizedBox(height: 18),
      switch (page) {
        SettingsPage.appearance => const AppearanceSettings(),
        SettingsPage.layout => const LayoutSettings(),
        SettingsPage.keyboard => const KeyboardSettings(),
        SettingsPage.spelling => const SpellingSettingsPage(),
        SettingsPage.ai => const AiSettingsPage(),
        SettingsPage.about => const AboutSettings(),
      },
    ],
  );
}

/// A part of a settings page, under a heading.
class SettingsSection extends StatelessWidget {
  const SettingsSection({
    required this.title,
    required this.children,
    this.description,
    this.action,
    super.key,
  });

  final String title;
  final String? description;

  /// Beside the heading: resetting what is below it, say.
  final Widget? action;
  final List<Widget> children;

  @override
  Widget build(BuildContext context) {
    final tones = context.tones;
    return Padding(
      padding: const EdgeInsets.only(bottom: 26),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: <Widget>[
          Row(
            children: <Widget>[
              Expanded(child: SmallCaps(title)),
              ?action,
            ],
          ),
          const SizedBox(height: 4),
          Divider(color: tones.line),
          if (description case final description?)
            Padding(
              padding: const EdgeInsets.only(top: 8),
              child: Text(
                description,
                style: TextStyle(
                  fontSize: 12.5,
                  height: 1.45,
                  color: tones.muted,
                ),
              ),
            ),
          const SizedBox(height: 6),
          ...children,
        ],
      ),
    );
  }
}

/// One setting: what it is on the left, the control on the right, and what
/// it does beneath, if that needs saying.
class SettingRow extends StatelessWidget {
  const SettingRow({
    required this.label,
    required this.child,
    this.description,
    super.key,
  });

  final String label;
  final String? description;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    final tones = context.tones;
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 7),
      child: Wrap(
        crossAxisAlignment: WrapCrossAlignment.center,
        spacing: 16,
        runSpacing: 6,
        children: <Widget>[
          SizedBox(
            width: 180,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: <Widget>[
                Text(label, style: const TextStyle(fontSize: 13)),
                if (description case final description?)
                  Padding(
                    padding: const EdgeInsets.only(top: 2),
                    child: Text(
                      description,
                      style: TextStyle(fontSize: 11.5, color: tones.muted),
                    ),
                  ),
              ],
            ),
          ),
          child,
        ],
      ),
    );
  }
}
