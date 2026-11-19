/// Saving notebooks, sections and pages as PDFs: each page on its paper —
/// a page shown as sheets a sheet to a page, one without end cut where
/// nothing is cut through — and a notebook's sections and pages as the
/// PDF's bookmarks.
library;

import 'dart:async';
import 'dart:io';
import 'dart:isolate';

import 'package:aantekening_canvas/aantekening_canvas.dart';
import 'package:aantekening_core/aantekening_core.dart';
import 'package:aantekening_interchange/aantekening_interchange.dart';
import 'package:aantekening_store/aantekening_store.dart';
import 'package:file_selector/file_selector.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:url_launcher/url_launcher.dart';

import '../editor/page_title.dart';
import '../look/controls.dart';
import '../look/glass.dart';
import '../look/motion.dart';
import '../look/tones.dart';
import '../preferences.dart';
import '../providers.dart';
import '../shell/library_menu.dart';
import 'export_flow.dart' show fileName;
import 'notes_keeper.dart';
import 'page_printer.dart';
import 'printed_text.dart';

/// How sharp the pages of a PDF are drawn.
enum PdfQuality {
  small('Small', 150),
  standard('Standard', 200),
  sharp('Sharp', 300);

  const PdfQuality(this.label, this.dpi);

  final String label;

  /// Pixels to an inch of paper.
  final double dpi;
}

/// How a PDF is made: how a page without sheets is put on paper — A4, as
/// the paper is where the notes are kept — how sharp, and whether the
/// files the notes hold are attached to it.
@immutable
class PdfChoices {
  const PdfChoices({
    this.print = CanvasPrint.sheets,
    this.quality = PdfQuality.standard,
    this.attach = true,
  });

  final CanvasPrint print;
  final PdfQuality quality;

  /// Whether the PDFs, pictures and files on the pages are attached to the
  /// PDF as they were brought in: whole, sharp, every page of a PDF.
  final bool attach;

  PdfChoices copyWith({
    CanvasPrint? print,
    PdfQuality? quality,
    bool? attach,
  }) => PdfChoices(
    print: print ?? this.print,
    quality: quality ?? this.quality,
    attach: attach ?? this.attach,
  );

  @override
  bool operator ==(Object other) =>
      other is PdfChoices &&
      other.print == print &&
      other.quality == quality &&
      other.attach == attach;

  @override
  int get hashCode => Object.hash(print, quality, attach);
}

/// The choices the last PDF was made with, offered for the next.
class PdfChoicesController extends Notifier<PdfChoices> {
  static const String _print = 'pdf.print';
  static const String _quality = 'pdf.quality';
  static const String _attach = 'pdf.attach';

  @override
  PdfChoices build() {
    const start = PdfChoices();
    return PdfChoices(
      print: ref.enumPreference(_print, CanvasPrint.values, start.print),
      quality: ref.enumPreference(_quality, PdfQuality.values, start.quality),
      attach: ref.preference(_attach) as bool? ?? start.attach,
    );
  }

  void remember(PdfChoices choices) {
    if (choices == state) return;
    state = choices;
    ref
      ..savePreference(_print, choices.print.name)
      ..savePreference(_quality, choices.quality.name)
      ..savePreference(_attach, choices.attach);
  }
}

final pdfChoicesProvider = NotifierProvider<PdfChoicesController, PdfChoices>(
  PdfChoicesController.new,
);

/// A bookmark of a PDF: [title], leading to the note page [page] — counted
/// in [PdfContents.pages] — with [children] beneath it.
class PdfMark {
  const PdfMark(this.title, this.page, [this.children = const <PdfMark>[]]);

  final String title;
  final int page;
  final List<PdfMark> children;
}

/// What a PDF of a notebook, section or page holds: its pages in the order
/// the panes list them — each section's pages, then its subsections' — and
/// bookmarks for its sections and pages.
class PdfContents {
  const PdfContents({
    required this.title,
    required this.pages,
    this.marks = const <PdfMark>[],
    this.paths = const <String, List<String>>{},
  });

  final String title;
  final List<PageRef> pages;

  /// The bookmarks: none for a single page.
  final List<PdfMark> marks;

  /// Where each page is, by its id: the notebook, sections and pages it is
  /// in, outermost first.
  final Map<String, List<String>> paths;

  /// What [node] holds.
  static Future<PdfContents> of(AantekeningStore store, TreeNode node) async {
    final title = displayTitle(node);
    final sectionId = switch (node) {
      PageRef(:final sectionId) => sectionId,
      Section(:final id) => id,
      _ => null,
    };
    final notebookId = switch (node) {
      Section(:final notebookId) => notebookId,
      PageRef() =>
        (await store.library.findSection(sectionId!))?.notebookId ?? '',
      _ => node.id,
    };
    final notebook = (await store.library.findNotebook(notebookId))?.title;
    final sections = Section.hierarchy(
      await store.library.listAllSections(notebookId),
    );
    final pages = <PageRef>[];
    final paths = <String, List<String>>{};

    /// The notebook and sections down to [section].
    List<String> pathTo(Section section) => <String>[
      ?notebook,
      for (final above in sections.ancestorsOf(section.id).toList().reversed)
        ?sections[above]?.title,
      section.title,
    ];

    if (node is PageRef) {
      final section = sections[node.sectionId];
      final tree = PageRef.hierarchy(
        await store.pages.listPages(node.sectionId),
      );
      return PdfContents(
        title: title,
        pages: <PageRef>[node],
        paths: <String, List<String>>{
          node.id: <String>[
            if (section != null) ...pathTo(section),
            for (final above in tree.ancestorsOf(node.id).toList().reversed)
              if (tree[above] case final parent?) displayTitle(parent),
          ],
        },
      );
    }

    List<PdfMark> marksOfPages(
      Hierarchy<PageRef> tree,
      List<PageRef> level,
      List<String> path,
    ) {
      final marks = <PdfMark>[];
      for (final page in level) {
        final index = pages.length;
        pages.add(page);
        paths[page.id] = path;
        marks.add(
          PdfMark(
            displayTitle(page),
            index,
            marksOfPages(tree, tree.childrenOf(page.id), <String>[
              ...path,
              displayTitle(page),
            ]),
          ),
        );
      }
      return marks;
    }

    Future<List<PdfMark>> marksOfSections(List<Section> level) async {
      final marks = <PdfMark>[];
      for (final section in level) {
        final first = pages.length;
        final tree = PageRef.hierarchy(await store.pages.listPages(section.id));
        final within = <PdfMark>[
          ...marksOfPages(tree, tree.roots, pathTo(section)),
          ...await marksOfSections(sections.childrenOf(section.id)),
        ];
        // A section with no pages anywhere in it leads nowhere.
        if (pages.length > first) {
          marks.add(PdfMark(section.title, first, within));
        }
      }
      return marks;
    }

    final marks = node is Section
        ? (await marksOfSections(<Section>[node])).firstOrNull?.children ??
              const <PdfMark>[]
        : await marksOfSections(sections.roots);
    return PdfContents(title: title, pages: pages, marks: marks, paths: paths);
  }
}

/// How far a PDF has got: the page being drawn, counted from 0, of how
/// many, and its title.
typedef PdfProgress = ({int page, int of, String title});

/// Writes [contents] as a PDF to [path], made as [choices] has it, each
/// page with the title [headerOf] gives it at its top.
///
/// It is written beside [path] first and put there only once it is whole,
/// so a PDF stopped — [stopped] saying so between two pages — or failed
/// halfway leaves nothing behind. Returns whether it was written.
Future<bool> writePdf(
  AantekeningStore store,
  PdfContents contents,
  String path, {
  required PdfChoices choices,
  CanvasHeader? Function(PageRef page)? headerOf,
  void Function(PdfProgress progress)? onProgress,
  bool Function()? stopped,
}) async {
  final part = File('$path.part');
  final sink = part.openWrite();
  final writer = PdfWriter(sink.add);
  final printer = PagePrinter(store);
  final dpi = choices.quality.dpi;
  // Each note page's first page of the PDF.
  final firsts = <int>[];
  var queued = 0;
  // The files the pages hold, to be attached, each once.
  final assets = <String>{};
  // A sheet's pictures are made ready on an isolate while the next sheet is
  // drawn.
  Future<void> ready = Future<void>.value();
  var whole = false;
  try {
    for (final (index, page) in contents.pages.indexed) {
      if (stopped?.call() ?? false) return false;
      onProgress?.call((
        page: index,
        of: contents.pages.length,
        title: displayTitle(page),
      ));
      final document =
          await store.pages.loadDocument(page.id) ??
          PageDocument.empty(id: page.id);
      final header = headerOf?.call(page);
      final sheets = await printer.layOut(
        document,
        header: header,
        print: choices.print,
      );
      final lines = await printedText(
        document,
        wordsOf: printer.wordsOf,
        header: header,
        path: contents.paths[page.id] ?? const <String>[],
      );
      if (choices.attach) assets.addAll(document.referencedAssetIds);
      firsts.add(queued);
      for (final (index, sheet) in sheets.indexed) {
        if (stopped?.call() ?? false) return false;
        final strips = await printer.draw(
          document,
          sheet,
          dpi: dpi,
          header: header,
        );
        final encoding = _encodeAway(strips);
        final text = _textOn(sheet, lines, document, first: index == 0);
        await ready;
        queued++;
        ready = encoding.then(
          (images) => writer.addPage(
            width: sheet.widthInPoints,
            height: sheet.heightInPoints,
            pictures: _placed(sheet, strips, images),
            text: text,
          ),
        );
      }
    }
    await ready;
    if (stopped?.call() ?? false) return false;
    await _attach(store, writer, assets);
    if (stopped?.call() ?? false) return false;
    PdfOutline outlineOf(PdfMark mark) => PdfOutline(
      mark.title,
      page: firsts[mark.page],
      children: <PdfOutline>[
        for (final child in mark.children) outlineOf(child),
      ],
    );
    writer.finish(
      title: contents.title,
      outline: <PdfOutline>[for (final mark in contents.marks) outlineOf(mark)],
    );
    whole = true;
  } finally {
    // What is being made ready is waited for, so nothing is written after
    // the file is closed.
    await ready.then<void>((_) {}, onError: (Object _) {});
    await sink.close();
    await printer.close();
    // Put in the place of a PDF there already in one step, on Windows too,
    // so one that cannot be — open in a reader that will not let it go —
    // is left as it was.
    try {
      if (whole) await part.rename(path);
    } finally {
      if (part.existsSync()) await part.delete();
    }
  }
  return true;
}

/// The lines of [lines] — the text of [document] — that lie on [sheet],
/// as they lie on its paper: the title and where the page is on the
/// [first] sheet; on a sheet of a page shown as sheets, what is in what
/// has its middle on it, as it is drawn; on paper a page without sheets is
/// cut onto, each line whose middle is on it.
List<PdfText> _textOn(
  PrintedSheet sheet,
  List<PrintedLine> lines,
  PageDocument document, {
  required bool first,
}) {
  final sheets = sheet.sheet == null ? null : document.canvas.sheets;
  final region = sheet.region;
  final points = sheet.widthInPoints / region.width;
  bool onIt(PrintedLine line) {
    final id = line.elementId;
    if (id == null) return first;
    if (sheets != null) {
      final frame = document.elementById(id)?.frame;
      return frame != null &&
          sheets.sheetAt(frame.y + frame.height / 2) == sheet.sheet;
    }
    final shown = sheet.shown;
    final x = line.box.centerX;
    final y = line.box.centerY;
    return x >= shown.left &&
        x <= shown.right &&
        y >= shown.top &&
        y < shown.bottom;
  }

  return <PdfText>[
    for (final line in lines)
      if (onIt(line))
        (
          text: line.text,
          x: (line.box.left - region.left) * points,
          y: (line.box.top - region.top) * points,
          width: line.box.width * points,
          height: line.box.height * points,
        ),
  ];
}

/// The files [assetIds] attached to [writer] as they were brought in, each
/// by the name it came with — "Foto 2.png" for a second picture that came
/// as "Foto.png" — so nothing the notes hold is missing from the PDF.
Future<void> _attach(
  AantekeningStore store,
  PdfWriter writer,
  Set<String> assetIds,
) async {
  // Taken, as a file system that ignores case compares names.
  final taken = <String>{};
  String free(String name) {
    final dot = name.lastIndexOf('.');
    final stem = dot > 0 ? name.substring(0, dot) : name;
    final extension = dot > 0 ? name.substring(dot) : '';
    for (var n = 1; ; n++) {
      final candidate = n == 1 ? name : '$stem $n$extension';
      if (taken.add(candidate.toLowerCase())) return candidate;
    }
  }

  for (final assetId in assetIds) {
    final asset = await store.assets.find(assetId);
    if (asset == null) continue;
    final bytes = await store.assets.readBytes(assetId);
    if (bytes == null) continue;
    final given = asset.originalName?.trim() ?? '';
    writer.attach(
      free(
        given.isEmpty ? '${asset.id}${_extensionOf(asset.mimeType)}' : given,
      ),
      bytes,
      mimeType: asset.mimeType,
    );
  }
}

/// What a file of [mimeType] is named with, for one that came with no name.
String _extensionOf(String mimeType) => switch (mimeType) {
  'application/pdf' => '.pdf',
  'image/png' => '.png',
  'image/jpeg' => '.jpg',
  'image/gif' => '.gif',
  'image/webp' => '.webp',
  'image/svg+xml' => '.svg',
  _ => '',
};

/// [strips] made ready for a PDF on an isolate of their own.
///
/// Apart from where it is called, so that what is sent there is the strips
/// alone.
Future<List<PdfImage>> _encodeAway(List<PrintedStrip> strips) => Isolate.run(
  () => <PdfImage>[
    for (final strip in strips)
      PdfImage.rgba(strip.rgba, strip.width, strip.height),
  ],
);

/// Where on [sheet] each of [images] — [strips] made ready — lies: one
/// under another, across the whole sheet.
List<PdfPlacement> _placed(
  PrintedSheet sheet,
  List<PrintedStrip> strips,
  List<PdfImage> images,
) {
  final last = strips.last;
  // Points to a pixel down, from how many pixels tall the sheet was drawn.
  final down = sheet.heightInPoints / (last.top + last.height);
  return <PdfPlacement>[
    for (final (index, strip) in strips.indexed)
      (
        image: images[index],
        x: 0,
        y: strip.top * down,
        width: sheet.widthInPoints,
        height: strip.height * down,
      ),
  ];
}

/// Asks how to make a PDF of [node] — a notebook, section or page, with
/// all that is in it — and where to save it, and saves it there, saying
/// how far it has got.
///
/// What it shows goes through the window's own navigator and providers,
/// not [context]'s, as the menu it is started from closes.
Future<void> exportPdf(BuildContext context, TreeNode node) async {
  final container = ProviderScope.containerOf(context, listen: false);
  final window = Navigator.of(context, rootNavigator: true).context;
  final store = await container.read(storeProvider.future);
  // What is still being typed is printed too: the PDF is made from the
  // index, which has a page once it is saved.
  await container.read(openSavesProvider).saveAll();
  final contents = await PdfContents.of(store, node);
  if (!window.mounted) return;
  if (contents.pages.isEmpty) {
    window.say('There are no pages in ${contents.title} to save.');
    return;
  }
  // A page shown as sheets is printed as it is: nothing to choose of how.
  final canvas =
      node is! PageRef ||
      (await store.pages.loadDocument(node.id))?.canvas.sheetsShown == null;
  if (!window.mounted) return;
  final choices = await showAppDialog<PdfChoices>(
    context: window,
    builder: (_) => _PdfChoicesDialog(
      title: contents.title,
      initial: container.read(pdfChoicesProvider),
      canvas: canvas,
    ),
  );
  if (choices == null) return;
  container.read(pdfChoicesProvider.notifier).remember(choices);

  final location = await getSaveLocation(
    suggestedName: '${fileName(contents.title)}.pdf',
    acceptedTypeGroups: const <XTypeGroup>[
      XTypeGroup(
        label: 'PDF',
        extensions: <String>['pdf'],
        mimeTypes: <String>['application/pdf'],
      ),
    ],
  );
  if (location == null || !window.mounted) return;
  final path = location.path.toLowerCase().endsWith('.pdf')
      ? location.path
      : '${location.path}.pdf';
  final failure = await showAppDialog<Object>(
    context: window,
    barrierDismissible: false,
    builder: (_) => _PdfProgressDialog(
      store: store,
      contents: contents,
      path: path,
      choices: choices,
    ),
  );
  if (!window.mounted) return;
  switch (failure) {
    case true:
      ScaffoldMessenger.maybeOf(window)?.showMessage(
        'Saved to $path',
        action: (
          label: 'Open',
          run: () => unawaited(launchUrl(Uri.file(path))),
        ),
      );
    case false || null:
      break;
    case final Object error:
      window.say('The PDF could not be saved: $error');
  }
}

/// What a PDF is to be made as, asked before it is.
class _PdfChoicesDialog extends StatefulWidget {
  const _PdfChoicesDialog({
    required this.title,
    required this.initial,
    required this.canvas,
  });

  final String title;
  final PdfChoices initial;

  /// Whether a page shown as one paper may be among those saved, so there
  /// is a choice of how it is put on paper.
  final bool canvas;

  @override
  State<_PdfChoicesDialog> createState() => _PdfChoicesDialogState();
}

class _PdfChoicesDialogState extends State<_PdfChoicesDialog> {
  late PdfChoices _choices = widget.initial;

  void _set(PdfChoices choices) => setState(() => _choices = choices);

  @override
  Widget build(BuildContext context) {
    final tones = context.tones;
    final about = TextStyle(fontSize: 12.5, color: tones.muted);
    Widget row(String label, Widget choice) => Padding(
      padding: const EdgeInsets.only(top: 12),
      child: Row(
        children: <Widget>[
          SizedBox(width: 96, child: SmallCaps(label)),
          Flexible(child: choice),
        ],
      ),
    );
    return GlassDialog(
      title: Text('Save ${widget.title} as a PDF'),
      content: SizedBox(
        width: 460,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: <Widget>[
            Text(
              'A page shown as sheets is saved a sheet to a page, as it is. '
              'Its text is in the PDF as text, to select, search and copy '
              'and for an AI to read: formulas as LaTeX, and what is typed '
              'onto a printout in its text, where it was typed.',
              style: about,
            ),
            if (widget.canvas) ...<Widget>[
              const SizedBox(height: 4),
              Text(
                _choices.print == CanvasPrint.sheets
                    ? 'A page without sheets is cut onto sheets of A4 '
                          'between lines and drawings, never through them, '
                          'each turned or made smaller as what is on it '
                          'needs.'
                    : 'A page without sheets is saved on one page as long '
                          'as it is, to read on a screen.',
                style: about,
              ),
              row(
                'Without sheets',
                ChoiceRow<CanvasPrint>(
                  choices: CanvasPrint.values,
                  selected: _choices.print,
                  labelOf: (print) => print.label,
                  compact: true,
                  onSelected: (print) => _set(_choices.copyWith(print: print)),
                ),
              ),
            ],
            row(
              'Sharpness',
              ChoiceRow<PdfQuality>(
                choices: PdfQuality.values,
                selected: _choices.quality,
                labelOf: (quality) => quality.label,
                tooltipOf: (quality) =>
                    '${quality.dpi.round()} pixels to an inch',
                compact: true,
                onSelected: (quality) =>
                    _set(_choices.copyWith(quality: quality)),
              ),
            ),
            const SizedBox(height: 8),
            CheckRow(
              title: 'Attach the files on the pages',
              description:
                  'The PDFs, pictures and files as they were brought in — '
                  'whole and sharp, every page of a PDF — kept in this one, '
                  'to be saved from it again.',
              value: _choices.attach,
              onChanged: (attach) => _set(_choices.copyWith(attach: attach)),
            ),
          ],
        ),
      ),
      actions: <Widget>[
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('Cancel'),
        ),
        FilledButton(
          autofocus: true,
          onPressed: () => Navigator.of(context).pop(_choices),
          child: const Text('Save…'),
        ),
      ],
    );
  }
}

/// The PDF being written, as a dialog that closes with true once it is
/// whole, false if it was stopped, or what went wrong.
class _PdfProgressDialog extends StatefulWidget {
  const _PdfProgressDialog({
    required this.store,
    required this.contents,
    required this.path,
    required this.choices,
  });

  final AantekeningStore store;
  final PdfContents contents;
  final String path;
  final PdfChoices choices;

  @override
  State<_PdfProgressDialog> createState() => _PdfProgressDialogState();
}

class _PdfProgressDialogState extends State<_PdfProgressDialog> {
  PdfProgress? _progress;
  bool _stopped = false;

  @override
  void initState() {
    super.initState();
    // Begun once the dialog is up, with the window's localisations to
    // write the pages' dates in.
    WidgetsBinding.instance.addPostFrameCallback((_) => unawaited(_write()));
  }

  Future<void> _write() async {
    if (!mounted) return;
    final localizations = MaterialLocalizations.of(context);
    final hours = MediaQuery.alwaysUse24HourFormatOf(context);
    Object result;
    try {
      result = await writePdf(
        widget.store,
        widget.contents,
        widget.path,
        choices: widget.choices,
        headerOf: (page) {
          final made = DateTime.fromMillisecondsSinceEpoch(page.createdAt);
          return CanvasHeader(
            frame: PageTitle.frame,
            child: PrintedTitle(
              title: page.title,
              date: <String>[
                localizations.formatFullDate(made),
                localizations.formatTimeOfDay(
                  TimeOfDay.fromDateTime(made),
                  alwaysUse24HourFormat: hours,
                ),
              ],
            ),
          );
        },
        onProgress: (progress) {
          if (mounted) setState(() => _progress = progress);
        },
        stopped: () => _stopped,
      );
    } on Object catch (error) {
      result = error;
    }
    if (mounted) Navigator.of(context).pop(result);
  }

  @override
  Widget build(BuildContext context) {
    final tones = context.tones;
    final progress = _progress;
    return GlassDialog(
      title: const Text('Saving as a PDF'),
      content: SizedBox(
        width: 420,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: <Widget>[
            Text(
              progress == null
                  ? 'Starting'
                  : progress.of == 1
                  ? progress.title
                  : 'Page ${progress.page + 1} of ${progress.of}: '
                        '${progress.title}',
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(fontSize: 12.5, color: tones.muted),
            ),
            const SizedBox(height: 12),
            LayoutBuilder(
              builder: (context, constraints) => Busy(
                width: constraints.maxWidth,
                value: progress == null || progress.of == 1
                    ? null
                    : progress.page / progress.of,
              ),
            ),
          ],
        ),
      ),
      actions: <Widget>[
        TextButton(
          onPressed: _stopped ? null : () => setState(() => _stopped = true),
          child: const Text('Stop'),
        ),
      ],
    );
  }
}
