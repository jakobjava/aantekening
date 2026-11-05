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
* **Equilibria lying one way drawn as such**
  (`lib/src/parser/tex/functions/katex_base/arrow.dart`): `\xrightequilibrium`
  and `\xleftequilibrium` are drawn with KaTeX's pictures of them, one
  arrow longer than the other, rather than as `⇌` and `⇋`, which drew them
  as `\xrightleftharpoons`.
* **Brackets drawn as large as they were chosen**
  (`lib/src/ast/nodes/left_right.dart`,
  `lib/src/render/layout/layout_builder_baseline.dart`): a `\left`/`\right`
  bracket is chosen from the size of the style it is in up, and drawn at
  the size it was measured at, as KaTeX chooses and draws it, and laid out
  within the height it is asked to fill rather than made to meet it. In a script or a fraction it was drawn at the formula's
  smaller size, shorter than it was chosen to be, and a debug build stopped
  on it (`RenderResetDimension does not meet its constraints`).
* **A named operator is its name alone**
  (`lib/src/parser/tex/functions/katex_base/operator_name.dart`):
  `\operatorname{tr}` is set as TeX sets it, taking nothing after it as
  its argument. Taking what followed failed where that was a command of its
  own, `\operatorname{tr} \left( A \right)` say, and gave a group after it
  the scripts meant for that group.
* **Commands of amsmath, amssymb and mathtools** (`lib/src/parser/tex/ams_macros.dart`,
  new, gathered into `builtinMacros` in `lib/src/parser/tex/macros.dart`):
  `\def` and `\gdef`, `\DeclareMathOperator`, labels, references and
  `\notag`, which show what they say or nothing, since a formula is one
  equation, and the operators, accents, fractions and upright Greek letters
  notes use that KaTeX's set lacks.
* **Defining commands as a note defines them**
  (`lib/src/parser/tex/macros.dart`): `\newcommand*` is read as
  `\newcommand`, a command defined again is defined anew, as a note's
  preamble defines `\R`, which is defined already, and `\tag` is set after
  the equation.
* **Matrices whose columns are aligned**
  (`lib/src/parser/tex/environments/array.dart`): mathtools' `matrix*`,
  `pmatrix*` and the other starred matrices, aligned as their optional
  argument says.
* **amsmath's display environments**
  (`lib/src/parser/tex/environments/eqn_array.dart`): `align`, `flalign`,
  `split` and their starred forms are set as `aligned`, and `gather`,
  `equation` and `multline` as `gathered`, a formula being one equation,
  numbered by nothing.

Only `lib`, the licence, the change log and the pubspec are kept.
