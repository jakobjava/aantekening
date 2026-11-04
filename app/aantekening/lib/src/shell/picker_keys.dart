part of 'picker.dart';

/// The picker's keys: what each does in the columns and in the graph, and
/// how a key pressed finds what it does.
extension _Keys on _PickerState {
  /// How the column is ordered, to choose from.
  KeyLayer _orders() {
    final list = _listOf(_column);
    final order = ref.read(listOrderProvider(list));
    final keys = galleryKeys(ListOrder.values.length);
    return KeyLayer.of('Order of the ${list.name}', <KeyAction>[
      for (final (index, choice) in ListOrder.values.indexed)
        KeyAction(
          keys[index],
          choice.label,
          run: () => ref.read(listOrderProvider(list).notifier).choose(choice),
          checked: choice == order,
        ),
    ]);
  }

  /// The picker's keys: what they do, and what the guide and the foot call
  /// them.
  KeyLayer _keys() {
    final pages = _column == _Column.pages;
    return KeyLayer('Picker', <KeyGroup>[
      KeyGroup(title: 'Move', <KeyAction>[
        KeyAction(
          'j',
          'Down',
          run: () => _move(1),
          also: const <String>[ModeKey.down],
        ),
        KeyAction(
          'k',
          'Up',
          run: () => _move(-1),
          also: const <String>[ModeKey.up],
        ),
        KeyAction(
          'h',
          'The column before',
          run: () => _step(-1),
          also: const <String>[ModeKey.left],
        ),
        KeyAction(
          'l',
          'The column after',
          run: () => _step(1),
          also: const <String>[ModeKey.right],
        ),
        KeyAction('g', 'The first', run: () => _toEnd(last: false)),
        KeyAction('G', 'The last', run: () => _toEnd(last: true)),
        KeyAction('z', 'Fold or unfold', run: _fold),
      ]),
      KeyGroup(title: 'Open', <KeyAction>[
        KeyAction(ModeKey.enter, pages ? 'Open' : 'Into it', run: _enter),
        KeyAction(
          't',
          'In a new tab',
          run: () {
            if (_nodeAt(_Column.pages) case final PageRef page) {
              unawaited(ref.read(libraryActionsProvider).openInNewTab(page));
            }
          },
          enabled: pages,
        ),
        KeyAction('/', 'Search instead', run: _searchInstead),
        KeyAction(ModeKey.tab, 'The graph', run: _toggleView),
      ]),
      KeyGroup(title: 'Change', <KeyAction>[
        KeyAction('n', 'New ${_newOf(_column)}', run: _create),
        if (_column != _Column.notebooks)
          KeyAction(
            'N',
            pages ? 'New subpage' : 'New subsection',
            run: () => _create(beneath: true),
          ),
        KeyAction('r', 'Rename', run: () => unawaited(_rename())),
        KeyAction(
          'd',
          'Delete',
          run: _delete,
          also: const <String>[ModeKey.delete],
        ),
        KeyAction('x', 'Cut', run: () => _clip(cut: true)),
        KeyAction('y', 'Copy', run: () => _clip(cut: false)),
        KeyAction('p', 'Paste', run: _paste),
        KeyAction('J', 'Move down', run: () => _shift(1)),
        KeyAction('K', 'Move up', run: () => _shift(-1)),
        KeyAction('o', 'Order', layer: _orders),
      ]),
      KeyGroup(<KeyAction>[
        KeyAction(ModeKey.space, 'More', run: _menu, also: const <String>['.']),
        KeyAction('b', 'Bin', run: () => unawaited(showBin(context))),
        KeyAction('?', 'These keys', layer: _keys),
        KeyAction(
          ModeKey.escape,
          'Close',
          run: () => Navigator.of(context).maybePop(),
        ),
      ]),
    ]);
  }

  static String _newOf(_Column column) => switch (column) {
    _Column.notebooks => 'notebook',
    _Column.sections => 'section',
    _Column.pages => 'page',
  };

  /// The graph's keys: back to the columns, and away.
  KeyLayer _graphKeys() => KeyLayer.of('Graph', <KeyAction>[
    KeyAction(ModeKey.tab, 'The notebooks', run: _toggleView),
    KeyAction(
      ModeKey.escape,
      'Close',
      run: () => Navigator.of(context).maybePop(),
    ),
  ]);

  /// Takes a key, saying whether it did.
  bool _press(String pressed) {
    // Under a dialog it opened — naming a notebook — the keys are its.
    if (!mounted || !(ModalRoute.of(context)?.isCurrent ?? false)) {
      return false;
    }
    final layer = _view == PickerView.library ? _keys() : _graphKeys();
    final action = layer.actionFor(pressed);
    if (action == null || !action.enabled) return false;
    if (action.layer case final next?) {
      openKeyGuide(context, pressed: pressed, layer: next, atOnce: true);
    } else {
      action.run!();
    }
    return true;
  }
}
