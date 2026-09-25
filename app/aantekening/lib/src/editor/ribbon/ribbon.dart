/// The ribbon: tabs of commands above the page, as in OneNote.
library;

import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../arrangement/arrangement_drag.dart';
import '../../commands/app_command.dart';
import '../../commands/shortcuts.dart';
import '../../look/controls.dart';
import '../../look/marks.dart';
import '../../look/tones.dart';
import 'ribbon_items.dart';
import 'ribbon_layout.dart';
import 'ribbon_state.dart';

export 'ribbon_items.dart' show RibbonCommands;
export 'ribbon_layout.dart' show RibbonTab;
export 'ribbon_state.dart' show ribbonLayoutProvider, ribbonProvider;

/// Tabs of commands, each in sections divided by lines, with every section's
/// name beneath it, across the top of the window.
///
/// It is always there — nothing appears or disappears as the caret moves —
/// and commands with nothing to act on are greyed out. Tool shortcuts bring
/// the matching tab forward (see [RibbonController.show]), and any button can
/// be dragged to another place, section or tab, which is remembered.
class Ribbon extends ConsumerStatefulWidget {
  const Ribbon({required this.commands, this.enabled = true, super.key});

  final RibbonCommands commands;

  /// Whether there is a page for the commands to act on. Without one they
  /// are shown greyed out, so the ribbon keeps its place and its size.
  final bool enabled;

  static const double tabStripHeight = 30;
  static const double labelHeight = 16;

  /// The height of the commands below the tabs.
  static const double bodyHeight = 4 + RibbonMetrics.content + labelHeight + 2;

  @override
  ConsumerState<Ribbon> createState() => _RibbonState();
}

class _RibbonState extends ConsumerState<Ribbon> {
  final ArrangementDrag<RibbonGroup, RibbonItem> _drag =
      ArrangementDrag<RibbonGroup, RibbonItem>();

  final ScrollController _scroll = ScrollController();

  @override
  void dispose() {
    _drag.dispose();
    _scroll.dispose();
    super.dispose();
  }

  void _drop(RibbonItem item, RibbonGroup group, int index) =>
      ref.read(ribbonLayoutProvider.notifier).move(item, group, index);

  /// A button dropped on a tab's name goes at the end of that tab.
  void _dropOnTab(RibbonItem item, RibbonTab tab) {
    final group = RibbonGroup.of(tab).last;
    ref
        .read(ribbonLayoutProvider.notifier)
        .move(
          item,
          group,
          ref.read(ribbonLayoutProvider).itemsIn(group).length,
        );
    ref.read(ribbonProvider.notifier).open(tab);
    _drag.end();
  }

  /// Lets a mouse wheel scroll a ribbon too wide for the window sideways.
  void _scrollSideways(PointerSignalEvent event) {
    if (event is! PointerScrollEvent || !_scroll.hasClients) return;
    final position = _scroll.position;
    if (position.maxScrollExtent <= 0) return;
    final delta = event.scrollDelta.dx != 0
        ? event.scrollDelta.dx
        : event.scrollDelta.dy;
    GestureBinding.instance.pointerSignalResolver.register(event, (_) {
      position.jumpTo(
        (position.pixels + delta).clamp(0, position.maxScrollExtent),
      );
    });
  }

  @override
  Widget build(BuildContext context) {
    final state = ref.watch(ribbonProvider);
    final layout = ref.watch(ribbonLayoutProvider);
    final tones = context.tones;

    return RibbonScope(
      commands: widget.commands,
      // Nothing on the ribbon takes the keyboard focus, so pressing Bold
      // leaves the caret in the text it formats.
      child: ExcludeFocus(
        child: Material(
          color: tones.base,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: <Widget>[
              _TabStrip(
                state: state,
                saving: widget.commands.saving,
                onDropped: _dropOnTab,
              ),
              if (!state.collapsed)
                SizedBox(
                  height: Ribbon.bodyHeight,
                  child: IgnorePointer(
                    ignoring: !widget.enabled,
                    child: AnimatedOpacity(
                      opacity: widget.enabled ? 1 : 0.4,
                      duration: const Duration(milliseconds: 150),
                      child: _body(state, layout),
                    ),
                  ),
                ),
              const Divider(),
            ],
          ),
        ),
      ),
    );
  }

  Widget _body(RibbonState state, RibbonLayout layout) =>
      ValueListenableBuilder<RibbonItem?>(
        valueListenable: _drag.dragging,
        builder: (context, dragging, _) {
          // A section emptied by moving its buttons away is hidden, except
          // while a button is being dragged, when it is somewhere to put one
          // back.
          final groups = <RibbonGroup>[
            for (final group in RibbonGroup.of(state.tab))
              if (dragging != null || layout.itemsIn(group).isNotEmpty) group,
          ];
          return Listener(
            onPointerSignal: _scrollSideways,
            child: SingleChildScrollView(
              controller: _scroll,
              scrollDirection: Axis.horizontal,
              padding: const EdgeInsets.symmetric(horizontal: 6),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: <Widget>[
                  for (var i = 0; i < groups.length; i++) ...<Widget>[
                    if (i > 0) const _GroupDivider(),
                    _GroupView(
                      group: groups[i],
                      items: layout.itemsIn(groups[i]),
                      drag: _drag,
                      onDrop: _drop,
                    ),
                  ],
                ],
              ),
            ),
          );
        },
      );
}

// ------------------------------------------------------------------ tabs

class _TabStrip extends ConsumerWidget {
  const _TabStrip({
    required this.state,
    required this.saving,
    required this.onDropped,
  });

  final RibbonState state;
  final ValueListenable<bool>? saving;
  final void Function(RibbonItem item, RibbonTab tab) onDropped;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final tones = context.tones;
    final controller = ref.read(ribbonProvider.notifier);
    final bindings = ref.watch(shortcutsProvider);
    final saving = this.saving;

    return SizedBox(
      height: Ribbon.tabStripHeight,
      child: Row(
        children: <Widget>[
          const SizedBox(width: 4),
          // The tab names scroll rather than overflow in a narrow window.
          Expanded(
            child: SingleChildScrollView(
              scrollDirection: Axis.horizontal,
              child: Row(
                children: <Widget>[
                  for (final tab in RibbonTab.values)
                    _TabHeader(
                      tab: tab,
                      selected: tab == state.tab && !state.collapsed,
                      onDropped: (item) => onDropped(item, tab),
                    ),
                ],
              ),
            ),
          ),
          if (saving != null)
            ValueListenableBuilder<bool>(
              valueListenable: saving,
              builder: (context, saving, _) => saving
                  ? Padding(
                      padding: const EdgeInsets.only(right: 10),
                      child: Text(
                        'Saving…',
                        style: TextStyle(fontSize: 11.5, color: tones.muted),
                      ),
                    )
                  : const SizedBox.shrink(),
            ),
          MarkButton(
            state.collapsed ? MarkShape.chevronDown : MarkShape.chevronUp,
            tooltip: bindings.tooltip(
              AppCommand.toggleRibbon,
              label: state.collapsed
                  ? 'Show the ribbon'
                  : 'Collapse the ribbon',
            ),
            onPressed: controller.toggleCollapsed,
          ),
          const SizedBox(width: 4),
        ],
      ),
    );
  }
}

/// A tab's name. Holding a dragged button over it opens the tab, so the
/// button can be dropped anywhere on it; dropping it on the name puts it at
/// the tab's end.
class _TabHeader extends ConsumerStatefulWidget {
  const _TabHeader({
    required this.tab,
    required this.selected,
    required this.onDropped,
  });

  final RibbonTab tab;
  final bool selected;
  final ValueChanged<RibbonItem> onDropped;

  @override
  ConsumerState<_TabHeader> createState() => _TabHeaderState();
}

class _TabHeaderState extends ConsumerState<_TabHeader> {
  static const Duration _hoverDelay = Duration(milliseconds: 450);

  Timer? _hover;

  @override
  void dispose() {
    _hover?.cancel();
    super.dispose();
  }

  void _open() => ref.read(ribbonProvider.notifier).open(widget.tab);

  @override
  Widget build(BuildContext context) {
    final tones = context.tones;
    final selected = widget.selected;

    return DragTarget<RibbonItem>(
      onWillAcceptWithDetails: (_) {
        _hover?.cancel();
        _hover = Timer(_hoverDelay, () {
          if (mounted) _open();
        });
        return true;
      },
      onLeave: (_) => _hover?.cancel(),
      onAcceptWithDetails: (details) {
        _hover?.cancel();
        widget.onDropped(details.data);
      },
      builder: (context, candidates, _) => InkWell(
        onTap: _open,
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 11),
          color: candidates.isEmpty ? null : tones.selection,
          alignment: Alignment.center,
          child: Container(
            padding: const EdgeInsets.only(top: 2),
            height: double.infinity,
            alignment: Alignment.center,
            decoration: BoxDecoration(
              border: Border(
                bottom: BorderSide(
                  color: selected ? tones.emphasis : Colors.transparent,
                  width: 2,
                ),
              ),
            ),
            child: Text(
              widget.tab.label,
              style: TextStyle(
                fontSize: 12.5,
                fontWeight: selected ? FontWeight.w600 : FontWeight.w500,
                color: selected ? tones.text : tones.muted,
              ),
            ),
          ),
        ),
      ),
    );
  }
}

// -------------------------------------------------------------- sections

class _GroupDivider extends StatelessWidget {
  const _GroupDivider();

  @override
  Widget build(BuildContext context) =>
      const VerticalDivider(width: 13, indent: 6, endIndent: 6);
}

/// A section: its buttons — tall ones side by side, small ones stacked in
/// two rows — with its name beneath.
class _GroupView extends StatelessWidget {
  const _GroupView({
    required this.group,
    required this.items,
    required this.drag,
    required this.onDrop,
  });

  final RibbonGroup group;
  final List<RibbonItem> items;
  final ArrangementDrag<RibbonGroup, RibbonItem> drag;
  final void Function(RibbonItem item, RibbonGroup group, int index) onDrop;

  @override
  Widget build(BuildContext context) {
    final tones = context.tones;
    return ArrangementDropTarget<RibbonGroup, RibbonItem>(
      drag: drag,
      group: group,
      items: items,
      axis: Axis.horizontal,
      onDrop: onDrop,
      builder: (context, highlighted) => Container(
        padding: const EdgeInsets.fromLTRB(3, 4, 3, 2),
        color: highlighted ? tones.hover : null,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: <Widget>[
            SizedBox(
              height: RibbonMetrics.content,
              child: items.isEmpty
                  ? ArrangementEmptyGroup(highlighted: highlighted)
                  : Row(mainAxisSize: MainAxisSize.min, children: _columns()),
            ),
            SizedBox(
              height: Ribbon.labelHeight,
              child: Center(
                child: Text(
                  group.label,
                  style: TextStyle(fontSize: 10.5, color: tones.muted),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  /// Tall buttons each take a column; each run of small ones between them is
  /// split across two rows, the first row taking the extra one.
  List<Widget> _columns() {
    final columns = <Widget>[];
    var i = 0;
    while (i < items.length) {
      if (items[i].large) {
        columns.add(_cell(i));
        i++;
        continue;
      }
      final start = i;
      while (i < items.length && !items[i].large) {
        i++;
      }
      final run = <int>[for (var j = start; j < i; j++) j];
      final perRow = (run.length + 1) ~/ 2;
      Widget row(Iterable<int> cells) => SizedBox(
        height: RibbonMetrics.row,
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: <Widget>[for (final j in cells) _cell(j)],
        ),
      );
      columns.add(
        Column(
          mainAxisAlignment: MainAxisAlignment.center,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: <Widget>[
            row(run.take(perRow)),
            if (run.length > 1) row(run.skip(perRow)),
          ],
        ),
      );
    }
    return columns;
  }

  Widget _cell(int index) {
    final item = items[index];
    return ArrangeableItem<RibbonGroup, RibbonItem>(
      drag: drag,
      item: item,
      group: group,
      index: index,
      count: items.length,
      axis: Axis.horizontal,
      label: item.label,
      child: RibbonItemView(item: item),
    );
  }
}
