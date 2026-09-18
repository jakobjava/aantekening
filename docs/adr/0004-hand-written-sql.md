# 4. Hand-written SQL, not an ORM

**Status:** accepted

## Context

Dart has good database libraries. Drift in particular generates typed queries
from a schema definition.

## Decision

Use the `sqlite3` package directly, with SQL written by hand and a
prepared-statement cache on the connection.

## Consequences

* FTS5 — virtual tables, `bm25` column weights, `snippet()`, `optimize` — is
  available directly rather than through an escape hatch.
* The exact query plan for every hot path is visible in the source.
* No `build_runner` step, so a checkout builds and tests immediately.
* Type safety at the row boundary is ours to maintain; `row_read.dart` keeps
  every cast in one small file, and the store's tests run against a real
  database rather than a mock.
