/// The status line: one thin line of glass along the top or the foot of the
/// window, as vim's is, saying what mode the keys are in, which tabs are
/// open, and what the page has in hand.
library;

import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../command_menu.dart';
import '../commands/app_command.dart';
import '../commands/shortcuts.dart';
import '../editor/page_status.dart';
import '../look/controls.dart';
import '../look/glass.dart';
import '../look/marks.dart';
import '../look/motion.dart';
import '../look/tones.dart';
import '../modes/editor_mode.dart';
import '../preferences.dart';
import '../providers.dart';
import 'library_menu.dart';
import 'tabs.dart';

/// Where the status line lies.
enum StatusLinePlace {
  top('At the top'),
  bottom('At the foot');

  const StatusLinePlace(this.label);

  final String label;
}

/// Where the status line lies, as chosen in the settings.
class StatusLinePlacement extends Notifier<StatusLinePlace> {
  static const String _key = 'statusLine.place';

  @override
  StatusLinePlace build() =>
      StatusLinePlace.values.asNameMap()[ref.preference(_key)] ??
      StatusLinePlace.top;

  void place(StatusLinePlace place) {
    state = place;
    ref.savePreference(_key, place == StatusLinePlace.top ? null : place.name);
  }
}

final statusLinePlaceProvider =
    NotifierProvider<StatusLinePlacement, StatusLinePlace>(
      StatusLinePlacement.new,
    );

/// The mode, the tabs, and what the page with the keys has in hand — the
/// pen, the zoom, a save under way — on a thin line of glass floating
/// clear of the window's edge, all along it.
class StatusLine extends StatelessWidget {
  const StatusLine({super.key});

  static const double height = 26;

  /// How far it floats from the window's edges.
  static const double margin = 6;

  /// How much of the window, from the edge it lies along, it covers.
  static const double reach = margin + height;

  static const BorderRadius _round = BorderRadius.all(
    Radius.circular(height / 2),
  );

  @override
  Widget build(BuildContext context) => const Glass(
    borderRadius: _round,
    child: SizedBox(
      height: height,
      child: Row(
        children: <Widget>[
          SizedBox(width: 12),
          _Mode(),
          SizedBox(width: 12),
          Expanded(child: _Tabs()),
          SizedBox(width: 8),
          PageStatus(),
          SizedBox(width: 14),
        ],
      ),
    ),
  );
}

/// What is round, as a pill is, on the status line.
const BorderRadius _pill = BorderRadius.all(Radius.circular(13));

/// The mode: a drop of its colour, and its name.
class _Mode extends ConsumerWidget {
  const _Mode();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final tones = context.tones;
    final mode = ref.watch(editorModeProvider);
    return Semantics(
      label: '${mode.label} mode',
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: <Widget>[
          TweenAnimationBuilder<Color?>(
            tween: ColorTween(end: mode.colourOn(tones)),
            duration: context.motion.of(Motion.quick),
            builder: (context, colour, _) => Drop.dot(size: 8, colour: colour),
          ),
          const SizedBox(width: 7),
          ExcludeSemantics(
            child: Text(
              mode.label.toUpperCase(),
              style: TextStyle(
                fontSize: 10,
                letterSpacing: 1,
                fontWeight: FontWeight.w700,
                color: tones.text,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// The open tabs, numbered as Alt and a digit shows them: the one showing
/// marked, each shown by a click, closed by a middle-click or the cross on
/// it, and moved by dragging it along the line.
class _Tabs extends ConsumerWidget {
  const _Tabs();

  /// The widest a tab's name grows; with more tabs than fit, they share the
  /// line.
  static const double maxTabWidth = 200;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final state = ref.watch(tabsProvider);
    return Row(
      children: <Widget>[
        for (var i = 0; i < state.tabs.length; i++)
          Flexible(
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: maxTabWidth),
              child: _Tab(
                key: ValueKey<int>(state.tabs[i].id),
                index: i,
                tab: state.tabs[i],
                showing: i == state.active,
                beside: i == state.beside,
              ),
            ),
          ),
      ],
    );
  }
}

class _Tab extends ConsumerStatefulWidget {
  const _Tab({
    required this.index,
    required this.tab,
    required this.showing,
    required this.beside,
    super.key,
  });

  final int index;
  final NoteTab tab;
  final bool showing;

  /// Whether it shows beside the one showing, the window split.
  final bool beside;

  @override
  ConsumerState<_Tab> createState() => _TabState();
}

class _TabState extends ConsumerState<_Tab> {
  /// How large the cross that closes it is.
  static const double _closeSize = 18;

  bool _hovering = false;

  TabsController get _tabs => ref.read(tabsProvider.notifier);

  void _showMenu() {
    final count = ref.read(tabsProvider).tabs.length;
    final bindings = ref.read(shortcutsProvider);
    String? keys(AppCommand command) => bindings.of(command).firstOrNull?.label;
    unawaited(
      showCommandMenu(context, <List<MenuCommand>>[
        <MenuCommand>[
          MenuCommand('New tab', _tabs.open, shortcut: keys(AppCommand.newTab)),
          MenuCommand(
            'Reopen closed tab',
            _tabs.canReopen ? _tabs.reopen : null,
            shortcut: keys(AppCommand.reopenTab),
          ),
        ],
        <MenuCommand>[
          MenuCommand(
            'Close tab',
            () => _tabs.close(widget.index),
            shortcut: keys(AppCommand.closeTab),
          ),
          MenuCommand(
            'Close other tabs',
            count > 1 ? () => _tabs.closeOthers(widget.index) : null,
          ),
        ],
      ]),
    );
  }

  @override
  Widget build(BuildContext context) {
    final tones = context.tones;
    final showing = widget.showing;
    final title = _TabTitle(
      number: widget.index + 1,
      tab: widget.tab,
      showing: showing,
    );
    final closeTooltip = ref
        .watch(shortcutsProvider)
        .tooltip(AppCommand.closeTab);

    final body = MouseRegion(
      onEnter: (_) => setState(() => _hovering = true),
      onExit: (_) => setState(() => _hovering = false),
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: () => _tabs.activate(widget.index),
        onTertiaryTapUp: (_) => _tabs.close(widget.index),
        onSecondaryTap: _showMenu,
        child: AnimatedContainer(
          duration: context.motion.of(Motion.quick),
          height: StatusLine.height,
          margin: const EdgeInsets.symmetric(horizontal: 1),
          decoration: BoxDecoration(
            color: _hovering ? tones.veil : tones.veil.withValues(alpha: 0),
            borderRadius: _pill,
          ),
          child: Stack(
            alignment: Alignment.centerLeft,
            children: <Widget>[
              Padding(
                padding: const EdgeInsets.only(left: 10, right: 4),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: <Widget>[
                    Flexible(child: title),
                    Opacity(
                      opacity: _hovering ? 1 : 0,
                      child: MarkButton(
                        MarkShape.close,
                        tooltip: closeTooltip,
                        size: _closeSize,
                        markSize: 9,
                        onPressed: () => _tabs.close(widget.index),
                      ),
                    ),
                  ],
                ),
              ),
              // The tab showing, a drop of the accent along the foot of its
              // name; the one beside it, split, a plain one.
              if (showing || widget.beside)
                Positioned(
                  left: 10,
                  right: 4 + _closeSize,
                  bottom: 1,
                  child: Drop.under(
                    width: double.infinity,
                    colour: showing ? null : tones.faint,
                  ),
                ),
            ],
          ),
        ),
      ),
    );

    return DragTarget<int>(
      onWillAcceptWithDetails: (details) => details.data != widget.index,
      onAcceptWithDetails: (details) => _tabs.move(details.data, widget.index),
      builder: (context, candidates, _) => Stack(
        alignment: Alignment.centerLeft,
        children: <Widget>[
          Draggable<int>(
            data: widget.index,
            axis: Axis.horizontal,
            affinity: Axis.horizontal,
            feedback: Glass(
              borderRadius: _pill,
              child: SizedBox(
                width: 160,
                height: 24,
                child: Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 8),
                  child: title,
                ),
              ),
            ),
            childWhenDragging: Opacity(opacity: 0.4, child: body),
            child: body,
          ),
          // Where a tab dragged here will go.
          if (candidates.isNotEmpty)
            Container(width: 2, height: 16, color: tones.emphasis),
        ],
      ),
    );
  }
}

/// A tab's number and name: its page's title, or where it is while it has
/// no page.
class _TabTitle extends ConsumerWidget {
  const _TabTitle({
    required this.number,
    required this.tab,
    required this.showing,
  });

  final int number;
  final NoteTab tab;
  final bool showing;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final tones = context.tones;
    final pageId = tab.pageId;
    final sectionId = tab.sectionId;
    final notebookId = tab.notebookId;
    final String title;
    if (pageId != null) {
      final page = ref.watch(pageProvider(pageId)).value;
      title = page == null ? '' : pageTitleOrPlaceholder(page.title);
    } else if (sectionId != null) {
      title = ref.watch(sectionProvider(sectionId)).value?.title ?? '';
    } else if (notebookId != null) {
      title =
          ref
              .watch(notebooksProvider)
              .value
              ?.where((notebook) => notebook.id == notebookId)
              .firstOrNull
              ?.title ??
          '';
    } else {
      title = 'New tab';
    }

    return Row(
      mainAxisSize: MainAxisSize.min,
      children: <Widget>[
        Text(
          '$number',
          style: TextStyle(
            fontSize: 11,
            fontWeight: FontWeight.w600,
            fontFeatures: const <FontFeature>[FontFeature.tabularFigures()],
            color: tones.muted,
          ),
        ),
        const SizedBox(width: 6),
        // What sets a tab on the AI apart from one on the page.
        if (tab.ai) ...<Widget>[
          Text(
            'AI',
            style: TextStyle(
              fontSize: 10.5,
              fontWeight: FontWeight.w700,
              color: EditorMode.ai.colourOn(tones),
            ),
          ),
          const SizedBox(width: 5),
        ],
        Flexible(
          child: Text(
            title,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(
              fontSize: 12,
              fontWeight: showing ? FontWeight.w600 : FontWeight.w400,
              fontStyle: pageId == null ? FontStyle.italic : FontStyle.normal,
              color: showing ? tones.text : tones.muted,
            ),
          ),
        ),
      ],
    );
  }
}
