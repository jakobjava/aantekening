/// The controls the interface is built from, the same wherever they are
/// used: rows to pick from, buttons with a mark, choices, switches,
/// swatches, labels, shortcuts and a sign of work going on.
library;

import 'package:flutter/material.dart';

import 'marks.dart';
import 'tones.dart';

/// A square button showing a [Mark]: closing a tab, adding a notebook,
/// stepping through what was found.
class MarkButton extends StatelessWidget {
  const MarkButton(
    this.shape, {
    required this.tooltip,
    required this.onPressed,
    this.size = 24,
    this.markSize = 12,
    this.selected = false,
    super.key,
  });

  final MarkShape shape;
  final String tooltip;
  final VoidCallback? onPressed;
  final double size;
  final double markSize;

  /// Whether what it turns on is on, shown as the row picked is.
  final bool selected;

  @override
  Widget build(BuildContext context) {
    final tones = context.tones;
    return SizedBox.square(
      dimension: size,
      child: IconButton(
        tooltip: tooltip,
        onPressed: onPressed,
        style: IconButton.styleFrom(
          minimumSize: Size.square(size),
          fixedSize: Size.square(size),
          backgroundColor: selected ? tones.selection : null,
        ),
        icon: Mark(shape, size: markSize),
      ),
    );
  }
}

/// A small text button: a pane's New, a heading's Clear.
class SmallButton extends StatelessWidget {
  const SmallButton(
    this.label, {
    required this.onPressed,
    this.tooltip,
    super.key,
  });

  final String label;
  final VoidCallback? onPressed;
  final String? tooltip;

  @override
  Widget build(BuildContext context) {
    final button = TextButton(
      onPressed: onPressed,
      style: TextButton.styleFrom(
        minimumSize: const Size(0, 22),
        padding: const EdgeInsets.symmetric(horizontal: 6),
        textStyle: Theme.of(context).textTheme.labelMedium,
        foregroundColor: context.tones.muted,
      ),
      child: Text(label, maxLines: 1, overflow: TextOverflow.ellipsis),
    );
    final tooltip = this.tooltip;
    return tooltip == null ? button : Tooltip(message: tooltip, child: button);
  }
}

/// A pane's title, with a button for its main command: making something
/// new, unless it says otherwise.
class PaneHeader extends StatelessWidget {
  const PaneHeader({
    required this.title,
    this.action = 'New',
    this.actionTooltip,
    this.onAction,
    this.trailing,
    super.key,
  });

  final String title;

  /// The command's name, on its button.
  final String action;
  final String? actionTooltip;

  /// Carries out the command, or null while it has nothing to act on. Without
  /// one, and without [trailing], the header has no button.
  final VoidCallback? onAction;

  /// In place of the button.
  final Widget? trailing;

  static const double height = 34;

  @override
  Widget build(BuildContext context) => SizedBox(
    height: height,
    child: Padding(
      padding: const EdgeInsets.only(left: 12, right: 4),
      child: Row(
        children: <Widget>[
          Expanded(child: SmallCaps(title)),
          ?trailing,
          if (trailing == null && (onAction != null || actionTooltip != null))
            SmallButton(action, tooltip: actionTooltip, onPressed: onAction),
        ],
      ),
    ),
  );
}

/// A label in capitals, spaced out, over a part of a pane or a page.
class SmallCaps extends StatelessWidget {
  const SmallCaps(this.text, {this.color, super.key});

  final String text;
  final Color? color;

  @override
  Widget build(BuildContext context) => Text(
    text.toUpperCase(),
    maxLines: 1,
    overflow: TextOverflow.ellipsis,
    style: TextStyle(
      fontSize: 10.5,
      letterSpacing: 0.9,
      fontWeight: FontWeight.w600,
      color: color ?? context.tones.muted,
    ),
  );
}

/// A shortcut, as it is typed — "Ctrl+Shift+P" — quietly, beside what it
/// does.
class KeyHint extends StatelessWidget {
  const KeyHint(this.keys, {this.color, super.key});

  final String keys;
  final Color? color;

  @override
  Widget build(BuildContext context) => Text(
    keys,
    maxLines: 1,
    style: TextStyle(
      fontSize: 11.5,
      fontFeatures: const <FontFeature>[FontFeature.tabularFigures()],
      color: color ?? context.tones.muted,
    ),
  );
}

/// A row to pick: a notebook, a page, something found, a setting's page.
///
/// Everything listed to be picked from is one of these, so every list looks
/// and answers alike: lit under the pointer, shaded with a bar at its edge
/// when picked, outlined when the keyboard is on it.
class RowTile extends StatefulWidget {
  const RowTile({
    required this.title,
    this.subtitle,
    this.leading,
    this.trailing,
    this.selected = false,
    this.onTap,
    this.titleStyle,
    this.subtitleLines = 1,
    this.padding = const EdgeInsets.symmetric(horizontal: 8, vertical: 5),
    this.focusNode,
    this.autofocus = false,
    super.key,
  });

  final Widget title;
  final Widget? subtitle;
  final Widget? leading;
  final Widget? trailing;
  final bool selected;
  final VoidCallback? onTap;

  /// Merged into the title's style.
  final TextStyle? titleStyle;
  final int subtitleLines;
  final EdgeInsetsGeometry padding;
  final FocusNode? focusNode;
  final bool autofocus;

  @override
  State<RowTile> createState() => _RowTileState();
}

class _RowTileState extends State<RowTile> {
  bool _focused = false;

  @override
  Widget build(BuildContext context) {
    final tones = context.tones;
    final selected = widget.selected;
    return Material(
      color: selected ? tones.selection : Colors.transparent,
      child: InkWell(
        onTap: widget.onTap,
        focusNode: widget.focusNode,
        autofocus: widget.autofocus,
        onFocusChange: (focused) => setState(() => _focused = focused),
        child: DecoratedBox(
          position: DecorationPosition.foreground,
          decoration: BoxDecoration(
            border: _focused
                ? Border.all(color: tones.emphasis)
                : selected
                ? Border(left: BorderSide(color: tones.emphasis, width: 2))
                : null,
          ),
          child: Padding(
            padding: widget.padding,
            child: Row(
              children: <Widget>[
                if (widget.leading case final leading?) ...<Widget>[
                  leading,
                  const SizedBox(width: 8),
                ],
                Expanded(
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: <Widget>[
                      DefaultTextStyle.merge(
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          fontSize: 13,
                          color: tones.text,
                          fontWeight: selected ? FontWeight.w600 : null,
                        ).merge(widget.titleStyle),
                        child: widget.title,
                      ),
                      if (widget.subtitle case final subtitle?)
                        DefaultTextStyle.merge(
                          maxLines: widget.subtitleLines,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(
                            fontSize: 11.5,
                            height: 1.35,
                            color: tones.muted,
                          ),
                          child: subtitle,
                        ),
                    ],
                  ),
                ),
                if (widget.trailing case final trailing?) ...<Widget>[
                  const SizedBox(width: 6),
                  trailing,
                ],
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// One of a few choices, side by side, the one chosen filled in.
class ChoiceRow<T> extends StatelessWidget {
  const ChoiceRow({
    required this.choices,
    required this.selected,
    required this.onSelected,
    this.labelOf,
    this.tooltipOf,
    this.compact = false,
    super.key,
  });

  final List<T> choices;
  final T selected;
  final ValueChanged<T> onSelected;

  /// What [choice] is called; its string otherwise.
  final String Function(T choice)? labelOf;

  /// What [choice] means, shown while the pointer is on it.
  final String Function(T choice)? tooltipOf;

  /// Smaller, to fit a row of the ribbon.
  final bool compact;

  @override
  Widget build(BuildContext context) {
    final tones = context.tones;
    return DecoratedBox(
      decoration: BoxDecoration(border: Border.all(color: tones.strongLine)),
      child: IntrinsicHeight(
        child: Row(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: <Widget>[
            for (final (index, choice) in choices.indexed) ...<Widget>[
              if (index > 0) VerticalDivider(width: 1, color: tones.strongLine),
              _Choice(
                label: labelOf?.call(choice) ?? '$choice',
                tooltip: tooltipOf?.call(choice),
                chosen: choice == selected,
                compact: compact,
                onTap: () => onSelected(choice),
              ),
            ],
          ],
        ),
      ),
    );
  }
}

class _Choice extends StatelessWidget {
  const _Choice({
    required this.label,
    required this.tooltip,
    required this.chosen,
    required this.compact,
    required this.onTap,
  });

  final String label;
  final String? tooltip;
  final bool chosen;
  final bool compact;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final tones = context.tones;
    final choice = Semantics(
      selected: chosen,
      button: true,
      child: Material(
        color: chosen ? tones.emphasis : Colors.transparent,
        child: InkWell(
          onTap: chosen ? null : onTap,
          child: Padding(
            padding: compact
                ? const EdgeInsets.symmetric(horizontal: 9, vertical: 3)
                : const EdgeInsets.symmetric(horizontal: 11, vertical: 5),
            child: Text(
              label,
              style: TextStyle(
                fontSize: compact ? 11.5 : 12.5,
                fontWeight: FontWeight.w500,
                color: chosen ? tones.onEmphasis : tones.text,
              ),
            ),
          ),
        ),
      ),
    );
    final tooltip = this.tooltip;
    return tooltip == null ? choice : Tooltip(message: tooltip, child: choice);
  }
}

/// A setting that is on or off: a box to tick, what it is, and what it
/// does.
class CheckRow extends StatelessWidget {
  const CheckRow({
    required this.title,
    required this.value,
    required this.onChanged,
    this.description,
    super.key,
  });

  final String title;
  final String? description;
  final bool value;
  final ValueChanged<bool>? onChanged;

  @override
  Widget build(BuildContext context) {
    final tones = context.tones;
    final onChanged = this.onChanged;
    return InkWell(
      onTap: onChanged == null ? null : () => onChanged(!value),
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 6),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: <Widget>[
            SizedBox(
              width: 18,
              height: 18,
              child: Checkbox(
                value: value,
                onChanged: onChanged == null
                    ? null
                    : (value) => onChanged(value ?? false),
              ),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: <Widget>[
                  Text(
                    title,
                    style: TextStyle(fontSize: 13, color: tones.text),
                  ),
                  if (description case final description?)
                    Padding(
                      padding: const EdgeInsets.only(top: 2),
                      child: Text(
                        description,
                        style: TextStyle(
                          fontSize: 12,
                          height: 1.4,
                          color: tones.muted,
                        ),
                      ),
                    ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// A colour to pick: a square, ringed when it is the one chosen.
class Swatch extends StatelessWidget {
  const Swatch({
    required this.color,
    required this.name,
    required this.selected,
    required this.onTap,
    this.size = 20,
    super.key,
  });

  final Color color;
  final String name;
  final bool selected;
  final VoidCallback? onTap;
  final double size;

  @override
  Widget build(BuildContext context) {
    final tones = context.tones;
    return Tooltip(
      message: name,
      child: InkWell(
        onTap: onTap,
        child: Container(
          padding: const EdgeInsets.all(2),
          decoration: BoxDecoration(
            border: Border.all(
              color: selected ? tones.emphasis : Colors.transparent,
              width: 1.5,
            ),
          ),
          child: Container(
            width: size,
            height: size,
            decoration: BoxDecoration(
              color: color,
              border: Border.all(color: tones.line),
            ),
          ),
        ),
      ),
    );
  }
}

/// That something is being worked on: a short bar running along a line.
class Busy extends StatefulWidget {
  const Busy({this.width = 16, super.key});

  final double width;

  @override
  State<Busy> createState() => _BusyState();
}

class _BusyState extends State<Busy> with SingleTickerProviderStateMixin {
  late final AnimationController _run = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 1100),
  )..repeat();

  @override
  void dispose() {
    _run.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final tones = context.tones;
    return Semantics(
      label: 'Working',
      child: SizedBox(
        width: widget.width,
        height: 2,
        child: CustomPaint(
          painter: _BusyPainter(_run, tones.emphasis, tones.line),
        ),
      ),
    );
  }
}

class _BusyPainter extends CustomPainter {
  _BusyPainter(this.run, this.color, this.track) : super(repaint: run);

  final Animation<double> run;
  final Color color;
  final Color track;

  @override
  void paint(Canvas canvas, Size size) {
    canvas.drawRect(Offset.zero & size, Paint()..color = track);
    final length = size.width * 0.4;
    final start = Curves.easeInOut.transform(run.value) * (size.width + length);
    canvas.drawRect(
      Rect.fromLTRB(
        (start - length).clamp(0, size.width),
        0,
        start.clamp(0, size.width),
        size.height,
      ),
      Paint()..color = color,
    );
  }

  @override
  bool shouldRepaint(_BusyPainter oldDelegate) =>
      oldDelegate.color != color || oldDelegate.track != track;
}

/// A message filling a pane or a page: that it is empty, or what went
/// wrong.
class EmptyMessage extends StatelessWidget {
  const EmptyMessage(this.message, {this.detail, super.key});

  final String message;

  /// Said beneath, more quietly: what to do about it, or the error itself.
  final String? detail;

  @override
  Widget build(BuildContext context) {
    final tones = context.tones;
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: <Widget>[
            Text(
              message,
              textAlign: TextAlign.center,
              style: TextStyle(fontSize: 12.5, color: tones.muted),
            ),
            if (detail case final detail?)
              Padding(
                padding: const EdgeInsets.only(top: 6),
                child: SelectableText(
                  detail,
                  textAlign: TextAlign.center,
                  style: TextStyle(fontSize: 11.5, color: tones.faint),
                ),
              ),
          ],
        ),
      ),
    );
  }
}

/// Where something is loading: [Busy], in the middle.
class Loading extends StatelessWidget {
  const Loading({super.key});

  @override
  Widget build(BuildContext context) => const Center(child: Busy(width: 48));
}
