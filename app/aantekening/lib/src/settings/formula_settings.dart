/// How formulas are typeset: the commands and TikZ styles every one is
/// given.
library;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../editor/text/formula_preamble.dart';
import '../look/appearance.dart';
import '../look/tones.dart';
import 'settings_view.dart';

/// The formulas page of the settings.
class FormulaSettings extends ConsumerStatefulWidget {
  const FormulaSettings({super.key});

  @override
  ConsumerState<FormulaSettings> createState() => _FormulaSettingsState();
}

class _FormulaSettingsState extends ConsumerState<FormulaSettings> {
  late final TextEditingController _source = TextEditingController(
    text: ref.read(formulaPreambleSourceProvider),
  );

  @override
  void dispose() {
    _source.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final tones = context.tones;
    final leftOver = ref.watch(
      formulaPreambleProvider.select((preamble) => preamble.leftOver),
    );
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: <Widget>[
        SettingsSection(
          title: 'Preamble',
          description:
              'Commands and styles every formula is typeset with, as at the '
              r'top of a LaTeX document: \newcommand, \DeclareMathOperator '
              r'and \def, and \tikzset for TikZ pictures. A formula keeps '
              'what it says written in it; one brought in as LaTeX can also '
              'use physics, mhchem and siunitx.',
          children: <Widget>[
            TextField(
              controller: _source,
              minLines: 8,
              maxLines: 16,
              keyboardType: TextInputType.multiline,
              style: TextStyle(
                fontFamily: InterfaceFont.mono.family,
                fontSize: 13,
              ),
              decoration: const InputDecoration(
                hintText:
                    '\\newcommand{\\Rn}{\\mathbb{R}^n}\n'
                    '\\DeclareMathOperator{\\sgn}{sgn}\n'
                    '\\tikzset{dot/.style={circle, fill, inner sep=1.5pt}}',
              ),
              onChanged: ref.read(formulaPreambleSourceProvider.notifier).set,
            ),
            if (leftOver.isNotEmpty)
              Padding(
                padding: const EdgeInsets.only(top: 6),
                child: Text(
                  'Not read, being neither a command nor a style: $leftOver',
                  style: TextStyle(fontSize: 12, color: tones.muted),
                ),
              ),
          ],
        ),
      ],
    );
  }
}
