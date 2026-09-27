/// The object kinds and properties of OneNote's object model ([MS-ONE]),
/// and reading their values.
library;

import 'dart:typed_data';

import '../bytes.dart';
import '../onestore/revision_store.dart';

/// Kinds of object (JCIDs).
abstract final class Jcid {
  static const sectionNode = 0x00060007;
  static const pageSeriesNode = 0x00060008;
  static const pageNode = 0x0006000B;
  static const outlineNode = 0x0006000C;
  static const outlineElementNode = 0x0006000D;
  static const richTextNode = 0x0006000E;
  static const imageNode = 0x00060011;
  static const numberListNode = 0x00060012;
  static const inkContainer = 0x00060014;
  static const outlineGroup = 0x00060019;
  static const tableNode = 0x00060022;
  static const tableRowNode = 0x00060023;
  static const tableCellNode = 0x00060024;
  static const titleNode = 0x0006002C;
  static const pageMetadata = 0x00020030;
  static const sectionMetadata = 0x00020031;
  static const embeddedFileNode = 0x00060035;
  static const pageManifestNode = 0x00060037;
  static const inkDataNode = 0x0002003B;
  static const inkStrokeNode = 0x00020047;
  static const strokePropertiesNode = 0x00120048;
  static const paragraphStyleObject = 0x0012004D;
  static const noteTagSharedDefinition = 0x00120043;
  static const tocContainer = 0x00020001;
}

/// Property ids, with their type bits as [MS-ONE] 2.1.12 gives them.
abstract final class Prop {
  static const pageWidth = 0x14001C01;
  static const pageHeight = 0x14001C02;
  static const outlineElementChildLevel = 0x0C001C03;
  static const bold = 0x08001C04;
  static const italic = 0x08001C05;
  static const underline = 0x08001C06;
  static const strikethrough = 0x08001C07;
  static const superscript = 0x08001C08;
  static const subscript = 0x08001C09;
  static const font = 0x1C001C0A;
  static const fontSize = 0x10001C0B;
  static const fontColor = 0x14001C0C;
  static const highlight = 0x14001C0D;
  static const rgOutlineIndentDistance = 0x1C001C12;
  static const offsetFromParentHoriz = 0x14001C14;
  static const offsetFromParentVert = 0x14001C15;
  static const numberListFormat = 0x1C001C1A;
  static const layoutMaxWidth = 0x14001C1B;
  static const layoutMaxHeight = 0x14001C1C;
  static const contentChildNodes = 0x24001C1F;
  static const elementChildNodes = 0x24001C20;
  static const richEditTextUnicode = 0x1C001C22;
  static const listNodes = 0x24001C26;
  static const notebookManagementEntityGuid = 0x1C001C30;
  static const pictureContainer = 0x20001C3F;
  static const inkScalingX = 0x14001C46;
  static const inkScalingY = 0x14001C47;
  static const listFont = 0x1C001C52;
  static const topologyCreationTimeStamp = 0x18001C65;
  static const isTitleTime = 0x08001C87;
  static const isTitleDate = 0x08001CB5;
  static const listRestart = 0x14001CB7;
  static const notebookElementOrderingId = 0x14001CB9;
  static const sectionColor = 0x14001CBE;
  static const cachedTitleString = 0x1C001CF3;
  static const tocChildren = 0x24001CF6;
  static const isBackground = 0x08001D13;
  static const rowCount = 0x14001D57;
  static const columnCount = 0x14001D58;
  static const tableBordersVisible = 0x08001D5E;
  static const structureElementChildNodes = 0x24001D5F;
  static const childGraphSpaceElementNodes = 0x2C001D63;
  static const tableColumnWidths = 0x1C001D66;
  static const folderChildFilename = 0x1C001D6B;
  static const lastModifiedTime = 0x14001D7A;
  static const embeddedFileContainer = 0x20001D9B;
  static const embeddedFileName = 0x1C001D9C;
  static const imageFilename = 0x1C001DD7;
  static const isDeletedGraphSpaceContent = 0x00001DE9;
  static const pageLevel = 0x14001DFF;
  static const textRunIndex = 0x1C001E12;
  static const textRunFormatting = 0x24001E13;
  static const hyperlink = 0x08001E14;
  static const hidden = 0x08001E16;
  static const textRunIsEmbeddedObject = 0x08001E22;
  static const cellBackgroundColor = 0x14001E26;
  static const imageAltText = 0x1C001E58;
  static const wzHyperlinkUrl = 0x1C001E20;
  static const mathFormatting = 0x08003401;
  static const inkPath = 0x1C00340B;
  static const inkStrokeProperties = 0x20003409;
  static const inkDimensions = 0x1C00340A;
  static const inkHeight = 0x1400340C;
  static const inkWidth = 0x1400340D;
  static const inkColor = 0x1400340F;
  static const inkPenTip = 0x0C003412;
  static const inkRasterOperation = 0x0C003413;
  static const inkTransparency = 0x0C003414;
  static const inkData = 0x20003415;
  static const inkStrokes = 0x24003416;
  static const paragraphStyle = 0x2000342C;
  static const paragraphSpaceBefore = 0x1400342E;
  static const paragraphSpaceAfter = 0x1400342F;
  static const paragraphLineSpacingExact = 0x14003430;
  static const metaDataObjectsAboveGraphSpace = 0x24003442;
  static const mathInlineObjectType = 0x1400344F;
  static const mathInlineObjectCount = 0x14003450;
  static const mathInlineObjectColumns = 0x0C003451;
  static const mathInlineObjectAlign = 0x0C003452;
  static const mathInlineObjectChar = 0x10003453;
  static const mathInlineObjectChar1 = 0x10003454;
  static const mathInlineObjectChar2 = 0x10003455;
  static const paragraphStyleId = 0x1C00345A;
  static const noteTagShape = 0x10003464;
  static const noteTagLabel = 0x1C003468;
  static const noteTagCompleted = 0x1400346F;
  static const actionItemStatus = 0x10003470;
  static const paragraphAlignment = 0x0C003477;
  static const noteTagDefinitionOid = 0x20003488;
  static const noteTags = 0x40003489;
  static const textExtendedAscii = 0x1C003498;
  static const textRunData = 0x40003499;
  static const sectionDisplayName = 0x1C00349B;
  static const pictureFileExtension = 0x24003424;
  static const pictureWidth = 0x140034CD;
  static const pictureHeight = 0x140034CE;
}

/// Reading a [PropertySet]'s values as the types they are meant as.
extension PropertyReading on PropertySet {
  bool flag(int id) => switch (this[id]) {
    BoolValue(:final value) => value,
    _ => false,
  };

  int? integer(int id) => switch (this[id]) {
    IntValue(:final value) => value,
    _ => null,
  };

  /// A four-byte float, as OneNote's sizes and offsets are.
  double? float(int id) => switch (this[id]) {
    IntValue(width: 4) && final IntValue value => () {
      final float = value.asFloat;
      return float.isFinite ? float : null;
    }(),
    _ => null,
  };

  Uint8List? bytes(int id) => switch (this[id]) {
    BytesValue(:final bytes) => bytes,
    _ => null,
  };

  /// A UTF-16 string.
  String? text(int id) {
    final value = bytes(id);
    return value == null ? null : utf16Text(value);
  }

  List<ExGuid?> refs(int id) => switch (this[id]) {
    ReferencesValue(:final ids) => ids,
    _ => const <ExGuid?>[],
  };

  ExGuid? ref(int id) {
    final all = refs(id);
    return all.isEmpty ? null : all.first;
  }

  List<PropertySet> sets(int id) => switch (this[id]) {
    SetsValue(:final sets) => sets,
    _ => const <PropertySet>[],
  };

  /// A COLORREF: an RGB colour, or null for "automatic".
  int? colorRef(int id) {
    final value = integer(id);
    if (value == null || (value >> 24) & 0xFF != 0) return null;
    final red = value & 0xFF;
    final green = (value >> 8) & 0xFF;
    final blue = (value >> 16) & 0xFF;
    return 0xFF000000 | (red << 16) | (green << 8) | blue;
  }

  /// A FILETIME, 100-nanosecond steps since 1601, as a UTC time.
  DateTime? fileTime(int id) {
    final value = integer(id);
    if (value == null || value <= 0) return null;
    final micros = value ~/ 10 - 11644473600000000;
    return DateTime.fromMicrosecondsSinceEpoch(micros, isUtc: true);
  }

  /// A Time32, seconds since 1980, as a UTC time.
  DateTime? time32(int id) {
    final value = integer(id);
    if (value == null) return null;
    return DateTime.utc(1980).add(Duration(seconds: value));
  }
}
