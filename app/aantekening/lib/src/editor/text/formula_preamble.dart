/// The person's own preamble: commands and TikZ styles every formula is
/// typeset with.
library;

import 'package:aantekening_core/aantekening_core.dart';
import 'package:aantekening_math/aantekening_math.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../preferences.dart';

/// The preamble as written: `\newcommand`s, `\DeclareMathOperator`s,
/// `\def`s and `\tikzset`s.
class FormulaPreambleController extends Notifier<String> {
  static const String _key = 'math.preamble';

  @override
  String build() => ref.preference(_key) as String? ?? '';

  void set(String source) {
    if (state == source) return;
    state = source;
    ref.savePreference(_key, source.trim().isEmpty ? null : source);
  }
}

final formulaPreambleSourceProvider =
    NotifierProvider<FormulaPreambleController, String>(
      FormulaPreambleController.new,
    );

/// The preamble as read, to be written into every formula.
final formulaPreambleProvider = Provider<LatexPreamble>(
  (ref) => LatexPreamble.read(ref.watch(formulaPreambleSourceProvider)),
);

/// Gives every formula beneath it the person's preamble.
class FormulaPreambleScope extends ConsumerWidget {
  const FormulaPreambleScope({required this.child, super.key});

  final Widget child;

  @override
  Widget build(BuildContext context, WidgetRef ref) =>
      MathPreamble(preamble: ref.watch(formulaPreambleProvider), child: child);
}
