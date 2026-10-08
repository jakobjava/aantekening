/// Asking for LaTeX to put into the notes: a passage, or a whole document.
library;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../look/appearance.dart';
import '../look/motion.dart';
import '../look/tones.dart';

/// Asks for LaTeX — as many lines of it as there are, a whole document
/// with its preamble if need be — returning what was given, or null if
/// nothing was.
Future<String?> askForLatex(BuildContext context) => showAppDialog<String>(
  context: context,
  builder: (context) => const _LatexDialog(),
);

class _LatexDialog extends StatefulWidget {
  const _LatexDialog();

  @override
  State<_LatexDialog> createState() => _LatexDialogState();
}

class _LatexDialogState extends State<_LatexDialog> {
  final TextEditingController _source = TextEditingController();

  @override
  void dispose() {
    _source.dispose();
    super.dispose();
  }

  void _insert() {
    final source = _source.text;
    Navigator.of(context).pop(source.trim().isEmpty ? null : source);
  }

  @override
  Widget build(BuildContext context) {
    final tones = context.tones;
    return CallbackShortcuts(
      // Enter is a new line; Ctrl+Enter puts the LaTeX in.
      bindings: <ShortcutActivator, VoidCallback>{
        const SingleActivator(LogicalKeyboardKey.enter, control: true): _insert,
        const SingleActivator(LogicalKeyboardKey.numpadEnter, control: true):
            _insert,
      },
      child: AlertDialog(
        title: const Text('Insert LaTeX'),
        content: SizedBox(
          width: 560,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: <Widget>[
              Text(
                'Text and formulas — \$…\$ in a line, \\[…\\] or align and '
                'the other environments on lines of their own — sections, '
                'lists, tables and TikZ pictures. Commands defined with '
                '\\newcommand are written out; physics, mhchem and siunitx '
                'are read. What is brought in stays LaTeX.',
                style: TextStyle(fontSize: 12, color: tones.muted),
              ),
              const SizedBox(height: 10),
              TextField(
                controller: _source,
                autofocus: true,
                minLines: 12,
                maxLines: 20,
                keyboardType: TextInputType.multiline,
                style: TextStyle(
                  fontFamily: InterfaceFont.mono.family,
                  fontSize: 13,
                ),
                decoration: const InputDecoration(
                  hintText:
                      'Let \$f(x) = x^2\$. Then\n'
                      '\\begin{align*}\n'
                      "  f'(x) &= 2x \\\\\n"
                      "  f''(x) &= 2\n"
                      '\\end{align*}',
                ),
              ),
            ],
          ),
        ),
        actions: <Widget>[
          TextButton(
            onPressed: () => Navigator.of(context).pop(),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: _insert,
            child: const Text('Insert  (Ctrl+Enter)'),
          ),
        ],
      ),
    );
  }
}
