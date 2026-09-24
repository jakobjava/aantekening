/// The workspace, as the AI reads it.
library;

import 'package:aantekening_ai/aantekening_ai.dart';
import 'package:aantekening_core/aantekening_core.dart';
import 'package:aantekening_store/aantekening_store.dart';

import '../shell/library_menu.dart';
import 'visual_renderer.dart';

/// Reads the workspace for the AI: what a notebook or section holds, pages
/// taken apart, searches, and visuals drawn — each page read once for each
/// version of it.
class WorkspaceReader implements NoteReader {
  WorkspaceReader(this.store) : _renderer = VisualRenderer(store);

  final AantekeningStore store;
  final VisualRenderer _renderer;

  /// Pages read, with the version each was read at.
  final Map<String, ({int revision, PageDocument document, PageDigest digest})>
  _read =
      <String, ({int revision, PageDocument document, PageDigest digest})>{};

  @override
  Future<ScopeInfo?> scope(NoteLink link) async {
    switch (link.kind) {
      case NoteLinkKind.page:
        final page = await store.pages.findPage(link.id);
        if (page == null || page.isDeleted) return null;
        return ScopeInfo(
          link: link.whole,
          title: displayTitle(page),
          path: await _sectionPath(page.sectionId),
        );
      case NoteLinkKind.section:
        final section = await store.library.findSection(link.id);
        if (section == null || section.isDeleted) return null;
        final path = await _sectionPath(section.id);
        return ScopeInfo(
          link: link.whole,
          title: section.title,
          path: path.sublist(0, path.length - 1),
        );
      case NoteLinkKind.notebook:
        final notebook = await store.library.findNotebook(link.id);
        if (notebook == null || notebook.isDeleted) return null;
        return ScopeInfo(
          link: link.whole,
          title: notebook.title,
          path: const <String>[],
        );
    }
  }

  /// The notebook and sections, outermost first, down to section [id].
  Future<List<String>> _sectionPath(String id) async {
    final section = await store.library.findSection(id);
    if (section == null) return const <String>[];
    final notebook = await store.library.findNotebook(section.notebookId);
    final sections = Section.hierarchy(
      await store.library.listAllSections(section.notebookId),
    );
    return <String>[
      ?notebook?.title,
      for (final above in sections.ancestorsOf(id).toList().reversed)
        ?sections[above]?.title,
      section.title,
    ];
  }

  @override
  Future<List<PageEntry>> pagesIn(NoteLink scope) async {
    switch (scope.kind) {
      case NoteLinkKind.page:
        final page = await store.pages.findPage(scope.id);
        if (page == null || page.isDeleted) return const <PageEntry>[];
        return <PageEntry>[
          await _entry(page, await _sectionPath(page.sectionId)),
        ];
      case NoteLinkKind.section:
        final section = await store.library.findSection(scope.id);
        if (section == null) return const <PageEntry>[];
        return _pagesOfSections(section.notebookId, within: section.id);
      case NoteLinkKind.notebook:
        return _pagesOfSections(scope.id);
    }
  }

  /// The pages of notebook [notebookId]'s sections — only section [within]
  /// and those in it, if given — in the order the panes list them.
  Future<List<PageEntry>> _pagesOfSections(
    String notebookId, {
    String? within,
  }) async {
    final sections = Section.hierarchy(
      await store.library.listAllSections(notebookId),
    );
    final out = <PageEntry>[];
    for (final entry in sections.walk()) {
      if (within != null &&
          entry.id != within &&
          !sections.isWithin(entry.id, within)) {
        continue;
      }
      final path = await _sectionPath(entry.id);
      final pages = PageRef.hierarchy(await store.pages.listPages(entry.id));
      for (final page in pages.walk()) {
        out.add(await _entry(page.item, path));
      }
    }
    return out;
  }

  Future<PageEntry> _entry(PageRef page, List<String> path) async => PageEntry(
    id: page.id,
    title: displayTitle(page),
    path: path,
    createdAt: DateTime.fromMillisecondsSinceEpoch(page.createdAt),
  );

  /// Page [pageId] read and taken apart, or null if it is gone.
  Future<({int revision, PageDocument document, PageDigest digest})?> _page(
    String pageId,
  ) async {
    final page = await store.pages.findPage(pageId);
    if (page == null || page.isDeleted) return null;
    final kept = _read[pageId];
    if (kept != null && kept.revision == page.revision) return kept;
    final document =
        await store.pages.loadDocument(pageId) ??
        PageDocument.empty(id: pageId);
    final read = (
      revision: page.revision,
      document: document,
      digest: PageDigest.of(
        document,
        title: displayTitle(page),
        createdAt: DateTime.fromMillisecondsSinceEpoch(page.createdAt),
      ),
    );
    return _read[pageId] = read;
  }

  @override
  Future<PageDigest?> digest(String pageId) async =>
      (await _page(pageId))?.digest;

  @override
  Future<List<String>> searchPages(
    String query, {
    NoteLink? within,
    int limit = 10,
  }) async {
    final hits = await store.search.search(
      query,
      matchAny: true,
      prefixLastTerm: false,
      limit: 80,
    );
    final allowed = within == null
        ? null
        : <String>{for (final page in await pagesIn(within)) page.id};
    return <String>[
      for (final hit in hits)
        if (allowed == null || allowed.contains(hit.pageId)) hit.pageId,
    ].take(limit).toList();
  }

  @override
  Future<ImagePart?> render(String pageId, DigestVisual visual) async {
    final page = await _page(pageId);
    if (page == null) return null;
    return _renderer.render(page.document, visual, revision: page.revision);
  }
}
