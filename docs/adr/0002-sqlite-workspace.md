# 2. One SQLite database per workspace

**Status:** accepted

## Context

Notes must be searchable and navigable instantly across thousands of pages, on
three platforms, with no server.

## Decision

A workspace is a directory holding one SQLite database plus a
content-addressed asset directory. The database holds the tree, the page
bodies, the search index and the embeddings. Attachments are files.

## Alternatives considered

* **A folder of JSON files.** Simple and inspectable, but every search, sort and
  breadcrumb becomes a directory walk that gets slower as notes accumulate —
  the opposite of the priority here.
* **Everything, including attachments, in SQLite.** One file to copy, but a
  40 MB PDF would then be read through SQLite's page cache on every access, and
  a large database is slower to open and to back up.

## Consequences

* Navigation and search are index lookups.
* The workspace is still one folder to copy, sync or back up.
* Attachments deduplicate by SHA-256 automatically.
* Concurrent access from two app instances is bounded by SQLite's locking; WAL
  plus a busy timeout makes that safe, not fast. Multi-instance editing is not
  a goal.
