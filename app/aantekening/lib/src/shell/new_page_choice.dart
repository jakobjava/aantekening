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
    this.size = SheetSize.a4,
  });

  final NoteLayout layout;

  /// What its first sheet is printed with, shown as sheets.
  final SheetTemplate template;

  /// How large its sheets are, shown as sheets.
  final SheetSize size;

  /// The settings a page starts with, made as this says.
  CanvasSettings get canvas => layout == NoteLayout.pages
      ? CanvasSettings(
          layout: NoteLayout.pages,
          sheets: Sheets(size: size, templates: <SheetTemplate>[template]),
        )
      : CanvasSettings.defaults;

  NewPageChoice copyWith({
    NoteLayout? layout,
    SheetTemplate? template,
    SheetSize? size,
  }) => NewPageChoice(
    layout: layout ?? this.layout,
    template: template ?? this.template,
    size: size ?? this.size,
  );

  @override
  bool operator ==(Object other) =>
      other is NewPageChoice &&
      other.layout == layout &&
      other.template == template &&
      other.size == size;

  @override
  int get hashCode => Object.hash(layout, template, size);
}

/// What the last page made started as, offered first for the next — and
/// what a notebook's first page starts as, made without asking.
class NewPageChoiceController extends Notifier<NewPageChoice> {
  static const String _layout = 'newPage.layout';
  static const String _template = 'newPage.template';
  static const String _size = 'newPage.size';

  @override
  NewPageChoice build() {
    const start = NewPageChoice();
    T named<T extends Enum>(String key, List<T> values, T fallback) =>
        values.asNameMap()[ref.preference(key)] ?? fallback;
    return NewPageChoice(
      layout: named(_layout, NoteLayout.values, start.layout),
      template: named(_template, SheetTemplate.values, start.template),
      size: named(_size, SheetSize.values, start.size),
    );
  }

  void remember(NewPageChoice choice) {
    if (choice == state) return;
    state = choice;
    ref
      ..savePreference(_layout, choice.layout.name)
      ..savePreference(_template, choice.template.name)
      ..savePreference(_size, choice.size.name);
  }
}

final newPageChoiceProvider =
    NotifierProvider<NewPageChoiceController, NewPageChoice>(
      NewPageChoiceController.new,
    );
