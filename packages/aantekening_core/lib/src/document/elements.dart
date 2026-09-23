/// The element hierarchy placed on a page's infinite canvas.
///
/// Every element subtype lives in this library because [NoteElement] is
/// `sealed`: exhaustive `switch` statements over elements are then checked by
/// the compiler, so adding a new element type surfaces every renderer, hit-test
/// and serialiser that still needs to handle it.
library;

import '../util/geometry.dart';
import '../util/json_read.dart';
import '../util/ulid.dart';
import 'ink.dart';
import 'rich_text.dart';

/// How an image or PDF fills its frame.
enum MediaFit { contain, cover, stretch }

/// Thrown when a page document cannot be interpreted at all.
class PageFormatException implements Exception {
  PageFormatException(this.message);

  final String message;

  @override
  String toString() => 'PageFormatException: $message';
}

/// Base class for anything positioned on a page.
sealed class NoteElement {
  const NoteElement({
    required this.id,
    required this.frame,
    required this.createdAt,
    required this.updatedAt,
    this.z = 0,
    this.locked = false,
  });

  /// Stable identifier, unique within the page.
  final String id;

  /// Position and size in page space.
  final Frame frame;

  /// Paint order; higher values are drawn on top.
  final int z;

  /// Whether the element is part of the page's background: drawn beneath
  /// all ink and everything else, and never picked, moved or erased — a
  /// picture or a PDF page set as the background to write over.
  final bool locked;

  /// Creation time in milliseconds since the Unix epoch.
  final int createdAt;

  /// Last modification time in milliseconds since the Unix epoch.
  final int updatedAt;

  /// The discriminator written to JSON.
  String get type;

  /// The box used for culling and hit-testing.
  Aabb get bounds => frame.rotatedBounds;

  /// The box around every one of [elements], or [Aabb.empty] for none.
  static Aabb boundsOf(Iterable<NoteElement> elements) =>
      Aabb.around(elements.map((element) => element.bounds));

  /// Appends this element's searchable text to [out].
  ///
  /// Called while building the full-text index, so it avoids returning
  /// intermediate strings.
  void writeSearchText(StringBuffer out);

  /// Returns a copy moved or resized to [frame].
  NoteElement withFrame(Frame frame);

  /// Returns a copy at paint order [z].
  NoteElement withZ(int z);

  /// Returns a copy that is, or is not, part of the background ([locked]).
  NoteElement withLocked(bool locked);

  /// Returns a copy stamped as modified at [timestamp].
  NoteElement touch(int timestamp);

  /// This element as an object in a text box — a picture or a PDF page —
  /// or null for anything that cannot sit in text.
  BlockEmbed? get asEmbed => null;

  /// Identifiers of binary attachments this element depends on.
  ///
  /// The store uses these to garbage-collect orphaned assets.
  Iterable<String> get assetIds => const <String>[];

  Map<String, Object?> toJson();

  /// Fields shared by every element type.
  Map<String, Object?> baseJson() => <String, Object?>{
    'id': id,
    'type': type,
    'frame': frame.toJson(),
    if (z != 0) 'z': z,
    if (locked) 'locked': true,
    'createdAt': createdAt,
    'updatedAt': updatedAt,
  };

  /// Copies of [elements] to paste: each with an identifier of its own,
  /// moved by [offset] and made at [now], a group keeping those of its
  /// members copied with it.
  static List<NoteElement> copiesOf(
    List<NoteElement> elements, {
    required int now,
    Vec2 offset = const Vec2(0, 0),
  }) {
    final ids = <String, String>{
      for (final element in elements) element.id: Ulid.generate(),
    };
    return <NoteElement>[
      for (final element in elements)
        ?NoteElement.fromJson(<String, Object?>{
          ...element.toJson(),
          'id': ids[element.id],
          'frame': element.frame.translate(offset.x, offset.y).toJson(),
          'createdAt': now,
          'updatedAt': now,
          if (element is GroupElement)
            'childIds': <String>[
              for (final child in element.childIds) ?ids[child],
            ],
        }),
    ];
  }

  /// Decodes any element, dispatching on its `type` field.
  ///
  /// Returns null for an unrecognised type so that a document written by a
  /// newer version of the app still opens, minus the elements this build cannot
  /// represent.
  static NoteElement? fromJson(Map<String, Object?> json) {
    final type = readString(json, 'type');
    return switch (type) {
      'text' => TextElement.fromJson(json),
      'ink' => InkElement.fromJson(json),
      'image' => ImageElement.fromJson(json),
      'pdf' => PdfElement.fromJson(json),
      'math' => MathElement.fromJson(json),
      'table' => TableElement.fromJson(json),
      'group' => GroupElement.fromJson(json),
      _ => null,
    };
  }
}

/// A moveable text box, the primary way of writing on a page.
final class TextElement extends NoteElement {
  const TextElement({
    required super.id,
    required super.frame,
    required super.createdAt,
    required super.updatedAt,
    super.z,
    super.locked,
    this.blocks = const <TextBlock>[],
    this.autoGrow = true,
    this.autoWidth = false,
  });

  final List<TextBlock> blocks;

  /// Whether the box grows downward to fit its content, as OneNote text
  /// containers do, instead of clipping at a fixed height.
  final bool autoGrow;

  /// Whether the box widens to fit its longest line, up to a limit, as a new
  /// OneNote text container does while you type. Resizing the box by hand
  /// fixes its width.
  final bool autoWidth;

  @override
  String get type => 'text';

  @override
  Iterable<String> get assetIds => <String>{
    for (final block in blocks)
      if (block.embed case final embed?) embed.assetId,
  };

  @override
  void writeSearchText(StringBuffer out) {
    for (final block in blocks) {
      final embedText = block.embed?.text;
      if (embedText != null) out.write(embedText);
      for (final run in block.runs) {
        out.write(run.text);
      }
      out.write('\n');
    }
  }

  TextElement copyWith({
    Frame? frame,
    int? z,
    bool? locked,
    int? updatedAt,
    List<TextBlock>? blocks,
    bool? autoGrow,
    bool? autoWidth,
  }) => TextElement(
    id: id,
    frame: frame ?? this.frame,
    createdAt: createdAt,
    updatedAt: updatedAt ?? this.updatedAt,
    z: z ?? this.z,
    locked: locked ?? this.locked,
    blocks: blocks ?? this.blocks,
    autoGrow: autoGrow ?? this.autoGrow,
    autoWidth: autoWidth ?? this.autoWidth,
  );

  /// Moves, rotates or resizes the box. A new width means the user has sized
  /// it, so it stops widening by itself.
  @override
  TextElement withFrame(Frame frame) => copyWith(
    frame: frame,
    autoWidth: autoWidth && frame.width == this.frame.width,
  );

  @override
  TextElement withZ(int z) => copyWith(z: z);

  @override
  TextElement withLocked(bool locked) => copyWith(locked: locked);

  @override
  TextElement touch(int timestamp) => copyWith(updatedAt: timestamp);

  @override
  Map<String, Object?> toJson() => <String, Object?>{
    ...baseJson(),
    'blocks': <Object?>[for (final block in blocks) block.toJson()],
    if (!autoGrow) 'autoGrow': false,
    if (autoWidth) 'autoWidth': true,
  };

  static TextElement fromJson(Map<String, Object?> json) => TextElement(
    id: readString(json, 'id'),
    frame: Frame.fromJson(readObject(json, 'frame')),
    createdAt: readInt(json, 'createdAt'),
    updatedAt: readInt(json, 'updatedAt'),
    z: readInt(json, 'z'),
    locked: readBool(json, 'locked'),
    blocks: <TextBlock>[
      for (final block in readObjectList(json, 'blocks'))
        TextBlock.fromJson(block),
    ],
    autoGrow: readBool(json, 'autoGrow', true),
    autoWidth: readBool(json, 'autoWidth'),
  );
}

/// A layer of handwritten or drawn strokes.
///
/// Ink is grouped into one element per capture session rather than one element
/// per stroke, so a page of handwriting stays a handful of elements instead of
/// thousands.
final class InkElement extends NoteElement {
  InkElement({
    required super.id,
    required super.frame,
    required super.createdAt,
    required super.updatedAt,
    super.z,
    super.locked,
    this.strokes = const <InkStroke>[],
  });

  final List<InkStroke> strokes;

  Aabb? _bounds;

  @override
  String get type => 'ink';

  /// The union of the contained strokes, which is tighter than [frame] and is
  /// what the canvas culls and hit-tests against.
  @override
  Aabb get bounds {
    final cached = _bounds;
    if (cached != null) return cached;
    if (strokes.isEmpty) return _bounds = frame.bounds;
    var box = strokes.first.bounds;
    for (var i = 1; i < strokes.length; i++) {
      box = box.union(strokes[i].bounds);
    }
    return _bounds = box;
  }

  @override
  void writeSearchText(StringBuffer out) {
    // Handwriting is indexed from recognised text supplied by the AI layer and
    // stored alongside the page, not from the strokes themselves.
  }

  InkElement copyWith({
    Frame? frame,
    int? z,
    bool? locked,
    int? updatedAt,
    List<InkStroke>? strokes,
  }) => InkElement(
    id: id,
    frame: frame ?? this.frame,
    createdAt: createdAt,
    updatedAt: updatedAt ?? this.updatedAt,
    z: z ?? this.z,
    locked: locked ?? this.locked,
    strokes: strokes ?? this.strokes,
  );

  /// A copy holding [strokes], with its frame recomputed to fit them, so the
  /// frame never goes stale as strokes are added or erased.
  InkElement withStrokes(List<InkStroke> strokes, {int? updatedAt}) {
    var box = Aabb.empty;
    for (final stroke in strokes) {
      box = box.union(stroke.bounds);
    }
    return copyWith(
      strokes: strokes,
      updatedAt: updatedAt,
      frame: box.isEmpty
          ? frame
          : Frame(
              x: box.left,
              y: box.top,
              width: box.width,
              height: box.height,
            ),
    );
  }

  /// A copy with [transform] baked into every stroke.
  InkElement transformed(Affine2D transform) => withStrokes(<InkStroke>[
    for (final stroke in strokes) stroke.transformed(transform),
  ]);

  /// Whether a drawn stroke passes within [radius] of ([x], [y]) — tighter
  /// than [bounds], which for a page of handwriting covers a lot of paper
  /// that has nothing on it.
  bool hitsStroke(double x, double y, double radius) {
    if (!bounds.inflate(radius).containsPoint(x, y)) return false;
    for (final stroke in strokes) {
      if (stroke.hitTest(x, y, radius)) return true;
    }
    return false;
  }

  /// Moves and scales the contained strokes to match [frame].
  ///
  /// Ink geometry is absolute, so unlike other elements a frame change has to
  /// be baked into the samples rather than applied as a transform at paint time.
  @override
  InkElement withFrame(Frame frame) {
    final from = this.frame;
    if (from.width == 0 || from.height == 0) {
      return copyWith(frame: frame);
    }
    final scaleX = frame.width / from.width;
    final scaleY = frame.height / from.height;
    final moved = <InkStroke>[
      for (final stroke in strokes)
        (scaleX == 1 && scaleY == 1)
            ? stroke.translate(frame.x - from.x, frame.y - from.y)
            : stroke
                  .scale(scaleX, scaleY, originX: from.x, originY: from.y)
                  .translate(frame.x - from.x, frame.y - from.y),
    ];
    return copyWith(frame: frame, strokes: moved);
  }

  @override
  InkElement withZ(int z) => copyWith(z: z);

  @override
  InkElement withLocked(bool locked) => copyWith(locked: locked);

  @override
  InkElement touch(int timestamp) => copyWith(updatedAt: timestamp);

  @override
  Map<String, Object?> toJson() => <String, Object?>{
    ...baseJson(),
    'strokes': <Object?>[for (final stroke in strokes) stroke.toJson()],
  };

  static InkElement fromJson(Map<String, Object?> json) => InkElement(
    id: readString(json, 'id'),
    frame: Frame.fromJson(readObject(json, 'frame')),
    createdAt: readInt(json, 'createdAt'),
    updatedAt: readInt(json, 'updatedAt'),
    z: readInt(json, 'z'),
    locked: readBool(json, 'locked'),
    strokes: <InkStroke>[
      for (final stroke in readObjectList(json, 'strokes'))
        InkStroke.fromJson(stroke),
    ],
  );
}

/// A bitmap or vector image stored in the asset store.
final class ImageElement extends NoteElement {
  const ImageElement({
    required super.id,
    required super.frame,
    required super.createdAt,
    required super.updatedAt,
    required this.assetId,
    super.z,
    super.locked,
    this.fit = MediaFit.contain,
    this.altText,
    this.recognizedText,
  });

  final String assetId;
  final MediaFit fit;

  /// Accessibility description.
  final String? altText;

  /// Text extracted from the image by OCR, indexed for search.
  final String? recognizedText;

  @override
  String get type => 'image';

  @override
  BlockEmbed get asEmbed => BlockEmbed(
    kind: EmbedKind.image,
    assetId: assetId,
    width: frame.width,
    height: frame.height,
    text: altText,
  );

  @override
  Iterable<String> get assetIds => <String>[assetId];

  @override
  void writeSearchText(StringBuffer out) {
    if (altText != null) out.writeln(altText);
    if (recognizedText != null) out.writeln(recognizedText);
  }

  ImageElement copyWith({
    Frame? frame,
    int? z,
    bool? locked,
    int? updatedAt,
    MediaFit? fit,
    String? altText,
    String? recognizedText,
  }) => ImageElement(
    id: id,
    frame: frame ?? this.frame,
    createdAt: createdAt,
    updatedAt: updatedAt ?? this.updatedAt,
    assetId: assetId,
    z: z ?? this.z,
    locked: locked ?? this.locked,
    fit: fit ?? this.fit,
    altText: altText ?? this.altText,
    recognizedText: recognizedText ?? this.recognizedText,
  );

  @override
  ImageElement withFrame(Frame frame) => copyWith(frame: frame);

  @override
  ImageElement withZ(int z) => copyWith(z: z);

  @override
  ImageElement withLocked(bool locked) => copyWith(locked: locked);

  @override
  ImageElement touch(int timestamp) => copyWith(updatedAt: timestamp);

  @override
  Map<String, Object?> toJson() => <String, Object?>{
    ...baseJson(),
    'assetId': assetId,
    if (fit != MediaFit.contain) 'fit': fit.name,
    if (altText != null) 'altText': altText,
    if (recognizedText != null) 'recognizedText': recognizedText,
  };

  static ImageElement fromJson(Map<String, Object?> json) => ImageElement(
    id: readString(json, 'id'),
    frame: Frame.fromJson(readObject(json, 'frame')),
    createdAt: readInt(json, 'createdAt'),
    updatedAt: readInt(json, 'updatedAt'),
    assetId: readString(json, 'assetId'),
    z: readInt(json, 'z'),
    locked: readBool(json, 'locked'),
    fit: readEnum(json, 'fit', MediaFit.values, MediaFit.contain),
    altText: readStringOrNull(json, 'altText'),
    recognizedText: readStringOrNull(json, 'recognizedText'),
  );
}

/// One page of a PDF, placed on the canvas as a backdrop to annotate over.
///
/// Each PDF page is its own element so that a document can be spread across the
/// canvas and annotated page by page, and so that culling skips pages outside
/// the viewport.
final class PdfElement extends NoteElement {
  const PdfElement({
    required super.id,
    required super.frame,
    required super.createdAt,
    required super.updatedAt,
    required this.assetId,
    required this.pageIndex,
    super.z,
    super.locked,
    this.extractedText,
  });

  final String assetId;

  /// Zero-based page number within the source document.
  final int pageIndex;

  /// The page's embedded text layer, indexed for search.
  final String? extractedText;

  @override
  String get type => 'pdf';

  @override
  BlockEmbed get asEmbed => BlockEmbed(
    kind: EmbedKind.pdfPage,
    assetId: assetId,
    pageIndex: pageIndex,
    width: frame.width,
    height: frame.height,
    text: extractedText,
  );

  @override
  Iterable<String> get assetIds => <String>[assetId];

  @override
  void writeSearchText(StringBuffer out) {
    if (extractedText != null) out.writeln(extractedText);
  }

  PdfElement copyWith({
    Frame? frame,
    int? z,
    bool? locked,
    int? updatedAt,
    String? extractedText,
  }) => PdfElement(
    id: id,
    frame: frame ?? this.frame,
    createdAt: createdAt,
    updatedAt: updatedAt ?? this.updatedAt,
    assetId: assetId,
    pageIndex: pageIndex,
    z: z ?? this.z,
    locked: locked ?? this.locked,
    extractedText: extractedText ?? this.extractedText,
  );

  @override
  PdfElement withFrame(Frame frame) => copyWith(frame: frame);

  @override
  PdfElement withZ(int z) => copyWith(z: z);

  @override
  PdfElement withLocked(bool locked) => copyWith(locked: locked);

  @override
  PdfElement touch(int timestamp) => copyWith(updatedAt: timestamp);

  @override
  Map<String, Object?> toJson() => <String, Object?>{
    ...baseJson(),
    'assetId': assetId,
    'pageIndex': pageIndex,
    if (extractedText != null) 'extractedText': extractedText,
  };

  static PdfElement fromJson(Map<String, Object?> json) => PdfElement(
    id: readString(json, 'id'),
    frame: Frame.fromJson(readObject(json, 'frame')),
    createdAt: readInt(json, 'createdAt'),
    updatedAt: readInt(json, 'updatedAt'),
    assetId: readString(json, 'assetId'),
    pageIndex: readInt(json, 'pageIndex'),
    z: readInt(json, 'z'),
    locked: readBool(json, 'locked'),
    extractedText: readStringOrNull(json, 'extractedText'),
  );
}

/// A mathematical expression.
///
/// The [source] is always stored in the mode it was authored in, and linear
/// input is translated to LaTeX only at render time. Round-tripping through
/// LaTeX would destroy the user's original keystrokes and make the expression
/// harder to edit later.
final class MathElement extends NoteElement {
  const MathElement({
    required super.id,
    required super.frame,
    required super.createdAt,
    required super.updatedAt,
    required this.source,
    super.z,
    super.locked,
    this.mode = MathMode.linear,
    this.displayStyle = true,
  });

  final String source;
  final MathMode mode;

  /// Whether to typeset in display style (centred, full-size operators) rather
  /// than inline style.
  final bool displayStyle;

  @override
  String get type => 'math';

  @override
  void writeSearchText(StringBuffer out) {
    // The raw source is indexed so that searching "frac" or "alpha" finds the
    // formula, alongside any plain-text fragments it contains.
    out.writeln(source);
  }

  MathElement copyWith({
    Frame? frame,
    int? z,
    bool? locked,
    int? updatedAt,
    String? source,
    MathMode? mode,
    bool? displayStyle,
  }) => MathElement(
    id: id,
    frame: frame ?? this.frame,
    createdAt: createdAt,
    updatedAt: updatedAt ?? this.updatedAt,
    source: source ?? this.source,
    z: z ?? this.z,
    locked: locked ?? this.locked,
    mode: mode ?? this.mode,
    displayStyle: displayStyle ?? this.displayStyle,
  );

  @override
  MathElement withFrame(Frame frame) => copyWith(frame: frame);

  @override
  MathElement withZ(int z) => copyWith(z: z);

  @override
  MathElement withLocked(bool locked) => copyWith(locked: locked);

  @override
  MathElement touch(int timestamp) => copyWith(updatedAt: timestamp);

  @override
  Map<String, Object?> toJson() => <String, Object?>{
    ...baseJson(),
    'source': source,
    'mode': mode.name,
    if (!displayStyle) 'displayStyle': false,
  };

  static MathElement fromJson(Map<String, Object?> json) => MathElement(
    id: readString(json, 'id'),
    frame: Frame.fromJson(readObject(json, 'frame')),
    createdAt: readInt(json, 'createdAt'),
    updatedAt: readInt(json, 'updatedAt'),
    source: readString(json, 'source'),
    z: readInt(json, 'z'),
    locked: readBool(json, 'locked'),
    mode: readEnum(json, 'mode', MathMode.values, MathMode.linear),
    displayStyle: readBool(json, 'displayStyle', true),
  );
}

/// A grid of rich-text cells.
final class TableElement extends NoteElement {
  const TableElement({
    required super.id,
    required super.frame,
    required super.createdAt,
    required super.updatedAt,
    required this.columnWidths,
    required this.rows,
    super.z,
    super.locked,
    this.headerRow = false,
  });

  /// Width of each column in page-space pixels; its length defines the column
  /// count.
  final List<double> columnWidths;

  /// Row-major cell contents. Short rows render as empty trailing cells.
  final List<List<TextBlock>> rows;

  final bool headerRow;

  @override
  String get type => 'table';

  int get columnCount => columnWidths.length;
  int get rowCount => rows.length;

  @override
  void writeSearchText(StringBuffer out) {
    for (final row in rows) {
      for (final cell in row) {
        for (final run in cell.runs) {
          out.write(run.text);
        }
        out.write('\t');
      }
      out.write('\n');
    }
  }

  TableElement copyWith({
    Frame? frame,
    int? z,
    bool? locked,
    int? updatedAt,
    List<double>? columnWidths,
    List<List<TextBlock>>? rows,
    bool? headerRow,
  }) => TableElement(
    id: id,
    frame: frame ?? this.frame,
    createdAt: createdAt,
    updatedAt: updatedAt ?? this.updatedAt,
    columnWidths: columnWidths ?? this.columnWidths,
    rows: rows ?? this.rows,
    z: z ?? this.z,
    locked: locked ?? this.locked,
    headerRow: headerRow ?? this.headerRow,
  );

  @override
  TableElement withFrame(Frame frame) => copyWith(frame: frame);

  @override
  TableElement withZ(int z) => copyWith(z: z);

  @override
  TableElement withLocked(bool locked) => copyWith(locked: locked);

  @override
  TableElement touch(int timestamp) => copyWith(updatedAt: timestamp);

  @override
  Map<String, Object?> toJson() => <String, Object?>{
    ...baseJson(),
    'columnWidths': columnWidths,
    'rows': <Object?>[
      for (final row in rows) <Object?>[for (final cell in row) cell.toJson()],
    ],
    if (headerRow) 'headerRow': true,
  };

  static TableElement fromJson(Map<String, Object?> json) {
    final rawRows = json['rows'];
    final rows = <List<TextBlock>>[];
    if (rawRows is List) {
      for (final rawRow in rawRows) {
        if (rawRow is! List) continue;
        rows.add(<TextBlock>[
          for (final cell in rawRow)
            if (cell is Map) TextBlock.fromJson(cell.cast<String, Object?>()),
        ]);
      }
    }
    return TableElement(
      id: readString(json, 'id'),
      frame: Frame.fromJson(readObject(json, 'frame')),
      createdAt: readInt(json, 'createdAt'),
      updatedAt: readInt(json, 'updatedAt'),
      columnWidths: readDoubleList(json, 'columnWidths'),
      rows: rows,
      z: readInt(json, 'z'),
      locked: readBool(json, 'locked'),
      headerRow: readBool(json, 'headerRow'),
    );
  }
}

/// A named grouping of other elements, which move and scale together.
///
/// Children stay top-level entries in the page's element list and are
/// referenced by id, so grouping never rewrites their geometry and ungrouping
/// is a single deletion.
final class GroupElement extends NoteElement {
  const GroupElement({
    required super.id,
    required super.frame,
    required super.createdAt,
    required super.updatedAt,
    required this.childIds,
    super.z,
    super.locked,
    this.label,
  });

  final List<String> childIds;
  final String? label;

  @override
  String get type => 'group';

  @override
  void writeSearchText(StringBuffer out) {
    if (label != null) out.writeln(label);
  }

  GroupElement copyWith({
    Frame? frame,
    int? z,
    bool? locked,
    int? updatedAt,
    List<String>? childIds,
    String? label,
  }) => GroupElement(
    id: id,
    frame: frame ?? this.frame,
    createdAt: createdAt,
    updatedAt: updatedAt ?? this.updatedAt,
    childIds: childIds ?? this.childIds,
    z: z ?? this.z,
    locked: locked ?? this.locked,
    label: label ?? this.label,
  );

  @override
  GroupElement withFrame(Frame frame) => copyWith(frame: frame);

  @override
  GroupElement withZ(int z) => copyWith(z: z);

  @override
  GroupElement withLocked(bool locked) => copyWith(locked: locked);

  @override
  GroupElement touch(int timestamp) => copyWith(updatedAt: timestamp);

  @override
  Map<String, Object?> toJson() => <String, Object?>{
    ...baseJson(),
    'childIds': childIds,
    if (label != null) 'label': label,
  };

  static GroupElement fromJson(Map<String, Object?> json) => GroupElement(
    id: readString(json, 'id'),
    frame: Frame.fromJson(readObject(json, 'frame')),
    createdAt: readInt(json, 'createdAt'),
    updatedAt: readInt(json, 'updatedAt'),
    childIds: readStringList(json, 'childIds'),
    z: readInt(json, 'z'),
    locked: readBool(json, 'locked'),
    label: readStringOrNull(json, 'label'),
  );
}

/// Pictures and PDF pages sit on the page by themselves or in a text box, as
/// objects in its text; these are the one's terms for the other.
extension EmbedOnPage on BlockEmbed {
  /// This object on the page by itself, in [frame], made at [now].
  NoteElement toElement({required Frame frame, required int now}) =>
      switch (kind) {
        EmbedKind.image => ImageElement(
          id: Ulid.generate(),
          frame: frame,
          createdAt: now,
          updatedAt: now,
          assetId: assetId,
          altText: text,
        ),
        EmbedKind.pdfPage => PdfElement(
          id: Ulid.generate(),
          frame: frame,
          createdAt: now,
          updatedAt: now,
          assetId: assetId,
          pageIndex: pageIndex,
          extractedText: text,
        ),
      };
}
