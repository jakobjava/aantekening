/// A printout's own text and what was typed onto it, read as one: the
/// sheet's lines in the order they stand on it, and each answer, label or
/// note typed onto it put where it stands — in the blank after "Name:", on
/// the line under a task — rather than after the sheet's text, in pieces.
library;

import 'dart:math' as math;

import '../util/geometry.dart';

/// A word of a sheet's own text, and where it lies on the page, in page
/// units. Words are read a space apart, as the text holds them.
typedef SheetGlyph = ({String text, Aabb box});

/// Text typed onto a sheet, as Markdown, and where its box lies on the
/// page, in page units.
typedef SheetTyping = ({String text, Aabb box});

/// Reads a sheet's text with what was typed onto it (see the library
/// comment).
abstract final class SheetReading {
  /// What marks text typed onto a sheet, before and after it.
  static const String open = '⟦';
  static const String close = '⟧';

  /// A word that is only a blank to fill in: a rule of underscores or dots.
  static final RegExp _blank = RegExp(r'^[_.…·]{3,}$');

  /// The sheet lying at [sheet], its own text [glyphs], with [typed] onto it.
  ///
  /// Its words make its lines, top down and each read across, whatever
  /// order the PDF holds them in — a text read out of a scan by machine
  /// holds them in many. A piece of typing whose first line stands on a
  /// line of the sheet is put into that line where it begins, or, written
  /// over more than one line, under it; one standing between lines is put
  /// between them. A blank the typing covers — the rule it was typed on,
  /// the empty lines an answer fills — is left out; one left empty stays,
  /// saying so. With no lines to put them in, the pieces are listed by
  /// where they stand ([listed]).
  static String read(
    Aabb sheet,
    List<SheetGlyph> glyphs,
    List<SheetTyping> typed,
  ) {
    final parts = arrange(glyphs, typed);
    if (!parts.any((part) => part is SheetWords)) return listed(sheet, typed);
    final out = <String>[];
    final line = StringBuffer();
    void put(String text, {bool apart = false}) {
      if (line.isNotEmpty) line.write(apart ? '   ' : ' ');
      line.write(text);
    }

    void end() {
      if (line.isNotEmpty) out.add('$line');
      line.clear();
    }

    for (final part in parts) {
      switch (part) {
        case SheetWords(:final text, :final apart):
          put(text, apart: apart);
        case SheetTyped(:final index, :final inline):
          final text = '$open${typed[index].text.trim()}$close';
          if (inline) {
            put(text);
          } else {
            end();
            out.add(text);
          }
        case SheetBreak():
          end();
      }
    }
    end();
    return out.join('\n');
  }

  /// The order [glyphs], a sheet's own words, and [typed] onto it are read
  /// in (see [read]): runs of words, what was typed — by its place in
  /// [typed], in a line or on one of its own — and where lines end. A
  /// blank the typing covers, and the lines of blanks it was typed into,
  /// are left out; a word drawn twice in one place is read once.
  static List<SheetPart> arrange(
    List<SheetGlyph> glyphs,
    List<SheetTyping> typed,
  ) {
    final lines = _lines(glyphs);
    final pieces = <int>[
      for (final (index, piece) in typed.indexed)
        if (piece.text.trim().isNotEmpty) index,
    ];
    if (lines.isEmpty) {
      return <SheetPart>[
        for (final index
            in pieces..sort(
              (a, b) => typed[a].box.top.compareTo(typed[b].box.top),
            )) ...<SheetPart>[
          SheetTyped(index, inline: false),
          const SheetBreak(),
        ],
      ];
    }
    final heights = <double>[for (final line in lines) line.height]..sort();
    final lineHeight = heights[heights.length ~/ 2];

    // Into each line, where it begins.
    final inline = <int, List<int>>{};
    // Under each line, the first being above the first line.
    final under = <int, List<int>>{};
    for (final index in pieces) {
      final piece = typed[index];
      final text = piece.text.trim();
      final box = piece.box;
      // Where its first line of text is: a box of one line, a formula
      // standing taller than its line, is that line; the first line of a
      // longer one stands at its top, as high as a line of the sheet's and
      // a half.
      final oneLine = !text.contains('\n') && box.height <= lineHeight * 6;
      final firstTop = box.top;
      final firstBottom = oneLine
          ? box.bottom
          : box.top + math.min(box.height, lineHeight * 1.5);
      final firstMiddle = (firstTop + firstBottom) / 2;
      int? on;
      var best = 0.0;
      for (final (at, line) in lines.indexed) {
        final overlap =
            math.min(line.bottom, firstBottom) - math.max(line.top, firstTop);
        final share = overlap / math.max(line.height, 1);
        if (share < 0.5) continue;
        final nearer =
            on != null &&
            share == best &&
            (line.middle - firstMiddle).abs() <
                (lines[on].middle - firstMiddle).abs();
        if (share > best || nearer) {
          on = at;
          best = share;
        }
      }
      // A line in the top of a box of one line is above its text, the box
      // standing taller than what it holds: it is typed under that line.
      final above =
          on != null &&
          oneLine &&
          lines[on].middle < box.top + box.height / 4 &&
          box.height > lines[on].height * 2;
      if (on != null && !text.contains('\n') && !above) {
        (inline[on] ??= <int>[]).add(index);
      } else if (on != null) {
        (under[on + 1] ??= <int>[]).add(index);
      } else {
        final below = lines.indexWhere((line) => line.middle > firstMiddle);
        (under[below < 0 ? lines.length : below] ??= <int>[]).add(index);
      }
    }

    final filled = <SheetTyping>[for (final index in pieces) typed[index]];
    final out = <SheetPart>[];
    // Whether typing came last: the lines of blanks after it are the room
    // it was typed into, however far down its box reaches.
    var typedLast = false;
    void putUnder(int slot) {
      final here = under[slot];
      if (here == null) return;
      typedLast = true;
      here.sort((a, b) => typed[a].box.top.compareTo(typed[b].box.top));
      for (final index in here) {
        out
          ..add(SheetTyped(index, inline: false))
          ..add(const SheetBreak());
      }
    }

    for (final (index, line) in lines.indexed) {
      putUnder(index);
      final into = inline[index] ?? const <int>[];
      if (line.blank && into.isEmpty && typedLast) continue;
      final parts = line.parts(into, typed, filled: filled);
      if (parts.isNotEmpty) {
        out
          ..addAll(parts)
          ..add(const SheetBreak());
      }
      typedLast = into.isNotEmpty || (line.blank && typedLast);
    }
    putUnder(lines.length);
    return out;
  }

  /// [typed] onto the sheet lying at [sheet], top down, each said with
  /// where on the sheet it stands: for a sheet whose own text has no
  /// places — a picture's, a scan's.
  static String listed(Aabb sheet, List<SheetTyping> typed) {
    final pieces =
        <SheetTyping>[
          for (final piece in typed)
            if (piece.text.trim().isNotEmpty) piece,
        ]..sort((a, b) {
          final down = a.box.top.compareTo(b.box.top);
          return down != 0 ? down : a.box.left.compareTo(b.box.left);
        });
    String share(double at, double from, double size) =>
        '${((at - from) / math.max(size, 1) * 100).clamp(0, 100).round()}%';
    return <String>[
      for (final piece in pieces)
        '- ${share(piece.box.top, sheet.top, sheet.height)} down, '
            '${share(piece.box.left, sheet.left, sheet.width)} across: '
            '$open${piece.text.trim().replaceAll('\n', '\n  ')}$close',
    ].join('\n');
  }

  /// The lines [glyphs] make, top down: each word on the line it shares
  /// most of its height with, if that is at least half of it.
  static List<_Line> _lines(List<SheetGlyph> glyphs) {
    final shown = <SheetGlyph>[
      for (final glyph in glyphs)
        if (glyph.text.trim().isNotEmpty &&
            !_marksAlone(glyph.text.trim()) &&
            glyph.box.width > 0 &&
            glyph.box.height > 0)
          (text: glyph.text.trim(), box: glyph.box),
    ]..sort((a, b) => a.box.centerY.compareTo(b.box.centerY));
    final lines = <_Line>[];
    for (final glyph in shown) {
      _Line? best;
      var most = 0.5;
      for (final line in lines) {
        final share = line.share(glyph.box);
        if (share >= most) {
          best = line;
          most = share;
        }
      }
      (best ?? (lines..add(_Line())).last).add(glyph);
    }
    return lines..sort((a, b) => a.middle.compareTo(b.middle));
  }

  /// Whether [text] is only marks drawn over another letter — the arrow
  /// over a vector — which a PDF may hold apart from it, as a line of their
  /// own.
  static bool _marksAlone(String text) => text.runes.every(
    (rune) =>
        (rune >= 0x0300 && rune <= 0x036F) ||
        (rune >= 0x20D0 && rune <= 0x20FF),
  );

  /// Whether [box], a blank, is covered by any of [pieces]: across most of
  /// its height, and somewhere along its width.
  static bool _covered(Aabb box, List<SheetTyping> pieces) => pieces.any(
    (piece) =>
        math.min(box.bottom, piece.box.bottom + box.height / 2) -
                math.max(box.top, piece.box.top) >=
            box.height / 2 &&
        math.min(box.right, piece.box.right) >
            math.max(box.left, piece.box.left),
  );
}

/// A line of a sheet's text: its words, and the band they stand in.
class _Line {
  final List<SheetGlyph> _glyphs = <SheetGlyph>[];
  double _middles = 0;
  double _heights = 0;

  /// Where the middle of its words is, on average, and how tall they are.
  double get middle => _middles / _glyphs.length;
  double get height => _heights / _glyphs.length;
  double get top => middle - height / 2;
  double get bottom => middle + height / 2;

  /// Whether it is only blanks to fill in.
  bool get blank =>
      _glyphs.every((glyph) => SheetReading._blank.hasMatch(glyph.text));

  void add(SheetGlyph glyph) {
    _glyphs.add(glyph);
    _middles += glyph.box.centerY;
    _heights += glyph.box.height;
  }

  /// How much of [box]'s height, or of the line's if it is the smaller,
  /// the two share.
  double share(Aabb box) {
    final overlap = math.min(bottom, box.bottom) - math.max(top, box.top);
    return overlap / math.max(math.min(height, box.height), 0.5);
  }

  /// Its words read across, in runs, with the pieces of [typed] at
  /// [into] put in among them where each begins, and the blanks any of
  /// [filled] covers left out. None for a line of blanks all filled.
  List<SheetPart> parts(
    List<int> into,
    List<SheetTyping> typed, {
    required List<SheetTyping> filled,
  }) {
    final glyphs = <SheetGlyph>[..._glyphs]
      ..sort((a, b) => a.box.left.compareTo(b.box.left));
    final pieces = <int>[...into]
      ..sort((a, b) => typed[a].box.left.compareTo(typed[b].box.left));
    final out = <SheetPart>[];
    var words = <SheetGlyph>[];
    var apart = false;
    void endWords() {
      if (words.isNotEmpty) out.add(SheetWords(words, apart: apart));
      words = <SheetGlyph>[];
      apart = false;
    }

    var next = 0;
    void putTyping(double before) {
      while (next < pieces.length && typed[pieces[next]].box.left < before) {
        endWords();
        out.add(SheetTyped(pieces[next], inline: true));
        next++;
      }
    }

    SheetGlyph? last;
    var lastRight = double.negativeInfinity;
    // How much typing was put before the word written last.
    var typedBefore = 0;
    for (final glyph in glyphs) {
      // A word drawn twice in one place, as a PDF fakes bold, is read once.
      if (last != null &&
          last.text == glyph.text &&
          (last.box.left - glyph.box.left).abs() < glyph.box.width / 2 &&
          (last.box.top - glyph.box.top).abs() < glyph.box.height / 2) {
        continue;
      }
      last = glyph;
      putTyping(glyph.box.centerX);
      if (SheetReading._blank.hasMatch(glyph.text) &&
          SheetReading._covered(glyph.box, filled)) {
        continue;
      }
      // Far from the word before it, it is in a column or cell of its own;
      // after what was typed into the gap, it goes on from it.
      if (out.isNotEmpty || words.isNotEmpty) {
        if (next == typedBefore && glyph.box.left - lastRight > height * 3) {
          endWords();
          apart = true;
        }
      }
      words.add(glyph);
      typedBefore = next;
      lastRight = glyph.box.right;
    }
    endWords();
    putTyping(double.infinity);
    return out;
  }
}

/// What a sheet's text is read as, one after another (see
/// [SheetReading.arrange]).
sealed class SheetPart {
  const SheetPart();
}

/// Words of a line of a sheet, read one after another, a space apart:
/// [apart] from what comes before them on their line, in a column or cell
/// of their own.
final class SheetWords extends SheetPart {
  const SheetWords(this.words, {this.apart = false});

  final List<SheetGlyph> words;
  final bool apart;

  String get text => words.map((word) => word.text).join(' ');

  /// Where they lie, together.
  Aabb get box => Aabb.around(words.map((word) => word.box));
}

/// What was typed onto a sheet, by its place among what was given:
/// [inline], put into a line of the sheet; else on a line of its own.
final class SheetTyped extends SheetPart {
  const SheetTyped(this.index, {required this.inline});

  final int index;
  final bool inline;
}

/// Where a line ends.
final class SheetBreak extends SheetPart {
  const SheetBreak();
}
