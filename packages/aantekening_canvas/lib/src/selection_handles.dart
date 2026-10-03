/// The selection box: its shape, its handles, and what dragging them does.
library;

import 'dart:math' as math;

import 'package:aantekening_core/aantekening_core.dart';
import 'package:flutter/widgets.dart';

import 'canvas_viewport.dart';

/// How a selection may be resized.
enum ResizeBehavior {
  /// Not resizable.
  none,

  /// Width only; the height follows the content. Text boxes behave this way,
  /// as OneNote text containers do, so resizing one never changes its font.
  horizontal,

  /// Both axes together from a corner, keeping the aspect ratio, so pictures,
  /// PDF pages and handwriting do not distort unless a side is dragged; a
  /// side stretches them in its own direction only.
  proportional,
}

/// A grab point on the selection box.
enum SelectionHandle {
  topLeft,
  topRight,
  bottomLeft,
  bottomRight,
  left,
  right,
  top,
  bottom,

  /// The knob above the box that turns it.
  rotate;

  /// Whether this is the middle of a side, which resizes in one direction
  /// only. The whole side can be dragged, not just its handle.
  bool get isSide =>
      this == left || this == right || this == top || this == bottom;

  /// Whether dragging this handle moves the box's left edge.
  bool get movesLeft => this == topLeft || this == bottomLeft || this == left;

  /// Whether dragging this handle moves the box's top edge.
  bool get movesTop => this == topLeft || this == topRight || this == top;
}

/// The box drawn around a selection: a rectangle in page space, turned by
/// [rotation] about its centre.
///
/// One element is framed exactly, rotation included. Several are framed by the
/// upright box around all of them, which is what turns and scales as a group.
@immutable
class SelectionFrame {
  const SelectionFrame({
    required this.center,
    required this.width,
    required this.height,
    this.rotation = 0,
  });

  /// The frame around [elements], or null when there are none.
  static SelectionFrame? around(List<NoteElement> elements) {
    if (elements.isEmpty) return null;
    if (elements.length == 1 && elements.single is! InkElement) {
      final frame = elements.single.frame;
      return SelectionFrame(
        center: Offset(frame.centerX, frame.centerY),
        width: frame.width,
        height: frame.height,
        rotation: frame.rotation,
      );
    }
    // Ink is framed by its strokes; its geometry has no rotation of its own.
    final bounds = NoteElement.boundsOf(elements);
    return SelectionFrame(
      center: Offset(bounds.centerX, bounds.centerY),
      width: bounds.width,
      height: bounds.height,
    );
  }

  final Offset center;
  final double width;
  final double height;
  final double rotation;

  /// Maps a point in the frame's own coordinates, (0, 0) at its unrotated
  /// top-left corner, to page space.
  Offset toPage(Offset local) {
    final dx = local.dx - width / 2;
    final dy = local.dy - height / 2;
    final cos = math.cos(rotation);
    final sin = math.sin(rotation);
    return center + Offset(dx * cos - dy * sin, dx * sin + dy * cos);
  }

  /// The page-space position of [handle]'s anchor point on the frame.
  Offset anchorOf(SelectionHandle handle) => toPage(switch (handle) {
    SelectionHandle.topLeft => Offset.zero,
    SelectionHandle.topRight => Offset(width, 0),
    SelectionHandle.bottomLeft => Offset(0, height),
    SelectionHandle.bottomRight => Offset(width, height),
    SelectionHandle.left => Offset(0, height / 2),
    SelectionHandle.right => Offset(width, height / 2),
    SelectionHandle.top || SelectionHandle.rotate => Offset(width / 2, 0),
    SelectionHandle.bottom => Offset(width / 2, height),
  });

  /// The corner or edge that stays put while [handle] is dragged.
  Offset oppositeOf(SelectionHandle handle) => anchorOf(switch (handle) {
    SelectionHandle.topLeft => SelectionHandle.bottomRight,
    SelectionHandle.topRight => SelectionHandle.bottomLeft,
    SelectionHandle.bottomLeft => SelectionHandle.topRight,
    SelectionHandle.bottomRight => SelectionHandle.topLeft,
    SelectionHandle.left => SelectionHandle.right,
    SelectionHandle.right => SelectionHandle.left,
    SelectionHandle.top => SelectionHandle.bottom,
    SelectionHandle.bottom => SelectionHandle.top,
    SelectionHandle.rotate => SelectionHandle.rotate,
  });

  /// Whether [page] lies inside the frame.
  bool contains(Offset page) => Frame(
    x: center.dx - width / 2,
    y: center.dy - height / 2,
    width: width,
    height: height,
    rotation: rotation,
  ).containsPoint(page.dx, page.dy);

  /// The four corners in page space, clockwise from the top-left.
  List<Offset> get corners => <Offset>[
    toPage(Offset.zero),
    toPage(Offset(width, 0)),
    toPage(Offset(width, height)),
    toPage(Offset(0, height)),
  ];

  @override
  bool operator ==(Object other) =>
      other is SelectionFrame &&
      other.center == center &&
      other.width == width &&
      other.height == height &&
      other.rotation == rotation;

  @override
  int get hashCode => Object.hash(center, width, height, rotation);
}

/// Geometry shared by the selection painter and the canvas's input handling,
/// so that what is drawn and what can be grabbed never disagree.
abstract final class SelectionHandles {
  /// Side length of a drawn handle, in screen pixels.
  static const double size = 8;

  /// How far from a handle's centre a press still grabs it, in screen pixels.
  static const double mouseReach = 7;

  /// Touch needs a larger target than a mouse pointer.
  static const double touchReach = 16;

  /// Gap between the selected content and the box drawn round it, in screen
  /// pixels.
  static const double outlineInset = 3;

  /// How far above the box the rotation knob sits, in screen pixels.
  static const double rotateKnobDistance = 24;

  /// The smallest size a resize may produce, in page units.
  static const double minExtent = 16;

  /// The narrowest a text box may become, in page units.
  static const double minTextWidth = 60;

  /// How one [element] on its own may be resized.
  static ResizeBehavior behaviorOf(NoteElement element) => switch (element) {
    TextElement() => ResizeBehavior.horizontal,
    ImageElement() ||
    PdfElement() ||
    TikzElement() ||
    InkElement() => ResizeBehavior.proportional,
  };

  /// How [selection] may be resized. Several elements scale together,
  /// keeping their proportions and the layout between them.
  static ResizeBehavior behaviorOfSelection(List<NoteElement> selection) =>
      switch (selection.length) {
        0 => ResizeBehavior.none,
        1 => behaviorOf(selection.single),
        _ => ResizeBehavior.proportional,
      };

  /// The handles [selection] offers: the corners, where it resizes in both
  /// directions, and the sides, where it resizes in one.
  static List<SelectionHandle> handlesOf(List<NoteElement> selection) {
    if (selection.isEmpty) return const <SelectionHandle>[];
    final handles = switch (behaviorOfSelection(selection)) {
      ResizeBehavior.none => <SelectionHandle>[],
      ResizeBehavior.horizontal => <SelectionHandle>[
        SelectionHandle.left,
        SelectionHandle.right,
      ],
      ResizeBehavior.proportional => <SelectionHandle>[
        SelectionHandle.topLeft,
        SelectionHandle.topRight,
        SelectionHandle.bottomLeft,
        SelectionHandle.bottomRight,
        SelectionHandle.left,
        SelectionHandle.right,
        SelectionHandle.top,
        SelectionHandle.bottom,
      ],
    };
    return <SelectionHandle>[...handles, SelectionHandle.rotate];
  }

  /// The corners of the box drawn round [frame], in screen space, pushed out
  /// by [outlineInset] so the outline never covers what it frames.
  static List<Offset> outlineOf(SelectionFrame frame, CanvasViewport viewport) {
    final inset = outlineInset / viewport.zoom;
    final padded = SelectionFrame(
      center: frame.center,
      width: frame.width + inset * 2,
      height: frame.height + inset * 2,
      rotation: frame.rotation,
    );
    // Moved whole with what it frames, on sheets.
    return <Offset>[
      for (final corner in padded.corners)
        viewport.toScreenWith(corner, frame.center),
    ];
  }

  /// The handles that resize something in both directions: its corners,
  /// and its sides.
  static const List<SelectionHandle> resizing = <SelectionHandle>[
    SelectionHandle.topLeft,
    SelectionHandle.topRight,
    SelectionHandle.bottomLeft,
    SelectionHandle.bottomRight,
    SelectionHandle.left,
    SelectionHandle.right,
    SelectionHandle.top,
    SelectionHandle.bottom,
  ];

  /// The screen-space centre of each handle [selection] offers.
  static Map<SelectionHandle, Offset> positionsFor(
    List<NoteElement> selection,
    CanvasViewport viewport,
  ) {
    final frame = SelectionFrame.around(selection);
    if (frame == null) return const <SelectionHandle, Offset>{};
    return positionsOn(
      outlineOf(frame, viewport),
      handlesOf(selection),
      rotation: frame.rotation,
    );
  }

  /// The centre of each of [handles] on the box whose corners are
  /// [outline], clockwise from the top-left, turned by [rotation].
  static Map<SelectionHandle, Offset> positionsOn(
    List<Offset> outline,
    Iterable<SelectionHandle> handles, {
    double rotation = 0,
  }) {
    final [topLeft, topRight, bottomRight, bottomLeft] = outline;
    final topMid = (topLeft + topRight) / 2;
    final up = Offset(math.sin(rotation), -math.cos(rotation));
    return <SelectionHandle, Offset>{
      for (final handle in handles)
        handle: switch (handle) {
          SelectionHandle.topLeft => topLeft,
          SelectionHandle.topRight => topRight,
          SelectionHandle.bottomLeft => bottomLeft,
          SelectionHandle.bottomRight => bottomRight,
          SelectionHandle.left => (topLeft + bottomLeft) / 2,
          SelectionHandle.right => (topRight + bottomRight) / 2,
          SelectionHandle.top => topMid,
          SelectionHandle.bottom => (bottomLeft + bottomRight) / 2,
          SelectionHandle.rotate => topMid + up * rotateKnobDistance,
        },
    };
  }

  /// The screen-space ends of each side of the box round [selection] that can
  /// be dragged.
  static Map<SelectionHandle, (Offset, Offset)> sidesFor(
    List<NoteElement> selection,
    CanvasViewport viewport,
  ) {
    final frame = SelectionFrame.around(selection);
    if (frame == null) return const <SelectionHandle, (Offset, Offset)>{};
    return sidesOn(outlineOf(frame, viewport), handlesOf(selection));
  }

  /// The ends of each side among [handles] of the box whose corners are
  /// [outline].
  static Map<SelectionHandle, (Offset, Offset)> sidesOn(
    List<Offset> outline,
    Iterable<SelectionHandle> handles,
  ) => <SelectionHandle, (Offset, Offset)>{
    for (final handle in handles)
      if (handle.isSide)
        handle: switch (handle) {
          SelectionHandle.left => (outline[0], outline[3]),
          SelectionHandle.right => (outline[1], outline[2]),
          SelectionHandle.top => (outline[0], outline[1]),
          _ => (outline[3], outline[2]),
        },
  };

  /// The handle of [selection] within [reach] of a screen point, if any: a
  /// handle itself, or anywhere along a side that can be dragged.
  static SelectionHandle? hitTest(
    List<NoteElement> selection,
    CanvasViewport viewport,
    Offset screen, {
    double reach = mouseReach,
  }) => hitTestOn(
    positionsFor(selection, viewport),
    sidesFor(selection, viewport),
    screen,
    reach: reach,
  );

  /// Which of the handles at [positions], or the [sides] that can be
  /// dragged, lies within [reach] of [point]: the handles first.
  static SelectionHandle? hitTestOn(
    Map<SelectionHandle, Offset> positions,
    Map<SelectionHandle, (Offset, Offset)> sides,
    Offset point, {
    double reach = mouseReach,
  }) {
    SelectionHandle? best;
    var bestDistance = reach;
    for (final entry in positions.entries) {
      final distance = (entry.value - point).distance;
      if (distance <= bestDistance) {
        best = entry.key;
        bestDistance = distance;
      }
    }
    if (best != null) return best;
    for (final entry in sides.entries) {
      final (from, to) = entry.value;
      final distance = _distanceToSegment(point, from, to);
      if (distance <= bestDistance) {
        best = entry.key;
        bestDistance = distance;
      }
    }
    return best;
  }

  /// A resize cursor pointing the way [handle] drags, turned with the box
  /// by [rotation].
  static MouseCursor cursorFor(SelectionHandle handle, double rotation) {
    final base = switch (handle) {
      SelectionHandle.rotate => null,
      SelectionHandle.left || SelectionHandle.right => 0.0,
      SelectionHandle.top || SelectionHandle.bottom => math.pi / 2,
      SelectionHandle.topLeft || SelectionHandle.bottomRight => math.pi / 4,
      SelectionHandle.topRight || SelectionHandle.bottomLeft => -math.pi / 4,
    };
    if (base == null) return SystemMouseCursors.grab;
    final octant = (((base + rotation) / (math.pi / 4)).round()) % 4;
    return switch (octant) {
      0 => SystemMouseCursors.resizeLeftRight,
      1 => SystemMouseCursors.resizeUpLeftDownRight,
      2 => SystemMouseCursors.resizeUpDown,
      _ => SystemMouseCursors.resizeUpRightDownLeft,
    };
  }

  /// Draws the box whose corners are [outline] in [accent], in screen
  /// pixels.
  static void paintOutline(Canvas canvas, List<Offset> outline, Color accent) =>
      canvas.drawPath(
        Path()..addPolygon(outline, true),
        Paint()
          ..color = accent
          ..style = PaintingStyle.stroke
          ..strokeWidth = 1.5,
      );

  /// Draws the resize handles at [positions] in [accent], in screen pixels,
  /// turned with the box by [rotation]: a square at a corner, a bar along a
  /// side. The rotation knob is the canvas's own.
  static void paintHandles(
    Canvas canvas,
    Map<SelectionHandle, Offset> positions,
    Color accent, {
    double rotation = 0,
  }) {
    final fill = Paint()..color = accent;
    final ring = Paint()
      ..color = const Color(0xFFFFFFFF)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.5;
    for (final MapEntry(key: handle, value: at) in positions.entries) {
      if (handle == SelectionHandle.rotate) continue;
      final upright =
          handle == SelectionHandle.left || handle == SelectionHandle.right;
      // Handles turn with the box, so a side's bar always lies along it.
      canvas
        ..save()
        ..translate(at.dx, at.dy)
        ..rotate(rotation);
      final rect = Rect.fromCenter(
        center: Offset.zero,
        width: handle.isSide && !upright ? size * 2.5 : size,
        height: upright ? size * 2.5 : size,
      );
      canvas
        ..drawRect(rect, fill)
        ..drawRect(rect, ring)
        ..restore();
    }
  }

  static double _distanceToSegment(Offset point, Offset from, Offset to) {
    final along = to - from;
    final lengthSquared = along.distanceSquared;
    if (lengthSquared == 0) return (point - from).distance;
    final t =
        (((point.dx - from.dx) * along.dx + (point.dy - from.dy) * along.dy) /
                lengthSquared)
            .clamp(0.0, 1.0);
    return (point - (from + along * t)).distance;
  }

  /// The upright frame produced by dragging [handle] of the upright [start]
  /// by [delta].
  ///
  /// The corner or side opposite the handle stays where it is, which is what
  /// makes a resize feel anchored rather than sliding. A side moves in its
  /// own direction only.
  static Frame resize(
    Frame start,
    SelectionHandle handle,
    Offset delta,
    ResizeBehavior behavior,
  ) {
    switch (behavior) {
      case ResizeBehavior.none:
        return start;
      case ResizeBehavior.horizontal:
        return _resizeHorizontally(start, handle, delta.dx);
      case ResizeBehavior.proportional:
        if (handle.isSide) return _resizeSide(start, handle, delta);
        return _resizeCorner(start, handle, delta);
    }
  }

  static Frame _resizeHorizontally(
    Frame start,
    SelectionHandle handle,
    double dx,
  ) {
    final growsLeft = handle.movesLeft;
    final width = math.max(
      minTextWidth,
      growsLeft ? start.width - dx : start.width + dx,
    );
    return Frame(
      x: growsLeft ? start.x + start.width - width : start.x,
      y: start.y,
      width: width,
      height: start.height,
      rotation: start.rotation,
    );
  }

  /// Moves one side, stretching the frame in that direction alone.
  static Frame _resizeSide(Frame start, SelectionHandle handle, Offset delta) {
    final horizontal =
        handle == SelectionHandle.left || handle == SelectionHandle.right;
    final width = horizontal
        ? math.max(
            minExtent,
            handle.movesLeft ? start.width - delta.dx : start.width + delta.dx,
          )
        : start.width;
    final height = horizontal
        ? start.height
        : math.max(
            minExtent,
            handle.movesTop ? start.height - delta.dy : start.height + delta.dy,
          );
    return Frame(
      x: handle.movesLeft ? start.x + start.width - width : start.x,
      y: handle.movesTop ? start.y + start.height - height : start.y,
      width: width,
      height: height,
      rotation: start.rotation,
    );
  }

  static Frame _resizeCorner(
    Frame start,
    SelectionHandle handle,
    Offset delta,
  ) {
    final left = handle.movesLeft;
    final top = handle.movesTop;

    var width = left ? start.width - delta.dx : start.width + delta.dx;
    var height = top ? start.height - delta.dy : start.height + delta.dy;

    if (start.width > 0 && start.height > 0) {
      // Follow whichever axis the pointer has moved further along, so the
      // corner stays under the pointer as closely as the ratio allows.
      final scale = math.max(width / start.width, height / start.height);
      final minScale = math.max(
        minExtent / start.width,
        minExtent / start.height,
      );
      final clamped = math.max(scale, minScale);
      width = start.width * clamped;
      height = start.height * clamped;
    } else {
      width = math.max(minExtent, width);
      height = math.max(minExtent, height);
    }

    return Frame(
      x: left ? start.x + start.width - width : start.x,
      y: top ? start.y + start.height - height : start.y,
      width: width,
      height: height,
      rotation: start.rotation,
    );
  }
}
