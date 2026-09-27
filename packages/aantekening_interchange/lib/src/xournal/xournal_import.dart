/// Bringing over Xournal++ documents: each a page here, its pages one
/// beneath the other, with its handwriting, text, pictures, formulas and
/// the PDFs it annotates.
library;

import 'dart:convert';
import 'dart:io';
import 'dart:math' as math;
import 'dart:typed_data';

import 'package:aantekening_core/aantekening_core.dart';
import 'package:path/path.dart' as p;
import 'package:xml/xml.dart';

import '../importer.dart';

/// Page units per point, Xournal++'s unit.
const double _perPoint = 96 / 72;

/// The space left between one Xournal++ page and the next, in page units.
const double _pageGap = 24;

/// Reads Xournal++ documents (.xopp) and Xournal ones (.xoj): each file a
/// page, a folder of them a notebook whose folders are its sections.
final class XournalImporter implements NotesImporter {
  const XournalImporter({this.folders = false});

  /// Whether a folder of documents is read, rather than documents chosen.
  final bool folders;

  @override
  String get name => folders ? 'Xournal++ folder' : 'Xournal++';

  @override
  String get description => folders
      ? 'A folder of Xournal++ documents, as a notebook: each folder in it a '
            'section, each document a page.'
      : 'Xournal++ documents (.xopp, .xoj), each as a page: its pages one '
            'beneath the other, with the PDFs they annotate.';

  @override
  List<String> get extensions => const <String>['xopp', 'xoj'];

  @override
  ImportSource get source => folders ? ImportSource.folder : ImportSource.files;

  @override
  ImportTarget get target =>
      folders ? ImportTarget.newNotebook : ImportTarget.section;

  @override
  NotesDraft read(List<String> paths, ImportWork work) {
    final reader = _Reader(work);
    if (!folders) {
      return NotesDraft(
        pages: <PageDraft>[
          for (final path in <String>[...paths]..sort())
            ?reader.document(File(path)),
        ],
        assets: reader.assets,
        warnings: reader.warnings,
      );
    }
    return NotesDraft(
      notebooks: <NotebookDraft>[
        for (final path in paths)
          NotebookDraft(
            title: p.basename(path),
            sections: reader.sections(Directory(path)),
          ),
      ],
      assets: reader.assets,
      warnings: reader.warnings,
    );
  }
}

final class _Reader {
  _Reader(this._work);

  final ImportWork _work;
  final Map<String, AssetDraft> assets = <String, AssetDraft>{};
  final List<String> warnings = <String>[];

  /// PDFs kept, by path, so a background used by every page is kept once.
  final Map<String, String> _pdfs = <String, String>{};

  /// The sections a folder of documents makes: documents directly in it
  /// in a section of its name, and a section for each folder in it.
  List<SectionDraft> sections(Directory folder) {
    final entries = folder.listSync()..sort((a, b) => a.path.compareTo(b.path));
    final pages = <PageDraft>[
      for (final entry in entries)
        if (entry is File && _isDocument(entry.path)) ?document(entry),
    ];
    return <SectionDraft>[
      if (pages.isNotEmpty)
        SectionDraft(title: p.basename(folder.path), pages: pages),
      for (final entry in entries)
        if (entry is Directory && !p.basename(entry.path).startsWith('.'))
          ..._subsection(entry),
    ];
  }

  List<SectionDraft> _subsection(Directory folder) {
    final inside = sections(folder);
    if (inside.isEmpty) return const <SectionDraft>[];
    // A folder of documents alone is a section of its own.
    if (inside.length == 1 && inside.single.title == p.basename(folder.path)) {
      return inside;
    }
    return <SectionDraft>[
      SectionDraft(title: p.basename(folder.path), sections: inside),
    ];
  }

  static bool _isDocument(String path) {
    final extension = p.extension(path).toLowerCase();
    return extension == '.xopp' || extension == '.xoj';
  }

  /// The page document [file] becomes, or null if it cannot be read.
  PageDraft? document(File file) {
    _work.progress('Reading ${p.basename(file.path)}');
    final XmlDocument xml;
    try {
      final bytes = file.readAsBytesSync();
      final text = bytes.length > 2 && bytes[0] == 0x1F && bytes[1] == 0x8B
          ? utf8.decode(gzip.decode(bytes), allowMalformed: true)
          : utf8.decode(bytes, allowMalformed: true);
      xml = XmlDocument.parse(text);
    } on Object catch (error) {
      warnings.add('${p.basename(file.path)} could not be read: $error');
      return null;
    }
    final modified = file.lastModifiedSync().millisecondsSinceEpoch;
    final elements = <NoteElement>[];
    var top = 0.0;
    PageBackground? background;
    String? previousPdf;
    for (final page in xml.findAllElements('page')) {
      final width = _number(page, 'width', 595) * _perPoint;
      final height = _number(page, 'height', 842) * _perPoint;
      final paper = page.getElement('background');
      if (paper != null) {
        final (backdrop, pdf) = _background(
          paper,
          file,
          top: top,
          width: width,
          height: height,
          previousPdf: previousPdf,
          now: modified,
        );
        previousPdf = pdf ?? previousPdf;
        if (backdrop != null) elements.add(backdrop);
        background ??= _paper(paper);
      }
      for (final layer in page.findElements('layer')) {
        for (final item in layer.childElements) {
          final element = switch (item.name.local) {
            'stroke' => _stroke(item, top, modified),
            'text' => _text(item, top, modified),
            'image' => _image(item, top, modified),
            'teximage' => _formula(item, top, modified),
            _ => null,
          };
          if (element != null) elements.add(element);
        }
      }
      top += height + _pageGap;
    }
    var z = 0;
    return PageDraft(
      title: _title(file),
      createdAt: modified,
      document: PageDocument(
        id: Ulid.generate(),
        canvas: CanvasSettings(
          background: background ?? PageBackground.defaults,
        ),
        elements: <NoteElement>[
          for (final element in elements) element.withZ(z++),
        ],
      ),
    );
  }

  /// A document's name, without the date the OneNote converter puts
  /// before it: "2025-10-24 15-15 - Beispiele".
  static String _title(File file) {
    final name = p.basenameWithoutExtension(file.path);
    final dated = RegExp(
      r'^\d{4}-\d{2}-\d{2} \d{2}-\d{2} - (.+)$',
    ).firstMatch(name);
    return dated?.group(1) ?? name;
  }

  static double _number(XmlElement element, String name, double fallback) =>
      double.tryParse(element.getAttribute(name) ?? '') ?? fallback;

  /// The ruling of a page's paper, as the page's background here.
  static PageBackground? _paper(XmlElement background) {
    if (background.getAttribute('type') != 'solid') return null;
    final kind = switch (background.getAttribute('style')) {
      'graph' || 'isograph' => PageBackgroundKind.grid,
      'lined' || 'ruled' || 'staves' => PageBackgroundKind.ruled,
      'dotted' || 'isodotted' => PageBackgroundKind.dotted,
      _ => PageBackgroundKind.blank,
    };
    final paper = _color(background.getAttribute('color')) ?? 0xFFFFFFFF;
    return PageBackground(
      kind: kind,
      paperColor: paper,
      lineColor: _isDark(paper) ? 0x33FFFFFF : 0x1F000000,
    );
  }

  static bool _isDark(int color) {
    final r = (color >> 16) & 0xFF;
    final g = (color >> 8) & 0xFF;
    final b = color & 0xFF;
    return (r * 299 + g * 587 + b * 114) / 1000 < 128;
  }

  /// A page's PDF or picture background, set as the background of that
  /// part of the page, and the PDF it came from.
  (NoteElement?, String?) _background(
    XmlElement background,
    File document, {
    required double top,
    required double width,
    required double height,
    required String? previousPdf,
    required int now,
  }) {
    final frame = Frame(x: 0, y: top, width: width, height: height);
    switch (background.getAttribute('type')) {
      case 'pdf':
        final domain = background.getAttribute('domain');
        final name = background.getAttribute('filename');
        final source = domain == 'clone' || name == null
            ? previousPdf
            : _findBeside(document, name, domain);
        if (source == null) {
          warnings.add(
            '${p.basename(document.path)}: its PDF, ${name ?? '(unnamed)'}, '
            'could not be found.',
          );
          return (null, null);
        }
        final key = _pdfs[source] ??= _keepFile(source);
        final pageNumber = int.tryParse(
          background.getAttribute('pageno') ?? '',
        );
        return (
          PdfElement(
            id: Ulid.generate(),
            frame: frame,
            createdAt: now,
            updatedAt: now,
            assetId: key,
            pageIndex: math.max(0, (pageNumber ?? 1) - 1),
            locked: true,
          ),
          source,
        );
      case 'pixmap' || 'image':
        final name = background.getAttribute('filename');
        final source = name == null
            ? null
            : _findBeside(document, name, background.getAttribute('domain'));
        if (source == null) return (null, null);
        return (
          ImageElement(
            id: Ulid.generate(),
            frame: frame,
            createdAt: now,
            updatedAt: now,
            assetId: _keepFile(source),
            fit: MediaFit.stretch,
            locked: true,
          ),
          null,
        );
      default:
        return (null, null);
    }
  }

  /// Where a file a document refers to is: its path as written, or, for
  /// one attached, beside the document.
  static String? _findBeside(File document, String name, String? domain) {
    final candidates = <String>[
      if (domain == 'attach') '${document.path}.$name',
      name,
      p.join(p.dirname(document.path), name),
      p.join(p.dirname(document.path), p.basename(name)),
    ];
    for (final candidate in candidates) {
      if (File(candidate).existsSync()) return candidate;
    }
    return null;
  }

  String _keepFile(String path) {
    final bytes = File(path).readAsBytesSync();
    final (key, asset) = _work.keep(bytes, name: p.basename(path));
    assets[key] = asset;
    return key;
  }

  String _keepBytes(Uint8List bytes, String? name) {
    final (key, asset) = _work.keep(bytes, name: name);
    assets[key] = asset;
    return key;
  }

  InkElement? _stroke(XmlElement stroke, double top, int now) {
    final numbers = stroke.innerText
        .trim()
        .split(RegExp(r'\s+'))
        .map(double.tryParse)
        .whereType<double>()
        .toList();
    if (numbers.length < 2) return null;
    final widths = (stroke.getAttribute('width') ?? '1')
        .trim()
        .split(RegExp(r'\s+'))
        .map(double.tryParse)
        .whereType<double>()
        .toList();
    final width = widths.isEmpty ? 1.0 : widths.first;
    final count = numbers.length ~/ 2;
    // Widths after the first, one to each point, say how hard it pressed:
    // shown here as a pressure between a light and a firm touch.
    final pressures = widths.length > 1
        ? <double>[
            for (var i = 0; i < count; i++)
              ((widths[math.min(i + 1, widths.length - 1)] / width) - 0.4)
                  .clamp(0.0, 1.0),
          ]
        : null;
    final tool = switch (stroke.getAttribute('tool')) {
      'highlighter' => InkTool.highlighter,
      _ => InkTool.pen,
    };
    var color = _color(stroke.getAttribute('color')) ?? 0xFF000000;
    if (stroke.getAttribute('tool') == 'eraser') color = 0xFFFFFFFF;
    return InkElement(
      id: Ulid.generate(),
      frame: const Frame(x: 0, y: 0, width: 0, height: 0),
      createdAt: now,
      updatedAt: now,
    ).withStrokes(<InkStroke>[
      InkStroke.fromPoints(
        tool: tool,
        color: color,
        width: width * _perPoint,
        xs: <double>[
          for (var i = 0; i < count; i++) numbers[i * 2] * _perPoint,
        ],
        ys: <double>[
          for (var i = 0; i < count; i++) top + numbers[i * 2 + 1] * _perPoint,
        ],
        pressures: pressures,
      ),
    ]);
  }

  TextElement? _text(XmlElement text, double top, int now) {
    final content = text.innerText;
    if (content.trim().isEmpty) return null;
    final size = _number(text, 'size', 12);
    final marks = TextMarks(
      font: text.getAttribute('font'),
      size: size,
      color: _color(text.getAttribute('color')),
    );
    final lines = content.split('\n');
    final longest = lines.fold<int>(
      0,
      (most, line) => math.max(most, line.length),
    );
    return TextElement(
      id: Ulid.generate(),
      frame: Frame(
        x: _number(text, 'x', 0) * _perPoint - 6,
        y: top + _number(text, 'y', 0) * _perPoint,
        width: math.max(40, longest * size * 0.62 * _perPoint + 12),
        height: lines.length * size * 1.3 * _perPoint,
      ),
      createdAt: now,
      updatedAt: now,
      autoWidth: true,
      blocks: <TextBlock>[
        for (final line in lines)
          TextBlock(
            runs: <TextRun>[if (line.isNotEmpty) TextRun(line, marks)],
            spacing: BlockSpacing.tight,
          ),
      ],
    );
  }

  ImageElement? _image(XmlElement image, double top, int now) {
    final data = _base64(image.innerText);
    if (data == null) return null;
    return ImageElement(
      id: Ulid.generate(),
      frame: _box(image, top),
      createdAt: now,
      updatedAt: now,
      assetId: _keepBytes(data, null),
      fit: MediaFit.stretch,
    );
  }

  /// A formula: its LaTeX, as a formula in a text box, where that LaTeX can
  /// be set here; otherwise the picture of it Xournal++ keeps, as it was.
  NoteElement? _formula(XmlElement formula, double top, int now) {
    final latex = _latex(formula.getAttribute('text') ?? '');
    final frame = _box(formula, top);
    if (latex != null && latex.isNotEmpty) {
      final size = (frame.height / _perPoint / 1.35).clamp(8.0, 40.0);
      return TextElement(
        id: Ulid.generate(),
        frame: Frame(
          x: frame.x - 6,
          y: frame.y,
          width: frame.width + 12,
          height: frame.height,
        ),
        createdAt: now,
        updatedAt: now,
        autoWidth: true,
        blocks: <TextBlock>[
          TextBlock(
            runs: <TextRun>[
              TextRun.math(
                latex,
                MathMode.latex,
                TextMarks(size: (size * 2).round() / 2),
              ),
            ],
            spacing: BlockSpacing.tight,
          ),
        ],
      );
    }
    final data = _base64(formula.innerText);
    if (data == null) return null;
    final key = _keepBytes(data, null);
    return mimeTypeOf(data) == 'application/pdf'
        ? PdfElement(
            id: Ulid.generate(),
            frame: frame,
            createdAt: now,
            updatedAt: now,
            assetId: key,
            pageIndex: 0,
          )
        : ImageElement(
            id: Ulid.generate(),
            frame: frame,
            createdAt: now,
            updatedAt: now,
            assetId: key,
            fit: MediaFit.stretch,
          );
  }

  /// The LaTeX of a Xournal++ formula, as a formula here holds it, or null
  /// for one written with TeX's own layout commands, which only TeX sets.
  static String? _latex(String source) {
    var latex = source.trim();
    for (final (open, close) in const <(String, String)>[
      (r'\(', r'\)'),
      (r'\[', r'\]'),
      (r'$$', r'$$'),
      (r'$', r'$'),
    ]) {
      if (latex.startsWith(open) && latex.endsWith(close) && latex.length > 2) {
        latex = latex.substring(open.length, latex.length - close.length);
        break;
      }
    }
    latex = latex
        .replaceAll(r'\displaystyle', '')
        .replaceAll('&nbsp;', r'\ ')
        .trim();
    const primitives = <String>[
      r'\halign', r'\vcenter', r'\cr', r'\baselineskip', r'\lineskip', //
      r'\everycr', r'\tabskip', r'\mathsurround', r'\hfil',
    ];
    if (primitives.any(latex.contains)) return null;
    return latex;
  }

  static Frame _box(XmlElement element, double top) {
    final left = _number(element, 'left', 0) * _perPoint;
    final right = _number(element, 'right', 0) * _perPoint;
    final upper = _number(element, 'top', 0) * _perPoint;
    final lower = _number(element, 'bottom', 0) * _perPoint;
    return Frame(
      x: math.min(left, right),
      y: top + math.min(upper, lower),
      width: math.max(1, (right - left).abs()),
      height: math.max(1, (lower - upper).abs()),
    );
  }

  static Uint8List? _base64(String text) {
    try {
      final data = base64.decode(text.replaceAll(RegExp(r'\s'), ''));
      return data.isEmpty ? null : data;
    } on FormatException {
      return null;
    }
  }

  /// A colour as Xournal++ writes it: `#RRGGBBAA`, or one of the names
  /// Xournal gave its pens.
  static int? _color(String? value) {
    if (value == null) return null;
    final named = _named[value.toLowerCase()];
    if (named != null) return named;
    if (!value.startsWith('#')) return null;
    final hex = value.substring(1);
    final parsed = int.tryParse(hex, radix: 16);
    if (parsed == null) return null;
    return switch (hex.length) {
      8 => ((parsed & 0xFF) << 24) | (parsed >> 8),
      6 => 0xFF000000 | parsed,
      _ => null,
    };
  }

  static const Map<String, int> _named = <String, int>{
    'black': 0xFF000000, 'blue': 0xFF3333CC, 'red': 0xFFFF0000, //
    'green': 0xFF008000, 'gray': 0xFF808080, 'lightblue': 0xFF00C0FF,
    'lightgreen': 0xFF00FF00, 'magenta': 0xFFFF00FF, 'orange': 0xFFFF8000,
    'yellow': 0xFFFFFF00, 'white': 0xFFFFFFFF,
  };
}
