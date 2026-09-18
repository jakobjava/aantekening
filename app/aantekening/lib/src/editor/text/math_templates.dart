/// Structures and symbols to put into a formula from the ribbon.
library;

import 'package:aantekening_core/aantekening_core.dart';
import 'package:aantekening_math/aantekening_math.dart';
import 'package:flutter/foundation.dart';

/// A piece of a formula: a structure with places to fill in, or a symbol,
/// spelled in each syntax.
@immutable
class MathTemplate {
  const MathTemplate(
    this.name, {
    required this.simple,
    required this.latex,
    String? preview,
  }) : preview = preview ?? latex;

  /// Where the caret goes once the template is in.
  static const String caret = '‸';

  final String name;

  /// In Simple syntax, with [caret] where typing continues.
  final String simple;

  /// In LaTeX, likewise.
  final String latex;

  /// LaTeX drawn on its button.
  final String preview;

  String inSyntax(MathMode syntax) => syntax == MathMode.latex ? latex : simple;
}

/// Templates behind one ribbon button.
@immutable
class MathGallery {
  const MathGallery(this.name, this.icon, this.templates, {this.columns = 4});

  final String name;

  /// LaTeX drawn as the button's icon.
  final String icon;

  final List<MathTemplate> templates;
  final int columns;
}

MathTemplate _symbol(String name, String simple, String latex) =>
    MathTemplate(name, simple: ' $simple ', latex: ' $latex ', preview: latex);

/// Everything the ribbon's Math tab offers.
abstract final class MathGalleries {
  static const MathGallery fraction = MathGallery(
    'Fraction',
    r'\frac{a}{b}',
    <MathTemplate>[
      MathTemplate(
        'Fraction',
        simple: '(‸)/()',
        latex: r'\frac{‸}{}',
        preview: r'\frac{a}{b}',
      ),
      MathTemplate(
        'Binomial coefficient',
        simple: 'binom(‸, )',
        latex: r'\binom{‸}{}',
        preview: r'\binom{n}{k}',
      ),
      MathTemplate(
        'Derivative',
        simple: '(d ‸)/(d x)',
        latex: r'\frac{d‸}{dx}',
        preview: r'\frac{dy}{dx}',
      ),
      MathTemplate(
        'Partial derivative',
        simple: '(partial ‸)/(partial x)',
        latex: r'\frac{\partial ‸}{\partial x}',
        preview: r'\frac{\partial f}{\partial x}',
      ),
    ],
  );

  static const MathGallery script = MathGallery(
    'Script',
    r'x^{n}',
    <MathTemplate>[
      MathTemplate(
        'Superscript',
        simple: '^(‸)',
        latex: '^{‸}',
        preview: 'x^{2}',
      ),
      MathTemplate(
        'Subscript',
        simple: '_(‸)',
        latex: '_{‸}',
        preview: 'x_{i}',
      ),
      MathTemplate(
        'Subscript and superscript',
        simple: '_(‸)^()',
        latex: '_{‸}^{}',
        preview: 'x_{i}^{2}',
      ),
      MathTemplate('Prime', simple: "'‸", latex: "'‸", preview: "f'"),
    ],
  );

  static const MathGallery radical = MathGallery(
    'Radical',
    r'\sqrt{x}',
    <MathTemplate>[
      MathTemplate(
        'Square root',
        simple: 'sqrt(‸)',
        latex: r'\sqrt{‸}',
        preview: r'\sqrt{x}',
      ),
      MathTemplate(
        'Root',
        simple: 'root(‸, )',
        latex: r'\sqrt[‸]{}',
        preview: r'\sqrt[n]{x}',
      ),
      MathTemplate(
        'Cube root',
        simple: 'root(3, ‸)',
        latex: r'\sqrt[3]{‸}',
        preview: r'\sqrt[3]{x}',
      ),
    ],
  );

  static const MathGallery integral = MathGallery(
    'Integral',
    r'\int',
    <MathTemplate>[
      MathTemplate(
        'Integral',
        simple: 'int ‸',
        latex: r'\int ‸',
        preview: r'\int f',
      ),
      MathTemplate(
        'Definite integral',
        simple: 'int_(‸)^() ',
        latex: r'\int_{‸}^{} ',
        preview: r'\int_a^b',
      ),
      MathTemplate(
        'Double integral',
        simple: 'iint ‸',
        latex: r'\iint ‸',
        preview: r'\iint',
      ),
      MathTemplate(
        'Triple integral',
        simple: 'iiint ‸',
        latex: r'\iiint ‸',
        preview: r'\iiint',
      ),
      MathTemplate(
        'Contour integral',
        simple: 'oint ‸',
        latex: r'\oint ‸',
        preview: r'\oint',
      ),
      MathTemplate(
        'Differential',
        simple: ' d x‸',
        latex: r'\,\mathrm{d}x‸',
        preview: r'\mathrm{d}x',
      ),
    ],
  );

  static const MathGallery largeOperator = MathGallery(
    'Large operator',
    r'\sum',
    <MathTemplate>[
      MathTemplate(
        'Sum',
        simple: 'sum_(‸)^() ',
        latex: r'\sum_{‸}^{} ',
        preview: r'\sum_{i=1}^{n}',
      ),
      MathTemplate(
        'Product',
        simple: 'prod_(‸)^() ',
        latex: r'\prod_{‸}^{} ',
        preview: r'\prod_{i=1}^{n}',
      ),
      MathTemplate(
        'Limit',
        simple: 'lim_(‸ -> ) ',
        latex: r'\lim_{‸ \to } ',
        preview: r'\lim_{x \to 0}',
      ),
      MathTemplate(
        'Union',
        simple: 'bigcup_(‸) ',
        latex: r'\bigcup_{‸} ',
        preview: r'\bigcup_{i}',
      ),
      MathTemplate(
        'Intersection',
        simple: 'bigcap_(‸) ',
        latex: r'\bigcap_{‸} ',
        preview: r'\bigcap_{i}',
      ),
      MathTemplate(
        'Maximum',
        simple: 'max_(‸) ',
        latex: r'\max_{‸} ',
        preview: r'\max_{x}',
      ),
    ],
  );

  static const MathGallery bracket = MathGallery(
    'Bracket',
    '(x)',
    <MathTemplate>[
      MathTemplate(
        'Parentheses',
        simple: '(‸)',
        latex: r'\left( ‸ \right)',
        preview: '(x)',
      ),
      MathTemplate(
        'Square brackets',
        simple: '[‸]',
        latex: r'\left[ ‸ \right]',
        preview: '[x]',
      ),
      MathTemplate(
        'Braces',
        simple: 'set(‸)',
        latex: r'\left\{ ‸ \right\}',
        preview: r'\{x\}',
      ),
      MathTemplate(
        'Absolute value',
        simple: 'abs(‸)',
        latex: r'\left| ‸ \right|',
        preview: '|x|',
      ),
      MathTemplate(
        'Norm',
        simple: 'norm(‸)',
        latex: r'\left\| ‸ \right\|',
        preview: r'\|x\|',
      ),
      MathTemplate(
        'Floor',
        simple: 'floor(‸)',
        latex: r'\left\lfloor ‸ \right\rfloor',
        preview: r'\lfloor x \rfloor',
      ),
      MathTemplate(
        'Ceiling',
        simple: 'ceil(‸)',
        latex: r'\left\lceil ‸ \right\rceil',
        preview: r'\lceil x \rceil',
      ),
      MathTemplate(
        'Angle brackets',
        simple: 'inner(‸, )',
        latex: r'\langle ‸, \rangle',
        preview: r'\langle a, b \rangle',
      ),
    ],
  );

  static const MathGallery accent = MathGallery(
    'Accent',
    r'\vec{v}',
    <MathTemplate>[
      MathTemplate(
        'Vector arrow',
        simple: 'vec(‸)',
        latex: r'\vec{‸}',
        preview: r'\vec{v}',
      ),
      MathTemplate(
        'Hat',
        simple: 'hat(‸)',
        latex: r'\hat{‸}',
        preview: r'\hat{x}',
      ),
      MathTemplate(
        'Bar',
        simple: 'bar(‸)',
        latex: r'\bar{‸}',
        preview: r'\bar{x}',
      ),
      MathTemplate(
        'Dot',
        simple: 'dot(‸)',
        latex: r'\dot{‸}',
        preview: r'\dot{x}',
      ),
      MathTemplate(
        'Double dot',
        simple: 'ddot(‸)',
        latex: r'\ddot{‸}',
        preview: r'\ddot{x}',
      ),
      MathTemplate(
        'Tilde',
        simple: 'tilde(‸)',
        latex: r'\tilde{‸}',
        preview: r'\tilde{x}',
      ),
      MathTemplate(
        'Overline',
        simple: 'overline(‸)',
        latex: r'\overline{‸}',
        preview: r'\overline{AB}',
      ),
      MathTemplate(
        'Bold',
        simple: 'boldsymbol(‸)',
        latex: r'\boldsymbol{‸}',
        preview: r'\boldsymbol{v}',
      ),
    ],
  );

  static const MathGallery function = MathGallery(
    'Function',
    r'\sin\theta',
    <MathTemplate>[
      MathTemplate(
        'Sine',
        simple: 'sin(‸)',
        latex: r'\sin(‸)',
        preview: r'\sin x',
      ),
      MathTemplate(
        'Cosine',
        simple: 'cos(‸)',
        latex: r'\cos(‸)',
        preview: r'\cos x',
      ),
      MathTemplate(
        'Tangent',
        simple: 'tan(‸)',
        latex: r'\tan(‸)',
        preview: r'\tan x',
      ),
      MathTemplate(
        'Natural logarithm',
        simple: 'ln(‸)',
        latex: r'\ln(‸)',
        preview: r'\ln x',
      ),
      MathTemplate(
        'Logarithm',
        simple: 'log_(‸)()',
        latex: r'\log_{‸}()',
        preview: r'\log_{b} x',
      ),
      MathTemplate(
        'Exponential',
        simple: 'e^(‸)',
        latex: 'e^{‸}',
        preview: 'e^{x}',
      ),
    ],
  );

  static const MathGallery matrix = MathGallery(
    'Matrix',
    r'\begin{pmatrix}a&b\\c&d\end{pmatrix}',
    <MathTemplate>[
      MathTemplate(
        '2×2 matrix',
        simple: 'mat(‸, ; , )',
        latex: r'\begin{pmatrix} ‸ &  \\  &  \end{pmatrix}',
        preview: r'\begin{pmatrix}a&b\\c&d\end{pmatrix}',
      ),
      MathTemplate(
        '3×3 matrix',
        simple: 'mat(‸, , ; , , ; , , )',
        latex: r'\begin{pmatrix} ‸ &  &  \\  &  &  \\  &  &  \end{pmatrix}',
        preview: r'\begin{pmatrix}a&b&c\\d&e&f\\g&h&i\end{pmatrix}',
      ),
      MathTemplate(
        '2×2 matrix, square brackets',
        simple: 'bmat(‸, ; , )',
        latex: r'\begin{bmatrix} ‸ &  \\  &  \end{bmatrix}',
        preview: r'\begin{bmatrix}a&b\\c&d\end{bmatrix}',
      ),
      MathTemplate(
        'Determinant',
        simple: 'vmat(‸, ; , )',
        latex: r'\begin{vmatrix} ‸ &  \\  &  \end{vmatrix}',
        preview: r'\begin{vmatrix}a&b\\c&d\end{vmatrix}',
      ),
      MathTemplate(
        'Column vector',
        simple: 'vec(‸, , )',
        latex: r'\begin{pmatrix} ‸ \\  \\  \end{pmatrix}',
        preview: r'\begin{pmatrix}x\\y\\z\end{pmatrix}',
      ),
      MathTemplate(
        'Cases',
        simple: 'cases(‸, ; , )',
        latex: r'\begin{cases} ‸ &  \\  &  \end{cases}',
        preview: r'\begin{cases}a & x>0\\b & x\le 0\end{cases}',
      ),
    ],
    columns: 3,
  );

  static final MathGallery greek = MathGallery(
    'Greek',
    r'\alpha',
    <MathTemplate>[
      for (final entry in greekLetters.entries)
        if (entry.value.startsWith(r'\') && !entry.key.startsWith('var'))
          _symbol(entry.key, entry.key, entry.value),
    ],
    columns: 8,
  );

  static final MathGallery operators = MathGallery(
    'Operators',
    r'\pm',
    <MathTemplate>[
      _symbol('Plus or minus', '+-', r'\pm'),
      _symbol('Minus or plus', '-+', r'\mp'),
      _symbol('Times', 'times', r'\times'),
      _symbol('Divided by', 'div', r'\div'),
      _symbol('Dot', '*', r'\cdot'),
      _symbol('Composition', 'circ', r'\circ'),
      _symbol('Direct sum', 'oplus', r'\oplus'),
      _symbol('Tensor product', 'otimes', r'\otimes'),
      _symbol('Union', 'cup', r'\cup'),
      _symbol('Intersection', 'cap', r'\cap'),
      _symbol('Set difference', 'setminus', r'\setminus'),
      _symbol('And', 'wedge', r'\wedge'),
      _symbol('Or', 'vee', r'\vee'),
      _symbol('Not', 'neg', r'\neg'),
      _symbol('Nabla', 'nabla', r'\nabla'),
      _symbol('Partial', 'partial', r'\partial'),
    ],
    columns: 8,
  );

  static final MathGallery relations = MathGallery(
    'Relations',
    r'\leq',
    <MathTemplate>[
      _symbol('Not equal', '!=', r'\neq'),
      _symbol('Less or equal', '<=', r'\leq'),
      _symbol('Greater or equal', '>=', r'\geq'),
      _symbol('Approximately', '~~', r'\approx'),
      _symbol('Identical', 'equiv', r'\equiv'),
      _symbol('Similar', 'sim', r'\sim'),
      _symbol('Congruent', 'cong', r'\cong'),
      _symbol('Proportional', 'propto', r'\propto'),
      _symbol('Much less', 'll', r'\ll'),
      _symbol('Much greater', 'gg', r'\gg'),
      _symbol('Element of', 'in', r'\in'),
      _symbol('Not an element of', 'notin', r'\notin'),
      _symbol('Subset', 'subset', r'\subset'),
      _symbol('Subset or equal', 'subseteq', r'\subseteq'),
      _symbol('Superset', 'supset', r'\supset'),
      _symbol('Perpendicular', 'perp', r'\perp'),
      _symbol('Parallel', 'parallel', r'\parallel'),
    ],
    columns: 8,
  );

  static final MathGallery arrows = MathGallery(
    'Arrows',
    r'\to',
    <MathTemplate>[
      _symbol('To', '->', r'\to'),
      _symbol('From', '<-', r'\leftarrow'),
      _symbol('Maps to', 'mapsto', r'\mapsto'),
      _symbol('Therefore', '=>', r'\Rightarrow'),
      _symbol('Implies', '==>', r'\implies'),
      _symbol('Is implied by', '<==', r'\impliedby'),
      _symbol('If and only if', '<=>', r'\iff'),
    ],
    columns: 7,
  );

  static final MathGallery other = MathGallery(
    'Other',
    r'\infty',
    <MathTemplate>[
      _symbol('Infinity', 'infty', r'\infty'),
      _symbol('For all', 'forall', r'\forall'),
      _symbol('There exists', 'exists', r'\exists'),
      _symbol('Empty set', 'emptyset', r'\emptyset'),
      _symbol('Real numbers', 'mathbb(R)', r'\mathbb{R}'),
      _symbol('Natural numbers', 'mathbb(N)', r'\mathbb{N}'),
      _symbol('Integers', 'mathbb(Z)', r'\mathbb{Z}'),
      _symbol('Rationals', 'mathbb(Q)', r'\mathbb{Q}'),
      _symbol('Complex numbers', 'mathbb(C)', r'\mathbb{C}'),
      _symbol('Reduced Planck constant', 'hbar', r'\hbar'),
      _symbol('Script l', 'ell', r'\ell'),
      _symbol('Degree', '^circ', r'^\circ'),
      _symbol('Dots', '...', r'\ldots'),
      _symbol('Centred dots', 'cdots', r'\cdots'),
      _symbol('Therefore', 'therefore', r'\therefore'),
      _symbol('Because', 'because', r'\because'),
    ],
    columns: 8,
  );
}
