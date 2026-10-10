part of 'page_editor.dart';

/// Files, pictures and text dragged onto the page from outside the app.
extension _Drop on _PageEditorState {
  /// [child], taking what is dropped on it while the page shows and nothing
  /// is open over it, and saying where it will go while it is held there.
  Widget _dropTarget(Widget child) => DropTarget(
    enable: _pageShowing && (ModalRoute.of(context)?.isCurrent ?? true),
    onDragEntered: (details) => _dropHover.value = details.localPosition,
    onDragUpdated: (details) => _dropHover.value = details.localPosition,
    onDragExited: (_) => _dropHover.value = null,
    onDragDone: (details) {
      _dropHover.value = null;
      unawaited(
        _drop(
          paths: <String>[for (final file in details.files) file.path],
          text: details.rawText,
          at: details.localPosition,
        ),
      );
    },
    child: Stack(
      children: <Widget>[
        Positioned.fill(child: child),
        ValueListenableBuilder<Offset?>(
          valueListenable: _dropHover,
          builder: (context, at, _) => at == null
              ? const SizedBox.shrink()
              : Positioned(
                  left: at.dx + 14,
                  top: at.dy + 14,
                  child: const IgnorePointer(child: _DropHint()),
                ),
        ),
      ],
    ),
  );

  /// Puts what was dropped at [at], in the canvas's pixels: each of
  /// [paths], or else [text], dragged by itself. Into the text box being
  /// edited, if it was dropped on it; else onto the page, one thing under
  /// another — pictures and GIFs as themselves, a PDF's pages where it is
  /// asked they go, text and LaTeX in a box, notes from another program as
  /// an import of them, and any other file attached.
  Future<void> _drop({
    required List<String> paths,
    required String? text,
    required Offset at,
  }) async {
    final store = _store;
    if (store == null || !_ready) return;
    if (paths.isEmpty && (text == null || text.trim().isEmpty)) {
      _showMessage('What was dropped could not be read.');
      return;
    }
    final failures = <String>[];
    final dropped = await readDropped(
      store,
      paths: _isDraggedText(paths, text) ? const <String>[] : paths,
      text: text,
      client: ref.read(httpClientProvider),
      failures: failures,
    );
    if (!mounted) return;
    if (failures.isNotEmpty) {
      _showMessage('Could not bring in ${failures.join('; ')}.');
    }
    if (dropped.isEmpty) return;

    final point = _controller.viewport.toPage(at);
    final editingId = _editingId;
    final editing = editingId == null
        ? null
        : _controller.elementById(editingId);
    final intoBox =
        _textController.isActive &&
        editing is TextElement &&
        !TextBoxEditor.isEmpty(editing.blocks) &&
        editing.bounds.containsPoint(point.dx, point.dy);
    if (!intoBox) _stopEditing();

    // The first where it was let go — a picture in the middle there, text
    // starting there — and each after under the last, its top there.
    Offset? under;
    for (final thing in dropped) {
      if (!mounted) return;
      final top = under;
      switch (thing) {
        case DroppedMedia(:final items, :final printout):
          await _placeMedia(
            items,
            printout: printout,
            at: top ?? point,
            fromTop: top != null,
          );
        case DroppedText(:final blocks) when intoBox:
          _textController.insertBlocks(blocks);
        case DroppedText(:final blocks):
          _pasteBox(blocks, at: top == null ? point : top + _textOrigin);
        case DroppedFile(:final embed) when intoBox:
          _textController.insertEmbeds(<BlockEmbed>[embed]);
        case DroppedFile(:final embed):
          final start = top == null ? point : top + _textOrigin;
          final box = embed.toElement(
            frame: TextElement.frameAround(
              Frame(
                // Its name starting where a box's text would.
                x: start.dx,
                y: start.dy - _textOrigin.dy + TextBoxEditor.grabBand,
                width: embed.width,
                height: embed.height,
              ),
            ),
            now: DateTime.now().millisecondsSinceEpoch,
          );
          _controller
            ..setTool(CanvasTool.select)
            ..addElement(box)
            ..select(box.id);
        case DroppedNotes(:final importer, :final paths):
          await importNotes(context, importer, dropped: paths);
          continue;
      }
      if (intoBox) continue;
      // Laid out, a box is as tall as its text.
      await WidgetsBinding.instance.endOfFrame;
      final placed = NoteElement.boundsOf(_controller.selectedElements);
      if (!placed.isEmpty) under = Offset(point.dx, placed.bottom + 24);
    }
  }

  /// Whether what was dragged is text, rather than files or addresses:
  /// some line of it is not an address, and none of [paths] a file here —
  /// a line of text naming a website is not that website.
  static bool _isDraggedText(List<String> paths, String? text) {
    if (text == null) return false;
    bool isAddress(String line) => Uri.tryParse(line)?.hasScheme ?? false;
    final lines = <String>[
      for (final line in text.split('\n'))
        if (line.trim().isNotEmpty) line.trim(),
    ];
    return lines.any((line) => !isAddress(line)) &&
        paths.every(
          (path) => path.startsWith('http://') || path.startsWith('https://'),
        );
  }
}

/// Said beside the pointer while something from outside the app is held
/// over the page: it goes where it is let go.
class _DropHint extends StatelessWidget {
  const _DropHint();

  @override
  Widget build(BuildContext context) => Glass(
    borderRadius: Corners.controlRadius,
    child: Padding(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: <Widget>[
          const Drop.dot(),
          const SizedBox(width: 8),
          Text(
            'Let go to put it here',
            style: TextStyle(fontSize: 12.5, color: context.tones.text),
          ),
        ],
      ),
    ),
  );
}
