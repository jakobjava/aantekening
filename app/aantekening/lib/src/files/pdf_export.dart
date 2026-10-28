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
import 'page_printer.dart';

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
/// the paper is where the notes are kept — and how sharp.
@immutable
class PdfChoices {
  const PdfChoices({
    this.print = CanvasPrint.sheets,
    this.quality = PdfQuality.standard,
  });

  final CanvasPrint print;
  final PdfQuality quality;

  PdfChoices copyWith({CanvasPrint? print, PdfQuality? quality}) =>
      PdfChoices(print: print ?? this.print, quality: quality ?? this.quality);

  @override
  bool operator ==(Object other) =>
      other is PdfChoices && other.print == print && other.quality == quality;

  @override
  int get hashCode => Object.hash(print, quality);
}

/// The choices the last PDF was made with, offered for the next.
class PdfChoicesController extends Notifier<PdfChoices> {
  static const String _print = 'pdf.print';
  static const String _quality = 'pdf.quality';

  @override
  PdfChoices build() {
    const start = PdfChoices();
    T named<T extends Enum>(String key, List<T> values, T fallback) =>
        values.asNameMap()[ref.preference(key)] ?? fallback;
    return PdfChoices(
      print: named(_print, CanvasPrint.values, start.print),
      quality: named(_quality, PdfQuality.values, start.quality),
    );
  }

  void remember(PdfChoices choices) {
    if (choices == state) return;
    state = choices;
    ref
      ..savePreference(_print, choices.print.name)
      ..savePreference(_quality, choices.quality.name);
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
  });

  final String title;
  final List<PageRef> pages;

  /// The bookmarks: none for a single page.
  final List<PdfMark> marks;

  /// What [node] holds.
  static Future<PdfContents> of(AantekeningStore store, TreeNode node) async {
    final title = displayTitle(node);
    if (node is PageRef) {
      return PdfContents(title: title, pages: <PageRef>[node]);
    }
    final notebookId = switch (node) {
      Section(:final notebookId) => notebookId,
      _ => node.id,
    };
    final sections = Section.hierarchy(
      await store.library.listAllSections(notebookId),
    );
    final pages = <PageRef>[];

    List<PdfMark> marksOfPages(Hierarchy<PageRef> tree, List<PageRef> level) {
      final marks = <PdfMark>[];
      for (final page in level) {
        final index = pages.length;
        pages.add(page);
        marks.add(
          PdfMark(
            displayTitle(page),
            index,
            marksOfPages(tree, tree.childrenOf(page.id)),
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
          ...marksOfPages(tree, tree.roots),
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
    return PdfContents(title: title, pages: pages, marks: marks);
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
      firsts.add(queued);
      for (final sheet in sheets) {
        if (stopped?.call() ?? false) return false;
        final strips = await printer.draw(
          document,
          sheet,
          dpi: dpi,
          header: header,
        );
        final encoding = _encodeAway(strips);
        await ready;
        queued++;
        ready = encoding.then(
          (images) => writer.addPage(
            width: sheet.widthInPoints,
            height: sheet.heightInPoints,
            pictures: _placed(sheet, strips, images),
          ),
        );
      }
    }
    await ready;
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
    if (whole) {
      final target = File(path);
      // Windows does not put a file in another's place.
      if (Platform.isWindows && target.existsSync()) target.deleteSync();
      await part.rename(path);
    } else if (part.existsSync()) {
      await part.delete();
    }
  }
  return true;
}

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
  final contents = await PdfContents.of(store, node);
  if (!window.mounted) return;
  if (contents.pages.isEmpty) {
    _say(window, 'There are no pages in ${contents.title} to save.');
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
  await store.mirror?.flush();
  if (!window.mounted) return;
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
      _say(window, 'The PDF could not be saved: $error');
  }
}

void _say(BuildContext context, String message) =>
    ScaffoldMessenger.maybeOf(context)?.showMessage(message);

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
              'A page shown as sheets is saved a sheet to a page, as it is.',
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
