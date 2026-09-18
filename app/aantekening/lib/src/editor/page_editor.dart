/// The page editor: canvas, toolbar and autosave.
library;

import 'dart:async';

import 'package:aantekening_canvas/aantekening_canvas.dart';
import 'package:aantekening_core/aantekening_core.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../providers.dart';
import 'editor_toolbar.dart';
import 'element_views.dart';
import 'rich_text_view.dart';

/// Edits one page.
///
/// The editor owns the [CanvasController] directly rather than holding it in a
/// provider: its lifetime is exactly this widget's, and tying it to the widget
/// makes switching pages a plain state change with a guaranteed final save.
class PageEditor extends ConsumerStatefulWidget {
  const PageEditor({required this.pageId, super.key});

  final String pageId;

  @override
  ConsumerState<PageEditor> createState() => _PageEditorState();
}

class _PageEditorState extends ConsumerState<PageEditor> {
  /// How long to wait after the last edit before writing to disk.
  ///
  /// Long enough that a burst of typing or a drawn stroke is one write, short
  /// enough that no meaningful work is at risk if the app stops.
  static const Duration _autosaveDelay = Duration(milliseconds: 700);

  /// Default size for a text box or formula dropped on the canvas.
  static const Size _newTextBoxSize = Size(320, 90);
  static const Size _newMathBoxSize = Size(260, 70);

  final CanvasController _controller = CanvasController();

  Timer? _autosave;
  String? _editingElementId;
  bool _loading = true;
  bool _saving = false;
  Object? _error;

  @override
  void initState() {
    super.initState();
    _controller.addListener(_onCanvasChanged);
    unawaited(_load());
  }

  @override
  void didUpdateWidget(PageEditor old) {
    super.didUpdateWidget(old);
    if (old.pageId != widget.pageId) {
      // Leaving a page must never lose what is on it, so the pending save is
      // flushed before the new one is loaded.
      unawaited(_flushThenLoad(old.pageId));
    }
  }

  @override
  void dispose() {
    _autosave?.cancel();
    _controller.removeListener(_onCanvasChanged);
    if (_controller.isDirty) {
      unawaited(_persist(widget.pageId, _controller.document));
    }
    _controller.dispose();
    super.dispose();
  }

  // ------------------------------------------------------------ load / save

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final store = await ref.read(storeProvider.future);
      final document = await store.pages.loadDocument(widget.pageId);
      if (!mounted) return;
      _controller.loadDocument(
        document ?? PageDocument.empty(id: widget.pageId),
      );
      setState(() => _loading = false);
    } on Object catch (error) {
      if (!mounted) return;
      setState(() {
        _error = error;
        _loading = false;
      });
    }
  }

  Future<void> _flushThenLoad(String previousPageId) async {
    _autosave?.cancel();
    if (_controller.isDirty) {
      await _persist(previousPageId, _controller.document);
    }
    _editingElementId = null;
    await _load();
  }

  void _onCanvasChanged() {
    if (mounted) setState(() {});
    if (!_controller.isDirty) return;

    _autosave?.cancel();
    _autosave = Timer(_autosaveDelay, () {
      unawaited(_persist(widget.pageId, _controller.document));
    });
  }

  Future<void> _persist(String pageId, PageDocument document) async {
    if (mounted) setState(() => _saving = true);
    try {
      final store = await ref.read(storeProvider.future);
      await store.pages.saveDocument(pageId, document);
      if (pageId == widget.pageId && mounted) _controller.markSaved();
      // The page list shows titles and previews derived from the body, so it
      // has to be refreshed once the save lands.
      ref.read(libraryRevisionProvider.notifier).bump();
    } on Object catch (error) {
      if (mounted) setState(() => _error = error);
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  // -------------------------------------------------------------- authoring

  void _createElementAt(CanvasTool tool, Offset page) {
    final now = DateTime.now().millisecondsSinceEpoch;
    final id = Ulid.generate();

    switch (tool) {
      case CanvasTool.text:
        _controller.addElement(
          TextElement(
            id: id,
            frame: Frame(
              x: page.dx,
              y: page.dy,
              width: _newTextBoxSize.width,
              height: _newTextBoxSize.height,
            ),
            createdAt: now,
            updatedAt: now,
            blocks: <TextBlock>[TextBlock.plain('')],
          ),
        );
        setState(() => _editingElementId = id);
        _controller.setTool(CanvasTool.select);
      case CanvasTool.math:
        _controller.addElement(
          MathElement(
            id: id,
            frame: Frame(
              x: page.dx,
              y: page.dy,
              width: _newMathBoxSize.width,
              height: _newMathBoxSize.height,
            ),
            createdAt: now,
            updatedAt: now,
            source: '',
          ),
        );
        unawaited(_editFormula(id));
        _controller.setTool(CanvasTool.select);
      case CanvasTool.select:
      case CanvasTool.pan:
      case CanvasTool.draw:
      case CanvasTool.eraser:
        break;
    }
  }

  void _onElementDoubleTap(NoteElement element) {
    switch (element) {
      case TextElement():
        setState(() => _editingElementId = element.id);
      case MathElement():
        unawaited(_editFormula(element.id));
      case _:
        break;
    }
  }

  void _onTextChanged(String elementId, String text) {
    final element = _controller.document.elementById(elementId);
    if (element is! TextElement) return;
    _controller.replaceElement(
      element.copyWith(
        blocks: applyPlainText(element.blocks, text),
        updatedAt: DateTime.now().millisecondsSinceEpoch,
      ),
      // One undo step per editing session rather than one per keystroke.
      recordUndo: false,
    );
  }

  Future<void> _editFormula(String elementId) async {
    final element = _controller.document.elementById(elementId);
    if (element is! MathElement) return;

    final edited = await showDialog<MathElement>(
      context: context,
      builder: (context) => _FormulaDialog(element: element),
    );
    if (edited == null || !mounted) return;
    _controller.replaceElement(edited);
  }

  // ------------------------------------------------------------- shortcuts

  Map<ShortcutActivator, VoidCallback> get _shortcuts =>
      <ShortcutActivator, VoidCallback>{
        const SingleActivator(LogicalKeyboardKey.keyZ, control: true):
            _controller.undo,
        const SingleActivator(
          LogicalKeyboardKey.keyZ,
          control: true,
          shift: true,
        ): _controller.redo,
        const SingleActivator(LogicalKeyboardKey.keyY, control: true):
            _controller.redo,
        const SingleActivator(LogicalKeyboardKey.delete):
            _controller.deleteSelection,
        const SingleActivator(LogicalKeyboardKey.backspace):
            _controller.deleteSelection,
        const SingleActivator(LogicalKeyboardKey.escape): () =>
            setState(() => _editingElementId = null),
        const SingleActivator(LogicalKeyboardKey.keyV): () =>
            _controller.setTool(CanvasTool.select),
        const SingleActivator(LogicalKeyboardKey.keyH): () =>
            _controller.setTool(CanvasTool.pan),
        const SingleActivator(LogicalKeyboardKey.keyP): () =>
            _controller.setTool(CanvasTool.draw),
        const SingleActivator(LogicalKeyboardKey.keyE): () =>
            _controller.setTool(CanvasTool.eraser),
        const SingleActivator(LogicalKeyboardKey.keyT): () =>
            _controller.setTool(CanvasTool.text),
        const SingleActivator(LogicalKeyboardKey.keyM): () =>
            _controller.setTool(CanvasTool.math),
        const SingleActivator(LogicalKeyboardKey.keyS, control: true): () =>
            unawaited(_persist(widget.pageId, _controller.document)),
      };

  // ----------------------------------------------------------------- build

  @override
  Widget build(BuildContext context) {
    if (_loading) {
      return const Center(child: CircularProgressIndicator());
    }

    return Column(
      children: <Widget>[
        EditorToolbar(
          controller: _controller,
          isSaving: _saving,
          onZoomToFit: () => _controller.zoomToFit(_canvasSize(context)),
          onResetZoom: () => _controller.resetZoom(_canvasSize(context)),
        ),
        if (_error != null) _ErrorBanner(error: _error!),
        Expanded(
          child: CallbackShortcuts(
            bindings: _shortcuts,
            child: Focus(
              autofocus: true,
              // Typing into a text box must not be intercepted by the
              // single-letter tool shortcuts.
              skipTraversal: true,
              descendantsAreFocusable: true,
              child: InfiniteCanvas(
                controller: _controller,
                onCreate: _createElementAt,
                onElementDoubleTap: _onElementDoubleTap,
                elementBuilder: (context, element) => CanvasElementView(
                  element: element,
                  isEditing: element.id == _editingElementId,
                  onTextChanged: (text) => _onTextChanged(element.id, text),
                  onEditingFinished: () {
                    if (_editingElementId == element.id) {
                      setState(() => _editingElementId = null);
                    }
                  },
                ),
              ),
            ),
          ),
        ),
      ],
    );
  }

  Size _canvasSize(BuildContext context) {
    final box = context.findRenderObject();
    return box is RenderBox ? box.size : const Size(1024, 768);
  }
}

/// Edits a formula's source and previews the result as it is typed.
class _FormulaDialog extends StatefulWidget {
  const _FormulaDialog({required this.element});

  final MathElement element;

  @override
  State<_FormulaDialog> createState() => _FormulaDialogState();
}

class _FormulaDialogState extends State<_FormulaDialog> {
  late final TextEditingController _source = TextEditingController(
    text: widget.element.source,
  );
  late MathMode _mode = widget.element.mode;

  @override
  void dispose() {
    _source.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;

    return AlertDialog(
      title: const Text('Formula'),
      content: SizedBox(
        width: 520,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: <Widget>[
            SegmentedButton<MathMode>(
              segments: const <ButtonSegment<MathMode>>[
                ButtonSegment<MathMode>(
                  value: MathMode.linear,
                  label: Text('Simple'),
                  icon: Icon(Icons.keyboard_rounded, size: 15),
                ),
                ButtonSegment<MathMode>(
                  value: MathMode.latex,
                  label: Text('LaTeX'),
                  icon: Icon(Icons.code_rounded, size: 15),
                ),
              ],
              selected: <MathMode>{_mode},
              onSelectionChanged: (selection) =>
                  setState(() => _mode = selection.first),
              showSelectedIcon: false,
            ),
            const SizedBox(height: 12),
            TextField(
              controller: _source,
              autofocus: true,
              maxLines: 3,
              style: const TextStyle(fontFamily: 'monospace', fontSize: 13),
              decoration: InputDecoration(
                hintText: _mode == MathMode.linear
                    ? 'e.g.  sum_(i=1)^n i^2 = n(n+1)(2n+1)/6'
                    : r'e.g.  \sum_{i=1}^{n} i^2',
              ),
              onChanged: (_) => setState(() {}),
            ),
            const SizedBox(height: 16),
            Container(
              constraints: const BoxConstraints(minHeight: 72),
              alignment: Alignment.center,
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: scheme.surfaceContainerHighest.withValues(alpha: 0.4),
                borderRadius: BorderRadius.circular(8),
              ),
              child: SingleChildScrollView(
                scrollDirection: Axis.horizontal,
                child: CanvasElementView(
                  element: widget.element.copyWith(
                    source: _source.text,
                    mode: _mode,
                  ),
                  isEditing: false,
                ),
              ),
            ),
          ],
        ),
      ),
      actions: <Widget>[
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('Cancel'),
        ),
        FilledButton(
          onPressed: () => Navigator.of(context).pop(
            widget.element.copyWith(
              source: _source.text,
              mode: _mode,
              updatedAt: DateTime.now().millisecondsSinceEpoch,
            ),
          ),
          child: const Text('Apply'),
        ),
      ],
    );
  }
}

class _ErrorBanner extends StatelessWidget {
  const _ErrorBanner({required this.error});

  final Object error;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Container(
      width: double.infinity,
      color: scheme.errorContainer,
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
      child: Text(
        '$error',
        style: TextStyle(fontSize: 12, color: scheme.onErrorContainer),
      ),
    );
  }
}
