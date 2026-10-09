/// The status line: one thin line of glass along the top or the foot of the
/// window, as vim's is, saying what mode the keys are in, which tabs are
/// open, and what the page has in hand.
library;

import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
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

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final state = ref.watch(tabsProvider);
    return _FairRow(
      children: <Widget>[
        for (var i = 0; i < state.tabs.length; i++)
          _Tab(
            key: ValueKey<int>(state.tabs[i].id),
            index: i,
            tab: state.tabs[i],
            showing: i == state.active,
            beside: i == state.beside,
          ),
      ],
    );
  }
}

/// Lays the tabs along the line as wide as their names, until there are
/// more than fit: then the widest are narrowed, alike, just enough that all
/// of them do, and only their names are cut short.
class _FairRow extends MultiChildRenderObjectWidget {
  const _FairRow({required super.children});

  @override
  RenderObject createRenderObject(BuildContext context) => _RenderFairRow();
}

class _FairRowData extends ContainerBoxParentData<RenderBox> {}

class _RenderFairRow extends RenderBox
    with
        ContainerRenderObjectMixin<RenderBox, _FairRowData>,
        RenderBoxContainerDefaultsMixin<RenderBox, _FairRowData> {
  @override
  void setupParentData(RenderBox child) {
    if (child.parentData is! _FairRowData) child.parentData = _FairRowData();
  }

  Iterable<RenderBox> get _children sync* {
    for (var child = firstChild; child != null; child = childAfter(child)) {
      yield child;
    }
  }

  /// The widest each tab is laid out, for room [room] wide: as wide as each
  /// would be, or, where they are wider together, the width at which the
  /// tabs no wider than it and the rest at it fill the room.
  static double _cap(Iterable<double> widths, double room) {
    final sorted = widths.toList()..sort();
    var left = room;
    for (var i = 0; i < sorted.length; i++) {
      final share = left / (sorted.length - i);
      if (sorted[i] > share) return share;
      left -= sorted[i];
    }
    return double.infinity;
  }

  /// Each tab's width for [constraints].
  List<double> _widths(BoxConstraints constraints) {
    final natural = <double>[
      for (final child in _children)
        child.getMaxIntrinsicWidth(double.infinity),
    ];
    final cap = _cap(natural, constraints.maxWidth);
    return <double>[for (final width in natural) math.min(width, cap)];
  }

  @override
  double computeMinIntrinsicWidth(double height) => 0;

  @override
  double computeMaxIntrinsicWidth(double height) => _children.fold(
    0,
    (sum, child) => sum + child.getMaxIntrinsicWidth(height),
  );

  @override
  double computeMinIntrinsicHeight(double width) => _children.fold(
    0,
    (most, child) => math.max(most, child.getMinIntrinsicHeight(width)),
  );

  @override
  double computeMaxIntrinsicHeight(double width) => _children.fold(
    0,
    (most, child) => math.max(most, child.getMaxIntrinsicHeight(width)),
  );

  @override
  Size computeDryLayout(BoxConstraints constraints) {
    final widths = _widths(constraints);
    var height = 0.0;
    var i = 0;
    for (final child in _children) {
      height = math.max(
        height,
        child.getDryLayout(_along(widths[i++], constraints)).height,
      );
    }
    return constraints.constrain(
      Size(widths.fold(0, (sum, width) => sum + width), height),
    );
  }

  static BoxConstraints _along(double width, BoxConstraints constraints) =>
      BoxConstraints(maxWidth: width, maxHeight: constraints.maxHeight);

  @override
  void performLayout() {
    final widths = _widths(constraints);
    var height = 0.0;
    var i = 0;
    for (final child in _children) {
      child.layout(_along(widths[i++], constraints), parentUsesSize: true);
      height = math.max(height, child.size.height);
    }
    size = constraints.constrain(
      Size(_children.fold(0, (sum, child) => sum + child.size.width), height),
    );
    var x = 0.0;
    for (final child in _children) {
      (child.parentData! as _FairRowData).offset = Offset(
        x,
        (size.height - child.size.height) / 2,
      );
      x += child.size.width;
    }
  }

  @override
  bool hitTestChildren(BoxHitTestResult result, {required Offset position}) =>
      defaultHitTestChildren(result, position: position);

  @override
  void paint(PaintingContext context, Offset offset) =>
      defaultPaint(context, offset);
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
