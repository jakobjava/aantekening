part of 'page_editor.dart';

/// Where the page goes while none is open: what to do instead.
class _NoPageSelected extends ConsumerWidget {
  const _NoPageSelected();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final tones = context.tones;
    final bindings = ref.watch(shortcutsProvider);
    Widget line(AppCommand command, String what) => Padding(
      padding: const EdgeInsets.symmetric(vertical: 3),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: <Widget>[
          SizedBox(
            width: 170,
            child: Text(
              what,
              style: TextStyle(fontSize: 13, color: tones.muted),
            ),
          ),
          SizedBox(
            width: 120,
            child: KeyHint(
              bindings.of(command).firstOrNull?.label ?? '',
              color: tones.text,
            ),
          ),
        ],
      ),
    );
    return ColoredBox(
      color: tones.base,
      child: Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: <Widget>[
            line(AppCommand.goTo, 'Go to a page'),
            line(AppCommand.newPage, 'New page'),
            line(AppCommand.search, 'Search every page'),
            line(AppCommand.commands, 'Every command'),
            line(AppCommand.settings, 'Settings'),
          ],
        ),
      ),
    );
  }
}

class _ErrorBanner extends StatelessWidget {
  const _ErrorBanner({required this.error});

  final String error;

  @override
  Widget build(BuildContext context) {
    final tones = context.tones;
    return Container(
      width: double.infinity,
      decoration: BoxDecoration(
        color: tones.base,
        border: Border(bottom: BorderSide(color: tones.strongLine)),
      ),
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
      child: Text(error, style: TextStyle(fontSize: 12, color: tones.text)),
    );
  }
}

/// Places the formula panel beneath the formula being edited, or above it
/// when there is no room below, always within the view: its left edge under
/// the source's, and as wide as that where it is wider than the panel's
/// least width.
class _BelowFormula extends SingleChildLayoutDelegate {
  _BelowFormula(this.formula) : super(relayout: formula);

  /// Where the formula is on screen.
  final ValueListenable<Rect?> formula;

  static const double _gap = 6;
  static const double _margin = 8;

  /// As wide as the source above it, within the preview's limits.
  @override
  BoxConstraints getConstraintsForChild(BoxConstraints constraints) {
    final available = math.max(0.0, constraints.maxWidth - 2 * _margin);
    final source = formula.value?.width ?? 0;
    final width = math.min(
      available,
      source.clamp(FormulaPreview.minWidth, FormulaPreview.maxWidth),
    );
    return BoxConstraints(
      minWidth: width,
      maxWidth: width,
      maxHeight: math.max(0, constraints.maxHeight - 2 * _margin),
    );
  }

  @override
  Offset getPositionForChild(Size size, Size childSize) {
    final anchor = formula.value ?? const Rect.fromLTWH(24, 24, 0, 0);
    final x = anchor.left
        .clamp(
          _margin,
          math.max(_margin, size.width - childSize.width - _margin),
        )
        .toDouble();
    var y = anchor.bottom + _gap;
    final above = anchor.top - _gap - childSize.height;
    if (y + childSize.height > size.height - _margin && above >= _margin) {
      y = above;
    }
    y = y
        .clamp(
          _margin,
          math.max(_margin, size.height - childSize.height - _margin),
        )
        .toDouble();
    return Offset(x, y);
  }

  @override
  bool shouldRelayout(_BelowFormula oldDelegate) =>
      !identical(oldDelegate.formula, formula);
}
