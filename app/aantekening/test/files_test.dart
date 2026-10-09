import 'dart:io';
import 'dart:typed_data';

import 'package:aantekening/src/editor/text/text_styles.dart';
import 'package:aantekening/src/files/attached_files.dart';
import 'package:aantekening/src/files/backup_settings.dart';
import 'package:aantekening/src/files/bin_view.dart';
import 'package:aantekening/src/files/notes_keeper.dart';
import 'package:aantekening/src/files/notes_location.dart';
import 'package:aantekening/src/look/theme.dart';
import 'package:aantekening/src/preferences.dart';
import 'package:aantekening/src/providers.dart';
import 'package:aantekening/src/settings/files_settings.dart';
import 'package:aantekening/src/settings/settings_view.dart';
import 'package:aantekening_core/aantekening_core.dart';
import 'package:aantekening_store/aantekening_store.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;

import 'editor_harness.dart';

void main() {
  group('attached files', () {
    test('are named as one file, never a way out of their folder', () {
      expect(safeFileName('notes.pdf'), 'notes.pdf');
      expect(safeFileName('../../.bashrc'), 'bashrc');
      expect(safeFileName(r'..\..\Windows\win.ini'), 'win.ini');
      expect(safeFileName('/etc/passwd'), 'passwd');
      expect(safeFileName('a:b*c?.txt'), 'a_b_c_.txt');
      expect(safeFileName('..'), 'Attached file');
      expect(safeFileName(''), 'Attached file');
    });

    test('that would run a program are known', () {
      for (final name in <String>[
        'setup.exe',
        'Run.BAT',
        'start.desktop',
        'install.sh',
        'macro.vbs',
        'shortcut.lnk',
      ]) {
        expect(runsCode(name), isTrue, reason: name);
      }
      for (final name in <String>['notes.pdf', 'photo.JPG', 'data.csv']) {
        expect(runsCode(name), isFalse, reason: name);
      }
    });
  });

  group('backups', () {
    test('are due once their interval has passed since the last', () {
      final at = DateTime(2026, 9, 27, 12);
      expect(const BackupSettings().dueAt(at), isTrue, reason: 'never made');
      final made = BackupSettings(last: at.subtract(const Duration(hours: 5)));
      expect(made.dueAt(at), isFalse);
      expect(made.dueAt(at.add(const Duration(days: 1))), isTrue);
      expect(
        made.copyWith(interval: BackupInterval.never).dueAt(DateTime(2030)),
        isFalse,
      );
    });

    test('are remembered, and read back leniently', () {
      final settings = BackupSettings(
        folder: '/backups',
        interval: BackupInterval.weekly,
        keep: 30,
        last: DateTime.fromMillisecondsSinceEpoch(1758000000000),
      );
      final read = BackupSettings.fromJson(settings.toJson());
      expect(read.folder, '/backups');
      expect(read.interval, BackupInterval.weekly);
      expect(read.keep, 30);
      expect(read.last, settings.last);
      final odd = BackupSettings.fromJson(<String, Object?>{
        'interval': 'hourly',
        'keep': -1,
      });
      expect(odd.interval, BackupInterval.daily);
      expect(odd.keep, 10);
    });

    test('being made when the app closes end quietly', () async {
      final container = ProviderContainer(
        overrides: [
          preferencesProvider.overrideWith(
            (ref) async => Preferences.inMemory(),
          ),
        ],
      );
      await container.read(preferencesProvider.future);
      final backups = container.read(backupsProvider.notifier);

      final made = backups.backUpNow();
      container.dispose();
      expect(await made, isNull);
    });
  });

  test('says when, as a person says it', () {
    final now = DateTime(2026, 9, 27, 18);
    int at(DateTime time) => time.millisecondsSinceEpoch;
    expect(
      timeSaid(at(DateTime(2026, 9, 27, 9, 5)), now: now),
      'today at 09:05',
    );
    expect(timeSaid(at(DateTime(2026, 9, 26, 23)), now: now), 'yesterday');
    expect(timeSaid(at(DateTime(2026, 9, 23)), now: now), '4 days ago');
    expect(timeSaid(at(DateTime(2026, 1, 2)), now: now), '2.1.2026');
  });

  group('folders chosen for notes', () {
    late Directory root;

    setUp(() => root = Directory.systemTemp.createTempSync('notes_where_'));
    tearDown(() => root.deleteSync(recursive: true));

    test(
      'take the notes, open theirs, or hold a folder of their own',
      () async {
        final empty = Directory(p.join(root.path, 'empty'))..createSync();
        expect(contentsOf(empty.path), FolderContents.empty);
        expect(notesFolderIn(empty.path), empty.path);

        final busy = Directory(p.join(root.path, 'Documents'))..createSync();
        File(p.join(busy.path, 'letter.txt')).writeAsStringSync('dear');
        expect(contentsOf(busy.path), FolderContents.other);
        expect(
          notesFolderIn(busy.path),
          p.join(busy.path, 'aantekening notes'),
        );

        final notes = p.join(root.path, 'Notes');
        await NotesFolder(notes).writeIdentity('01JABCDEFGHJKMNPQRSTVWXYZ0');
        expect(contentsOf(notes), FolderContents.notes);
      },
    );
  });

  test('saving everything open waits for every page', () async {
    final saves = OpenSaves();
    final saved = <String>[];
    final remove = saves.register(() async {
      await Future<void>.delayed(const Duration(milliseconds: 5));
      saved.add('a');
    });
    saves.register(() async => saved.add('b'));
    await saves.saveAll();
    expect(saved, unorderedEquals(<String>['a', 'b']));
    remove();
    saved.clear();
    await saves.saveAll();
    expect(saved, <String>['b']);
  });

  test(
    'notes moved to another folder open there, the old folder left',
    () async {
      if (Platform.environment['AANTEKENING_HOME'] case final home?
          when home.isNotEmpty) {
        markTestSkipped('AANTEKENING_HOME chooses the notes folder');
        return;
      }
      final support = Directory.systemTemp.createTempSync('notes_moved_');
      addTearDown(() => support.deleteSync(recursive: true));
      final container = ProviderContainer(
        overrides: [
          preferencesProvider.overrideWith(
            (ref) async => Preferences.inMemory(),
          ),
          supportFolderProvider.overrideWith((ref) async => support.path),
        ],
      );
      addTearDown(container.dispose);
      final before = await container.read(storeProvider.future);
      final notebook = await before.library.createNotebook(title: 'Physics');
      final section = await before.library.createSection(
        notebookId: notebook.id,
        title: 'Waves',
      );
      final page = await before.pages.createPage(sectionId: section.id);
      await before.pages.saveDocument(
        page.id,
        PageDocument.empty(id: page.id).withElementAdded(
          TextElement(
            id: Ulid.generate(),
            frame: const Frame(x: 0, y: 0, width: 200, height: 40),
            createdAt: 0,
            updatedAt: 0,
            blocks: <TextBlock>[TextBlock.plain('moved whole')],
          ),
        ),
      );
      final from = before.directory;
      final target = p.join(support.path, 'Elsewhere');

      await container.read(notesLocationProvider).moveTo(target);
      // The same notes — the same index — opened only once the old store
      // has let go of them.
      final after = await container.read(storeProvider.future);
      expect(after.directory, target);
      expect(
        (await after.pages.loadDocument(page.id))!.extractSearchText(),
        'moved whole',
      );
      expect(
        File(p.join(from, 'pages', '${page.id}.json.gz')).existsSync(),
        isTrue,
        reason: 'the folder they were in is left as it was',
      );
    },
  );

  test(
    'notes gone from their folder are waited for, not started afresh',
    () async {
      if (Platform.environment['AANTEKENING_HOME'] case final home?
          when home.isNotEmpty) {
        markTestSkipped('AANTEKENING_HOME chooses the notes folder');
        return;
      }
      final support = Directory.systemTemp.createTempSync('notes_gone_');
      addTearDown(() => support.deleteSync(recursive: true));
      final preferences = Preferences.inMemory();
      ProviderContainer window() {
        final container = ProviderContainer(
          overrides: [
            preferencesProvider.overrideWith((ref) async => preferences),
            supportFolderProvider.overrideWith((ref) async => support.path),
          ],
        );
        addTearDown(container.dispose);
        return container;
      }

      var container = window();
      final first = await container.read(storeProvider.future);
      final notes = first.directory;
      await first.library.createNotebook(title: 'Physics');
      container.dispose();
      await first.close();
      // The drive they are on taken out.
      Directory(notes).renameSync('$notes-out');

      container = window();
      await expectLater(
        container.read(storeProvider.future),
        throwsA(isA<NotesFolderMissing>()),
      );
      expect(Directory(notes).existsSync(), isFalse, reason: 'nothing made');

      // Plugged in again, and tried again.
      Directory('$notes-out').renameSync(notes);
      container.invalidate(storeProvider);
      final back = await container.read(storeProvider.future);
      expect(
        (await back.library.listNotebooks()).map((notebook) => notebook.title),
        contains('Physics'),
      );
    },
  );

  testWidgets('the settings have a page for files, with what they hold', (
    tester,
  ) async {
    final assets = Directory.systemTemp.createTempSync('files_settings_');
    addTearDown(() => assets.deleteSync(recursive: true));
    final store = AantekeningStore.inMemory(assetDirectory: assets);
    addTearDown(store.close);
    final notebook = await store.library.createNotebook(title: 'Old');
    await store.library.deleteNotebook(notebook.id);

    tester.view.physicalSize = const Size(1300, 1000);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          storeProvider.overrideWith((ref) async => store),
          preferencesProvider.overrideWith(
            (ref) async => Preferences.inMemory(),
          ),
          notesFolderProvider.overrideWith(
            (ref) async => '/home/me/OneDrive/Notes',
          ),
          supportFolderProvider.overrideWith((ref) async => '/support'),
        ],
        child: MaterialApp(
          theme: AppTheme.light(),
          home: const Scaffold(body: SettingsView(initial: SettingsPage.files)),
        ),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.byType(FilesSettings), findsOneWidget);
    expect(find.text('/home/me/OneDrive/Notes'), findsOneWidget);
    expect(find.text(p.join('/support', 'backups')), findsOneWidget);
    expect(find.text('No backup made yet.'), findsOneWidget);
    expect(find.text('1 deleted, 0 pages in all.'), findsOneWidget);
    for (final name in <String>['OneNote', 'Xournal++', 'aantekening']) {
      expect(find.text(name), findsOneWidget);
    }
  });

  group('preferences', () {
    test('keeps every value set at once, when read again', () async {
      final folder = await Directory.systemTemp.createTemp('preferences_');
      addTearDown(() => folder.delete(recursive: true));
      final file = File(p.join(folder.path, 'preferences.json'));
      final preferences = await Preferences.open(file);

      await Future.wait(<Future<void>>[
        preferences.set('a', 1),
        preferences.set('b', 2),
        preferences.set('c', 3),
        preferences.set('a', null),
      ]);

      final again = await Preferences.open(file);
      expect(
        <Object?>[again['a'], again['b'], again['c']],
        <Object?>[null, 2, 3],
      );
    });
  });

  group('text brought from elsewhere', () {
    late Directory assets;
    late AantekeningStore store;

    setUp(() {
      assets = Directory.systemTemp.createTempSync('imported_text_');
      store = AantekeningStore.inMemory(assetDirectory: assets);
    });

    tearDown(() async {
      await store.close();
      assets.deleteSync(recursive: true);
    });

    Future<String> pageWith(List<TextBlock> blocks) async {
      final notebook = await store.library.createNotebook(title: 'N');
      final section = await store.library.createSection(
        notebookId: notebook.id,
        title: 'S',
      );
      final page = await store.pages.createPage(sectionId: section.id);
      await store.pages.saveDocument(
        page.id,
        PageDocument.empty(id: page.id).withElementAdded(
          TextElement(
            id: Ulid.generate(),
            frame: const Frame(x: 40, y: 140, width: 400, height: 100),
            createdAt: 1,
            updatedAt: 1,
            blocks: blocks,
          ),
        ),
      );
      return page.id;
    }

    testWidgets('keeps its bullets, typefaces and alignment', (tester) async {
      final pageId = await pageWith(const <TextBlock>[
        TextBlock(
          kind: TextBlockKind.bulleted,
          marker: '➢',
          spacing: BlockSpacing.tight,
          runs: <TextRun>[TextRun('Consolas', TextMarks(font: 'Consolas'))],
        ),
        TextBlock(
          align: BlockAlign.center,
          runs: <TextRun>[
            TextRun('x'),
            TextRun('2', TextMarks(script: TextScript.superscript)),
          ],
        ),
      ]);
      await openEditor(tester, store, pageId);
      // A mark none of the drawn shapes stand for is set as written.
      expect(find.text('➢'), findsOneWidget);
      final texts = tester.widgetList<RichText>(find.byType(RichText));
      final centred = texts.firstWhere(
        (text) => text.text.toPlainText() == 'x2',
      );
      expect(centred.textAlign, TextAlign.center);
      final monospaced = texts.firstWhere(
        (text) => text.text.toPlainText() == 'Consolas',
      );
      final run = (monospaced.text as TextSpan).children!.single as TextSpan;
      expect(run.style!.fontFamily, 'Consolas');
      expect(run.style!.fontFamilyFallback, <String>[
        RichTextStyles.consolasMeasure,
      ]);
      final raised = (centred.text as TextSpan).children!.last as TextSpan;
      expect(raised.style!.fontFeatures, isNotEmpty);
    });

    testWidgets('shows an attached file by its name', (tester) async {
      // Written to disk, which the test's clock does not wait for.
      final file = (await tester.runAsync(
        () => store.assets.importBytes(
          Uint8List.fromList(List<int>.filled(2048, 1)),
          mimeType: 'application/octet-stream',
          originalName: 'lab report.docx',
        ),
      ))!;
      final pageId = await pageWith(<TextBlock>[
        TextBlock.embedded(
          BlockEmbed(
            kind: EmbedKind.file,
            assetId: file.id,
            width: 240,
            height: 36,
            name: 'lab report.docx',
          ),
        ),
      ]);
      await openEditor(tester, store, pageId);
      expect(find.text('lab report.docx'), findsOneWidget);
      expect(find.text('DOCX'), findsOneWidget);
      expect(find.text('  ·  2.0 KB'), findsOneWidget);
    });
  });
}
