/// The ribbon: tabs of commands above the page, as in OneNote.
library;

import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'ribbon_items.dart';
import 'ribbon_layout.dart';
import 'ribbon_state.dart';

export 'ribbon_items.dart' show RibbonCommands;
export 'ribbon_layout.dart' show RibbonTab;
export 'ribbon_state.dart' show ribbonProvider;

/// Where a dragged button would land: in front of the button now at [index]
/// in [group], or at its end.
typedef _Slot = ({RibbonGroup group, int index});

/// Tabs of commands, each in sections divided by lines, with every section's
/// name beneath it.
///
/// It is always there — nothing appears or disappears as the caret moves —
/// and commands with nothing to act on are greyed out. Tool shortcuts bring
/// the matching tab forward (see [RibbonController.show]), and any button can
/// be dragged to another place, section or tab, which is remembered.
class Ribbon extends ConsumerStatefulWidget {
  const Ribbon({required this.commands, super.key});

  final RibbonCommands commands;

  static const double tabStripHeight = 30;
  static const double labelHeight = 16;

  /// The height of the commands below the tabs.
  static const double bodyHeight = 4 + RibbonMetrics.content + labelHeight + 2;

  @override
  ConsumerState<Ribbon> createState() => _RibbonState();
}

class _RibbonState extends ConsumerState<Ribbon> {
  /// The button being dragged, if any.
  final ValueNotifier<RibbonItem?> _dragging = ValueNotifier<RibbonItem?>(null);

  /// Where it would land if dropped now.
  final ValueNotifier<_Slot?> _slot = ValueNotifier<_Slot?>(null);

  /// Each button's key, by which its place on screen is found while another
  /// is dragged over it — and which lets a moved button keep its state.
  final Map<RibbonItem, GlobalKey> _keys = <RibbonItem, GlobalKey>{
    for (final item in RibbonItem.values)
      item: GlobalKey(debugLabel: 'ribbon ${item.name}'),
  };

  final ScrollController _scroll = ScrollController();

  @override
  void dispose() {
    _dragging.dispose();
    _slot.dispose();
    _scroll.dispose();
    super.dispose();
  }

  void _startDrag(RibbonItem item) => _dragging.value = item;

  void _endDrag() {
    _dragging.value = null;
    _slot.value = null;
  }

  void _drop(RibbonItem item, RibbonGroup group, int index) {
    ref.read(ribbonProvider.notifier).move(item, group, index);
    _endDrag();
  }

  /// A button dropped on a tab's name goes at the end of that tab.
  void _dropOnTab(RibbonItem item, RibbonTab tab) {
    final group = RibbonGroup.of(tab).last;
    final controller = ref.read(ribbonProvider.notifier);
    controller.move(
      item,
      group,
      ref.read(ribbonProvider).layout.itemsIn(group).length,
    );
    controller.open(tab);
    _endDrag();
  }

  /// Where [pointer], in global coordinates, falls among [items]: in front of
  /// the nearest button, or after it if the pointer is past its middle.
  int _indexAt(List<RibbonItem> items, Offset pointer) {
    var best = items.length;
    var bestDistance = double.infinity;
    for (var i = 0; i < items.length; i++) {
      final box = _keys[items[i]]!.currentContext?.findRenderObject();
      if (box is! RenderBox || !box.hasSize) continue;
      final center = box.localToGlobal(box.size.center(Offset.zero));
      final distance = (center - pointer).distance;
      if (distance < bestDistance) {
        bestDistance = distance;
        best = pointer.dx < center.dx ? i : i + 1;
      }
    }
    return best;
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
    final scheme = Theme.of(context).colorScheme;

    return RibbonScope(
      commands: widget.commands,
      // Nothing on the ribbon takes the keyboard focus, so pressing Bold
      // leaves the caret in the text it formats.
      child: ExcludeFocus(
        child: Material(
          color: scheme.surfaceContainerLow,
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
                SizedBox(height: Ribbon.bodyHeight, child: _body(state)),
              Divider(height: 1, thickness: 1, color: scheme.outlineVariant),
            ],
          ),
        ),
      ),
    );
  }

  Widget _body(RibbonState state) => ValueListenableBuilder<RibbonItem?>(
    valueListenable: _dragging,
    builder: (context, dragging, _) {
      // A section emptied by moving its buttons away is hidden, except while
      // a button is being dragged, when it is somewhere to put one back.
      final groups = <RibbonGroup>[
        for (final group in RibbonGroup.of(state.tab))
          if (dragging != null || state.layout.itemsIn(group).isNotEmpty) group,
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
                  items: state.layout.itemsIn(groups[i]),
                  keys: _keys,
                  slot: _slot,
                  indexAt: _indexAt,
                  onDragStarted: _startDrag,
                  onDragEnded: _endDrag,
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
    final scheme = Theme.of(context).colorScheme;
    final controller = ref.read(ribbonProvider.notifier);
    final saving = this.saving;

    return SizedBox(
      height: Ribbon.tabStripHeight,
      child: Row(
        children: <Widget>[
          const SizedBox(width: 6),
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
                  ? _SavingIndicator(color: scheme.onSurfaceVariant)
                  : const SizedBox.shrink(),
            ),
          IconButton(
            icon: Icon(
              state.collapsed
                  ? Icons.keyboard_arrow_down_rounded
                  : Icons.keyboard_arrow_up_rounded,
              size: 18,
            ),
            tooltip: state.collapsed
                ? 'Show the ribbon  (Ctrl+F1)'
                : 'Collapse the ribbon  (Ctrl+F1)',
            visualDensity: VisualDensity.compact,
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
    final scheme = Theme.of(context).colorScheme;
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
        borderRadius: const BorderRadius.vertical(top: Radius.circular(6)),
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 12),
          color: candidates.isEmpty
              ? null
              : scheme.primary.withValues(alpha: 0.10),
          alignment: Alignment.bottomCenter,
          child: Container(
            padding: const EdgeInsets.only(bottom: 4),
            decoration: BoxDecoration(
              border: Border(
                bottom: BorderSide(
                  color: selected ? scheme.primary : Colors.transparent,
                  width: 2.5,
                ),
              ),
            ),
            child: Text(
              widget.tab.label,
              style: TextStyle(
                fontSize: 12.5,
                fontWeight: selected ? FontWeight.w600 : FontWeight.w500,
                color: selected ? scheme.primary : scheme.onSurfaceVariant,
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
  Widget build(BuildContext context) => VerticalDivider(
    width: 13,
    thickness: 1,
    indent: 6,
    endIndent: 6,
    color: Theme.of(context).colorScheme.outlineVariant,
  );
}

/// A section: its buttons — tall ones side by side, small ones stacked in
/// two rows — with its name beneath.
class _GroupView extends StatelessWidget {
  const _GroupView({
    required this.group,
    required this.items,
    required this.keys,
    required this.slot,
    required this.indexAt,
    required this.onDragStarted,
    required this.onDragEnded,
    required this.onDrop,
  });

  final RibbonGroup group;
  final List<RibbonItem> items;
  final Map<RibbonItem, GlobalKey> keys;
  final ValueNotifier<_Slot?> slot;
  final int Function(List<RibbonItem> items, Offset pointer) indexAt;
  final ValueChanged<RibbonItem> onDragStarted;
  final VoidCallback onDragEnded;
  final void Function(RibbonItem item, RibbonGroup group, int index) onDrop;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return DragTarget<RibbonItem>(
      onWillAcceptWithDetails: (_) => true,
      onMove: (details) =>
          slot.value = (group: group, index: indexAt(items, details.offset)),
      onLeave: (_) {
        if (slot.value?.group == group) slot.value = null;
      },
      onAcceptWithDetails: (details) =>
          onDrop(details.data, group, indexAt(items, details.offset)),
      builder: (context, candidates, _) => Container(
        padding: const EdgeInsets.fromLTRB(3, 4, 3, 2),
        decoration: BoxDecoration(
          color: candidates.isEmpty
              ? null
              : scheme.primary.withValues(alpha: 0.05),
          borderRadius: BorderRadius.circular(6),
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: <Widget>[
            SizedBox(
              height: RibbonMetrics.content,
              child: items.isEmpty
                  ? _EmptyGroup(highlighted: candidates.isNotEmpty)
                  : Row(mainAxisSize: MainAxisSize.min, children: _columns()),
            ),
            SizedBox(
              height: Ribbon.labelHeight,
              child: Center(
                child: Text(
                  group.label,
                  style: TextStyle(
                    fontSize: 10.5,
                    color: scheme.onSurfaceVariant,
                  ),
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
    return ValueListenableBuilder<_Slot?>(
      valueListenable: slot,
      builder: (context, slot, child) {
        final here = slot != null && slot.group == group;
        return _DropMarker(
          before: here && slot.index == index,
          after:
              here && slot.index == items.length && index == items.length - 1,
          child: child!,
        );
      },
      child: KeyedSubtree(
        key: keys[item],
        child: _ItemDraggable(
          item: item,
          onDragStarted: () => onDragStarted(item),
          onDragEnded: onDragEnded,
        ),
      ),
    );
  }
}

/// An emptied section, while a button is dragged: somewhere to drop it.
class _EmptyGroup extends StatelessWidget {
  const _EmptyGroup({required this.highlighted});

  final bool highlighted;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Container(
      width: 52,
      margin: const EdgeInsets.all(4),
      decoration: BoxDecoration(
        border: Border.all(
          color: highlighted ? scheme.primary : scheme.outlineVariant,
        ),
        borderRadius: BorderRadius.circular(6),
      ),
      child: Icon(Icons.add_rounded, size: 16, color: scheme.outline),
    );
  }
}

/// Marks where a dragged button would go: a line at the left or right edge
/// of the button beside that place.
class _DropMarker extends StatelessWidget {
  const _DropMarker({
    required this.before,
    required this.after,
    required this.child,
  });

  final bool before;
  final bool after;
  final Widget child;

  @override
  Widget build(BuildContext context) => CustomPaint(
    foregroundPainter: before || after
        ? _DropMarkerPainter(
            atStart: before,
            color: Theme.of(context).colorScheme.primary,
          )
        : null,
    child: child,
  );
}

class _DropMarkerPainter extends CustomPainter {
  _DropMarkerPainter({required this.atStart, required this.color});

  final bool atStart;
  final Color color;

  @override
  void paint(Canvas canvas, Size size) {
    final x = atStart ? 1.0 : size.width - 1;
    canvas.drawLine(
      Offset(x, 2),
      Offset(x, size.height - 2),
      Paint()
        ..color = color
        ..strokeWidth = 2.5
        ..strokeCap = StrokeCap.round,
    );
  }

  @override
  bool shouldRepaint(_DropMarkerPainter oldDelegate) =>
      oldDelegate.atStart != atStart || oldDelegate.color != color;
}

// -------------------------------------------------------------- dragging

/// A ribbon button that can be picked up and moved.
class _ItemDraggable extends StatelessWidget {
  const _ItemDraggable({
    required this.item,
    required this.onDragStarted,
    required this.onDragEnded,
  });

  final RibbonItem item;
  final VoidCallback onDragStarted;
  final VoidCallback onDragEnded;

  @override
  Widget build(BuildContext context) {
    final button = RibbonItemView(item: item);
    return _RibbonDraggable(
      data: item,
      dragAnchorStrategy: pointerDragAnchorStrategy,
      feedback: _DragPreview(item: item),
      childWhenDragging: Opacity(
        opacity: 0.3,
        child: IgnorePointer(child: button),
      ),
      onDragStarted: onDragStarted,
      // Called even if the tab it came from has been switched away from,
      // unlike onDragEnd.
      onDragCompleted: onDragEnded,
      onDraggableCanceled: (_, _) => onDragEnded(),
      child: button,
    );
  }
}

/// What follows the pointer while a button is dragged.
class _DragPreview extends StatelessWidget {
  const _DragPreview({required this.item});

  final RibbonItem item;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return FractionalTranslation(
      translation: const Offset(-0.5, -0.5),
      child: Material(
        elevation: 6,
        color: theme.colorScheme.surfaceContainerHighest,
        borderRadius: BorderRadius.circular(8),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: <Widget>[
              ribbonGlyphOf(item),
              const SizedBox(width: 6),
              Text(item.label, style: theme.textTheme.labelMedium),
            ],
          ),
        ),
      ),
    );
  }
}

class _RibbonDraggable extends Draggable<RibbonItem> {
  const _RibbonDraggable({
    required super.child,
    required super.feedback,
    required super.data,
    super.childWhenDragging,
    super.dragAnchorStrategy,
    super.onDragStarted,
    super.onDragCompleted,
    super.onDraggableCanceled,
  });

  @override
  MultiDragGestureRecognizer createRecognizer(
    GestureMultiDragStartCallback onStart,
  ) =>
      _RibbonDragRecognizer(allowedButtonsFilter: allowedButtonsFilter)
        ..onStart = onStart;
}

/// Picks a button up once a mouse has moved it a few pixels, or once a
/// finger has held it: a click still presses the button, and a finger
/// swiping along the ribbon still scrolls it.
class _RibbonDragRecognizer extends MultiDragGestureRecognizer {
  _RibbonDragRecognizer({super.debugOwner, super.allowedButtonsFilter});

  @override
  MultiDragPointerState createNewPointerState(PointerDownEvent event) =>
      event.kind == PointerDeviceKind.touch
      ? _HoldToDrag(event.position, event.kind, gestureSettings)
      : _MoveToDrag(event.position, event.kind, gestureSettings);

  @override
  String get debugDescription => 'ribbon drag';
}

class _MoveToDrag extends MultiDragPointerState {
  _MoveToDrag(super.initialPosition, super.kind, super.gestureSettings);

  /// Far enough that a click with a slight wobble is still a click.
  static const double _slop = 6;

  @override
  void checkForResolutionAfterMove() {
    if (pendingDelta!.distance > _slop) resolve(GestureDisposition.accepted);
  }

  @override
  void accepted(GestureMultiDragStartCallback starter) =>
      starter(initialPosition);
}

class _HoldToDrag extends MultiDragPointerState {
  _HoldToDrag(super.initialPosition, super.kind, super.gestureSettings) {
    _timer = Timer(_delay, _held);
  }

  /// A little shorter than a long press, so the drag wins over the tooltip.
  static const Duration _delay = Duration(milliseconds: 400);

  Timer? _timer;
  GestureMultiDragStartCallback? _starter;

  void _held() {
    _timer = null;
    final starter = _starter;
    if (starter != null) {
      _starter = null;
      starter(initialPosition);
    } else {
      resolve(GestureDisposition.accepted);
    }
  }

  @override
  void accepted(GestureMultiDragStartCallback starter) {
    if (_timer == null) {
      starter(initialPosition);
    } else {
      _starter = starter;
    }
  }

  @override
  void checkForResolutionAfterMove() {
    if (_timer == null) return;
    if (pendingDelta!.distance > computeHitSlop(kind, gestureSettings)) {
      resolve(GestureDisposition.rejected);
      _timer?.cancel();
      _timer = null;
    }
  }

  @override
  void dispose() {
    _timer?.cancel();
    _timer = null;
    super.dispose();
  }
}

class _SavingIndicator extends StatelessWidget {
  const _SavingIndicator({required this.color});

  final Color color;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.only(right: 8),
    child: Row(
      children: <Widget>[
        SizedBox(
          width: 11,
          height: 11,
          child: CircularProgressIndicator(strokeWidth: 1.6, color: color),
        ),
        const SizedBox(width: 6),
        Text('Saving', style: TextStyle(fontSize: 11, color: color)),
      ],
    ),
  );
}
