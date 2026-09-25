/// The workspace as a graph of notebooks, sections and pages.
library;

import 'package:aantekening_core/aantekening_core.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../providers.dart';
import '../shell/library_menu.dart';

/// What a node of the graph stands for.
enum GraphNodeKind { notebook, section, page }

/// A notebook, section or page in the graph.
@immutable
class GraphNode {
  const GraphNode({
    required this.id,
    required this.kind,
    required this.label,
    required this.notebookId,
    this.sectionId,
  });

  final String id;
  final GraphNodeKind kind;
  final String label;

  /// The notebook it is or is in, and the section it is or is in, by which
  /// it is opened.
  final String notebookId;
  final String? sectionId;
}

/// A node for every notebook, section and page, each linked to what it is
/// in: a section to its notebook or parent section, a page to its section
/// or parent page.
@immutable
class NoteGraph {
  const NoteGraph._(this.nodes, this.links, this._index);

  factory NoteGraph.of({
    required List<Notebook> notebooks,
    required List<Section> sections,
    required List<PageRef> pages,
  }) {
    final nodes = <GraphNode>[
      for (final notebook in notebooks)
        GraphNode(
          id: notebook.id,
          kind: GraphNodeKind.notebook,
          label: notebook.title,
          notebookId: notebook.id,
        ),
    ];
    final sectionNotebook = <String, String>{
      for (final section in sections) section.id: section.notebookId,
    };
    nodes.addAll(<GraphNode>[
      for (final section in sections)
        GraphNode(
          id: section.id,
          kind: GraphNodeKind.section,
          label: section.title,
          notebookId: section.notebookId,
          sectionId: section.id,
        ),
      for (final page in pages)
        if (sectionNotebook[page.sectionId] case final notebookId?)
          GraphNode(
            id: page.id,
            kind: GraphNodeKind.page,
            label: pageTitleOrPlaceholder(page.title),
            notebookId: notebookId,
            sectionId: page.sectionId,
          ),
    ]);
    final index = <String, int>{
      for (var i = 0; i < nodes.length; i++) nodes[i].id: i,
    };
    final parents = <String, String?>{
      for (final section in sections)
        section.id: section.parentId ?? section.notebookId,
      for (final page in pages) page.id: page.parentId ?? page.sectionId,
    };
    final links = <(int, int)>[
      for (var i = 0; i < nodes.length; i++)
        if (index[parents[nodes[i].id]] case final parent?) (parent, i),
    ];
    return NoteGraph._(nodes, links, index);
  }

  final List<GraphNode> nodes;

  /// Pairs of indexes into [nodes]: what a node is in, and the node.
  final List<(int, int)> links;

  final Map<String, int> _index;

  /// The index of the node for [id], if there is one.
  int? indexOf(String id) => _index[id];

  /// The node for [id], if there is one.
  GraphNode? node(String id) => switch (_index[id]) {
    final index? => nodes[index],
    null => null,
  };

  /// Whether [other] has the same nodes, linked the same way — though they
  /// may be named differently — so a layout of this one fits it too.
  bool sameShape(NoteGraph other) =>
      listEquals(
        <String>[for (final node in nodes) node.id],
        <String>[for (final node in other.nodes) node.id],
      ) &&
      listEquals(links, other.links);
}

/// The whole workspace as a graph.
final noteGraphProvider = FutureProvider<NoteGraph>((ref) async {
  ref.watch(libraryRevisionProvider);
  final store = await ref.watch(storeProvider.future);
  final notebooks = await store.library.listNotebooks();
  return NoteGraph.of(
    notebooks: notebooks,
    sections: <Section>[
      for (final notebook in notebooks)
        ...await store.library.listAllSections(notebook.id),
    ],
    pages: await store.pages.listAllPages(),
  );
});
