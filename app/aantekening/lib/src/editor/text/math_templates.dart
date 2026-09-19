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

  /// A piece written whole, such as a symbol, with a space either side to
  /// keep it apart from its neighbours, and the caret after it.
  factory MathTemplate.spaced(
    String name, {
    required String simple,
    required String latex,
  }) => MathTemplate(
    name,
    simple: ' $simple ',
    latex: ' $latex ',
    preview: latex,
  );

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
      MathTemplate(
        'Ket',
        simple: 'ket(‸)',
        latex: r'\ket{‸}',
        preview: r'\ket{\psi}',
      ),
      MathTemplate(
        'Bra',
        simple: 'bra(‸)',
        latex: r'\bra{‸}',
        preview: r'\bra{\phi}',
      ),
      MathTemplate(
        'Bra-ket',
        simple: 'braket(‸, )',
        latex: r'\braket{‸ | }',
        preview: r'\braket{\phi | \psi}',
      ),
      MathTemplate(
        'Matrix element',
        simple: 'braket(‸, , )',
        latex: r'\braket{‸ | | }',
        preview: r'\braket{\phi | A | \psi}',
      ),
      MathTemplate(
        'Expectation value',
        simple: 'braket(‸)',
        latex: r'\braket{‸}',
        preview: r'\braket{A}',
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
          MathTemplate.spaced(entry.key, simple: entry.key, latex: entry.value),
    ],
    columns: 8,
  );

  static final MathGallery operators = MathGallery(
    'Operators',
    r'\pm',
    <MathTemplate>[
      MathTemplate.spaced('Plus or minus', simple: '+-', latex: r'\pm'),
      MathTemplate.spaced('Minus or plus', simple: '-+', latex: r'\mp'),
      MathTemplate.spaced('Times', simple: 'times', latex: r'\times'),
      MathTemplate.spaced('Divided by', simple: 'div', latex: r'\div'),
      MathTemplate.spaced('Dot', simple: '*', latex: r'\cdot'),
      MathTemplate.spaced('Composition', simple: 'circ', latex: r'\circ'),
      MathTemplate.spaced('Direct sum', simple: 'oplus', latex: r'\oplus'),
      MathTemplate.spaced(
        'Tensor product',
        simple: 'otimes',
        latex: r'\otimes',
      ),
      MathTemplate.spaced('Union', simple: 'cup', latex: r'\cup'),
      MathTemplate.spaced('Intersection', simple: 'cap', latex: r'\cap'),
      MathTemplate.spaced(
        'Set difference',
        simple: 'setminus',
        latex: r'\setminus',
      ),
      MathTemplate.spaced('And', simple: 'wedge', latex: r'\wedge'),
      MathTemplate.spaced('Or', simple: 'vee', latex: r'\vee'),
      MathTemplate.spaced('Not', simple: 'neg', latex: r'\neg'),
      MathTemplate.spaced('Nabla', simple: 'nabla', latex: r'\nabla'),
      MathTemplate.spaced('Partial', simple: 'partial', latex: r'\partial'),
    ],
    columns: 8,
  );

  static final MathGallery relations = MathGallery(
    'Relations',
    r'\leq',
    <MathTemplate>[
      MathTemplate.spaced('Not equal', simple: '!=', latex: r'\neq'),
      MathTemplate.spaced('Less or equal', simple: '<=', latex: r'\leq'),
      MathTemplate.spaced('Greater or equal', simple: '>=', latex: r'\geq'),
      MathTemplate.spaced('Approximately', simple: '~~', latex: r'\approx'),
      MathTemplate.spaced('Identical', simple: 'equiv', latex: r'\equiv'),
      MathTemplate.spaced('Similar', simple: 'sim', latex: r'\sim'),
      MathTemplate.spaced('Congruent', simple: 'cong', latex: r'\cong'),
      MathTemplate.spaced('Proportional', simple: 'propto', latex: r'\propto'),
      MathTemplate.spaced('Much less', simple: 'll', latex: r'\ll'),
      MathTemplate.spaced('Much greater', simple: 'gg', latex: r'\gg'),
      MathTemplate.spaced('Element of', simple: 'in', latex: r'\in'),
      MathTemplate.spaced(
        'Not an element of',
        simple: 'notin',
        latex: r'\notin',
      ),
      MathTemplate.spaced('Subset', simple: 'subset', latex: r'\subset'),
      MathTemplate.spaced(
        'Subset or equal',
        simple: 'subseteq',
        latex: r'\subseteq',
      ),
      MathTemplate.spaced('Superset', simple: 'supset', latex: r'\supset'),
      MathTemplate.spaced('Perpendicular', simple: 'perp', latex: r'\perp'),
      MathTemplate.spaced('Parallel', simple: 'parallel', latex: r'\parallel'),
    ],
    columns: 8,
  );

  static final MathGallery arrows = MathGallery(
    'Arrows',
    r'\to',
    <MathTemplate>[
      MathTemplate.spaced('To', simple: '->', latex: r'\to'),
      MathTemplate.spaced('From', simple: '<-', latex: r'\leftarrow'),
      MathTemplate.spaced('Maps to', simple: 'mapsto', latex: r'\mapsto'),
      MathTemplate.spaced('Therefore', simple: '=>', latex: r'\Rightarrow'),
      MathTemplate.spaced('Implies', simple: '==>', latex: r'\implies'),
      MathTemplate.spaced('Is implied by', simple: '<==', latex: r'\impliedby'),
      MathTemplate.spaced('If and only if', simple: '<=>', latex: r'\iff'),
    ],
    columns: 7,
  );

  static final MathGallery
  other = MathGallery('Other', r'\infty', <MathTemplate>[
    MathTemplate.spaced('Infinity', simple: 'infty', latex: r'\infty'),
    MathTemplate.spaced('For all', simple: 'forall', latex: r'\forall'),
    MathTemplate.spaced('There exists', simple: 'exists', latex: r'\exists'),
    MathTemplate.spaced('Empty set', simple: 'emptyset', latex: r'\emptyset'),
    MathTemplate.spaced(
      'Real numbers',
      simple: 'mathbb(R)',
      latex: r'\mathbb{R}',
    ),
    MathTemplate.spaced(
      'Natural numbers',
      simple: 'mathbb(N)',
      latex: r'\mathbb{N}',
    ),
    MathTemplate.spaced('Integers', simple: 'mathbb(Z)', latex: r'\mathbb{Z}'),
    MathTemplate.spaced('Rationals', simple: 'mathbb(Q)', latex: r'\mathbb{Q}'),
    MathTemplate.spaced(
      'Complex numbers',
      simple: 'mathbb(C)',
      latex: r'\mathbb{C}',
    ),
    MathTemplate.spaced(
      'Reduced Planck constant',
      simple: 'hbar',
      latex: r'\hbar',
    ),
    MathTemplate.spaced('Script l', simple: 'ell', latex: r'\ell'),
    MathTemplate.spaced('Degree', simple: '^circ', latex: r'^\circ'),
    MathTemplate.spaced('Dots', simple: '...', latex: r'\ldots'),
    MathTemplate.spaced('Centred dots', simple: 'cdots', latex: r'\cdots'),
    MathTemplate.spaced('Therefore', simple: 'therefore', latex: r'\therefore'),
    MathTemplate.spaced('Because', simple: 'because', latex: r'\because'),
  ], columns: 8);
}
