/// Drawing a TikZ picture: its lines and fills painted, the text of its
/// nodes typeset.
library;

import 'dart:ui' as ui;

import 'package:aantekening_core/aantekening_core.dart' show MathMode;
import 'package:flutter/rendering.dart';
import 'package:flutter/widgets.dart';

import '../math_view.dart';
import 'tikz_picture.dart';

/// Draws [picture] as LaTeX would in type the size of [style]'s, its lines
/// and unlabelled text in [style]'s colour.
class TikzView extends StatelessWidget {
  const TikzView({required this.picture, required this.style, super.key});

  final TikzPicture picture;
  final TextStyle style;

  /// How many logical pixels a point is: a picture is drawn as in ten-point
  /// type, at the size of the text it is in.
  static double unitFor(TextStyle style) => (style.fontSize ?? 14) / 10;

  @override
  Widget build(BuildContext context) {
    final ink = style.color ?? const Color(0xFF000000);
    // Where the labels go depends on how large they are, which only laying
    // them out tells; what they say and how they look does not.
    final labels = picture.draw(ink: ink).labels;
    return _TikzLayout(
      picture: picture,
      ink: ink,
      unit: unitFor(style),
      children: <Widget>[
        for (final label in labels)
          label.latex.isEmpty
              ? const SizedBox.shrink()
              : MathView(
                  source: label.latex,
                  mode: MathMode.latex,
                  displayStyle: false,
                  textStyle: style.copyWith(
                    color: label.colour,
                    fontSize: (style.fontSize ?? 14) * label.scale,
                  ),
                ),
      ],
    );
  }
}

class _TikzLayout extends MultiChildRenderObjectWidget {
  const _TikzLayout({
    required this.picture,
    required this.ink,
    required this.unit,
    required super.children,
  });

  final TikzPicture picture;
  final Color ink;
  final double unit;

  @override
  RenderObject createRenderObject(BuildContext context) =>
      _RenderTikz(picture, ink, unit);

  @override
  void updateRenderObject(BuildContext context, _RenderTikz renderObject) {
    renderObject
      ..picture = picture
      ..ink = ink
      ..unit = unit;
  }
}

class _TikzParentData extends ContainerBoxParentData<RenderBox> {}

/// Lays the labels out, places them where the picture puts nodes that
/// large, and paints the picture beneath them. It sits on the line by its
/// foot, as a picture does in TeX.
class _RenderTikz extends RenderBox
    with
        ContainerRenderObjectMixin<RenderBox, _TikzParentData>,
        RenderBoxContainerDefaultsMixin<RenderBox, _TikzParentData> {
  _RenderTikz(this._picture, this._ink, this._unit);

  TikzPicture _picture;
  set picture(TikzPicture value) {
    if (identical(value, _picture)) return;
    _picture = value;
    markNeedsLayout();
  }

  Color _ink;
  set ink(Color value) {
    if (value == _ink) return;
    _ink = value;
    markNeedsLayout();
  }

  double _unit;
  set unit(double value) {
    if (value == _unit) return;
    _unit = value;
    markNeedsLayout();
  }

  TikzDrawing? _drawing;

  @override
  void setupParentData(RenderBox child) {
    if (child.parentData is! _TikzParentData) {
      child.parentData = _TikzParentData();
    }
  }

  /// What the picture draws, its labels as large as [sizes] (in logical
  /// pixels) say.
  TikzDrawing _drawingFor(List<Size> sizes) => _picture.draw(
    ink: _ink,
    labelSizes: <Size>[for (final size in sizes) size / _unit],
  );

  Size _sizeOf(TikzDrawing drawing) => drawing.bounds.size * _unit;

  Size _dryMeasure() => _sizeOf(
    _drawingFor(<Size>[
      for (final child in getChildrenAsList())
        child.getDryLayout(const BoxConstraints()),
    ]),
  );

  @override
  Size computeDryLayout(BoxConstraints constraints) =>
      constraints.constrain(_dryMeasure());

  @override
  double? computeDryBaseline(BoxConstraints constraints, TextBaseline _) =>
      computeDryLayout(constraints).height;

  @override
  double computeMinIntrinsicWidth(double height) => _dryMeasure().width;

  @override
  double computeMaxIntrinsicWidth(double height) => _dryMeasure().width;

  @override
  double computeMinIntrinsicHeight(double width) => _dryMeasure().height;

  @override
  double computeMaxIntrinsicHeight(double width) => _dryMeasure().height;

  @override
  double? computeDistanceToActualBaseline(TextBaseline baseline) => size.height;

  @override
  void performLayout() {
    final children = getChildrenAsList();
    for (final child in children) {
      child.layout(const BoxConstraints(), parentUsesSize: true);
    }
    final drawing = _drawingFor(<Size>[
      for (final child in children) child.size,
    ]);
    _drawing = drawing;
    size = constraints.constrain(_sizeOf(drawing));
    final origin = drawing.bounds.topLeft;
    for (var i = 0; i < children.length; i++) {
      final child = children[i];
      final centre = i < drawing.labels.length
          ? (drawing.labels[i].centre - origin) * _unit
          : Offset.zero;
      (child.parentData! as _TikzParentData).offset =
          centre - child.size.center(Offset.zero);
    }
  }

  @override
  bool hitTestChildren(BoxHitTestResult result, {required Offset position}) =>
      defaultHitTestChildren(result, position: position);

  @override
  void paint(PaintingContext context, Offset offset) {
    final drawing = _drawing;
    if (drawing == null) return;
    final canvas = context.canvas
      ..save()
      ..translate(offset.dx, offset.dy)
      ..scale(_unit)
      ..translate(-drawing.bounds.left, -drawing.bounds.top);
    for (final mark in drawing.marks) {
      final paint = Paint()
        ..color = mark.colour
        ..isAntiAlias = true;
      final width = mark.width;
      if (width != null) {
        paint
          ..style = PaintingStyle.stroke
          ..strokeWidth = width
          ..strokeCap = mark.cap
          ..strokeJoin = mark.join;
      } else if (mark.shading case final shading?) {
        paint.shader = _shader(shading, mark.path.getBounds());
      }
      canvas.drawPath(mark.path, paint);
    }
    canvas.restore();
    defaultPaint(context, offset);
  }

  static Shader _shader(TikzShading shading, Rect bounds) =>
      switch (shading.kind) {
        TikzShadingKind.horizontal => ui.Gradient.linear(
          bounds.centerLeft,
          bounds.centerRight,
          <Color>[shading.from, shading.to],
        ),
        TikzShadingKind.vertical => ui.Gradient.linear(
          bounds.topCenter,
          bounds.bottomCenter,
          <Color>[shading.from, shading.to],
        ),
        TikzShadingKind.ball => ui.Gradient.radial(
          bounds.topLeft + bounds.size.bottomRight(Offset.zero) * 0.35,
          bounds.longestSide * 0.75,
          <Color>[shading.from, shading.to],
        ),
      };
}
