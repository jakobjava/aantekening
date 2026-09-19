/// Which syntax formulas are typed in, and the switch between them.
library;

import 'package:aantekening_core/aantekening_core.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

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
  Widget build(BuildContext context, WidgetRef ref) {
    final scheme = Theme.of(context).colorScheme;
    final syntax = ref.watch(mathSyntaxProvider);

    Widget segment(MathMode value, String label, String tooltip) {
      final selected = syntax == value;
      return Tooltip(
        message: '$tooltip\nCtrl+Shift+M switches',
        child: InkWell(
          onTap: selected
              ? null
              : () => ref.read(mathSyntaxProvider.notifier).set(value),
          child: Container(
            height: 24,
            padding: const EdgeInsets.symmetric(horizontal: 9),
            alignment: Alignment.center,
            color: selected ? scheme.primary.withValues(alpha: 0.14) : null,
            child: Text(
              label,
              style: TextStyle(
                fontSize: 11.5,
                fontWeight: selected ? FontWeight.w600 : FontWeight.w400,
                color: selected ? scheme.primary : scheme.onSurfaceVariant,
              ),
            ),
          ),
        ),
      );
    }

    return DecoratedBox(
      decoration: BoxDecoration(
        border: Border.all(color: scheme.outlineVariant),
        borderRadius: BorderRadius.circular(6),
      ),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(5),
        child: Material(
          type: MaterialType.transparency,
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: <Widget>[
              segment(
                MathMode.linear,
                'Simple',
                'Type it as you would say it: x^2, a/b, sqrt(x), sum_(i=1)^n',
              ),
              segment(
                MathMode.latex,
                'LaTeX',
                r'Type LaTeX, as formulas are stored: x^{2}, \frac{a}{b}',
              ),
            ],
          ),
        ),
      ),
    );
  }
}
