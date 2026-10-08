part of 'text_box_editor.dart';

/// Words spelled wrongly, links, and the menu a right-click opens.
extension _Menu on TextBoxEditorState {
  /// The menu a right-click at [global] opens: what can be done about a
  /// word spelled wrongly there, cutting, copying and pasting, for a
  /// picture or PDF page, setting it as the page's background, and for a
  /// TikZ picture, editing its source.
  ///
  /// A right-click outside the selection first places the caret there, or
  /// picks the object there, as a click would, so the menu acts on what was
  /// clicked.
  Future<void> _showMenu(Offset global) async {
    // A formula being edited is finished first, as a click elsewhere
    // finishes it, and the text laid out again with it typeset, so the
    // words are found, and replaced, in the text as it is kept. A click in
    // its source leaves it open, to copy from.
    final open = _formula;
    final inFormula = open != null && _hitInOpenFormula(global, open) != null;
    if (open != null && !inFormula) {
      finishFormula();
      await WidgetsBinding.instance.endOfFrame;
      if (!mounted) return;
    }
    final hit = inFormula ? null : _hitTest(global);
    if (hit != null && !hit.checkbox && !_selects(hit.position)) {
      if (!widget.isEditing) widget.onStartEditing?.call();
      _focusNode.requestFocus();
      final block = hit.position.block;
      _select(
        hit.embed
            ? RichSelection(RichPosition(block, 0), RichPosition(block, 1))
            : RichSelection.collapsed(hit.position),
      );
    }
    await _menuFor(hit);
  }

  /// The menu a key opens: as a right-click on what is picked, or at the
  /// caret, opens it — what is picked kept picked.
  void _showMenuFromKeys() {
    if (_formula != null) finishFormula();
    final picture =
        !_selection.isCollapsed && _blocks[_selection.start.block].isEmbed;
    unawaited(
      _menuFor(
        _Hit(picture ? _selection.start : _selection.extent, embed: picture),
      ),
    );
  }

  /// The menu for [hit] — what a right-click landed on, or the caret — and
  /// for what is picked.
  Future<void> _menuFor(_Hit? hit) async {
    final misspelled = hit == null ? null : _misspelledAt(hit.position);
    final suggestions = misspelled == null
        ? const <String>[]
        : await widget.proofreader!.suggest(misspelled.spelled);
    final canPaste = await NoteClipboard.read() != null;
    if (!mounted) return;
    final selected = !_selection.isCollapsed;
    final picture = hit != null && hit.embed ? hit.position.block : null;
    final file = picture == null ? null : _fileAt(picture);
    final tikz = picture != null && _blocks[picture].embed?.source != null;
    final table = hit == null
        ? null
        : TextTables.tableAt(_blocks, hit.position.block);
    final link = hit == null ? null : _linkAt(hit.position);
    final paragraphLink = hit == null ? null : _linkTo(hit.position.block);
    await showCommandMenu(context, <List<MenuCommand>>[
      if (misspelled case (:final index, :final word, :final spelled)) ...[
        if (suggestions.isEmpty)
          const <MenuCommand>[MenuCommand('No suggestions', null)]
        else
          <MenuCommand>[
            for (final suggestion in suggestions)
              MenuCommand(
                suggestion,
                () => _replaceWord(index, word, spelled, suggestion),
              ),
          ],
        <MenuCommand>[
          MenuCommand(
            'Add to dictionary',
            () => unawaited(widget.proofreader!.addWord(spelled)),
            icon: AppIcon.spelling,
          ),
          MenuCommand('Ignore', () => widget.proofreader!.ignore(spelled)),
        ],
      ],
      <MenuCommand>[
        MenuCommand(
          'Cut',
          selected ? () => unawaited(_copy(cut: true)) : null,
          shortcut: EditorKey.cut.keys,
          icon: AppIcon.cut,
        ),
        MenuCommand(
          'Copy',
          selected ? () => unawaited(_copy()) : null,
          shortcut: EditorKey.copy.keys,
          icon: AppIcon.copy,
        ),
        MenuCommand(
          'Paste',
          canPaste ? () => unawaited(_paste()) : null,
          shortcut: EditorKey.paste.keys,
          icon: AppIcon.paste,
        ),
        MenuCommand(
          'Paste text only',
          canPaste ? () => unawaited(_paste(textOnly: true)) : null,
          shortcut: EditorKey.pasteText.keys,
          icon: AppIcon.paste,
        ),
      ],
      if (link != null || paragraphLink != null)
        <MenuCommand>[
          if (link != null) ...<MenuCommand>[
            MenuCommand(
              'Open link',
              () => widget.onOpenLink?.call(link),
              icon: AppIcon.link,
            ),
            MenuCommand(
              'Copy link',
              () => unawaited(Clipboard.setData(ClipboardData(text: link))),
              icon: AppIcon.link,
            ),
          ],
          if (paragraphLink != null)
            MenuCommand(
              'Copy link to paragraph',
              () => unawaited(
                Clipboard.setData(ClipboardData(text: paragraphLink)),
              ),
              icon: AppIcon.link,
            ),
        ],
      if (table != null) ..._tableCommands(table, hit!.position.block),
      if (file != null)
        <MenuCommand>[
          MenuCommand(
            'Open file',
            widget.onOpenFile == null ? null : () => widget.onOpenFile!(file),
            icon: AppIcon.folder,
          ),
          MenuCommand(
            'Save a copy…',
            widget.onSaveFile == null ? null : () => widget.onSaveFile!(file),
            icon: AppIcon.export,
          ),
        ]
      else if (picture != null)
        <MenuCommand>[
          if (tikz)
            MenuCommand(
              'Edit TikZ source',
              () => unawaited(_editPicture(picture)),
              icon: AppIcon.latex,
            ),
          if (widget.onEmbedToBackground != null)
            MenuCommand(
              'Set picture as background',
              () => _embedToBackground(picture),
              icon: AppIcon.picture,
            ),
        ],
    ]);
  }

  /// The file block [index] holds, or null if it holds none.
  BlockEmbed? _fileAt(int index) {
    final embed = _blocks[index].embed;
    return embed?.kind == EmbedKind.file ? embed : null;
  }

  /// What can be done to [table] from the cell block [index] is in: adding
  /// rows and columns beside it, removing its row, its column or the whole
  /// table, and fitting dragged columns to their text again.
  List<List<MenuCommand>> _tableCommands(TextTable table, int index) {
    final cell = _blocks[index].cell!;
    void edit(RichEdit Function(List<TextBlock> blocks) change) {
      _focusNode.requestFocus();
      _commit(change(_blocks), EditKind.other);
    }

    final dragged = TextTables.widthsOf(
      _blocks,
      table,
    ).any((width) => width != null);
    return <List<MenuCommand>>[
      <MenuCommand>[
        MenuCommand(
          'Insert row above',
          () => edit((b) => TableEditing.insertRow(b, table, cell.row)),
        ),
        MenuCommand(
          'Insert row below',
          () => edit((b) => TableEditing.insertRow(b, table, cell.row + 1)),
        ),
        MenuCommand(
          'Insert column left',
          () => edit(
            (b) => TableEditing.insertColumn(
              b,
              table,
              cell.column,
              caretRow: cell.row,
            ),
          ),
        ),
        MenuCommand(
          'Insert column right',
          () => edit(
            (b) => TableEditing.insertColumn(
              b,
              table,
              cell.column + 1,
              caretRow: cell.row,
            ),
          ),
        ),
      ],
      <MenuCommand>[
        MenuCommand(
          'Delete row',
          () => edit((b) => TableEditing.deleteRow(b, table, cell.row)),
          icon: AppIcon.bin,
        ),
        MenuCommand(
          'Delete column',
          () => edit(
            (b) => TableEditing.deleteColumn(
              b,
              table,
              cell.column,
              caretRow: cell.row,
            ),
          ),
          icon: AppIcon.bin,
        ),
        MenuCommand(
          'Delete table',
          () => edit((b) => TableEditing.deleteTable(b, table)),
          icon: AppIcon.bin,
        ),
        if (dragged)
          MenuCommand(
            'Fit columns to text',
            () => edit(
              (b) => (
                blocks: TableEditing.fitColumns(b, table),
                selection: _selection,
              ),
            ),
          ),
      ],
    ];
  }

  /// The link on the text at [position], if there is one.
  String? _linkAt(RichPosition position) {
    final block = _blocks[position.block];
    for (final (i, span) in RichTextEditing.runSpans(block).indexed) {
      if (span.start <= position.offset && position.offset < span.end) {
        return block.runs[i].marks.link;
      }
    }
    return null;
  }

  /// A link to paragraph [block] of this box, or null off a page.
  String? _linkTo(int block) {
    final pageId = widget.pageId;
    return pageId == null
        ? null
        : NoteLink.page(
            pageId,
            elementId: widget.element.id,
            block: block,
          ).toString();
  }

  /// Whether the selection takes in [position].
  bool _selects(RichPosition position) =>
      !_selection.isCollapsed &&
      _selection.start <= position &&
      position <= _selection.end;

  /// The word spelled wrongly at [at], if spelling is checked and one is.
  ({int index, WordSpan word, String spelled})? _misspelledAt(RichPosition at) {
    final proofreader = widget.proofreader;
    if (proofreader == null || _blocks[at.block].isEmbed) return null;
    final text = TextBoxEditor.textOf(_blocks[at.block], code: false);
    final word = proofreader
        .misspellingsIn(text)
        .where((word) => word.start <= at.offset && at.offset <= word.end)
        .firstOrNull;
    return word == null
        ? null
        : (
            index: at.block,
            word: word,
            spelled: text.substring(word.start, word.end),
          );
  }

  /// Asks the host to make the object on block [block] part of the page's
  /// background, where it is drawn now.
  void _embedToBackground(int block) {
    final object = _object(block);
    final box = context.findRenderObject();
    if (object == null || box is! RenderBox) return;
    widget.onEmbedToBackground?.call(
      block,
      MatrixUtils.transformRect(
        object.getTransformTo(box),
        Offset.zero & object.size,
      ),
    );
  }

  /// Puts [replacement] in place of [word] in block [index], unless the
  /// text has changed so that [spelled] is no longer there.
  void _replaceWord(
    int index,
    WordSpan word,
    String spelled,
    String replacement,
  ) {
    if (index >= _blocks.length) return;
    final block = _blocks[index];
    final text = TextBoxEditor.textOf(block, code: false);
    if (word.end > text.length ||
        text.substring(word.start, word.end) != spelled) {
      return;
    }
    if (!widget.isEditing) widget.onStartEditing?.call();
    _commit(
      RichTextEditing.insertText(
        _blocks,
        RichSelection(
          RichPosition(index, word.start),
          RichPosition(index, word.end),
        ),
        replacement,
        marks: RichTextEditing.marksAt(block, word.start + 1),
      ),
      EditKind.other,
    );
  }
}
