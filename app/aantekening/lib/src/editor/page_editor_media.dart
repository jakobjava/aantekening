part of 'page_editor.dart';

/// Pictures, PDFs and files: brought in, placed, and set as the background.
extension _Media on _PageEditorState {
  /// The widest a free-standing picture or PDF page is placed.
  static const double _defaultMediaWidth = 816;

  /// Inserts pictures or PDF pages: into the text box being edited, at its
  /// caret, or onto the canvas in view if no box is being edited.
  Future<void> _insertMedia(MediaKind kind) async {
    final store = _store;
    if (store == null) return;
    final List<BlockEmbed> items;
    try {
      items = await MediaImport.pickAndImport(store, kind);
    } on Object catch (error) {
      _showMessage('Could not import: $error');
      return;
    }
    if (items.isEmpty || !mounted) return;
    await _placeMedia(items, printout: kind == MediaKind.pdf);
  }

  /// Places pictures or, [printout], a PDF's pages: into the text box being
  /// edited, at its caret, or onto the page — the first in the middle at
  /// [at], a point on it, or with its top there, [fromTop]; or else in the
  /// middle of the view — asking first where a printout goes.
  Future<void> _placeMedia(
    List<BlockEmbed> items, {
    required bool printout,
    Offset? at,
    bool fromTop = false,
  }) async {
    // At a bare caret the pictures go onto the paper where the caret is, as
    // in OneNote; in a box with text they go into the box.
    final editingId = _editingId;
    final editing = editingId == null
        ? null
        : _controller.elementById(editingId);
    final atBareCaret =
        editing is TextElement && TextBoxEditor.isEmpty(editing.blocks);
    if (_textController.isActive && !atBareCaret) {
      _textController.insertEmbeds(items);
      return;
    }

    final sheets = _controller.document.canvas.sheetsShown;
    if (printout) {
      final place = await choosePrintoutPlace(
        context,
        pages: items.length,
        places: <PrintoutPlace>[
          if (sheets != null) PrintoutPlace.newSheets,
          PrintoutPlace.here,
          PrintoutPlace.newPage,
        ],
      );
      if (place == null || !mounted) return;
      switch (place) {
        case PrintoutPlace.newPage:
          await _printAsNewPage(items);
          return;
        case PrintoutPlace.newSheets || PrintoutPlace.here when sheets != null:
          _printOnSheets(
            items,
            sheets,
            onNew: place == PrintoutPlace.newSheets,
            at: at == null ? null : sheets.sheetAt(at.dy),
          );
          return;
        case PrintoutPlace.newSheets || PrintoutPlace.here:
          // On one paper: down the page, as a picture goes.
          break;
      }
    }

    final width = _controller.document.canvas.paperWidth ?? _defaultMediaWidth;
    final center = at ?? _controller.viewCenter;
    // Dropped, the first lies in the middle under the pointer.
    var y = at == null
        ? center.dy - 120
        : fromTop
        ? at.dy
        : at.dy -
              math.min(items.first.width, width) / items.first.aspectRatio / 2;
    if (editing != null && atBareCaret) {
      y = editing.frame.y + TextBoxEditor.grabBand;
      _stopEditing();
    }
    final now = DateTime.now().millisecondsSinceEpoch;
    final elements = <NoteElement>[];
    for (final item in items) {
      // No wider than the paper, keeping its proportions.
      final itemWidth = math.min(item.width, width);
      final itemHeight = itemWidth / item.aspectRatio;
      final element = item.toElement(
        frame: Frame(
          x: editing != null && atBareCaret
              ? editing.frame.x + TextBoxEditor.padding.left
              : center.dx - itemWidth / 2,
          y: y,
          width: itemWidth,
          height: itemHeight,
        ),
        now: now,
      );
      elements.add(element);
      y += itemHeight + 24;
    }
    _controller
      ..setTool(CanvasTool.select)
      ..addElements(elements)
      ..selectAll(elements.map((element) => element.id));
  }

  /// [printout]'s pages, each on a sheet of its own — new sheets after the
  /// one [at], or in view, [onNew], or else the sheets from that one on —
  /// as large as the sheet takes it, in its middle, to be written on.
  void _printOnSheets(
    List<BlockEmbed> printout,
    Sheets sheets, {
    required bool onNew,
    int? at,
  }) {
    final first = (at ?? _controller.currentSheet) + (onNew ? 1 : 0);
    final blank = <SheetTemplate>[
      for (final _ in printout) SheetTemplate.blank,
    ];
    final turned = <SheetOrientation>[
      for (final page in printout) _turnedFor(page),
    ];
    // On sheets of their own, they are what the sheets are printed with,
    // each turned as its page is.
    final placed = _onSheets(
      printout,
      onNew ? sheets.inserting(first, blank, turned) : sheets,
      first,
      background: onNew,
    );
    _controller.setTool(CanvasTool.select);
    if (onNew) {
      _controller.insertSheets(
        first,
        blank,
        orientations: turned,
        onThem: placed,
      );
    } else {
      // Sheets enough to lie on are added as they are needed.
      _controller
        ..addElements(placed)
        ..selectAll(placed.map((element) => element.id));
    }
    _controller.reveal(
      (_controller.document.canvas.sheetsShown ?? sheets).bandOf(first),
    );
  }

  /// Which way up a sheet for [page] of a printout is turned: as it is.
  static SheetOrientation _turnedFor(BlockEmbed page) => page.aspectRatio > 1
      ? SheetOrientation.landscape
      : SheetOrientation.portrait;

  /// [printout]'s pages on the sheets from [first] on, each as large as its
  /// sheet takes it, in its middle: set as their background, to be written
  /// over, if [background].
  static List<NoteElement> _onSheets(
    List<BlockEmbed> printout,
    Sheets sheets,
    int first, {
    required bool background,
  }) {
    final now = DateTime.now().millisecondsSinceEpoch;
    NoteElement placed(int sheet, BlockEmbed page) {
      final element = page.toElement(
        frame: _onSheet(page.aspectRatio, sheets, sheet),
        now: now,
      );
      return background ? element.withLocked(true) : element;
    }

    return <NoteElement>[
      for (final (i, page) in printout.indexed) placed(first + i, page),
    ];
  }

  /// [printout] as a page of its own, beside this one and named after its
  /// file: shown as pages, an A4 sheet turned as the page is for one to
  /// each of its pages, set as its background. A book, say, to read and
  /// write in.
  Future<void> _printAsNewPage(List<BlockEmbed> printout) async {
    final store = _store;
    final pageId = widget.pageId;
    if (store == null || pageId == null || printout.isEmpty) return;
    final file = await store.assets.find(printout.first.assetId);
    final sheets = Sheets(
      templates: <SheetTemplate>[for (final _ in printout) SheetTemplate.blank],
      orientations: <SheetOrientation>[
        for (final page in printout) _turnedFor(page),
      ],
    );
    await ref
        .read(libraryActionsProvider)
        .createPageHolding(
          besidePageId: pageId,
          title: p.basenameWithoutExtension(file?.originalName ?? 'Printout'),
          document: (id) {
            var document = PageDocument(
              id: id,
              canvas: CanvasSettings(layout: NoteLayout.pages, sheets: sheets),
            );
            for (final element in _onSheets(
              printout,
              sheets,
              0,
              background: true,
            )) {
              document = document.withElementAdded(element);
            }
            return document;
          },
        );
  }

  /// Where something [aspectRatio] wide to its height lies on [sheet], as
  /// large as the sheet takes it, in its middle.
  static Frame _onSheet(double aspectRatio, Sheets sheets, int sheet) {
    final band = sheets.bandOf(sheet);
    var width = band.width;
    var height = width / aspectRatio;
    if (height > band.height) {
      height = band.height;
      width = height * aspectRatio;
    }
    return Frame(
      x: (band.width - width) / 2,
      y: band.top + (band.height - height) / 2,
      width: width,
      height: height,
    );
  }

  void _showMessage(String message) {
    if (!mounted) return;
    ScaffoldMessenger.maybeOf(context)?.showMessage(message);
  }
}
