# flutter_math_fork 0.7.4, patched

The TeX typesetter formulas are drawn with, as published on pub.dev
(Apache-2.0, see `LICENSE`), with two changes, each marked `aantekening:`
where it is made. The workspace uses it through `dependency_overrides` in
its `pubspec.yaml`; 0.7.4 is the package's latest release.

* **`gathered`** (`lib/src/parser/tex/environments/eqn_array.dart`) is set
  as KaTeX sets it — one column, each row centred and in display style —
  instead of being refused. OneNote's equation arrays become it, and every
  one of them showed its source instead of the equations.
* **Rows kept apart** (`lib/src/ast/nodes/matrix.dart`): rows of a matrix
  or array taller than its strut, rows of fractions say, are kept a
  clearance apart, as TeX keeps lines apart by `\lineskip` where their
  boxes would otherwise meet. Arrays in TeX have no such rule, and a matrix
  of fractions was drawn with each one touching the next.

Only `lib`, the licence, the change log and the pubspec are kept.
