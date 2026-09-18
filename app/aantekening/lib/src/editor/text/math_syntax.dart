/// Which syntax formulas are typed in.
library;

import 'dart:async';

import 'package:aantekening_core/aantekening_core.dart';
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
  MathMode build() {
    final saved = ref.watch(preferencesProvider).value?[_key];
    return saved == 'latex' ? MathMode.latex : MathMode.linear;
  }

  void set(MathMode syntax) {
    if (state == syntax) return;
    state = syntax;
    final preferences = ref.read(preferencesProvider).value;
    if (preferences != null) {
      unawaited(
        preferences.set(_key, syntax == MathMode.latex ? 'latex' : null),
      );
    }
  }

  void toggle() =>
      set(state == MathMode.latex ? MathMode.linear : MathMode.latex);
}

final mathSyntaxProvider = NotifierProvider<MathSyntaxController, MathMode>(
  MathSyntaxController.new,
);
