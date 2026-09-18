/// Math input and rendering for aantekening.
///
/// Formulas can be authored in two modes. LaTeX mode takes the source verbatim.
/// Simple mode accepts OneNote-style linear input (`1/2`, `x^2`, `sqrt(3)`,
/// `sum_(i=1)^n`) and translates it to LaTeX through a real lexer and parser,
/// so that nesting, precedence and bracket elision behave predictably.
library;

export 'src/ast.dart';
export 'src/lexer.dart' show MathDiagnostic, MathLexer, Token, TokenType;
export 'src/linear_math.dart';
export 'src/math_view.dart';
export 'src/parser.dart';
export 'src/symbols.dart';
