/// A page as a machine reads it: its content in reading order, as passages
/// that can each be cited, and the pictures, PDF pages and drawings on it as
/// visuals to be looked at.
library;

import 'dart:math' as math;

import '../document/elements.dart';
import '../document/ink.dart';
import '../document/page_document.dart';
import '../document/rich_text.dart';
import '../document/text_tables.dart';
import '../link/note_link.dart';
import '../util/geometry.dart';
import 'rich_markdown.dart';

/// What a part of a page is.
enum DigestKind {
  /// Typed text, and the formulas and tables written in it.
  text,

  /// A formula placed on the page by itself.
  formula,

  /// A table placed on the page by itself.
  table,

  /// A picture.
  picture,

  /// A page of a PDF.
  pdfPage,

  /// Handwriting or a drawing made with the pen or highlighter.
  drawing,
}

/// One unit of a page that can be cited: a paragraph, a list item, a row of
/// a table, a formula, the text on a PDF page — and where it is.
class DigestPassage {
  const DigestPassage(
    this.text,
    this.link, {
    this.sentences = const <DigestPassage>[],
  });

  /// Markdown, formulas as `$…$` in LaTeX.
  final String text;

  /// Where on the page it is.
  final NoteLink link;

  /// Its sentences, each linked to its words, where it has more than one;
  /// otherwise none, and it is a sentence itself.
  final List<DigestPassage> sentences;

  /// What of it can be cited on its own: its sentences, or it whole.
  List<DigestPassage> get citable =>
      sentences.isEmpty ? <DigestPassage>[this] : sentences;

  @override
  String toString() => text;
}

/// One thing on a page, and what it says.
class DigestItem {
  const DigestItem({
    required this.elementId,
    required this.kind,
    required this.bounds,
    this.passages = const <DigestPassage>[],
    this.visualIds = const <String>[],
    this.notes = const <String>[],
  });

  final String elementId;
  final DigestKind kind;

  /// Where it is on the page, in page units from its top-left corner.
  final Aabb bounds;

  /// What it says, in reading order.
  final List<DigestPassage> passages;

  /// The visuals showing it, or showing what is in it.
  final List<String> visualIds;

  /// What a reader should know about it that its text does not say: that
  /// it is the page's background, that there is writing over it.
  final List<String> notes;
}

/// Something on a page to look at rather than read: a picture, a PDF page,
/// a drawing — with the handwriting over it, which only makes sense seen
/// together with what it was written on.
class DigestVisual {
  const DigestVisual({
    required this.id,
    required this.kind,
    required this.description,
    required this.link,
    this.bounds,
    this.elementIds = const <String>[],
    this.assetId,
    this.pdfPageIndex,
    this.annotated = false,
  });

  /// Tells the visuals of one page apart: `v1`, `v2`, …
  final String id;

  /// What it mainly shows.
  final DigestKind kind;

  /// A sentence saying what it is, for a reader that cannot see it.
  final String description;

  /// Where on the page it is.
  final NoteLink link;

  /// The region of the page to draw, with [elementIds] in it, or null for
  /// an object in a text box, drawn from its asset alone.
  final Aabb? bounds;
  final List<String> elementIds;

  /// The picture or PDF it shows, and which page of the PDF.
  final String? assetId;
  final int? pdfPageIndex;

  /// Whether there is handwriting or drawing over the picture or PDF page.
  final bool annotated;
}

/// A page taken apart for a machine to read (see the library comment).
///
/// Every kind of element describes itself here, in one exhaustive switch:
/// a new kind of element does not compile until it says what it is to a
/// reader that is not a person — the promise that whatever a page can hold,
/// the AI can understand.
class PageDigest {
  const PageDigest({
    required this.pageId,
    required this.title,
    required this.items,
    required this.visuals,
    this.createdAt,
  });

  /// Takes [document] apart, titled [title] and made at [createdAt].
  factory PageDigest.of(
    PageDocument document, {
    required String title,
    DateTime? createdAt,
  }) => _DigestBuilder(document).build(title, createdAt);

  final String pageId;
  final String title;
  final DateTime? createdAt;

  /// What is on the page, in reading order: down the page, and across where
  /// things sit side by side.
  final List<DigestItem> items;

  final List<DigestVisual> visuals;

  NoteLink get link => NoteLink.page(pageId);

  /// Every passage on the page, in reading order.
  Iterable<DigestPassage> get passages => items.expand((item) => item.passages);

  /// Roughly how long the page's text is, in characters.
  int get length => passages.fold(0, (total, p) => total + p.text.length);

  bool get isEmpty => items.isEmpty;

  DigestVisual? visual(String id) =>
      visuals.where((visual) => visual.id == id).firstOrNull;
}

class _DigestBuilder {
  _DigestBuilder(this.document);

  final PageDocument document;
  final List<DigestVisual> _visuals = <DigestVisual>[];

  /// How much of something has to lie on a PDF page or picture to count as
  /// written on it.
  static const double _overlap = 0.5;

  /// How close, in page units, drawings have to be to count as one.
  static const double _drawingGap = 40;

  /// What lies on each sheet — handwriting, and typed text boxes — by the
  /// sheet's id: the PDF page, picture or printout box everything on it is
  /// shown with.
  final Map<String, List<NoteElement>> _on = <String, List<NoteElement>>{};

  /// The sheet each thing on one lies on.
  final Map<String, NoteElement> _sheetOf = <String, NoteElement>{};

  /// The visual of each sheet, by the sheet's id.
  final Map<String, DigestVisual> _sheetVisual = <String, DigestVisual>{};

  PageDigest build(String title, DateTime? createdAt) {
    final elements = document.elements;
    _findSheets(elements);
    for (final element in elements) {
      if (_isSheet(element) && !_sheetOf.containsKey(element.id)) {
        final visual = _sheetVisualOf(element);
        if (visual != null) _sheetVisual[element.id] = visual;
      }
    }
    final loose = <InkElement>[
      for (final element in elements)
        if (element is InkElement &&
            element.strokes.isNotEmpty &&
            !_sheetOf.containsKey(element.id))
          element,
    ];
    final items = <DigestItem>[
      for (final element in elements) ?_describe(element),
      ..._drawings(loose),
    ]..sort(_readingOrder);
    return PageDigest(
      pageId: document.id,
      title: title,
      createdAt: createdAt,
      items: items,
      visuals: List<DigestVisual>.unmodifiable(_visuals),
    );
  }

  /// A PDF page, a picture, or a text box holding one: something written on
  /// — a worksheet, a printout — whose writing only makes sense seen on it.
  static bool _isSheet(NoteElement element) => switch (element) {
    ImageElement() || PdfElement() => true,
    TextElement(:final blocks) => blocks.any((block) => block.isEmbed),
    _ => false,
  };

  /// Whether [element] can be written on a sheet: handwriting, or a typed
  /// text box.
  static bool _canLieOn(NoteElement element) => switch (element) {
    InkElement(:final strokes) => strokes.isNotEmpty,
    TextElement() => true,
    _ => false,
  };

  /// Works out what lies on what: each stroke of handwriting and each text
  /// box on the topmost sheet it mostly lies on, and that on the sheet under
  /// it, if it lies on one — everything shown with the sheet at the bottom.
  void _findSheets(List<NoteElement> elements) {
    final direct = <String, NoteElement>{};
    for (final element in elements) {
      if (!_canLieOn(element)) continue;
      NoteElement? under;
      for (final sheet in elements) {
        if (identical(sheet, element) || !_isSheet(sheet)) continue;
        if (_share(element.bounds, sheet.bounds) < _overlap) continue;
        // A sheet no larger than what lies on it is not under it.
        if (_area(sheet.bounds) <= _area(element.bounds)) continue;
        if (under == null || sheet.z > under.z) under = sheet;
      }
      if (under != null) direct[element.id] = under;
    }
    for (final MapEntry(key: id, value: sheet) in direct.entries) {
      var bottom = sheet;
      final seen = <String>{id};
      // Down to the sheet at the bottom, never round a loop of them.
      while (true) {
        final lower = direct[bottom.id];
        if (lower == null || !seen.add(bottom.id)) break;
        bottom = lower;
      }
      _sheetOf[id] = bottom;
      (_on[bottom.id] ??= <NoteElement>[]).add(
        elements.firstWhere((e) => e.id == id),
      );
    }
  }

  /// The visual of [sheet] with everything on it, or null for a text box
  /// holding pictures with nothing written on it, whose pictures are shown
  /// on their own.
  DigestVisual? _sheetVisualOf(NoteElement sheet) {
    final on = _on[sheet.id] ?? const <NoteElement>[];
    final link = NoteLink.page(document.id, elementId: sheet.id);
    final (kind, what, assetId, pdfPage) = switch (sheet) {
      PdfElement(:final assetId, :final pageIndex) => (
        DigestKind.pdfPage,
        'Page ${pageIndex + 1} of a PDF',
        assetId,
        pageIndex,
      ),
      ImageElement(:final assetId) => (
        DigestKind.picture,
        'A picture',
        assetId,
        null,
      ),
      _ => (DigestKind.pdfPage, 'A printout in a text box', null, null),
    };
    if (sheet is TextElement && on.isEmpty) return null;
    return _addVisual(
      kind: kind,
      description: _written(what, on),
      link: link,
      bounds: Aabb.around(<Aabb>[sheet.bounds, for (final e in on) e.bounds]),
      elementIds: <String>[sheet.id, for (final e in on) e.id],
      assetId: assetId,
      pdfPageIndex: pdfPage,
      annotated: on.isNotEmpty,
    );
  }

  /// [what], and what is written on it.
  static String _written(String what, List<NoteElement> on) {
    final hand = on.any((e) => e is InkElement);
    final typed = on.any((e) => e is TextElement);
    if (!hand && !typed) return what;
    final writing = <String>[
      if (hand) 'handwriting or drawing',
      if (typed) 'typed text boxes',
    ].join(' and ');
    return '$what, with $writing on it — shown together, as it is on the page';
  }

  /// [element] for a reader, or null for one with nothing to say — a group,
  /// whose members say it, an empty box, or writing on a sheet, which its
  /// sheet's visual shows.
  DigestItem? _describe(NoteElement element) {
    final link = NoteLink.page(document.id, elementId: element.id);
    final background = element.locked
        ? const <String>['set as the page\'s background']
        : const <String>[];
    final sheet = _sheetVisual[element.id];
    final on = _on[element.id] ?? const <NoteElement>[];
    final onSheet = _sheetOf[element.id];
    final written = on.isEmpty
        ? const <String>[]
        : <String>[
            'what is written on it is shown with it in visual ${sheet!.id}',
          ];
    switch (element) {
      case TextElement():
        return _text(element, onSheet: onSheet, own: sheet);
      case MathElement(:final source):
        return DigestItem(
          elementId: element.id,
          kind: DigestKind.formula,
          bounds: element.bounds,
          passages: <DigestPassage>[DigestPassage('\$\$$source\$\$', link)],
        );
      case TableElement(:final rows):
        return DigestItem(
          elementId: element.id,
          kind: DigestKind.table,
          bounds: element.bounds,
          passages: <DigestPassage>[
            for (final row in rows)
              DigestPassage(
                '| ${row.map((cell) => RichMarkdown.block(cell)).join(' | ')} |',
                link,
              ),
          ],
        );
      case ImageElement(:final altText, :final recognizedText):
        return DigestItem(
          elementId: element.id,
          kind: DigestKind.picture,
          bounds: element.bounds,
          visualIds: <String>[?sheet?.id],
          passages: <DigestPassage>[
            if (altText != null && altText.isNotEmpty)
              DigestPassage('Picture: $altText', link),
            if (recognizedText != null && recognizedText.isNotEmpty)
              DigestPassage('Text in the picture: $recognizedText', link),
          ],
          notes: <String>[...background, ...written],
        );
      case PdfElement(:final pageIndex, :final extractedText):
        return DigestItem(
          elementId: element.id,
          kind: DigestKind.pdfPage,
          bounds: element.bounds,
          visualIds: <String>[?sheet?.id],
          passages: <DigestPassage>[
            if (extractedText != null && extractedText.isNotEmpty)
              DigestPassage(
                'Text on page ${pageIndex + 1} of the PDF: $extractedText',
                link,
              ),
          ],
          notes: <String>[...background, ...written],
        );
      case InkElement():
        // Drawings are gathered up by where they are, in _drawings; writing
        // on a sheet is in the sheet's visual.
        return null;
      case GroupElement():
        return null;
    }
  }

  /// [box]'s text, lying on [onSheet] if it lies on one; with [own], the
  /// visual of what is written on the printouts it holds.
  DigestItem? _text(
    TextElement box, {
    NoteElement? onSheet,
    DigestVisual? own,
  }) {
    final blocks = box.blocks;
    final passages = <DigestPassage>[];
    // Its pictures are shown with the sheet it lies on, or with what is
    // written on them, or else each on its own.
    final shown = onSheet == null ? own : _sheetVisual[onSheet.id];
    final visualIds = <String>[?shown?.id];
    final ordinals = _ordinals(blocks);
    var i = 0;
    while (i < blocks.length) {
      final block = blocks[i];
      final link = NoteLink.page(document.id, elementId: box.id, block: i);
      final table = TextTables.tableAt(blocks, i);
      if (table != null) {
        final rows = RichMarkdown.tableRows(blocks, table);
        // The head and the line under it are one passage; each row another.
        passages
          ..add(DigestPassage('${rows[0]}\n${rows[1]}', link))
          ..addAll(<DigestPassage>[
            for (final row in rows.skip(2)) DigestPassage(row, link),
          ]);
        i = table.end;
        continue;
      }
      final embed = block.embed;
      if (embed != null) {
        final pdf = embed.kind == EmbedKind.pdfPage;
        final visual =
            shown ??
            _addVisual(
              kind: pdf ? DigestKind.pdfPage : DigestKind.picture,
              description: pdf
                  ? 'Page ${embed.pageIndex + 1} of a PDF, in the text'
                  : 'A picture, in the text',
              link: link,
              assetId: embed.assetId,
              pdfPageIndex: pdf ? embed.pageIndex : null,
            );
        if (!visualIds.contains(visual.id)) visualIds.add(visual.id);
        passages.add(
          DigestPassage(
            pdf
                ? '[PDF page ${embed.pageIndex + 1}, in visual ${visual.id}]'
                      '${embed.text == null ? '' : ' Text on it: ${embed.text}'}'
                : '[Picture, in visual ${visual.id}]'
                      '${embed.text == null ? '' : ' ${embed.text}'}',
            link,
          ),
        );
      } else if (block.plainText.trim().isNotEmpty) {
        passages.add(
          DigestPassage(
            RichMarkdown.block(block, ordinal: ordinals[i]),
            link,
            sentences: <DigestPassage>[
              for (final sentence in RichMarkdown.sentences(block))
                DigestPassage(
                  sentence.text,
                  link.toWords(sentence.from, sentence.to),
                ),
            ],
          ),
        );
      }
      i++;
    }
    if (passages.isEmpty) return null;
    return DigestItem(
      elementId: box.id,
      kind: DigestKind.text,
      bounds: box.bounds,
      passages: passages,
      visualIds: visualIds,
      notes: <String>[
        if (_sheetVisual[onSheet?.id] case final sheet?)
          'typed onto ${_sheetName(sheet)}, where it answers or labels what '
              'is there — see visual ${sheet.id}',
        if (own != null)
          'what is written on its printouts is in visual ${own.id}',
      ],
    );
  }

  /// Drawings not on a sheet, those close together as one.
  List<DigestItem> _drawings(List<InkElement> loose) {
    final groups = <List<InkElement>>[];
    for (final drawing in loose) {
      final near = groups
          .where(
            (group) => group.any(
              (other) => _gap(other.bounds, drawing.bounds) <= _drawingGap,
            ),
          )
          .toList();
      final merged = <InkElement>[for (final group in near) ...group, drawing];
      groups
        ..removeWhere(near.contains)
        ..add(merged);
    }
    return <DigestItem>[for (final group in groups) _drawing(group)];
  }

  DigestItem _drawing(List<InkElement> group) {
    final first = group.first;
    final bounds = Aabb.around(group.map((element) => element.bounds));
    final strokes = group.fold(0, (total, e) => total + e.strokes.length);
    final highlighted = group.every(
      (e) => e.strokes.every((stroke) => stroke.tool == InkTool.highlighter),
    );
    final link = NoteLink.page(document.id, elementId: first.id);
    final visual = _addVisual(
      kind: DigestKind.drawing,
      description: highlighted
          ? 'Highlighter strokes'
          : 'Handwriting or a drawing, $strokes strokes',
      link: link,
      bounds: bounds,
      elementIds: <String>[for (final e in group) e.id],
    );
    return DigestItem(
      elementId: first.id,
      kind: DigestKind.drawing,
      bounds: bounds,
      visualIds: <String>[visual.id],
      notes: <String>[
        'handwritten or drawn; only the visual shows what it says',
      ],
    );
  }

  DigestVisual _addVisual({
    required DigestKind kind,
    required String description,
    required NoteLink link,
    Aabb? bounds,
    List<String> elementIds = const <String>[],
    String? assetId,
    int? pdfPageIndex,
    bool annotated = false,
  }) {
    final visual = DigestVisual(
      id: 'v${_visuals.length + 1}',
      kind: kind,
      description: description,
      link: link,
      bounds: bounds,
      elementIds: elementIds,
      assetId: assetId,
      pdfPageIndex: pdfPageIndex,
      annotated: annotated,
    );
    _visuals.add(visual);
    return visual;
  }

  /// What a sheet's [visual] shows, in a few words: "page 3 of a PDF".
  static String _sheetName(DigestVisual visual) {
    final what = visual.description.split(',').first;
    return what[0].toLowerCase() + what.substring(1);
  }

  static double _area(Aabb box) =>
      math.max(box.width, 1.0) * math.max(box.height, 1.0);

  /// How much of [a] lies within [b], from none to all of it.
  static double _share(Aabb a, Aabb b) {
    final width = math.min(a.right, b.right) - math.max(a.left, b.left);
    final height = math.min(a.bottom, b.bottom) - math.max(a.top, b.top);
    if (width <= 0 || height <= 0) return 0;
    return width * height / _area(a);
  }

  /// The distance between [a] and [b], or zero where they meet.
  static double _gap(Aabb a, Aabb b) {
    final dx = math.max(
      0.0,
      math.max(a.left, b.left) - math.min(a.right, b.right),
    );
    final dy = math.max(
      0.0,
      math.max(a.top, b.top) - math.min(a.bottom, b.bottom),
    );
    return math.sqrt(dx * dx + dy * dy);
  }

  /// Down the page, and across for things that start at much the same
  /// height.
  static int _readingOrder(DigestItem a, DigestItem b) {
    const sameRow = 24.0;
    final down = a.bounds.top - b.bounds.top;
    if (down.abs() > sameRow) return down.sign.toInt();
    return (a.bounds.left - b.bounds.left).sign.toInt();
  }

  /// The number of each numbered item in [blocks], as a list shows it.
  static List<int> _ordinals(List<TextBlock> blocks) {
    final out = List<int>.filled(blocks.length, 1);
    var count = 0;
    for (var i = 0; i < blocks.length; i++) {
      final numbered = blocks[i].kind == TextBlockKind.numbered;
      count = numbered ? count + 1 : 0;
      out[i] = numbered ? count : 1;
    }
    return out;
  }
}
