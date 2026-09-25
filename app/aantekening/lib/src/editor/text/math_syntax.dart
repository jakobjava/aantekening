/// Which syntax formulas are typed in, and the switch between them.
library;

import 'package:aantekening_core/aantekening_core.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../commands/editor_keys.dart';
import '../../look/controls.dart';
import '../../preferences.dart';

/// The syntax formulas are typed in: Simple or LaTeX.
///
/// A preference of the person rather than a property of each formula, since
/// every formula is stored as LaTeX and shown in whichever syntax is chosen.
/// Switching it while a formula is open translates that formula.
class MathSyntaxController extends Notifier<MathMode> {
  static const String _key = 'math.syntax';

  @override
  MathMode build() =>
      ref.preference(_key) == 'latex' ? MathMode.latex : MathMode.linear;

  void set(MathMode syntax) {
    if (state == syntax) return;
    state = syntax;
    ref.savePreference(_key, syntax == MathMode.latex ? 'latex' : null);
  }

  void toggle() =>
      set(state == MathMode.latex ? MathMode.linear : MathMode.latex);
}

final mathSyntaxProvider = NotifierProvider<MathSyntaxController, MathMode>(
  MathSyntaxController.new,
);

/// The switch between Simple and LaTeX syntax, as the Math tab and the
/// formula being edited show it.
class MathSyntaxToggle extends ConsumerWidget {
  const MathSyntaxToggle({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) => ChoiceRow<MathMode>(
    choices: const <MathMode>[MathMode.linear, MathMode.latex],
    selected: ref.watch(mathSyntaxProvider),
    compact: true,
    labelOf: (mode) => switch (mode) {
      MathMode.linear => 'Simple',
      MathMode.latex => 'LaTeX',
    },
    tooltipOf: (mode) => EditorKey.formulaSyntax.tooltipOf(switch (mode) {
      MathMode.linear =>
        'Type it as you would say it: x^2, a/b, sqrt(x), sum_(i=1)^n',
      MathMode.latex =>
        r'Type LaTeX, as formulas are stored: x^{2}, \frac{a}{b}',
    }),
    onSelected: ref.read(mathSyntaxProvider.notifier).set,
  );
}
