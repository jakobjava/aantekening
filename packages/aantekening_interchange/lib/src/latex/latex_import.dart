/// Bringing over LaTeX documents: each a page here, its text in a box.
library;

import 'dart:convert';
import 'dart:io';

import 'package:aantekening_core/aantekening_core.dart';
import 'package:path/path.dart' as p;

import '../importer.dart';
import 'latex_text.dart';

/// Reads LaTeX documents (.tex), each as a page in the section open: its
/// text, headings, lists and tables in a box, its formulas typeset
/// (`LatexText`).
final class LatexImporter implements NotesImporter {
  const LatexImporter();

  /// Where the box holding a document's text is placed: beneath the page's
  /// title, as wide as a page of text.
  static const Frame boxFrame = Frame(x: 40, y: 120, width: 640, height: 100);

  @override
  String get name => 'LaTeX';

  @override
  String get description =>
      'LaTeX documents (.tex), each as a page: its text, sections, lists and '
      'tables in a box, and its formulas typeset.';

  @override
  List<String> get extensions => const <String>['tex'];

  @override
  ImportSource get source => ImportSource.files;

  @override
  ImportTarget get target => ImportTarget.section;

  @override
  NotesDraft read(List<String> paths, ImportWork work) {
    final sorted = <String>[...paths]..sort();
    final pages = <PageDraft>[];
    for (final (index, path) in sorted.indexed) {
      work.progress('Reading ${p.basename(path)}', index / sorted.length);
      pages.add(_page(File(path)));
    }
    return NotesDraft(pages: pages);
  }

  PageDraft _page(File file) {
    final document = LatexText.read(
      utf8.decode(file.readAsBytesSync(), allowMalformed: true),
    );
    final now = file.lastModifiedSync().millisecondsSinceEpoch;
    return PageDraft(
      title: document.title ?? p.basenameWithoutExtension(file.path),
      createdAt: now,
      document: PageDocument(
        id: Ulid.generate(),
        elements: <NoteElement>[
          if (document.blocks.isNotEmpty)
            TextElement(
              id: Ulid.generate(),
              frame: boxFrame,
              createdAt: now,
              updatedAt: now,
              blocks: document.blocks,
            ),
        ],
      ),
    );
  }
}
