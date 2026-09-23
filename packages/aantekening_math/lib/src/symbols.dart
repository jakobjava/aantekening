/// The vocabulary recognised by the linear math parser.
///
/// Every entry maps a word a user can type to the LaTeX that renders it. The
/// tables are the single source of truth for both the lexer, which matches
/// the longest known word at each position, and the writer, which spells
/// LaTeX back in these words.
library;

import 'ast.dart' show BraketKind;

/// How a recognised word behaves in the grammar.
enum SymbolRole {
  /// A standalone symbol: `alpha`, `infty`, `nabla`.
  atom,

  /// A named function that may be applied to an argument: `sin`, `log`.
  function,

  /// A large operator that takes limits: `sum`, `int`, `lim`.
  bigOperator,

  /// Takes one bracketed argument: `sqrt`, `vec`, `bar`.
  unaryConstruct,

  /// Takes two comma-separated arguments: `frac`, `binom`, `root`.
  binaryConstruct,

  /// A fenced construct: `abs`, `norm`, `floor`, `ceil`.
  fenceConstruct,

  /// A grid of cells, rows separated by `;` and cells by `,`: `mat`, `cases`.
  matrixConstruct,

  /// Dirac notation: `bra(psi)`, `ket(psi)`, `braket(phi, psi)`.
  braketConstruct,

  /// A highlighter's mark behind its argument: `highlight(x)`, or
  /// `highlight(#A8E6B0, x)` in a colour of its own.
  highlightConstruct,
}

/// A word the parser knows about.
class MathSymbol {
  const MathSymbol(this.latex, this.role);

  /// The LaTeX command or fragment this word produces.
  final String latex;

  final SymbolRole role;
}

/// Greek letters, written the way they are spelled.
const Map<String, String> greekLetters = <String, String>{
  'alpha': r'\alpha',
  'beta': r'\beta',
  'gamma': r'\gamma',
  'delta': r'\delta',
  'epsilon': r'\epsilon',
  'varepsilon': r'\varepsilon',
  'zeta': r'\zeta',
  'eta': r'\eta',
  'theta': r'\theta',
  'vartheta': r'\vartheta',
  'iota': r'\iota',
  'kappa': r'\kappa',
  'lambda': r'\lambda',
  'mu': r'\mu',
  'nu': r'\nu',
  'xi': r'\xi',
  'omicron': r'o',
  'pi': r'\pi',
  'varpi': r'\varpi',
  'rho': r'\rho',
  'varrho': r'\varrho',
  'sigma': r'\sigma',
  'varsigma': r'\varsigma',
  'tau': r'\tau',
  'upsilon': r'\upsilon',
  'phi': r'\phi',
  'varphi': r'\varphi',
  'chi': r'\chi',
  'psi': r'\psi',
  'omega': r'\omega',
  'Gamma': r'\Gamma',
  'Delta': r'\Delta',
  'Theta': r'\Theta',
  'Lambda': r'\Lambda',
  'Xi': r'\Xi',
  'Pi': r'\Pi',
  'Sigma': r'\Sigma',
  'Upsilon': r'\Upsilon',
  'Phi': r'\Phi',
  'Psi': r'\Psi',
  'Omega': r'\Omega',
};

/// Named functions, typeset upright.
const List<String> namedFunctions = <String>[
  'arccos',
  'arcsin',
  'arctan',
  'arg',
  'cos',
  'cosh',
  'cot',
  'coth',
  'csc',
  'deg',
  'det',
  'dim',
  'exp',
  'gcd',
  'hom',
  'ker',
  'lg',
  'ln',
  'log',
  'sec',
  'sin',
  'sinh',
  'tan',
  'tanh',
];

/// Operators without a command of their own, typeset upright as named
/// functions are: `\operatorname{tr}`.
const List<String> operatorNames = <String>[
  'tr',
  'Tr',
  'rank',
  'sgn',
  'diag',
  'erf',
  'Var',
  'Cov',
];

/// The LaTeX for operator [name].
String operatorNameLatex(String name) => '\\operatorname{$name}';

/// Operators that carry limits above and below.
const Map<String, String> bigOperators = <String, String>{
  'sum': r'\sum',
  'prod': r'\prod',
  'coprod': r'\coprod',
  'int': r'\int',
  'iint': r'\iint',
  'iiint': r'\iiint',
  'oint': r'\oint',
  'lim': r'\lim',
  'limsup': r'\limsup',
  'liminf': r'\liminf',
  'max': r'\max',
  'min': r'\min',
  'sup': r'\sup',
  'bigcup': r'\bigcup',
  'bigcap': r'\bigcap',
};

/// Constructs taking a single bracketed argument.
const Map<String, String> unaryConstructs = <String, String>{
  'sqrt': r'\sqrt',
  'vec': r'\vec',
  'hat': r'\hat',
  'bar': r'\bar',
  'dot': r'\dot',
  'ddot': r'\ddot',
  'tilde': r'\tilde',
  'widehat': r'\widehat',
  'widetilde': r'\widetilde',
  'overline': r'\overline',
  'underline': r'\underline',
  'overbrace': r'\overbrace',
  'underbrace': r'\underbrace',
  'boldsymbol': r'\boldsymbol',
  'mathbb': r'\mathbb',
  'mathcal': r'\mathcal',
  'mathfrak': r'\mathfrak',
};

/// Constructs taking two comma-separated arguments.
const Map<String, String> binaryConstructs = <String, String>{
  'frac': r'\frac',
  'binom': r'\binom',
  'root': r'\sqrt',
  'nthroot': r'\sqrt',
  'stackrel': r'\stackrel',
};

/// Constructs that fence their argument in matching delimiters.
const Map<String, List<String>> fenceConstructs = <String, List<String>>{
  'abs': <String>[r'\lvert', r'\rvert'],
  'norm': <String>[r'\lVert', r'\rVert'],
  'floor': <String>[r'\lfloor', r'\rfloor'],
  'ceil': <String>[r'\lceil', r'\rceil'],
  'inner': <String>[r'\langle', r'\rangle'],
  'set': <String>[r'\{', r'\}'],
};

/// Grids and the LaTeX environment each is written as: `mat(1, 2; 3, 4)` is a
/// matrix in round brackets, `cases(x, x > 0; -x, x < 0)` a case split.
const Map<String, String> matrixConstructs = <String, String>{
  'mat': 'pmatrix',
  'pmat': 'pmatrix',
  'bmat': 'bmatrix',
  'Bmat': 'Bmatrix',
  'vmat': 'vmatrix',
  'Vmat': 'Vmatrix',
  'matrix': 'matrix',
  'cases': 'cases',
};

/// Operators that separate the two sides of a statement, as LaTeX.
const Set<String> relationOperators = <String>{
  '=',
  '<',
  '>',
  r'\leq',
  r'\geq',
  r'\neq',
  r'\approx',
  r'\equiv',
  r'\simeq',
  r'\cong',
  r'\sim',
  r'\propto',
  r'\to',
  r'\mapsto',
  r'\leftrightarrow',
  r'\iff',
  r'\implies',
  r'\impliedby',
  r'\Rightarrow',
  r'\leftarrow',
  r'\in',
  r'\notin',
  r'\ni',
  r'\subset',
  r'\subseteq',
  r'\supset',
  r'\supseteq',
  r'\ll',
  r'\gg',
  r'\perp',
  r'\parallel',
  r'\therefore',
  r'\because',
  ':',
  r'\colon',
};

/// Operators at addition's precedence level, as LaTeX.
const Set<String> additiveOperators = <String>{
  '+',
  '-',
  r'\pm',
  r'\mp',
  r'\cup',
  r'\cap',
  r'\setminus',
  r'\oplus',
  r'\wedge',
  r'\vee',
};

/// Operators at multiplication's precedence level, as LaTeX.
const Set<String> multiplicativeOperators = <String>{
  r'\cdot',
  r'\times',
  r'\div',
  r'\otimes',
  r'\circ',
  r'\star',
  r'\bullet',
  r'\bmod',
  '.',
};

/// Standalone symbols spelled as words.
const Map<String, String> wordSymbols = <String, String>{
  'oo': r'\infty',
  'infty': r'\infty',
  'infinity': r'\infty',
  'nabla': r'\nabla',
  'partial': r'\partial',
  'forall': r'\forall',
  'exists': r'\exists',
  'nexists': r'\nexists',
  'in': r'\in',
  'notin': r'\notin',
  'ni': r'\ni',
  'subset': r'\subset',
  'subseteq': r'\subseteq',
  'supset': r'\supset',
  'supseteq': r'\supseteq',
  'cup': r'\cup',
  'cap': r'\cap',
  'setminus': r'\setminus',
  'emptyset': r'\emptyset',
  'varnothing': r'\varnothing',
  'to': r'\to',
  'mapsto': r'\mapsto',
  'implies': r'\implies',
  'iff': r'\iff',
  'times': r'\times',
  'div': r'\div',
  'cdot': r'\cdot',
  'pm': r'\pm',
  'mp': r'\mp',
  'neq': r'\neq',
  'leq': r'\leq',
  'geq': r'\geq',
  'll': r'\ll',
  'gg': r'\gg',
  'approx': r'\approx',
  'equiv': r'\equiv',
  'propto': r'\propto',
  'sim': r'\sim',
  'simeq': r'\simeq',
  'cong': r'\cong',
  'perp': r'\perp',
  'parallel': r'\parallel',
  'deg': r'^\circ',
  'ldots': r'\ldots',
  'cdots': r'\cdots',
  'vdots': r'\vdots',
  'ddots': r'\ddots',
  'dots': r'\dots',
  'aleph': r'\aleph',
  'hbar': r'\hbar',
  'ell': r'\ell',
  'Re': r'\Re',
  'Im': r'\Im',
  'wedge': r'\wedge',
  'vee': r'\vee',
  'neg': r'\neg',
  'oplus': r'\oplus',
  'otimes': r'\otimes',
  'star': r'\star',
  'circ': r'\circ',
  'bullet': r'\bullet',
  'therefore': r'\therefore',
  'because': r'\because',
  'dagger': r'\dagger',
  'angle': r'\angle',
  'mod': r'\bmod',
  // The number sets, doubled as AsciiMath and many notes write them.
  'NN': r'\mathbb{N}',
  'ZZ': r'\mathbb{Z}',
  'QQ': r'\mathbb{Q}',
  'RR': r'\mathbb{R}',
  'CC': r'\mathbb{C}',
};

/// Multi-character operators typed with punctuation.
///
/// Longest match wins, so `<=>` is tried before `<=` and `<`.
const Map<String, String> operatorSequences = <String, String>{
  '<=>': r'\iff',
  '<->': r'\leftrightarrow',
  '==>': r'\implies',
  '<==': r'\impliedby',
  '!=': r'\neq',
  '<=': r'\leq',
  '>=': r'\geq',
  '->': r'\to',
  '<-': r'\leftarrow',
  '=>': r'\Rightarrow',
  '~=': r'\approx',
  '~~': r'\approx',
  '+-': r'\pm',
  '-+': r'\mp',
  '::': r'\colon',
  ':': ':',
  '...': r'\ldots',
  '.': '.',
  '*': r'\cdot',
  '=': '=',
  '<': '<',
  '>': '>',
  '+': '+',
  '-': '-',
  '!': '!',
};

/// The complete word table, assembled once.
final Map<String, MathSymbol> mathSymbols = <String, MathSymbol>{
  for (final entry in greekLetters.entries)
    entry.key: MathSymbol(entry.value, SymbolRole.atom),
  for (final entry in wordSymbols.entries)
    entry.key: MathSymbol(entry.value, SymbolRole.atom),
  for (final name in namedFunctions)
    name: MathSymbol('\\$name', SymbolRole.function),
  for (final name in operatorNames)
    name: MathSymbol(operatorNameLatex(name), SymbolRole.function),
  for (final entry in bigOperators.entries)
    entry.key: MathSymbol(entry.value, SymbolRole.bigOperator),
  for (final entry in unaryConstructs.entries)
    entry.key: MathSymbol(entry.value, SymbolRole.unaryConstruct),
  for (final entry in binaryConstructs.entries)
    entry.key: MathSymbol(entry.value, SymbolRole.binaryConstruct),
  for (final entry in fenceConstructs.entries)
    entry.key: MathSymbol(entry.value.first, SymbolRole.fenceConstruct),
  for (final entry in matrixConstructs.entries)
    entry.key: MathSymbol(entry.value, SymbolRole.matrixConstruct),
  for (final kind in BraketKind.values)
    kind.name: MathSymbol(kind.command, SymbolRole.braketConstruct),
  'highlight': const MathSymbol(r'\colorbox', SymbolRole.highlightConstruct),
};

/// Every word the parser knows, longest first.
///
/// The lexer walks this order so that `varepsilon` is matched before
/// `varepsilo`n would ever be split, and `arcsin` before `arc`.
final List<String> knownWordsByLength = mathSymbols.keys.toList()
  ..sort((a, b) => b.length.compareTo(a.length));
