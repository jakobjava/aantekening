/// Widgets that typeset a formula from either authoring mode.
library;

import 'package:aantekening_core/aantekening_core.dart';
import 'package:flutter/material.dart';
import 'package:flutter_math_fork/flutter_math.dart';

import 'linear_math.dart';
import 'renderer_latex.dart';

/// Renders a formula written in [mode].
///
/// Typesetting happens natively through flutter_math_fork rather than in a web
/// view: it keeps formulas as fast to paint as any other element on the canvas,
/// and it works identically on Linux, Windows and Android.
class MathView extends StatelessWidget {
  const MathView({
    required this.source,
    required this.mode,
    super.key,
    this.displayStyle = true,
    this.textStyle,
  });

  /// Renders the formula held by [element].
  factory MathView.element(MathElement element, {Key? key, TextStyle? style}) =>
      MathView(
        key: key,
        source: element.source,
        mode: element.mode,
        displayStyle: element.displayStyle,
        textStyle: style,
      );

  /// The formula, in whichever syntax [mode] names.
  final String source;

  final MathMode mode;

  /// Display style centres the formula and uses full-size operators; inline
  /// style keeps it on the text baseline.
  final bool displayStyle;

  final TextStyle? textStyle;

  @override
  Widget build(BuildContext context) {
    if (source.trim().isEmpty) {
      return _Placeholder(style: textStyle);
    }

    return Math.tex(
      RendererLatex.of(LinearMath.latexFor(mode, source)),
      mathStyle: displayStyle ? MathStyle.display : MathStyle.text,
      textStyle: textStyle ?? DefaultTextStyle.of(context).style,
      // A formula that TeX itself rejects still has to show something, or the
      // page would appear to lose content while it is being edited.
      onErrorFallback: (error) => _MathError(
        message: error.messageWithType,
        source: source,
        style: textStyle,
      ),
    );
  }
}

class _Placeholder extends StatelessWidget {
  const _Placeholder({this.style});

  final TextStyle? style;

  @override
  Widget build(BuildContext context) {
    final color = Theme.of(context).colorScheme.outline;
    return Text(
      '□',
      style: (style ?? DefaultTextStyle.of(context).style).copyWith(
        color: color,
      ),
    );
  }
}

class _MathError extends StatelessWidget {
  const _MathError({required this.message, required this.source, this.style});

  final String message;
  final String source;
  final TextStyle? style;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Tooltip(
      message: message,
      child: DecoratedBox(
        decoration: BoxDecoration(
          color: scheme.errorContainer.withValues(alpha: 0.4),
          borderRadius: BorderRadius.circular(4),
        ),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 2),
          child: Text(
            source,
            style: (style ?? DefaultTextStyle.of(context).style).copyWith(
              fontFamily: 'monospace',
              color: scheme.onErrorContainer,
            ),
          ),
        ),
      ),
    );
  }
}
