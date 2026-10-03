// aantekening: commands of amsmath, amssymb, mathtools and the packages
// notes most often use with them, that KaTeX's set lacks. Each is set as
// near as the renderer can to what LaTeX sets: a formula here is one
// equation, so numbering and labelling show what they say, or nothing.

import 'macro_expander.dart';
import 'macros.dart';

/// A command that takes [arguments] and shows nothing: a label, say.
MacroDefinition _ignoring(int arguments) =>
    MacroDefinition.fromCtxString((context) {
      context.consumeArgs(arguments);
      return '';
    });

/// Reads `\def\name#1#2{body}`, the parameters numbered from one, and
/// defines `\name` as the body: [global] for `\gdef`.
String _define(MacroContext context, {required bool global}) {
  final name = context.popToken().text;
  var numArgs = 0;
  while (context.future().text == '#') {
    context.popToken();
    context.popToken();
    numArgs++;
  }
  final body = context.consumeArgs(1)[0];
  context.macros.set(
    name,
    MacroDefinition.fromMacroExpansion(
      MacroExpansion(tokens: body, numArgs: numArgs),
    ),
    global: global,
  );
  return '';
}

/// Reads `\DeclareMathOperator{\name}{text}`, or its starred form, whose
/// operator takes its limits above and below, and defines `\name`.
String _declareOperator(MacroContext context) {
  final starred = context.future().text == '*';
  if (starred) context.popToken();
  final args = context.consumeArgs(2);
  final name = args[0].map((token) => token.text).join();
  final text = args[1].reversed.map((token) => token.text).join();
  context.macros.set(
    name,
    MacroDefinition.fromString(
      '\\operatorname${starred ? '*' : ''}{$text}',
    ),
  );
  return '';
}

const _lowerGreek = [
  'alpha', 'beta', 'gamma', 'delta', 'epsilon', 'zeta', 'eta', 'theta',
  'iota', 'kappa', 'lambda', 'mu', 'nu', 'xi', 'pi', 'rho', 'sigma', 'tau',
  'upsilon', 'phi', 'chi', 'psi', 'omega', 'varepsilon', 'vartheta',
  'varpi', 'varrho', 'varsigma', 'varphi',
];

final Map<String, MacroDefinition> amsMacros = {
  // Defining commands.
  '\\def': MacroDefinition.fromCtxString(
      (context) => _define(context, global: false)),
  '\\gdef': MacroDefinition.fromCtxString(
      (context) => _define(context, global: true)),
  '\\DeclareMathOperator': MacroDefinition.fromCtxString(_declareOperator),

  // Numbering, labels and references: one equation has no number to keep.
  '\\notag': MacroDefinition.fromString(''),
  '\\nonumber': MacroDefinition.fromString(''),
  '\\label': _ignoring(1),
  '\\eqref': MacroDefinition.fromString('(\\text{#1})'),
  '\\ref': MacroDefinition.fromString('\\text{#1}'),

  // amsmath.
  '\\iiiint': MacroDefinition.fromString(
      '\\mathop{\\int\\!\\!\\!\\!\\int\\!\\!\\!\\!\\int\\!\\!\\!\\!\\int}'
      '\\nolimits'),
  '\\idotsint': MacroDefinition.fromString(
      '\\mathop{\\int\\cdots\\int}\\nolimits'),
  '\\sideset': MacroDefinition.fromString('{}#1\\!\\mathop{#3}\\nolimits#2'),
  '\\varliminf': MacroDefinition.fromString(
      '\\mathop{\\underline{\\mathrm{lim}}}'),
  '\\varlimsup': MacroDefinition.fromString(
      '\\mathop{\\overline{\\mathrm{lim}}}'),
  '\\varinjlim': MacroDefinition.fromString(
      '\\mathop{\\underrightarrow{\\mathrm{lim}}}'),
  '\\varprojlim': MacroDefinition.fromString(
      '\\mathop{\\underleftarrow{\\mathrm{lim}}}'),
  '\\injlim': MacroDefinition.fromString(
      '\\DOTSB\\operatorname*{inj\\,lim}'),
  '\\projlim': MacroDefinition.fromString(
      '\\DOTSB\\operatorname*{proj\\,lim}'),
  '\\dddot': MacroDefinition.fromString('\\overset{\\cdot\\cdot\\cdot}{#1}'),
  '\\ddddot': MacroDefinition.fromString(
      '\\overset{\\cdot\\cdot\\cdot\\cdot}{#1}'),
  '\\smash': MacroDefinition.fromString('#1'),
  '\\mspace': MacroDefinition.fromString('\\mkern#1'),
  '\\intertext': MacroDefinition.fromString('\\text{#1}'),
  '\\shortintertext': MacroDefinition.fromString('\\text{#1}'),
  '\\shoveleft': MacroDefinition.fromString('#1'),
  '\\shoveright': MacroDefinition.fromString('#1'),
  '\\hdotsfor': MacroDefinition.fromCtxString((context) {
    context.consumeArgs(1);
    return '\\dots';
  }),

  // mathtools.
  '\\mathllap': MacroDefinition.fromString('#1'),
  '\\mathrlap': MacroDefinition.fromString('#1'),
  '\\mathclap': MacroDefinition.fromString('#1'),
  '\\prescript': MacroDefinition.fromString('{}^{#1}_{#2}{#3}'),

  // Text.
  '\\emph': MacroDefinition.fromString('\\textit{#1}'),

  // Fractions: xfrac and nicefrac. Units, siunitx's, are read only in
  // LaTeX brought in (aantekening_math's LatexPackages).
  '\\nicefrac': MacroDefinition.fromString('{}^{#1}\\!/\\!{}_{#2}'),
  '\\sfrac': MacroDefinition.fromString('{}^{#1}\\!/\\!{}_{#2}'),

  // upgreek: upright letters, set as the letters.
  for (final letter in _lowerGreek)
    '\\up$letter': MacroDefinition.fromString('\\$letter'),
};
