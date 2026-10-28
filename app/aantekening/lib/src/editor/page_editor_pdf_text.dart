part of 'page_editor.dart';

/// Text picked on a PDF page: of the page [elementId], the characters from
/// [from] up to [to].
typedef PdfTextPick = ({String elementId, int from, int to});

/// Selecting the text of the PDF pages on the page, as a reader selects
/// it, copying it, and following their links.
extension _PdfText on _PageEditorState {
  /// The PDF page a press at [page] lands on, beneath [hit]: the one
  /// pressed, or one set as the background with nothing over it.
  PdfElement? _pdfUnder(Offset page, NoteElement? hit) => switch (hit) {
    final PdfElement pdf => pdf,
    null => switch (_controller.backgroundAt(page)) {
      final PdfElement pdf => pdf,
      _ => null,
    },
    _ => null,
  };

  /// The text of [pdf], if it has been read; else it is read, to be there
  /// the next time it is asked for.
  PdfPageWords? _wordsOf(PdfElement pdf) => PdfWordsCache.shared.of(
    pdf.assetId,
    pdf.pageIndex,
    open: () => ref.read(pdfDocumentProvider(pdf.assetId).future),
  );

  /// Where [page] lies on [pdf], in shares of it from its top-left corner,
  /// however it is turned.
  Offset _onPdf(PdfElement pdf, Offset page) {
    final local = pdf.frame.pageToLocal(page.dx, page.dy);
    return Offset(local.x / pdf.frame.width, local.y / pdf.frame.height);
  }

  bool _pdfSelectsAt(Offset page, NoteElement? hit) {
    final pdf = _pdfUnder(page, hit);
    if (pdf == null) return false;
    return _wordsOf(pdf)?.lineAt(_onPdf(pdf, page)) != null;
  }

  /// Picks the text of the PDF page [from] lies on, from there to [to],
  /// [to] taken to the nearest of its text however far off it is.
  void _selectPdf(Offset from, Offset to) {
    final pdf = _pdfUnder(from, _controller.hitTest(from));
    final words = pdf == null ? null : _wordsOf(pdf);
    if (pdf == null || words == null) return;
    final start = words.caretAt(_onPdf(pdf, from));
    final end = words.caretAt(_onPdf(pdf, to));
    _pickPdf((
      elementId: pdf.id,
      from: math.min(start, end),
      to: math.max(start, end),
    ));
  }

  void _selectPdfWord(Offset page) {
    final pdf = _pdfUnder(page, _controller.hitTest(page));
    final words = pdf == null ? null : _wordsOf(pdf);
    if (pdf == null || words == null) return;
    final (from, to) = words.wordAt(_onPdf(pdf, page));
    _pickPdf((elementId: pdf.id, from: from, to: to));
  }

  /// Picks [pick], typing anywhere ending as it does: what is copied is
  /// then the text picked.
  void _pickPdf(PdfTextPick pick) {
    if (_editingId != null) _stopEditing();
    _pdfPick.value = pick.to > pick.from ? pick : null;
  }

  /// The text picked on a PDF page, if any.
  String? get _pdfPickedText {
    final pick = _pdfPick.value;
    final pdf = pick == null ? null : _controller.elementById(pick.elementId);
    if (pick == null || pdf is! PdfElement) return null;
    return _wordsOf(pdf)?.textOf(pick.from, pick.to);
  }

  /// The link on the PDF page at [page], beneath [hit], if any leads
  /// anywhere.
  PdfPageLink? _pdfLinkAt(Offset page, NoteElement? hit) {
    final pdf = _pdfUnder(page, hit);
    final link = pdf == null ? null : _wordsOf(pdf)?.linkAt(_onPdf(pdf, page));
    return link != null && (link.url != null || link.page != null)
        ? link
        : null;
  }

  /// Opens the link at [page]: a web address in the browser, and a page
  /// of the same PDF where it lies on this page, brought into view.
  void _openPdfLink(Offset page) {
    final link = _pdfLinkAt(page, _controller.hitTest(page));
    final pdf = _pdfUnder(page, _controller.hitTest(page));
    if (link == null || pdf == null) return;
    if (link.url case final url?) {
      unawaited(ref.read(noteLinksProvider).open('$url'));
      return;
    }
    final target = _controller.document.elements
        .whereType<PdfElement>()
        .where((each) => each.assetId == pdf.assetId)
        .where((each) => each.pageIndex == link.page)
        .firstOrNull;
    if (target == null) {
      _showMessage(
        'Page ${link.page! + 1} of this PDF is not on this page of notes.',
      );
      return;
    }
    _controller.reveal(target.bounds);
  }

  /// [page] — the widget of the PDF page [pdf] — with the text picked on
  /// it lit.
  Widget _withPdfPick(PdfElement pdf, Widget page) => Stack(
    fit: StackFit.expand,
    children: <Widget>[
      page,
      IgnorePointer(
        child: ValueListenableBuilder<PdfTextPick?>(
          valueListenable: _pdfPick,
          builder: (context, pick, _) {
            final words = pick?.elementId == pdf.id ? _wordsOf(pdf) : null;
            if (pick == null || words == null) return const SizedBox.shrink();
            return CustomPaint(
              painter: _PdfPickPainter(
                words.boxesOf(pick.from, pick.to),
                context.tones.paperSelection,
              ),
            );
          },
        ),
      ),
    ],
  );
}

/// The text of the PDF pages on the page, for the canvas to select by
/// dragging over it with the select tool, and to follow the links of.
class _PdfTextOnPage implements CanvasText {
  _PdfTextOnPage(this._editor);

  final _PageEditorState _editor;

  @override
  bool selectsAt(Offset page, NoteElement? hit) =>
      _editor._pdfSelectsAt(page, hit);

  @override
  void select(Offset from, Offset to) => _editor._selectPdf(from, to);

  @override
  void selectWord(Offset page) => _editor._selectPdfWord(page);

  @override
  bool linkAt(Offset page, NoteElement? hit) =>
      _editor._pdfLinkAt(page, hit) != null;

  @override
  void openLink(Offset page) => _editor._openPdfLink(page);
}

/// Lights [boxes], in shares of what it paints, with [color].
class _PdfPickPainter extends CustomPainter {
  const _PdfPickPainter(this.boxes, this.color);

  final List<Rect> boxes;
  final Color color;

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()..color = color;
    for (final box in boxes) {
      canvas.drawRect(
        Rect.fromLTRB(
          box.left * size.width,
          box.top * size.height,
          box.right * size.width,
          box.bottom * size.height,
        ),
        paint,
      );
    }
  }

  @override
  bool shouldRepaint(_PdfPickPainter old) =>
      !listEquals(old.boxes, boxes) || old.color != color;
}
