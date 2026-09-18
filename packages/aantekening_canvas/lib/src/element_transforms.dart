/// Moving, resizing and rotating page objects.
library;

import 'dart:math' as math;

import 'package:aantekening_core/aantekening_core.dart';
import 'package:flutter/widgets.dart';

import 'selection_handles.dart';

/// Geometry for the selection tool, the same for every kind of object.
///
/// A text box is never scaled: resizing changes its width and rotation turns
/// it, but its font stays the size it was. Ink has no frame of its own to turn
/// or stretch, so transforms are baked into its strokes.
abstract final class ElementTransforms {
  /// Within this angle of upright or sideways, a rotation snaps to it.
  static const double quarterSnap = 6 * math.pi / 180;

  /// Within this angle of a diagonal, a rotation snaps to it.
  static const double diagonalSnap = 3 * math.pi / 180;

  /// The step a rotation moves in while Shift is held.
  static const double fineStep = 15 * math.pi / 180;

  /// Resizes [original] on its own by dragging [handle] [delta] page units.
  ///
  /// The drag is measured along the element's own axes, so the handles of a
  /// turned picture behave as they would if it were upright. A corner keeps
  /// a picture's proportions; a side stretches it in that direction alone.
  ///
  /// [height] is the height the element has now, for one whose height
  /// follows its content: a text box reflows as it is resized, and is kept
  /// at the height its text needs, hanging from the same top edge.
  static NoteElement resize(
    NoteElement original,
    SelectionHandle handle,
    Offset delta, {
    double? height,
  }) {
    if (handle == SelectionHandle.rotate) return original;
    final behavior = SelectionHandles.behaviorOf(original);

    if (original is InkElement) {
      final bounds = original.bounds;
      final start = Frame(
        x: bounds.left,
        y: bounds.top,
        width: bounds.width,
        height: bounds.height,
      );
      if (start.width <= 0 && start.height <= 0) return original;
      final resized = SelectionHandles.resize(start, handle, delta, behavior);
      // A single straight stroke has no extent across itself to scale.
      final scaleX = start.width > 0 ? resized.width / start.width : 1.0;
      final scaleY = start.height > 0 ? resized.height / start.height : 1.0;
      return original.transformed(
        Affine2D.translation(resized.x, resized.y) *
            Affine2D.scaling(scaleX, scaleY) *
            Affine2D.translation(-start.x, -start.y),
      );
    }

    final frame = original.frame;
    final local = _rotate(delta, -frame.rotation);
    final start = Frame(
      x: -frame.width / 2,
      y: -frame.height / 2,
      width: frame.width,
      height: frame.height,
    );
    final resized = SelectionHandles.resize(start, handle, local, behavior);
    final center =
        Offset(frame.centerX, frame.centerY) +
        _rotate(
          Offset(resized.x + resized.width / 2, resized.y + resized.height / 2),
          frame.rotation,
        );
    var result = Frame(
      x: center.dx - resized.width / 2,
      y: center.dy - resized.height / 2,
      width: resized.width,
      height: resized.height,
      rotation: frame.rotation,
    );
    if (height != null && behavior == ResizeBehavior.horizontal) {
      result = result.resizedFromTopLeft(result.width, height);
    }
    return _stretched(original.withFrame(result), handle.isSide);
  }

  /// Scales [element] by [factor] about [anchor], as part of a group.
  ///
  /// Positions scale with the group so its layout is kept; a text box widens
  /// or narrows but keeps its font, and its height follows its text.
  static NoteElement scale(NoteElement element, double factor, Offset anchor) =>
      stretch(element, factor, factor, anchor);

  /// Scales [element] by [scaleX] across and [scaleY] down the page, about
  /// [anchor], as part of a group dragged by a side.
  ///
  /// A turned element keeps its angle, and is stretched along its own sides
  /// by as much as the group stretches in their directions.
  static NoteElement stretch(
    NoteElement element,
    double scaleX,
    double scaleY,
    Offset anchor,
  ) {
    if (element is InkElement) {
      return element.transformed(
        Affine2D.scalingAbout(scaleX, scaleY, anchor.dx, anchor.dy),
      );
    }
    final frame = element.frame;
    final offset = Offset(frame.centerX, frame.centerY) - anchor;
    final center = anchor + Offset(offset.dx * scaleX, offset.dy * scaleY);
    final cos = math.cos(frame.rotation);
    final sin = math.sin(frame.rotation);
    // How far the group's stretch lengthens each of the element's own sides.
    final alongWidth = math.sqrt(
      math.pow(scaleX * cos, 2) + math.pow(scaleY * sin, 2),
    );
    final alongHeight = math.sqrt(
      math.pow(scaleX * sin, 2) + math.pow(scaleY * cos, 2),
    );
    final width = element is TextElement
        ? math.max(SelectionHandles.minTextWidth, frame.width * alongWidth)
        : frame.width * alongWidth;
    final height = element is TextElement
        ? frame.height
        : frame.height * alongHeight;
    final stretched = element.withFrame(
      Frame(
        x: center.dx - width / 2,
        y: center.dy - height / 2,
        width: width,
        height: height,
        rotation: frame.rotation,
      ),
    );
    return _stretched(stretched, (alongWidth - alongHeight).abs() > 1e-9);
  }

  /// A picture whose frame was stretched out of its proportions fills the
  /// frame, rather than sitting in the middle of it at the old shape.
  static NoteElement _stretched(NoteElement element, bool outOfProportion) =>
      outOfProportion && element is ImageElement
      ? element.copyWith(fit: MediaFit.stretch)
      : element;

  /// Turns [element] by [angle] radians clockwise about [pivot].
  static NoteElement rotate(NoteElement element, double angle, Offset pivot) {
    if (element is InkElement) {
      return element.transformed(
        Affine2D.rotationAbout(angle, pivot.dx, pivot.dy),
      );
    }
    final frame = element.frame;
    final center =
        pivot + _rotate(Offset(frame.centerX, frame.centerY) - pivot, angle);
    return element.withFrame(
      frame
          .centeredAt(center.dx, center.dy)
          .copyWith(rotation: normalize(frame.rotation + angle)),
    );
  }

  /// Snaps an absolute rotation: to upright, sideways and upside down when
  /// close, then more weakly to the diagonals; with [fine], to every 15°.
  static double snapRotation(double radians, {bool fine = false}) {
    final angle = normalize(radians);
    if (fine) return normalize((angle / fineStep).round() * fineStep);
    const quarter = math.pi / 2;
    final nearestQuarter = (angle / quarter).round() * quarter;
    if ((angle - nearestQuarter).abs() <= quarterSnap) {
      return normalize(nearestQuarter);
    }
    const eighth = math.pi / 4;
    final nearestEighth = (angle / eighth).round() * eighth;
    if ((angle - nearestEighth).abs() <= diagonalSnap) {
      return normalize(nearestEighth);
    }
    return angle;
  }

  /// [radians] wrapped into (−π, π], with values within a hair of zero made
  /// exactly zero so a snapped upright frame stores no rotation at all.
  static double normalize(double radians) {
    var angle = radians % (2 * math.pi);
    if (angle > math.pi) angle -= 2 * math.pi;
    if (angle.abs() < 1e-9) return 0;
    return angle;
  }

  static Offset _rotate(Offset vector, double radians) {
    if (radians == 0) return vector;
    final cos = math.cos(radians);
    final sin = math.sin(radians);
    return Offset(
      vector.dx * cos - vector.dy * sin,
      vector.dx * sin + vector.dy * cos,
    );
  }
}
