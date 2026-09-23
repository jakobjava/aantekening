/// The infinite-canvas rendering and input engine.
///
/// The canvas owns layout, navigation and ink; the host application supplies
/// the widgets for text, maths, images and PDFs through a
/// [CanvasElementBuilder]. That split keeps this package free of dependencies
/// on the maths and document renderers while still letting those elements be
/// real, focusable, editable widgets.
library;

export 'src/canvas_controller.dart';
export 'src/canvas_painters.dart';
export 'src/canvas_scroll.dart';
export 'src/canvas_viewport.dart';
export 'src/canvas_scope.dart';
export 'src/infinite_canvas.dart';
export 'src/page_scrollbar.dart';
export 'src/selection_handles.dart';
export 'src/spatial_index.dart';
export 'src/stroke_geometry.dart';
export 'src/tools.dart';
