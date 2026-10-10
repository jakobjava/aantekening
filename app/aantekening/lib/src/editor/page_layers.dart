/// The layers of keys the page offers through the guide: formatting text,
/// ink and shapes, formulas, sheets and the view — all the page can do, a
/// key or two away.
library;

import 'dart:async';

import 'package:aantekening_canvas/aantekening_canvas.dart';
import 'package:aantekening_core/aantekening_core.dart' hide BoxShape;
import 'package:aantekening_math/aantekening_math.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../commands/app_command.dart';
import '../commands/fuzzy.dart';
import '../commands/shortcuts.dart';
import '../look/chooser.dart';
import '../look/colour_picker.dart';
import '../look/marks.dart';
import '../look/tones.dart';
import '../modes/mode_keys.dart';
import '../spelling/dictionaries.dart';
import '../spelling/spelling.dart';
import 'page_commands.dart';
import 'page_minimap.dart';
import 'palette.dart';
import 'shape_glyph.dart';
import 'text/cheat_sheet.dart';
import 'text/math_syntax.dart';
import 'text/math_templates.dart';
import 'text/text_box_controller.dart';
import 'text/text_styles.dart';
import 'text/typefaces.dart';

/// Builds the page's layers of keys from [commands], running what is the
/// window's or the page editor's through [ref]'s command handlers, and
/// opening what asks more — a colour, a typeface — over [context].
class PageLayers {
  const PageLayers(this.commands, this.context, this.ref);

  final PageCommands commands;
  final BuildContext context;
  final WidgetRef ref;

  TextBoxEditorController get _text => commands.text;
  CanvasController get _canvas => commands.canvas;

  /// [key] — or any of [also] — running [command], named as it is, as it
  /// can just now.
  KeyAction command(
    String key,
    AppCommand command, {
    String? label,
    List<String> also = const <String>[],
  }) {
    final action = ref.read(commandHandlersProvider)[command];
    return KeyAction(
      key,
      label ?? command.label,
      run: () => ref.read(commandHandlersProvider).run(command),
      also: also,
      enabled: action?.isEnabled ?? false,
    );
  }

  // ------------------------------------------------------------------ text

  /// Formatting the text being typed, or the text boxes picked.
  KeyLayer text() {
    final state = _text.state;
    final can = _text.hasTarget;
    final marks = can && !state.inFormula;
    KeyAction mark(String key, MarkKind kind, String label) => KeyAction(
      key,
      label,
      run: () => _text.toggleMark(kind),
      enabled: marks,
      checked: state.marks.contains(kind),
      stays: true,
    );
    KeyAction block(String key, TextBlockKind kind, String label) => KeyAction(
      key,
      label,
      run: () => _text.toggleBlockKind(kind),
      enabled: can,
      checked: state.blockKind == kind,
    );
    return KeyLayer('Text', <KeyGroup>[
      KeyGroup(title: 'Marks', <KeyAction>[
        mark('b', MarkKind.bold, 'Bold'),
        mark('i', MarkKind.italic, 'Italic'),
        mark('u', MarkKind.underline, 'Underline'),
        mark('s', MarkKind.strikethrough, 'Strikethrough'),
        mark('c', MarkKind.code, 'Code'),
        KeyAction(
          'h',
          'Highlight',
          layer: () => colours(
            'Highlight',
            current: state.highlight,
            noneLabel: 'No highlight',
            onPicked: (color) => _text.setHighlight(
              color == null ? null : RichTextStyles.highlightFor(color),
            ),
          ),
          enabled: can,
        ),
        KeyAction(
          't',
          'Text colour',
          layer: () => colours(
            'Text colour',
            current: state.textColor,
            noneLabel: 'Automatic (black)',
            offersInverse: true,
            onPicked: _text.setTextColor,
          ),
          enabled: can,
        ),
      ]),
      KeyGroup(title: 'Paragraph', <KeyAction>[
        block('0', TextBlockKind.paragraph, 'Normal'),
        block('1', TextBlockKind.heading1, 'Heading 1'),
        block('2', TextBlockKind.heading2, 'Heading 2'),
        block('3', TextBlockKind.heading3, 'Heading 3'),
        block('q', TextBlockKind.quote, 'Quote'),
        block('k', TextBlockKind.code, 'Code block'),
        block('l', TextBlockKind.bulleted, 'Bullets'),
        block('n', TextBlockKind.numbered, 'Numbering'),
        block('x', TextBlockKind.todo, 'To-do'),
        KeyAction(
          '>',
          'Indent',
          run: () => _text.indent(1),
          enabled: can,
          stays: true,
        ),
        KeyAction(
          '<',
          'Outdent',
          run: () => _text.indent(-1),
          enabled: can,
          stays: true,
        ),
      ]),
      KeyGroup(title: 'Type', <KeyAction>[
        KeyAction(
          'f',
          'Font: ${state.font ?? 'Default'}',
          run: () => unawaited(_chooseFont(state.font)),
          enabled: can,
        ),
        KeyAction(
          ']',
          'Larger: ${_points(state.fontSize)} pt',
          run: () => _stepFontSize(1),
          enabled: can,
          stays: true,
        ),
        KeyAction(
          '[',
          'Smaller',
          run: () => _stepFontSize(-1),
          enabled: can,
          stays: true,
        ),
      ]),
    ]);
  }

  static String _points(double points) => points == points.roundToDouble()
      ? points.toStringAsFixed(0)
      : points.toStringAsFixed(1);

  void _stepFontSize(int by) {
    const sizes = RichTextStyles.pointSizes;
    final current = _text.state.fontSize;
    final at = sizes.indexWhere((size) => size >= current);
    final from = at < 0 ? sizes.length - 1 : at;
    final to = by > 0 && at >= 0 && sizes[at] > current ? from : from + by;
    _text.setFontSize(sizes[to.clamp(0, sizes.length - 1)]);
  }

  /// Asks for a typeface by a few letters of its name: the page's own,
  /// those the app brings and those on this computer, each named in itself.
  Future<void> _chooseFont(String? current) => showChooser(
    context,
    hintFor: (_) => 'Type a typeface',
    choicesFor: (ref, typed) {
      final installed = ref.watch(installedTypefacesProvider).value;
      final families = <String?>[
        null,
        ...Typefaces.bundled,
        for (final family in installed ?? Typefaces.common)
          if (!Typefaces.bundled.contains(family)) family,
      ];
      final query = typed.trim();
      return <Choice>[
        for (final family in families)
          if (query.isEmpty || fuzzyScore(query, family ?? 'Default') != null)
            Choice(
              title: family ?? 'Default',
              detail: family == null ? 'The page’s own' : null,
              hint: family == current ? 'In use' : null,
              titleStyle: family == null
                  ? null
                  : TextStyle(
                      fontFamily: family,
                      fontFamilyFallback: RichTextStyles.typefacesFor(family),
                    ),
              run: () => _text.setFont(family),
            ),
      ];
    },
  );

  // --------------------------------------------------------------- colours

  /// Colours to pick, as tiles: the palette, those picked lately, the
  /// inverse where [offersInverse], none where [noneLabel] names it, and any
  /// other colour.
  KeyLayer colours(
    String title, {
    required int? current,
    required ValueChanged<int?> onPicked,
    String? noneLabel,
    bool offersInverse = false,
  }) {
    const none = 'x';
    const inverse = 'v';
    const more = '+';
    final colours = <({int color, String name})>[
      ...NotePalette.presets,
      for (final color in NotePalette.recent.value)
        (color: color, name: NotePalette.nameOf(color)),
    ];
    final keys = galleryKeys(
      colours.length,
      taken: const <String>{none, inverse, more},
    );
    final chosen = current == null ? null : NotePalette.opaque(current);
    return KeyLayer.of(title, tiles: true, <KeyAction>[
      for (final (index, entry) in colours.indexed)
        KeyAction(
          keys[index],
          entry.name,
          run: () => onPicked(entry.color),
          checked: entry.color == chosen,
          preview: _Dot(entry.color),
        ),
      if (offersInverse)
        KeyAction(
          inverse,
          NotePalette.inverse.name,
          run: () => onPicked(NotePalette.inverse.color),
          checked: current == NoteColors.inverse,
          preview: const _Dot(NoteColors.inverse),
        ),
      if (noneLabel != null)
        KeyAction(
          none,
          noneLabel,
          run: () => onPicked(null),
          checked: current == null,
          preview: const _Dot(null),
        ),
      KeyAction(
        more,
        'More colours…',
        run: () => unawaited(_pickColour(current, onPicked)),
        preview: Mark(MarkShape.add, color: context.tones.muted),
      ),
    ]);
  }

  Future<void> _pickColour(int? current, ValueChanged<int?> onPicked) async {
    final picked = await showColorPicker(
      context,
      initial: current ?? NotePalette.presets.first.color,
    );
    if (picked == null) return;
    NotePalette.remember(picked);
    onPicked(picked);
  }

  // ------------------------------------------------------------------- ink

  /// The pens, the highlighter, shapes and the eraser, and their ink.
  KeyLayer draw() {
    final tool = _canvas.tool;
    final ink = commands.ink;
    KeyAction take(String key, CanvasTool each, String label) => KeyAction(
      key,
      label,
      run: () => commands.onToolSelected(each),
      checked: tool == each,
    );
    return KeyLayer('Draw', <KeyGroup>[
      KeyGroup(title: 'Tools', <KeyAction>[
        take('p', CanvasTool.pen, 'Pen'),
        take('h', CanvasTool.highlighter, 'Highlighter'),
        take('e', CanvasTool.eraser, 'Eraser'),
        KeyAction(
          's',
          'Shapes',
          layer: shapes,
          checked: tool == CanvasTool.shape,
        ),
        take('l', CanvasTool.lasso, 'Lasso select'),
      ]),
      KeyGroup(
        title: ink.tool == InkTool.highlighter ? 'Highlighter' : 'Pen',
        <KeyAction>[
          KeyAction(
            'c',
            'Colour: ${NotePalette.nameOf(ink.color)}',
            layer: () => colours(
              ink.tool == InkTool.highlighter ? 'Highlighter' : 'Pen',
              current: ink.color,
              offersInverse: ink.tool != InkTool.highlighter,
              onPicked: (color) => commands.changeInk(
                commands.ink.copyWith(color: NotePalette.opaque(color!)),
              ),
            ),
            preview: _Dot(ink.color),
          ),
          KeyAction(
            ']',
            'Thicker: ${_points(ink.width)} pt',
            run: () => commands.stepInkWidth(1),
            stays: true,
          ),
          KeyAction(
            '[',
            'Thinner',
            run: () => commands.stepInkWidth(-1),
            stays: true,
          ),
        ],
      ),
    ]);
  }

  /// Every shape, to drag out with the shape tool.
  KeyLayer shapes() {
    final kinds = <ShapeKind>[
      for (final family in ShapeFamily.values) ...ShapeKind.of(family),
    ];
    final keys = galleryKeys(kinds.length);
    final inHand = _canvas.tool == CanvasTool.shape;
    return KeyLayer.of('Shapes', tiles: true, <KeyAction>[
      for (final (index, kind) in kinds.indexed)
        KeyAction(
          keys[index],
          kind.label,
          run: () {
            _canvas.setShapeKind(kind);
            commands.onToolSelected(CanvasTool.shape);
          },
          checked: inHand && _canvas.shapeKind == kind,
          preview: ShapeGlyph(kind, size: 22),
        ),
    ]);
  }

  // -------------------------------------------------------------- formulas

  /// The key each gallery of formulas is opened with.
  static String _keyOf(MathGallery gallery) => switch (gallery.name) {
    'Fraction' => 'f',
    'Script' => 's',
    'Radical' => 'r',
    'Integral' => 'i',
    'Large operator' => 'o',
    'Bracket' => 'b',
    'Accent' => 'a',
    'Function' => 'u',
    'Matrix' => 'x',
    'Greek' => 'g',
    'Operators' => '+',
    'Relations' => '=',
    'Arrows' => '>',
    _ => '.',
  };

  /// Structures and symbols to put into a formula, the syntax formulas are
  /// typed in, and the cheat sheet.
  KeyLayer math() {
    final state = _text.state;
    KeyAction gallery(MathGallery gallery) => KeyAction(
      _keyOf(gallery),
      gallery.name,
      layer: () => _gallery(gallery),
      preview: _Formula(gallery.icon, size: 13),
    );
    final latexOnly = state.inFormula && state.latexOnly;
    final syntax = latexOnly ? MathMode.latex : ref.read(mathSyntaxProvider);
    return KeyLayer('Formulas', <KeyGroup>[
      KeyGroup(title: 'Structures', <KeyAction>[
        for (final each in MathGalleries.structures) gallery(each),
      ]),
      KeyGroup(title: 'Symbols', <KeyAction>[
        for (final each in MathGalleries.symbols) gallery(each),
      ]),
      KeyGroup(title: 'Formula', <KeyAction>[
        KeyAction(
          'm',
          state.inFormula ? 'Finish the formula' : 'New formula',
          run: commands.onFormula,
        ),
        KeyAction(
          'l',
          syntax == MathMode.latex
              ? 'Typed in LaTeX: switch to Simple'
              : 'Typed simply: switch to LaTeX',
          run: ref.read(mathSyntaxProvider.notifier).toggle,
          enabled: !latexOnly,
        ),
        KeyAction(
          'c',
          'Cheat sheet',
          run: ref.read(cheatSheetProvider.notifier).toggle,
          checked: ref.read(cheatSheetProvider),
        ),
      ]),
    ]);
  }

  KeyLayer _gallery(MathGallery gallery) {
    final keys = galleryKeys(gallery.templates.length);
    return KeyLayer.of(gallery.name, tiles: true, <KeyAction>[
      for (final (index, template) in gallery.templates.indexed)
        KeyAction(
          keys[index],
          template.name,
          run: () => commands.onMathInsert(template),
          preview: _Formula(template.preview),
        ),
    ]);
  }

  // ---------------------------------------------------------------- sheets

  /// The sheets a page is shown as.
  KeyLayer sheets() {
    final sheets = _canvas.document.canvas.sheetsShown;
    return KeyLayer.of('Sheets', <KeyAction>[
      command('a', AppCommand.addSheet),
      KeyAction('p', 'Paper', layer: _paper, enabled: sheets != null),
      command('k', AppCommand.moveSheetUp, label: 'Move up'),
      command('j', AppCommand.moveSheetDown, label: 'Move down'),
      command('d', AppCommand.deleteSheet),
      KeyAction(
        'l',
        'Shown as sheets',
        run: () => ref.read(commandHandlersProvider).run(AppCommand.pageLayout),
        checked: _canvas.fold != null,
      ),
    ]);
  }

  /// What is printed on the sheet in view, and the choice to print it on
  /// every sheet.
  KeyLayer _paper() {
    final sheets = _canvas.document.canvas.sheetsShown!;
    final sheet = _canvas.currentSheet;
    final current = sheets.templates[sheet];
    final keys = galleryKeys(
      SheetTemplate.values.length,
      taken: const <String>{'e'},
    );
    return KeyLayer.of('Paper of sheet ${sheet + 1}', tiles: true, <KeyAction>[
      for (final (index, template) in SheetTemplate.values.indexed)
        KeyAction(
          keys[index],
          template.label,
          run: () => _canvas.setSheetTemplate(template, sheet: sheet),
          checked: template == current,
          preview: SheetThumbnail(
            template: template,
            width: 24,
            size: sheets.size,
            orientation: sheets.orientationOf(sheet),
          ),
        ),
      KeyAction(
        'e',
        '${current.label} on every sheet',
        run: () => _canvas.setSheetTemplate(current),
        enabled: sheets.templates.any((each) => each != current),
        preview: Mark(MarkShape.check, color: context.tones.muted),
      ),
    ]);
  }

  // ------------------------------------------------------------------ view

  /// Zoom, the page's layout and preview, and light or dark.
  KeyLayer view() => KeyLayer.of('View', <KeyAction>[
    KeyAction(
      '+',
      'Zoom in',
      run: commands.onZoomIn,
      also: const <String>['='],
      stays: true,
    ),
    KeyAction('-', 'Zoom out', run: commands.onZoomOut, stays: true),
    KeyAction('0', 'Actual size', run: commands.onActualSize),
    KeyAction('f', 'Fit page', run: commands.onFitPage),
    KeyAction(
      'l',
      'Shown as sheets',
      run: () => ref.read(commandHandlersProvider).run(AppCommand.pageLayout),
      checked: _canvas.fold != null,
    ),
    KeyAction(
      'p',
      'Page preview',
      run: ref.read(minimapProvider.notifier).toggle,
      checked: ref.read(minimapProvider),
    ),
    command('d', AppCommand.toggleDark),
  ]);

  // -------------------------------------------------------------- spelling

  /// Checking the spelling, and the languages it is checked in.
  KeyLayer spelling() {
    final state = ref.read(spellingProvider);
    final installed =
        ref.read(installedDictionariesProvider).value ??
        const <InstalledDictionary>[];
    final keys = galleryKeys(installed.length, taken: const <String>{'s', 'd'});
    return KeyLayer('Spelling', <KeyGroup>[
      KeyGroup(<KeyAction>[
        KeyAction(
          's',
          'Check spelling',
          run: () => ref.read(commandHandlersProvider).run(AppCommand.spelling),
          checked: state.enabled,
        ),
        command('d', AppCommand.dictionaries, label: 'Dictionaries…'),
      ]),
      KeyGroup(title: 'Languages', <KeyAction>[
        for (final (index, dictionary) in installed.indexed)
          KeyAction(
            keys[index],
            dictionary.name,
            run: () => ref
                .read(spellingProvider.notifier)
                .useLanguage(
                  dictionary.code,
                  used: !state.languages.contains(dictionary.code),
                ),
            checked: state.languages.contains(dictionary.code),
            stays: true,
          ),
      ]),
    ]);
  }
}

/// A colour, as a dot of it — or an empty ring for none.
class _Dot extends StatelessWidget {
  const _Dot(this.color);

  final int? color;

  @override
  Widget build(BuildContext context) {
    final tones = context.tones;
    final color = this.color;
    return Container(
      width: 16,
      height: 16,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        border: Border.all(color: tones.strongLine),
        color: color == null || color == NoteColors.inverse
            ? null
            : Color(color | 0xFF000000),
        gradient: color == NoteColors.inverse
            ? const LinearGradient(
                colors: <Color>[Color(0xFFFFFFFF), Color(0xFF000000)],
                stops: <double>[0.5, 0.5],
              )
            : null,
      ),
    );
  }
}

/// [latex], typeset small in the text's colour.
class _Formula extends StatelessWidget {
  const _Formula(this.latex, {this.size = 16});

  final String latex;
  final double size;

  @override
  Widget build(BuildContext context) => FittedBox(
    fit: BoxFit.scaleDown,
    child: MathView(
      source: latex,
      mode: MathMode.latex,
      displayStyle: false,
      textStyle: TextStyle(fontSize: size, color: context.tones.text),
    ),
  );
}
