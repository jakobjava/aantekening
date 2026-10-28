/// Writing a PDF: pages of pictures, with a table of contents.
library;

import 'dart:convert';
import 'dart:io' show ZLibEncoder;
import 'dart:typed_data';

/// A picture made ready to put in a PDF: its rows filtered as PNG filters
/// them, each the way that leaves least to store, and deflated.
///
/// Making one takes a while for a large picture, and needs nothing but the
/// pixels, so it can be done on an isolate of its own.
final class PdfImage {
  PdfImage._(this.width, this.height, this.data);

  /// [pixels], [width] by [height], four bytes to a pixel — red, green,
  /// blue and alpha, the colours multiplied by the alpha, as Flutter gives
  /// them — laid over white.
  factory PdfImage.rgba(Uint8List pixels, int width, int height) {
    if (pixels.length != width * height * 4) {
      throw ArgumentError(
        '$width×$height pixels are not ${pixels.length} '
        'bytes',
      );
    }
    final stride = width * 3;
    final rgb = Uint8List(stride * height);
    for (var from = 0, to = 0; from < pixels.length; from += 4, to += 3) {
      final clear = 255 - pixels[from + 3];
      rgb[to] = pixels[from] + clear;
      rgb[to + 1] = pixels[from + 1] + clear;
      rgb[to + 2] = pixels[from + 2] + clear;
    }
    return PdfImage._(width, height, _deflate(_filtered(rgb, stride, height)));
  }

  final int width;
  final int height;

  /// The filtered and deflated rows.
  final Uint8List data;

  /// [rgb]'s rows, [stride] bytes each, each after a byte saying how it is
  /// filtered: by what lies before it, above it or both, PNG's Sub, Up and
  /// Paeth — whichever leaves the smallest differences, which deflate best.
  static Uint8List _filtered(Uint8List rgb, int stride, int height) {
    final out = Uint8List((stride + 1) * height);
    final trial = <Uint8List>[for (var i = 0; i < 3; i++) Uint8List(stride)];
    for (var row = 0; row < height; row++) {
      final at = row * stride;
      final above = row - 1;
      var best = -1;
      var least = 1 << 62;
      for (var filter = 0; filter < 3; filter++) {
        final into = trial[filter];
        var cost = 0;
        for (var i = 0; i < stride; i++) {
          final x = rgb[at + i];
          final a = i >= 3 ? rgb[at + i - 3] : 0;
          final b = above >= 0 ? rgb[at - stride + i] : 0;
          final int predicted;
          if (filter == 0) {
            predicted = a;
          } else if (filter == 1) {
            predicted = b;
          } else {
            final c = i >= 3 && above >= 0 ? rgb[at - stride + i - 3] : 0;
            final p = a + b - c;
            final pa = (p - a).abs();
            final pb = (p - b).abs();
            final pc = (p - c).abs();
            predicted = pa <= pb && pa <= pc
                ? a
                : pb <= pc
                ? b
                : c;
          }
          final value = (x - predicted) & 0xFF;
          into[i] = value;
          cost += value < 128 ? value : 256 - value;
        }
        if (cost < least) {
          least = cost;
          best = filter;
        }
      }
      final to = row * (stride + 1);
      // Sub is PNG's filter 1, Up 2 and Paeth 4.
      out[to] = const <int>[1, 2, 4][best];
      out.setRange(to + 1, to + 1 + stride, trial[best]);
    }
    return out;
  }

  static Uint8List _deflate(Uint8List bytes) =>
      Uint8List.fromList(ZLibEncoder().convert(bytes));
}

/// A picture placed on a PDF page: [x] and [y] its top-left corner from
/// the page's, [width] and [height] its size, in points.
typedef PdfPlacement = ({
  PdfImage image,
  double x,
  double y,
  double width,
  double height,
});

/// An entry of a PDF's table of contents, the bookmarks a reader shows
/// beside it: [title], opening the page [page] — counted from 0 — with
/// [children] beneath it.
final class PdfOutline {
  const PdfOutline(
    this.title, {
    required this.page,
    this.children = const <PdfOutline>[],
  });

  final String title;
  final int page;
  final List<PdfOutline> children;
}

/// Writes a PDF to [_out] as its pages are added, so that a long one is
/// never held whole: each page's pictures written as it comes, and what
/// ties them together — the list of pages, the table of contents — when
/// it is [finish]ed.
final class PdfWriter {
  PdfWriter(this._out) {
    // The catalog, page tree and information come first, written last.
    _offsets.addAll(<int?>[null, null, null]);
    // The header, and bytes past ASCII to say that it holds binary data.
    _write(latin1.encode('%PDF-1.7\n'));
    _write(const <int>[0x25, 0xE2, 0xE3, 0xCF, 0xD3, 0x0A]);
  }

  final void Function(List<int> bytes) _out;

  /// How many bytes have been written.
  int _written = 0;

  /// Where each object begins, by its number less one.
  final List<int?> _offsets = <int?>[];

  /// The objects of the pages added, in order.
  final List<int> _pages = <int>[];

  static const int _catalog = 1;
  static const int _pageTree = 2;
  static const int _info = 3;

  bool _finished = false;

  int get pageCount => _pages.length;

  /// A page [width] by [height] points, with [pictures] on it, the first
  /// beneath the rest.
  void addPage({
    required double width,
    required double height,
    List<PdfPlacement> pictures = const <PdfPlacement>[],
  }) {
    if (_finished) throw StateError('The PDF is finished');
    final names = <String, int>{};
    final drawn = StringBuffer();
    for (final (index, placed) in pictures.indexed) {
      final image = placed.image;
      final number = _object(
        '<< /Type /XObject /Subtype /Image /Width ${image.width} '
        '/Height ${image.height} /ColorSpace /DeviceRGB /BitsPerComponent 8 '
        '/Filter /FlateDecode /DecodeParms << /Predictor 15 /Colors 3 '
        '/BitsPerComponent 8 /Columns ${image.width} >> '
        '/Length ${image.data.length} >>',
        stream: image.data,
      );
      final name = 'Im$index';
      names[name] = number;
      // PDF's y runs up from the page's foot.
      drawn.write(
        'q ${_n(placed.width)} 0 0 ${_n(placed.height)} ${_n(placed.x)} '
        '${_n(height - placed.y - placed.height)} cm /$name Do Q\n',
      );
    }
    final content = latin1.encode('$drawn');
    final contents = _object(
      '<< /Length ${content.length} >>',
      stream: content,
    );
    final images = <String>[
      for (final MapEntry(key: name, value: number) in names.entries)
        '/$name $number 0 R',
    ].join(' ');
    _pages.add(
      _object(
        '<< /Type /Page /Parent $_pageTree 0 R '
        '/MediaBox [0 0 ${_n(width)} ${_n(height)}] '
        '/Resources << /XObject << $images >> >> '
        '/Contents $contents 0 R >>',
      ),
    );
  }

  /// Ties the pages together, with [outline] as the table of contents and
  /// [title] as the document's, and ends the file.
  void finish({
    String? title,
    List<PdfOutline> outline = const <PdfOutline>[],
    DateTime? made,
  }) {
    if (_finished) throw StateError('The PDF is finished');
    _finished = true;
    _object(
      '<< /Type /Pages /Kids [${_pages.map((page) => '$page 0 R').join(' ')}] '
      '/Count ${_pages.length} >>',
      number: _pageTree,
    );
    final outlines = outline.isEmpty || _pages.isEmpty
        ? null
        : _outline(outline);
    _object(
      '<< /Type /Catalog /Pages $_pageTree 0 R'
      '${outlines == null ? '' : ' /Outlines $outlines 0 R /PageMode /UseOutlines'}'
      ' >>',
      number: _catalog,
    );
    _object(
      '<< /Producer ${_text('aantekening')} '
      '/CreationDate ${_date(made ?? DateTime.now())}'
      '${title == null ? '' : ' /Title ${_text(title)}'} >>',
      number: _info,
    );

    final table = _written;
    final xref = StringBuffer('xref\n0 ${_offsets.length + 1}\n')
      ..write('0000000000 65535 f \n');
    for (final offset in _offsets) {
      xref.write(
        offset == null
            ? '0000000000 65535 f \n'
            : '${'$offset'.padLeft(10, '0')} 00000 n \n',
      );
    }
    xref.write(
      'trailer\n<< /Size ${_offsets.length + 1} /Root $_catalog 0 R '
      '/Info $_info 0 R >>\nstartxref\n$table\n%%EOF\n',
    );
    _write(latin1.encode('$xref'));
  }

  /// The outline [entries] written, the object of the outline's root
  /// returned.
  int _outline(List<PdfOutline> entries) {
    final root = _reserve();
    final (first, last, count) = _entries(entries, root);
    _object(
      '<< /Type /Outlines /First $first 0 R /Last $last 0 R /Count $count >>',
      number: root,
    );
    return root;
  }

  /// [entries] written beneath [parent]: the first and last of them, and
  /// how many there are, those beneath them shown.
  (int, int, int) _entries(List<PdfOutline> entries, int parent) {
    final numbers = <int>[for (final _ in entries) _reserve()];
    var shown = entries.length;
    for (final (index, entry) in entries.indexed) {
      final number = numbers[index];
      final page = _pages[entry.page.clamp(0, _pages.length - 1)];
      var children = '';
      if (entry.children.isNotEmpty) {
        final (first, last, count) = _entries(entry.children, number);
        children = ' /First $first 0 R /Last $last 0 R /Count $count';
        shown += count;
      }
      _object(
        '<< /Title ${_text(entry.title)} /Parent $parent 0 R'
        '${index > 0 ? ' /Prev ${numbers[index - 1]} 0 R' : ''}'
        '${index < entries.length - 1 ? ' /Next ${numbers[index + 1]} 0 R' : ''}'
        '$children /Dest [$page 0 R /XYZ null null null] >>',
        number: number,
      );
    }
    return (numbers.first, numbers.last, shown);
  }

  /// A number for an object written later.
  int _reserve() {
    _offsets.add(null);
    return _offsets.length;
  }

  /// Writes the object [dictionary], followed by [stream] if given, as
  /// object [number] — a new one if not given — and returns its number.
  int _object(String dictionary, {Uint8List? stream, int? number}) {
    final at = number ?? _reserve();
    _offsets[at - 1] = _written;
    _write(latin1.encode('$at 0 obj\n$dictionary\n'));
    if (stream != null) {
      _write(latin1.encode('stream\n'));
      _write(stream);
      _write(latin1.encode('\nendstream\n'));
    }
    _write(latin1.encode('endobj\n'));
    return at;
  }

  void _write(List<int> bytes) {
    _out(bytes);
    _written += bytes.length;
  }

  /// [value] as PDF writes a number: to a thousandth, without needless
  /// zeros.
  static String _n(double value) {
    final fixed = value.toStringAsFixed(3);
    final trimmed = fixed.replaceFirst(RegExp(r'\.?0+$'), '');
    return trimmed == '-0' || trimmed.isEmpty ? '0' : trimmed;
  }

  /// [text] as a PDF text string: UTF-16, big end first, in hexadecimal.
  static String _text(String text) {
    final hex = StringBuffer('<FEFF');
    for (final unit in text.codeUnits) {
      hex.write(unit.toRadixString(16).padLeft(4, '0').toUpperCase());
    }
    return '$hex>';
  }

  /// [time] as a PDF date, in UTC.
  static String _date(DateTime time) {
    final utc = time.toUtc();
    String two(int value) => '$value'.padLeft(2, '0');
    return '(D:${utc.year}${two(utc.month)}${two(utc.day)}'
        '${two(utc.hour)}${two(utc.minute)}${two(utc.second)}Z)';
  }
}
