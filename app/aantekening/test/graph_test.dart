import 'package:aantekening/src/graph/force_layout.dart';
import 'package:aantekening/src/graph/note_graph.dart';
import 'package:aantekening_core/aantekening_core.dart';
import 'package:flutter_test/flutter_test.dart';

Notebook _notebook(String id) =>
    Notebook(id: id, title: id, position: 0, createdAt: 0, updatedAt: 0);

Section _section(String id, String notebookId, {String? parentId}) => Section(
  id: id,
  notebookId: notebookId,
  title: id,
  position: 0,
  createdAt: 0,
  updatedAt: 0,
  parentId: parentId,
);

PageRef _page(String id, String sectionId, {String? parentId, String? title}) =>
    PageRef(
      id: id,
      sectionId: sectionId,
      title: title ?? id,
      position: 0,
      createdAt: 0,
      updatedAt: 0,
      parentId: parentId,
    );

NoteGraph _graph({String pageTitle = 'p1'}) => NoteGraph.of(
  notebooks: <Notebook>[_notebook('n1'), _notebook('n2')],
  sections: <Section>[
    _section('s1', 'n1'),
    _section('s2', 'n1', parentId: 's1'),
    _section('s3', 'n2'),
  ],
  pages: <PageRef>[
    _page('p1', 's1', title: pageTitle),
    _page('p2', 's2'),
    _page('p3', 's2', parentId: 'p2'),
    _page('p4', 's3'),
  ],
);

void main() {
  group('the graph of a workspace', () {
    test('links each node to what it is in', () {
      final graph = _graph();
      String name(int index) => graph.nodes[index].id;

      expect(
        <String>{
          for (final (parent, child) in graph.links)
            '${name(parent)}>${name(child)}',
        },
        <String>{'n1>s1', 's1>s2', 'n2>s3', 's1>p1', 's2>p2', 'p2>p3', 's3>p4'},
      );
      expect(graph.nodes[graph.indexOf('p3')!].notebookId, 'n1');
      expect(graph.nodes[graph.indexOf('p3')!].sectionId, 's2');
    });

    test('names an untitled page as the page list does', () {
      final graph = _graph(pageTitle: '');
      expect(graph.nodes[graph.indexOf('p1')!].label, 'Untitled page');
    });

    test('is the same shape when only names differ', () {
      expect(_graph().sameShape(_graph(pageTitle: 'renamed')), isTrue);
      final fewer = NoteGraph.of(
        notebooks: <Notebook>[_notebook('n1')],
        sections: const <Section>[],
        pages: const <PageRef>[],
      );
      expect(_graph().sameShape(fewer), isFalse);
    });
  });

  group('the force layout', () {
    ForceLayout settled(NoteGraph graph) {
      final layout = ForceLayout(graph);
      for (var i = 0; i < 1000 && !layout.isSettled; i++) {
        layout.step();
      }
      return layout;
    }

    test('settles, with every node apart from every other', () {
      final layout = settled(_graph());

      expect(layout.isSettled, isTrue);
      for (var i = 0; i < layout.positions.length; i++) {
        for (var j = i + 1; j < layout.positions.length; j++) {
          expect(
            (layout.positions[i] - layout.positions[j]).distance,
            greaterThan(10),
          );
        }
      }
    });

    test('keeps what is linked closer than what is not', () {
      final graph = _graph();
      final layout = settled(graph);
      double between(String a, String b) =>
          (layout.positions[graph.indexOf(a)!] -
                  layout.positions[graph.indexOf(b)!])
              .distance;

      expect(between('p3', 'p2'), lessThan(between('p3', 'p4')));
      expect(between('s3', 'n2'), lessThan(between('s3', 'n1')));
    });

    test('lays a changed graph out from where the last one was', () {
      final first = settled(_graph());
      final next = ForceLayout(_graph(), previous: first.positionsById);

      expect(next.positions, first.positions);
    });

    test('holds a node where the pointer is, and lets it go', () {
      final graph = _graph();
      final layout = settled(graph);
      final node = graph.indexOf('n1')!;

      layout.hold(node, const Offset(500, 500));
      for (var i = 0; i < 50; i++) {
        layout.step();
      }
      expect(layout.positions[node], const Offset(500, 500));
      expect(layout.isSettled, isFalse);
      expect(layout.nodeAt(const Offset(502, 499)), node);

      layout.release();
      for (var i = 0; i < 1000 && !layout.isSettled; i++) {
        layout.step();
      }
      expect(layout.isSettled, isTrue);
      expect(layout.positions[node], isNot(const Offset(500, 500)));
    });
  });
}
