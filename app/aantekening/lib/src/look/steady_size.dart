/// A size that holds: what floats grows to fit what it shows, and does not
/// shrink back as it shows less, so it never jumps about under the eye.
library;

import 'dart:math' as math;

import 'package:flutter/rendering.dart';
import 'package:flutter/widgets.dart';

/// [child], laid out at least as large as it has ever been here: grown to
/// fit more, it stays that large when it shows less.
class SteadySize extends SingleChildRenderObjectWidget {
  const SteadySize({required Widget super.child, super.key});

  @override
  RenderObject createRenderObject(BuildContext context) => _RenderSteadySize();
}

class _RenderSteadySize extends RenderProxyBox {
  Size _largest = Size.zero;

  @override
  void performLayout() {
    final child = this.child;
    if (child == null) {
      size = constraints.smallest;
      return;
    }
    child.layout(
      constraints.copyWith(
        minWidth: math.min(
          math.max(constraints.minWidth, _largest.width),
          constraints.maxWidth,
        ),
        minHeight: math.min(
          math.max(constraints.minHeight, _largest.height),
          constraints.maxHeight,
        ),
      ),
      parentUsesSize: true,
    );
    size = child.size;
    _largest = Size(
      math.max(_largest.width, size.width),
      math.max(_largest.height, size.height),
    );
  }
}
