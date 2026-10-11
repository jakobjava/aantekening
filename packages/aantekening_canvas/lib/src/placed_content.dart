/// What of an element on the page is there to be pressed, where that is
/// less than its frame.
library;

import 'package:flutter/rendering.dart';
import 'package:flutter/widgets.dart';

/// Says where [child], an element's widget on the page, shows something:
/// a text box its lines, not the paper about them.
///
/// Where boxes lie over one another, a press on a box's paper goes to the
/// text of one beneath it, if there is text there; with none, the box on
/// top takes it as it would anyway. An element without one is pressed
/// anywhere in its frame.
class PlacedContent extends SingleChildRenderObjectWidget {
  const PlacedContent({required this.showsAt, super.child, super.key});

  /// Whether something is shown at a point in [child]'s coordinates.
  final bool Function(Offset local) showsAt;

  @override
  RenderPlacedContent createRenderObject(BuildContext context) =>
      RenderPlacedContent(showsAt);

  @override
  void updateRenderObject(
    BuildContext context,
    RenderPlacedContent renderObject,
  ) {
    renderObject.showsAt = showsAt;
  }
}

class RenderPlacedContent extends RenderProxyBox {
  RenderPlacedContent(this.showsAt);

  bool Function(Offset local) showsAt;

  /// The one [element] is shown by, where it is one of the boxes it is
  /// wrapped in, close about it.
  static RenderPlacedContent? of(RenderObject element) {
    RenderObject? object = element;
    for (var depth = 0; depth < 8 && object != null; depth++) {
      if (object is RenderPlacedContent) return object;
      object = object is RenderObjectWithChildMixin ? object.child : null;
    }
    return null;
  }
}
