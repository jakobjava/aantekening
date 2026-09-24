/// What the AI needs from the workspace, and nothing more.
library;

import 'package:aantekening_core/aantekening_core.dart';

import 'conversation.dart';

/// A page in the list of what a notebook or section holds.
class PageEntry {
  const PageEntry({
    required this.id,
    required this.title,
    required this.path,
    this.createdAt,
  });

  final String id;
  final String title;

  /// The notebook and sections it is in, outermost first.
  final List<String> path;
  final DateTime? createdAt;

  /// Where it is and when it was written, in a line.
  String get context => <String>[
    if (path.isNotEmpty) path.join(' › '),
    if (createdAt != null) _date(createdAt!),
  ].join(' · ');

  static String _date(DateTime date) =>
      '${date.year}-${date.month.toString().padLeft(2, '0')}-'
      '${date.day.toString().padLeft(2, '0')}';
}

/// A notebook, section or page the AI is asked about.
class ScopeInfo {
  const ScopeInfo({
    required this.link,
    required this.title,
    required this.path,
  });

  final NoteLink link;
  final String title;

  /// What it is in, outermost first.
  final List<String> path;

  String get kindName => switch (link.kind) {
    NoteLinkKind.notebook => 'notebook',
    NoteLinkKind.section => 'section',
    NoteLinkKind.page => 'page',
  };
}

/// The workspace, as the AI reads it. The app gives this; everything the AI
/// makes of the notes is built on it, so what the AI can read grows with
/// what these can give.
abstract interface class NoteReader {
  /// What [link] names, or null if it is gone.
  Future<ScopeInfo?> scope(NoteLink link);

  /// Every page in [scope], in the order the panes list them — a page
  /// alone for a page.
  Future<List<PageEntry>> pagesIn(NoteLink scope);

  /// The page [pageId] taken apart (see [PageDigest]), or null if it is
  /// gone.
  Future<PageDigest?> digest(String pageId);

  /// The pages matching [query] best, best first, within [within] or
  /// everywhere.
  Future<List<String>> searchPages(String query, {NoteLink? within, int limit});

  /// [visual] on page [pageId] drawn as a picture to look at, or null if
  /// it cannot be drawn.
  Future<ImagePart?> render(String pageId, DigestVisual visual);
}
