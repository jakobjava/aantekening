/// Storage: the notes folder, and the SQLite index that makes finding and
/// searching in it instant.
///
/// The notes are files in a folder — one for each notebook, section and
/// page, gzipped JSON for pages — and the organisational tree, page bodies
/// and derived indexes are kept in one SQLite database beside the app, so
/// that navigation and search are index lookups rather than directory walks.
library;

export 'src/ai_repository.dart';
export 'src/archive_export.dart';
export 'src/asset_store.dart';
export 'src/backups.dart';
export 'src/bin_repository.dart';
export 'src/database.dart';
export 'src/draft_storing.dart';
export 'src/embedding_repository.dart';
export 'src/files/entity_files.dart';
export 'src/files/folder_mirror.dart';
export 'src/files/notes_folder.dart';
export 'src/fts_query.dart';
export 'src/library_repository.dart';
export 'src/page_repository.dart' show BodyEncoding, PageRepository;
export 'src/schema.dart';
export 'src/search_repository.dart';
export 'src/store.dart';
