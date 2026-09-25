/// The row of tabs beneath the ribbon.
library;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../command_menu.dart';
import '../commands/app_command.dart';
import '../commands/shortcuts.dart';
import '../look/controls.dart';
import '../look/marks.dart';
import '../look/tones.dart';
import '../providers.dart';
import 'library_menu.dart';
import 'tabs.dart';

/// The tabs, as a browser shows them: the tab showing marked by a line
/// along its top and joined to the page beneath it, and a button after the
/// last to open another. A tab is shown by a click, closed by its cross or
/// a middle-click, and moved by dragging it along the row.
class TabStrip extends ConsumerWidget {
  const TabStrip({super.key});

  static const double height = 32;

  /// The widest a tab grows; with more tabs than fit, they share the row.
  static const double maxTabWidth = 220;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final state = ref.watch(tabsProvider);
    final bindings = ref.watch(shortcutsProvider);
    final tones = context.tones;

    return Container(
      height: height,
      decoration: BoxDecoration(
        color: tones.pane,
        border: Border(bottom: BorderSide(color: tones.line)),
      ),
      child: Row(
        children: <Widget>[
          Flexible(
            child: Row(
              mainAxisSize: MainAxisSize.min,
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
                      ),
                    ),
                  ),
              ],
            ),
          ),
          const SizedBox(width: 4),
          MarkButton(
            MarkShape.add,
            tooltip: bindings.tooltip(AppCommand.newTab),
            onPressed: ref.read(tabsProvider.notifier).open,
          ),
        ],
      ),
    );
  }
}

class _Tab extends ConsumerStatefulWidget {
  const _Tab({
    required this.index,
    required this.tab,
    required this.showing,
    super.key,
  });

  final int index;
  final NoteTab tab;
  final bool showing;

  @override
  ConsumerState<_Tab> createState() => _TabState();
}

class _TabState extends ConsumerState<_Tab> {
  bool _hovering = false;

  TabsController get _tabs => ref.read(tabsProvider.notifier);

  void _showMenu(Offset position) {
    final count = ref.read(tabsProvider).tabs.length;
    final bindings = ref.read(shortcutsProvider);
    String? keys(AppCommand command) => bindings.of(command).firstOrNull?.label;
    showCommandMenu(context, position, <List<MenuCommand>>[
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
    ]);
  }

  @override
  Widget build(BuildContext context) {
    final tones = context.tones;
    final showing = widget.showing;
    final title = _TabTitle(tab: widget.tab, showing: showing);
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
        onSecondaryTapUp: (details) => _showMenu(details.globalPosition),
        child: Container(
          padding: const EdgeInsets.only(left: 12, right: 4),
          decoration: BoxDecoration(
            color: showing
                ? tones.base
                : _hovering
                ? tones.hover
                : null,
            border: Border(
              top: BorderSide(
                color: showing ? tones.emphasis : Colors.transparent,
                width: 2,
              ),
              right: BorderSide(color: tones.line),
            ),
          ),
          child: Row(
            children: <Widget>[
              Expanded(child: title),
              Opacity(
                opacity: showing || _hovering ? 1 : 0,
                child: MarkButton(
                  MarkShape.close,
                  tooltip: closeTooltip,
                  size: 20,
                  markSize: 10,
                  onPressed: () => _tabs.close(widget.index),
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
        children: <Widget>[
          Draggable<int>(
            data: widget.index,
            axis: Axis.horizontal,
            affinity: Axis.horizontal,
            feedback: Material(
              color: tones.base,
              shape: RoundedRectangleBorder(
                side: BorderSide(color: tones.emphasis),
              ),
              child: SizedBox(
                width: 160,
                height: TabStrip.height - 2,
                child: Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 12),
                  child: title,
                ),
              ),
            ),
            childWhenDragging: Opacity(opacity: 0.4, child: body),
            child: body,
          ),
          // Where a tab dragged here will go.
          if (candidates.isNotEmpty)
            Positioned(
              left: 0,
              top: 4,
              bottom: 4,
              child: Container(width: 2, color: tones.emphasis),
            ),
        ],
      ),
    );
  }
}

/// A tab's name: its page's title, or where its sidebar is while it has no
/// page.
class _TabTitle extends ConsumerWidget {
  const _TabTitle({required this.tab, required this.showing});

  final NoteTab tab;
  final bool showing;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
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
      children: <Widget>[
        // What sets a tab on the AI apart from one on the page.
        if (tab.ai) ...<Widget>[
          SmallCaps(
            'AI',
            color: showing ? context.tones.emphasis : context.tones.muted,
          ),
          const SizedBox(width: 6),
        ],
        Expanded(
          child: Text(
            title,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(
              fontSize: 12.5,
              fontWeight: showing ? FontWeight.w600 : FontWeight.w400,
              fontStyle: pageId == null ? FontStyle.italic : FontStyle.normal,
              color: showing ? context.tones.text : context.tones.muted,
            ),
          ),
        ),
      ],
    );
  }
}
