part of 'ribbon_items.dart';

PenSettings _inkSettings(RibbonCommands commands) =>
    commands.lastInkTool() == CanvasTool.highlighter
    ? commands.canvas.highlighterSettings
    : commands.canvas.penSettings;

/// Changes the pen or highlighter and takes it up, as picking a pen colour in
/// OneNote does — unless the shape tool, which draws in the pen's ink, is in
/// hand.
void _changeInk(RibbonCommands commands, PenSettings settings) {
  commands.canvas.setPen(settings);
  if (commands.canvas.tool == CanvasTool.shape &&
      settings.tool != InkTool.highlighter) {
    return;
  }
  commands.onToolSelected(
    settings.tool == InkTool.highlighter
        ? CanvasTool.highlighter
        : CanvasTool.pen,
  );
}

/// The shapes: the one the shape tool drags out, which the button takes
/// up, and every shape, family by family, to choose another.
class _ShapesGallery extends StatefulWidget {
  const _ShapesGallery({
    required this.commands,
    required this.label,
    required this.tooltip,
  });

  final RibbonCommands commands;
  final String label;
  final String tooltip;

  @override
  State<_ShapesGallery> createState() => _ShapesGalleryState();
}

class _ShapesGalleryState extends State<_ShapesGallery> {
  final MenuController _menu = MenuController();

  static const double _tile = 40;
  static const int _columns = 6;

  void _choose(ShapeKind kind) {
    _menu.close();
    widget.commands.canvas.setShapeKind(kind);
    widget.commands.onToolSelected(CanvasTool.shape);
  }

  @override
  Widget build(BuildContext context) {
    final canvas = widget.commands.canvas;
    return _CanvasSelect<(CanvasTool, ShapeKind)>(
      canvas: canvas,
      select: () => (canvas.tool, canvas.shapeKind),
      builder: (context, value) {
        final (tool, chosen) = value;
        final inHand = tool == CanvasTool.shape;
        return MenuAnchor(
          controller: _menu,
          menuChildren: <Widget>[
            Padding(
              padding: const EdgeInsets.all(8),
              child: SizedBox(
                width: _tile * _columns,
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: <Widget>[
                    for (final family in ShapeFamily.values) ...<Widget>[
                      Padding(
                        padding: const EdgeInsets.fromLTRB(4, 6, 4, 2),
                        child: SmallCaps(family.label),
                      ),
                      Wrap(
                        children: <Widget>[
                          for (final kind in ShapeKind.of(family))
                            _ShapeTile(
                              kind: kind,
                              size: _tile,
                              selected: inHand && kind == chosen,
                              onTap: () => _choose(kind),
                            ),
                        ],
                      ),
                    ],
                  ],
                ),
              ),
            ),
          ],
          child: RibbonLargeButton(
            glyph: ShapeGlyph(chosen, size: 22),
            label: widget.label,
            tooltip:
                '${widget.tooltip}\nShift keeps it square, or its '
                'lines to steps of 15°',
            selected: inHand,
            onPressed: () => _menu.isOpen ? _menu.close() : _menu.open(),
          ),
        );
      },
    );
  }
}

/// What is printed on the sheet in view, to choose, and the choice to
/// print that on every sheet.
class _PaperMenu extends StatefulWidget {
  const _PaperMenu({required this.canvas});

  final CanvasController canvas;

  @override
  State<_PaperMenu> createState() => _PaperMenuState();
}

class _PaperMenuState extends State<_PaperMenu> {
  final MenuController _menu = MenuController();

  @override
  Widget build(BuildContext context) {
    final canvas = widget.canvas;
    return _CanvasSelect<(Sheets?, int)>(
      canvas: canvas,
      select: () => (canvas.document.canvas.sheetsShown, canvas.currentSheet),
      builder: (context, value) {
        final (sheets, sheet) = value;
        final current = sheets?.templates[sheet];
        return MenuAnchor(
          controller: _menu,
          menuChildren: <Widget>[
            if (sheets != null && current != null) ...<Widget>[
              Padding(
                padding: const EdgeInsets.fromLTRB(12, 10, 12, 4),
                child: SmallCaps('Sheet ${sheet + 1}'),
              ),
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 8),
                child: SizedBox(
                  width: 3 * 78,
                  child: SheetTemplatePicker(
                    selected: current,
                    size: sheets.size,
                    onSelected: (template) {
                      _menu.close();
                      canvas.setSheetTemplate(template, sheet: sheet);
                    },
                  ),
                ),
              ),
              const Divider(height: 12),
              MenuItemButton(
                onPressed: sheets.templates.every((t) => t == current)
                    ? null
                    : () => canvas.setSheetTemplate(current),
                child: Text('${current.label} on every sheet'),
              ),
            ],
          ],
          child: RibbonButton(
            face: ribbonFaceOf(RibbonItem.paper),
            tooltip: 'Paper\nWhat is printed on the sheet in view',
            onPressed: sheets == null
                ? null
                : () => _menu.isOpen ? _menu.close() : _menu.open(),
          ),
        );
      },
    );
  }
}

/// One shape in the gallery, drawn as it is drawn on the page.
class _ShapeTile extends StatelessWidget {
  const _ShapeTile({
    required this.kind,
    required this.size,
    required this.selected,
    required this.onTap,
  });

  final ShapeKind kind;
  final double size;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return _GalleryCell(
      tooltip: kind.label,
      selected: selected,
      onTap: onTap,
      size: Size.square(size),
      child: ShapeGlyph(kind, size: size - 14),
    );
  }
}

/// One choice in a gallery, picked with a click: shaded, with a line
/// beneath, while it is [selected].
class _GalleryCell extends StatelessWidget {
  const _GalleryCell({
    required this.tooltip,
    required this.selected,
    required this.onTap,
    required this.size,
    required this.child,
  });

  final String tooltip;
  final bool selected;
  final VoidCallback onTap;
  final Size size;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    final tones = context.tones;
    return Tooltip(
      message: tooltip,
      child: InkWell(
        onTap: onTap,
        child: Container(
          width: size.width,
          height: size.height,
          alignment: Alignment.center,
          decoration: BoxDecoration(
            color: selected ? tones.selection : null,
            border: Border(
              bottom: BorderSide(
                color: selected ? tones.emphasis : Colors.transparent,
                width: 2,
              ),
            ),
          ),
          child: child,
        ),
      ),
    );
  }
}

/// The palette, for the pen or highlighter in hand.
class _InkColourGallery extends StatelessWidget {
  const _InkColourGallery({required this.commands});

  final RibbonCommands commands;

  /// Custom colours shown after the presets.
  static const int _recent = 4;

  /// How large a colour's swatch is.
  static const double _swatch = 18;

  @override
  Widget build(BuildContext context) {
    final canvas = commands.canvas;
    return _CanvasSelect<PenSettings>(
      canvas: canvas,
      select: () => _inkSettings(commands),
      builder: (context, settings) => ValueListenableBuilder<List<int>>(
        valueListenable: NotePalette.recent,
        builder: (context, recent, _) {
          final owner = settings.tool == InkTool.highlighter
              ? 'Highlighter'
              : 'Pen';
          final colours = <({int color, String name})>[
            ...NotePalette.presets,
            for (final color in recent.take(_recent))
              (color: color, name: NotePalette.nameOf(color)),
          ];
          void pick(int color) => _changeInk(
            commands,
            settings.copyWith(color: NotePalette.opaque(color)),
          );
          Widget swatch(({int color, String name}) entry) => NoteSwatch(
            color: entry.color,
            name: '$owner colour: ${entry.name}',
            selected: entry.color == NotePalette.opaque(settings.color),
            size: _swatch,
            onTap: () => pick(entry.color),
          );

          return SizedBox(
            height: RibbonMetrics.content,
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: <Widget>[
                Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: <Widget>[
                    // No colour of its own, the inverse stands apart, in a
                    // column of its own, the place beneath it left empty.
                    if (settings.tool != InkTool.highlighter)
                      swatch(NotePalette.inverse),
                    for (var i = 0; i < colours.length; i += 2)
                      Column(
                        children: <Widget>[
                          for (final entry in colours.skip(i).take(2))
                            swatch(entry),
                        ],
                      ),
                  ],
                ),
                RibbonButton(
                  face: const Mark(MarkShape.add),
                  tooltip: 'More colours…',
                  onPressed: () async {
                    final picked = await showColorPicker(
                      context,
                      initial: settings.color,
                    );
                    if (picked == null) return;
                    NotePalette.remember(picked);
                    pick(picked);
                  },
                ),
              ],
            ),
          );
        },
      ),
    );
  }
}

/// Line widths, for the pen or highlighter in hand.
class _InkThicknessGallery extends StatelessWidget {
  const _InkThicknessGallery({required this.commands});

  final RibbonCommands commands;

  @override
  Widget build(BuildContext context) => _CanvasSelect<PenSettings>(
    canvas: commands.canvas,
    select: () => _inkSettings(commands),
    builder: (context, settings) {
      final highlighter = settings.tool == InkTool.highlighter;
      return SizedBox(
        height: RibbonMetrics.content,
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: <Widget>[
            for (final width
                in highlighter
                    ? RibbonCommands.highlighterWidths
                    : RibbonCommands.penWidths)
              _WidthChoice(
                width: width,
                color: settings.color,
                highlighter: highlighter,
                selected: width == settings.width,
                onTap: () =>
                    _changeInk(commands, settings.copyWith(width: width)),
              ),
          ],
        ),
      );
    },
  );
}

/// One width choice, drawn as the line it would make.
class _WidthChoice extends StatelessWidget {
  const _WidthChoice({
    required this.width,
    required this.color,
    required this.highlighter,
    required this.selected,
    required this.onTap,
  });

  final double width;
  final int color;
  final bool highlighter;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final tones = context.tones;
    final shown = highlighter
        ? Color(color | 0xFF000000).withValues(alpha: 0.45)
        : color == NoteColors.inverse
        ? tones.text
        : Color(color | 0xFF000000);
    final points = width.toStringAsFixed(width % 1 == 0 ? 0 : 1);
    // Each drawn as the stroke it makes: the pen's a line that thick, the
    // highlighter's a nib that tall.
    return _GalleryCell(
      tooltip: highlighter ? 'Highlighter: $points pt' : 'Pen: $points pt',
      selected: selected,
      onTap: onTap,
      size: const Size(30, 44),
      child: highlighter
          ? Container(
              width: (width * 0.16).clamp(2, 5),
              height: (width * 0.7).clamp(6, 28),
              color: shown,
            )
          : Container(
              width: 18,
              height: (width * 1.2).clamp(1, 10),
              color: shown,
            ),
    );
  }
}

/// A Math tab button: a structure or symbol family, whose variants drop down
/// in a grid, each drawn as it will look.
class _MathGalleryButton extends StatefulWidget {
  const _MathGalleryButton({required this.gallery, required this.onInsert});

  final MathGallery gallery;
  final ValueChanged<MathTemplate> onInsert;

  @override
  State<_MathGalleryButton> createState() => _MathGalleryButtonState();
}

class _MathGalleryButtonState extends State<_MathGalleryButton> {
  final MenuController _menu = MenuController();

  @override
  Widget build(BuildContext context) {
    final tones = context.tones;
    final gallery = widget.gallery;
    final tileWidth = gallery.columns >= 7 ? 40.0 : 64.0;
    return MenuAnchor(
      controller: _menu,
      menuChildren: <Widget>[
        Padding(
          padding: const EdgeInsets.all(6),
          child: SizedBox(
            width: tileWidth * gallery.columns,
            child: Wrap(
              children: <Widget>[
                for (final template in gallery.templates)
                  _MathTile(
                    template: template,
                    width: tileWidth,
                    onTap: () {
                      _menu.close();
                      widget.onInsert(template);
                    },
                  ),
              ],
            ),
          ),
        ),
      ],
      child: RibbonLargeButton(
        glyph: FittedBox(
          fit: BoxFit.scaleDown,
          child: MathView(
            source: gallery.icon,
            mode: MathMode.latex,
            displayStyle: false,
            textStyle: TextStyle(fontSize: 18, color: tones.text),
          ),
        ),
        label: gallery.name,
        tooltip: gallery.name,
        onPressed: () => _menu.isOpen ? _menu.close() : _menu.open(),
      ),
    );
  }
}

/// One variant in a Math tab gallery.
class _MathTile extends StatelessWidget {
  const _MathTile({
    required this.template,
    required this.width,
    required this.onTap,
  });

  final MathTemplate template;
  final double width;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final tones = context.tones;
    return Tooltip(
      message: template.name,
      child: InkWell(
        onTap: onTap,
        child: Container(
          width: width,
          height: width >= 60 ? 52 : 40,
          padding: const EdgeInsets.all(6),
          alignment: Alignment.center,
          child: FittedBox(
            fit: BoxFit.scaleDown,
            child: MathView(
              source: template.preview,
              mode: MathMode.latex,
              displayStyle: false,
              textStyle: TextStyle(fontSize: 18, color: tones.text),
            ),
          ),
        ),
      ),
    );
  }
}
