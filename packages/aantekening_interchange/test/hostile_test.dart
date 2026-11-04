import 'dart:async';
import 'dart:isolate';

import 'package:aantekening_interchange/src/bytes.dart';
import 'package:aantekening_interchange/src/onestore/file_nodes.dart';
import 'package:aantekening_interchange/src/onestore/revision_store.dart';
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
}

/// What [read] comes to, in an isolate of its own given a few seconds:
/// 'read', 'damage: ' and what it found, the error it ran into, or
/// 'timeout'.
Future<String> bounded(Object? Function() read) async {
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
        )
        as String;
  } finally {
    isolate.kill(priority: Isolate.immediate);
    port.close();
  }
}
