import 'package:aantekening_store/aantekening_store.dart';
import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';

import 'editor_harness.dart';

/// What is written on a page is kept, however the page is left: for
/// another page, or by the editor closing, straight after the last key.
void main() {
  late AantekeningStore store;
  late String pageId;
  useTestPage((made, id) {
    store = made;
    pageId = id;
  });

  Future<String> stored(String id) async =>
      (await store.pages.loadDocument(id))?.extractSearchText() ?? '';

  Future<String> anotherPage() async => (await store.pages.createPage(
    sectionId: (await store.pages.findPage(pageId))!.sectionId,
  )).id;

  testWidgets('every letter typed is kept when another page opens at once', (
    tester,
  ) async {
    final other = await anotherPage();
    await openEditor(tester, store, pageId);
    await startTextBox(tester);
    await type(tester, 'Hello');
    await openEditor(tester, store, other);
    await tester.pumpAndSettle();
    expect(await stored(pageId), contains('Hello'));
  });

  testWidgets('a formula still being typed is kept when another page opens', (
    tester,
  ) async {
    final other = await anotherPage();
    await openEditor(tester, store, pageId);
    await startTextBox(tester);
    await type(tester, 'Energy ');
    await press(tester, LogicalKeyboardKey.keyM, control: true);
    await type(tester, 'mc^2');
    await openEditor(tester, store, other);
    await tester.pumpAndSettle();
    final text = await stored(pageId);
    expect(text, contains('Energy'));
    expect(text, contains('c^2'));
  });

  testWidgets('a formula still being typed is kept when the editor closes', (
    tester,
  ) async {
    await openEditor(tester, store, pageId);
    await startTextBox(tester);
    await type(tester, 'Energy ');
    await press(tester, LogicalKeyboardKey.keyM, control: true);
    await type(tester, 'mc^2');
    await tester.pumpWidget(const SizedBox());
    await tester.pumpAndSettle();
    final text = await stored(pageId);
    expect(text, contains('Energy'));
    expect(text, contains('c^2'));
  });
}
