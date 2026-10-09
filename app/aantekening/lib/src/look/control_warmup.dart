/// The controls panes are made of, laid out once just after the window
/// first shows, so the first pane to show them does not wait.
library;

import 'package:flutter/material.dart';
import 'package:flutter/scheduler.dart';

import 'controls.dart';

/// Lays out, unseen, one of each control a pane is made of — a field to
/// type in, buttons, words across several lines — for one frame, just after
/// the window first shows, as it settles.
///
/// Laying out a control's words the first time costs what the second time
/// does not: laying out the AI pane as it first opened took 51 ms, nearly
/// all of it its field and its button; with these laid out first, 14 ms.
/// Paid here, as the window opens, nobody waits on it.
void warmControls(BuildContext context) {
  if (_warmed) return;
  _warmed = true;
  final overlay = Overlay.maybeOf(context, rootOverlay: true);
  if (overlay == null) return;
  final entry = OverlayEntry(
    builder: (context) => const Offstage(child: _Controls()),
  );
  overlay.insert(entry);
  // Laid out in the next frame; then gone — let go of once it is no longer
  // drawn, a frame later.
  SchedulerBinding.instance.addPostFrameCallback((_) {
    entry.remove();
    SchedulerBinding.instance.addPostFrameCallback((_) => entry.dispose());
  });
}

bool _warmed = false;

class _Controls extends StatelessWidget {
  const _Controls();

  @override
  Widget build(BuildContext context) => Material(
    type: MaterialType.transparency,
    child: SizedBox(
      width: 480,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: <Widget>[
          for (final weight in <FontWeight>[
            FontWeight.w400,
            FontWeight.w500,
            FontWeight.w600,
            FontWeight.w700,
          ])
            Text(
              'Words — set in each weight, … › ← → “½×”',
              style: TextStyle(fontWeight: weight),
            ),
          const Text(
            'Words across several lines, in the middle: as a pane says what '
            'it holds, or what to do when it holds nothing yet, and why.',
            textAlign: TextAlign.center,
          ),
          const TextField(decoration: InputDecoration(hintText: 'Ask…')),
          FilledButton(onPressed: () {}, child: const Text('Choose')),
          TextButton(onPressed: () {}, child: const Text('Cancel')),
          PillButton('Overview', onPressed: () {}),
        ],
      ),
    ),
  );
}
