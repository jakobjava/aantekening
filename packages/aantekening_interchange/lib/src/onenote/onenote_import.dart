/// Bringing OneNote notebooks over: every page as it was, each outline a
/// text box where it was, with its formulas, tables, pictures, files and
/// handwriting.
library;

import 'dart:io';
import 'dart:math' as math;
import 'dart:typed_data';

import 'package:aantekening_core/aantekening_core.dart';
import 'package:path/path.dart' as p;

import '../cabinet/cabinet.dart';
import '../importer.dart';
import 'model.dart';
import 'notebook_reader.dart';
import 'office_math.dart';

/// Page units — 1/96 inch — in OneNote's half-inch and HIMETRIC.
const double _perHalfInch = 48;
const double _perHimetric = 96 / 2540;

/// OneNote's own text size, in points: text at it is left at the page's.
const double _bodySize = 11;

/// Reads OneNote notebooks exported as .onepkg, and single sections (.one).
final class OneNoteImporter implements NotesImporter {
  const OneNoteImporter();

  @override
  String get name => 'OneNote';

  @override
  String get description =>
      'A notebook exported from OneNote (.onepkg), or one of its '
      'sections (.one): every page, where everything was on it.';

  @override
  List<String> get extensions => const <String>['onepkg', 'one'];

  @override
  ImportSource get source => ImportSource.file;

  @override
  ImportTarget get target => ImportTarget.newNotebook;

  @override
  NotesDraft read(List<String> paths, ImportWork work) =>
      convertOneNote(<String, List<OneEntry>>{
        for (final path in paths)
          p.basenameWithoutExtension(
            path,
          ): p.extension(path).toLowerCase() == '.onepkg'
              ? _readPackage(path, work)
              : <OneEntry>[_readLoneSection(path, work)],
      }, work);

  static List<OneEntry> _readPackage(String path, ImportWork work) {
    final folder = Directory(p.join(work.directory.path, 'notebook'))
      ..createSync(recursive: true);
    final file = File(path).openSync();
    try {
      work.progress('Unpacking', 0);
      Cabinet.read(FileSource(file)).extractTo(
        folder,
        onProgress: (done, total) =>
            work.progress('Unpacking', total == 0 ? null : done / total),
      );
    } finally {
      file.closeSync();
    }
    // A package holds its notebook's folder, or the notebook itself.
    final contents = folder.listSync();
    final root =
        contents.length == 1 &&
            contents.single is Directory &&
            !contents.any((entry) => entry.path.endsWith('.onetoc2'))
        ? contents.single as Directory
        : folder;
    return readNotebookFolder(
      root,
      onSection: (name) => work.progress('Reading $name'),
    );
  }

  /// A section on its own, read as a notebook of one section would be.
  static OneEntry _readLoneSection(String path, ImportWork work) {
    final directory = Directory(p.join(work.directory.path, 'section'))
      ..createSync(recursive: true);
    File(path).copySync(p.join(directory.path, p.basename(path)));
    final entries = readNotebookFolder(directory);
    return entries.isEmpty
        ? OneUnreadableSection(p.basename(path), 'The file is empty')
        : entries.first;
  }
}

/// The notebooks [notebooks] — each's sections and groups by its name — as
/// drafts, their pictures and files kept in [work].
NotesDraft convertOneNote(
  Map<String, List<OneEntry>> notebooks,
  ImportWork work,
) {
  final converter = _Converter(work);
  return NotesDraft(
    notebooks: <NotebookDraft>[
      for (final entry in notebooks.entries)
        NotebookDraft(
          title: entry.key,
          sections: converter.sections(entry.value),
        ),
    ],
    assets: converter.assets,
    warnings: converter.warnings,
  );
}

/// Turns OneNote's model into drafts, keeping the pictures and files it
/// meets.
final class _Converter {
  _Converter(this._work);

  final ImportWork _work;
  final Map<String, AssetDraft> assets = <String, AssetDraft>{};
  final List<String> warnings = <String>[];

  /// The page being converted, for warnings.
  String _page = '';

  List<SectionDraft> sections(List<OneEntry> entries) => <SectionDraft>[
    for (final entry in entries)
      switch (entry) {
        OneSection() => _section(entry),
        OneSectionGroup() => SectionDraft(
          title: entry.name,
          sections: sections(entry.entries),
        ),
        OneUnreadableSection() => () {
          warnings.add('The section “${entry.name}”: ${entry.reason}');
          return SectionDraft(title: entry.name);
        }(),
      },
  ];

  SectionDraft _section(OneSection section) {
    // A page's level puts it beneath the page before it of a lower level.
    final top = <PageDraft>[];
    final open = <(int, List<PageDraft>)>[];
    for (final page in section.pages) {
      _work.progress('Converting ${section.name}: ${page.title}');
      final subpages = <PageDraft>[];
      final draft = PageDraft(
        title: page.title,
        createdAt: page.createdAt.millisecondsSinceEpoch,
        document: _document(page),
        subpages: subpages,
      );
      while (open.isNotEmpty && open.last.$1 >= page.level) {
        open.removeLast();
      }
      (open.isEmpty ? top : open.last.$2).add(draft);
      open.add((page.level, subpages));
    }
    return SectionDraft(title: section.name, pages: top, color: section.color);
  }

  PageDocument _document(OnePage page) {
    _page = page.title;
    final now = (page.modifiedAt ?? page.createdAt).millisecondsSinceEpoch;
    final pictures = <NoteElement>[];
    final text = <NoteElement>[];
    final ink = <NoteElement>[];
    for (final item in page.contents) {
      switch (item) {
        case OneOutline():
          final box = _outline(item, now, ink);
          if (box != null) text.add(box);
        case OneImage():
          final picture = _picture(item, now);
          if (picture != null) pictures.add(picture);
        case OneFile():
          final file = _fileBox(item, now);
          if (file != null) text.add(file);
        case OneInk():
          final element = _inkElement(item, 0, 0, now);
          if (element != null) ink.add(element);
      }
    }
    // Pictures beneath text beneath handwriting, as OneNote draws them.
    var z = 0;
    final elements = <NoteElement>[
      for (final element in <NoteElement>[...pictures, ...text, ...ink])
        element.withZ(z++),
    ];
    return PageDocument(
      id: Ulid.generate(),
      elements: elements,
    ).withContentOnPage().copyWith(revision: 0);
  }

  // ---------------------------------------------------------------- text

  /// The text box an outline becomes, or null for one with nothing in it.
  /// Drawings inside it go into [ink], placed where the outline is.
  TextElement? _outline(OneOutline outline, int now, List<NoteElement> ink) {
    final x = (outline.x ?? 0) * _perHalfInch;
    final y = (outline.y ?? 0) * _perHalfInch;
    final blocks = <TextBlock>[];
    for (final element in outline.elements) {
      _element(element, 0, blocks, (drawing) {
        final element = _inkElement(drawing, x, y, now);
        if (element != null) ink.add(element);
      });
    }
    if (!blocks.any((block) => block.isEmbed || block.plainText.isNotEmpty)) {
      return null;
    }
    return TextElement(
      id: Ulid.generate(),
      frame: TextElement.frameAround(
        Frame(
          x: x,
          y: y,
          width: (outline.maxWidth ?? 13) * _perHalfInch,
          height: math.max(24, (outline.maxHeight ?? 0.6) * _perHalfInch),
        ),
      ),
      createdAt: now,
      updatedAt: now,
      blocks: blocks,
    );
  }

  /// Adds the blocks of [element], [depth] levels in, and those of the
  /// elements beneath it, to [blocks].
  void _element(
    OneElement element,
    int depth,
    List<TextBlock> blocks,
    void Function(OneInk drawing) onInk, [
    TableCell? cell,
  ]) {
    var first = true;
    for (final content in element.contents) {
      switch (content) {
        case OneRichText():
          final list = first ? element.list : null;
          blocks.addAll(_paragraph(content, depth, list, cell));
        case OneTable():
          if (cell != null) {
            // A table in a table: its cells' text, in the cell.
            for (final row in content.rows) {
              for (final inner in row) {
                for (final nested in inner.elements) {
                  _element(nested, depth, blocks, onInk, cell);
                }
              }
            }
          } else {
            blocks.addAll(_table(content, depth, onInk));
          }
        case OneImage():
          final embed = _imageEmbed(content);
          if (embed != null) {
            blocks.add(
              TextBlock.embedded(
                embed,
                indent: depth,
                spacing: BlockSpacing.tight,
                cell: cell,
              ),
            );
          }
        case OneFile():
          final embed = _fileEmbed(content);
          if (embed != null) {
            blocks.add(
              TextBlock.embedded(
                embed,
                indent: depth,
                spacing: BlockSpacing.tight,
                cell: cell,
              ),
            );
          }
        case OneInk():
          onInk(content);
      }
      first = false;
    }
    for (final child in element.children) {
      _element(child, depth + 1, blocks, onInk, cell);
    }
  }

  List<TextBlock> _table(
    OneTable table,
    int depth,
    void Function(OneInk drawing) onInk,
  ) {
    final blocks = <TextBlock>[];
    final columns = table.rows.fold<int>(
      0,
      (most, row) => math.max(most, row.length),
    );
    for (var r = 0; r < table.rows.length; r++) {
      final row = table.rows[r];
      for (var c = 0; c < columns; c++) {
        final source = c < row.length ? row[c] : null;
        final cell = TableCell(
          r,
          c,
          width: c < table.columnWidths.length
              ? table.columnWidths[c] * _perHalfInch
              : null,
          shading: source?.background,
          borders: table.bordersVisible,
        );
        final lines = <TextBlock>[];
        for (final element in source?.elements ?? const <OneElement>[]) {
          _element(element, 0, lines, onInk, cell);
        }
        blocks.addAll(
          lines.isEmpty
              ? <TextBlock>[TextBlock(spacing: BlockSpacing.tight, cell: cell)]
              : lines,
        );
      }
    }
    return blocks;
  }

  /// The blocks a paragraph becomes: one for each of its lines, since a
  /// line break within a paragraph starts another block here.
  List<TextBlock> _paragraph(
    OneRichText text,
    int depth,
    OneList? list,
    TableCell? cell,
  ) {
    final kind = _kindOf(text, list);
    final lines = <List<TextRun>>[<TextRun>[]];
    final runs = text.runs.where((run) => !run.style.hidden).toList();
    var i = 0;
    while (i < runs.length) {
      final run = runs[i];
      if (run.style.math) {
        final formula = <OneRun>[];
        while (i < runs.length && runs[i].style.math) {
          formula.add(runs[i++]);
        }
        final marks = _marks(formula.first.style, null).forFormula;
        // Spaces at either end of a formula in a sentence are the sentence's.
        final source = formula.map((run) => run.text).join();
        final space = _marks(formula.first.style, null).withFont(null);
        if (source.startsWith(' ')) lines.last.add(TextRun(' ', space));
        var previousWasFormula = false;
        for (final piece in officeMathToLatex(formula)) {
          if (piece == null) {
            lines.add(<TextRun>[]);
            previousWasFormula = false;
            continue;
          }
          if (previousWasFormula) lines.last.add(TextRun(' ', marks));
          lines.last.add(TextRun.math(piece, MathMode.latex, marks));
          previousWasFormula = true;
        }
        if (source.endsWith(' ') && source.trim().isNotEmpty) {
          lines.last.add(TextRun(' ', space));
        }
        continue;
      }
      final pieces = run.text
          .replaceAll('\r\n', '\n')
          .split(RegExp('[\u000B\n\r]'));
      for (var j = 0; j < pieces.length; j++) {
        if (j > 0) lines.add(<TextRun>[]);
        final words = pieces[j].replaceAll('\t', '    ');
        if (words.isNotEmpty) {
          lines.last.add(TextRun(words, _marks(run.style, run.link)));
        }
      }
      i++;
    }

    final align = switch (text.alignment) {
      1 => BlockAlign.center,
      2 => BlockAlign.end,
      _ => BlockAlign.start,
    };
    final spacing = BlockSpacing(
      before: text.spaceBefore * 36,
      after: text.spaceAfter * 36,
      line: text.lineSpacing == null || text.lineSpacing == 0
          ? null
          : text.lineSpacing! * 36,
    );
    final checked = text.tags.any((tag) => tag.completed);
    final prefix = _tagPrefix(text.tags);
    return <TextBlock>[
      for (var l = 0; l < lines.length; l++)
        TextBlock(
          kind: l == 0 ? kind : TextBlockKind.paragraph,
          runs: RichTextEditing.normalizeRuns(<TextRun>[
            if (l == 0 && prefix != null) TextRun(prefix),
            ...lines[l],
          ]),
          indent: depth,
          checked: l == 0 && kind == TextBlockKind.todo && checked,
          marker: l == 0 && kind == TextBlockKind.bulleted
              ? _bullet(list!)
              : null,
          align: align,
          spacing: spacing,
          cell: cell,
        ),
    ];
  }

  static TextBlockKind _kindOf(OneRichText text, OneList? list) {
    if (text.tags.any((tag) => _isCheckBox(tag.shape))) {
      return TextBlockKind.todo;
    }
    if (list != null) {
      return _isNumbered(list.format)
          ? TextBlockKind.numbered
          : TextBlockKind.bulleted;
    }
    return switch (text.styleId) {
      'h1' => TextBlockKind.heading1,
      'h2' => TextBlockKind.heading2,
      'h3' || 'h4' || 'h5' || 'h6' => TextBlockKind.heading3,
      'code' => TextBlockKind.code,
      'blockquote' || 'cite' => TextBlockKind.quote,
      _ => TextBlockKind.paragraph,
    };
  }

  /// Whether a list's format holds a number — a character below U+0020
  /// stands where it goes — rather than being a bullet.
  static bool _isNumbered(String format) =>
      format.runes.any((rune) => rune < 0x20);

  static bool _isCheckBox(int shape) =>
      (shape >= 1 && shape <= 12) ||
      const <int>{28, 30, 32, 48, 50, 52, 69, 71, 73}.contains(shape) ||
      (shape >= 94 && shape <= 99);

  /// The mark a note tag other than a box to tick is shown by, before its
  /// paragraph.
  static String? _tagPrefix(List<OneNoteTag> tags) {
    final marks = <String>[
      for (final tag in tags)
        if (!_isCheckBox(tag.shape))
          switch (tag.shape) {
            13 || 34 || 40 || 54 || 61 || 75 => '★',
            14 || 89 || 90 || 91 || 92 || 93 => '⚑',
            15 || 111 => '?',
            16 || 59 || 80 => '→',
            17 || 115 => '!',
            21 => '💡',
            22 => '📌',
            24 => '💬',
            25 => '☺',
            27 => '🔑',
            35 || 55 || 76 => '✓',
            47 || 68 || 88 => '✗',
            112 => '📎',
            _ => tag.label.isEmpty ? '◆' : '[${tag.label}]',
          },
    ];
    return marks.isEmpty ? null : '${marks.join(' ')} ';
  }

  /// The mark a bulleted list is shown with, in Unicode: bullets set in
  /// symbol fonts are the characters those fonts draw at their codes.
  static String _bullet(OneList list) {
    final format = list.format.trim();
    if (format.isEmpty) return '•';
    final code = format.runes.first;
    final font = (list.font ?? '').toLowerCase();
    final symbol = switch (font) {
      'wingdings' => _wingdings[code & 0xFF],
      'symbol' => code & 0xFF == 0xB7 ? '•' : null,
      _ => null,
    };
    if (symbol != null) return symbol;
    if (font == 'courier new' && format == 'o') return '○';
    // Private-use codes of symbol fonts nobody else draws.
    if (code >= 0xF000 && code <= 0xF0FF) return '•';
    return format;
  }

  static const Map<int, String> _wingdings = <int, String>{
    0x6C: '●', 0x6E: '■', 0x6F: '□', 0x71: '❑', 0x75: '◆', 0x76: '❖', //
    0x77: '◆', 0xA7: '▪', 0xA8: '◻', 0x9F: '•', 0xD8: '➢', 0xE0: '➔',
    0xE8: '➔', 0xF0: '⇨', 0xFB: '✗', 0xFC: '✓', 0xFE: '☑', 0xA1: '○',
    0x4A: '☺', 0x46: '☞',
  };

  TextMarks _marks(OneStyle style, String? link) {
    final size = style.size;
    return TextMarks(
      bold: style.bold,
      italic: style.italic,
      underline: style.underline,
      strikethrough: style.strikethrough,
      color: style.color,
      highlight: style.highlight,
      link: link,
      size: size == null || size == _bodySize ? null : size,
      font: style.font,
      script: style.superscript
          ? TextScript.superscript
          : style.subscript
          ? TextScript.subscript
          : null,
    );
  }

  // ------------------------------------------------------ pictures, files

  String? _keep(Uint8List? bytes, String? name, String what) {
    if (bytes == null || bytes.isEmpty) {
      warnings.add('“$_page”: $what could not be read from the notebook.');
      return null;
    }
    final (key, asset) = _work.keep(bytes, name: name);
    assets[key] = asset;
    return key;
  }

  BlockEmbed? _imageEmbed(OneImage image) {
    final key = _keep(image.data, image.fileName, 'A picture');
    if (key == null) return null;
    return BlockEmbed(
      kind: EmbedKind.image,
      assetId: key,
      width: (image.width ?? 4) * _perHalfInch,
      height: (image.height ?? 3) * _perHalfInch,
      text: _imageText(image),
    );
  }

  static String? _imageText(OneImage image) {
    final text = <String>[
      ?image.altText,
      ?image.recognizedText,
    ].where((part) => part.trim().isNotEmpty).join('\n');
    return text.isEmpty ? null : text;
  }

  ImageElement? _picture(OneImage image, int now) {
    final key = _keep(image.data, image.fileName, 'A picture');
    if (key == null) return null;
    return ImageElement(
      id: Ulid.generate(),
      frame: Frame(
        x: (image.x ?? 0) * _perHalfInch,
        y: (image.y ?? 0) * _perHalfInch,
        width: (image.width ?? 4) * _perHalfInch,
        height: (image.height ?? 3) * _perHalfInch,
      ),
      createdAt: now,
      updatedAt: now,
      assetId: key,
      fit: MediaFit.stretch,
      locked: image.isBackground,
      altText: image.altText,
      recognizedText: image.recognizedText,
    );
  }

  BlockEmbed? _fileEmbed(OneFile file) {
    final key = _keep(file.data, file.name, 'The file “${file.name}”');
    if (key == null) return null;
    return BlockEmbed(
      kind: EmbedKind.file,
      assetId: key,
      width: (file.width ?? 3) * _perHalfInch,
      height: (file.height ?? 1) * _perHalfInch,
      name: file.name,
    );
  }

  TextElement? _fileBox(OneFile file, int now) {
    final embed = _fileEmbed(file);
    if (embed == null) return null;
    return TextElement(
      id: Ulid.generate(),
      frame: TextElement.frameAround(
        Frame(
          x: (file.x ?? 0) * _perHalfInch,
          y: (file.y ?? 0) * _perHalfInch,
          width: embed.width,
          height: embed.height,
        ),
      ),
      createdAt: now,
      updatedAt: now,
      blocks: <TextBlock>[TextBlock.embedded(embed)],
    );
  }

  // ------------------------------------------------------------ drawings

  /// The drawing [ink] as one element, its groups' strokes among its own,
  /// placed from ([originX], [originY]); null for one with no strokes.
  InkElement? _inkElement(OneInk ink, double originX, double originY, int now) {
    final strokes = <InkStroke>[];
    void collect(OneInk drawing, double x, double y) {
      final left = x + (drawing.x ?? 0) * _perHalfInch;
      final top = y + (drawing.y ?? 0) * _perHalfInch;
      for (final stroke in drawing.strokes) {
        strokes.add(_stroke(stroke, left, top));
      }
      for (final group in drawing.groups) {
        collect(group, left, top);
      }
    }

    collect(ink, originX, originY);
    if (strokes.isEmpty) return null;
    return InkElement(
      id: Ulid.generate(),
      frame: const Frame(x: 0, y: 0, width: 0, height: 0),
      createdAt: now,
      updatedAt: now,
    ).withStrokes(strokes);
  }

  static InkStroke _stroke(OneStroke stroke, double left, double top) {
    final alpha = 255 - stroke.transparency.clamp(0, 255);
    final color = (stroke.color ?? 0xFF000000) & 0x00FFFFFF;
    return InkStroke.fromPoints(
      tool: stroke.highlighter ? InkTool.highlighter : InkTool.pen,
      color: (alpha << 24) | color,
      width:
          math.max(
            stroke.highlighter ? math.max(stroke.width, stroke.height) : 0,
            stroke.width,
          ) *
          _perHimetric,
      xs: <double>[for (final x in stroke.xs) left + x * _perHimetric],
      ys: <double>[for (final y in stroke.ys) top + y * _perHimetric],
      pressures: stroke.pressures,
    );
  }
}
