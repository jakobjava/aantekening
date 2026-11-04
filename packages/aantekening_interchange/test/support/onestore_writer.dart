import 'dart:typed_data';

/// A file node to write: its id, the chunk of the file it points at — a
/// list, for [baseType] 2 — and its own fields.
typedef TestNode = ({
  int id,
  int baseType,
  (int, int)? chunk,
  List<int> fields,
});

/// A node of [id] with [fields], pointing at the list [list] or the data
/// [data] if either is given.
TestNode fileNode(
  int id, {
  List<int> fields = const <int>[],
  (int, int)? list,
  (int, int)? data,
}) => (
  id: id,
  baseType: list != null ? 2 : (data != null ? 1 : 0),
  chunk: list ?? data,
  fields: fields,
);

/// Writes a OneNote revision store file a piece at a time, as damaged and
/// hostile files are made: its header, file node lists that may point
/// anywhere — at themselves too — and chunks of bytes.
final class OneStoreWriter {
  OneStoreWriter() {
    _out.add(Uint8List(1024));
  }

  final BytesBuilder _out = BytesBuilder();

  /// Where what is written next starts.
  int get end => _out.length;

  static int _size(TestNode node) =>
      4 + (node.chunk == null ? 0 : 12) + node.fields.length;

  /// Where a list of [nodes] would be, written next, and its length.
  (int, int) nextList(List<TestNode> nodes) =>
      (end, 36 + nodes.fold<int>(0, (sum, node) => sum + _size(node)));

  /// Writes one fragment holding [nodes], followed by [next] if given,
  /// and returns where it is.
  (int, int) list(
    List<TestNode> nodes, {
    int listId = 0x10,
    int sequence = 0,
    (int, int)? next,
  }) {
    final at = nextList(nodes);
    final data = ByteData(at.$2);
    var p = 0;
    data.setUint64(p, 0xA4567AB1F5F7F4C4, Endian.little);
    data.setUint32(p += 8, listId, Endian.little);
    data.setUint32(p += 4, sequence, Endian.little);
    p += 4;
    for (final node in nodes) {
      final size = _size(node);
      data.setUint32(
        p,
        node.id | (size << 10) | (node.baseType << 27),
        Endian.little,
      );
      p += 4;
      if (node.chunk case (final offset, final length)) {
        data.setUint64(p, offset, Endian.little);
        data.setUint32(p + 8, length, Endian.little);
        p += 12;
      }
      for (final byte in node.fields) {
        data.setUint8(p++, byte);
      }
    }
    _chunk(data, p, next);
    data.setUint64(p + 12, 0x8BC215C38233BA4B, Endian.little);
    _out.add(data.buffer.asUint8List());
    return at;
  }

  /// Writes [bytes] as they are, and returns where they are.
  (int, int) data(List<int> bytes) {
    final at = (end, bytes.length);
    _out.add(bytes);
    return at;
  }

  /// Writes a transaction log fragment of [entries], each a list id and
  /// its count, followed by [next], and returns where it is.
  (int, int) transactions(List<(int, int)> entries, {(int, int)? next}) {
    final data = ByteData(entries.length * 8 + 12);
    var p = 0;
    for (final (list, count) in entries) {
      data.setUint32(p, list, Endian.little);
      data.setUint32(p + 4, count, Endian.little);
      p += 8;
    }
    _chunk(data, p, next);
    return this.data(data.buffer.asUint8List());
  }

  static void _chunk(ByteData data, int at, (int, int)? chunk) {
    data.setUint64(at, chunk?.$1 ?? -1, Endian.little);
    data.setUint32(at + 8, chunk?.$2 ?? 0, Endian.little);
  }

  /// The file, its root file node list [root], with the transaction log
  /// [log] committing [transactions].
  Uint8List finish({
    required (int, int) root,
    (int, int)? log,
    int transactions = 0,
  }) {
    final bytes = _out.toBytes();
    final header = ByteData.sublistView(bytes);
    // A section, in the revision store format.
    bytes.setAll(0, _guid('7B5C52E4-D88C-4DA7-AEB1-5378D02996D3'));
    bytes.setAll(48, _guid('109ADD3F-911B-49F5-A5D0-1791EDC8AED8'));
    header.setUint32(96, transactions, Endian.little);
    header.setUint64(160, log?.$1 ?? 0, Endian.little);
    header.setUint32(168, log?.$2 ?? 0, Endian.little);
    header.setUint64(172, root.$1, Endian.little);
    header.setUint32(180, root.$2, Endian.little);
    return bytes;
  }
}

/// The bytes of a GUID written as text, as a file holds them.
List<int> _guid(String text) {
  final hex = text.replaceAll('-', '');
  int byte(int i) => int.parse(hex.substring(i * 2, i * 2 + 2), radix: 16);
  return <int>[
    byte(3), byte(2), byte(1), byte(0), byte(5), byte(4), byte(7), byte(6), //
    for (var i = 8; i < 16; i++) byte(i),
  ];
}

/// The bytes of an extended GUID, a GUID of sixteen [fill] bytes and [n].
List<int> exGuid(int fill, int n) => <int>[
  ...List<int>.filled(16, fill),
  n & 0xFF,
  (n >> 8) & 0xFF,
  (n >> 16) & 0xFF,
  (n >> 24) & 0xFF,
];

/// [value] as four little-endian bytes.
List<int> u32(int value) => <int>[
  value & 0xFF,
  (value >> 8) & 0xFF,
  (value >> 16) & 0xFF,
  (value >> 24) & 0xFF,
];
