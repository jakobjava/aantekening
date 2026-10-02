part of 'ribbon_items.dart';

/// Paragraph style: normal, headings, code, quotation.
class _StyleMenu extends StatelessWidget {
  const _StyleMenu({required this.controller, required this.enabled});

  final TextBoxEditorController controller;
  final bool enabled;

  static const List<(TextBlockKind, String, EditorKey?)> _styles =
      <(TextBlockKind, String, EditorKey?)>[
        (TextBlockKind.paragraph, 'Normal', EditorKey.normal),
        (TextBlockKind.heading1, 'Heading 1', EditorKey.heading1),
        (TextBlockKind.heading2, 'Heading 2', EditorKey.heading2),
        (TextBlockKind.heading3, 'Heading 3', EditorKey.heading3),
        (TextBlockKind.code, 'Code', null),
        (TextBlockKind.quote, 'Quote', EditorKey.quote),
      ];

  @override
  Widget build(BuildContext context) {
    final current = controller.state.blockKind;
    final label = _styles
        .firstWhere((style) => style.$1 == current, orElse: () => _styles.first)
        .$2;

    return MenuAnchor(
      builder: (context, menu, _) => _MenuButton(
        label: label,
        width: 72,
        tooltip: 'Paragraph style',
        onPressed: enabled
            ? () => menu.isOpen ? menu.close() : menu.open()
            : null,
      ),
      menuChildren: <Widget>[
        for (final (kind, name, key) in _styles)
          MenuItemButton(
            // A menu sets a style rather than toggling it, so choosing the
            // current one changes nothing.
            onPressed: kind == current
                ? null
                : () => controller.toggleBlockKind(kind),
            trailingIcon: key == null
                ? null
                : KeyHint(
                    <String>[
                      if (key.chords.isNotEmpty) key.keys,
                      if (key.typed case final typed?) '"$typed"',
                    ].join('  or  '),
                  ),
            child: Text(name),
          ),
      ],
    );
  }
}

/// Font size, in points.
class _FontSizeMenu extends StatelessWidget {
  const _FontSizeMenu({required this.controller, required this.enabled});

  final TextBoxEditorController controller;
  final bool enabled;

  static String _format(double points) => points == points.roundToDouble()
      ? points.toStringAsFixed(0)
      : points.toStringAsFixed(1);

  @override
  Widget build(BuildContext context) {
    final current = controller.state.fontSize;
    return MenuAnchor(
      builder: (context, menu, _) => _MenuButton(
        label: _format(current),
        width: 22,
        tooltip: 'Font size',
        onPressed: enabled
            ? () => menu.isOpen ? menu.close() : menu.open()
            : null,
      ),
      menuChildren: <Widget>[
        for (final size in RichTextStyles.pointSizes)
          MenuItemButton(
            onPressed: () => controller.setFontSize(size),
            trailingIcon: size == current
                ? Mark(MarkShape.check, color: context.tones.emphasis)
                : null,
            child: SizedBox(width: 40, child: Text(_format(size))),
          ),
      ],
    );
  }
}

/// The typeface: the page's own, those the app brings, and those installed
/// on this computer, each named in itself.
class _FontMenu extends ConsumerWidget {
  const _FontMenu({required this.controller, required this.enabled});

  final TextBoxEditorController controller;
  final bool enabled;

  static const String _default = 'Default';

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final current = controller.state.font;
    final installed = ref.watch(installedTypefacesProvider).value;
    final others = <String>[
      for (final family in installed ?? Typefaces.common)
        if (!Typefaces.bundled.contains(family)) family,
    ];
    final sections = <(String, List<String>)>[
      if (current != null &&
          !Typefaces.bundled.contains(current) &&
          !others.contains(current))
        ('In this text', <String>[current]),
      ('In the app', Typefaces.bundled),
      (installed == null ? 'Common' : 'On this computer', others),
    ];
    // One list, headings among the families, built as it is scrolled: a
    // computer can have hundreds.
    final rows = <({String? heading, String? family})>[
      (heading: null, family: null),
      for (final (heading, families) in sections) ...[
        (heading: heading, family: null),
        for (final family in families) (heading: null, family: family),
      ],
    ];

    return MenuAnchor(
      builder: (context, menu, _) => _MenuButton(
        label: current ?? _default,
        width: 92,
        tooltip: 'Font',
        onPressed: enabled
            ? () => menu.isOpen ? menu.close() : menu.open()
            : null,
      ),
      menuChildren: <Widget>[
        SizedBox(
          width: 260,
          height: math.min(420, rows.length * _rowHeight),
          child: ListView.builder(
            // The menu scrolls itself; this list scrolls apart from it.
            primary: false,
            itemCount: rows.length,
            itemExtent: _rowHeight,
            itemBuilder: (context, index) {
              final (:heading, :family) = rows[index];
              if (heading != null) {
                return Padding(
                  padding: const EdgeInsets.fromLTRB(12, 12, 12, 0),
                  child: SmallCaps(heading),
                );
              }
              return MenuItemButton(
                onPressed: () => controller.setFont(family),
                trailingIcon: family == current
                    ? Mark(MarkShape.check, color: context.tones.emphasis)
                    : null,
                child: Text(
                  family ?? _default,
                  overflow: TextOverflow.ellipsis,
                  style: family == null
                      ? null
                      : TextStyle(
                          fontFamily: family,
                          fontFamilyFallback: RichTextStyles.typefacesFor(
                            family,
                          ),
                          fontSize: 14,
                        ),
                ),
              );
            },
          ),
        ),
      ],
    );
  }

  static const double _rowHeight = 32;
}

/// A drop-down's face: its current value and an arrow, in a box.
class _MenuButton extends StatelessWidget {
  const _MenuButton({
    required this.label,
    required this.width,
    required this.tooltip,
    required this.onPressed,
  });

  final String label;
  final double width;
  final String tooltip;
  final VoidCallback? onPressed;

  @override
  Widget build(BuildContext context) => Tooltip(
    message: tooltip,
    child: SizedBox(
      height: RibbonMetrics.row - 4,
      child: OutlinedButton(
        onPressed: onPressed,
        style: OutlinedButton.styleFrom(
          padding: const EdgeInsets.only(left: 7, right: 4),
          minimumSize: Size.zero,
          textStyle: Theme.of(context).textTheme.labelMedium,
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: <Widget>[
            SizedBox(
              width: width,
              child: Text(label, overflow: TextOverflow.ellipsis),
            ),
            const SizedBox(width: 4),
            const Mark(MarkShape.dropdown, size: 10),
          ],
        ),
      ),
    ),
  );
}

/// A colour button: the letter applies the colour shown beneath it; the
/// arrow opens the palette.
class _ColorButton extends StatefulWidget {
  const _ColorButton({
    required this.face,
    required this.tooltip,
    required this.name,
    required this.current,
    required this.fallback,
    required this.noneLabel,
    required this.enabled,
    required this.onChanged,
    this.offersInverse = false,
  });

  /// The letters shown over the colour.
  final String face;
  final String tooltip;

  /// What the colour is of, before its name: "Text colour: Red".
  final String name;

  /// The colour of the text under the caret, or null for none.
  final int? current;

  /// What the button applies before any colour has been chosen here.
  final int fallback;

  final String noneLabel;
  final bool enabled;

  /// Whether the inverse of what is beneath is offered too.
  final bool offersInverse;

  /// Called with the chosen colour, opaque, or null for [noneLabel].
  final ValueChanged<int?> onChanged;

  @override
  State<_ColorButton> createState() => _ColorButtonState();
}

class _ColorButtonState extends State<_ColorButton> {
  final MenuController _menu = MenuController();
  late int _last = widget.fallback;

  void _apply(int? color) {
    if (color != null) setState(() => _last = NotePalette.opaque(color));
    _menu.close();
    widget.onChanged(color);
  }

  @override
  Widget build(BuildContext context) {
    return MenuAnchor(
      controller: _menu,
      menuChildren: <Widget>[
        ColorSwatchPanel(
          selected: widget.current,
          onSelected: _apply,
          offersInverse: widget.offersInverse,
          noneLabel: widget.noneLabel,
          onNone: () => _apply(null),
          onPickerOpened: _menu.close,
        ),
      ],
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: <Widget>[
          RibbonButton(
            face: ColourBar(
              color: _last,
              child: Text(
                widget.face,
                style: const TextStyle(fontSize: 12.5, height: 1.1),
              ),
            ),
            tooltip:
                '${widget.tooltip}\n${widget.name}: '
                '${NotePalette.nameOf(_last)}',
            onPressed: widget.enabled ? () => widget.onChanged(_last) : null,
          ),
          RibbonButton(
            face: const Mark(MarkShape.dropdown, size: 10),
            padding: EdgeInsets.zero,
            tooltip: '${widget.name}: choose',
            onPressed: widget.enabled
                ? () => _menu.isOpen ? _menu.close() : _menu.open()
                : null,
          ),
        ],
      ),
    );
  }
}

/// The languages spelling is checked in: those installed, ticked while they
/// are used — and the settings, where dictionaries are downloaded, added
/// and removed.
class _LanguagesMenu extends ConsumerWidget {
  const _LanguagesMenu({required this.item});

  final RibbonItem item;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final used = ref.watch(spellingProvider.select((s) => s.languages));
    final reading = ref.watch(installedDictionariesProvider);
    final installed = reading.value ?? const <InstalledDictionary>[];

    return MenuAnchor(
      builder: (context, menu, _) => RibbonLargeButton(
        label: item.label,
        icon: item.icon,
        tooltip: 'Languages\nThe languages spelling is checked in',
        onPressed: () => menu.isOpen ? menu.close() : menu.open(),
      ),
      menuChildren: <Widget>[
        if (installed.isEmpty)
          MenuItemButton(
            child: Text(
              reading.isLoading
                  ? 'Looking for dictionaries…'
                  : 'No dictionaries yet',
            ),
          )
        else
          for (final dictionary in installed)
            CheckboxMenuButton(
              value: used.contains(dictionary.code),
              onChanged: (value) => ref
                  .read(spellingProvider.notifier)
                  .useLanguage(dictionary.code, used: value ?? false),
              child: Text(dictionary.name),
            ),
        const Divider(height: 9),
        MenuItemButton(
          onPressed: () =>
              ref.read(commandHandlersProvider).run(AppCommand.dictionaries),
          child: const Text('Dictionaries…'),
        ),
      ],
    );
  }
}
