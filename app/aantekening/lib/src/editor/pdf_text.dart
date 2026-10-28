/// The text and links of PDF pages, to be selected and followed on the
/// page as a reader selects and follows them.
library;

import 'dart:async';
import 'dart:math' as math;
import 'dart:ui';

import 'package:flutter/foundation.dart';
import 'package:pdfrx/pdfrx.dart';

/// A link on a PDF page: where it lies, and where it leads — a web
/// address, or a page of the same PDF, counted from 0.
@immutable
class PdfPageLink {
  const PdfPageLink({required this.areas, this.url, this.page});

  /// Where it lies, in shares of the page from its top-left corner.
  final List<Rect> areas;
  final Uri? url;
  final int? page;
}

/// A line of a PDF page's text: its characters from [start] up to [end],
/// and the box round them, in shares of the page.
typedef PdfLine = ({int start, int end, Rect box});

/// The text of a PDF page and its links, laid over the page in shares of
/// its width and height from its top-left corner, so that the page drawn
/// at any size, wherever it lies, finds them.
///
/// Its lines run the way its text reads: across, or down a page turned on
/// its side, or upside down.
class PdfPageWords {
  PdfPageWords({
    required this.text,
    required this.boxes,
    this.links = const <PdfPageLink>[],
  }) : assert(text.length == boxes.length);

  /// The page's text and links as PDFium reads them, on a page [width] by
  /// [height] points as it is shown. [place] turns a box, measured up from
  /// the page's foot as PDF measures it, into one down from its top as the
  /// page is shown — turned, if it is turned; else it is taken as shown.
  factory PdfPageWords.read(
    PdfPageText text,
    List<PdfLink> links, {
    required double width,
    required double height,
    Rect Function(PdfRect rect)? place,
  }) {
    Rect share(PdfRect rect) {
      final shown =
          place?.call(rect) ??
          Rect.fromLTRB(
            rect.left,
            height - rect.top,
            rect.right,
            height - rect.bottom,
          );
      return Rect.fromLTRB(
        shown.left / width,
        shown.top / height,
        shown.right / width,
        shown.bottom / height,
      );
    }

    return PdfPageWords(
      text: text.fullText,
      boxes: <Rect>[for (final rect in text.charRects) share(rect)],
      links: <PdfPageLink>[
        for (final link in links)
          PdfPageLink(
            areas: <Rect>[for (final rect in link.rects) share(rect)],
            url: link.url,
            page: link.dest == null ? null : link.dest!.pageNumber - 1,
          ),
      ],
    );
  }

  /// The characters, one to each of [boxes].
  final String text;

  /// Where each character lies.
  final List<Rect> boxes;
  final List<PdfPageLink> links;

  /// The way the text reads, and the characters' boxes turned to read
  /// across, as everything here finds them.
  late final _Reading _reading = _Reading.of(text, boxes);
  late final List<Rect> _across = <Rect>[
    for (final box in boxes) _reading.rect(box),
  ];
  late final List<PdfLine> _lines = _linesOf(text, _across);

  /// The lines the characters make, in the order the PDF holds them.
  late final List<PdfLine> lines = <PdfLine>[
    for (final line in _lines)
      (start: line.start, end: line.end, box: _reading.back(line.box)),
  ];

  bool get isEmpty => lines.isEmpty;

  /// The line [at] lies on, a little room left round it, if any.
  PdfLine? lineAt(Offset at) {
    final across = _reading.point(at);
    for (final (index, line) in _lines.indexed) {
      final box = line.box;
      final room = box.height * 0.2;
      if (Rect.fromLTRB(
        box.left - room,
        box.top - room,
        box.right + room,
        box.bottom + room,
      ).contains(across)) {
        return lines[index];
      }
    }
    return null;
  }

  /// Where between the characters [at] falls, from 0, before the first, to
  /// the text's length, after the last: on the line beside or nearest it,
  /// before the first character whose middle lies to its right.
  int caretAt(Offset at) {
    if (_lines.isEmpty) return 0;
    final across = _reading.point(at);
    final line = _lineNearest(across);
    for (var i = line.start; i < line.end; i++) {
      if (_across[i].isEmpty) continue;
      if (_across[i].center.dx > across.dx) return i;
    }
    return line.end;
  }

  /// The word round [at], as the characters from where it begins up to
  /// where it ends; on no word, the character there alone.
  (int, int) wordAt(Offset at) {
    if (_lines.isEmpty) return (0, 0);
    // The character on the line nearest the point that lies nearest it
    // along the line.
    final across = _reading.point(at);
    final line = _lineNearest(across);
    var index = line.start;
    var distance = double.infinity;
    for (var i = line.start; i < line.end; i++) {
      final box = _across[i];
      if (box.isEmpty) continue;
      final away = across.dx < box.left
          ? box.left - across.dx
          : across.dx > box.right
          ? across.dx - box.right
          : 0.0;
      if (away < distance) {
        distance = away;
        index = i;
      }
    }
    if (!_inWord(index)) return (index, index + 1);
    var start = index;
    while (start > 0 && _inWord(start - 1)) {
      start--;
    }
    var end = index + 1;
    while (end < text.length && _inWord(end)) {
      end++;
    }
    return (start, end);
  }

  /// The boxes to light the characters from [from] up to [to] with: one
  /// to each line they cover.
  List<Rect> boxesOf(int from, int to) {
    final shown = <Rect>[];
    for (final line in _lines) {
      final start = math.max(from, line.start);
      final end = math.min(to, line.end);
      Rect? box;
      for (var i = start; i < end; i++) {
        if (_across[i].isEmpty) continue;
        box = box == null ? _across[i] : box.expandToInclude(_across[i]);
      }
      if (box != null) {
        shown.add(
          _reading.back(
            Rect.fromLTRB(box.left, line.box.top, box.right, line.box.bottom),
          ),
        );
      }
    }
    return shown;
  }

  /// The characters from [from] up to [to], as they would be copied.
  String textOf(int from, int to) =>
      text.substring(from.clamp(0, text.length), to.clamp(0, text.length));

  /// The link [at] lies on, if any.
  PdfPageLink? linkAt(Offset at) {
    for (final link in links) {
      for (final area in link.areas) {
        if (area.contains(at)) return link;
      }
    }
    return null;
  }

  /// The line [at], turned to read across, lies on, or else the one
  /// nearest it up or down.
  PdfLine _lineNearest(Offset at) {
    var nearest = _lines.first;
    var distance = double.infinity;
    for (final line in _lines) {
      final box = line.box;
      final away = at.dy < box.top
          ? box.top - at.dy
          : at.dy > box.bottom
          ? at.dy - box.bottom
          : 0.0;
      if (away < distance) {
        distance = away;
        nearest = line;
      }
    }
    return nearest;
  }

  bool _inWord(int index) =>
      RegExp(r"[\p{L}\p{N}_'’-]", unicode: true).hasMatch(text[index]);

  /// The lines [text] makes: a new one after each line break, and where
  /// the next character lies wholly below the one before it.
  static List<PdfLine> _linesOf(String text, List<Rect> boxes) {
    final lines = <PdfLine>[];
    var start = 0;
    Rect? box;
    void end(int at) {
      if (box != null && at > start) {
        lines.add((start: start, end: at, box: box!));
      }
      start = at;
      box = null;
    }

    for (var i = 0; i < text.length; i++) {
      final character = boxes[i];
      if (text[i] == '\n' || text[i] == '\r') {
        end(i);
        start = i + 1;
        continue;
      }
      if (text[i].trim().isEmpty && character.isEmpty) continue;
      final before = box;
      if (before != null &&
          (character.top >= before.bottom - before.height * 0.1 ||
              character.bottom <= before.top)) {
        end(i);
      }
      box = box == null ? character : box!.expandToInclude(character);
    }
    end(text.length);
    return lines;
  }
}

/// The way a page's text reads — [along] the line, from character to
/// character, and [down], from line to line — which turns what lies on the
/// page to read across from left to right, as on an upright page, and back.
class _Reading {
  _Reading(this.along) : down = Offset(-along.dy, along.dx);

  /// The way most of the characters follow one another: across, down a
  /// page turned on its side, up one turned the other way, or back, upside
  /// down.
  factory _Reading.of(String text, List<Rect> boxes) {
    const ways = <Offset>[
      Offset(1, 0),
      Offset(0, 1),
      Offset(0, -1),
      Offset(-1, 0),
    ];
    final votes = List<int>.filled(ways.length, 0);
    for (var i = 1; i < boxes.length; i++) {
      if (boxes[i].isEmpty || boxes[i - 1].isEmpty) continue;
      if (text[i - 1] == '\n' || text[i] == '\n') continue;
      final step = boxes[i].center - boxes[i - 1].center;
      final way = step.dx.abs() >= step.dy.abs()
          ? (step.dx >= 0 ? 0 : 3)
          : (step.dy >= 0 ? 1 : 2);
      votes[way]++;
    }
    var most = 0;
    for (var way = 1; way < ways.length; way++) {
      if (votes[way] > votes[most]) most = way;
    }
    return _Reading(ways[most]);
  }

  final Offset along;
  final Offset down;

  /// [at], turned to read across.
  Offset point(Offset at) => Offset(
    at.dx * along.dx + at.dy * along.dy,
    at.dx * down.dx + at.dy * down.dy,
  );

  /// [box], turned to read across.
  Rect rect(Rect box) => box.isEmpty
      ? Rect.zero
      : Rect.fromPoints(point(box.topLeft), point(box.bottomRight));

  /// [box], read across, turned back as it lies on the page.
  Rect back(Rect box) =>
      Rect.fromPoints(_unturn(box.topLeft), _unturn(box.bottomRight));

  Offset _unturn(Offset at) => along * at.dx + down * at.dy;
}

/// The text and links of the pages of PDFs, read once each and kept: what
/// a page shows does not change.
class PdfWordsCache {
  PdfWordsCache._();

  /// The one every page shares.
  static final PdfWordsCache shared = PdfWordsCache._();

  final Map<String, PdfPageWords?> _read = <String, PdfPageWords?>{};
  final Set<String> _reading = <String>{};

  /// Keeps [words] as the text of page [pageIndex] of the PDF [assetId],
  /// as though it had been read: for tests, where there is no PDFium.
  @visibleForTesting
  void keep(String assetId, int pageIndex, PdfPageWords? words) =>
      _read['$assetId/$pageIndex'] = words;

  /// The text of page [pageIndex] of the PDF [assetId], if it has been
  /// read; else null, and it is read from the PDF [open] gives.
  PdfPageWords? of(
    String assetId,
    int pageIndex, {
    required Future<PdfDocument?> Function() open,
  }) {
    final key = '$assetId/$pageIndex';
    if (_read.containsKey(key)) return _read[key];
    if (_reading.add(key)) {
      unawaited(
        _readPage(open, pageIndex).then((words) {
          _read[key] = words;
          _reading.remove(key);
        }),
      );
    }
    return null;
  }

  static Future<PdfPageWords?> _readPage(
    Future<PdfDocument?> Function() open,
    int pageIndex,
  ) async {
    try {
      final document = await open();
      if (document == null || pageIndex >= document.pages.length) return null;
      final page = document.pages[pageIndex];
      final text = await page.loadStructuredText();
      final links = await page.loadLinks();
      return PdfPageWords.read(
        text,
        links,
        width: page.width,
        height: page.height,
        place: (rect) => rect.toRect(page: page),
      );
    } on Object {
      // A page whose text cannot be read is one without text to select.
      return null;
    }
  }
}
