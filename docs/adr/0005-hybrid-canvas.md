# 5. Ink is painted; everything else is a widget

**Status:** accepted

## Context

A page holds both handwriting — potentially hundreds of thousands of samples —
and text, formulas, images and tables, which need editing, focus and selection.
One rendering strategy cannot serve both well.

## Decision

Paint ink with `CustomPainter` in page space. Render every other element as a
real widget, positioned at its on-screen rectangle and scaled from page units.
Highlighter paints beneath the widget layer, pen above it.

## Consequences

* Text boxes get the framework's text layout, input methods and focus, with
  the editor on top of them described in ADR 8; formulas get
  `flutter_math_fork`; images get `Image`.
* Ink costs no widgets at all, and the stroke in progress has its own layer, so
  a new sample repaints only that.
* Splitting ink around the widget layer means ink cannot interleave arbitrarily
  with text in paint order. Bound to the tools rather than to `z`, this matches
  what the instruments mean physically: a highlighter goes under writing, a pen
  over it.
* Elements are placed individually rather than under one big `Transform`,
  because a transformed, overflowing layer silently loses hit-testing and
  keyboard focus for anything outside its box.
