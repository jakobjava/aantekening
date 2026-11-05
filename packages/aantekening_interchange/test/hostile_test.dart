import 'dart:async';
import 'dart:io';
import 'dart:isolate';
import 'dart:typed_data';

import 'package:aantekening_interchange/aantekening_interchange.dart';
import 'package:aantekening_interchange/src/bytes.dart';
import 'package:aantekening_interchange/src/onenote/model.dart';
import 'package:aantekening_interchange/src/onenote/notebook_reader.dart';
import 'package:aantekening_interchange/src/onenote/properties.dart';
import 'package:aantekening_interchange/src/onenote/section_reader.dart';
import 'package:aantekening_interchange/src/onestore/file_nodes.dart';
import 'package:aantekening_interchange/src/onestore/revision_store.dart';
import 'package:aantekening_store/aantekening_store.dart' show ArchiveExport;
import 'package:archive/archive.dart' show Archive, ArchiveFile, ZipEncoder;
import 'package:path/path.dart' as p;
import 'package:test/test.dart';

import 'support/onestore_writer.dart';

/// Files made to hang a reader or to fill the memory — references that
/// point back at themselves, or at one thing many times over — are read
/// soon all the same, or refused: beside the fuzzer, which damages files
/// at random, these are damaged on purpose.
void main() {
  group('OneNote file node lists', () {
    test('refuse a list that holds itself, however often', () async {
      final writer = OneStoreWriter();
      final self = writer.nextList(<TestNode>[
        for (var i = 0; i < 2; i++) fileNode(0x090, list: (0, 0)),
      ]);
      writer.list(<TestNode>[
        for (var i = 0; i < 2; i++) fileNode(0x090, list: self),
      ]);
      final bytes = writer.finish(root: self);
      expect(
        await bounded(() => StoreFile.read(bytes)),
        'damage: A file node list loops back on itself',
      );
    });

    test('refuse lists that hold one list twice, on and on', () async {
      // Each list holds the next twice: 2^40 lists, read one by one.
      final writer = OneStoreWriter();
      var next = writer.list(const <TestNode>[]);
      for (var i = 0; i < 40; i++) {
        next = writer.list(<TestNode>[
          fileNode(0x090, list: next),
          fileNode(0x090, list: next),
        ]);
      }
      final bytes = writer.finish(root: next);
      expect(
        await bounded(() => StoreFile.read(bytes)),
        startsWith('damage: '),
      );
    });

    test('refuse a transaction log that loops back on itself', () async {
      final writer = OneStoreWriter();
      final root = writer.list(const <TestNode>[]);
      final log = (writer.end, 8 * 4 + 12);
      writer.transactions(<(int, int)>[
        for (var i = 0; i < 4; i++) (0x10, 1),
      ], next: log);
      final bytes = writer.finish(
        root: root,
        log: log,
        transactions: 0xFFFFFFFF,
      );
      expect(
        await bounded(() => StoreFile.read(bytes)),
        'damage: The transaction log loops back on itself',
      );
    });
  });

  group('OneNote files damaged where a range error waited', () {
    // Each of these once failed with an error of its own, not as damage,
    // and took the whole notebook down with it.
    test('say a fragment too short to hold its header is damage', () async {
      final writer = OneStoreWriter();
      // The magic, a list id and the first sequence number, and no more.
      final root = writer.data(<int>[
        0xC4, 0xF4, 0xF7, 0xF5, 0xB1, 0x7A, 0x56, 0xA4, //
        ...u32(0x10),
        ...u32(0),
      ]);
      final log = writer.data(List<int>.filled(8, 0));
      expect(
        await bounded(() => StoreFile.read(writer.finish(root: root))),
        'damage: A file node list fragment is too short',
      );
      expect(
        await bounded(
          () => StoreFile.read(
            writer.finish(root: root, log: log, transactions: 1),
          ),
        ),
        'damage: A fragment of the transaction log is too short',
      );
    });

    test('say a transaction log past every offset is damage', () async {
      final writer = OneStoreWriter();
      final root = writer.list(const <TestNode>[]);
      final bytes = writer.finish(
        root: root,
        log: (-1 << 63, 12),
        transactions: 1,
      );
      expect(await bounded(() => StoreFile.read(bytes)), startsWith('damage'));
    });

    test('say a file reference pointing at nothing is damage', () async {
      final writer = OneStoreWriter();
      final files = writer.list(<TestNode>[
        fileNode(
          NodeId.fileDataStoreObjectReference,
          fields: List<int>.filled(16, 0xF0),
        ),
      ]);
      final root = writer.list(<TestNode>[
        fileNode(NodeId.fileDataStoreListReference, list: files),
      ]);
      final bytes = writer.finish(root: root);
      expect(
        await bounded(() => RevisionStore.read(bytes)),
        'damage: A file node points at nothing it should',
      );
    });
  });

  group('OneNote revisions', () {
    test('end the search for an earlier object, revisions looping', () async {
      // B; A on B; B again, on A — so A, B and A again —; and C on B,
      // which changes an object none of them has.
      final writer = OneStoreWriter();
      List<TestNode> revision(int id, int? on, [List<TestNode>? nodes]) =>
          <TestNode>[
            fileNode(
              NodeId.revisionManifestStart6,
              fields: <int>[
                ...exGuid(0xB0, id),
                ...(on == null ? exGuid(0, 0) : exGuid(0xB0, on)),
                ...u32(1),
                0,
                0,
              ],
            ),
            ...?nodes,
            fileNode(NodeId.revisionManifestEnd),
          ];
      final properties = writer.data(<int>[0, 0, 0, 0, 0, 0, 0, 0, 0, 0]);
      final revisions = writer.list(<TestNode>[
        ...revision(2, null),
        ...revision(1, 2),
        ...revision(2, 1),
        ...revision(3, 2, <TestNode>[
          fileNode(NodeId.globalIdTableStart2),
          fileNode(
            NodeId.globalIdTableEntry,
            fields: <int>[...u32(0), ...List<int>.filled(16, 0xC0)],
          ),
          fileNode(NodeId.globalIdTableEnd),
          fileNode(
            NodeId.objectRevisionWithRefCount,
            fields: u32(1),
            data: properties,
          ),
        ]),
      ]);
      final manifests = writer.list(<TestNode>[
        fileNode(NodeId.revisionManifestListReference, list: revisions),
      ]);
      final root = writer.list(<TestNode>[
        fileNode(NodeId.objectSpaceManifestRoot, fields: exGuid(0xA0, 1)),
        fileNode(
          NodeId.objectSpaceManifestListReference,
          fields: exGuid(0xA0, 1),
          list: manifests,
        ),
      ]);
      final bytes = writer.finish(root: root);
      expect(await bounded(() => RevisionStore.read(bytes)), 'read');
    });
  });

  group('compressed files', () {
    late Directory folder;

    setUp(() => folder = Directory.systemTemp.createTempSync('hostile_'));
    tearDown(() => folder.deleteSync(recursive: true));

    // Eighty megabytes of nothing, which deflate keeps in eighty kilobytes.
    final nothing = Uint8List(80 << 20);

    test('inflate to no more than their limit', () {
      final packed = Uint8List.fromList(gzip.encode(Uint8List(1 << 20)));
      expect(inflateAtMost(packed, 1 << 20), hasLength(1 << 20));
      expect(
        () => inflateAtMost(packed, (1 << 20) - 1),
        throwsA(isA<FormatDamage>()),
      );
      final raw = Uint8List.fromList(
        ZLibEncoder(raw: true).convert(Uint8List(1000)),
      );
      expect(inflateAtMost(raw, 1000, raw: true), hasLength(1000));
    });

    test('a Xournal++ document unpacking to far more than it is is '
        'refused', () {
      final path = p.join(folder.path, 'Bomb.xopp');
      File(path).writeAsBytesSync(gzip.encode(nothing));
      final draft = const XournalImporter().read(<String>[
        path,
      ], ImportWork(Directory(p.join(folder.path, 'work'))..createSync()));
      expect(draft.pages, isEmpty);
      expect(draft.warnings.single, contains('unpacks to more than'));
    });

    test('an export unpacking to far more than it is is refused', () {
      final path = p.join(folder.path, 'Bomb.aantekening');
      final archive = Archive()
        ..addFile(ArchiveFile.string(ArchiveExport.manifestName, '{}'))
        ..addFile(ArchiveFile.bytes('pages/bomb.json', nothing));
      File(path).writeAsBytesSync(ZipEncoder().encode(archive));
      expect(File(path).lengthSync(), lessThan(1 << 20));
      expect(
        () => const AantekeningImporter().read(<String>[
          path,
        ], ImportWork(Directory(p.join(folder.path, 'work'))..createSync())),
        throwsA(isA<FormatDamage>()),
      );
    });
  });

  group('OneNote pages', () {
    test('pass over an outline element within itself', () async {
      final store = _section(<ExGuid, StoreObject>{
        _id(10): _node(Jcid.outlineElementNode, <int, List<ExGuid>>{
          Prop.elementChildNodes: <ExGuid>[_id(10), _id(11), _id(10)],
        }),
        _id(11): _node(Jcid.outlineElementNode),
      });
      expect(
        await bounded(() {
          final page = readSection(store, 'Loops').pages.single;
          final outline = page.contents.single as OneOutline;
          final element = outline.elements.single;
          if (element.children.length != 1) throw StateError('$element');
        }),
        'read',
      );
    });

    test('refuse elements that hold one element twice, on and on', () async {
      // Each element holds the next twice: 2^40 elements, read one by one.
      final store = _section(<ExGuid, StoreObject>{
        for (var i = 10; i < 50; i++)
          _id(i): _node(Jcid.outlineElementNode, <int, List<ExGuid>>{
            Prop.elementChildNodes: <ExGuid>[_id(i + 1), _id(i + 1)],
          }),
        _id(50): _node(Jcid.outlineElementNode),
      });
      expect(
        await bounded(() => readSection(store, 'Twice')),
        startsWith('damage: '),
      );
    });

    test('read a table of contents listing an entry within itself, or '
        'its entries over and over', () async {
      // An entry within itself; and entries a thousand times sixteen deep.
      ObjectSpace contents(Map<ExGuid, StoreObject> objects) => ObjectSpace(
        _id(0),
        <ExGuid, StoreObject>{
          _id(1): _node(0, <int, List<ExGuid>>{
            Prop.tocChildren: <ExGuid>[_id(1), _id(2)],
          }),
          ...objects,
        },
        <int, ExGuid>{1: _id(1)},
      );
      final loop = RevisionStore.of(
        StoreKind.tableOfContents,
        contents(<ExGuid, StoreObject>{
          _id(2): _node(0, const <int, List<ExGuid>>{}, 'Physik.one'),
        }),
        const <ExGuid, ObjectSpace>{},
      );
      expect(tableOfContents(loop), <String>['Physik.one']);
      final over = RevisionStore.of(
        StoreKind.tableOfContents,
        contents(<ExGuid, StoreObject>{
          for (var i = 2; i < 18; i++)
            _id(i): _node(0, <int, List<ExGuid>>{
              Prop.tocChildren: List<ExGuid>.filled(1000, _id(i + 1)),
            }),
        }),
        const <ExGuid, ObjectSpace>{},
      );
      expect(
        await bounded(() => tableOfContents(over)),
        startsWith('damage: '),
      );
    });
  });
}

ExGuid _id(int n) =>
    ExGuid(Guid.parse('11111111-2222-3333-4444-555555555555'), n);

/// An object of [jcid] referring to others by [references], named [name].
StoreObject _node(
  int jcid, [
  Map<int, List<ExGuid>> references = const <int, List<ExGuid>>{},
  String? name,
]) => StoreObject(
  jcid,
  PropertySet(<int, PropertyValue>{
    for (final MapEntry(:key, :value) in references.entries)
      key & 0x3FFFFFF: ReferencesValue(
        ReferenceKind.object,
        value,
        single: false,
      ),
    if (name != null)
      Prop.folderChildFilename & 0x3FFFFFF: BytesValue(
        Uint8List.fromList(<int>[
          for (final unit in '$name\u0000'.codeUnits) ...<int>[unit, 0],
        ]),
      ),
  }),
);

/// A section of one page, whose outline holds the element `_id(10)` of
/// [elements].
RevisionStore _section(Map<ExGuid, StoreObject> elements) {
  final page = _id(100);
  final space = ObjectSpace(
    page,
    <ExGuid, StoreObject>{
      _id(1): _node(0),
      _id(2): _node(0, <int, List<ExGuid>>{
        Prop.contentChildNodes: <ExGuid>[_id(3)],
      }),
      _id(3): _node(Jcid.pageNode, <int, List<ExGuid>>{
        Prop.elementChildNodes: <ExGuid>[_id(4)],
      }),
      _id(4): _node(Jcid.outlineNode, <int, List<ExGuid>>{
        Prop.elementChildNodes: <ExGuid>[_id(10)],
      }),
      ...elements,
    },
    <int, ExGuid>{1: _id(2), 2: _id(1)},
  );
  final root = ObjectSpace(
    _id(0),
    <ExGuid, StoreObject>{
      _id(1): _node(Jcid.sectionNode, <int, List<ExGuid>>{
        Prop.elementChildNodes: <ExGuid>[_id(2)],
      }),
      _id(2): StoreObject(
        Jcid.pageSeriesNode,
        PropertySet(<int, PropertyValue>{
          Prop.childGraphSpaceElementNodes & 0x3FFFFFF: ReferencesValue(
            ReferenceKind.objectSpace,
            <ExGuid>[page],
            single: false,
          ),
        }),
      ),
    },
    <int, ExGuid>{1: _id(1)},
  );
  return RevisionStore.of(StoreKind.section, root, <ExGuid, ObjectSpace>{
    page: space,
  });
}

/// What [read] comes to, in an isolate of its own given a few seconds:
/// 'read', 'damage: ' and what it found, the error it ran into, or
/// 'timeout'.
Future<String> bounded(void Function() read) async {
  final port = ReceivePort();
  final isolate = await Isolate.spawn((SendPort send) {
    try {
      read();
      send.send('read');
    } on FormatDamage catch (damage) {
      send.send('damage: ${damage.message}');
    } on Object catch (error) {
      send.send('error: $error');
    }
  }, port.sendPort);
  try {
    return await port.first.timeout(
      const Duration(seconds: 20),
      onTimeout: () => 'timeout',
    ) as String;
  } finally {
    isolate.kill(priority: Isolate.immediate);
    port.close();
  }
}
