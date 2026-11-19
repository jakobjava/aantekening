/// The text a page carries on paper: every line of it where it is seen, in
/// the order it is read, to lie unseen over the page's picture in a PDF —
/// so the PDF's text is read, searched and selected as the page's own.
library;

import 'package:aantekening_canvas/aantekening_canvas.dart';
import 'package:aantekening_core/aantekening_core.dart';

import '../ai/offscreen_text.dart';

/// A line of a printed page's text: what it says, where it lies on the
/// page, in page units, and the element it is in — null for the page's
/// title, and what is said with it.
typedef PrintedLine = ({String text, Aabb box, String? elementId});

/// The text of [document], with [header] at its top and [path] — the
/// notebook and sections it is in — above that, in the order it is read.
///
/// The title first, then what is on the page down it, as the in-app AI
/// reads it (`PageDigest`): typed text a line at a time, a formula as its
/// LaTeX; a printout's own text, from [wordsOf], line by line as it stands,
/// with what was typed onto it put where it stands and marked as typed
/// (`SheetReading`); the text read out of a picture; a TikZ picture's
/// source. Handwriting has no text: only the picture shows it.
Future<List<PrintedLine>> printedText(
  PageDocument document, {
  required Future<List<SheetGlyph>> Function(PdfElement printout) wordsOf,
  CanvasHeader? header,
  List<String> path = const <String>[],
}) async {
  final laidOut = await layOutLines(<NoteElement>[
    for (final element in document.elements)
      if (element is TextElement) element,
  ], header: header);
  final linesOf = <String?, List<PrintedLine>>{};
  for (final line in laidOut) {
    (linesOf[line.elementId] ??= <PrintedLine>[]).add(line);
  }

  final digest = PageDigest.of(document, title: '');
  final items = <String, DigestItem>{
    for (final item in digest.items) item.elementId: item,
  };
  final elements = <String, NoteElement>{
    for (final element in document.elements) element.id: element,
  };
  // What was typed onto each sheet: read with it, not apart from it.
  final typedOn = <String, List<String>>{};
  final onSheet = <String>{};
  for (final item in digest.items) {
    final visual = _sheetVisual(digest, item);
    if (visual == null) continue;
    for (final id in visual.elementIds.skip(1)) {
      if (items[id]?.kind != DigestKind.text) continue;
      (typedOn[item.elementId] ??= <String>[]).add(id);
      onSheet.add(id);
    }
  }

  final out = <PrintedLine>[];
  final title = linesOf[null] ?? const <PrintedLine>[];
  if (path.isNotEmpty && title.isNotEmpty) {
    // Where the page is, in the margin above its title.
    final first = title.first.box;
    final high = (first.height * 0.5).clamp(4.0, 12.0);
    final top = (first.top - high - 2).clamp(0.0, first.top);
    final said = path.join(' › ');
    // As wide as its letters are, not stretched: a reader takes a gap
    // between its words for one between columns.
    final wide = (said.length * high * 0.5).clamp(0.0, first.width * 2);
    out.add((
      text: said,
      box: Aabb(first.left, top, first.left + wide, top + high),
      elementId: null,
    ));
  }
  out.addAll(title);

  /// The lines typed in box [id], marked as typed onto a sheet.
  List<PrintedLine> typed(String id) {
    final lines = linesOf[id] ?? const <PrintedLine>[];
    if (lines.isEmpty) return lines;
    return <PrintedLine>[
      for (final (index, line) in lines.indexed)
        (
          text:
              '${index == 0 ? SheetReading.open : ''}${line.text}'
              '${index == lines.length - 1 ? SheetReading.close : ''}',
          box: line.box,
          elementId: line.elementId,
        ),
    ];
  }

  for (final item in digest.items) {
    final id = item.elementId;
    if (onSheet.contains(id)) continue;
    final element = elements[id];
    final onIt = typedOn[id] ?? const <String>[];
    switch (element) {
      case PdfElement():
        final words = await wordsOf(element);
        if (words.isEmpty) {
          out.addAll(_stacked(element.extractedText ?? '', element));
          for (final box in _topDown(onIt, elements)) {
            out.addAll(typed(box));
          }
          continue;
        }
        final pieces = <SheetTyping>[
          for (final box in onIt)
            (
              text: [
                for (final line in linesOf[box] ?? const <PrintedLine>[])
                  line.text,
              ].join('\n'),
              box: elements[box]!.bounds,
            ),
        ];
        for (final part in SheetReading.arrange(words, pieces)) {
          switch (part) {
            case SheetWords(:final text, :final box):
              out.add((text: text, box: box, elementId: id));
            case SheetTyped(:final index):
              out.addAll(typed(onIt[index]));
            case SheetBreak():
              break;
          }
        }
      case ImageElement(:final altText, :final recognizedText):
        out
          ..addAll(
            _stacked(
              <String>[
                if (altText != null && altText.trim().isNotEmpty) altText,
                if (recognizedText != null && recognizedText.trim().isNotEmpty)
                  recognizedText,
              ].join('\n'),
              element,
            ),
          )
          ..addAll(<PrintedLine>[
            for (final box in _topDown(onIt, elements)) ...typed(box),
          ]);
      case TikzElement(:final source):
        out.addAll(_stacked(source, element));
      case TextElement():
        out.addAll(linesOf[id] ?? const <PrintedLine>[]);
      case InkElement() || null:
        break;
    }
  }
  return out;
}

/// The visual [item] is the sheet of — a PDF page or picture shown with
/// what is on it — or null if it is none.
DigestVisual? _sheetVisual(PageDigest digest, DigestItem item) {
  if (item.kind != DigestKind.pdfPage && item.kind != DigestKind.picture) {
    return null;
  }
  for (final id in item.visualIds) {
    final visual = digest.visual(id);
    if (visual != null &&
        visual.elementIds.isNotEmpty &&
        visual.elementIds.first == item.elementId) {
      return visual;
    }
  }
  return null;
}

/// [ids] in the order they stand on the page, top down.
List<String> _topDown(List<String> ids, Map<String, NoteElement> elements) =>
    <String>[...ids]..sort(
      (a, b) => elements[a]!.bounds.top.compareTo(elements[b]!.bounds.top),
    );

/// [text], which has no places of its own, laid over [element] a line under
/// another from its top: found where it belongs, if not where each word is.
List<PrintedLine> _stacked(String text, NoteElement element) {
  final lines = <String>[
    for (final line in text.split('\n'))
      if (line.trim().isNotEmpty) line.trim(),
  ];
  if (lines.isEmpty) return const <PrintedLine>[];
  final box = element.bounds;
  final high = (box.height / lines.length).clamp(1.0, 14.0);
  return <PrintedLine>[
    for (final (index, line) in lines.indexed)
      (
        text: line,
        box: Aabb(
          box.left,
          box.top + index * high,
          box.right,
          box.top + (index + 1) * high,
        ),
        elementId: element.id,
      ),
  ];
}
