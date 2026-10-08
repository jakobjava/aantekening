/// What the page shows of itself on the status line: the pen in hand, the
/// zoom, and a save under way.
library;

import 'package:aantekening_canvas/aantekening_canvas.dart';
import 'package:aantekening_core/aantekening_core.dart' show NoteColors;
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../look/tones.dart';
import 'canvas_select.dart';
import 'palette.dart';

/// What the status line shows of a page: what is on it, whether it is
/// being saved, and how to put it back to actual size.
@immutable
class PageHandle {
  const PageHandle({
    required this.canvas,
    required this.saving,
    required this.onActualSize,
  });

  final CanvasController canvas;
  final ValueListenable<bool> saving;
  final VoidCallback onActualSize;
}

/// The page with the keys, as its editor says: what the status line shows.
class ActivePage extends Notifier<PageHandle?> {
  @override
  PageHandle? build() => null;

  // A setter would read as a field; this is an editor taking the keys.
  // ignore: use_setters_to_change_properties
  void show(PageHandle page) => state = page;

  /// [page] lets go of the keys, if it had them — and if the window is
  /// still there, which an editor letting go as it closes outlives.
  void leave(PageHandle page) {
    if (ref.mounted && identical(state, page)) state = null;
  }
}

final activePageProvider = NotifierProvider<ActivePage, PageHandle?>(
  ActivePage.new,
);

/// The page's part of the status line: the pen in hand while drawing, a
/// save under way, and the zoom, which a click puts back to actual size.
class PageStatus extends ConsumerWidget {
  const PageStatus({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final page = ref.watch(activePageProvider);
    if (page == null) return const SizedBox.shrink();
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: <Widget>[
        _InHand(canvas: page.canvas),
        const SizedBox(width: 10),
        _Saving(saving: page.saving),
        const SizedBox(width: 10),
        _Zoom(canvas: page.canvas, onActualSize: page.onActualSize),
      ],
    );
  }
}

/// Quiet text, as everything on the status line but the mode and the tab
/// showing is.
TextStyle _quiet(BuildContext context) => TextStyle(
  fontSize: 11.5,
  fontFeatures: const <FontFeature>[FontFeature.tabularFigures()],
  color: context.tones.muted,
);

/// The tool in hand, while it is one that draws: its name, and the colour
/// and width of its ink.
class _InHand extends StatelessWidget {
  const _InHand({required this.canvas});

  final CanvasController canvas;

  @override
  Widget build(BuildContext context) => CanvasSelect<(CanvasTool, PenSettings)>(
    canvas: canvas,
    select: () => (canvas.tool, canvas.pen),
    builder: (context, value) {
      final (tool, pen) = value;
      final name = switch (tool) {
        CanvasTool.pen => 'Pen',
        CanvasTool.highlighter => 'Highlighter',
        CanvasTool.shape => 'Shapes',
        CanvasTool.eraser => 'Eraser',
        CanvasTool.select || CanvasTool.lasso => null,
      };
      if (name == null) return const SizedBox.shrink();
      final inked = tool != CanvasTool.eraser;
      final width = pen.width.toStringAsFixed(pen.width % 1 == 0 ? 0 : 1);
      return Row(
        mainAxisSize: MainAxisSize.min,
        children: <Widget>[
          if (inked) ...<Widget>[
            _Ink(color: pen.color),
            const SizedBox(width: 6),
          ],
          Text(inked ? '$name  $width pt' : name, style: _quiet(context)),
        ],
      );
    },
  );
}

/// A dot of [color], as ink of it looks.
class _Ink extends StatelessWidget {
  const _Ink({required this.color});

  final int color;

  @override
  Widget build(BuildContext context) => Tooltip(
    message: NotePalette.nameOf(color),
    child: Container(
      width: 10,
      height: 10,
      decoration: BoxDecoration(
        color: color == NoteColors.inverse
            ? context.tones.text
            : Color(color | 0xFF000000),
        shape: BoxShape.circle,
        border: Border.all(color: context.tones.line),
      ),
    ),
  );
}

class _Saving extends StatelessWidget {
  const _Saving({required this.saving});

  final ValueListenable<bool> saving;

  @override
  Widget build(BuildContext context) => ValueListenableBuilder<bool>(
    valueListenable: saving,
    builder: (context, saving, _) => saving
        ? Text('Saving…', style: _quiet(context))
        : const SizedBox.shrink(),
  );
}

class _Zoom extends StatelessWidget {
  const _Zoom({required this.canvas, required this.onActualSize});

  final CanvasController canvas;
  final VoidCallback onActualSize;

  @override
  Widget build(BuildContext context) => CanvasSelect<int>(
    canvas: canvas,
    select: () => (canvas.viewport.zoom * 100).round(),
    builder: (context, percent) => Tooltip(
      message: 'Back to actual size',
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: onActualSize,
        child: Text('$percent%', style: _quiet(context)),
      ),
    ),
  );
}
