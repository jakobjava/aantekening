/// A panel's part that takes the keyboard when the panel is asked to.
library;

import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'sidebar_state.dart';

/// Gives [node] the keyboard when [tab]'s panel is asked to take it, from
/// its shortcut — whether the panel was open already or opens for it — so
/// long as [wanted] says [node] is the one to.
class PanelFocus extends ConsumerStatefulWidget {
  const PanelFocus({
    required this.tab,
    required this.node,
    required this.child,
    this.wanted,
    super.key,
  });

  final SidebarTab tab;
  final FocusNode node;

  /// Whether [node] is the part of the panel to take the keyboard just now;
  /// always, if not given.
  final bool Function()? wanted;

  final Widget child;

  @override
  ConsumerState<PanelFocus> createState() => _PanelFocusState();
}

class _PanelFocusState extends ConsumerState<PanelFocus> {
  @override
  void initState() {
    super.initState();
    // A panel opened by the request was not there to hear it.
    WidgetsBinding.instance.addPostFrameCallback((_) => _answer());
  }

  void _answer() {
    if (!mounted || !(widget.wanted?.call() ?? true)) return;
    if (ref.read(panelFocusProvider.notifier).take(widget.tab)) {
      widget.node.requestFocus();
    }
  }

  @override
  Widget build(BuildContext context) {
    ref.listen(panelFocusProvider, (_, request) {
      if (request != null) _answer();
    });
    return widget.child;
  }
}
