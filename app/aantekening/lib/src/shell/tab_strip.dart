/// The row of tabs beneath the ribbon.
library;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../command_menu.dart';
import '../providers.dart';
import '../theme.dart';
import 'library_menu.dart';
import 'tabs.dart';

/// The tabs, as a browser shows them: the tab showing drawn as part of the
/// page beneath it, and a button after the last to open another. A tab is
/// shown by a click, closed by its cross or a middle-click, and moved by
/// dragging it along the row.
class TabStrip extends ConsumerWidget {
  const TabStrip({super.key});

  static const double height = 34;

  /// The widest a tab grows; with more tabs than fit, they share the row.
  static const double maxTabWidth = 220;

  /// The keys that open, close and step through tabs: Ctrl+T, Ctrl+W, and
  /// Ctrl+Tab or Ctrl+Page Down on and back with Shift or Page Up.
  static Map<ShortcutActivator, VoidCallback> shortcuts(
    TabsController tabs,
  ) => <ShortcutActivator, VoidCallback>{
    const SingleActivator(LogicalKeyboardKey.keyT, control: true): tabs.open,
    const SingleActivator(LogicalKeyboardKey.keyW, control: true):
        tabs.closeShowing,
    const SingleActivator(LogicalKeyboardKey.tab, control: true): () =>
        tabs.step(1),
    const SingleActivator(
      LogicalKeyboardKey.tab,
      control: true,
      shift: true,
    ): () =>
        tabs.step(-1),
    const SingleActivator(LogicalKeyboardKey.pageDown, control: true): () =>
        tabs.step(1),
    const SingleActivator(LogicalKeyboardKey.pageUp, control: true): () =>
        tabs.step(-1),
  };

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final state = ref.watch(tabsProvider);
    final scheme = Theme.of(context).colorScheme;
    final tabs = ref.read(tabsProvider.notifier);

    return Container(
      height: height,
      padding: const EdgeInsets.only(left: 6, top: 4),
      decoration: BoxDecoration(
        color: AppTheme.paneColor(scheme),
        border: Border(bottom: BorderSide(color: scheme.outlineVariant)),
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
          IconButton(
            icon: const Icon(Icons.add_rounded, size: 18),
            tooltip: 'New tab (Ctrl+T)',
            visualDensity: VisualDensity.compact,
            onPressed: tabs.open,
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
    showCommandMenu(context, position, <List<MenuCommand>>[
      <MenuCommand>[MenuCommand('New Tab', Icons.add_rounded, _tabs.open)],
      <MenuCommand>[
        MenuCommand(
          'Close Tab',
          Icons.close_rounded,
          () => _tabs.close(widget.index),
        ),
        MenuCommand(
          'Close Other Tabs',
          null,
          count > 1 ? () => _tabs.closeOthers(widget.index) : null,
        ),
      ],
    ]);
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final title = _TabTitle(tab: widget.tab, showing: widget.showing);

    final body = MouseRegion(
      onEnter: (_) => setState(() => _hovering = true),
      onExit: (_) => setState(() => _hovering = false),
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: () => _tabs.activate(widget.index),
        onTertiaryTapUp: (_) => _tabs.close(widget.index),
        onSecondaryTapUp: (details) => _showMenu(details.globalPosition),
        child: Container(
          padding: const EdgeInsets.only(left: 10, right: 4),
          decoration: BoxDecoration(
            color: widget.showing
                ? scheme.surface
                : _hovering
                ? scheme.onSurface.withValues(alpha: 0.06)
                : null,
            borderRadius: const BorderRadius.vertical(top: Radius.circular(8)),
            border: widget.showing
                ? Border(
                    top: BorderSide(color: scheme.outlineVariant),
                    left: BorderSide(color: scheme.outlineVariant),
                    right: BorderSide(color: scheme.outlineVariant),
                  )
                : null,
          ),
          child: Row(
            children: <Widget>[
              Expanded(child: title),
              Opacity(
                opacity: widget.showing || _hovering ? 1 : 0,
                child: IconButton(
                  icon: const Icon(Icons.close_rounded, size: 14),
                  tooltip: 'Close tab (Ctrl+W)',
                  iconSize: 14,
                  visualDensity: VisualDensity.compact,
                  constraints: const BoxConstraints.tightFor(
                    width: 22,
                    height: 22,
                  ),
                  padding: EdgeInsets.zero,
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
              elevation: 4,
              borderRadius: BorderRadius.circular(8),
              child: SizedBox(
                width: 160,
                height: TabStrip.height - 4,
                child: Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 10),
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
              child: Container(width: 2, color: scheme.primary),
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
    final scheme = Theme.of(context).colorScheme;
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
        Icon(
          pageId == null ? Icons.tab_outlined : Icons.description_outlined,
          size: 14,
          color: showing ? scheme.primary : scheme.onSurfaceVariant,
        ),
        const SizedBox(width: 6),
        Expanded(
          child: Text(
            title,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(
              fontSize: 12.5,
              fontWeight: showing ? FontWeight.w600 : FontWeight.w400,
              color: showing ? scheme.onSurface : scheme.onSurfaceVariant,
            ),
          ),
        ),
      ],
    );
  }
}
