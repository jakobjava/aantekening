/// The controls the interface is built from, the same wherever they are
/// used: rows to pick from, buttons with a mark, choices, switches,
/// swatches, labels, shortcuts and a sign of work going on.
library;

import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'glass.dart';
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
    this.options,
    super.key,
  });

  final String title;

  /// Before the button: how what the pane lists is ordered, say.
  final Widget? options;

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
          ?options,
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
  const KeyHint(this.keys, {this.color, this.overflow, super.key});

  final String keys;
  final Color? color;

  /// How it ends where there is no room for all of it.
  final TextOverflow? overflow;

  @override
  Widget build(BuildContext context) => Text(
    keys,
    maxLines: 1,
    softWrap: false,
    overflow: overflow,
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
      color: selected ? tones.lift : Colors.transparent,
      borderRadius: Corners.controlRadius,
      child: InkWell(
        onTap: widget.onTap,
        focusNode: widget.focusNode,
        autofocus: widget.autofocus,
        borderRadius: Corners.controlRadius,
        hoverColor: tones.veil,
        onFocusChange: (focused) => setState(() => _focused = focused),
        child: DecoratedBox(
          position: DecorationPosition.foreground,
          decoration: BoxDecoration(
            border: _focused ? Border.all(color: tones.emphasis) : null,
            borderRadius: Corners.controlRadius,
          ),
          child: Stack(
            alignment: Alignment.centerLeft,
            children: <Widget>[
              if (selected) const Positioned(left: 2, child: Drop()),
              Padding(
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
            ],
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

  /// Smaller, to fit a row.
  final bool compact;

  @override
  Widget build(BuildContext context) {
    final tones = context.tones;
    return Container(
      padding: const EdgeInsets.all(2),
      decoration: BoxDecoration(
        color: tones.text.withValues(alpha: 0.06),
        borderRadius: Corners.controlRadius,
      ),
      child: IntrinsicHeight(
        child: Row(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: <Widget>[
            for (final choice in choices)
              _Choice(
                label: labelOf?.call(choice) ?? '$choice',
                tooltip: tooltipOf?.call(choice),
                chosen: choice == selected,
                compact: compact,
                onTap: () => onSelected(choice),
              ),
          ],
        ),
      ),
    );
  }
}

class _Choice extends StatelessWidget {
  /// The corners of a choice, inside the row's.
  static const BorderRadius _inner = BorderRadius.all(
    Radius.circular(Corners.control - 2),
  );

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
        borderRadius: _inner,
        child: InkWell(
          onTap: chosen ? null : onTap,
          borderRadius: _inner,
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

/// A level from 0 to 1, set by pressing or dragging along a line, or with
/// the arrow keys.
class LevelSlider extends StatefulWidget {
  const LevelSlider({
    required this.value,
    required this.onChanged,
    required this.label,
    this.width = 180,
    super.key,
  });

  final double value;
  final ValueChanged<double> onChanged;

  /// What the level is of, for a screen reader.
  final String label;
  final double width;

  @override
  State<LevelSlider> createState() => _LevelSliderState();
}

class _LevelSliderState extends State<LevelSlider> {
  /// How far an arrow key moves it.
  static const double _step = 0.05;

  static const double _height = 24;

  final FocusNode _focus = FocusNode(debugLabel: 'LevelSlider');
  bool _focused = false;

  @override
  void dispose() {
    _focus.dispose();
    super.dispose();
  }

  void _set(double value) {
    final level = value.clamp(0.0, 1.0);
    if (level != widget.value) widget.onChanged(level);
  }

  /// Set where it is pressed, and from then on by the keys too.
  void _setAt(Offset local) {
    _focus.requestFocus();
    _set(local.dx / widget.width);
  }

  KeyEventResult _onKey(FocusNode node, KeyEvent event) {
    if (event is KeyUpEvent) return KeyEventResult.ignored;
    final key = event.logicalKey;
    if (key == LogicalKeyboardKey.arrowRight ||
        key == LogicalKeyboardKey.arrowUp) {
      _set(widget.value + _step);
    } else if (key == LogicalKeyboardKey.arrowLeft ||
        key == LogicalKeyboardKey.arrowDown) {
      _set(widget.value - _step);
    } else if (key == LogicalKeyboardKey.home) {
      _set(0);
    } else if (key == LogicalKeyboardKey.end) {
      _set(1);
    } else {
      return KeyEventResult.ignored;
    }
    return KeyEventResult.handled;
  }

  @override
  Widget build(BuildContext context) {
    final tones = context.tones;
    String percent(double level) => '${(level.clamp(0.0, 1.0) * 100).round()}%';
    return Semantics(
      slider: true,
      label: widget.label,
      value: percent(widget.value),
      increasedValue: percent(widget.value + _step),
      decreasedValue: percent(widget.value - _step),
      onIncrease: () => _set(widget.value + _step),
      onDecrease: () => _set(widget.value - _step),
      child: Focus(
        focusNode: _focus,
        onKeyEvent: _onKey,
        onFocusChange: (focused) => setState(() => _focused = focused),
        child: MouseRegion(
          cursor: SystemMouseCursors.click,
          child: GestureDetector(
            behavior: HitTestBehavior.opaque,
            onTapDown: (details) => _setAt(details.localPosition),
            onHorizontalDragStart: (details) => _setAt(details.localPosition),
            onHorizontalDragUpdate: (details) => _setAt(details.localPosition),
            child: CustomPaint(
              size: Size(widget.width, _height),
              painter: _LevelPainter(
                level: widget.value,
                line: tones.strongLine,
                filled: tones.emphasis,
                knob: tones.base,
                focused: _focused,
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _LevelPainter extends CustomPainter {
  const _LevelPainter({
    required this.level,
    required this.line,
    required this.filled,
    required this.knob,
    required this.focused,
  });

  final double level;
  final Color line;
  final Color filled;
  final Color knob;
  final bool focused;

  @override
  void paint(Canvas canvas, Size size) {
    final middle = size.height / 2;
    final x = level.clamp(0.0, 1.0) * size.width;
    const round = Radius.circular(2);
    canvas
      ..drawRRect(
        RRect.fromLTRBR(0, middle - 2, size.width, middle + 2, round),
        Paint()..color = line,
      )
      ..drawRRect(
        RRect.fromLTRBR(0, middle - 2, x, middle + 2, round),
        Paint()..color = filled,
      );
    // A round knob, kept within the line's ends.
    final knobAt = Offset(x.clamp(7.0, size.width - 7), middle);
    canvas
      ..drawCircle(knobAt, 7, Paint()..color = knob)
      ..drawCircle(
        knobAt,
        7,
        Paint()
          ..color = filled
          ..style = PaintingStyle.stroke
          ..strokeWidth = focused ? 3 : 2,
      );
  }

  @override
  bool shouldRepaint(_LevelPainter old) =>
      old.level != level ||
      old.line != line ||
      old.filled != filled ||
      old.knob != knob ||
      old.focused != focused;
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
      borderRadius: Corners.controlRadius,
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 6, horizontal: 4),
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

/// A colour to pick: a dot of it, ringed when it is the one chosen.
class Swatch extends StatelessWidget {
  const Swatch({
    required Color this.color,
    required this.name,
    required this.selected,
    required this.onTap,
    this.size = 20,
    super.key,
  });

  /// The swatch of no colour but the inverse of what lies beneath: half
  /// white, half black.
  const Swatch.inverse({
    required this.name,
    required this.selected,
    required this.onTap,
    this.size = 20,
    super.key,
  }) : color = null;

  /// The colour, or null for the inverse of what lies beneath.
  final Color? color;
  final String name;
  final bool selected;
  final VoidCallback? onTap;
  final double size;

  @override
  Widget build(BuildContext context) {
    return Tooltip(
      message: name,
      child: PickRing(
        selected: selected,
        onTap: onTap,
        round: true,
        child: Container(
          width: size,
          height: size,
          clipBehavior: Clip.antiAlias,
          decoration: const BoxDecoration(shape: BoxShape.circle),
          foregroundDecoration: BoxDecoration(
            shape: BoxShape.circle,
            border: Border.all(color: context.tones.line),
          ),
          child: switch (color) {
            final color? => ColoredBox(color: color),
            null => const CustomPaint(painter: InverseHalves()),
          },
        ),
      ),
    );
  }
}

/// [child], to be picked with a click, in a ring of the emphasis while it
/// is [selected], and on the selection's tint if [filled]: a swatch, or a
/// tile drawn as what it picks.
class PickRing extends StatelessWidget {
  const PickRing({
    required this.selected,
    required this.onTap,
    required this.child,
    this.padding = const EdgeInsets.all(2),
    this.filled = false,
    this.round = false,
    super.key,
  });

  final bool selected;
  final VoidCallback? onTap;
  final Widget child;
  final EdgeInsets padding;
  final bool filled;

  /// Whether the ring is round, for a round [child]: a swatch.
  final bool round;

  @override
  Widget build(BuildContext context) {
    final tones = context.tones;
    final radius = round ? null : Corners.controlRadius;
    return InkWell(
      onTap: onTap,
      customBorder: round
          ? const CircleBorder()
          : const RoundedRectangleBorder(borderRadius: Corners.controlRadius),
      child: Container(
        padding: padding,
        decoration: BoxDecoration(
          color: filled && selected ? tones.lift : null,
          shape: round ? BoxShape.circle : BoxShape.rectangle,
          borderRadius: radius,
          border: Border.all(
            color: selected ? tones.emphasis : Colors.transparent,
            width: 2,
          ),
        ),
        child: child,
      ),
    );
  }
}

/// How the inverse of what lies beneath is shown: white and black, split
/// from corner to corner, as it is black on white paper and white on
/// black.
class InverseHalves extends CustomPainter {
  const InverseHalves();

  @override
  void paint(Canvas canvas, Size size) => canvas
    ..drawRect(Offset.zero & size, Paint()..color = const Color(0xFFFFFFFF))
    ..drawPath(
      Path()..addPolygon(<Offset>[
        size.bottomLeft(Offset.zero),
        size.topRight(Offset.zero),
        size.bottomRight(Offset.zero),
      ], true),
      Paint()..color = const Color(0xFF000000),
    );

  @override
  bool shouldRepaint(InverseHalves old) => false;
}

/// That something is being worked on: a short bar running along a line —
/// or, where how far it has got is known, the line filled that far.
class Busy extends StatefulWidget {
  const Busy({this.width = 16, this.value, super.key});

  final double width;

  /// How far the work has got, from 0 to 1, if that is known.
  final double? value;

  @override
  State<Busy> createState() => _BusyState();
}

class _BusyState extends State<Busy> with SingleTickerProviderStateMixin {
  late final AnimationController _run = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 1100),
  );

  @override
  void initState() {
    super.initState();
    _runWhileUnknown();
  }

  @override
  void didUpdateWidget(Busy old) {
    super.didUpdateWidget(old);
    _runWhileUnknown();
  }

  /// The bar runs only while how far the work has got is not known: a line
  /// filled so far stays still, and asks for no frames.
  void _runWhileUnknown() {
    if (widget.value != null) {
      _run.stop();
    } else if (!_run.isAnimating) {
      unawaited(_run.repeat());
    }
  }

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
          painter: _BusyPainter(_run, tones.emphasis, tones.line, widget.value),
        ),
      ),
    );
  }
}

class _BusyPainter extends CustomPainter {
  _BusyPainter(this.run, this.color, this.track, this.value)
    : super(repaint: value == null ? run : null);

  final Animation<double> run;
  final Color color;
  final Color track;
  final double? value;

  @override
  void paint(Canvas canvas, Size size) {
    canvas.drawRect(Offset.zero & size, Paint()..color = track);
    if (value case final done?) {
      canvas.drawRect(
        Rect.fromLTWH(0, 0, size.width * done.clamp(0, 1), size.height),
        Paint()..color = color,
      );
      return;
    }
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
      oldDelegate.color != color ||
      oldDelegate.track != track ||
      oldDelegate.value != value;
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

/// A note set apart: [child] on a rounded ground, a bar of [colour] down
/// its side — a quotation, what a summary comes to, where a line of an
/// answer comes from.
class Callout extends StatelessWidget {
  const Callout({
    required this.colour,
    required this.child,
    this.fill,
    this.padding = const EdgeInsets.fromLTRB(14, 10, 14, 10),
    this.margin = EdgeInsets.zero,
    super.key,
  });

  final Color colour;
  final Widget child;

  /// The ground, or none.
  final Color? fill;
  final EdgeInsetsGeometry padding;
  final EdgeInsetsGeometry margin;

  @override
  Widget build(BuildContext context) => Container(
    margin: margin,
    decoration: BoxDecoration(color: fill, borderRadius: Corners.controlRadius),
    child: IntrinsicHeight(
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: <Widget>[
          Container(
            width: 3,
            margin: const EdgeInsets.symmetric(vertical: 4),
            decoration: BoxDecoration(
              color: colour,
              borderRadius: const BorderRadius.all(Radius.circular(2)),
            ),
          ),
          Expanded(
            child: Padding(padding: padding, child: child),
          ),
        ],
      ),
    ),
  );
}

/// A small rounded button: a way back, something quick to do — [lit], a
/// drop of the accent, where what it does stands out or is on.
class PillButton extends StatelessWidget {
  const PillButton(
    this.label, {
    required this.onPressed,
    this.lit = false,
    this.leading,
    this.tooltip,
    super.key,
  });

  final String label;
  final VoidCallback? onPressed;
  final bool lit;

  /// A mark before the label: an arrow back, say.
  final Widget? leading;
  final String? tooltip;

  @override
  Widget build(BuildContext context) {
    final tones = context.tones;
    final button = TextButton(
      onPressed: onPressed,
      style: TextButton.styleFrom(
        shape: const StadiumBorder(),
        minimumSize: const Size(0, 28),
        padding: const EdgeInsets.symmetric(horizontal: 12),
        visualDensity: VisualDensity.compact,
        tapTargetSize: MaterialTapTargetSize.shrinkWrap,
        backgroundColor: lit ? tones.emphasis : tones.lift,
        foregroundColor: lit ? tones.onEmphasis : tones.text,
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: <Widget>[
          if (leading case final leading?) ...<Widget>[
            leading,
            const SizedBox(width: 6),
          ],
          Text(
            label,
            style: const TextStyle(fontSize: 12.5, fontWeight: FontWeight.w600),
          ),
        ],
      ),
    );
    final tooltip = this.tooltip;
    return tooltip == null ? button : Tooltip(message: tooltip, child: button);
  }
}

/// A drop of the accent, glowing a little in the glass: a rounded bar
/// marking what is picked or showing — beside a row, or [Drop.under] a tab
/// — or, as [Drop.dot], a round one marking what is open, or the mode.
class Drop extends StatelessWidget {
  const Drop({this.width = 3, this.height = 14, this.colour, super.key});

  /// A bar along the foot of what it marks, as wide as [width].
  const Drop.under({double width = 18, Color? colour, Key? key})
    : this(width: width, height: 3, colour: colour, key: key);

  /// A round drop, [size] across.
  const Drop.dot({double size = 6, Color? colour, Key? key})
    : this(width: size, height: size, colour: colour, key: key);

  final double width;
  final double height;

  /// Its colour: the accent, unless it marks something of its own colour —
  /// a mode.
  final Color? colour;

  @override
  Widget build(BuildContext context) {
    final colour = this.colour ?? context.tones.emphasis;
    return Container(
      width: width,
      height: height,
      decoration: BoxDecoration(
        color: colour,
        borderRadius: BorderRadius.all(
          Radius.circular((width < height ? width : height) / 2),
        ),
        boxShadow: <BoxShadow>[
          BoxShadow(color: colour.withValues(alpha: 0.5), blurRadius: 6),
        ],
      ),
    );
  }
}

/// A tab to show a view by: its label, the one showing marked with a drop
/// of the accent beneath it, as the status line marks the tab showing.
class DropTab extends StatelessWidget {
  const DropTab(
    this.label, {
    required this.showing,
    required this.onPressed,
    super.key,
  });

  final String label;
  final bool showing;
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    final tones = context.tones;
    return InkWell(
      onTap: onPressed,
      borderRadius: Corners.controlRadius,
      hoverColor: tones.veil,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(10, 6, 10, 3),
        child: IntrinsicWidth(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: <Widget>[
              Text(
                label,
                style: TextStyle(
                  fontSize: 12.5,
                  fontWeight: FontWeight.w600,
                  color: showing ? tones.text : tones.muted,
                ),
              ),
              const SizedBox(height: 4),
              if (showing)
                const Drop.under(width: double.infinity)
              else
                const SizedBox(height: 3),
            ],
          ),
        ),
      ),
    );
  }
}
