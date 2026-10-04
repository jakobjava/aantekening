/// The rows of the navigation panes as trees: indented to their depth,
/// joined to their parents by lines, and collapsed by a click on a line.
library;

import 'package:aantekening_core/aantekening_core.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../look/marks.dart';
import '../look/tones.dart';
import '../preferences.dart';

/// The ids of some rows, remembered between sessions.
class RememberedRows extends Notifier<Set<String>> {
  RememberedRows(this._key);

  final String _key;

  @override
  Set<String> build() => <String>{
    if (ref.preference(_key) case final List<Object?> ids)
      ...ids.whereType<String>(),
  };

  /// Takes [id] out if it is in, and puts it in if it is not.
  void toggle(String id) => _set(
    state.contains(id)
        ? state.difference(<String>{id})
        : <String>{...state, id},
  );

  /// Puts [ids] in.
  void add(Iterable<String> ids) {
    final more = state.union(ids.toSet());
    if (more.length != state.length) _set(more);
  }

  /// Takes [ids] out.
  void remove(Iterable<String> ids) {
    final fewer = state.difference(ids.toSet());
    if (fewer.length != state.length) _set(fewer);
  }

  void _set(Set<String> ids) {
    state = ids;
    ref.savePreference(_key, ids.isEmpty ? null : ids.toList());
  }
}

/// The rows collapsed to hide what lies beneath them: the sections and
/// pages, which show it otherwise, and the notebooks collapsed while open.
final collapsedRowsProvider = NotifierProvider<RememberedRows, Set<String>>(
  () => RememberedRows('library.collapsed'),
);

/// The notebooks expanded to show their sections — those opened, until
/// collapsed again, as many at once as wanted. The rest show only their
/// names, so a long list of notebooks stays short, but for the one open,
/// unless it was collapsed.
final expandedNotebooksProvider = NotifierProvider<RememberedRows, Set<String>>(
  () => RememberedRows('library.expandedNotebooks'),
);

/// A row above another in a tree, and whether its line goes on down past
/// that row, to a later child.
typedef TreeAncestor = ({String id, bool continues});

/// Where a row stands in a tree: beneath which rows, and whether its own
/// children show.
@immutable
class TreePlace {
  const TreePlace({
    required this.id,
    this.ancestors = const <TreeAncestor>[],
    this.expanded,
  });

  /// The id of the row's item.
  final String id;

  /// The rows this one lies beneath, from the top down.
  final List<TreeAncestor> ancestors;

  /// Whether the row's children show beneath it, or null for a row without
  /// any.
  final bool? expanded;

  int get depth => ancestors.length;
}

/// The rows of [tree] that show, in order, each with its place: what lies
/// beneath a [collapsed] row is left out. Every row lies beneath [root], a
/// row of another tree, if one is given.
List<({T item, TreePlace place})> treeRows<T>(
  Hierarchy<T> tree,
  Set<String> collapsed, {
  String? root,
}) {
  final rows = <({T item, TreePlace place})>[];
  final above = root == null ? 0 : 1;
  final path = <TreeAncestor>[if (root != null) (id: root, continues: false)];
  bool expanded(String id) => !collapsed.contains(id);

  for (final entry in tree.walk(expanded: expanded)) {
    path.removeRange(entry.depth + above, path.length);
    if (path.isNotEmpty) path.last = (id: path.last.id, continues: !entry.last);
    rows.add((
      item: entry.item,
      place: TreePlace(
        id: entry.id,
        ancestors: List<TreeAncestor>.unmodifiable(path),
        expanded: tree.hasChildren(entry.id) ? expanded(entry.id) : null,
      ),
    ));
    path.add((id: entry.id, continues: false));
  }
  return rows;
}

/// Shares among the [TreeRow]s beneath it which row's line the pointer is
/// on, so that line lights up along its whole length, past every row it
/// passes.
class TreeLines extends StatefulWidget {
  const TreeLines({required this.child, super.key});

  final Widget child;

  static ValueNotifier<String?> _hoveredOf(BuildContext context) =>
      context.getInheritedWidgetOfExactType<_TreeLinesScope>()!.hovered;

  @override
  State<TreeLines> createState() => _TreeLinesState();
}

class _TreeLinesState extends State<TreeLines> {
  final ValueNotifier<String?> _hovered = ValueNotifier<String?>(null);

  @override
  void dispose() {
    _hovered.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) =>
      _TreeLinesScope(hovered: _hovered, child: widget.child);
}

class _TreeLinesScope extends InheritedWidget {
  const _TreeLinesScope({required this.hovered, required super.child});

  final ValueNotifier<String?> hovered;

  @override
  bool updateShouldNotify(_TreeLinesScope oldWidget) =>
      hovered != oldWidget.hovered;
}

/// A row of a tree: [child] indented to the row's depth, beside the lines
/// joining it to the rows around it, with a chevron when it has children.
///
/// Each line comes down from a row with children to them. Clicking a line,
/// or a row's chevron, calls [onToggle] with the id of the row it belongs
/// to, to collapse or expand that row.
class TreeRow extends StatelessWidget {
  const TreeRow({
    required this.place,
    required this.onToggle,
    required this.child,
    super.key,
  });

  /// How far each level is indented, and so how far apart the lines are.
  static const double indent = 18;

  /// How far the row's content is inset from where it starts: clear of
  /// the line branching to it, and of the edge marking it chosen.
  static const EdgeInsetsGeometry tilePadding = EdgeInsetsDirectional.fromSTEB(
    8,
    5,
    8,
    5,
  );

  final TreePlace place;
  final ValueChanged<String> onToggle;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    final tones = context.tones;
    final hovered = TreeLines._hoveredOf(context);
    final lead = (place.depth + 1) * indent;

    Widget target(String id, {Widget? child}) => MouseRegion(
      cursor: SystemMouseCursors.click,
      onEnter: (_) => hovered.value = id,
      onExit: (_) {
        if (hovered.value == id) hovered.value = null;
      },
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: () {
          // The rows the line passed may be gone once it is collapsed, and
          // with them the chance to hear that the pointer left it.
          hovered.value = null;
          onToggle(id);
        },
        child: child,
      ),
    );

    return Stack(
      children: <Widget>[
        Padding(
          padding: EdgeInsetsDirectional.only(start: lead),
          child: child,
        ),
        PositionedDirectional(
          start: 0,
          top: 0,
          bottom: 0,
          width: lead,
          child: CustomPaint(
            painter: _TreeLinePainter(
              place: place,
              hovered: hovered,
              color: tones.line,
              highlight: tones.emphasis,
              textDirection: Directionality.of(context),
            ),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: <Widget>[
                for (final (level, ancestor) in place.ancestors.indexed)
                  SizedBox(
                    width: indent,
                    child: level == place.depth - 1 || ancestor.continues
                        ? target(ancestor.id)
                        : null,
                  ),
                SizedBox(
                  width: indent,
                  child: switch (place.expanded) {
                    null => null,
                    final expanded => Semantics(
                      button: true,
                      label: expanded ? 'Collapse' : 'Expand',
                      child: target(
                        place.id,
                        child: RotatedBox(
                          quarterTurns: expanded ? 1 : 0,
                          child: Center(
                            child: Mark(
                              MarkShape.chevronRight,
                              size: 10,
                              color: tones.muted,
                            ),
                          ),
                        ),
                      ),
                    ),
                  },
                ),
              ],
            ),
          ),
        ),
      ],
    );
  }
}

/// Paints the lines beside a row: those of its ancestors passing it, the
/// branch from its parent's line to it, and the start of its own line down
/// to its children.
class _TreeLinePainter extends CustomPainter {
  _TreeLinePainter({
    required this.place,
    required this.hovered,
    required this.color,
    required this.highlight,
    required this.textDirection,
  }) : super(repaint: hovered);

  static const double chevronSize = 12;

  final TreePlace place;
  final ValueNotifier<String?> hovered;
  final Color color;
  final Color highlight;
  final TextDirection textDirection;

  @override
  void paint(Canvas canvas, Size size) {
    const indent = TreeRow.indent;
    final middle = size.height / 2;
    final depth = place.depth;
    // Lines are drawn left to right and mirrored for right-to-left text.
    double x(double offset) =>
        textDirection == TextDirection.ltr ? offset : size.width - offset;
    double centreOf(int level) => x(level * indent + indent / 2);
    Paint paintFor(String id) => Paint()
      ..color = hovered.value == id ? highlight : color
      ..strokeWidth = 1
      ..style = PaintingStyle.stroke;

    for (final (level, ancestor) in place.ancestors.indexed) {
      final line = centreOf(level);
      final paint = paintFor(ancestor.id);
      if (level < depth - 1) {
        if (ancestor.continues) {
          canvas.drawLine(Offset(line, 0), Offset(line, size.height), paint);
        }
        continue;
      }
      // The branch into this row, ending at its chevron or else at the
      // start of its content.
      final end = x(
        place.expanded == null
            ? (depth + 1) * indent
            : depth * indent + (indent - chevronSize) / 2,
      );
      final branch = Path()..moveTo(line, 0);
      if (ancestor.continues) {
        branch
          ..lineTo(line, size.height)
          ..moveTo(line, middle);
      } else {
        // The line ends here, turning into this row at a right angle.
        branch.lineTo(line, middle);
      }
      canvas.drawPath(branch..lineTo(end, middle), paint);
    }

    if (place.expanded ?? false) {
      final line = centreOf(depth);
      canvas.drawLine(
        Offset(line, middle + chevronSize / 2),
        Offset(line, size.height),
        paintFor(place.id),
      );
    }
  }

  @override
  bool shouldRepaint(_TreeLinePainter oldDelegate) =>
      place != oldDelegate.place ||
      hovered != oldDelegate.hovered ||
      color != oldDelegate.color ||
      highlight != oldDelegate.highlight ||
      textDirection != oldDelegate.textDirection;
}
