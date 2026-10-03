/// Something that cannot wrap, made smaller where it would not fit.
library;

import 'package:flutter/rendering.dart';
import 'package:flutter/widgets.dart';

/// [child] at its own size, or scaled down to the width there is where it is
/// wider: a formula in a narrow box or a table's column, which cannot wrap
/// as words do.
///
/// Its baseline is scaled with it, so a formula made smaller still sits on
/// the line of the text around it.
class ShrinkToWidth extends SingleChildRenderObjectWidget {
  const ShrinkToWidth({required super.child, super.key});

  @override
  RenderShrinkToWidth createRenderObject(BuildContext context) =>
      RenderShrinkToWidth();
}

class RenderShrinkToWidth extends RenderProxyBox {
  /// How much the child is scaled down by: 1 where it fits.
  double _scale = 1;

  /// The child's constraints: as wide as it likes.
  static BoxConstraints _free(BoxConstraints constraints) =>
      constraints.copyWith(minWidth: 0, maxWidth: double.infinity);

  /// How much a child [natural] wide is scaled down by within [constraints].
  static double _scaleIn(BoxConstraints constraints, double natural) =>
      natural > constraints.maxWidth && natural > 0
      ? constraints.maxWidth / natural
      : 1;

  @override
  Size computeDryLayout(BoxConstraints constraints) {
    final child = this.child;
    if (child == null) return constraints.smallest;
    final natural = child.getDryLayout(_free(constraints));
    return constraints.constrain(
      natural * _scaleIn(constraints, natural.width),
    );
  }

  @override
  void performLayout() {
    final child = this.child;
    if (child == null) {
      size = constraints.smallest;
      return;
    }
    child.layout(_free(constraints), parentUsesSize: true);
    final natural = child.size;
    _scale = _scaleIn(constraints, natural.width);
    size = constraints.constrain(natural * _scale);
  }

  /// Where the baseline falls, measured without laying out — as text is
  /// measured in a table's cell to size its column — taken as the foot of
  /// the child: a formula cannot say where its baseline is until it is
  /// laid out, and asked, its typesetter fails. Laid out, it sits on its
  /// own baseline ([computeDistanceToActualBaseline]).
  @override
  double? computeDryBaseline(
    BoxConstraints constraints,
    TextBaseline baseline,
  ) => child == null ? null : computeDryLayout(constraints).height;

  @override
  double? computeDistanceToActualBaseline(TextBaseline baseline) {
    final distance = child?.getDistanceToActualBaseline(baseline);
    return distance == null ? null : distance * _scale;
  }

  @override
  void paint(PaintingContext context, Offset offset) {
    final child = this.child;
    if (child == null) return;
    if (_scale == 1) {
      context.paintChild(child, offset);
      return;
    }
    layer = context.pushTransform(
      needsCompositing,
      offset,
      Matrix4.diagonal3Values(_scale, _scale, 1),
      (context, offset) => context.paintChild(child, offset),
      oldLayer: layer is TransformLayer ? layer! as TransformLayer : null,
    );
  }

  @override
  bool hitTestChildren(BoxHitTestResult result, {required Offset position}) {
    final child = this.child;
    if (child == null) return false;
    return result.addWithPaintTransform(
      transform: Matrix4.diagonal3Values(_scale, _scale, 1),
      position: position,
      hitTest: (result, position) => child.hitTest(result, position: position),
    );
  }

  @override
  void applyPaintTransform(RenderBox child, Matrix4 transform) {
    transform.scaleByDouble(_scale, _scale, 1, 1);
  }
}
