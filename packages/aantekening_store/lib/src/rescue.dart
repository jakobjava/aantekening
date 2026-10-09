/// Pages that could not be saved, kept in files of their own until they
/// can be.
library;

import 'dart:convert';
import 'dart:io';

import 'package:aantekening_core/aantekening_core.dart';
import 'package:path/path.dart' as p;

import 'files/entity_files.dart';
import 'files/notes_folder.dart';
import 'library_repository.dart';
import 'page_repository.dart';

/// What could not be saved: a page's contents the store would not take —
/// the disk full, the index locked, the page deleted for good on another
/// computer while it was being edited here — kept in a file beside the
/// index, and put back the next time the notes are opened.
///
/// Nothing in it is ever deleted until what it holds is safely in the
/// notes again.
final class Rescue {
  Rescue(this.path);

  /// The folder the rescued pages are kept in.
  final String path;

  static const String _suffix = '.rescued.json.gz';

  /// Keeps [document], the contents of a page that could not be saved,
  /// with what is known of where it belongs, [page]. A page rescued again
  /// is kept in place of what was rescued of it before: its contents now
  /// hold all of that.
  Future<File> keep(PageDocument document, {PageRef? page}) async {
    final file = fileFor(document.id);
    final json = jsonEncode(<String, Object?>{
      'kind': 'aantekening rescued page',
      'rescuedAt': DateTime.now().millisecondsSinceEpoch,
      'page': ?page?.toJson(),
      'document': jsonDecode(document.encode()),
    });
    await NotesFolder.writeAtomically(
      file.path,
      pageCompression.encode(utf8.encode(json)),
    );
    return file;
  }

  /// The file the page [pageId] is rescued to.
  File fileFor(String pageId) => File(
    p.join(
      path,
      '${pageId.isEmpty ? 'page-${DateTime.now().microsecondsSinceEpoch}' : pageId}'
      '$_suffix',
    ),
  );

  /// Lets go of what was rescued of the page [pageId], now that it has
  /// been saved: what is saved holds it all.
  void release(String pageId) {
    try {
      final file = fileFor(pageId);
      if (file.existsSync()) file.deleteSync();
    } on FileSystemException {
      // Put back next time as a page of its own, beside it: nothing lost.
    }
  }

  /// Every rescued page waiting to be put back.
  List<File> get waiting {
    final directory = Directory(path);
    if (!directory.existsSync()) return const <File>[];
    return <File>[
      for (final entity in directory.listSync())
        if (entity is File && entity.path.endsWith(_suffix)) entity,
    ];
  }

  /// Puts every rescued page back into the notes, returning the pages they
  /// went into. A page not changed since it was rescued takes the rescued
  /// contents itself; otherwise — or if it is gone — the contents become a
  /// page of their own beside it, "(rescued)", or in a notebook "Rescued"
  /// if its section is gone too. A file is deleted only once what it holds
  /// is in the notes; one that cannot be read is left where it is.
  Future<List<PageRef>> restore(
    PageRepository pages,
    LibraryRepository library,
  ) async {
    final restored = <PageRef>[];
    for (final file in waiting) {
      final RescuedPage rescued;
      try {
        rescued = RescuedPage.decode(file.readAsBytesSync());
      } on Object {
        continue;
      }
      restored.add(await _putBack(rescued, pages, library));
      try {
        file.deleteSync();
      } on FileSystemException {
        // Put back again next time, as a page of its own: nothing is lost.
      }
    }
    return restored;
  }

  Future<PageRef> _putBack(
    RescuedPage rescued,
    PageRepository pages,
    LibraryRepository library,
  ) async {
    final document = rescued.document;
    final known = rescued.page;
    final current = document.id.isEmpty
        ? null
        : await pages.findPage(document.id);
    if (current != null &&
        current.deletedAt == null &&
        current.updatedAt <= rescued.rescuedAt) {
      // Nothing was saved to it since: the rescued contents are its own.
      return pages.saveDocument(current.id, document);
    }
    final where = current ?? known;
    var sectionId = where?.sectionId;
    if (sectionId == null || await library.findSection(sectionId) == null) {
      sectionId = (await rescuedSection(library)).id;
    }
    final title = where?.title ?? '';
    final page = await pages.createPage(
      sectionId: sectionId,
      title: title.isEmpty ? 'Rescued' : '$title (rescued)',
      canvas: document.canvas,
    );
    return pages.saveDocument(
      page.id,
      PageDocument(
        id: page.id,
        revision: document.revision,
        canvas: document.canvas,
        elements: document.elements,
      ),
    );
  }

  /// A section for rescued pages whose own section is gone.
  static Future<Section> rescuedSection(LibraryRepository library) async {
    const title = 'Rescued';
    for (final notebook in await library.listNotebooks()) {
      if (notebook.title != title) continue;
      for (final section in await library.listAllSections(notebook.id)) {
        if (section.title == title) return section;
      }
    }
    final notebook = await library.createNotebook(title: title);
    return library.createSection(notebookId: notebook.id, title: title);
  }
}

/// A rescued page, as its file keeps it.
final class RescuedPage {
  const RescuedPage({
    required this.document,
    required this.rescuedAt,
    this.page,
  });

  /// Reads a rescued page's file; throws if it is not one.
  factory RescuedPage.decode(List<int> bytes) {
    final json = jsonDecode(utf8.decode(gzip.decode(bytes)));
    if (json is! Map<String, Object?> ||
        json['kind'] != 'aantekening rescued page') {
      throw const FormatException('Not a rescued page');
    }
    final page = json['page'];
    return RescuedPage(
      document: PageDocument.fromJson(readObject(json, 'document')),
      rescuedAt: readInt(json, 'rescuedAt'),
      page: page is Map<String, Object?> ? PageRef.fromJson(page) : null,
    );
  }

  final PageDocument document;
  final int rescuedAt;
  final PageRef? page;
}
