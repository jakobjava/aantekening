/// Splitting page text into passages that can be embedded.
library;

/// One embeddable passage of a page.
class TextChunk {
  const TextChunk({
    required this.index,
    required this.text,
    required this.startOffset,
  });

  /// Position of this chunk within its page.
  final int index;

  final String text;

  /// Character offset into the page's text, so a hit can be traced back.
  final int startOffset;
}

/// Splits page text into overlapping passages.
///
/// Embedding a whole page as one vector loses everything specific about it, and
/// embedding single sentences loses the context that makes them meaningful. A
/// few hundred characters with a small overlap keeps each passage self-contained
/// while making sure an idea spanning a boundary is still fully present in one
/// of them.
class TextChunker {
  const TextChunker({
    this.targetSize = 900,
    this.overlap = 150,
    this.minimumSize = 80,
  }) : assert(overlap < targetSize, 'overlap must be smaller than targetSize');

  /// Preferred chunk length in characters.
  final int targetSize;

  /// How much of the previous chunk each one repeats.
  final int overlap;

  /// Chunks shorter than this are merged into the previous one rather than
  /// stored on their own, where they would match almost any query.
  final int minimumSize;

  /// Splits [text] into chunks, preferring paragraph then sentence boundaries.
  List<TextChunk> split(String text) {
    final trimmed = text.trim();
    if (trimmed.isEmpty) return const <TextChunk>[];
    if (trimmed.length <= targetSize) {
      return <TextChunk>[TextChunk(index: 0, text: trimmed, startOffset: 0)];
    }

    final chunks = <TextChunk>[];
    var start = 0;

    while (start < trimmed.length) {
      var end = start + targetSize;
      if (end >= trimmed.length) {
        end = trimmed.length;
      } else {
        end = _breakPointNear(trimmed, start, end);
      }

      final piece = trimmed.substring(start, end).trim();
      if (piece.isNotEmpty) {
        if (piece.length < minimumSize && chunks.isNotEmpty) {
          // Fold a short tail into the chunk before it.
          final previous = chunks.removeLast();
          chunks.add(
            TextChunk(
              index: previous.index,
              text: '${previous.text}\n$piece',
              startOffset: previous.startOffset,
            ),
          );
        } else {
          chunks.add(
            TextChunk(index: chunks.length, text: piece, startOffset: start),
          );
        }
      }

      if (end >= trimmed.length) break;
      start = end - overlap;
      if (start < 0) start = 0;
    }

    return chunks;
  }

  /// Finds a natural break at or before [limit], falling back to a hard cut.
  int _breakPointNear(String text, int start, int limit) {
    // Never search back past the overlap, or chunks would shrink unboundedly.
    final earliest = start + targetSize - overlap;

    for (final separator in const <String>['\n\n', '\n', '. ', ', ', ' ']) {
      final found = text.lastIndexOf(separator, limit);
      if (found > earliest) return found + separator.length;
    }
    return limit;
  }
}
