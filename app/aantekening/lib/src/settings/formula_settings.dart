/// How formulas are typed and typeset: when a source is typed in a window,
/// and the commands and TikZ styles every formula is given.
library;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../editor/text/formula_preamble.dart';
import '../editor/text/formula_window.dart';
import '../look/appearance.dart';
import '../look/controls.dart';
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
    final window = ref.watch(formulaWindowProvider);
    const range = FormulaWindow.most - FormulaWindow.least;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: <Widget>[
        SettingsSection(
          title: 'Source window',
          description:
              'A formula\'s source is typed beneath its line until it grows '
              'longer than this, and then in a window of its own; it goes '
              'back beneath its line once it is '
              '${FormulaWindow.margin} characters shorter. A source on more '
              'than one line is always typed in the window.',
          children: <Widget>[
            SettingRow(
              label: 'Longer than',
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: <Widget>[
                  LevelSlider(
                    label: 'Source window',
                    value: (window.opensPast - FormulaWindow.least) / range,
                    // In steps of ten characters.
                    onChanged: (level) => ref
                        .read(formulaWindowProvider.notifier)
                        .set(
                          ((FormulaWindow.least + level * range) / 10).round() *
                              10,
                        ),
                  ),
                  const SizedBox(width: 12),
                  Text(
                    '${window.opensPast} characters',
                    style: const TextStyle(fontSize: 12.5),
                  ),
                ],
              ),
            ),
          ],
        ),
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
