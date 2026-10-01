/// The page's own layers, laid out in page units and moved and scaled to
/// the view as a whole.
library;

import 'dart:async';
import 'dart:math' as math;

import 'package:aantekening_core/aantekening_core.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/widgets.dart';

import 'canvas_viewport.dart';

/// The part of the page worth laying out for a view of it: what is visible,
/// and a quarter to a half as much again on every side.
///
/// It lies on a grid a quarter of the view's size, so it stays the same
/// while the view moves within it and changes by a step once the view has
/// moved a quarter of its size; what is laid out over it then needs doing
/// again only that often, not at every frame of scrolling. Its corner lies
/// a whole number of [_corner] screen pixels from the page's, so that what
/// is drawn over it in pixels lines up with the screen's.
Aabb pageRegion(CanvasViewport viewport, Size size) {
  const steps = 4;
  final visible = viewport.visibleBounds(size);
  final stepX = math.max(visible.width / steps, 1.0);
  final stepY = math.max(visible.height / steps, 1.0);
  final corner = _corner / viewport.zoom;
  double snapped(double at) => (at / corner).floorToDouble() * corner;
  final left = snapped((visible.left / stepX).floor() * stepX - stepX);
  final top = snapped((visible.top / stepY).floor() * stepY - stepY);
  return Aabb(
    left,
    top,
    left + (steps + 3) * stepX + corner,
    top + (steps + 3) * stepY + corner,
  );
}

/// The screen pixels a region's corner is a whole number of from the
/// page's: a whole number of device pixels, too, at every common pixel
/// density — one, one and a quarter, one and a half, two.
const double _corner = 64;

/// Lays [child] out over [region] of the page, in page units, and shows it
/// as [view] sees the page.
///
/// Following the view changes one transform on the layer the child is
/// painted in: nothing beneath is built, laid out or painted again as the
/// page scrolls or zooms. The child is hit, and places its descendants on
/// screen, through the same transform.
///
/// The child is moved by whole device pixels, so what it draws lands on
/// the screen's pixels as it does still: text and pictures as sharp as they
/// are drawn, scrolled or not.
class PageSpace extends SingleChildRenderObjectWidget {
  const PageSpace({
    required this.view,
    required this.region,
    required super.child,
    this.devicePixelRatio = 1,
    super.key,
  });

  final ValueListenable<CanvasViewport> view;

  /// The part of the page the child covers, in page units.
  final Aabb region;

  /// Device pixels per screen pixel.
  final double devicePixelRatio;

  @override
  RenderPageSpace createRenderObject(BuildContext context) => RenderPageSpace(
    view: view,
    region: region,
    devicePixelRatio: devicePixelRatio,
  );

  @override
  void updateRenderObject(BuildContext context, RenderPageSpace renderObject) {
    // Built again, it may be for a view that moved without saying so: a
    // view that depends on the size it is seen in, say.
    renderObject
      ..view = view
      ..region = region
      ..devicePixelRatio = devicePixelRatio
      ..markNeedsCompositedLayerUpdate();
  }
}

class RenderPageSpace extends RenderBox
    with RenderObjectWithChildMixin<RenderBox> {
  RenderPageSpace({
    required ValueListenable<CanvasViewport> view,
    required Aabb region,
    double devicePixelRatio = 1,
  }) : _view = view,
       _region = region,
       _devicePixelRatio = devicePixelRatio;

  double _devicePixelRatio;
  set devicePixelRatio(double value) {
    if (value == _devicePixelRatio) return;
    _devicePixelRatio = value;
    markNeedsCompositedLayerUpdate();
  }

  ValueListenable<CanvasViewport> _view;
  set view(ValueListenable<CanvasViewport> value) {
    if (identical(value, _view)) return;
    if (attached) {
      _view.removeListener(_onViewChanged);
      value.addListener(_onViewChanged);
    }
    _view = value;
    _onViewChanged();
  }

  Aabb _region;
  set region(Aabb value) {
    if (value == _region) return;
    _region = value;
    markNeedsLayout();
  }

  /// How long the view rests before where the page's parts are is told to
  /// a screen reader again.
  static const Duration _semanticsRest = Duration(milliseconds: 150);

  Timer? _semanticsDue;

  void _onViewChanged() {
    markNeedsCompositedLayerUpdate();
    // Not at every frame of a scroll: working out where every part of the
    // page is took a quarter of each frame's work, and a screen reader
    // needs to know only where the view comes to rest.
    _semanticsDue?.cancel();
    _semanticsDue = Timer(_semanticsRest, () {
      _semanticsDue = null;
      if (attached) markNeedsSemanticsUpdate();
    });
  }

  /// From the child's coordinates to this box's: page units from the
  /// region's corner, to the view's pixels, moved to the nearest device
  /// pixel.
  Matrix4 get _transform {
    final viewport = _view.value;
    final zoom = viewport.zoom;
    final ratio = _devicePixelRatio;
    double snapped(double at) => (at * ratio).roundToDouble() / ratio;
    return Matrix4.translationValues(
      snapped((_region.left - viewport.origin.dx) * zoom),
      snapped((_region.top - viewport.origin.dy) * zoom),
      0,
    )..scaleByDouble(zoom, zoom, 1, 1);
  }

  @override
  void attach(PipelineOwner owner) {
    super.attach(owner);
    _view.addListener(_onViewChanged);
  }

  @override
  void detach() {
    _view.removeListener(_onViewChanged);
    _semanticsDue?.cancel();
    _semanticsDue = null;
    super.detach();
  }

  @override
  bool get isRepaintBoundary => true;

  @override
  OffsetLayer updateCompositedLayer({
    required covariant TransformLayer? oldLayer,
  }) => (oldLayer ?? TransformLayer())..transform = _transform;

  @override
  bool get sizedByParent => true;

  @override
  Size computeDryLayout(BoxConstraints constraints) => constraints.biggest;

  @override
  void performLayout() {
    child?.layout(BoxConstraints.tight(Size(_region.width, _region.height)));
  }

  @override
  void paint(PaintingContext context, Offset offset) {
    final child = this.child;
    if (child != null) context.paintChild(child, offset);
  }

  @override
  bool hitTestChildren(BoxHitTestResult result, {required Offset position}) {
    final child = this.child;
    if (child == null) return false;
    return result.addWithPaintTransform(
      transform: _transform,
      position: position,
      hitTest: (result, position) => child.hitTest(result, position: position),
    );
  }

  @override
  void applyPaintTransform(RenderBox child, Matrix4 transform) {
    transform.multiply(_transform);
  }
}

/// Places each of [children] at its frame on the page, turned about its
/// middle, as the page covered from [origin] has them: each is a
/// [PlacedOnPage].
class PagePlacement extends MultiChildRenderObjectWidget {
  const PagePlacement({required this.origin, super.children, super.key});

  /// The page point at this box's top-left corner.
  final Offset origin;

  @override
  RenderPagePlacement createRenderObject(BuildContext context) =>
      RenderPagePlacement(origin);

  @override
  void updateRenderObject(
    BuildContext context,
    RenderPagePlacement renderObject,
  ) {
    renderObject.origin = origin;
  }
}

/// Puts [child] at [frame] on the page of a [PagePlacement], laid out at
/// the frame's size in page units.
class PlacedOnPage extends ParentDataWidget<PlacedData> {
  const PlacedOnPage({required this.frame, required super.child, super.key});

  final Frame frame;

  @override
  void applyParentData(RenderObject renderObject) {
    final data = renderObject.parentData! as PlacedData;
    if (data.frame == frame) return;
    data.frame = frame;
    renderObject.parent?.markNeedsLayout();
  }

  @override
  Type get debugTypicalAncestorWidgetClass => PagePlacement;
}

class PlacedData extends ContainerBoxParentData<RenderBox> {
  Frame frame = const Frame.origin(0, 0);

  /// The layer a turned child is painted in, where it needs one.
  final LayerHandle<TransformLayer> turned = LayerHandle<TransformLayer>();

  @override
  void detach() {
    turned.layer = null;
    super.detach();
  }
}

class RenderPagePlacement extends RenderBox
    with
        ContainerRenderObjectMixin<RenderBox, PlacedData>,
        RenderBoxContainerDefaultsMixin<RenderBox, PlacedData> {
  RenderPagePlacement(this._origin);

  Offset _origin;
  set origin(Offset value) {
    if (value == _origin) return;
    _origin = value;
    markNeedsLayout();
  }

  @override
  void setupParentData(RenderBox child) {
    if (child.parentData is! PlacedData) child.parentData = PlacedData();
  }

  @override
  bool get sizedByParent => true;

  @override
  Size computeDryLayout(BoxConstraints constraints) => constraints.biggest;

  @override
  void performLayout() {
    var child = firstChild;
    while (child != null) {
      final data = child.parentData! as PlacedData;
      final frame = data.frame;
      child.layout(BoxConstraints.tight(Size(frame.width, frame.height)));
      data.offset = Offset(frame.x, frame.y) - _origin;
      child = data.nextSibling;
    }
  }

  /// From [data]'s child's coordinates to this box's, for a turned child.
  static Matrix4 _turn(PlacedData data) {
    final frame = data.frame;
    final middleX = data.offset.dx + frame.width / 2;
    final middleY = data.offset.dy + frame.height / 2;
    return Matrix4.translationValues(middleX, middleY, 0)
      ..rotateZ(frame.rotation)
      ..translateByDouble(-frame.width / 2, -frame.height / 2, 0, 1);
  }

  @override
  void paint(PaintingContext context, Offset offset) {
    var child = firstChild;
    while (child != null) {
      final data = child.parentData! as PlacedData;
      if (data.frame.rotation == 0) {
        data.turned.layer = null;
        context.paintChild(child, offset + data.offset);
      } else {
        final turned = child;
        data.turned.layer = context.pushTransform(
          needsCompositing,
          offset,
          _turn(data),
          (context, offset) => context.paintChild(turned, offset),
          oldLayer: data.turned.layer,
        );
      }
      child = data.nextSibling;
    }
  }

  @override
  bool hitTestChildren(BoxHitTestResult result, {required Offset position}) {
    var child = lastChild;
    while (child != null) {
      final data = child.parentData! as PlacedData;
      final placed = child;
      final hit = data.frame.rotation == 0
          ? result.addWithPaintOffset(
              offset: data.offset,
              position: position,
              hitTest: (result, position) =>
                  placed.hitTest(result, position: position),
            )
          : result.addWithPaintTransform(
              transform: _turn(data),
              position: position,
              hitTest: (result, position) =>
                  placed.hitTest(result, position: position),
            );
      if (hit) return true;
      child = data.previousSibling;
    }
    return false;
  }

  @override
  void applyPaintTransform(RenderBox child, Matrix4 transform) {
    final data = child.parentData! as PlacedData;
    if (data.frame.rotation == 0) {
      transform.translateByDouble(data.offset.dx, data.offset.dy, 0, 1);
    } else {
      transform.multiply(_turn(data));
    }
  }
}
