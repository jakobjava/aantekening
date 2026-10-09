/// The guide: a pane of glass beside what has the focus, showing what each
/// key does next — at once for the menu, or once a sequence of keys pauses
/// half way, as which-key does in an editor.
library;

import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../look/appearance.dart';
import '../look/controls.dart';
import '../look/floating_pane.dart';
import '../look/glass.dart';
import '../look/marks.dart';
import '../look/motion.dart';
import '../look/steady_size.dart';
import '../look/tones.dart';
import 'key_catch.dart';
import 'mode_keys.dart';

/// The keys pressed so far in a sequence not yet finished, as the status
/// line shows them.
class PendingKeys extends Notifier<List<String>> {
  @override
  List<String> build() => const <String>[];

  // A setter would read as a field; this is the guide saying what it has.
  // ignore: use_setters_to_change_properties
  void show(List<String> keys) {
    // The window may have gone from under a guide still open.
    if (ref.mounted) state = keys;
  }
}

final pendingKeysProvider = NotifierProvider<PendingKeys, List<String>>(
  PendingKeys.new,
);

/// The guide open, if one is: there is only ever one.
_Guide? _open;

/// Opens [layer], which [pressed] opened: the keys go to it from now on —
/// straight from the keyboard, so none is lost however fast they come —
/// until one runs something, Esc closes it, or a key it has nothing for
/// does. It shows in the middle of the window, always in the same place:
/// at once with [atOnce], else once the keys pause.
void openKeyGuide(
  BuildContext context, {
  required String pressed,
  required KeyLayer Function() layer,
  bool atOnce = false,
}) {
  closeKeyGuide();
  final overlay = Overlay.of(context, rootOverlay: true);
  final pending = ProviderScope.containerOf(
    context,
    listen: false,
  ).read(pendingKeysProvider.notifier);
  final guide = _Guide(
    first: (pressed, layer),
    pending: pending,
    atOnce: atOnce,
  );
  _open = guide;
  overlay.insert(guide.entry);
}

/// Hands [pressed] to the guide open, as if it had been pressed there:
/// for a key that came before the guide was open, with the one that opens
/// it still held. Says whether the guide took it.
bool pressInKeyGuide(String pressed) => _open?.press(pressed) ?? false;

/// Closes the guide, if it is open, without running anything.
void closeKeyGuide() => _open?.close();

/// One guide open: the layers its keys have opened, whether it shows yet,
/// and the keys it takes from the keyboard meanwhile.
class _Guide extends ChangeNotifier {
  _Guide({
    required (String, KeyLayer Function()) first,
    required this.pending,
    required bool atOnce,
  }) : layers = <(String, KeyLayer Function())>[first],
       shown = atOnce {
    _catch = KeyCatch(press);
    entry = OverlayEntry(builder: (context) => _GuideView(guide: this));
    if (!atOnce) _waiting = Timer(_pause, _show);
    _tellPending();
  }

  /// How long the keys pause before the guide shows what comes next.
  static const Duration _pause = Duration(milliseconds: 420);

  final List<(String, KeyLayer Function())> layers;
  final PendingKeys pending;
  late final OverlayEntry entry;
  late final KeyCatch _catch;
  Timer? _waiting;

  /// Whether it shows: it may be taking keys before it does.
  bool shown;
  bool _closed = false;

  KeyLayer get layer => layers.last.$2();

  List<String> get trail => <String>[
    for (final (pressed, _) in layers) pressed,
  ];

  void _show() {
    if (_closed || shown) return;
    shown = true;
    notifyListeners();
  }

  void _tellPending() => pending.show(_closed ? const <String>[] : trail);

  /// Takes [pressed] — saying whether it did — as the guide's keys do:
  /// Esc closes it, Backspace goes back a layer, and a key it has nothing
  /// for ends the sequence, as in vim.
  bool press(String pressed) {
    if (_closed) return false;
    if (pressed == ModeKey.escape) {
      close();
    } else if (pressed == ModeKey.backspace) {
      if (layers.length > 1) {
        layers.removeLast();
        _tellPending();
        notifyListeners();
      } else {
        close();
      }
    } else if (layer.actionFor(pressed) case final action?) {
      take(action);
    } else {
      close();
    }
    return true;
  }

  /// Runs [action], or opens its layer.
  void take(KeyAction action) {
    if (_closed || !action.enabled) return;
    final next = action.layer;
    if (next != null) {
      layers.add((action.key, next));
      // A layer opened from one showing shows at once.
      if (shown) {
        notifyListeners();
      } else {
        _waiting?.cancel();
        _waiting = Timer(_pause, _show);
      }
      _tellPending();
      return;
    }
    if (action.stays) {
      action.run!();
      notifyListeners();
      return;
    }
    close();
    action.run!();
  }

  /// Gives the keys back as the guide goes with the window under it,
  /// unclosed.
  void _lost() {
    if (_closed) return;
    _closed = true;
    if (identical(_open, this)) _open = null;
    _waiting?.cancel();
    _catch.release();
  }

  /// Takes the guide away, the keys going where they went before.
  void close() {
    if (_closed) return;
    _lost();
    _tellPending();
    // In the overlay from the start, if not yet drawn there.
    entry.remove();
    // Not while it may still be drawn this frame.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      entry.dispose();
      dispose();
    });
  }
}

/// The guide as it shows: nothing until it should, then floating in, in
/// the middle of the window, a click elsewhere closing it.
class _GuideView extends StatefulWidget {
  const _GuideView({required this.guide});

  final _Guide guide;

  @override
  State<_GuideView> createState() => _GuideViewState();
}

class _GuideViewState extends State<_GuideView>
    with SingleTickerProviderStateMixin {
  late final AnimationController _shown = AnimationController(vsync: this);

  _Guide get _guide => widget.guide;

  @override
  void initState() {
    super.initState();
    _guide.addListener(_changed);
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _shown.duration = context.motion.of(Motion.settle);
    if (_guide.shown) unawaited(_shown.forward());
  }

  @override
  void dispose() {
    _guide
      ..removeListener(_changed)
      .._lost();
    _shown.dispose();
    super.dispose();
  }

  void _changed() {
    if (!mounted) return;
    if (_guide.shown && _shown.status == AnimationStatus.dismissed) {
      unawaited(_shown.forward());
    }
    setState(() {});
  }

  @override
  Widget build(BuildContext context) => AnimatedBuilder(
    animation: _shown,
    builder: (context, pane) => _shown.value == 0
        ? const SizedBox.shrink()
        : Stack(
            children: <Widget>[
              // A click elsewhere closes it.
              Positioned.fill(
                child: GestureDetector(
                  behavior: HitTestBehavior.opaque,
                  onTap: _guide.close,
                  onSecondaryTap: _guide.close,
                ),
              ),
              pane!,
            ],
          ),
    // Clear of the window's edges, wherever it is moved.
    child: Padding(
      padding: const EdgeInsets.all(10),
      child: FloatingPane(
        pane: Pane.menu,
        natural: BoxConstraints.loose,
        position: _middle,
        minSize: const Size(180, 120),
        child: FloatingIn(
          animation: _shown,
          alignment: Alignment.topCenter,
          child: Glass(
            // As large as the largest layer opened in it, so going from one
            // to another it holds still.
            child: SteadySize(
              child: _GuidePane(
                trail: _guide.trail,
                layer: _guide.layer,
                onTake: _guide.take,
              ),
            ),
          ),
        ),
      ),
    ),
  );
}

/// Where the guide goes by itself: in the middle of the window, its top
/// always at the same height, so a layer opened from it grows down from
/// where it was rather than jumping.
Offset _middle(Size area, Size guide) =>
    Offset((area.width - guide.width) / 2, area.height * 0.26);

/// What the guide shows: the layer's name and the keys pressed so far, and
/// what each key does next — in even columns of their groups, or tiles of
/// what they give — with the keys that go back or away along the foot.
class _GuidePane extends StatelessWidget {
  const _GuidePane({
    required this.trail,
    required this.layer,
    required this.onTake,
  });

  final List<String> trail;
  final KeyLayer layer;
  final ValueChanged<KeyAction> onTake;

  /// How many rows a layer lists in one column before its groups go side
  /// by side.
  static const int _column = 12;

  /// The most columns a layer is set out in.
  static const int _most = 4;

  /// How wide a column is at least, and at most: as wide as its labels
  /// between, the longest cut short.
  static const BoxConstraints _columnWidth = BoxConstraints(
    minWidth: 132,
    maxWidth: 220,
  );

  @override
  Widget build(BuildContext context) {
    final tones = context.tones;
    final groups = <KeyGroup>[
      for (final group in layer.groups)
        if (group.actions.isNotEmpty) group,
    ];
    // Sized by hand, it fills what it was made: its columns as many as fit.
    final sized = FloatingPane.sizedByHand(context);
    final Widget body;
    if (layer.tiles) {
      final tiles = Wrap(
        children: <Widget>[
          for (final action in layer.actions)
            _Tile(action: action, onTap: () => onTake(action)),
        ],
      );
      body = sized
          ? tiles
          : ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 6 * _Tile.width + 12),
              child: tiles,
            );
    } else if (sized) {
      body = LayoutBuilder(
        builder: (context, constraints) => _columnsOf(
          context,
          groups,
          most: math.max(
            1,
            ((constraints.maxWidth + _gap) / (_fitted + _gap)).floor(),
          ),
          fill: true,
        ),
      );
    } else {
      body = _columnsOf(context, groups, most: _most, fill: false);
    }
    final pane = Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: <Widget>[
        PaneDragArea(
          child: Padding(
            padding: const EdgeInsets.fromLTRB(6, 0, 2, 6),
            child: Row(
              children: <Widget>[
                Semantics(
                  header: true,
                  child: Text(
                    layer.title,
                    style: TextStyle(
                      fontSize: 13,
                      fontWeight: FontWeight.w700,
                      color: tones.text,
                    ),
                  ),
                ),
                const Spacer(),
                const SizedBox(width: 16),
                for (final (index, key) in trail.indexed) ...<Widget>[
                  if (index > 0)
                    Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 3),
                      child: Mark(
                        MarkShape.chevronRight,
                        size: 8,
                        color: tones.faint,
                      ),
                    ),
                  KeyCap(key, accented: true),
                ],
                const SizedBox(width: 10),
                // The keys that go back or away, by the way here.
                KeyHint(trail.length > 1 ? 'Bksp  back   Esc' : 'Esc'),
              ],
            ),
          ),
        ),
        Flexible(child: SingleChildScrollView(child: body)),
      ],
    );
    return Padding(
      padding: const EdgeInsets.fromLTRB(6, 8, 6, 6),
      child: sized ? pane : IntrinsicWidth(child: pane),
    );
  }

  /// The space between columns, the rule down its middle.
  static const double _gap = 11;

  /// How wide a column is, at least, in a guide sized by hand.
  static const double _fitted = 170;

  /// [groups] in columns, at most [most] of them, side by side: each as
  /// wide as its labels, or with [fill], sharing the width there is.
  Widget _columnsOf(
    BuildContext context,
    List<KeyGroup> groups, {
    required int most,
    required bool fill,
  }) {
    final tones = context.tones;
    final columns = _columns(groups, most: most);
    return IntrinsicHeight(
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        mainAxisSize: MainAxisSize.min,
        children: <Widget>[
          for (final (index, column) in columns.indexed) ...<Widget>[
            if (index > 0) VerticalDivider(width: _gap, color: tones.glassRim),
            if (fill)
              Expanded(child: _groupsDown(column))
            else
              ConstrainedBox(
                constraints: _columnWidth,
                child: IntrinsicWidth(child: _groupsDown(column)),
              ),
          ],
        ],
      ),
    );
  }

  /// One column of [groups]: each under its title, its keys beneath.
  Widget _groupsDown(List<KeyGroup> groups) => Column(
    crossAxisAlignment: CrossAxisAlignment.stretch,
    children: <Widget>[
      for (final (at, group) in groups.indexed) ...<Widget>[
        if (group.title case final title?)
          Padding(
            padding: EdgeInsets.fromLTRB(6, at == 0 ? 0 : 6, 6, 2),
            child: SmallCaps(title),
          )
        else if (at > 0)
          const SizedBox(height: 6),
        for (final action in group.actions)
          KeyGuideRow(action: action, onTap: () => onTake(action)),
      ],
    ],
  );

  /// [groups] set out in columns: one, for a short layer; else as many as
  /// fit them, at most [most], each group put in the shortest so far,
  /// keeping their order down each.
  static List<List<KeyGroup>> _columns(
    List<KeyGroup> groups, {
    required int most,
  }) {
    final rows = groups.fold<int>(
      0,
      (sum, group) => sum + group.actions.length,
    );
    if (rows <= _column || groups.length < 2) return <List<KeyGroup>>[groups];
    final count = math.min(most, groups.length);
    final columns = <List<KeyGroup>>[for (var i = 0; i < count; i++) []];
    final heights = List<int>.filled(count, 0);
    for (final group in groups) {
      var shortest = 0;
      for (var i = 1; i < count; i++) {
        if (heights[i] < heights[shortest]) shortest = i;
      }
      columns[shortest].add(group);
      heights[shortest] += group.actions.length + 1;
    }
    return columns;
  }
}

/// A key, drawn as a key cap: in the accent, for one that opens more.
class KeyCap extends StatelessWidget {
  const KeyCap(
    this.label, {
    this.enabled = true,
    this.accented = false,
    super.key,
  });

  /// The key, as [ModeKey.of] names it.
  final String label;
  final bool enabled;
  final bool accented;

  /// Keys whose names are long, as their caps are printed — in words, as
  /// not every typeface has the arrows and symbols printed on some.
  static const Map<String, String> _shown = <String, String>{
    ModeKey.delete: 'Del',
    ModeKey.backspace: 'Bksp',
  };

  @override
  Widget build(BuildContext context) {
    final tones = context.tones;
    final colour = accented ? tones.emphasis : tones.text;
    // The caps are all of the glass; those that open more say so in the
    // accent alone.
    return Container(
      constraints: const BoxConstraints(minWidth: 20),
      height: 20,
      padding: const EdgeInsets.symmetric(horizontal: 5),
      alignment: Alignment.center,
      decoration: BoxDecoration(
        color: tones.lift,
        border: Border.all(color: tones.glassRim),
        borderRadius: Corners.smallRadius,
      ),
      child: Text(
        _shown[label] ?? label,
        maxLines: 1,
        softWrap: false,
        style: TextStyle(
          fontFamily: InterfaceFont.mono.family,
          fontSize: 11,
          height: 1,
          fontWeight: FontWeight.w600,
          color: enabled ? colour : tones.faint,
        ),
      ),
    );
  }
}

/// One key in a list: its cap — in the accent where it opens more — what
/// it does, and whether it opens more or is on.
class KeyGuideRow extends StatelessWidget {
  const KeyGuideRow({required this.action, required this.onTap, super.key});

  final KeyAction action;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final tones = context.tones;
    final enabled = action.enabled;
    final opens = action.layer != null;
    return Opacity(
      opacity: enabled ? 1 : 0.4,
      child: InkWell(
        onTap: enabled ? onTap : null,
        borderRadius: Corners.controlRadius,
        hoverColor: tones.veil,
        child: SizedBox(
          height: 26,
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 5),
            child: Row(
              children: <Widget>[
                // The labels lined up, past caps with longer names.
                ConstrainedBox(
                  constraints: const BoxConstraints(minWidth: 30),
                  child: Padding(
                    padding: const EdgeInsets.only(right: 6),
                    child: KeyCap(action.key, accented: opens),
                  ),
                ),
                if (action.preview case final preview?) ...<Widget>[
                  SizedBox(
                    width: 18,
                    height: 18,
                    child: Center(child: preview),
                  ),
                  const SizedBox(width: 8),
                ],
                Expanded(
                  child: Text(
                    action.label,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      fontSize: 12.5,
                      fontWeight: opens ? FontWeight.w600 : FontWeight.w400,
                      color: tones.text,
                    ),
                  ),
                ),
                if (action.checked ?? false) ...<Widget>[
                  const SizedBox(width: 6),
                  Mark(MarkShape.check, size: 11, color: tones.emphasis),
                ] else if (opens) ...<Widget>[
                  const SizedBox(width: 6),
                  Mark(MarkShape.chevronRight, size: 9, color: tones.emphasis),
                ],
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// One key in a gallery: what it gives, drawn, with its key in a corner.
class _Tile extends StatelessWidget {
  const _Tile({required this.action, required this.onTap});

  final KeyAction action;
  final VoidCallback onTap;

  static const double width = 58;
  static const double height = 52;

  @override
  Widget build(BuildContext context) {
    final tones = context.tones;
    final checked = action.checked ?? false;
    return Tooltip(
      message: action.label,
      waitDuration: const Duration(milliseconds: 600),
      child: InkWell(
        onTap: action.enabled ? onTap : null,
        borderRadius: Corners.controlRadius,
        hoverColor: tones.veil,
        child: Container(
          width: width,
          height: height,
          margin: const EdgeInsets.all(1),
          decoration: BoxDecoration(
            color: checked ? tones.lift : null,
            border: checked
                ? Border.all(color: tones.emphasis, width: 1.5)
                : null,
            borderRadius: Corners.controlRadius,
          ),
          child: Stack(
            children: <Widget>[
              Positioned.fill(
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(8, 15, 8, 5),
                  child: Center(child: action.preview ?? Text(action.label)),
                ),
              ),
              Positioned(
                left: 5,
                top: 4,
                child: Text(
                  action.key,
                  style: TextStyle(
                    fontFamily: InterfaceFont.mono.family,
                    fontSize: 10,
                    height: 1,
                    fontWeight: FontWeight.w700,
                    color: checked ? tones.emphasis : tones.muted,
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
