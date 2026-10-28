import 'package:aantekening_canvas/aantekening_canvas.dart';
import 'package:aantekening_core/aantekening_core.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

/// Text lying in [area] of the page, with a link in [link], beneath what
/// lies over it unless that is [under] or nothing; it tells what was done
/// to it.
class _Text implements CanvasText {
  _Text({required this.area, required this.link, this.under});

  final Aabb area;
  final Aabb link;
  final String? under;

  final List<(Offset, Offset)> selected = <(Offset, Offset)>[];
  final List<Offset> words = <Offset>[];
  final List<Offset> opened = <Offset>[];

  bool _beneath(NoteElement? hit) => hit == null || hit.id == under;

  @override
  bool selectsAt(Offset page, NoteElement? hit) =>
      _beneath(hit) && area.containsPoint(page.dx, page.dy);

  @override
  void select(Offset from, Offset to) => selected.add((from, to));

  @override
  void selectWord(Offset page) => words.add(page);

  @override
  bool linkAt(Offset page, NoteElement? hit) =>
      _beneath(hit) && link.containsPoint(page.dx, page.dy);

  @override
  void openLink(Offset page) => opened.add(page);
}

ImageElement _printout(String id, {bool locked = false}) => ImageElement(
  id: id,
  frame: const Frame(x: 100, y: 100, width: 400, height: 300),
  createdAt: 0,
  updatedAt: 0,
  locked: locked,
  assetId: 'asset',
);

Widget _host(
  CanvasController controller,
  CanvasText text, {
  ValueChanged<Offset>? onEmptyTap,
}) => MaterialApp(
  home: Scaffold(
    body: InfiniteCanvas(
      controller: controller,
      text: text,
      onEmptyTap: onEmptyTap,
      elementBuilder: (context, element) =>
          const ColoredBox(color: Colors.blue),
    ),
  ),
);

/// A page with a PDF page on it, set as its background or not, and text
/// across it.
(CanvasController, _Text) _page({bool background = true}) {
  final controller = CanvasController()
    ..loadDocument(
      PageDocument.empty(
        id: 'p',
      ).withElementAdded(_printout('sheet', locked: background)),
    );
  return (
    controller,
    _Text(
      area: const Aabb(120, 120, 480, 300),
      link: const Aabb(120, 280, 300, 300),
      under: background ? null : 'sheet',
    ),
  );
}

Future<void> _drag(WidgetTester tester, Offset from, Offset to) async {
  final mouse = await tester.startGesture(from, kind: PointerDeviceKind.mouse);
  await mouse.moveTo(Offset.lerp(from, to, 0.5)!);
  await mouse.moveTo(to);
  await mouse.up();
  await tester.pump();
}

Future<void> _click(WidgetTester tester, Offset at) async {
  await tester.tapAt(at, kind: PointerDeviceKind.mouse);
  await tester.pump();
}

void main() {
  testWidgets('dragged across, the text beneath is selected, from where the '
      'drag began', (tester) async {
    final (controller, text) = _page();
    final taps = <Offset>[];
    await tester.pumpWidget(_host(controller, text, onEmptyTap: taps.add));
    await _drag(tester, const Offset(150, 150), const Offset(400, 200));
    expect(text.selected, isNotEmpty);
    expect(text.selected.first.$1, const Offset(150, 150));
    expect(text.selected.last.$2, const Offset(400, 200));
    expect(taps, isEmpty, reason: 'no caret placed');
    expect(controller.selection, isEmpty, reason: 'no marquee either');
  });

  testWidgets('clicked, a worksheet still takes the caret', (tester) async {
    final (controller, text) = _page();
    final taps = <Offset>[];
    await tester.pumpWidget(_host(controller, text, onEmptyTap: taps.add));
    await _click(tester, const Offset(200, 160));
    expect(taps, <Offset>[const Offset(200, 160)]);
    expect(text.selected, isEmpty);
  });

  testWidgets('clicked twice, a word of it is selected', (tester) async {
    final (controller, text) = _page();
    await tester.pumpWidget(_host(controller, text));
    await _click(tester, const Offset(200, 160));
    await tester.pump(const Duration(milliseconds: 50));
    await _click(tester, const Offset(201, 160));
    expect(text.words, <Offset>[const Offset(201, 160)]);
  });

  testWidgets('on a PDF page of its own, a drag across its text selects the '
      'text, and a click picks the page up, moving nothing', (tester) async {
    final (controller, text) = _page(background: false);
    await tester.pumpWidget(_host(controller, text));
    await _drag(tester, const Offset(150, 150), const Offset(400, 200));
    expect(text.selected, isNotEmpty);
    expect(controller.document.elementById('sheet')!.frame.x, 100);

    await tester.pump(const Duration(seconds: 1));
    await _click(tester, const Offset(200, 160));
    expect(controller.selection, <String>{'sheet'});
    expect(controller.document.elementById('sheet')!.frame.x, 100);
  });

  testWidgets('beyond its text, a PDF page of its own is dragged away as '
      'before', (tester) async {
    final (controller, text) = _page(background: false);
    await tester.pumpWidget(_host(controller, text));
    await _drag(tester, const Offset(110, 380), const Offset(160, 380));
    expect(text.selected, isEmpty);
    expect(controller.document.elementById('sheet')!.frame.x, 150);
  });

  testWidgets('a link is opened by a click with Ctrl held, not without', (
    tester,
  ) async {
    final (controller, text) = _page();
    final taps = <Offset>[];
    await tester.pumpWidget(_host(controller, text, onEmptyTap: taps.add));
    await _click(tester, const Offset(200, 290));
    expect(text.opened, isEmpty);
    expect(taps, hasLength(1), reason: 'a plain click places the caret');

    await tester.pump(const Duration(seconds: 1));
    await tester.sendKeyDownEvent(LogicalKeyboardKey.controlLeft);
    await _click(tester, const Offset(200, 290));
    await tester.sendKeyUpEvent(LogicalKeyboardKey.controlLeft);
    expect(text.opened, <Offset>[const Offset(200, 290)]);
    expect(taps, hasLength(1));
  });

  testWidgets('a finger dragged across the text scrolls the page', (
    tester,
  ) async {
    final (controller, text) = _page();
    await tester.pumpWidget(_host(controller, text));
    await tester.dragFrom(const Offset(300, 200), const Offset(0, -100));
    await tester.pump();
    expect(text.selected, isEmpty);
    expect(controller.viewport.origin.dy, greaterThan(0));
  });

  testWidgets('the pointer shows a text cursor over the text, and a hand '
      'over a link with Ctrl held', (tester) async {
    final (controller, text) = _page();
    await tester.pumpWidget(_host(controller, text));
    final mouse = await tester.createGesture(
      kind: PointerDeviceKind.mouse,
      pointer: 1,
    );
    await mouse.addPointer(location: const Offset(700, 500));
    await mouse.moveTo(const Offset(200, 160));
    await tester.pump();
    MouseCursor shown() =>
        RendererBinding.instance.mouseTracker.debugDeviceActiveCursor(1)!;
    expect(shown(), SystemMouseCursors.text);

    await tester.sendKeyDownEvent(LogicalKeyboardKey.controlLeft);
    await mouse.moveTo(const Offset(200, 290));
    await tester.pump();
    expect(shown(), SystemMouseCursors.click);
    await tester.sendKeyUpEvent(LogicalKeyboardKey.controlLeft);
    await mouse.removePointer();
  });
}
