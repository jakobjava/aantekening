/// The page document: the unit that is saved, loaded and indexed.
library;

import 'dart:convert';
import 'dart:math' as math;

import '../util/geometry.dart';
import '../util/json_read.dart';
import '../util/ulid.dart';
import 'elements.dart';

/// The ruling drawn behind a page's content.
enum PageBackgroundKind { blank, grid, ruled, dotted }

/// The paper a page is drawn on.
class PageBackground {
  const PageBackground({
    this.kind = PageBackgroundKind.blank,
    this.spacing = 24,
    this.lineColor = 0x1F000000,
    this.paperColor = 0xFFFFFFFF,
  });

  static const PageBackground defaults = PageBackground();

  final PageBackgroundKind kind;

  /// Grid or rule spacing in page-space pixels.
  final double spacing;

  /// Rule colour as 32-bit ARGB.
  final int lineColor;

  /// Paper colour as 32-bit ARGB.
  final int paperColor;

  PageBackground copyWith({
    PageBackgroundKind? kind,
    double? spacing,
    int? lineColor,
    int? paperColor,
  }) => PageBackground(
    kind: kind ?? this.kind,
    spacing: spacing ?? this.spacing,
    lineColor: lineColor ?? this.lineColor,
    paperColor: paperColor ?? this.paperColor,
  );

  Map<String, Object?> toJson() => <String, Object?>{
    'kind': kind.name,
    'spacing': spacing,
    'lineColor': lineColor,
    'paperColor': paperColor,
  };

  static PageBackground fromJson(Map<String, Object?> json) => PageBackground(
    kind: readEnum(
      json,
      'kind',
      PageBackgroundKind.values,
      PageBackgroundKind.blank,
    ),
    spacing: readDouble(json, 'spacing', 24),
    lineColor: readInt(json, 'lineColor', 0x1F000000),
    paperColor: readInt(json, 'paperColor', 0xFFFFFFFF),
  );
}

/// Canvas-level settings for a page.
class CanvasSettings {
  const CanvasSettings({
    this.background = PageBackground.defaults,
    this.paperWidth,
  });

  static const CanvasSettings defaults = CanvasSettings();

  final PageBackground background;

  /// Width of the printable column in page-space pixels, or null for a truly
  /// unbounded canvas.
  ///
  /// A page always runs on without end to the right; this only draws a guide
  /// and sets the wrap width for new text boxes, the way OneNote's page-width
  /// rule does.
  final double? paperWidth;

  CanvasSettings copyWith({
    PageBackground? background,
    double? paperWidth,
    bool clearPaperWidth = false,
  }) => CanvasSettings(
    background: background ?? this.background,
    paperWidth: clearPaperWidth ? null : (paperWidth ?? this.paperWidth),
  );

  Map<String, Object?> toJson() => <String, Object?>{
    'background': background.toJson(),
    if (paperWidth != null) 'paperWidth': paperWidth,
  };

  static CanvasSettings fromJson(Map<String, Object?> json) => CanvasSettings(
    background: PageBackground.fromJson(readObject(json, 'background')),
    paperWidth: readDoubleOrNull(json, 'paperWidth'),
  );
}

/// The full contents of one page.
///
/// This is the object serialised to the `.json` page format and stored as the
/// page body in SQLite. It is immutable: edits produce a new document with a
/// higher [revision], which makes undo/redo a matter of keeping references and
/// lets the renderer compare identity to decide what to repaint.
class PageDocument {
  PageDocument({
    required this.id,
    this.revision = 0,
    this.canvas = CanvasSettings.defaults,
    this.elements = const <NoteElement>[],
  });

  /// Creates an empty page with a fresh identifier.
  factory PageDocument.empty({String? id}) =>
      PageDocument(id: id ?? Ulid.generate());

  /// The version of the on-disk format this build writes.
  ///
  /// Bump only for changes a previous build could not safely ignore; additive
  /// fields do not need a new version because every reader tolerates unknown
  /// keys.
  static const int currentFormatVersion = 1;

  /// Matches the owning page's identifier in the database.
  final String id;

  /// Monotonically increasing edit counter, used for conflict detection and
  /// for skipping redundant saves.
  final int revision;

  final CanvasSettings canvas;

  /// Elements in paint order; see [sortedByZ] for the guaranteed ordering.
  final List<NoteElement> elements;

  /// The elements sorted back-to-front for painting.
  List<NoteElement> get sortedByZ {
    final sorted = List<NoteElement>.of(elements);
    sorted.sort((a, b) => a.z.compareTo(b.z));
    return sorted;
  }

  /// The bounding box of all content, or an empty box for a blank page.
  ///
  /// Drives "zoom to fit" and the scrollable extent of the infinite canvas.
  Aabb get contentBounds {
    if (elements.isEmpty) return Aabb.empty;
    var box = elements.first.bounds;
    for (var i = 1; i < elements.length; i++) {
      box = box.union(elements[i].bounds);
    }
    return box;
  }

  /// How far content spanning [bounds] has to move, right and down, to lie on
  /// the page: nothing when it already does.
  ///
  /// A page has a top-left corner, at (0, 0), and runs on without end to the
  /// right and downwards, as a OneNote page does. Nothing is placed above or
  /// left of the corner, and the view never scrolls there.
  static Vec2 shiftOntoPage(Aabb bounds) =>
      Vec2(math.max(0.0, -bounds.left), math.max(0.0, -bounds.top));

  /// This page with its content moved just far enough right and down to lie
  /// on the page, or this page when it already does — as a page kept from
  /// before pages had edges may not.
  PageDocument withContentOnPage() {
    if (elements.isEmpty) return this;
    final shift = shiftOntoPage(contentBounds);
    if (shift.x == 0 && shift.y == 0) return this;
    return copyWith(
      revision: revision + 1,
      elements: <NoteElement>[
        for (final element in elements)
          element.withFrame(element.frame.translate(shift.x, shift.y)),
      ],
    );
  }

  /// The highest paint order currently in use.
  int get topZ {
    var top = 0;
    for (final element in elements) {
      if (element.z > top) top = element.z;
    }
    return top;
  }

  /// Every asset referenced by this page.
  Set<String> get referencedAssetIds => <String>{
    for (final element in elements) ...element.assetIds,
  };

  /// Looks up an element by identifier, or null when it is not on this page.
  NoteElement? elementById(String elementId) {
    for (final element in elements) {
      if (element.id == elementId) return element;
    }
    return null;
  }

  /// Returns the topmost element whose bounds contain ([x], [y]).
  NoteElement? hitTest(double x, double y) {
    NoteElement? best;
    for (final element in elements) {
      if (element.locked) continue;
      if (!element.bounds.containsPoint(x, y)) continue;
      if (best == null || element.z >= best.z) best = element;
    }
    return best;
  }

  /// The plain text of the page, used to build the full-text index and to
  /// generate list previews.
  String extractSearchText() {
    final buffer = StringBuffer();
    for (final element in sortedByZ) {
      element.writeSearchText(buffer);
    }
    return buffer.toString().trim();
  }

  PageDocument copyWith({
    int? revision,
    CanvasSettings? canvas,
    List<NoteElement>? elements,
  }) => PageDocument(
    id: id,
    revision: revision ?? this.revision,
    canvas: canvas ?? this.canvas,
    elements: elements ?? this.elements,
  );

  /// Returns a copy with [element] added on top, bumping [revision].
  PageDocument withElementAdded(NoteElement element) => copyWith(
    revision: revision + 1,
    elements: <NoteElement>[...elements, element.withZ(topZ + 1)],
  );

  /// Returns a copy with the element sharing [replacement]'s id swapped out.
  ///
  /// Returns this document unchanged when no such element exists, so callers
  /// can apply edits optimistically.
  PageDocument withElementReplaced(NoteElement replacement) {
    final index = elements.indexWhere((e) => e.id == replacement.id);
    if (index < 0) return this;
    final updated = List<NoteElement>.of(elements);
    updated[index] = replacement;
    return copyWith(revision: revision + 1, elements: updated);
  }

  /// Returns a copy without the elements named in [elementIds].
  PageDocument withElementsRemoved(Set<String> elementIds) {
    if (elementIds.isEmpty) return this;
    final kept = <NoteElement>[
      for (final element in elements)
        if (!elementIds.contains(element.id)) element,
    ];
    if (kept.length == elements.length) return this;
    return copyWith(revision: revision + 1, elements: kept);
  }

  Map<String, Object?> toJson() => <String, Object?>{
    'formatVersion': currentFormatVersion,
    'id': id,
    'revision': revision,
    'canvas': canvas.toJson(),
    'elements': <Object?>[for (final element in elements) element.toJson()],
  };

  /// Decodes a page document.
  ///
  /// Unknown element types are skipped rather than treated as corruption, so a
  /// page written by a newer build still opens here.
  factory PageDocument.fromJson(Map<String, Object?> json) {
    final formatVersion = readInt(json, 'formatVersion', 1);
    if (formatVersion > currentFormatVersion) {
      // Forward compatibility is best-effort: read what this build understands.
      // A hard failure here would lock the user out of their own notes.
    }
    final elements = <NoteElement>[];
    for (final raw in readObjectList(json, 'elements')) {
      final element = NoteElement.fromJson(raw);
      if (element != null) elements.add(element);
    }
    return PageDocument(
      id: readString(json, 'id'),
      revision: readInt(json, 'revision'),
      canvas: CanvasSettings.fromJson(readObject(json, 'canvas')),
      elements: elements,
    );
  }

  /// Encodes the document as compact JSON.
  String encode() => jsonEncode(toJson());

  /// Encodes the document as indented JSON, for export and for diffing in
  /// version control.
  String encodePretty() => const JsonEncoder.withIndent('  ').convert(toJson());

  /// Decodes a document from a JSON string.
  ///
  /// Throws [PageFormatException] when [source] is not a JSON object.
  factory PageDocument.decode(String source) {
    final Object? decoded;
    try {
      decoded = jsonDecode(source);
    } on FormatException catch (error) {
      throw PageFormatException('Page is not valid JSON: ${error.message}');
    }
    if (decoded is! Map) {
      throw PageFormatException('Page must be a JSON object');
    }
    return PageDocument.fromJson(decoded.cast<String, Object?>());
  }
}
