/// Notes read from elsewhere and not yet stored: notebooks, sections and
/// pages as a whole, to be stored at once.
library;

import '../document/page_document.dart';

/// A notebook brought in whole.
final class NotebookDraft {
  const NotebookDraft({
    required this.title,
    this.sections = const <SectionDraft>[],
    this.color,
  });

  final String title;
  final List<SectionDraft> sections;
  final int? color;
}

/// A section, with the sections beneath it and its pages.
final class SectionDraft {
  const SectionDraft({
    required this.title,
    this.sections = const <SectionDraft>[],
    this.pages = const <PageDraft>[],
    this.color,
  });

  final String title;
  final List<SectionDraft> sections;
  final List<PageDraft> pages;
  final int? color;
}

/// A page, with its subpages.
///
/// Its [document]'s pictures and files are named by the keys of the
/// [NotesDraft.assets] they are among, until they are stored.
final class PageDraft {
  const PageDraft({
    required this.title,
    required this.createdAt,
    required this.document,
    this.subpages = const <PageDraft>[],
    this.id,
  });

  final String title;

  /// When the page was made, in milliseconds since the epoch: the date and
  /// time it shows beneath its title.
  final int createdAt;
  final PageDocument document;
  final List<PageDraft> subpages;

  /// The identifier to keep, for a page coming back from an export of this
  /// app, so links to it still lead there; stored under a new one if that
  /// is taken.
  final String? id;
}

/// A picture or file a draft page shows, waiting in a file to be stored.
final class AssetDraft {
  const AssetDraft({required this.path, required this.mimeType, this.name});

  final String path;
  final String mimeType;

  /// The name it had, if it had one.
  final String? name;
}

/// Everything read from one import: notebooks, or sections and pages to go
/// into the one open, their pictures and files, and what could not be
/// brought over.
final class NotesDraft {
  const NotesDraft({
    this.notebooks = const <NotebookDraft>[],
    this.sections = const <SectionDraft>[],
    this.pages = const <PageDraft>[],
    this.assets = const <String, AssetDraft>{},
    this.warnings = const <String>[],
  });

  final List<NotebookDraft> notebooks;
  final List<SectionDraft> sections;
  final List<PageDraft> pages;

  /// The pictures and files, by the keys the pages name them by.
  final Map<String, AssetDraft> assets;

  /// What was read only in part, or not at all, and why.
  final List<String> warnings;

  bool get isEmpty => notebooks.isEmpty && sections.isEmpty && pages.isEmpty;

  /// How many pages there are, at every depth.
  int get pageCount {
    int inPages(List<PageDraft> pages) =>
        pages.fold(0, (sum, page) => sum + 1 + inPages(page.subpages));
    int inSections(List<SectionDraft> sections) => sections.fold(
      0,
      (sum, section) =>
          sum + inPages(section.pages) + inSections(section.sections),
    );
    return inPages(pages) +
        inSections(sections) +
        notebooks.fold(0, (sum, book) => sum + inSections(book.sections));
  }
}
