/// What an element widget may need to know about the canvas it sits on.
library;

import 'package:aantekening_core/aantekening_core.dart';
import 'package:flutter/widgets.dart';

/// What of the canvas an element widget depends on.
enum CanvasScopeAspect { zoom, region }

/// Exposes the canvas's current zoom, and the part of the page laid out
/// around what is in view, to the element widgets beneath it.
///
/// Element widgets are laid out in page units and scaled as a whole, so they
/// never see the zoom through their constraints. Most do not need it — text and
/// vector formulas stay sharp under any transform — but anything rasterised,
/// such as a PDF page, has to pick a resolution to render at, and zoomed in
/// far, may draw sharp only the part of itself that can be seen.
///
/// A widget depending on the zoom is not told when only the region moves.
class CanvasScope extends InheritedModel<CanvasScopeAspect> {
  const CanvasScope({
    required this.zoom,
    required super.child,
    this.region,
    super.key,
  });

  /// Screen pixels per page unit.
  final double zoom;

  /// The part of the page laid out around the view, in page units; null
  /// where all of it is.
  final Aabb? region;

  /// The zoom of the nearest canvas, or 1 outside of one.
  static double zoomOf(BuildContext context) =>
      InheritedModel.inheritFrom<CanvasScope>(
        context,
        aspect: CanvasScopeAspect.zoom,
      )?.zoom ??
      1;

  /// The part of the page the nearest canvas lays out around its view, or
  /// null outside of one, or where it lays out all of the page.
  static Aabb? regionOf(BuildContext context) =>
      InheritedModel.inheritFrom<CanvasScope>(
        context,
        aspect: CanvasScopeAspect.region,
      )?.region;

  @override
  bool updateShouldNotify(CanvasScope old) =>
      old.zoom != zoom || old.region != region;

  @override
  bool updateShouldNotifyDependent(
    CanvasScope old,
    Set<CanvasScopeAspect> aspects,
  ) =>
      aspects.contains(CanvasScopeAspect.zoom) && old.zoom != zoom ||
      aspects.contains(CanvasScopeAspect.region) && old.region != region;
}
