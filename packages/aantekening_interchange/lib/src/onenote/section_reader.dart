/// Reading a OneNote section file into its pages ([MS-ONE] 2.2–2.3).
library;

import 'dart:typed_data';

import '../bytes.dart';
import '../importer.dart';
import '../onestore/revision_store.dart';
import 'model.dart';
import 'properties.dart';

/// Reads the pages of the section in [store], named [fallbackName] when
/// the section does not name itself.
OneSection readSection(RevisionStore store, String fallbackName) {
  final root = store.root;
  final metadata = root[root.metadataRoot]?.properties ?? PropertySet.empty;
  final section = root[root.contentRoot];
  if (section == null || section.jcid != Jcid.sectionNode) {
    throw FormatDamage('The section has no pages');
  }
  final pages = <OnePage>[];
  for (final seriesId in section.properties.refs(Prop.elementChildNodes)) {
    final series = root[seriesId];
    if (series == null || series.jcid != Jcid.pageSeriesNode) continue;
    for (final spaceId in series.properties.refs(
      Prop.childGraphSpaceElementNodes,
    )) {
      final space = store.spaces[spaceId];
      if (space == null) continue;
      final page = _PageReader(space).read();
      if (page != null) pages.add(page);
    }
  }
  return OneSection(
    metadata.text(Prop.sectionDisplayName) ?? fallbackName,
    pages,
    color: metadata.colorRef(Prop.sectionColor),
  );
}

/// Reads one page's object space.
final class _PageReader {
  _PageReader(this._space);

  final ObjectSpace _space;
  int _depth = 0;

  StoreObject? _object(ExGuid? id) => _space[id];

  OnePage? read() {
    final metadata = _object(_space.metadataRoot)?.properties;
    final manifest = _object(_space.contentRoot);
    if (metadata == null || manifest == null) return null;
    if (metadata.flag(Prop.isDeletedGraphSpaceContent)) return null;
    final page = _object(manifest.properties.ref(Prop.contentChildNodes));
    if (page == null || page.jcid != Jcid.pageNode) return null;
    final properties = page.properties;

    OneOutline? title;
    final titleNode = _object(properties.ref(Prop.structureElementChildNodes));
    if (titleNode != null && titleNode.jcid == Jcid.titleNode) {
      final outlines = <OneOutline>[
        for (final id in titleNode.properties.refs(Prop.elementChildNodes))
          ?_outline(id),
      ];
      if (outlines.isNotEmpty) {
        final first = outlines.first;
        title = OneOutline(
          elements: [for (final outline in outlines) ...outline.elements],
          indents: first.indents,
          x: titleNode.properties.float(Prop.offsetFromParentHoriz),
          y: titleNode.properties.float(Prop.offsetFromParentVert),
          maxWidth: first.maxWidth,
        );
      }
    }

    return OnePage(
      title: metadata.text(Prop.cachedTitleString) ?? _titleText(title) ?? '',
      level: metadata.integer(Prop.pageLevel) ?? 1,
      createdAt:
          metadata.fileTime(Prop.topologyCreationTimeStamp) ??
          DateTime.utc(1970),
      modifiedAt: properties.time32(Prop.lastModifiedTime),
      titleItem: title,
      contents: <OnePageItem>[
        for (final id in properties.refs(Prop.elementChildNodes))
          ?_pageItem(id),
      ],
    );
  }

  /// The title's words, without its date and time.
  static String? _titleText(OneOutline? title) {
    if (title == null) return null;
    final words = <String>[
      for (final element in title.elements)
        for (final content in element.contents)
          if (content is OneRichText &&
              !content.isTitleDate &&
              !content.isTitleTime)
            content.runs
                .where((run) => !run.style.hidden)
                .map((run) => run.text)
                .join(),
    ].join(' ').trim();
    return words.isEmpty ? null : words;
  }

  OnePageItem? _pageItem(ExGuid? id) {
    final object = _object(id);
    if (object == null) return null;
    return switch (object.jcid) {
      Jcid.outlineNode => _outline(id),
      Jcid.imageNode => _image(object),
      Jcid.embeddedFileNode => _file(object),
      Jcid.inkContainer => _ink(object),
      _ => null,
    };
  }

  OneOutline? _outline(ExGuid? id) {
    final object = _object(id);
    if (object == null || object.jcid != Jcid.outlineNode) return null;
    final properties = object.properties;
    return OneOutline(
      elements: _elements(properties.refs(Prop.elementChildNodes)),
      indents: _indents(properties.bytes(Prop.rgOutlineIndentDistance)),
      x: properties.float(Prop.offsetFromParentHoriz),
      y: properties.float(Prop.offsetFromParentVert),
      maxWidth: properties.float(Prop.layoutMaxWidth),
      maxHeight: properties.float(Prop.layoutMaxHeight),
      sizeSetByUser: properties.flag(Prop.isLayoutSizeSetByUser),
    );
  }

  static List<double> _indents(Uint8List? bytes) {
    if (bytes == null || bytes.length < 4) return const <double>[];
    final reader = ByteReader(bytes);
    final count = reader.u8();
    reader.skip(3);
    return <double>[
      for (var i = 0; i < count && reader.remaining >= 4; i++) reader.f32(),
    ];
  }

  /// The outline elements [ids] name, with groups opened out into theirs.
  List<OneElement> _elements(List<ExGuid?> ids) {
    if (++_depth > 64) throw FormatDamage('Outlines nest too deep');
    try {
      final elements = <OneElement>[];
      for (final id in ids) {
        final object = _object(id);
        if (object == null) continue;
        final properties = object.properties;
        if (object.jcid == Jcid.outlineGroup) {
          elements.addAll(_elements(properties.refs(Prop.elementChildNodes)));
        } else if (object.jcid == Jcid.outlineElementNode) {
          elements.add(
            OneElement(
              contents: <OneContent>[
                for (final content in properties.refs(Prop.contentChildNodes))
                  ?_content(content),
              ],
              list: _list(properties.ref(Prop.listNodes)),
              children: _elements(properties.refs(Prop.elementChildNodes)),
            ),
          );
        }
      }
      return elements;
    } finally {
      _depth--;
    }
  }

  OneContent? _content(ExGuid? id) {
    final object = _object(id);
    if (object == null) return null;
    return switch (object.jcid) {
      Jcid.richTextNode => _richText(object.properties),
      Jcid.tableNode => _table(object.properties),
      Jcid.imageNode => _image(object),
      Jcid.embeddedFileNode => _file(object),
      Jcid.inkContainer => _ink(object),
      _ => null,
    };
  }

  OneList? _list(ExGuid? id) {
    final object = _object(id);
    if (object == null || object.jcid != Jcid.numberListNode) return null;
    final properties = object.properties;
    final format = properties.bytes(Prop.numberListFormat);
    final size = properties.integer(Prop.fontSize);
    return OneList(
      // The format's first character is its length.
      format: format == null || format.length < 2
          ? ''
          : String.fromCharCodes(<int>[
              for (var i = 2; i + 1 < format.length; i += 2)
                format[i] | (format[i + 1] << 8),
            ]),
      font: properties.text(Prop.listFont) ?? properties.text(Prop.font),
      restart: properties.integer(Prop.listRestart),
      bold: properties.flag(Prop.bold),
      italic: properties.flag(Prop.italic),
      fontSize: size == null ? null : size / 2,
      color: properties.colorRef(Prop.fontColor),
    );
  }

  OneStyle _style(PropertySet properties, [OneStyle? base]) {
    final size = properties.integer(Prop.fontSize);
    bool flag(int id, bool inherited) =>
        properties[id] == null ? inherited : properties.flag(id);
    return OneStyle(
      font: properties.text(Prop.font) ?? base?.font,
      size: size == null ? base?.size : size / 2,
      color: properties.colorRef(Prop.fontColor) ?? base?.color,
      highlight: properties.colorRef(Prop.highlight) ?? base?.highlight,
      bold: flag(Prop.bold, base?.bold ?? false),
      italic: flag(Prop.italic, base?.italic ?? false),
      underline: flag(Prop.underline, base?.underline ?? false),
      strikethrough: flag(Prop.strikethrough, base?.strikethrough ?? false),
      superscript: flag(Prop.superscript, base?.superscript ?? false),
      subscript: flag(Prop.subscript, base?.subscript ?? false),
      math: properties.flag(Prop.mathFormatting),
      hidden: properties.flag(Prop.hidden),
      hyperlink: properties.flag(Prop.hyperlink),
    );
  }

  OneRichText _richText(PropertySet properties) {
    final paragraphStyle = _object(properties.ref(Prop.paragraphStyle));
    final paragraph = paragraphStyle == null
        ? const OneStyle()
        : _style(paragraphStyle.properties);
    final styleId = paragraphStyle?.properties.text(Prop.paragraphStyleId);

    var text =
        properties.text(Prop.richEditTextUnicode) ??
        _windowsText(properties.bytes(Prop.textExtendedAscii));
    final formats = properties.refs(Prop.textRunFormatting);
    final data = properties.sets(Prop.textRunData);
    final indicesBytes = properties.bytes(Prop.textRunIndex);
    var ends = <int>[
      if (indicesBytes != null)
        for (var i = 0; i + 3 < indicesBytes.length; i += 4)
          ByteData.sublistView(indicesBytes).getUint32(i, Endian.little),
    ];
    // A paragraph that starts with a vertical tab can have its run ends
    // counted from after it.
    if (text.startsWith('\u000B') && ends.isNotEmpty && ends.first == 1) {
      text = text.substring(1);
      ends = <int>[for (final end in ends.skip(1)) end - 1];
    }

    final runs = <OneRun>[];
    if (formats.isEmpty) {
      runs.add(OneRun(text, paragraph));
    } else {
      var start = 0;
      for (var i = 0; i < formats.length; i++) {
        final end = (i < ends.length ? ends[i] : text.length).clamp(
          start,
          text.length,
        );
        final format = _object(formats[i]);
        final style = format == null
            ? paragraph
            : _style(format.properties, paragraph);
        runs.add(
          OneRun(
            text.substring(start, end),
            style,
            math: style.math && i < data.length ? _mathObject(data[i]) : null,
            link: format?.properties.text(Prop.wzHyperlinkUrl),
          ),
        );
        start = end;
      }
      if (start < text.length) {
        runs.add(OneRun(text.substring(start), runs.last.style));
      }
    }

    return OneRichText(
      runs: _withLinks(runs),
      alignment:
          properties.integer(Prop.paragraphAlignment) ??
          paragraphStyle?.properties.integer(Prop.paragraphAlignment) ??
          0,
      styleId: styleId,
      spaceBefore: properties.float(Prop.paragraphSpaceBefore) ?? 0,
      spaceAfter: properties.float(Prop.paragraphSpaceAfter) ?? 0,
      lineSpacing: properties.float(Prop.paragraphLineSpacingExact),
      tags: _noteTags(properties),
      isTitleDate: properties.flag(Prop.isTitleDate),
      isTitleTime: properties.flag(Prop.isTitleTime),
    );
  }

  static String _windowsText(Uint8List? bytes) {
    if (bytes == null) return '';
    final codes = <int>[
      for (final byte in bytes)
        if (byte != 0) windows1252(byte),
    ];
    return String.fromCharCodes(codes);
  }

  static const String _linkMarker = '﷟HYPERLINK "';

  /// [runs] with each link's target taken from the hidden field before its
  /// text — `﷟HYPERLINK "target"` — onto the visible runs it covers.
  static List<OneRun> _withLinks(List<OneRun> runs) {
    final linked = <OneRun>[];
    String? target;
    for (final run in runs) {
      if (run.style.hidden) {
        final at = run.text.indexOf(_linkMarker);
        if (at >= 0) {
          final start = at + _linkMarker.length;
          final end = run.text.indexOf('"', start);
          target = end < 0 ? null : run.text.substring(start, end);
        }
        linked.add(run);
        continue;
      }
      final link = run.link ?? (run.style.hyperlink ? target : null);
      if (!run.style.hyperlink) target = null;
      linked.add(
        link == run.link ? run : OneRun(run.text, run.style, link: link),
      );
    }
    return linked;
  }

  static OneMathObject? _mathObject(PropertySet properties) {
    final type = properties.integer(Prop.mathInlineObjectType);
    if (type == null) return null;
    return OneMathObject(
      type: type,
      arguments: properties.integer(Prop.mathInlineObjectCount) ?? 0,
      columns: properties.integer(Prop.mathInlineObjectColumns),
      align: properties.integer(Prop.mathInlineObjectAlign),
      char: properties.integer(Prop.mathInlineObjectChar),
      char1: properties.integer(Prop.mathInlineObjectChar1),
      char2: properties.integer(Prop.mathInlineObjectChar2),
    );
  }

  List<OneNoteTag> _noteTags(PropertySet properties) => <OneNoteTag>[
    for (final tag in properties.sets(Prop.noteTags))
      if (_object(tag.ref(Prop.noteTagDefinitionOid)) case final definition?)
        OneNoteTag(
          label: definition.properties.text(Prop.noteTagLabel) ?? '',
          shape: definition.properties.integer(Prop.noteTagShape) ?? 0,
          completed:
              tag[Prop.noteTagCompleted] != null ||
              ((tag.integer(Prop.actionItemStatus) ?? 0) & 1) != 0,
        ),
  ];

  OneTable _table(PropertySet properties) {
    final widths = properties.bytes(Prop.tableColumnWidths);
    return OneTable(
      rows: <List<OneCell>>[
        for (final rowId in properties.refs(Prop.elementChildNodes))
          if (_object(rowId) case final row?)
            <OneCell>[
              for (final cellId in row.properties.refs(Prop.elementChildNodes))
                if (_object(cellId) case final cell?)
                  OneCell(
                    _elements(cell.properties.refs(Prop.elementChildNodes)),
                    background: _cellColor(
                      cell.properties.integer(Prop.cellBackgroundColor),
                    ),
                  ),
            ],
      ],
      // The first byte is the count; four-byte floats follow.
      columnWidths: <double>[
        if (widths != null)
          for (var i = 1; i + 3 < widths.length; i += 4)
            ByteData.sublistView(widths).getFloat32(i, Endian.little),
      ],
      bordersVisible:
          properties[Prop.tableBordersVisible] == null ||
          properties.flag(Prop.tableBordersVisible),
    );
  }

  /// A cell's shading: RGB with a transparency byte, 255 for none.
  static int? _cellColor(int? value) {
    if (value == null) return null;
    final alpha = 255 - ((value >> 24) & 0xFF);
    if (alpha == 0) return null;
    return (alpha << 24) |
        ((value & 0xFF) << 16) |
        (value & 0xFF00) |
        ((value >> 16) & 0xFF);
  }

  OneImage _image(StoreObject object) {
    final properties = object.properties;
    final container = _object(properties.ref(Prop.pictureContainer));
    return OneImage(
      data: container?.fileData,
      extension: null,
      x: properties.float(Prop.offsetFromParentHoriz),
      y: properties.float(Prop.offsetFromParentVert),
      width:
          properties.float(Prop.layoutMaxWidth) ??
          properties.float(Prop.pictureWidth),
      height:
          properties.float(Prop.layoutMaxHeight) ??
          properties.float(Prop.pictureHeight),
      altText: properties.text(Prop.imageAltText),
      fileName: properties.text(Prop.imageFilename),
      link: properties.text(Prop.wzHyperlinkUrl),
      isBackground: properties.flag(Prop.isBackground),
      recognizedText: properties.text(Prop.richEditTextUnicode),
      printout: _printout(properties),
    );
  }

  /// The page of a PDF a picture shows, where it is a file printout's.
  OnePrintout? _printout(PropertySet properties) {
    final pdf = _object(properties.ref(Prop.printoutFile))?.fileData;
    final page = properties.integer(Prop.printoutPage);
    if (pdf == null || page == null || page < 1) return null;
    if (mimeTypeOf(pdf) != 'application/pdf') return null;
    return OnePrintout(pdf, page - 1);
  }

  OneFile _file(StoreObject object) {
    final properties = object.properties;
    final container = _object(properties.ref(Prop.embeddedFileContainer));
    return OneFile(
      name: properties.text(Prop.embeddedFileName) ?? 'Attachment',
      data: container?.fileData,
      x: properties.float(Prop.offsetFromParentHoriz),
      y: properties.float(Prop.offsetFromParentVert),
      width: properties.float(Prop.layoutMaxWidth),
      height: properties.float(Prop.layoutMaxHeight),
    );
  }

  OneInk _ink(StoreObject container, [double scaleX = 1, double scaleY = 1]) {
    if (++_depth > 64) throw FormatDamage('Drawings nest too deep');
    try {
      final properties = container.properties;
      final sx = properties.float(Prop.inkScalingX) ?? scaleX;
      final sy = properties.float(Prop.inkScalingY) ?? scaleY;
      final strokes = <OneStroke>[];
      final data = _object(properties.ref(Prop.inkData));
      if (data != null) {
        for (final strokeId in data.properties.refs(Prop.inkStrokes)) {
          final stroke = _stroke(_object(strokeId), sx, sy);
          if (stroke != null) strokes.add(stroke);
        }
      }
      return OneInk(
        strokes: strokes,
        groups: <OneInk>[
          for (final child in properties.refs(Prop.contentChildNodes))
            if (_object(child) case final nested?
                when nested.jcid == Jcid.inkContainer)
              _ink(nested, sx, sy),
        ],
        x: properties.float(Prop.offsetFromParentHoriz),
        y: properties.float(Prop.offsetFromParentVert),
      );
    } finally {
      _depth--;
    }
  }

  static final Guid _xDimension = Guid.parse(
    '598A6A8F-52C0-4BA0-93AF-AF357411A561',
  );
  static final Guid _yDimension = Guid.parse(
    'B53F9F75-04E0-4498-A7EE-C30DBB5A9011',
  );
  static final Guid _pressureDimension = Guid.parse(
    '7307502D-F9F4-4E18-B3F2-2CE1B1A3610C',
  );

  OneStroke? _stroke(StoreObject? node, double scaleX, double scaleY) {
    if (node == null || node.jcid != Jcid.inkStrokeNode) return null;
    final path = node.properties.bytes(Prop.inkPath);
    final brush = _object(node.properties.ref(Prop.inkStrokeProperties));
    final dimensionBytes = brush?.properties.bytes(Prop.inkDimensions);
    if (path == null || brush == null || dimensionBytes == null) return null;
    final dimensions = <(Guid, int, int)>[
      for (var i = 0; i + 32 <= dimensionBytes.length; i += 32)
        (
          Guid(Uint8List.sublistView(dimensionBytes, i, i + 16)),
          ByteData.sublistView(dimensionBytes).getInt32(i + 16, Endian.little),
          ByteData.sublistView(dimensionBytes).getInt32(i + 20, Endian.little),
        ),
    ];
    final values = decodeMultiByteSigned(path);
    if (dimensions.isEmpty || values.length % dimensions.length != 0) {
      return null;
    }
    final count = values.length ~/ dimensions.length;
    // Each dimension's values follow one another, each the change from the
    // one before.
    List<double>? dimension(Guid guid, double scale) {
      final index = dimensions.indexWhere((entry) => entry.$1 == guid);
      if (index < 0) return null;
      var sum = 0;
      return <double>[
        for (var i = 0; i < count; i++)
          (sum += values[index * count + i]) * scale,
      ];
    }

    final xs = dimension(_xDimension, scaleX);
    final ys = dimension(_yDimension, scaleY);
    if (xs == null || ys == null || count == 0) return null;
    final pressureAt = dimensions.indexWhere(
      (entry) => entry.$1 == _pressureDimension,
    );
    List<double>? pressures;
    if (pressureAt >= 0) {
      final (_, lower, upper) = dimensions[pressureAt];
      final span = upper - lower;
      final raw = dimension(_pressureDimension, 1)!;
      if (span > 0) {
        pressures = <double>[
          for (final value in raw) ((value - lower) / span).clamp(0.0, 1.0),
        ];
      }
    }
    final brushProperties = brush.properties;
    final tip = brushProperties.integer(Prop.inkPenTip) ?? 0;
    final transparency = brushProperties.integer(Prop.inkTransparency) ?? 0;
    final scale = (scaleX.abs() + scaleY.abs()) / 2;
    return OneStroke(
      xs: xs,
      ys: ys,
      pressures: pressures,
      width: (brushProperties.float(Prop.inkWidth) ?? 30) * scale,
      height: (brushProperties.float(Prop.inkHeight) ?? 30) * scale,
      color: brushProperties.colorRef(Prop.inkColor),
      transparency: transparency,
      rectangularTip: tip == 1,
      highlighter:
          brushProperties.integer(Prop.inkRasterOperation) == 9 ||
          (tip == 1 && transparency > 0),
    );
  }
}

/// Decodes the "multi-byte encoding of signed numbers" of the Ink
/// Serialized Format, which OneNote writes ink paths in: a count, then
/// that many values, each seven bits a byte with the sign in its lowest
/// bit.
List<int> decodeMultiByteSigned(Uint8List bytes) {
  var position = 0;
  int unsigned() {
    var value = 0;
    var shift = 0;
    while (true) {
      if (position >= bytes.length || shift > 63) {
        throw FormatDamage('An ink stroke is damaged');
      }
      final byte = bytes[position++];
      value |= (byte & 0x7F) << shift;
      shift += 7;
      if (byte & 0x80 == 0) return value;
    }
  }

  final count = unsigned() >> 1;
  final values = <int>[];
  for (var i = 0; i < count; i++) {
    final raw = unsigned();
    values.add(raw & 1 == 1 ? -(raw >> 1) : raw >> 1);
  }
  return values;
}
