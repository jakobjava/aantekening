/// Storage and nearest-neighbour search for text embeddings produced by a
/// locally run model.
library;

import 'dart:math' as math;
import 'dart:typed_data';

import 'database.dart';
import 'row_read.dart';

/// One embedded chunk of a page.
class EmbeddedChunk {
  const EmbeddedChunk({
    required this.pageId,
    required this.chunkIndex,
    required this.text,
    required this.vector,
  });

  final String pageId;
  final int chunkIndex;
  final String text;
  final Float32List vector;
}

/// A semantic-search result.
class SemanticHit {
  const SemanticHit({
    required this.pageId,
    required this.chunkIndex,
    required this.text,
    required this.similarity,
  });

  final String pageId;
  final int chunkIndex;
  final String text;

  /// Cosine similarity in `[-1, 1]`; higher is closer.
  final double similarity;
}

/// Stores embeddings and scores them against a query vector.
///
/// Vectors are kept as raw little-endian float32 blobs, so a scan reads them
/// through a [Float32List] view with no per-row parsing. Scoring is a linear
/// scan by design: it stays well inside a frame's budget for a personal
/// workspace, and it avoids taking on an approximate-index dependency before
/// the corpus is large enough to need one.
class EmbeddingRepository {
  EmbeddingRepository(this._db, {DateTime Function()? clock})
    : _clock = clock ?? DateTime.now;

  final AantekeningDatabase _db;
  final DateTime Function() _clock;

  /// Replaces every stored chunk for [pageId] under [model].
  Future<void> replacePageChunks(
    String pageId,
    String model,
    List<EmbeddedChunk> chunks,
  ) async {
    final now = _clock().millisecondsSinceEpoch;
    _db.transaction(() {
      _db.run(
        'DELETE FROM embeddings WHERE page_id = ? AND model = ?',
        <Object?>[pageId, model],
      );
      for (final chunk in chunks) {
        _db.run(
          'INSERT INTO embeddings '
          '(page_id, chunk_index, model, dimensions, vector, text, created_at) '
          'VALUES (?, ?, ?, ?, ?, ?, ?)',
          <Object?>[
            pageId,
            chunk.chunkIndex,
            model,
            chunk.vector.length,
            chunk.vector.buffer.asUint8List(
              chunk.vector.offsetInBytes,
              chunk.vector.lengthInBytes,
            ),
            chunk.text,
            now,
          ],
        );
      }
    });
  }

  /// Removes every embedding for [pageId], across all models.
  Future<void> clearPage(String pageId) async {
    _db.run('DELETE FROM embeddings WHERE page_id = ?', <Object?>[pageId]);
  }

  /// Returns the chunks closest to [query], best first.
  ///
  /// [minSimilarity] discards weak matches; without a floor a semantic search
  /// always returns something, however unrelated.
  Future<List<SemanticHit>> nearest(
    Float32List query, {
    required String model,
    int limit = 10,
    double minSimilarity = 0.2,
  }) async {
    final queryNorm = _norm(query);
    if (queryNorm == 0) return const <SemanticHit>[];

    final rows = _db.select(
      'SELECT e.page_id AS page_id, e.chunk_index AS chunk_index, '
      '       e.text AS text, e.vector AS vector '
      'FROM embeddings e '
      'JOIN pages p ON p.id = e.page_id '
      'WHERE e.model = ? AND e.dimensions = ? AND p.deleted_at IS NULL',
      <Object?>[model, query.length],
    );

    final hits = <SemanticHit>[];
    for (final row in rows) {
      final vector = _viewAsFloat32(row['vector'] as Uint8List);
      if (vector.length != query.length) continue;

      final similarity = _cosine(query, vector, queryNorm);
      if (similarity < minSimilarity) continue;

      hits.add(
        SemanticHit(
          pageId: str(row, 'page_id'),
          chunkIndex: integer(row, 'chunk_index'),
          text: str(row, 'text'),
          similarity: similarity,
        ),
      );
    }

    hits.sort((a, b) => b.similarity.compareTo(a.similarity));
    return hits.length <= limit ? hits : hits.sublist(0, limit);
  }

  /// Number of stored chunks, optionally restricted to one model.
  Future<int> chunkCount({String? model}) async {
    final rows = model == null
        ? _db.select('SELECT COUNT(*) AS c FROM embeddings')
        : _db.select(
            'SELECT COUNT(*) AS c FROM embeddings WHERE model = ?',
            <Object?>[model],
          );
    return integer(rows.first, 'c');
  }

  /// Reads a blob as float32, copying only when the blob is not aligned to a
  /// four-byte boundary.
  static Float32List _viewAsFloat32(Uint8List bytes) {
    if (bytes.offsetInBytes % Float32List.bytesPerElement == 0) {
      return bytes.buffer.asFloat32List(
        bytes.offsetInBytes,
        bytes.lengthInBytes ~/ Float32List.bytesPerElement,
      );
    }
    return Uint8List.fromList(bytes).buffer.asFloat32List();
  }

  static double _norm(Float32List vector) {
    var sum = 0.0;
    for (var i = 0; i < vector.length; i++) {
      sum += vector[i] * vector[i];
    }
    return sum <= 0 ? 0 : math.sqrt(sum);
  }

  static double _cosine(Float32List a, Float32List b, double aNorm) {
    var dot = 0.0;
    var bSum = 0.0;
    for (var i = 0; i < a.length; i++) {
      dot += a[i] * b[i];
      bSum += b[i] * b[i];
    }
    if (bSum <= 0) return 0;
    return dot / (aNorm * math.sqrt(bSum));
  }
}
