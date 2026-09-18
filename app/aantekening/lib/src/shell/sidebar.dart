/// The sidebar down the left of the window, beneath the ribbon.
library;

import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../arrangement/arrangement_drag.dart';
import '../graph/graph_panel.dart';
import '../providers.dart';
import '../search/search_panel.dart';
import '../settings/ai_panel.dart';
import 'library_menu.dart';
import 'library_pane.dart';
import 'page_list_pane.dart';
import 'sidebar_state.dart';

/// A strip of buttons, each opening a panel beside it — the notebooks and
/// pages, search, the graph, the local AI — with [page] taking the rest of
/// the window.
///
/// Clicking the open panel's button closes it. Each column of a panel is
/// dragged by its right edge to make it wider or narrower, and the buttons
/// are dragged to rearrange them, as the ribbon's are. In a narrow window a
/// panel opens over the page instead of beside it, as a drawer would.
class Sidebar extends ConsumerStatefulWidget {
  const Sidebar({required this.page, super.key});

  final Widget page;

  static const double barWidth = 44;

  /// The narrowest a panel beside it squeezes the page to.
  static const double minPageWidth = 320;

  /// Below this width a panel opens over the page.
  static const double compactWidth = 720;

  @override
  ConsumerState<Sidebar> createState() => _SidebarState();
}

class _SidebarState extends ConsumerState<Sidebar> {
  bool _compact = false;

  @override
  Widget build(BuildContext context) {
    // A panel over the page is closed once a page is picked from it.
    ref.listen<String?>(selectedPageProvider, (previous, next) {
      if (_compact && next != null && next != previous) {
        ref.read(sidebarProvider.notifier).close();
      }
    });
    final open = ref.watch(sidebarProvider.select((state) => state.open));

    return LayoutBuilder(
      builder: (context, constraints) {
        _compact = constraints.maxWidth < Sidebar.compactWidth;
        final room = _compact
            ? constraints.maxWidth - Sidebar.barWidth - 48
            : constraints.maxWidth - Sidebar.barWidth - Sidebar.minPageWidth;
        final panel = open == null
            ? null
            : _Panel(
                key: ValueKey<SidebarTab>(open),
                tab: open,
                maxWidth: math.max(0, room),
              );

        return Row(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: <Widget>[
            const _ButtonStrip(),
            const VerticalDivider(width: 1),
            if (panel != null && !_compact) panel,
            Expanded(
              child: Stack(
                children: <Widget>[
                  Positioned.fill(child: widget.page),
                  if (panel != null && _compact) ...<Widget>[
                    Positioned.fill(
                      child: GestureDetector(
                        onTap: ref.read(sidebarProvider.notifier).close,
                        child: const ColoredBox(color: Color(0x42000000)),
                      ),
                    ),
                    Positioned(
                      left: 0,
                      top: 0,
                      bottom: 0,
                      child: Material(elevation: 8, child: panel),
                    ),
                  ],
                ],
              ),
            ),
          ],
        );
      },
    );
  }
}

// ---------------------------------------------------------------- buttons

/// The sidebar's buttons: some down from the top, some up from the bottom.
class _ButtonStrip extends ConsumerStatefulWidget {
  const _ButtonStrip();

  @override
  ConsumerState<_ButtonStrip> createState() => _ButtonStripState();
}

class _ButtonStripState extends ConsumerState<_ButtonStrip> {
  final ArrangementDrag<SidebarGroup, SidebarTab> _drag =
      ArrangementDrag<SidebarGroup, SidebarTab>();

  @override
  void dispose() {
    _drag.dispose();
    super.dispose();
  }

  void _drop(SidebarTab tab, SidebarGroup group, int index) =>
      ref.read(sidebarLayoutProvider.notifier).move(tab, group, index);

  @override
  Widget build(BuildContext context) {
    final layout = ref.watch(sidebarLayoutProvider);
    final scheme = Theme.of(context).colorScheme;

    Widget group(SidebarGroup group) {
      final tabs = layout.itemsIn(group);
      return ArrangementDropTarget<SidebarGroup, SidebarTab>(
        drag: _drag,
        group: group,
        items: tabs,
        axis: Axis.vertical,
        onDrop: _drop,
        builder: (context, highlighted) => ValueListenableBuilder<SidebarTab?>(
          valueListenable: _drag.dragging,
          builder: (context, dragging, _) => Column(
            mainAxisAlignment: group == SidebarGroup.top
                ? MainAxisAlignment.start
                : MainAxisAlignment.end,
            children: <Widget>[
              for (var i = 0; i < tabs.length; i++)
                ArrangeableItem<SidebarGroup, SidebarTab>(
                  drag: _drag,
                  item: tabs[i],
                  group: group,
                  index: i,
                  count: tabs.length,
                  axis: Axis.vertical,
                  icon: Icon(tabs[i].icon, size: 18),
                  label: tabs[i].label,
                  child: _TabButton(tab: tabs[i]),
                ),
              // An emptied group, while a button is dragged, is somewhere to
              // put one back.
              if (tabs.isEmpty && dragging != null)
                ArrangementEmptyGroup(
                  highlighted: highlighted,
                  width: 34,
                  height: 34,
                ),
            ],
          ),
        ),
      );
    }

    return GestureDetector(
      onSecondaryTapUp: (details) =>
          showCommandMenu(context, details.globalPosition, <List<MenuCommand>>[
            <MenuCommand>[
              MenuCommand(
                'Reset the sidebar',
                Icons.restart_alt_rounded,
                layout.isDefault
                    ? null
                    : ref.read(sidebarLayoutProvider.notifier).reset,
              ),
            ],
          ]),
      child: Material(
        color: scheme.surfaceContainer,
        child: SizedBox(
          width: Sidebar.barWidth,
          child: Padding(
            padding: const EdgeInsets.symmetric(vertical: 4),
            child: Column(
              children: <Widget>[
                Expanded(child: group(SidebarGroup.top)),
                group(SidebarGroup.bottom),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _TabButton extends ConsumerWidget {
  const _TabButton({required this.tab});

  final SidebarTab tab;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final scheme = Theme.of(context).colorScheme;
    final open = ref.watch(sidebarProvider.select((state) => state.open));
    final selected = open == tab;
    // The local AI's button is lit while a model runtime can be reached.
    final connected =
        tab == SidebarTab.assistant &&
        ref.watch(modelAvailabilityProvider).value == true;

    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 2),
      child: Stack(
        children: <Widget>[
          IconButton(
            icon: Icon(tab.icon, size: 20),
            tooltip: connected ? '${tab.label} — connected' : tab.label,
            isSelected: selected,
            color: connected ? scheme.primary : scheme.onSurfaceVariant,
            selectedIcon: Icon(tab.icon, size: 20, color: scheme.primary),
            style: IconButton.styleFrom(
              fixedSize: const Size.square(36),
              backgroundColor: selected
                  ? scheme.primary.withValues(alpha: 0.12)
                  : null,
            ),
            onPressed: () => ref.read(sidebarProvider.notifier).toggle(tab),
          ),
          if (selected)
            Positioned(
              left: 0,
              top: 8,
              bottom: 8,
              child: Container(
                width: 2.5,
                decoration: BoxDecoration(
                  color: scheme.primary,
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
            ),
        ],
      ),
    );
  }
}

// ----------------------------------------------------------------- panels

/// The columns of [tab]'s panel, side by side, no wider together than
/// [maxWidth], each with an edge to drag.
class _Panel extends ConsumerWidget {
  const _Panel({required this.tab, required this.maxWidth, super.key});

  final SidebarTab tab;
  final double maxWidth;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final state = ref.watch(sidebarProvider);
    final columns = tab.columns;
    final shown = fitWidths(<double>[
      for (final column in columns) state.widthOf(column),
    ], maxWidth - columns.length);

    final children = <Widget>[];
    final handles = <Widget>[];
    var edge = 0.0;
    for (var i = 0; i < columns.length; i++) {
      final column = columns[i];
      children
        ..add(
          SizedBox(
            width: shown[i],
            child: KeyedSubtree(
              key: ValueKey<SidebarColumn>(column),
              child: _content(column),
            ),
          ),
        )
        ..add(const VerticalDivider(width: 1));
      edge += shown[i];
      // A column can widen into what the page and its neighbours can spare.
      final others = shown.fold<double>(0, (sum, width) => sum + width);
      final room = maxWidth - columns.length - (others - shown[i]);
      handles.add(
        Positioned(
          left: edge - _EdgeHandle.reach,
          top: 0,
          bottom: 0,
          width: _EdgeHandle.reach + 1,
          child: _EdgeHandle(
            width: shown[i],
            onResize: (width) => ref
                .read(sidebarProvider.notifier)
                .resize(column, math.min(width, room)),
            onEnd: ref.read(sidebarProvider.notifier).saveWidths,
          ),
        ),
      );
      edge += 1;
    }

    return SizedBox(
      width: edge,
      child: Stack(
        children: <Widget>[
          Row(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: children,
          ),
          ...handles,
        ],
      ),
    );
  }

  static Widget _content(SidebarColumn column) => switch (column) {
    SidebarColumn.notebooks => const LibraryPane(),
    SidebarColumn.pages => const PageListPane(),
    SidebarColumn.search => const SearchPanel(),
    SidebarColumn.graph => const GraphPanel(),
    SidebarColumn.assistant => const AiPanel(),
  };
}

/// [wanted] widths, scaled down together to fit [room] if they do not.
List<double> fitWidths(List<double> wanted, double room) {
  final total = wanted.fold<double>(0, (sum, width) => sum + width);
  if (total <= room || total <= 0) return wanted;
  final scale = math.max(0, room) / total;
  return <double>[for (final width in wanted) width * scale];
}

/// The right edge of a column, dragged to resize it.
class _EdgeHandle extends StatefulWidget {
  const _EdgeHandle({
    required this.width,
    required this.onResize,
    required this.onEnd,
  });

  /// How far into the column, from its edge, it can be taken hold of.
  static const double reach = 5;

  /// The column's width now.
  final double width;

  /// Called with the width the column is dragged to.
  final ValueChanged<double> onResize;

  final VoidCallback onEnd;

  @override
  State<_EdgeHandle> createState() => _EdgeHandleState();
}

class _EdgeHandleState extends State<_EdgeHandle> {
  double _start = 0;
  double _dragged = 0;
  bool _hovered = false;
  bool _dragging = false;

  @override
  Widget build(BuildContext context) {
    final lit = _hovered || _dragging;
    return MouseRegion(
      cursor: SystemMouseCursors.resizeColumn,
      onEnter: (_) => setState(() => _hovered = true),
      onExit: (_) => setState(() => _hovered = false),
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onHorizontalDragStart: (_) => setState(() {
          _dragging = true;
          _start = widget.width;
          _dragged = 0;
        }),
        onHorizontalDragUpdate: (details) {
          _dragged += details.delta.dx;
          widget.onResize(_start + _dragged);
        },
        onHorizontalDragEnd: (_) {
          setState(() => _dragging = false);
          widget.onEnd();
        },
        onHorizontalDragCancel: () => setState(() => _dragging = false),
        child: Align(
          alignment: Alignment.centerRight,
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 120),
            width: lit ? 3 : 0,
            color: Theme.of(context).colorScheme.primary,
          ),
        ),
      ),
    );
  }
}
