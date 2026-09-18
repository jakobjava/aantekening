/// What an element widget may need to know about the canvas it sits on.
library;

import 'package:flutter/widgets.dart';

/// Exposes the canvas's current zoom to the element widgets beneath it.
///
/// Element widgets are laid out in page units and scaled as a whole, so they
/// never see the zoom through their constraints. Most do not need it — text and
/// vector formulas stay sharp under any transform — but anything rasterised,
/// such as a PDF page, has to pick a resolution to render at.
class CanvasScope extends InheritedWidget {
  const CanvasScope({required this.zoom, required super.child, super.key});

  /// Screen pixels per page unit.
  final double zoom;

  /// The zoom of the nearest canvas, or 1 outside of one.
  static double zoomOf(BuildContext context) =>
      context.dependOnInheritedWidgetOfExactType<CanvasScope>()?.zoom ?? 1;

  @override
  bool updateShouldNotify(CanvasScope old) => old.zoom != zoom;
}
