part of 'page_editor.dart';

/// The keys of each mode the page is in, and the menu — Space, Ctrl+Space,
/// or a right-click — with everything the page can do a key or two away.
extension _Keys on _PageEditorState {
  PageLayers get _layers => PageLayers(_commands, context, ref);

  /// Takes a key pressed while the page has the keyboard and nothing on it
  /// is typed in: the mode's, if it has one for it. Any other goes on to
  /// the page's shortcuts.
  KeyEventResult _onModeKey(FocusNode node, KeyEvent event) {
    if (!_pageShowing || _mode == EditorMode.insert) {
      return KeyEventResult.ignored;
    }
    // Space held moves the page with the pointer, as it always has; let go
    // without that, it opens the menu.
    final keyboard = HardwareKeyboard.instance;
    if (event.logicalKey == LogicalKeyboardKey.space &&
        !keyboard.isControlPressed &&
        !keyboard.isAltPressed &&
        !keyboard.isMetaPressed) {
      if (event is KeyDownEvent) {
        _space = _SpaceHeld.alone;
      } else if (event is KeyUpEvent) {
        if (_space == _SpaceHeld.alone) _openMenu();
        _space = null;
      }
      return KeyEventResult.handled;
    }
    final pressed = ModeKey.of(event, HardwareKeyboard.instance);
    if (pressed == null) return KeyEventResult.ignored;
    if (_space == _SpaceHeld.alone) {
      // A key pressed before Space is let go, as fast typing rolls over:
      // the menu's first key.
      _space = _SpaceHeld.rolledOver;
      _openMenu();
      pressInKeyGuide(pressed);
      return KeyEventResult.handled;
    }
    final action = _modeKeys().actionFor(pressed);
    if (action == null || !action.enabled) return KeyEventResult.ignored;
    _take(pressed, action);
    return KeyEventResult.handled;
  }

  /// Notes that the pointer was pressed on the page, which with Space held
  /// moves the page rather than opening the menu.
  void _pressedWithKeys(PointerDownEvent event) {
    if (_space != null) _space = _SpaceHeld.withPointer;
  }

  /// Runs [action], or opens its layer in the guide.
  void _take(String pressed, KeyAction action) {
    final layer = action.layer;
    if (layer == null) {
      action.run!();
      return;
    }
    openKeyGuide(
      context,
      pressed: pressed,
      layer: layer,
      atOnce: !action.waits,
    );
  }

  /// The keys of a tab with no page open: the menu, and the ways to a page.
  KeyLayer _emptyKeys() {
    final layers = _layers;
    return KeyLayer.of('No page open', <KeyAction>[
      KeyAction(ModeKey.space, 'Menu', layer: _menu),
      layers.command('p', AppCommand.notebooks, label: 'Pages'),
      layers.command('P', AppCommand.goTo, label: 'A page by name…'),
      layers.command('/', AppCommand.search),
      layers.command(':', AppCommand.commands, label: 'Commands…'),
      KeyAction('?', 'These keys', layer: _emptyKeys),
    ]);
  }

  KeyEventResult _onEmptyKey(FocusNode node, KeyEvent event) {
    if (event is KeyUpEvent) return KeyEventResult.ignored;
    final pressed = ModeKey.of(event, HardwareKeyboard.instance);
    final action = pressed == null ? null : _emptyKeys().actionFor(pressed);
    if (action == null || !action.enabled) return KeyEventResult.ignored;
    _take(pressed!, action);
    return KeyEventResult.handled;
  }

  /// Opens the menu, from the keys or, [clicked], a right-click — which has
  /// set where on the page it was. With no page open, it offers what needs
  /// none.
  void _openMenu({bool clicked = false}) {
    if (widget.aiScope != null) return;
    if (!clicked) _menuPoint = null;
    openKeyGuide(
      context,
      pressed: clicked ? 'Menu' : ModeKey.space,
      layer: _menu,
      atOnce: true,
    );
  }

  /// The menu a right-click opens, from the keys: the text's, in the box
  /// typed in, for what is picked in it or at its caret; else the page's,
  /// for what is picked on it.
  void _openPickedMenu() {
    if (_editingId != null && _textController.isActive) {
      _textController.showMenu();
    } else {
      _openMenu();
    }
  }

  /// What every menu opened on the page offers after its own commands —
  /// a text box's, say: formatting the text, and formulas.
  List<KeyAction> _menuExtras() => <KeyAction>[
    KeyAction('f', 'Text', layer: _layers.text),
    KeyAction('m', 'Formulas', layer: _layers.math),
  ];

  /// The keys of the mode the page is in.
  KeyLayer _modeKeys() => switch (_mode) {
    EditorMode.draw => _drawKeys(),
    EditorMode.select => _selectKeys(),
    EditorMode.normal || EditorMode.insert || EditorMode.ai => _normalKeys(),
  };

  // ----------------------------------------------------------------- menu

  /// Everything the page can do, a key or two away.
  KeyLayer _menu() {
    final layers = _layers;
    final some = _controller.selection.isNotEmpty;
    final selected = _controller.selectedElements;
    final picture = selected.length == 1 && selected.single.asEmbed != null
        ? selected.single
        : null;
    final point = _menuPoint;
    final background = !some && point != null
        ? _controller.backgroundAt(point)
        : null;
    final go = KeyGroup(title: 'Go', <KeyAction>[
      layers.command('p', AppCommand.notebooks, label: 'Pages'),
      layers.command('P', AppCommand.goTo, label: 'A page by name…'),
      layers.command('/', AppCommand.search),
      layers.command('g', AppCommand.graph),
      layers.command(':', AppCommand.commands, label: 'Commands…'),
      KeyAction('t', 'Tabs', layer: _tabKeys),
    ]);
    KeyGroup window({required bool page}) =>
        KeyGroup(title: 'Window', <KeyAction>[
          KeyAction('n', 'New', layer: _newKeys),
          KeyAction('w', 'Window', layer: _windowKeys),
          if (page) ...<KeyAction>[
            KeyAction('z', 'View', layer: layers.view),
            KeyAction('r', 'Spelling', layer: layers.spelling),
          ],
          layers.command('a', AppCommand.ai),
          layers.command(',', AppCommand.settings),
          KeyAction(
            '?',
            page ? 'Keys of ${_mode.label.toLowerCase()} mode' : 'These keys',
            layer: page ? _modeKeys : _emptyKeys,
          ),
        ]);
    if (!_ready) {
      return KeyLayer('Menu', <KeyGroup>[go, window(page: false)]);
    }
    return KeyLayer('Menu', <KeyGroup>[
      go,
      KeyGroup(title: 'Page', <KeyAction>[
        KeyAction('i', 'Insert', layer: _insertKeys),
        KeyAction(
          'f',
          'Text',
          layer: layers.text,
          enabled: _textController.hasTarget,
        ),
        KeyAction('d', 'Draw', layer: layers.draw),
        KeyAction('m', 'Formulas', layer: layers.math),
        KeyAction('s', 'Sheets', layer: layers.sheets),
      ]),
      KeyGroup(title: 'Edit', <KeyAction>[
        KeyAction(
          'x',
          'Cut',
          run: () => unawaited(_copySelection(cut: true)),
          enabled: some,
        ),
        KeyAction(
          'c',
          'Copy',
          run: () => unawaited(_copySelection()),
          enabled: some,
        ),
        KeyAction('v', 'Paste', run: () => unawaited(_paste())),
        KeyAction(
          'V',
          'Paste text only',
          run: () => unawaited(_paste(textOnly: true)),
        ),
        KeyAction(
          ModeKey.delete,
          'Delete',
          run: _deleteSelection,
          enabled: some,
        ),
        if (picture is TikzElement)
          KeyAction(
            'T',
            'Edit TikZ source',
            run: () => unawaited(_editTikz(picture.id)),
          ),
        if (picture != null)
          KeyAction(
            'B',
            'Set as background',
            run: () => _controller.setBackground(picture.id, background: true),
          ),
        if (background != null)
          KeyAction(
            'B',
            'Take out of the background',
            run: () =>
                _controller.setBackground(background.id, background: false),
          ),
      ]),
      window(page: true),
    ]);
  }

  KeyLayer _insertKeys() {
    final layers = _layers;
    return KeyLayer.of('Insert', <KeyAction>[
      KeyAction('t', 'Text box', run: _insertTextBox),
      KeyAction('p', 'Picture', run: _commands.onInsertImage),
      KeyAction('d', 'PDF printout', run: _commands.onInsertPdf),
      KeyAction('f', 'Formula', run: _insertFormula),
      KeyAction('l', 'LaTeX…', run: _commands.onInsertLatex),
      layers.command('s', AppCommand.addSheet),
    ]);
  }

  KeyLayer _newKeys() {
    final layers = _layers;
    return KeyLayer.of('New', <KeyAction>[
      layers.command('p', AppCommand.newPage, label: 'Page'),
      layers.command('s', AppCommand.newSubpage, label: 'Subpage'),
      layers.command('S', AppCommand.newSection, label: 'Section'),
      layers.command('N', AppCommand.newNotebook, label: 'Notebook'),
      layers.command('t', AppCommand.newTab, label: 'Tab'),
    ]);
  }

  /// Splitting the window between two pages, and going between them.
  KeyLayer _windowKeys() {
    final layers = _layers;
    return KeyLayer('Window', <KeyGroup>[
      KeyGroup(<KeyAction>[
        layers.command('v', AppCommand.splitSideBySide, label: 'Side by side'),
        layers.command(
          's',
          AppCommand.splitStacked,
          label: 'One above the other',
        ),
        layers.command('q', AppCommand.unsplit, label: 'One page'),
      ]),
      KeyGroup(<KeyAction>[
        layers.command(
          'w',
          AppCommand.otherPane,
          also: <String>[for (final (key, _, _, _) in _directions) key],
        ),
      ]),
    ]);
  }

  KeyLayer _tabKeys() {
    final layers = _layers;
    return KeyLayer.of('Tabs', <KeyAction>[
      layers.command('n', AppCommand.newTab),
      layers.command('x', AppCommand.closeTab),
      layers.command('u', AppCommand.reopenTab),
      layers.command('l', AppCommand.nextTab),
      layers.command('h', AppCommand.previousTab),
    ]);
  }

  // ---------------------------------------------------------- normal mode

  /// Normal mode: moving about, and a letter for each thing to do.
  KeyLayer _normalKeys() {
    final layers = _layers;
    final some = _controller.selection.isNotEmpty;
    return KeyLayer('Normal mode', <KeyGroup>[
      KeyGroup(title: 'Modes', <KeyAction>[
        KeyAction(ModeKey.escape, 'Pick nothing, find nothing', run: _forget),
        KeyAction(
          'i',
          'Type: in the box picked, or a new one',
          run: () => _typeOn(_enterInsert),
          also: const <String>[ModeKey.enter],
        ),
        KeyAction(
          'o',
          'Type in a new box below',
          run: () => _typeOn(_openBelow),
        ),
        KeyAction('d', 'Draw', run: () => _selectTool(_lastInkTool)),
        KeyAction('v', 'Select', run: () => _selectTool(CanvasTool.lasso)),
        layers.command('a', AppCommand.ai, label: 'Ask the AI'),
        KeyAction(ModeKey.space, 'Menu', layer: _menu),
      ]),
      KeyGroup(title: 'Move about', <KeyAction>[
        for (final (key, arrow, label, direction) in _directions)
          KeyAction(
            key,
            'To what is $label',
            run: () => _moveFocus(direction),
            also: <String>[arrow],
          ),
        KeyAction('f', 'Jump to…', run: _startJump),
        KeyAction('m', 'Move what is picked', layer: _moveKeys, enabled: some),
      ]),
      KeyGroup(title: 'Edit', <KeyAction>[
        KeyAction(r'$', 'Formula', run: () => _typeOn(_insertFormula)),
        KeyAction(
          'x',
          'Delete',
          run: _deleteSelection,
          also: const <String>[ModeKey.delete],
          enabled: some,
        ),
        KeyAction(
          'y',
          'Copy',
          run: () => unawaited(_copySelection()),
          enabled: some,
        ),
        KeyAction('p', 'Paste', run: () => unawaited(_paste())),
        KeyAction(
          'P',
          'Paste text only',
          run: () => unawaited(_paste(textOnly: true)),
        ),
        KeyAction(
          'u',
          'Undo',
          run: _controller.undo,
          enabled: _controller.canUndo,
        ),
        KeyAction(
          'U',
          'Redo',
          run: _controller.redo,
          also: const <String>['Ctrl+r'],
          enabled: _controller.canRedo,
        ),
      ]),
      KeyGroup(title: 'Go', <KeyAction>[
        KeyAction('g', 'Go', layer: _goKeys, waits: true),
        KeyAction('G', 'Foot of the page', run: _toFoot),
        layers.command('J', AppCommand.nextPage),
        layers.command('K', AppCommand.previousPage),
        layers.command('H', AppCommand.back),
        layers.command('L', AppCommand.forward),
        layers.command(':', AppCommand.commands, label: 'Commands…'),
        layers.command('/', AppCommand.search),
        KeyAction('n', 'Next page found', run: () => _search.step(1)),
        KeyAction('N', 'Page found before', run: () => _search.step(-1)),
      ]),
      KeyGroup(title: 'View', <KeyAction>[
        KeyAction(
          '+',
          'Zoom in',
          run: _commands.onZoomIn,
          also: const <String>['='],
        ),
        KeyAction('-', 'Zoom out', run: _commands.onZoomOut),
        KeyAction('0', 'Actual size', run: _commands.onActualSize),
        KeyAction('?', 'These keys', layer: _normalKeys),
      ]),
    ]);
  }

  /// After g: going to the top of the page, and to other pages and tabs.
  KeyLayer _goKeys() {
    final layers = _layers;
    return KeyLayer.of('Go', <KeyAction>[
      KeyAction('g', 'Top of the page', run: _toTop),
      layers.command('p', AppCommand.goTo, label: 'A page by name…'),
      layers.command('t', AppCommand.nextTab),
      layers.command('T', AppCommand.previousTab),
      layers.command('j', AppCommand.nextPage),
      layers.command('k', AppCommand.previousPage),
      layers.command('J', AppCommand.nextSection),
      layers.command('K', AppCommand.previousSection),
      layers.command('b', AppCommand.back),
      layers.command('f', AppCommand.forward),
    ]);
  }

  // ------------------------------------------------------------ draw mode

  /// Draw mode: the tools, the palette's first colours by number, and the
  /// width.
  KeyLayer _drawKeys() {
    final layers = _layers;
    final ink = _commands.ink;
    final colours = NotePalette.presets.take(9).toList();
    return KeyLayer('Draw mode', <KeyGroup>[
      layers.draw().groups.first,
      KeyGroup(title: 'Ink', <KeyAction>[
        for (final (index, colour) in colours.indexed)
          KeyAction(
            '${index + 1}',
            colour.name,
            run: () => _commands.changeInk(
              _commands.ink.copyWith(color: colour.color),
            ),
            checked: ink.color == colour.color,
          ),
        ...layers.draw().groups.last.actions,
      ]),
      KeyGroup(title: 'Modes', <KeyAction>[
        KeyAction(ModeKey.escape, 'Back to normal', run: _toNormal),
        KeyAction('v', 'Select', run: () => _selectTool(CanvasTool.lasso)),
        KeyAction(ModeKey.space, 'Menu', layer: _menu),
        KeyAction(
          'u',
          'Undo',
          run: _controller.undo,
          enabled: _controller.canUndo,
        ),
        KeyAction(
          'U',
          'Redo',
          run: _controller.redo,
          also: const <String>['Ctrl+r'],
          enabled: _controller.canRedo,
        ),
        KeyAction('?', 'These keys', layer: _drawKeys),
      ]),
    ]);
  }

  // ---------------------------------------------------------- select mode

  /// Select mode: the lasso, and what to do with what it picks.
  KeyLayer _selectKeys() {
    final some = _controller.selection.isNotEmpty;
    return KeyLayer.of('Select mode', <KeyAction>[
      KeyAction(ModeKey.escape, 'Back to normal', run: _toNormal),
      for (final (key, arrow, label, direction) in _directions)
        KeyAction(
          key,
          'And what is $label',
          run: () => _moveFocus(direction, extend: true),
          also: <String>[arrow],
        ),
      KeyAction('f', 'And jump to…', run: () => _startJump(additive: true)),
      KeyAction('m', 'Move what is picked', layer: _moveKeys, enabled: some),
      KeyAction('a', 'Everything', run: _selectEverything),
      KeyAction(
        'd',
        'Delete',
        run: _deleteSelection,
        also: const <String>['x', ModeKey.delete],
        enabled: some,
      ),
      KeyAction(
        'y',
        'Copy',
        run: () => unawaited(_copySelection()),
        enabled: some,
      ),
      KeyAction(
        'c',
        'Cut',
        run: () => unawaited(_copySelection(cut: true)),
        enabled: some,
      ),
      KeyAction('p', 'Paste', run: () => unawaited(_paste())),
      KeyAction(
        'u',
        'Undo',
        run: _controller.undo,
        enabled: _controller.canUndo,
      ),
      KeyAction(ModeKey.space, 'Menu', layer: _menu),
      KeyAction('?', 'These keys', layer: _selectKeys),
    ]);
  }

  // ------------------------------------------------------- moving about

  /// The keys that move about, the arrow that goes the same way, what
  /// way they go, and that way named.
  static const List<(String, String, String, AxisDirection)> _directions =
      <(String, String, String, AxisDirection)>[
        ('h', ModeKey.left, 'left', AxisDirection.left),
        ('j', ModeKey.down, 'below', AxisDirection.down),
        ('k', ModeKey.up, 'above', AxisDirection.up),
        ('l', ModeKey.right, 'right', AxisDirection.right),
      ];

  static Rect _rectOf(Aabb bounds) =>
      Rect.fromLTRB(bounds.left, bounds.top, bounds.right, bounds.bottom);

  /// Everything on the page the keys can go to: all but the pictures set as
  /// its background, and carets placed with nothing at them.
  List<Placed> get _things => <Placed>[
    for (final element in _controller.document.elements)
      if (!element.locked && !_placed.contains(element.id))
        (id: element.id, bounds: _rectOf(element.frame.bounds)),
  ];

  /// What of the page is in view.
  Rect get _inView {
    final view = _controller.viewport;
    return Rect.fromPoints(
      view.toPage(Offset.zero),
      view.toPage(_controller.viewSize.bottomRight(Offset.zero)),
    );
  }

  /// [page], a rectangle on the page, where it is on the screen, in the
  /// canvas's own coordinates.
  Rect _onScreen(Rect page) {
    final view = _controller.viewport;
    return Rect.fromPoints(
      view.toScreen(page.topLeft),
      view.toScreen(page.bottomRight),
    );
  }

  /// Picks the nearest thing [direction] of what is picked — or, with
  /// nothing picked, the first thing in view — along with what is picked,
  /// with [extend].
  void _moveFocus(AxisDirection direction, {bool extend = false}) {
    final things = _things;
    final from = _controller.selectionBounds;
    final String? to;
    if (from == null) {
      final view = _inView;
      to =
          (firstRead(things.where((thing) => view.overlaps(thing.bounds))) ??
                  firstRead(things))
              ?.id;
    } else {
      final picked = _controller.selection;
      to = nearestTowards(
        things.where((thing) => !picked.contains(thing.id)),
        _rectOf(from),
        direction,
      );
    }
    if (to != null) _go(to, additive: extend);
  }

  /// Picks [id], brings it into view, and draws the eye to it.
  void _go(String id, {bool additive = false}) {
    final element = _controller.elementById(id);
    if (element == null) return;
    _stopEditing(refocusCanvas: false);
    _controller
      ..select(id, additive: additive)
      ..reveal(element.frame.bounds);
    _glide.value = _onScreen(_rectOf(element.frame.bounds));
  }

  /// Puts a label over everything in view, to jump to by typing it.
  void _startJump({bool additive = false}) {
    final view = _inView;
    final targets = <JumpTarget>[
      for (final thing in _things)
        if (view.overlaps(thing.bounds))
          (id: thing.id, rect: _onScreen(thing.bounds)),
    ]..sort((a, b) => compareReading(a.rect, b.rect));
    if (targets.isEmpty) return;
    _jump?.end();
    _update(
      () => _jump = Jump(
        targets: targets,
        onPicked: (id) => _endJump(to: id, additive: additive),
        onDone: _endJump,
      ),
    );
  }

  /// Takes the labels away, having gone [to] what was jumped to, if
  /// anything was.
  void _endJump({String? to, bool additive = false}) {
    _jump?.end();
    _update(() => _jump = null);
    _canvasFocus.requestFocus();
    if (to != null) _go(to, additive: additive);
  }

  /// Moving what is picked, a step at a time or ten.
  KeyLayer _moveKeys() => KeyLayer('Move', <KeyGroup>[
    KeyGroup(title: 'A step', <KeyAction>[
      for (final (key, arrow, label, direction) in _directions)
        KeyAction(
          key,
          label,
          run: () => _nudge(_stepOf(direction)),
          also: <String>[arrow],
          stays: true,
        ),
    ]),
    KeyGroup(title: 'Ten steps', <KeyAction>[
      for (final (key, _, label, direction) in _directions)
        KeyAction(
          key.toUpperCase(),
          label,
          run: () => _nudge(_stepOf(direction) * 10),
          stays: true,
        ),
    ]),
  ]);

  static Offset _stepOf(AxisDirection direction) => switch (direction) {
    AxisDirection.left => const Offset(-1, 0),
    AxisDirection.right => const Offset(1, 0),
    AxisDirection.up => const Offset(0, -1),
    AxisDirection.down => const Offset(0, 1),
  };

  // ------------------------------------------------------------- moving

  SearchSession get _search => ref.read(searchSessionProvider.notifier);

  /// Lets go of what is picked, and of what was searched for: nothing is
  /// marked on the page any longer.
  void _forget() {
    _stopEditing();
    _controller.clearSelection();
    _search.clear();
  }

  /// Back to normal mode: the select tool in hand, nothing typed in.
  void _toNormal() => _selectTool(CanvasTool.select);

  /// Runs [start], which starts typing in a text box, keeping what is
  /// typed meanwhile — the box takes the keyboard only once it is drawn —
  /// to type into it once it is there.
  void _typeOn(VoidCallback start) {
    _endTypeOn?.call(type: true);
    final ahead = TypeAhead();
    late final VoidCallback attached;
    late final Timer unclaimed;
    void finish({required bool type}) {
      _endTypeOn = null;
      unclaimed.cancel();
      _textController.removeListener(attached);
      final typed = ahead.take();
      if (type && typed.isNotEmpty && _textController.isActive) {
        _textController.typeText(typed);
      }
    }

    attached = () {
      if (_textController.isActive) finish(type: true);
    };
    _textController.addListener(attached);
    _endTypeOn = finish;
    // A box that never takes the keyboard does not keep them.
    unclaimed = Timer(
      const Duration(milliseconds: 600),
      () => _endTypeOn?.call(type: true),
    );
    start();
  }

  /// Types in the box picked, if one is — else in a new one in view.
  void _enterInsert() {
    final selected = _controller.selectedElements;
    if (selected.length == 1 && selected.single is TextElement) {
      _controller.setTool(CanvasTool.select);
      _startEditing(selected.single.id);
    } else {
      _insertTextBox();
    }
  }

  /// Types in a new box below what is picked, lined up with it — or in
  /// view, where nothing is.
  void _openBelow() {
    final bounds = _controller.selectionBounds;
    if (bounds == null) {
      _insertTextBox();
      return;
    }
    _stopEditing(refocusCanvas: false);
    _controller.setTool(CanvasTool.select);
    final id = _createTextBox(Offset(bounds.left, bounds.bottom + _gapBelow));
    _startEditing(id);
    final box = _controller.elementById(id);
    if (box != null) _controller.reveal(box.frame.bounds);
  }

  /// How far below what is picked a box opened beneath it starts.
  static const double _gapBelow = 12;

  void _toTop() => _controller.viewport = _controller.viewport.copyWith(
    origin: Offset(_controller.viewport.origin.dx, double.negativeInfinity),
  );

  void _toFoot() {
    final bounds = _controller.contentBounds;
    if (bounds.isEmpty) return;
    _controller.reveal(
      Aabb(bounds.left, bounds.bottom, bounds.left, bounds.bottom),
    );
  }
}

/// Space held down: alone so far; with the pointer pressed, moving the
/// page; or with another key pressed, which went to the menu.
enum _SpaceHeld { alone, withPointer, rolledOver }
