/// What is done to notebooks, sections and pages: creating, opening,
/// renaming, deleting, copying and moving them.
library;

import 'dart:async';

import 'package:aantekening_core/aantekening_core.dart';
import 'package:aantekening_store/aantekening_store.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../providers.dart';
import 'tabs.dart';
import 'tree_rows.dart';

/// A section or page cut or copied, to be pasted elsewhere: moved there if it
/// was cut, copied there if it was copied.
@immutable
class LibraryClip {
  const LibraryClip(this.node, {required this.cut});

  /// A [Section] or a [PageRef].
  final TreeNode node;
  final bool cut;
}

class LibraryClipboard extends Notifier<LibraryClip?> {
  @override
  LibraryClip? build() => null;

  void hold(TreeNode node, {required bool cut}) =>
      state = LibraryClip(node, cut: cut);

  void clear() => state = null;
}

final libraryClipboardProvider =
    NotifierProvider<LibraryClipboard, LibraryClip?>(LibraryClipboard.new);

/// A page whose title takes the keyboard when it opens: one just created, as
/// OneNote puts the caret in a new page's title.
class TitleFocusRequest extends Notifier<String?> {
  @override
  String? build() => null;

  void request(String pageId) => state = pageId;

  /// Takes the request for [pageId], so it is honoured once.
  bool take(String pageId) {
    if (state != pageId) return false;
    state = null;
    return true;
  }
}

final titleFocusProvider = NotifierProvider<TitleFocusRequest, String?>(
  TitleFocusRequest.new,
);

/// Everything done to notebooks, sections and pages: each change written to
/// the store, the lists refreshed, and the selection kept on something that
/// exists.
///
/// The navigation panes, their menus, the page's title, search and the graph
/// all come through here, so each of these is done one way wherever it is
/// started from.
class LibraryActions {
  const LibraryActions(this._ref);

  final Ref _ref;

  Future<AantekeningStore> get _store => _ref.read(storeProvider.future);

  void _changed() => _ref.read(libraryRevisionProvider.notifier).bump();

  /// Selects what is opened, and expands the rows above it in the panes so
  /// it shows there, wherever it was opened from.
  void _select({String? notebookId, String? sectionId, String? pageId}) {
    _ref.read(selectedNotebookProvider.notifier).select(notebookId);
    _ref.read(selectedSectionProvider.notifier).select(sectionId);
    _ref.read(selectedPageProvider.notifier).select(pageId);
    unawaited(
      _reveal(notebookId: notebookId, sectionId: sectionId, pageId: pageId),
    );
  }

  Future<void> _reveal({
    String? notebookId,
    String? sectionId,
    String? pageId,
  }) async {
    if (notebookId == null) return;
    final above = <String>[notebookId];
    if (sectionId != null) {
      final sections = await _ref.read(sectionTreeProvider(notebookId).future);
      above.addAll(sections.ancestorsOf(sectionId));
      if (pageId != null) {
        final pages = await _ref.read(pageTreeProvider(sectionId).future);
        above.addAll(pages.ancestorsOf(pageId));
      }
    }
    _ref.read(collapsedRowsProvider.notifier).expand(above);
  }

  // ---------------------------------------------------------------- opening

  void openNotebook(String notebookId) => _select(notebookId: notebookId);

  void openSection(String notebookId, String sectionId) =>
      _select(notebookId: notebookId, sectionId: sectionId);

  /// Opens a page, and the notebook and section it is in with it, so the
  /// panes show where it lives.
  void openPage({
    required String notebookId,
    required String sectionId,
    required String pageId,
  }) => _select(notebookId: notebookId, sectionId: sectionId, pageId: pageId);

  /// Shows the AI of [node] — a notebook, section or page — in the tab
  /// showing, in place of the page.
  Future<void> openAi(TreeNode node) async {
    switch (node) {
      case Notebook(:final id):
        openNotebook(id);
      case Section(:final id, :final notebookId):
        openSection(notebookId, id);
      case PageRef(:final id):
        if (!await openPageId(id)) return;
      default:
        return;
    }
    _ref.read(tabsProvider.notifier).updateCurrent((tab) => tab.inAi(true));
  }

  /// Opens the page [pageId], wherever it is, saying whether it could be:
  /// not if it has since been deleted.
  Future<bool> openPageId(String pageId) async {
    final page = await _ref.read(pageProvider(pageId).future);
    if (page == null || page.isDeleted) return false;
    final section = await _ref.read(sectionProvider(page.sectionId).future);
    if (section == null || section.isDeleted) return false;
    openPage(
      notebookId: section.notebookId,
      sectionId: section.id,
      pageId: page.id,
    );
    return true;
  }

  /// Opens the page [by] places below the one open in its section — above,
  /// for a negative [by] — counting subpages where they are in the list,
  /// and stopping at either end. With no page open, opens the first.
  Future<void> stepPage(int by) async {
    final sectionId = _ref.read(selectedSectionProvider);
    final notebookId = _ref.read(selectedNotebookProvider);
    if (sectionId == null || notebookId == null) return;
    final tree = await _ref.read(pageTreeProvider(sectionId).future);
    final pages = <String>[for (final entry in tree.walk()) entry.id];
    final next = _stepIn(pages, _ref.read(selectedPageProvider), by);
    if (next != null) {
      openPage(notebookId: notebookId, sectionId: sectionId, pageId: next);
    }
  }

  /// Opens the section [by] places below the one open in its notebook —
  /// above, for a negative [by] — and its first page, stopping at either
  /// end.
  Future<void> stepSection(int by) async {
    final notebookId = _ref.read(selectedNotebookProvider);
    if (notebookId == null) return;
    final tree = await _ref.read(sectionTreeProvider(notebookId).future);
    final sections = <String>[for (final entry in tree.walk()) entry.id];
    final next = _stepIn(sections, _ref.read(selectedSectionProvider), by);
    if (next == null) return;
    final pages = await _ref.read(pageTreeProvider(next).future);
    final first = pages.walk().firstOrNull?.id;
    if (first == null) {
      openSection(notebookId, next);
    } else {
      openPage(notebookId: notebookId, sectionId: next, pageId: first);
    }
  }

  /// The id [by] places on from [current] in [ids], the first if there is
  /// no [current], or null past either end.
  static String? _stepIn(List<String> ids, String? current, int by) {
    if (ids.isEmpty) return null;
    final at = current == null ? -1 : ids.indexOf(current);
    if (at < 0) return ids.first;
    final to = at + by;
    return to < 0 || to >= ids.length ? null : ids[to];
  }

  /// Opens [page] in a tab of its own, after the tab showing, and shows it.
  Future<void> openInNewTab(PageRef page) async {
    final section = await _ref.read(sectionProvider(page.sectionId).future);
    _ref
        .read(tabsProvider.notifier)
        .open(
          notebookId: section?.notebookId,
          sectionId: page.sectionId,
          pageId: page.id,
        );
    await _reveal(
      notebookId: section?.notebookId,
      sectionId: page.sectionId,
      pageId: page.id,
    );
  }

  /// Opens the page [pageId] in a tab of its own, if it is still there.
  Future<void> openIdInNewTab(String pageId) async {
    final page = await _ref.read(pageProvider(pageId).future);
    if (page != null && !page.isDeleted) await openInNewTab(page);
  }

  // --------------------------------------------------------------- creating

  /// Creates a notebook, with a first section and a first page in it, as a
  /// paper notebook starts with a first page, and opens that page.
  Future<void> createNotebook(String title) async {
    final store = await _store;
    final notebook = await store.library.createNotebook(title: title);
    final section = await store.library.createSection(
      notebookId: notebook.id,
      title: 'Notes',
    );
    final page = await store.pages.createPage(sectionId: section.id);
    _changed();
    openPage(notebookId: notebook.id, sectionId: section.id, pageId: page.id);
  }

  /// Creates a section at the end of [notebookId], or of [parentId]'s
  /// subsections, and opens it.
  Future<void> createSection({
    required String notebookId,
    required String title,
    String? parentId,
  }) async {
    final store = await _store;
    final section = await store.library.createSection(
      notebookId: notebookId,
      title: title,
      parentId: parentId,
    );
    _changed();
    openSection(notebookId, section.id);
  }

  /// Creates a page at the end of [sectionId], or of [parentId]'s subpages,
  /// and opens it with the caret in its title.
  Future<void> createPage({required String sectionId, String? parentId}) async {
    final store = await _store;
    final section = await store.library.findSection(sectionId);
    if (section == null) return;
    final page = await store.pages.createPage(
      sectionId: sectionId,
      parentId: parentId,
    );
    _changed();
    _ref.read(titleFocusProvider.notifier).request(page.id);
    openPage(
      notebookId: section.notebookId,
      sectionId: sectionId,
      pageId: page.id,
    );
  }

  // ------------------------------------------------------------- changing

  /// Renames a notebook, section or page.
  Future<void> rename(TreeNode node, String title) async {
    final store = await _store;
    switch (node) {
      case Notebook(:final id):
        await store.library.renameNotebook(id, title);
      case Section(:final id):
        await store.library.renameSection(id, title);
      case PageRef(:final id):
        return renamePage(id, title);
      default:
        throw ArgumentError.value(
          node,
          'node',
          'not a notebook, section or page',
        );
    }
    _changed();
  }

  /// Renames a page, as its title field does while it is typed in.
  Future<void> renamePage(String pageId, String title) async {
    final store = await _store;
    await store.pages.renamePage(pageId, title);
    _changed();
  }

  /// Sets the date and time shown beneath a page's title.
  Future<void> setPageDate(String pageId, DateTime date) async {
    final store = await _store;
    await store.pages.setPageDate(pageId, date.millisecondsSinceEpoch);
    _changed();
  }

  /// Deletes a notebook, section or page, and everything in it.
  Future<void> delete(TreeNode node) async {
    final store = await _store;
    final List<String> deleted;
    switch (node) {
      case Notebook(:final id):
        await store.library.deleteNotebook(id);
        deleted = <String>[id];
      case Section(:final id):
        deleted = await store.library.deleteSection(id);
      case PageRef(:final id):
        deleted = await store.pages.deletePage(id);
      default:
        throw ArgumentError.value(
          node,
          'node',
          'not a notebook, section or page',
        );
    }
    // No tab goes on showing what was deleted, nor what was in it.
    _ref.read(tabsProvider.notifier).forget(deleted);
    final clip = _ref.read(libraryClipboardProvider);
    if (clip != null && deleted.contains(clip.node.id)) {
      _ref.read(libraryClipboardProvider.notifier).clear();
    }
    _changed();
  }

  // ------------------------------------------------------ cutting, copying

  void cut(TreeNode node) =>
      _ref.read(libraryClipboardProvider.notifier).hold(node, cut: true);

  void copy(TreeNode node) =>
      _ref.read(libraryClipboardProvider.notifier).hold(node, cut: false);

  /// Whether what is cut or copied can be pasted onto [target]: a page into a
  /// section or after another page, a section into a notebook or another
  /// section — though never a section into itself, nor a cut page beneath
  /// itself.
  bool canPaste(TreeNode target) {
    final clip = _ref.read(libraryClipboardProvider);
    return switch ((clip?.node, target)) {
      (PageRef(), Section()) => true,
      (PageRef(:final id), PageRef(:final sectionId)) =>
        !clip!.cut ||
            !_isWithin(
              _ref.read(pageTreeProvider(sectionId)).value,
              target,
              id,
            ),
      (Section(), Notebook()) => true,
      (Section(:final id), Section(:final notebookId)) => !_isWithin(
        _ref.read(sectionTreeProvider(notebookId)).value,
        target,
        id,
      ),
      _ => false,
    };
  }

  /// Whether [node] is [ancestor] or lies beneath it in [tree], taking it to
  /// be until [tree] has been read.
  static bool _isWithin(
    Hierarchy<TreeNode>? tree,
    TreeNode node,
    String ancestor,
  ) => tree?.isWithin(node.id, ancestor) ?? true;

  /// Pastes what is cut or copied onto [target], as [canPaste] allows, and
  /// opens what was pasted.
  Future<void> paste(TreeNode target) async {
    final clip = _ref.read(libraryClipboardProvider);
    if (clip == null) return;
    final store = await _store;
    switch ((clip.node, target)) {
      case (PageRef page, Section section):
        await _pastePage(store, clip, page, section.notebookId, section.id);
      case (PageRef page, PageRef after):
        final section = await store.library.findSection(after.sectionId);
        if (section == null) return;
        await _pastePage(
          store,
          clip,
          page,
          section.notebookId,
          after.sectionId,
          parentId: after.parentId,
          after: after.id,
        );
      case (Section section, Notebook notebook):
        await _pasteSection(store, clip, section, notebook.id);
      case (Section section, Section parent):
        await _pasteSection(
          store,
          clip,
          section,
          parent.notebookId,
          parentId: parent.id,
        );
      default:
        return;
    }
    if (clip.cut) _ref.read(libraryClipboardProvider.notifier).clear();
    _changed();
  }

  Future<void> _pastePage(
    AantekeningStore store,
    LibraryClip clip,
    PageRef page,
    String notebookId,
    String sectionId, {
    String? parentId,
    String? after,
  }) async {
    final String pageId;
    if (clip.cut) {
      await store.pages.movePage(
        page.id,
        sectionId: sectionId,
        parentId: parentId,
        after: after,
      );
      pageId = page.id;
    } else {
      final copy = await store.pages.copyPage(
        page.id,
        sectionId: sectionId,
        parentId: parentId,
        after: after,
      );
      pageId = copy.id;
    }
    openPage(notebookId: notebookId, sectionId: sectionId, pageId: pageId);
  }

  Future<void> _pasteSection(
    AantekeningStore store,
    LibraryClip clip,
    Section section,
    String notebookId, {
    String? parentId,
  }) async {
    final String sectionId;
    if (clip.cut) {
      await store.library.moveSection(
        section.id,
        notebookId: notebookId,
        parentId: parentId,
      );
      sectionId = section.id;
    } else {
      final copy = await store.library.copySection(
        section.id,
        notebookId: notebookId,
        parentId: parentId,
      );
      sectionId = copy.id;
    }
    openSection(notebookId, sectionId);
  }
}

final libraryActionsProvider = Provider<LibraryActions>(LibraryActions.new);
