import 'dart:async';
import 'dart:io';

import 'package:aantekening/src/ai/ai_state.dart';
import 'package:aantekening/src/ai/ai_view.dart';
import 'package:aantekening/src/ai/flashcards_view.dart';
import 'package:aantekening/src/ai/sources_view.dart';
import 'package:aantekening/src/ai/study_pages.dart';
import 'package:aantekening/src/ai/summary_sheet.dart';
import 'package:aantekening/src/editor/text/text_box_editor.dart';
import 'package:aantekening/src/preferences.dart';
import 'package:aantekening/src/providers.dart';
import 'package:aantekening/src/shell/home_shell.dart';
import 'package:aantekening/src/shell/library_pane.dart';
import 'package:aantekening/src/shell/tabs.dart';
import 'package:aantekening/src/look/theme.dart';
import 'package:aantekening_ai/aantekening_ai.dart';
import 'package:aantekening_canvas/aantekening_canvas.dart';
import 'package:aantekening_core/aantekening_core.dart';
import 'package:aantekening_store/aantekening_store.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

/// A model that answers from the first source it is given, citing it — and
/// with flashcards when asked for them.
class FakeProvider implements ChatProvider {
  final List<ChatRequest> asked = <ChatRequest>[];

  /// While set, the model thinks, and answers once it is completed.
  Completer<void>? gate;

  /// While set, flashcards are written once it is completed.
  Completer<void>? cardsGate;

  @override
  String get name => 'Fake';

  @override
  Future<ModelCapabilities> capabilitiesOf(String model) async =>
      const ModelCapabilities(tools: true, contextTokens: 100000);

  @override
  Stream<ChatEvent> chat(ChatRequest request) async* {
    asked.add(request);
    final question = request.messages.last.text;
    const done = MessageDone(
      ChatMessage(ChatRole.assistant, <ChatPart>[]),
      stop: StopReason.done,
    );
    // A study set, written as JSON, citing the first sentence.
    if (request.system.contains('study material')) {
      if (question.contains('"cards"')) await cardsGate?.future;
      yield TextDelta(
        question.contains('"cards"')
            ? '{"cards": [{"front": "What is force?", "back": "Mass times '
                  r'acceleration, $F = ma$", "sources": ["1.1"]}, '
                  '{"front": "Unit of force?", "back": "The newton", '
                  '"sources": ["1.2"]}]}'
            : '{"title": "Forces", "gist": "What force is.", "sections": '
                  '[{"heading": "Force", "points": [{"text": "Force is mass '
                  'times acceleration.", "sources": ["1.1"]}]}], '
                  r'"formulas": [{"latex": "F = ma", "meaning": "force", '
                  '"sources": ["1.1"]}], "beyond": ["Mass is in kg."]}',
      );
      yield done;
      return;
    }
    final source = sourcesIn(request.messages).first;
    final passage = source.passages.first;
    final citation = Citation(
      uri: passage.uri,
      title: source.title,
      origin: SourceOrigin.notes,
      quote: passage.text,
    );
    if (gate case final gate?) {
      yield const Reasoning('They ask about force.\nNewton’s second law.');
      await gate.future;
    }
    if (question.contains('flashcards')) {
      yield const TextDelta(
        'Cards from your notes:\n\n```flashcards\n'
        '[{"front": "What is force?", "back": "Mass times acceleration"},'
        ' {"front": "Unit of force?", "back": "Newton"}]\n```',
      );
    } else {
      yield const TextDelta('Force is mass times acceleration.');
      yield CitedSpan(<Citation>[citation]);
      yield const TextDelta('\n\nBeyond your notes, it is named after Newton.');
      yield const CitedSpan(<Citation>[]);
    }
    yield MessageDone(
      ChatMessage.assistant(const <ChatPart>[TextPart('…')]),
      stop: StopReason.done,
    );
  }

  @override
  Future<List<ModelInfo>> listModels() async => const <ModelInfo>[];

  @override
  void close() {}
}

void main() {
  late AantekeningStore store;
  late Directory assets;
  late FakeProvider model;
  late Notebook notebook;
  late Section section;
  late PageRef page;

  setUp(() async {
    assets = Directory.systemTemp.createTempSync('aantekening_ai_test_');
    store = AantekeningStore.inMemory(assetDirectory: assets);
    model = FakeProvider();
    notebook = await store.library.createNotebook(title: 'Physics');
    section = await store.library.createSection(
      notebookId: notebook.id,
      title: 'Mechanics',
    );
    page = await store.pages.createPage(sectionId: section.id, title: 'Forces');
    await store.pages.saveDocument(
      page.id,
      PageDocument.empty(id: page.id).withElementAdded(
        TextElement(
          id: 'law',
          frame: const Frame(x: 40, y: 400, width: 300, height: 60),
          createdAt: 0,
          updatedAt: 0,
          blocks: <TextBlock>[
            TextBlock.plain(
              'Force is mass times acceleration. It is measured in newtons.',
            ),
          ],
        ),
      ),
    );
  });

  tearDown(() async {
    await store.close();
    if (assets.existsSync()) assets.deleteSync(recursive: true);
  });

  Future<ProviderContainer> openShell(
    WidgetTester tester, {
    bool withModel = true,
    Preferences? preferences,
  }) async {
    tester.view.physicalSize = const Size(1500, 950);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          storeProvider.overrideWith((ref) async => store),
          preferencesProvider.overrideWith(
            (ref) async => preferences ?? Preferences.inMemory(),
          ),
          aiSecretsProvider.overrideWithValue(MemorySecrets()),
          if (withModel)
            aiModelProvider.overrideWith(
              (ref) async => (
                provider: model as ChatProvider,
                config: ProviderConfig.of(
                  ProviderPreset.ollama,
                  id: 'local',
                ).copyWith(model: 'test-model'),
              ),
            ),
        ],
        child: MaterialApp(theme: AppTheme.light(), home: const HomeShell()),
      ),
    );
    await tester.pumpAndSettle();
    final container = ProviderScope.containerOf(
      tester.element(find.byType(HomeShell)),
    );
    container.read(selectedNotebookProvider.notifier).select(notebook.id);
    container.read(selectedSectionProvider.notifier).select(section.id);
    container.read(selectedPageProvider.notifier).select(page.id);
    await tester.pumpAndSettle();
    return container;
  }

  Future<void> pressControl(WidgetTester tester, LogicalKeyboardKey key) async {
    await tester.sendKeyDownEvent(LogicalKeyboardKey.controlLeft);
    await tester.sendKeyEvent(key);
    await tester.sendKeyUpEvent(LogicalKeyboardKey.controlLeft);
    await tester.pumpAndSettle();
  }

  Future<void> ask(WidgetTester tester, String question) async {
    await tester.enterText(
      find.descendant(
        of: find.byType(AiView),
        matching: find.byType(TextField),
      ),
      question,
    );
    await tester.tap(find.byTooltip('Ask (Enter)'));
    await tester.pumpAndSettle();
  }

  testWidgets('Ctrl+J turns the tab to the AI of its page, and back', (
    tester,
  ) async {
    final container = await openShell(tester);
    expect(find.byType(InfiniteCanvas), findsOneWidget);

    await pressControl(tester, LogicalKeyboardKey.keyJ);
    expect(find.byType(AiView), findsOneWidget);
    expect(find.byType(InfiniteCanvas), findsNothing, reason: 'in its place');
    expect(container.read(tabsProvider).current.ai, isTrue);
    expect(find.byType(StudyOverview), findsOneWidget);

    // The sidebar's button turns it back.
    await tester.tap(find.byTooltip('Back to the notes  (Ctrl+J)'));
    await tester.pumpAndSettle();
    expect(find.byType(InfiniteCanvas), findsOneWidget);
  });

  testWidgets('an answer comes from the notes, cites them, and says what '
      'is not from them', (tester) async {
    await openShell(tester);
    await tester.tap(find.byTooltip('Ask AI about what is open  (Ctrl+J)'));
    await tester.pumpAndSettle();

    await ask(tester, 'What is force?');

    // The page was given to the model with the question.
    final first = model.asked.first.messages.first;
    final given = first.parts.whereType<SourcesPart>().single.sources.single;
    expect(given.title, 'Forces');
    expect(given.passages.first.uri, contains('element=law'));

    expect(
      find.textContaining(
        'Force is mass times acceleration.',
        findRichText: true,
      ),
      findsWidgets,
    );
    expect(find.byType(FootnoteMark), findsOneWidget);
    expect(find.text('FROM YOUR NOTES'), findsOneWidget);
    expect(
      find.text('From the model’s own knowledge, not from your notes'),
      findsOneWidget,
    );

    // Nothing of it went into the page.
    final document = await tester.runAsync(
      () => store.pages.loadDocument(page.id),
    );
    expect(document!.elements, hasLength(1));
    final threads = await tester.runAsync(
      () => store.ai.threadsAbout(NoteLink.page(page.id)),
    );
    expect(threads, hasLength(1));
  });

  testWidgets('shows how an answer is coming along: each step, how long '
      'it took, and what the model thinks', (tester) async {
    final container = await openShell(tester);
    container.read(tabsProvider.notifier).toggleAi();
    await tester.pumpAndSettle();
    final gate = model.gate = Completer<void>();

    await tester.enterText(
      find.descendant(
        of: find.byType(AiView),
        matching: find.byType(TextField),
      ),
      'What is force?',
    );
    await tester.tap(find.byTooltip('Ask (Enter)'));
    for (var i = 0; i < 5; i++) {
      await tester.pump(const Duration(milliseconds: 100));
    }

    expect(find.text('Gathering your notes'), findsOneWidget, reason: 'done');
    expect(
      find.textContaining('test-model is reading your question — 1 page, '),
      findsOneWidget,
    );
    expect(find.text('Thinking…'), findsOneWidget);
    expect(find.textContaining('Newton’s second law.'), findsOneWidget);

    gate.complete();
    await tester.pumpAndSettle();
    expect(find.text('Thinking…'), findsNothing);
    expect(find.textContaining('Ollama · test-model · '), findsOneWidget);
  });

  testWidgets('a cited source opens where it is, in a tab of its own', (
    tester,
  ) async {
    final container = await openShell(tester);
    container.read(tabsProvider.notifier).toggleAi();
    await tester.pumpAndSettle();
    await ask(tester, 'What is force?');

    await tester.tap(find.byType(FootnoteMark));
    await tester.pumpAndSettle();

    final tabs = container.read(tabsProvider);
    expect(tabs.tabs, hasLength(2));
    expect(tabs.current.ai, isFalse);
    expect(tabs.current.pageId, page.id);
    final canvas = tester.widget<InfiniteCanvas>(find.byType(InfiniteCanvas));
    expect(canvas.controller.selection, <String>{'law'}, reason: 'picked out');
    // The very sentence cited is marked.
    final box = tester.widget<TextBoxEditor>(find.byType(TextBoxEditor));
    expect(box.mark, (block: 0, from: 0, to: 33));
  });

  testWidgets('flashcards are made from the notes, kept, and studied: '
      'turned over, graded, and due again later', (tester) async {
    final container = await openShell(tester);
    container.read(tabsProvider.notifier).toggleAi();
    await tester.pumpAndSettle();
    expect(find.byType(StudyOverview), findsOneWidget);

    await tester.tap(
      find.descendant(
        of: find.byKey(const ValueKey<StudyKind>(StudyKind.flashcards)),
        matching: find.text('Make'),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.byType(FlashcardsView), findsOneWidget);
    final items = await tester.runAsync(
      () => store.ai.itemsAbout(NoteLink.page(page.id)),
    );
    expect(items!.single.kind, 'flashcards');

    // A card, its question showing; turned over, its answer and where it
    // is in the notes.
    expect(find.text('0 of 2'), findsOneWidget);
    expect(find.text('What is force?'), findsOneWidget);
    await tester.tap(find.text('Show answer'));
    await tester.pumpAndSettle();
    expect(find.textContaining('Mass times acceleration'), findsWidgets);
    expect(find.byType(SourceLine), findsOneWidget);

    await tester.tap(find.text('Good'));
    await tester.pumpAndSettle();
    expect(find.text('1 of 2'), findsOneWidget);
    final reviews = await tester.runAsync(
      () => store.ai.reviewsOf(items.single.id),
    );
    expect(reviews, hasLength(1));
  });

  testWidgets('a set not made yet is only made when asked, and while one '
      'is made everything else can be done', (tester) async {
    final container = await openShell(tester);
    container.read(tabsProvider.notifier).toggleAi();
    await tester.pumpAndSettle();
    Future<void> settle() async {
      for (var i = 0; i < 10; i++) {
        await tester.pump(const Duration(milliseconds: 50));
      }
    }

    // Looking at a kind not made yet makes nothing.
    // The list down the side comes first.
    await tester.tap(
      find
          .descendant(of: find.byType(AiView), matching: find.text('Quiz'))
          .first,
    );
    await settle();
    expect(find.byType(StudyKindPage), findsOneWidget);
    expect(model.asked, isEmpty);

    // Flashcards being made; meanwhile the overview, and the summary made.
    final cards = model.cardsGate = Completer<void>();
    await tester.tap(find.text('Overview'));
    await settle();
    await tester.tap(
      find.descendant(
        of: find.byKey(const ValueKey<StudyKind>(StudyKind.flashcards)),
        matching: find.text('Make'),
      ),
    );
    await settle();
    expect(find.byType(StudyDraftPage), findsOneWidget);
    await tester.tap(find.text('Overview'));
    await settle();
    expect(find.byType(StudyOverview), findsOneWidget);
    await tester.tap(
      find.descendant(
        of: find.byKey(const ValueKey<StudyKind>(StudyKind.summary)),
        matching: find.text('Make'),
      ),
    );
    await settle();
    expect(find.byType(SummarySheet), findsOneWidget);

    // The flashcards, done, are kept without taking the summary's place.
    cards.complete();
    await settle();
    expect(find.byType(SummarySheet), findsOneWidget);
    final items = await tester.runAsync(
      () => store.ai.itemsAbout(NoteLink.page(page.id)),
    );
    expect(
      items!.map((item) => item.kind),
      unorderedEquals(<String>['flashcards', 'summary']),
    );
  });

  testWidgets('a summary is set out as a study sheet, each point numbered '
      'to its sentence', (tester) async {
    final container = await openShell(tester);
    container.read(tabsProvider.notifier).toggleAi();
    await tester.pumpAndSettle();
    await tester.tap(
      find.descendant(
        of: find.byKey(const ValueKey<StudyKind>(StudyKind.summary)),
        matching: find.text('Make'),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.byType(SummarySheet), findsOneWidget);
    expect(find.text('BEYOND YOUR NOTES'), findsOneWidget);
    expect(find.byType(FootnoteMark), findsNWidgets(2));
    expect(find.text('FROM YOUR NOTES'), findsOneWidget);
  });

  testWidgets('a section has an AI of its own, from its menu', (tester) async {
    final container = await openShell(tester);
    await tester.tap(
      find.descendant(
        of: find.byType(LibraryPane),
        matching: find.text('Mechanics'),
      ),
      buttons: kSecondaryMouseButton,
      kind: PointerDeviceKind.mouse,
    );
    await tester.pumpAndSettle();
    await tester.tap(find.text('Ask AI'));
    await tester.pumpAndSettle();

    expect(container.read(tabsProvider).current.pageId, isNull);
    expect(
      find.descendant(
        of: find.byType(StudyOverview),
        matching: find.text('Mechanics'),
      ),
      findsOneWidget,
    );
    expect(
      find.text('Starts from this section, then all your notes'),
      findsOneWidget,
    );
  });

  testWidgets('without a model, it offers to choose one', (tester) async {
    final preferences = Preferences.inMemory();
    final container = await openShell(
      tester,
      withModel: false,
      preferences: preferences,
    );
    container.read(tabsProvider.notifier).toggleAi();
    await tester.pumpAndSettle();

    expect(find.text('Ask about your notes'), findsOneWidget);
    await tester.tap(find.widgetWithText(FilledButton, 'Choose a model'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Add a model provider…'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Anthropic'));
    await tester.pumpAndSettle();

    expect(
      find.textContaining('Sends the notes you ask about to api.anthropic.com'),
      findsOneWidget,
    );
    final saved = AiSettings.fromJson(preferences['ai']);
    expect(saved.active!.preset, ProviderPreset.anthropic);
    expect(saved.active!.model, AnthropicProvider.defaultModel);
    expect(
      preferences['ai'].toString(),
      isNot(contains('sk-')),
      reason: 'no keys',
    );
  });
}
