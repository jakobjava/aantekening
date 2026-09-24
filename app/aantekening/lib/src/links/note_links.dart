/// Opening links: to notes, and to the web.
library;

import 'package:aantekening_core/aantekening_core.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:url_launcher/url_launcher.dart';

import '../providers.dart';
import '../shell/library_actions.dart';
import '../shell/tabs.dart';

/// A place on a page to be brought into view once the page is showing.
class RevealRequest extends Notifier<NoteLink?> {
  @override
  NoteLink? build() => null;

  void request(NoteLink link) => state = link;

  /// Clears the request, once it has been met.
  void done() => state = null;
}

final revealRequestProvider = NotifierProvider<RevealRequest, NoteLink?>(
  RevealRequest.new,
);

/// Opens links wherever they are found: in a text box, in an AI answer's
/// sources, on the clipboard.
class NoteLinks {
  const NoteLinks(this._ref);

  final Ref _ref;

  /// Opens [uri]: a note in the app — in a tab of its own with [newTab],
  /// one already showing it if there is one — and anything else in the
  /// browser. Returns whether there was anything to open.
  Future<bool> open(String uri, {bool newTab = false}) async {
    final link = NoteLink.tryParse(uri);
    if (link != null) return openNote(link, newTab: newTab);
    final web = Uri.tryParse(uri);
    if (web == null || !(web.isScheme('http') || web.isScheme('https'))) {
      return false;
    }
    try {
      return await launchUrl(web, mode: LaunchMode.externalApplication);
    } on Object catch (error) {
      debugPrint('Could not open $uri: $error');
      return false;
    }
  }

  /// Shows what [link] points at, and brings the place on the page into
  /// view.
  Future<bool> openNote(NoteLink link, {bool newTab = false}) async {
    final store = await _ref.read(storeProvider.future);
    String? notebookId;
    String? sectionId;
    String? pageId;
    switch (link.kind) {
      case NoteLinkKind.page:
        final page = await store.pages.findPage(link.id);
        if (page == null || page.isDeleted) return false;
        pageId = page.id;
        sectionId = page.sectionId;
        notebookId = (await store.library.findSection(sectionId))?.notebookId;
      case NoteLinkKind.section:
        final section = await store.library.findSection(link.id);
        if (section == null || section.isDeleted) return false;
        sectionId = section.id;
        notebookId = section.notebookId;
      case NoteLinkKind.notebook:
        final notebook = await store.library.findNotebook(link.id);
        if (notebook == null || notebook.isDeleted) return false;
        notebookId = notebook.id;
    }
    if (notebookId == null) return false;

    final tabs = _ref.read(tabsProvider.notifier);
    final showing = _ref
        .read(tabsProvider)
        .tabs
        .indexWhere((tab) => tab.pageId == pageId && pageId != null && !tab.ai);
    if (newTab && showing >= 0) {
      tabs.activate(showing);
    } else if (newTab) {
      tabs.open(notebookId: notebookId, sectionId: sectionId, pageId: pageId);
    } else {
      tabs.updateCurrent((tab) => tab.inAi(false));
      final actions = _ref.read(libraryActionsProvider);
      if (pageId != null) {
        actions.openPage(
          notebookId: notebookId,
          sectionId: sectionId!,
          pageId: pageId,
        );
      } else if (sectionId != null) {
        actions.openSection(notebookId, sectionId);
      } else {
        actions.openNotebook(notebookId);
      }
    }
    if (link.elementId != null) {
      _ref.read(revealRequestProvider.notifier).request(link);
    }
    return true;
  }
}

final noteLinksProvider = Provider<NoteLinks>(NoteLinks.new);
