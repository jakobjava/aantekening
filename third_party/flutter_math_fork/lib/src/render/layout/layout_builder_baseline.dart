import 'package:flutter/rendering.dart';
import 'package:flutter/widgets.dart';

class LayoutBuilderPreserveBaseline
    extends ConstrainedLayoutBuilder<BoxConstraints> {
  /// Creates a widget that defers its building until layout.
  ///
  /// The [builder] argument must not be null.
  const LayoutBuilderPreserveBaseline({
    Key? key,
    required LayoutWidgetBuilder builder,
  }) : super(key: key, builder: builder);

  @override
  LayoutWidgetBuilder get builder => super.builder;

  @override
  _RenderLayoutBuilderPreserveBaseline createRenderObject(
          BuildContext context) =>
      _RenderLayoutBuilderPreserveBaseline();
}

class _RenderLayoutBuilderPreserveBaseline extends RenderBox
    with
        RenderObjectWithChildMixin<RenderBox>,
        RenderObjectWithLayoutCallbackMixin,
        RenderConstrainedLayoutBuilder<BoxConstraints, RenderBox> {
  @override
  double? computeDistanceToActualBaseline(TextBaseline baseline) =>
      child?.getDistanceToActualBaseline(baseline);

  @override
  double computeMinIntrinsicWidth(double height) {
    assert(_debugThrowIfNotCheckingIntrinsics());
    return 0.0;
  }

  @override
  double computeMaxIntrinsicWidth(double height) {
    assert(_debugThrowIfNotCheckingIntrinsics());
    return 0.0;
  }

  @override
  double computeMinIntrinsicHeight(double width) {
    assert(_debugThrowIfNotCheckingIntrinsics());
    return 0.0;
  }

  @override
  double computeMaxIntrinsicHeight(double width) {
    assert(_debugThrowIfNotCheckingIntrinsics());
    return 0.0;
  }

  // aantekening: the constraints are what the child is built for — a
  // delimiter as tall as what it encloses — not what it must meet. The
  // largest of a delimiter that cannot be stacked may still be shorter, so
  // the child is laid out loosely, at its own size, within this box.
  @override
  Size computeDryLayout(BoxConstraints constraints) => constraints.constrain(
      child?.getDryLayout(constraints.loosen()) ?? Size.zero);

  @override
  void performLayout() {
    final constraints = this.constraints;
    runLayoutCallback();
    if (child != null) {
      child!.layout(constraints.loosen(), parentUsesSize: true);
      size = constraints.constrain(child!.size);
    } else {
      size = constraints.biggest;
    }
  }

  @override
  bool hitTestChildren(BoxHitTestResult result, {required Offset position}) =>
      child?.hitTest(result, position: position) ?? false;

  @override
  void paint(PaintingContext context, Offset offset) {
    if (child != null) context.paintChild(child!, offset);
  }

  bool _debugThrowIfNotCheckingIntrinsics() {
    assert(() {
      if (!RenderObject.debugCheckingIntrinsics) {
        throw FlutterError(
            'LayoutBuilder does not support returning intrinsic dimensions.\n'
            'Calculating the intrinsic dimensions would require '
            'running the layout '
            'callback speculatively, which might mutate the live '
            'render object tree.');
      }
      return true;
    }());

    return true;
  }
}
