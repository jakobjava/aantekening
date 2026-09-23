/// Domain model, page-document format and serialization for aantekening.
///
/// This package is deliberately pure Dart with no Flutter dependency: the same
/// model backs the UI, the storage layer, the command-line import/export tools
/// and the test suite, and it can run inside a background isolate.
library;

export 'src/document/elements.dart';
export 'src/document/ink.dart';
export 'src/document/page_document.dart';
export 'src/document/rich_text.dart';
export 'src/document/rich_text_editing.dart';
export 'src/document/table_editing.dart';
export 'src/document/text_tables.dart';
export 'src/search/search_terms.dart';
export 'src/tree/hierarchy.dart';
export 'src/tree/tree.dart';
export 'src/util/fractional_index.dart';
export 'src/util/geometry.dart';
export 'src/util/json_read.dart';
export 'src/util/ulid.dart';
