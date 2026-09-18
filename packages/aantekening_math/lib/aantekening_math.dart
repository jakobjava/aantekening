/// Math input and rendering for aantekening.
///
/// Formulas are stored as LaTeX and can be typed in two syntaxes. LaTeX is
/// taken as it is. Simple syntax is OneNote-style linear input (`1/2`, `x^2`,
/// `sqrt(3)`, `sum_(i=1)^n`, `mat(1, 2; 3, 4)`), translated to LaTeX through a
/// real lexer and parser — and back again, so a formula typed either way can
/// be edited in the other.
library;

export 'src/ast.dart';
export 'src/latex_reader.dart';
export 'src/lexer.dart' show MathDiagnostic, MathLexer, Token, TokenType;
export 'src/linear_math.dart';
export 'src/linear_writer.dart';
export 'src/math_storage.dart';
export 'src/math_view.dart';
export 'src/parser.dart';
export 'src/symbols.dart';
