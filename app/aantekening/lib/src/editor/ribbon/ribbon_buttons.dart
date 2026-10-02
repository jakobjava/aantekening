part of 'ribbon_items.dart';

/// What every ribbon button is: lit under the pointer, shaded with a line
/// beneath while what it turns on is on, and greyed out while it has
/// nothing to act on.
class _Pressable extends StatelessWidget {
  const _Pressable({
    required this.tooltip,
    required this.onPressed,
    required this.selected,
    required this.child,
  });

  final String tooltip;
  final VoidCallback? onPressed;
  final bool selected;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    final tones = context.tones;
    final enabled = onPressed != null;
    final foreground = enabled ? tones.text : tones.faint;
    return Tooltip(
      message: tooltip,
      child: Semantics(
        button: true,
        selected: selected,
        enabled: enabled,
        child: Material(
          color: selected ? tones.selection : Colors.transparent,
          child: InkWell(
            onTap: onPressed,
            child: DecoratedBox(
              position: DecorationPosition.foreground,
              decoration: BoxDecoration(
                border: selected
                    ? Border(
                        bottom: BorderSide(color: tones.emphasis, width: 2),
                      )
                    : null,
              ),
              child: IconTheme.merge(
                data: IconThemeData(color: foreground),
                child: DefaultTextStyle.merge(
                  style: TextStyle(
                    fontSize: 12,
                    height: 1.2,
                    fontWeight: selected ? FontWeight.w600 : FontWeight.w500,
                    color: foreground,
                  ),
                  child: child,
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// A button one row high, showing [face]: its name, or a letter.
class RibbonButton extends StatelessWidget {
  const RibbonButton({
    required this.face,
    required this.tooltip,
    required this.onPressed,
    this.selected = false,
    this.padding = const EdgeInsets.symmetric(horizontal: 7),
    super.key,
  });

  final Widget face;
  final String tooltip;
  final VoidCallback? onPressed;
  final bool selected;
  final EdgeInsetsGeometry padding;

  @override
  Widget build(BuildContext context) => SizedBox(
    height: RibbonMetrics.row,
    child: _Pressable(
      tooltip: tooltip,
      onPressed: onPressed,
      selected: selected,
      child: ConstrainedBox(
        constraints: const BoxConstraints(minWidth: RibbonMetrics.row),
        child: Padding(
          padding: padding,
          child: Center(widthFactor: 1, child: face),
        ),
      ),
    ),
  );
}

/// A tall button: its name, under its icon, or under a [glyph] where there
/// is more to show — the pen's colour, the zoom, a formula.
class RibbonLargeButton extends StatelessWidget {
  const RibbonLargeButton({
    required this.label,
    required this.tooltip,
    required this.onPressed,
    this.glyph,
    this.icon,
    this.selected = false,
    super.key,
  });

  final String label;

  /// What is shown over the name: [icon], unless something more is to be
  /// shown.
  final Widget? glyph;
  final AppIcon? icon;
  final String tooltip;
  final VoidCallback? onPressed;
  final bool selected;

  @override
  Widget build(BuildContext context) {
    final icon = this.icon;
    final glyph =
        this.glyph ?? (icon == null ? null : AppIconView(icon, size: 20));
    final name = ConstrainedBox(
      constraints: const BoxConstraints(
        maxWidth: RibbonMetrics.largeLabelWidth,
      ),
      child: Text(
        label,
        maxLines: 2,
        textAlign: TextAlign.center,
        style: TextStyle(fontSize: glyph == null ? 12.5 : 11),
      ),
    );
    return SizedBox(
      height: RibbonMetrics.content,
      child: _Pressable(
        tooltip: tooltip,
        onPressed: onPressed,
        selected: selected,
        child: ConstrainedBox(
          constraints: const BoxConstraints(minWidth: 48),
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 8),
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              mainAxisSize: MainAxisSize.min,
              children: <Widget>[
                if (glyph != null) ...<Widget>[
                  SizedBox(height: 26, child: Center(child: glyph)),
                  const SizedBox(height: 3),
                ],
                name,
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// [child] over a bar of [color]: the colour a button applies, or the
/// pen's.
class ColourBar extends StatelessWidget {
  const ColourBar({required this.color, this.child, super.key});

  final int color;
  final Widget? child;

  @override
  Widget build(BuildContext context) => Column(
    mainAxisSize: MainAxisSize.min,
    children: <Widget>[
      ?child,
      Container(
        width: 18,
        height: 4,
        margin: const EdgeInsets.only(top: 1),
        foregroundDecoration: BoxDecoration(
          border: Border.all(color: context.tones.line, width: 0.5),
        ),
        child: color == NoteColors.inverse
            ? const CustomPaint(painter: InverseHalves())
            : ColoredBox(color: Color(color | 0xFF000000)),
      ),
    ],
  );
}
