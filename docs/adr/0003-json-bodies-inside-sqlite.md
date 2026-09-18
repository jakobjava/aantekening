# 3. Page bodies stay JSON, inside the database

**Status:** accepted

## Context

The note format should be open and inspectable, but queries have to be fast.
Those pull in opposite directions.

## Decision

A page is a JSON document. It is stored as a gzip-compressed blob in a
`page_bodies` table, separate from the `pages` metadata table. Export writes the
same JSON, byte for byte.

## Consequences

* There is no second, private representation that could drift from the format
  the user can export — the export *is* the stored document.
* Listing pages, searching and rendering breadcrumbs touch only the small
  `pages` rows; SQLite never has to seek past megabyte blobs to answer them.
* Compression above 4 KiB roughly halves a text-heavy page. Below that the
  gzip header and round trip cost more than they save, and short pages are the
  ones that must open instantly.
* JSON parsing is on the page-open path. It is fast enough at these sizes, and
  a binary format would trade away the openness that motivated the choice.
