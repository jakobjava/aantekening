/// Widgets for the non-ink elements on a page.
library;

import 'package:aantekening_core/aantekening_core.dart';
import 'package:aantekening_math/aantekening_math.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../providers.dart';
import 'rich_text_view.dart';

/// Renders one element of a page.
///
/// Text, maths, images and tables are real widgets rather than painted output,
/// so they can hold focus, be selected with the keyboard, and reuse the
/// framework's text and layout engines. Ink is painted by the canvas instead,
/// where the sample counts make widgets the wrong tool.
class CanvasElementView extends ConsumerWidget {
  const CanvasElementView({
    required this.element,
    required this.isEditing,
    super.key,
    this.onTextChanged,
    this.onEditingFinished,
  });

  final NoteElement element;
  final bool isEditing;
  final ValueChanged<String>? onTextChanged;
  final VoidCallback? onEditingFinished;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return switch (element) {
      TextElement(:final blocks) => _TextBox(
        blocks: blocks,
        isEditing: isEditing,
        onChanged: onTextChanged,
        onFinished: onEditingFinished,
      ),
      MathElement() => _MathBox(element: element as MathElement),
      ImageElement(:final assetId, :final fit) => _ImageBox(
        assetId: assetId,
        fit: fit,
      ),
      PdfElement() => _PdfBox(element: element as PdfElement),
      TableElement() => _TableBox(element: element as TableElement),
      // Groups have no appearance of their own; their children draw themselves.
      GroupElement() => const SizedBox.shrink(),
      InkElement() => const SizedBox.shrink(),
    };
  }
}

/// A moveable text container.
class _TextBox extends StatefulWidget {
  const _TextBox({
    required this.blocks,
    required this.isEditing,
    this.onChanged,
    this.onFinished,
  });

  final List<TextBlock> blocks;
  final bool isEditing;
  final ValueChanged<String>? onChanged;
  final VoidCallback? onFinished;

  @override
  State<_TextBox> createState() => _TextBoxState();
}

class _TextBoxState extends State<_TextBox> {
  late final TextEditingController _controller = TextEditingController(
    text: plainTextOf(widget.blocks),
  );
  final FocusNode _focus = FocusNode();

  @override
  void didUpdateWidget(_TextBox old) {
    super.didUpdateWidget(old);
    if (widget.isEditing && !old.isEditing) {
      _controller.text = plainTextOf(widget.blocks);
      _focus.requestFocus();
    }
  }

  @override
  void dispose() {
    _controller.dispose();
    _focus.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;

    if (!widget.isEditing) {
      return Align(
        alignment: Alignment.topLeft,
        child: Padding(
          padding: const EdgeInsets.all(4),
          child: widget.blocks.isEmpty
              ? Text(
                  'Empty text box',
                  style: TextStyle(
                    fontSize: 13,
                    fontStyle: FontStyle.italic,
                    color: scheme.onSurfaceVariant,
                  ),
                )
              : RichTextBlocks(blocks: widget.blocks),
        ),
      );
    }

    return DecoratedBox(
      decoration: BoxDecoration(
        border: Border.all(color: scheme.primary, width: 1.5),
        borderRadius: BorderRadius.circular(4),
        color: scheme.surface.withValues(alpha: 0.85),
      ),
      child: Focus(
        onFocusChange: (hasFocus) {
          if (!hasFocus) widget.onFinished?.call();
        },
        child: TextField(
          controller: _controller,
          focusNode: _focus,
          maxLines: null,
          expands: true,
          textAlignVertical: TextAlignVertical.top,
          style: Theme.of(context).textTheme.bodyMedium,
          decoration: const InputDecoration(
            border: InputBorder.none,
            filled: false,
            contentPadding: EdgeInsets.all(4),
          ),
          onChanged: widget.onChanged,
        ),
      ),
    );
  }
}

/// A typeset formula.
class _MathBox extends StatelessWidget {
  const _MathBox({required this.element});

  final MathElement element;

  @override
  Widget build(BuildContext context) => Align(
    alignment: Alignment.topLeft,
    child: Padding(
      padding: const EdgeInsets.all(4),
      child: FittedBox(
        fit: BoxFit.scaleDown,
        alignment: Alignment.topLeft,
        child: MathView.element(element),
      ),
    ),
  );
}

/// An imported image.
class _ImageBox extends ConsumerWidget {
  const _ImageBox({required this.assetId, required this.fit});

  final String assetId;
  final MediaFit fit;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final bytes = ref.watch(assetBytesProvider(assetId));

    return bytes.when(
      loading: () => const _MediaPlaceholder(label: 'Loading image…'),
      error: (error, _) => _MediaPlaceholder(label: 'Image failed: $error'),
      data: (data) => data == null
          ? const _MediaPlaceholder(label: 'Image is missing')
          : Image.memory(
              data,
              fit: switch (fit) {
                MediaFit.contain => BoxFit.contain,
                MediaFit.cover => BoxFit.cover,
                MediaFit.stretch => BoxFit.fill,
              },
              filterQuality: FilterQuality.medium,
            ),
    );
  }
}

/// A PDF page placed for annotation.
///
/// Rendering the page image needs a PDF engine; until one is wired in, the
/// element still holds its position, its source and its extracted text, so ink
/// annotations made over it keep their place and the page stays searchable.
class _PdfBox extends StatelessWidget {
  const _PdfBox({required this.element});

  final PdfElement element;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Container(
      decoration: BoxDecoration(
        color: scheme.surfaceContainerLowest,
        border: Border.all(color: scheme.outlineVariant),
      ),
      padding: const EdgeInsets.all(12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Row(
            children: <Widget>[
              Icon(
                Icons.picture_as_pdf_outlined,
                size: 16,
                color: scheme.onSurfaceVariant,
              ),
              const SizedBox(width: 6),
              Text(
                'PDF page ${element.pageIndex + 1}',
                style: TextStyle(fontSize: 12, color: scheme.onSurfaceVariant),
              ),
            ],
          ),
          if (element.extractedText != null) ...<Widget>[
            const SizedBox(height: 8),
            Expanded(
              child: Text(
                element.extractedText!,
                style: TextStyle(fontSize: 11, color: scheme.onSurfaceVariant),
                overflow: TextOverflow.fade,
              ),
            ),
          ],
        ],
      ),
    );
  }
}

/// A grid of rich-text cells.
class _TableBox extends StatelessWidget {
  const _TableBox({required this.element});

  final TableElement element;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final base = Theme.of(context).textTheme.bodySmall ?? const TextStyle();

    return Table(
      border: TableBorder.all(color: scheme.outlineVariant),
      columnWidths: <int, TableColumnWidth>{
        for (var i = 0; i < element.columnWidths.length; i++)
          i: FixedColumnWidth(element.columnWidths[i]),
      },
      children: <TableRow>[
        for (var r = 0; r < element.rows.length; r++)
          TableRow(
            decoration: r == 0 && element.headerRow
                ? BoxDecoration(color: scheme.surfaceContainerHigh)
                : null,
            children: <Widget>[
              for (var c = 0; c < element.columnWidths.length; c++)
                Padding(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 6,
                    vertical: 4,
                  ),
                  child: c < element.rows[r].length
                      ? Text.rich(
                          RichTextBlocks.spanFor(element.rows[r][c], base),
                        )
                      : const SizedBox.shrink(),
                ),
            ],
          ),
      ],
    );
  }
}

class _MediaPlaceholder extends StatelessWidget {
  const _MediaPlaceholder({required this.label});

  final String label;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Container(
      alignment: Alignment.center,
      decoration: BoxDecoration(
        color: scheme.surfaceContainerHighest.withValues(alpha: 0.4),
        border: Border.all(color: scheme.outlineVariant),
      ),
      child: Text(
        label,
        textAlign: TextAlign.center,
        style: TextStyle(fontSize: 11, color: scheme.onSurfaceVariant),
      ),
    );
  }
}
