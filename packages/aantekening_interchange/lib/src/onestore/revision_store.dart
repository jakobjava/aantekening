/// The objects a OneNote file holds, as its latest revision has them
/// ([MS-ONESTORE] 2.1, 2.5–2.7).
library;

import 'dart:typed_data';

import 'package:meta/meta.dart';

import '../bytes.dart';
import 'file_nodes.dart';

/// An extended GUID: a GUID and a number, which together name an object,
/// an object space or a revision.
@immutable
final class ExGuid {
  const ExGuid(this.guid, this.n);

  static final ExGuid nil = ExGuid(Guid.nil, 0);

  final Guid guid;
  final int n;

  bool get isNil => n == 0 && guid.isNil;

  static ExGuid read(ByteReader reader) {
    final guid = reader.guid();
    return ExGuid(guid, reader.u32());
  }

  @override
  bool operator ==(Object other) =>
      other is ExGuid && other.n == n && other.guid == guid;

  @override
  int get hashCode => Object.hash(guid, n);

  @override
  String toString() => '{$guid}#$n';
}

/// A property's value, in whichever of the property types it was stored as
/// ([MS-ONESTORE] 2.6.6); references to other objects are already
/// resolved to their names.
sealed class PropertyValue {
  const PropertyValue();
}

final class NoValue extends PropertyValue {
  const NoValue();
}

final class BoolValue extends PropertyValue {
  const BoolValue(this.value);
  final bool value;
}

/// A fixed-width value of 1, 2, 4 or 8 bytes.
final class IntValue extends PropertyValue {
  const IntValue(this.value, this.width);
  final int value;
  final int width;

  /// The four bytes read as an IEEE float, as sizes and offsets are.
  double get asFloat {
    final data = ByteData(4)..setUint32(0, value, Endian.little);
    return data.getFloat32(0, Endian.little);
  }
}

final class BytesValue extends PropertyValue {
  const BytesValue(this.bytes);
  final Uint8List bytes;
}

/// References to objects, to object spaces or to contexts, in order; a
/// reference whose name is not in the file is null.
final class ReferencesValue extends PropertyValue {
  const ReferencesValue(this.kind, this.ids, {required this.single});
  final ReferenceKind kind;
  final List<ExGuid?> ids;

  /// Whether the property holds one reference rather than an array.
  final bool single;
}

enum ReferenceKind { object, objectSpace, context }

final class SetsValue extends PropertyValue {
  const SetsValue(this.sets);
  final List<PropertySet> sets;
}

final class SetValue extends PropertyValue {
  const SetValue(this.set);
  final PropertySet set;
}

/// Properties by id — the id without its type bits.
final class PropertySet {
  const PropertySet(this._values);

  static const PropertySet empty = PropertySet(<int, PropertyValue>{});

  final Map<int, PropertyValue> _values;

  PropertyValue? operator [](int propertyId) => _values[propertyId & 0x3FFFFFF];

  Iterable<int> get ids => _values.keys;
}

/// One object: what kind it is (its JCID), its properties, and, for an
/// object that is a file — a picture, an attachment — its bytes.
final class StoreObject {
  const StoreObject(this.jcid, this.properties, {this.fileData});

  final int jcid;
  final PropertySet properties;
  final Uint8List? fileData;
}

/// The objects of one object space, as its current revision has them: a
/// section's own space, or one of its pages.
final class ObjectSpace {
  ObjectSpace(this.id, this.objects, this.roots);

  final ExGuid id;
  final Map<ExGuid, StoreObject> objects;

  /// The root objects, by role: 1 for the content, 2 for its metadata.
  final Map<int, ExGuid> roots;

  ExGuid? get contentRoot => roots[1];
  ExGuid? get metadataRoot => roots[2];

  StoreObject? operator [](ExGuid? id) => id == null ? null : objects[id];
}

/// A OneNote revision store file, read: its object spaces as their latest
/// revisions have them.
final class RevisionStore {
  RevisionStore._(this.kind, this.root, this.spaces);

  /// Reads [bytes]; [externalFile] finds a file stored beside the section
  /// rather than in it, by its name, if it can.
  factory RevisionStore.read(
    Uint8List bytes, {
    Uint8List? Function(String name)? externalFile,
  }) {
    final file = StoreFile.read(bytes);
    final files = _fileDataStore(file);
    ExGuid? rootId;
    final spaces = <ExGuid, ObjectSpace>{};
    for (final node in file.rootList) {
      switch (node.id) {
        case NodeId.objectSpaceManifestRoot:
          rootId = ExGuid.read(node.fields);
        case NodeId.objectSpaceManifestListReference:
          final id = ExGuid.read(node.fields);
          final space = _SpaceReader(
            id,
            files,
            file.bytes,
            externalFile,
          ).read(node.children ?? const <FileNode>[]);
          spaces[id] = space;
      }
    }
    final root = spaces[rootId];
    if (root == null) throw FormatDamage('The OneNote file has no root');
    return RevisionStore._(file.kind, root, spaces);
  }

  final StoreKind kind;
  final ObjectSpace root;
  final Map<ExGuid, ObjectSpace> spaces;

  /// Files stored in the section, by GUID ([MS-ONESTORE] 2.5.21).
  static Map<Guid, Uint8List> _fileDataStore(StoreFile file) {
    final files = <Guid, Uint8List>{};
    final list = file.rootList.where(
      (node) => node.id == NodeId.fileDataStoreListReference,
    );
    for (final reference in list.expand(
      (node) => node.children ?? const <FileNode>[],
    )) {
      if (reference.id != NodeId.fileDataStoreObjectReference) continue;
      final guid = reference.fields.guid();
      final chunk = reference.chunk!;
      final object = ByteReader(file.bytes).at(chunk.offset, chunk.length);
      object.skip(16);
      final length = object.u64();
      object.skip(4 + 8);
      files[guid] = object.take(length);
    }
    return files;
  }
}

/// A revision of an object space: the objects it declared or changed, the
/// roots it set, and the global id table in effect at its end.
final class _Revision {
  _Revision(this.id, this.dependsOn, this.context, this.role);

  final ExGuid id;
  final ExGuid dependsOn;
  final ExGuid context;
  final int role;
  final Map<ExGuid, StoreObject> objects = <ExGuid, StoreObject>{};
  final Map<int, ExGuid> roots = <int, ExGuid>{};
  Map<int, Guid> ids = <int, Guid>{};
}

/// Reads one object space's revision manifest list, and puts together the
/// objects of the revision that is its current content.
final class _SpaceReader {
  _SpaceReader(this.id, this._files, this._bytes, this._externalFile);

  final ExGuid id;
  final Map<Guid, Uint8List> _files;
  final Uint8List _bytes;
  final Uint8List? Function(String name)? _externalFile;
  final Map<ExGuid, _Revision> _revisions = <ExGuid, _Revision>{};

  ObjectSpace read(List<FileNode> manifestList) {
    // The last revision manifest list is the current one.
    final lists = manifestList.where(
      (node) => node.id == NodeId.revisionManifestListReference,
    );
    if (lists.isEmpty) return ObjectSpace(id, const {}, const {});
    final revisions = lists.last.children ?? const <FileNode>[];

    // Which revision holds each role, in each context.
    final labels = <(ExGuid, int), ExGuid>{};
    var index = 0;
    while (index < revisions.length) {
      final node = revisions[index];
      switch (node.id) {
        case NodeId.revisionManifestStart4 ||
            NodeId.revisionManifestStart6 ||
            NodeId.revisionManifestStart7:
          final (revision, next) = _readRevision(revisions, index);
          _revisions[revision.id] = revision;
          labels[(revision.context, revision.role)] = revision.id;
          index = next;
        case NodeId.revisionRoleDeclaration ||
            NodeId.revisionRoleAndContextDeclaration:
          final rid = ExGuid.read(node.fields);
          final role = node.fields.u32();
          final context = node.id == NodeId.revisionRoleAndContextDeclaration
              ? ExGuid.read(node.fields)
              : ExGuid.nil;
          if (_revisions.containsKey(rid)) labels[(context, role)] = rid;
          index++;
        default:
          index++;
      }
    }

    final current = labels[(ExGuid.nil, 1)];
    if (current == null) return ObjectSpace(id, const {}, const {});
    // The revision and every one it depends on, oldest first.
    final chain = <_Revision>[];
    final seen = <ExGuid>{};
    for (
      var rid = current;
      !rid.isNil && seen.add(rid);
      rid = _revisions[rid]?.dependsOn ?? ExGuid.nil
    ) {
      final revision = _revisions[rid];
      if (revision == null) {
        throw FormatDamage('A revision depends on one that is not there');
      }
      chain.add(revision);
    }
    final objects = <ExGuid, StoreObject>{};
    final roots = <int, ExGuid>{};
    for (final revision in chain.reversed) {
      objects.addAll(revision.objects);
      roots.addAll(revision.roots);
    }
    return ObjectSpace(id, objects, roots);
  }

  /// Reads the revision manifest starting at [start], returning it and
  /// the index after its end.
  (_Revision, int) _readRevision(List<FileNode> nodes, int start) {
    final head = nodes[start];
    final rid = ExGuid.read(head.fields);
    final dependsOn = ExGuid.read(head.fields);
    if (head.id == NodeId.revisionManifestStart4) head.fields.skip(8);
    final role = head.fields.u32();
    var context = ExGuid.nil;
    if (head.id == NodeId.revisionManifestStart7) {
      head.fields.skip(2);
      context = ExGuid.read(head.fields);
    }
    final revision = _Revision(rid, dependsOn, context, role);
    final parent = dependsOn.isNil ? null : _revisions[dependsOn];
    if (!dependsOn.isNil && parent == null) {
      throw FormatDamage('A revision depends on one declared after it');
    }
    revision.ids = <int, Guid>{...?parent?.ids};

    // The global id table the declarations after it resolve their ids by.
    Map<int, Guid>? table;
    var index = start + 1;
    for (; index < nodes.length; index++) {
      final node = nodes[index];
      if (node.id == NodeId.revisionManifestEnd) {
        index++;
        break;
      }
      switch (node.id) {
        case NodeId.globalIdTableStart || NodeId.globalIdTableStart2:
          final (read, next) = _readIdTable(nodes, index, parent?.ids);
          table = read;
          revision.ids.addAll(read);
          index = next - 1;
        case NodeId.objectGroupListReference:
          _readObjectGroup(node.children ?? const [], revision);
        case NodeId.rootObjectReference3:
          final root = ExGuid.read(node.fields);
          revision.roots[node.fields.u32()] = root;
        case NodeId.rootObjectReference2:
          final root = _resolve(node.fields.u32(), table ?? revision.ids);
          final role = node.fields.u32();
          if (root != null) revision.roots[role] = root;
        case NodeId.objectRevisionWithRefCount ||
            NodeId.objectRevisionWithRefCount2:
          _readObjectRevision(node, table ?? revision.ids, revision);
        case NodeId.objectDataEncryptionKeyV2:
          throw FormatDamage(
            'This section is protected by a password. Remove the password '
            'in OneNote, export the notebook again and import that.',
          );
        default:
          _readDeclaration(node, table ?? revision.ids, revision.objects);
      }
    }
    return (revision, index);
  }

  /// Reads the global id table starting at [start], whose entries may copy
  /// from [parent]'s, returning it and the index after its end.
  (Map<int, Guid>, int) _readIdTable(
    List<FileNode> nodes,
    int start,
    Map<int, Guid>? parent,
  ) {
    final table = <int, Guid>{};
    var index = start + 1;
    for (; index < nodes.length; index++) {
      final node = nodes[index];
      final fields = node.fields;
      switch (node.id) {
        case NodeId.globalIdTableEnd:
          return (table, index + 1);
        case NodeId.globalIdTableEntry:
          final at = fields.u32();
          table[at] = fields.guid();
        case NodeId.globalIdTableEntry2:
          final from = fields.u32();
          final to = fields.u32();
          final guid = parent?[from];
          if (guid == null) throw FormatDamage('A global id is missing');
          table[to] = guid;
        case NodeId.globalIdTableEntry3:
          final from = fields.u32();
          final count = fields.u32();
          final to = fields.u32();
          for (var i = 0; i < count; i++) {
            final guid = parent?[from + i];
            if (guid == null) throw FormatDamage('A global id is missing');
            table[to + i] = guid;
          }
      }
    }
    return (table, index);
  }

  void _readObjectGroup(List<FileNode> nodes, _Revision revision) {
    Map<int, Guid> table = const {};
    for (var index = 0; index < nodes.length; index++) {
      final node = nodes[index];
      switch (node.id) {
        case NodeId.objectGroupEnd:
          return;
        case NodeId.globalIdTableStart || NodeId.globalIdTableStart2:
          final (read, next) = _readIdTable(nodes, index, null);
          table = read;
          index = next - 1;
        default:
          _readDeclaration(node, table, revision.objects);
      }
    }
  }

  /// Reads [node] into [objects] if it declares an object.
  void _readDeclaration(
    FileNode node,
    Map<int, Guid> table,
    Map<ExGuid, StoreObject> objects,
  ) {
    final fields = node.fields;
    switch (node.id) {
      case NodeId.objectDeclaration2RefCount ||
          NodeId.objectDeclaration2LargeRefCount ||
          NodeId.readOnlyObjectDeclaration2RefCount ||
          NodeId.readOnlyObjectDeclaration2LargeRefCount:
        final id = _resolve(fields.u32(), table);
        final jcid = fields.u32();
        if (id != null) {
          objects[id] = StoreObject(jcid, _propertySet(node.chunk!, table));
        }
      case NodeId.objectDeclarationWithRefCount ||
          NodeId.objectDeclarationWithRefCount2:
        final id = _resolve(fields.u32(), table);
        final bits = fields.u32();
        if (((bits >> 10) & 0xF) != 0) {
          throw FormatDamage('An object of this OneNote file is encrypted');
        }
        // The JCID index; the declaration always has a property set.
        final jcid = (bits & 0x3FF) | 0x20000;
        if (id != null) {
          objects[id] = StoreObject(jcid, _propertySet(node.chunk!, table));
        }
      case NodeId.objectDeclarationFileData3RefCount ||
          NodeId.objectDeclarationFileData3LargeRefCount:
        final id = _resolve(fields.u32(), table);
        final jcid = fields.u32();
        fields.skip(
          node.id == NodeId.objectDeclarationFileData3RefCount ? 1 : 4,
        );
        final reference = utf16Text(fields.take(fields.u32() * 2));
        final extension = utf16Text(fields.take(fields.u32() * 2));
        if (id != null) {
          objects[id] = StoreObject(
            jcid,
            PropertySet.empty,
            fileData: _fileData(reference, extension),
          );
        }
    }
  }

  /// The bytes of the file a file data declaration refers to, if they can
  /// be found.
  Uint8List? _fileData(String reference, String extension) {
    if (reference.startsWith('<ifndf>')) {
      final guid = Guid.parse(reference.substring('<ifndf>'.length));
      return _files[guid];
    }
    if (reference.startsWith('<file>')) {
      return _externalFile?.call(reference.substring('<file>'.length));
    }
    return null;
  }

  /// A later version of an object declared in this revision or one it
  /// depends on: same kind, new properties.
  void _readObjectRevision(
    FileNode node,
    Map<int, Guid> table,
    _Revision revision,
  ) {
    final id = _resolve(node.fields.u32(), table);
    if (id == null) return;
    StoreObject? earlier = revision.objects[id];
    for (
      var rid = revision.dependsOn;
      earlier == null && !rid.isNil;
      rid = _revisions[rid]?.dependsOn ?? ExGuid.nil
    ) {
      earlier = _revisions[rid]?.objects[id];
    }
    if (earlier == null) return;
    revision.objects[id] = StoreObject(
      earlier.jcid,
      _propertySet(node.chunk!, table),
      fileData: earlier.fileData,
    );
  }

  /// The name a compact id stands for in [table], or null if it is not
  /// there.
  static ExGuid? _resolve(int compact, Map<int, Guid> table) {
    final n = compact & 0xFF;
    final index = compact >> 8;
    final guid = table[index];
    return guid == null ? null : ExGuid(guid, n);
  }

  /// Reads the ObjectSpaceObjectPropSet at [chunk], resolving the
  /// references its properties make through [table].
  PropertySet _propertySet(FileChunk chunk, Map<int, Guid> table) {
    final reader = ByteReader(_bytes).at(chunk.offset, chunk.length);
    List<int> stream(int header) => <int>[
      for (var i = 0; i < (header & 0xFFFFFF); i++) reader.u32(),
    ];
    final objectHeader = reader.u32();
    final objectIds = stream(objectHeader);
    var spaceIds = const <int>[];
    var contextIds = const <int>[];
    if (objectHeader & 0x80000000 == 0) {
      final spaceHeader = reader.u32();
      spaceIds = stream(spaceHeader);
      if (spaceHeader & 0x40000000 != 0) contextIds = stream(reader.u32());
    }
    final streams = _Streams(table, objectIds, spaceIds, contextIds);
    return _readSet(reader, streams, 0);
  }

  static PropertySet _readSet(ByteReader reader, _Streams streams, int depth) {
    if (depth > 32) throw FormatDamage('Property sets nest too deep');
    final count = reader.u16();
    final ids = <int>[for (var i = 0; i < count; i++) reader.u32()];
    final values = <int, PropertyValue>{};
    for (final prid in ids) {
      values[prid & 0x3FFFFFF] = _readValue(prid, reader, streams, depth);
    }
    return PropertySet(values);
  }

  static PropertyValue _readValue(
    int prid,
    ByteReader reader,
    _Streams streams,
    int depth,
  ) {
    final type = (prid >> 26) & 0x1F;
    return switch (type) {
      0x1 => const NoValue(),
      0x2 => BoolValue((prid >> 31) & 1 == 1),
      0x3 => IntValue(reader.u8(), 1),
      0x4 => IntValue(reader.u16(), 2),
      0x5 => IntValue(reader.u32(), 4),
      0x6 => IntValue(reader.u64(), 8),
      0x7 => BytesValue(reader.take(reader.u32())),
      0x8 => streams.take(ReferenceKind.object, 1, single: true),
      0x9 => streams.take(ReferenceKind.object, reader.u32(), single: false),
      0xA => streams.take(ReferenceKind.objectSpace, 1, single: true),
      0xB => streams.take(
        ReferenceKind.objectSpace,
        reader.u32(),
        single: false,
      ),
      0xC => streams.take(ReferenceKind.context, 1, single: true),
      0xD => streams.take(ReferenceKind.context, reader.u32(), single: false),
      0x10 => () {
        final count = reader.u32();
        if (count == 0) return const SetsValue(<PropertySet>[]);
        reader.u32(); // The type of the elements, always a property set.
        return SetsValue(<PropertySet>[
          for (var i = 0; i < count; i++) _readSet(reader, streams, depth + 1),
        ]);
      }(),
      // A property set on its own takes no references from the object's
      // streams.
      0x11 => SetValue(_readSet(reader, _Streams.none, depth + 1)),
      _ => throw FormatDamage('Property type $type does not exist'),
    };
  }
}

/// The references an object's properties take from, in the order they
/// take them.
final class _Streams {
  _Streams(this._table, this._objects, this._spaces, this._contexts);

  static final _Streams none = _Streams(const {}, const [], const [], const []);

  final Map<int, Guid> _table;
  final List<int> _objects;
  final List<int> _spaces;
  final List<int> _contexts;
  int _object = 0;
  int _space = 0;
  int _context = 0;

  ReferencesValue take(ReferenceKind kind, int count, {required bool single}) {
    final (list, at) = switch (kind) {
      ReferenceKind.object => (_objects, _object),
      ReferenceKind.objectSpace => (_spaces, _space),
      ReferenceKind.context => (_contexts, _context),
    };
    final ids = <ExGuid?>[
      for (var i = 0; i < count; i++)
        at + i < list.length
            ? _SpaceReader._resolve(list[at + i], _table)
            : null,
    ];
    switch (kind) {
      case ReferenceKind.object:
        _object += count;
      case ReferenceKind.objectSpace:
        _space += count;
      case ReferenceKind.context:
        _context += count;
    }
    return ReferencesValue(kind, ids, single: single);
  }
}
