/// Choosing what of the notes goes with a question, and writing it out.
library;

import 'dart:math' as math;

import 'package:aantekening_core/aantekening_core.dart';

import 'conversation.dart';
import 'note_reader.dart';
import 'provider.dart';

/// How much of the notes goes with a question: a share of what the model
/// can take, so there is room for its answer and for what it reads later.
class ContextBudget {
  const ContextBudget({required this.characters, required this.images});

  /// For a model that can do [capabilities]: [notesTokens] of the notes,
  /// and no more than a third of its context.
  factory ContextBudget.forModel(
    ModelCapabilities capabilities, {
    int notesTokens = defaultNotesTokens,
  }) => ContextBudget(
    characters: math.min(capabilities.contextTokens * 4 ~/ 3, notesTokens * 4),
    images: capabilities.vision ? 6 : 0,
  );

  /// About forty thousand tokens, so a question costs what it needs to and
  /// not what the model could take.
  static const int defaultNotesTokens = 40000;

  /// How many tokens of the notes can go with a question, to choose from:
  /// less for a quick question, more to read a notebook at once.
  static const List<int> notesChoices = <int>[
    10000,
    40000,
    100000,
    200000,
    400000,
  ];

  final int characters;
  final int images;
}

/// The notes that go with the first question about a notebook, section or
/// page.
class ScopeContext {
  const ScopeContext({
    required this.overview,
    required this.sources,
    required this.images,
  });

  /// What is in the scope, page by page, and which pages were not given
  /// whole: for the model to know what else it can read.
  final String overview;
  final List<Source> sources;
  final List<ImagePart> images;
}

/// Pages as sources, and the context of a scope.
class NoteContext {
  const NoteContext(this.reader);

  final NoteReader reader;

  /// The notes of [scope] for a first question — [question], if it is
  /// known — within [budget]: its pages whole while they fit, those most
  /// about the question first, and the rest named in the overview; and
  /// what is on them to look at, writing over PDF pages first. With
  /// [tools], the model is told it can read what was not given.
  Future<ScopeContext> build(
    ScopeInfo scope, {
    required ContextBudget budget,
    String? question,
    bool tools = false,
  }) async {
    final pages = await reader.pagesIn(scope.link);
    final ranked = question == null || question.trim().isEmpty
        ? const <String>[]
        : await reader.searchPages(question, within: scope.link, limit: 20);
    final order = <PageEntry>[
      for (final id in ranked) ?pages.where((p) => p.id == id).firstOrNull,
      for (final page in pages)
        if (!ranked.contains(page.id)) page,
    ];

    var room = budget.characters;
    final sources = <Source>[];
    final given = <String>{};
    final seen = <(String, DigestVisual)>[];
    for (final page in order) {
      final digest = await reader.digest(page.id);
      if (digest == null || (digest.isEmpty && digest.visuals.isEmpty)) {
        continue;
      }
      // A page on its own is given as much of it as fits; in a section or
      // notebook, a page is given whole or named.
      final alone = scope.link.kind == NoteLinkKind.page;
      if (!alone && digest.length > room) continue;
      final source = pageSource(
        digest,
        context: page.context,
        limit: room,
        tools: tools,
      );
      sources.add(source);
      given.add(page.id);
      room -= digest.length;
      seen.addAll(<(String, DigestVisual)>[
        for (final visual in digest.visuals) (page.id, visual),
      ]);
      if (room <= 0) break;
    }

    seen.sort((a, b) => _visualRank(a.$2).compareTo(_visualRank(b.$2)));
    final images = <ImagePart>[];
    for (final (pageId, visual) in seen) {
      if (images.length >= budget.images) break;
      // Plain PDF pages and pictures in a section are for looking at when
      // asked about; writing and drawings say nothing without being seen.
      if (scope.link.kind != NoteLinkKind.page && _visualRank(visual) > 1) {
        continue;
      }
      final image = await reader.render(pageId, visual);
      if (image != null) images.add(image);
    }

    return ScopeContext(
      overview: _overview(scope, pages, given, tools: tools),
      sources: sources,
      images: images,
    );
  }

  /// Handwriting over something first, then drawings, then pictures, then
  /// PDF pages, whose text is given already.
  static int _visualRank(DigestVisual visual) => visual.annotated
      ? 0
      : switch (visual.kind) {
          DigestKind.drawing => 1,
          DigestKind.picture => 2,
          _ => 3,
        };

  /// What [scope] holds, page by page under the sections they are in,
  /// each named once, saying which were not [given].
  String _overview(
    ScopeInfo scope,
    List<PageEntry> pages,
    Set<String> given, {
    required bool tools,
  }) {
    final out = StringBuffer()
      ..writeln(
        'The ${scope.kindName} "${scope.title}"'
        '${scope.path.isEmpty ? '' : ', in ${scope.path.join(' › ')}'}, '
        'holds ${pages.length} ${pages.length == 1 ? 'page' : 'pages'}'
        '${pages.length == given.length ? ', all given here' : ''}:',
      );
    String? place;
    for (final page in pages) {
      final where = page.path.join(' › ');
      if (where != place && pages.length > 1) {
        out.writeln('${where.isEmpty ? 'At the top' : where}:');
        place = where;
      }
      out.writeln(
        '- "${page.title}"'
        '${page.createdAt == null ? '' : ' (${PageEntry.dateOf(page.createdAt!)})'}'
        ' [page ${page.id}]'
        '${given.contains(page.id) ? '' : ' — not given'}',
      );
    }
    if (pages.length > given.length) {
      out.writeln(
        tools
            ? 'Pages marked "not given" are not among the sources here: read '
                  'one with read_page when it matters.'
            : 'Pages marked "not given" did not fit with the sources here.',
      );
    }
    return out.toString();
  }

  /// [digest] as a source: each passage of it citable on its own, and each
  /// visual named where it is, for the model to ask to see. With [limit],
  /// no more than that many characters of it, and a last passage saying
  /// the page goes on.
  static Source pageSource(
    PageDigest digest, {
    String? context,
    int? limit,
    bool tools = true,
  }) {
    final passages = <SourcePassage>[];
    final shown = <String>{};
    var length = 0;
    var cut = false;
    for (final item in digest.items) {
      for (final passage in item.passages) {
        if (limit != null && length + passage.text.length > limit) {
          cut = true;
          break;
        }
        length += passage.text.length;
        passages.addAll(_citable(passage));
      }
      if (cut) break;
      final notes = item.notes.isEmpty ? '' : ' (${item.notes.join('; ')})';
      final itemLink = NoteLink.page(digest.pageId, elementId: item.elementId);
      for (final id in item.visualIds) {
        final visual = digest.visual(id)!;
        // Each visual is named once, where it first comes; what else is
        // shown in it — an answer typed onto a worksheet — says so.
        if (shown.add(visual.id)) {
          passages.add(
            SourcePassage(
              '[Visual ${visual.id} on page ${digest.pageId}: '
              '${visual.description}]$notes',
              uri: visual.link.toString(),
            ),
          );
        } else if (notes.isNotEmpty) {
          passages.add(
            SourcePassage('[${item.notes.join('; ')}]', uri: '$itemLink'),
          );
        }
      }
    }
    if (cut) {
      passages.add(
        SourcePassage(
          tools
              ? '[The page goes on; read it whole with read_page '
                    '${digest.pageId}.]'
              : '[The page goes on, beyond what fits here.]',
          uri: digest.link.toString(),
        ),
      );
    }
    return Source(
      uri: digest.link.toString(),
      title: digest.title.isEmpty ? 'Untitled page' : digest.title,
      origin: SourceOrigin.notes,
      context: context,
      passages: passages,
    );
  }

  /// The passages of [digest] that [terms] find, each with the passage
  /// before and after it for context, up to [limit] of them.
  static Source matchingSource(
    PageDigest digest,
    SearchTerms terms, {
    String? context,
    int limit = 8,
  }) {
    final all = digest.passages.toList();
    final keep = <int>{};
    for (var i = 0; i < all.length && keep.length < limit * 3; i++) {
      if (terms.matchesIn(all[i].text).isNotEmpty) {
        keep.addAll(
          <int>[i - 1, i, i + 1].where((j) => j >= 0 && j < all.length),
        );
      }
    }
    final chosen = (keep.toList()..sort()).take(limit * 3).toList();
    return Source(
      uri: digest.link.toString(),
      title: digest.title.isEmpty ? 'Untitled page' : digest.title,
      origin: SourceOrigin.notes,
      context: context,
      passages: <SourcePassage>[
        for (final i
            in chosen.isEmpty
                ? List<int>.generate(math.min(3, all.length), (i) => i)
                : chosen)
          ..._citable(all[i]),
      ],
    );
  }

  /// [passage] as passages to cite: sentence by sentence, where it has
  /// more than one.
  static List<SourcePassage> _citable(DigestPassage passage) => <SourcePassage>[
    for (final (i, part) in passage.citable.indexed)
      SourcePassage(part.text, uri: part.link.toString(), follows: i > 0),
  ];
}
