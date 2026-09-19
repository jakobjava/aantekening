import 'package:aantekening_core/aantekening_core.dart';
import 'package:test/test.dart';

typedef _Item = ({String id, String? parent});

Hierarchy<_Item> _tree(List<_Item> items) => Hierarchy<_Item>.of(
  items,
  idOf: (item) => item.id,
  parentOf: (item) => item.parent,
);

List<String> _read(Hierarchy<_Item> tree, {Set<String> collapsed = const {}}) =>
    <String>[
      for (final (:id, :depth, item: _, last: _) in tree.walk(
        expanded: (id) => !collapsed.contains(id),
      ))
        '${'  ' * depth}$id',
    ];

void main() {
  group('a hierarchy', () {
    final tree = _tree(<_Item>[
      (id: 'a', parent: null),
      (id: 'a1', parent: 'a'),
      (id: 'b', parent: null),
      (id: 'a2', parent: 'a'),
      (id: 'a1x', parent: 'a1'),
    ]);

    test('reads each item followed by what lies beneath it, in order', () {
      expect(_read(tree), <String>['a', '  a1', '    a1x', '  a2', 'b']);
      expect(tree.roots.map((item) => item.id), <String>['a', 'b']);
      expect(tree.childrenOf('a').map((item) => item.id), <String>['a1', 'a2']);
      expect(tree.hasChildren('a1'), isTrue);
      expect(tree.hasChildren('b'), isFalse);
      expect(tree.parentOf('a1x'), 'a1');
      expect(tree.ancestorsOf('a1x'), <String>['a1', 'a']);
      expect(
        tree.walk().where((entry) => entry.last).map((entry) => entry.id),
        <String>['a1x', 'a2', 'b'],
      );
      expect(tree['a2']?.parent, 'a');
    });

    test('leaves out what lies beneath a collapsed item', () {
      expect(_read(tree, collapsed: <String>{'a1'}), <String>[
        'a',
        '  a1',
        '  a2',
        'b',
      ]);
      expect(_read(tree, collapsed: <String>{'a'}), <String>['a', 'b']);
    });

    test('knows what lies within what', () {
      expect(tree.isWithin('a1x', 'a'), isTrue);
      expect(tree.isWithin('a', 'a'), isTrue);
      expect(tree.isWithin('a', 'a1x'), isFalse);
      expect(tree.isWithin('b', 'a'), isFalse);
      expect(tree.isWithin('unknown', 'a'), isFalse);
    });

    test('puts an item whose parent is missing at the top', () {
      final orphaned = _tree(<_Item>[
        (id: 'a', parent: null),
        (id: 'lost', parent: 'gone'),
      ]);
      expect(_read(orphaned), <String>['a', 'lost']);
      expect(orphaned.parentOf('lost'), isNull);
    });

    test('breaks a loop of parents rather than losing its items', () {
      final looped = _tree(<_Item>[
        (id: 'x', parent: 'y'),
        (id: 'y', parent: 'x'),
      ]);
      expect(_read(looped), <String>['x', '  y']);
      expect(looped.isWithin('y', 'x'), isTrue);
      expect(looped.isWithin('x', 'y'), isFalse);
    });

    test('is built for sections and pages from their parents', () {
      final pages = PageRef.hierarchy(const <PageRef>[
        PageRef(
          id: 'p',
          sectionId: 's',
          title: 'p',
          position: 0,
          createdAt: 0,
          updatedAt: 0,
        ),
        PageRef(
          id: 'q',
          sectionId: 's',
          title: 'q',
          position: 1,
          createdAt: 0,
          updatedAt: 0,
          parentId: 'p',
        ),
      ]);
      expect(pages.childrenOf('p').single.id, 'q');
    });
  });
}
