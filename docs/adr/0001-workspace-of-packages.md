# 1. A pub workspace of packages, not one application

**Status:** accepted

## Context

The application has to grow in several directions at once — a canvas engine, a
storage engine, a maths engine, an AI layer — and stay fast while doing it.

## Decision

Use a Dart pub workspace: `app/aantekening` over five packages, with
`aantekening_core` at the bottom holding pure Dart with no Flutter dependency.

## Consequences

* The model can run in a background isolate and in plain `dart test`, because
  nothing in `_core` touches Flutter.
* Dependency direction is enforced by the compiler rather than by convention.
  The canvas *cannot* accidentally reach for the maths renderer.
* A pub workspace resolves all members together, so there is one lockfile, one
  `pub get`, and no Melos or bootstrap script to keep working.
* The cost is more `pubspec.yaml` files and a moment's thought about where new
  code belongs. That thought is the point.
