/// What a new page starts as: one paper, or sheets on a paper of some
/// kind — the choice last made, remembered.
library;

import 'package:aantekening_core/aantekening_core.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../preferences.dart';

/// What a new page starts as.
@immutable
class NewPageChoice {
  const NewPageChoice({
    this.layout = NoteLayout.canvas,
    this.template = SheetTemplate.lined,
    this.orientation = SheetOrientation.portrait,
  });

  final NoteLayout layout;

  /// What its first sheet is printed with, shown as sheets.
  final SheetTemplate template;

  /// Which way up its sheets are turned, shown as sheets.
  final SheetOrientation orientation;

  /// The settings a page starts with, made as this says.
  CanvasSettings get canvas => layout == NoteLayout.pages
      ? CanvasSettings(
          layout: NoteLayout.pages,
          sheets: Sheets(
            orientation: orientation,
            templates: <SheetTemplate>[template],
          ),
        )
      : CanvasSettings.defaults;

  NewPageChoice copyWith({
    NoteLayout? layout,
    SheetTemplate? template,
    SheetOrientation? orientation,
  }) => NewPageChoice(
    layout: layout ?? this.layout,
    template: template ?? this.template,
    orientation: orientation ?? this.orientation,
  );

  @override
  bool operator ==(Object other) =>
      other is NewPageChoice &&
      other.layout == layout &&
      other.template == template &&
      other.orientation == orientation;

  @override
  int get hashCode => Object.hash(layout, template, orientation);
}

/// What the last page made started as, offered first for the next — and
/// what a notebook's first page starts as, made without asking.
class NewPageChoiceController extends Notifier<NewPageChoice> {
  static const String _layout = 'newPage.layout';
  static const String _template = 'newPage.template';
  static const String _orientation = 'newPage.orientation';

  @override
  NewPageChoice build() {
    const start = NewPageChoice();
    T named<T extends Enum>(String key, List<T> values, T fallback) =>
        values.asNameMap()[ref.preference(key)] ?? fallback;
    return NewPageChoice(
      layout: named(_layout, NoteLayout.values, start.layout),
      template: named(_template, SheetTemplate.values, start.template),
      orientation: named(
        _orientation,
        SheetOrientation.values,
        start.orientation,
      ),
    );
  }

  void remember(NewPageChoice choice) {
    if (choice == state) return;
    state = choice;
    ref
      ..savePreference(_layout, choice.layout.name)
      ..savePreference(_template, choice.template.name)
      ..savePreference(_orientation, choice.orientation.name);
  }
}

final newPageChoiceProvider =
    NotifierProvider<NewPageChoiceController, NewPageChoice>(
      NewPageChoiceController.new,
    );
