# flutter_math_fork 0.7.4, patched

The TeX typesetter formulas are drawn with, as published on pub.dev
(Apache-2.0, see `LICENSE`), with changes, each marked `aantekening:`
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
* **Brackets drawn as large as they were chosen**
  (`lib/src/ast/nodes/left_right.dart`,
  `lib/src/render/layout/layout_builder_baseline.dart`): a `\left`/`\right`
  bracket is chosen from the size of the style it is in up, and drawn at
  the size it was measured at, as KaTeX chooses and draws it, and laid out
  within the height it is asked to fill rather than made to meet it. In a script or a fraction it was drawn at the formula's
  smaller size, shorter than it was chosen to be, and a debug build stopped
  on it (`RenderResetDimension does not meet its constraints`).

Only `lib`, the licence, the change log and the pubspec are kept.
