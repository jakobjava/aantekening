/// Where the person has put the buttons, remembered between sessions.
library;

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../preferences.dart';
import 'arrangement.dart';

/// An [Arrangement] kept in the [Preferences] under [key].
class ArrangementController<G extends ArrangementGroup<I>, I extends Enum>
    extends Notifier<Arrangement<G, I>> {
  ArrangementController(this.key, this.groups);

  /// Where the arrangement is saved.
  final String key;

  /// Every group, in order: the values of the enum implementing
  /// [ArrangementGroup].
  final List<G> groups;

  @override
  Arrangement<G, I> build() =>
      Arrangement.fromJson(groups, ref.preference(key));

  /// Moves [item] into [group], in front of the item now at [index].
  void move(I item, G group, int index) {
    final moved = state.move(item, group, index);
    if (moved == state) return;
    state = moved;
    _save();
  }

  /// Puts every item back where it started.
  void reset() {
    if (state.isDefault) return;
    state = Arrangement.defaults(groups);
    _save();
  }

  void _save() =>
      ref.savePreference(key, state.isDefault ? null : state.toJson());
}
