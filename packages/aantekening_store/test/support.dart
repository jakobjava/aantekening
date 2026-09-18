import 'dart:io';

import 'package:aantekening_core/aantekening_core.dart';
import 'package:aantekening_store/aantekening_store.dart';

/// An in-memory store plus the temporary directory its assets live in.
class TestWorkspace {
  TestWorkspace(this.store, this._assetDirectory);

  factory TestWorkspace.create() {
    final directory = Directory.systemTemp.createTempSync('aantekening_test_');
    return TestWorkspace(
      AantekeningStore.inMemory(assetDirectory: directory),
      directory,
    );
  }

  final AantekeningStore store;
  final Directory _assetDirectory;

  Future<void> dispose() async {
    await store.close();
    if (_assetDirectory.existsSync()) {
      _assetDirectory.deleteSync(recursive: true);
    }
  }

  /// Creates a notebook, a section inside it and returns the section id.
  Future<String> seedSection({
    String notebook = 'Maths',
    String section = 'Analysis',
  }) async {
    final book = await store.library.createNotebook(title: notebook);
    final created = await store.library.createSection(
      notebookId: book.id,
      title: section,
    );
    return created.id;
  }
}

/// Builds a page document holding a single text element with [body].
PageDocument documentWithText(String pageId, String body) {
  const now = 1758000000000;
  return PageDocument.empty(id: pageId).withElementAdded(
    TextElement(
      id: Ulid.generate(),
      frame: const Frame(x: 0, y: 0, width: 400, height: 100),
      createdAt: now,
      updatedAt: now,
      blocks: <TextBlock>[
        for (final line in body.split('\n')) TextBlock.plain(line),
      ],
    ),
  );
}
