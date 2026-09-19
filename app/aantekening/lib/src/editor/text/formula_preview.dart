/// The formula being edited, typeset beneath the line it is typed on.
library;

import 'package:aantekening_core/aantekening_core.dart';
import 'package:aantekening_math/aantekening_math.dart';
import 'package:flutter/material.dart';

import 'math_syntax.dart';
import 'text_box_controller.dart';
import 'text_styles.dart';

/// Shows the formula being typed in a text box as it will look, with the
/// switch between Simple and LaTeX syntax and a button to finish it.
///
/// The formula is typed in the box itself; nothing here takes the keyboard,
/// so clicking the switch or the button leaves the caret where it was.
class FormulaPreview extends StatelessWidget {
  const FormulaPreview({
    required this.session,
    required this.onDone,
    super.key,
  });

  final FormulaSession session;
  final VoidCallback onDone;

  /// The narrowest and widest the preview is. In between it is as wide as
  /// the source typed above it.
  static const double minWidth = 240;
  static const double maxWidth = 560;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final error = session.error;

    return ExcludeFocus(
      child: Material(
        elevation: 2,
        shadowColor: Colors.black26,
        color: scheme.surfaceContainerHigh,
        borderRadius: BorderRadius.circular(10),
        child: Container(
          padding: const EdgeInsets.all(5),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(10),
            border: Border.all(color: scheme.outlineVariant),
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: <Widget>[
              _Typeset(latex: session.latex),
              if (error != null)
                Padding(
                  padding: const EdgeInsets.fromLTRB(4, 5, 4, 0),
                  child: Row(
                    children: <Widget>[
                      Icon(
                        Icons.error_outline_rounded,
                        size: 13,
                        color: scheme.error,
                      ),
                      const SizedBox(width: 5),
                      Expanded(
                        child: Text(
                          error,
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(fontSize: 11.5, color: scheme.error),
                        ),
                      ),
                    ],
                  ),
                ),
              const SizedBox(height: 5),
              // The switch on the left, Done on the right; on a narrow
              // screen Done goes beneath rather than overflowing.
              Wrap(
                alignment: WrapAlignment.spaceBetween,
                crossAxisAlignment: WrapCrossAlignment.center,
                runSpacing: 4,
                children: <Widget>[
                  const MathSyntaxToggle(),
                  Tooltip(
                    message: 'Done  (Enter)',
                    child: TextButton.icon(
                      onPressed: onDone,
                      icon: const Icon(Icons.check_rounded, size: 15),
                      label: const Text('Done'),
                      style: TextButton.styleFrom(
                        minimumSize: const Size(0, 26),
                        padding: const EdgeInsets.symmetric(horizontal: 8),
                        tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                        visualDensity: VisualDensity.compact,
                        textStyle: Theme.of(context).textTheme.labelMedium
                            ?.copyWith(fontWeight: FontWeight.w600),
                      ),
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// The formula typeset on white paper, as it will be on the page.
class _Typeset extends StatelessWidget {
  const _Typeset({required this.latex});

  final String latex;

  @override
  Widget build(BuildContext context) {
    return Container(
      constraints: const BoxConstraints(minHeight: 40, maxHeight: 180),
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(6),
      ),
      // Only as tall as the formula: centring it must not fill the space
      // it is allowed.
      child: Center(
        heightFactor: 1,
        child: latex.trim().isEmpty
            ? Text(
                'Type a formula',
                style: TextStyle(
                  fontSize: 13,
                  fontStyle: FontStyle.italic,
                  color: Colors.black.withValues(alpha: 0.4),
                ),
              )
            : FittedBox(
                fit: BoxFit.scaleDown,
                child: MathView(
                  source: latex,
                  mode: MathMode.latex,
                  textStyle: const TextStyle(
                    fontSize: 20,
                    color: RichTextStyles.ink,
                  ),
                ),
              ),
      ),
    );
  }
}
