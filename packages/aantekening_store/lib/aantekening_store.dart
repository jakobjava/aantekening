/// SQLite-backed storage, full-text search and asset management.
///
/// The organisational tree, page bodies and derived indexes all live in one
/// SQLite database so that navigation and search are index lookups rather than
/// directory walks. Page bodies remain plain JSON inside that database, which
/// keeps the note format open and exportable without giving up query speed.
library;

export 'src/ai_repository.dart';
export 'src/asset_store.dart';
export 'src/database.dart';
export 'src/embedding_repository.dart';
export 'src/fts_query.dart';
export 'src/library_repository.dart';
export 'src/page_repository.dart' show BodyEncoding, PageRepository;
export 'src/schema.dart';
export 'src/search_repository.dart';
export 'src/store.dart';
