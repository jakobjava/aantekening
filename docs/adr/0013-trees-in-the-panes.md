# 13. Sections and pages as trees, built once

**Status:** accepted

## Context

Sections nest in sections and pages under pages, and the store lists both
flat. Four places put them back into a tree, each its own way: the notebook
pane with a node class of its own, the page pane with an ordering function,
pasting with a map of parents walked by hand, and the store with loops of
queries. Each dealt with a missing parent, or a loop of parents, in its own
way, and the panes showed nesting by indentation alone, which says little
once a tree is three or four levels deep.

## Decision

* **One `Hierarchy<T>`.** Core assembles a flat list of items, each naming
  its parent, into a tree: children in the order listed, an item whose parent
  is missing promoted to the top, and a loop of parents — which the store
  never writes — broken rather than followed. `Section.hierarchy` and
  `PageRef.hierarchy` build it for sections and pages; the section and page
  providers hand it out, and the panes, pasting and anything else that asks
  what lies within what read it. The store answers the same question in SQL,
  with a recursive query over `parent_id`.
* **Lines, and collapsing.** Each row of the notebook and page panes is
  joined to its parent by a line that comes down from the parent and turns
  into the row. Clicking a line, or a row's chevron, collapses the row it
  comes down from; the line under the pointer lights up along its whole
  length. What is collapsed is kept in the preferences. Opening something
  from elsewhere — search, the graph, a paste — expands the rows above it.
* **Sections are folders.** Every section shows a folder, open while its
  pages are listed beside it; pages show a page.

## Consequences

* A tree is built once for each list read, not once for each question.
* Collapsed rows are remembered by id; those of deleted sections and pages
  stay remembered in case they are restored.
