/// The study side of a notebook's, section's or page's AI: an overview of
/// what can be made to learn from it, each set on a page of its own, and a
/// set shown as it is made.
library;

import 'dart:async';

import 'package:aantekening_ai/aantekening_ai.dart';
import 'package:aantekening_core/aantekening_core.dart';
import 'package:aantekening_store/aantekening_store.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../command_menu.dart';
import '../look/controls.dart';
import '../look/glass.dart';
import '../look/motion.dart';
import '../look/tones.dart';
import '../modes/key_guide.dart' show KeyCap;
import 'ai_session.dart';
import 'ai_state.dart';
import 'answer_progress.dart';
import 'answer_view.dart';
import 'flashcards_view.dart';
import 'glossary_view.dart';
import 'money.dart';
import 'quiz_view.dart';
import 'study_profile_editor.dart';
import 'study_style.dart';
import 'summary_sheet.dart';

/// What [set] holds, counted: "12 cards", "8 questions".
String sizeOf(StudySet set) => switch (set) {
  StudySummary(:final sections) =>
    '${sections.length} ${sections.length == 1 ? 'part' : 'parts'}',
  FlashcardSet(:final cards) =>
    '${cards.length} ${cards.length == 1 ? 'card' : 'cards'}',
  QuizSet(:final questions) =>
    '${questions.length} ${questions.length == 1 ? 'question' : 'questions'}',
  Glossary(:final terms) =>
    '${terms.length} ${terms.length == 1 ? 'term' : 'terms'}',
  StudyText(:final size) => '$size ${size == 1 ? 'word' : 'words'}',
};

/// When [millis] was, as a person says it: "today", "3 days ago".
String whenOf(int millis) {
  final then = DateTime.fromMillisecondsSinceEpoch(millis);
  final days = DateTime.now().difference(then).inDays;
  return switch (days) {
    0 => 'today',
    1 => 'yesterday',
    < 30 => '$days days ago',
    _ =>
      '${then.year}-${then.month.toString().padLeft(2, '0')}-'
          '${then.day.toString().padLeft(2, '0')}',
  };
}

/// Kept set [item], [set], made by [profile], on a page of its own: its
/// head, and the set as its kind is used.
class StudySetPage extends ConsumerWidget {
  const StudySetPage({
    required this.scope,
    required this.item,
    required this.set,
    required this.profile,
    required this.onOpen,
    super.key,
  });

  final NoteLink scope;
  final AiItem item;
  final StudySet set;
  final StudyProfile profile;
  final void Function(Citation citation) onOpen;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final session = ref.read(aiSessionProvider(scope).notifier);
    final info = ref.watch(aiScopeInfoProvider(scope)).value;
    final cards = set is FlashcardSet;
    return Column(
      children: <Widget>[
        StudyHeader(
          kind: set.kind,
          title: profile.name,
          subtitle: <String>[
            ?info?.title,
            sizeOf(set),
            'made ${whenOf(item.updatedAt)}'
                '${item.model.isEmpty ? '' : ' by ${item.model}'}',
            ?costNote(AiSession.costOf(item.usage)),
          ].join('  ·  '),
          actions: <Widget>[
            SmallButton(
              'Edit',
              tooltip: 'Change what is asked for, then make it again',
              onPressed: () => editStudyProfile(context, profile: profile),
            ),
            SmallButton(
              'Make again',
              onPressed: () async {
                if (cards &&
                    !await _confirm(
                      context,
                      'Make ${profile.called} again?',
                      'Cards that ask the same keep what you learnt of '
                          'them; the others start afresh.',
                    )) {
                  return;
                }
                unawaited(session.make(profile));
              },
            ),
            SmallButton(
              'Delete',
              onPressed: () async {
                if (await _confirm(
                  context,
                  'Delete ${profile.called}?',
                  cards
                      ? 'What you learnt of the cards goes with them.'
                      : 'You can make it again at any time.',
                )) {
                  await session.deleteItem(item.id);
                }
              },
            ),
          ],
        ),
        Expanded(
          child: switch (set) {
            final StudySummary summary => SingleChildScrollView(
              child: SummarySheet(
                summary: summary,
                onOpen: onOpen,
                fallbackTitle: info?.title ?? '',
              ),
            ),
            final FlashcardSet cards => FlashcardsView(
              itemId: item.id,
              set: cards,
              onOpen: onOpen,
              onChanged: (changed) =>
                  unawaited(session.updateSet(item.id, changed)),
            ),
            final QuizSet quiz => QuizView(
              key: ValueKey<int>(item.updatedAt),
              quiz: quiz,
              onOpen: onOpen,
            ),
            final Glossary glossary => GlossaryView(
              glossary: glossary,
              onOpen: onOpen,
            ),
            final StudyText text => SingleChildScrollView(
              child: StudyPaper(
                child: AnswerView(answer: text.answer, onOpen: onOpen),
              ),
            ),
          },
        ),
      ],
    );
  }
}

Future<bool> _confirm(BuildContext context, String title, String body) async =>
    await showAppDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(title),
        content: Text(body),
        actions: <Widget>[
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(context).pop(true),
            child: const Text('Go on'),
          ),
        ],
      ),
    ) ??
    false;

/// A profile whose set is not made yet: what it makes, and a button to
/// make it — so looking at it never sets a model to work by itself.
class StudyProfilePage extends ConsumerWidget {
  const StudyProfilePage({
    required this.scope,
    required this.profile,
    super.key,
  });

  final NoteLink scope;
  final StudyProfile profile;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final tones = context.tones;
    final info = ref.watch(aiScopeInfoProvider(scope)).value;
    final model = ref.watch(aiModelProvider).value;
    return Center(
      child: SingleChildScrollView(
        padding: const EdgeInsets.all(20),
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 420),
          child: Column(
            children: <Widget>[
              Text(
                profile.name,
                style: Theme.of(context).textTheme.titleLarge,
              ),
              const SizedBox(height: 6),
              Text(
                profile.purpose,
                textAlign: TextAlign.center,
                style: TextStyle(color: tones.muted, height: 1.45),
              ),
              const SizedBox(height: 6),
              Text(
                'Made from “${info?.title ?? ''}”'
                '${model == null ? '' : ' by ${model.config.model}'}. You can '
                'look at anything else while it is made.',
                textAlign: TextAlign.center,
                style: TextStyle(fontSize: 12.5, color: tones.faint),
              ),
              const SizedBox(height: 14),
              Wrap(
                spacing: 8,
                runSpacing: 8,
                alignment: WrapAlignment.center,
                children: <Widget>[
                  OutlinedButton(
                    style: OutlinedButton.styleFrom(
                      minimumSize: const Size(0, 38),
                    ),
                    onPressed: () =>
                        editStudyProfile(context, profile: profile),
                    child: const Text('Edit'),
                  ),
                  FilledButton(
                    style: FilledButton.styleFrom(
                      minimumSize: const Size(0, 38),
                    ),
                    onPressed: model == null
                        ? null
                        : () => unawaited(
                            ref
                                .read(aiSessionProvider(scope).notifier)
                                .make(profile),
                          ),
                    child: Text('Make ${profile.called}'),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// A set being made: how far it has got, and as much of it as is written,
/// laid out as it will be.
class StudyDraftPage extends ConsumerWidget {
  const StudyDraftPage({
    required this.scope,
    required this.pending,
    required this.onOpen,
    super.key,
  });

  final NoteLink scope;
  final PendingTurn pending;
  final void Function(Citation citation) onOpen;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final profile = pending.profile!;
    final info = ref.watch(aiScopeInfoProvider(scope)).value;
    final model = ref.watch(aiModelProvider).value;
    final draft = pending.progress.study;
    return Column(
      children: <Widget>[
        StudyHeader(
          kind: profile.form,
          title: 'Making ${profile.called}',
          subtitle: <String>[
            'from “${info?.title ?? ''}”',
            if (model != null) 'with ${model.config.model}',
            '— look at anything else meanwhile',
          ].join('  '),
          actions: <Widget>[
            OutlinedButton(
              onPressed: () => unawaited(
                ref
                    .read(aiSessionProvider(scope).notifier)
                    .stopMaking(profile.id),
              ),
              child: const Text('Stop'),
            ),
          ],
        ),
        Expanded(
          child: SingleChildScrollView(
            child: Column(
              children: <Widget>[
                Center(
                  child: ConstrainedBox(
                    constraints: const BoxConstraints(maxWidth: 740),
                    child: Padding(
                      padding: const EdgeInsets.fromLTRB(16, 0, 16, 10),
                      child: AnswerProgress(pending: pending),
                    ),
                  ),
                ),
                if (draft != null)
                  switch (draft) {
                    final StudySummary summary => SummarySheet(
                      summary: summary,
                      onOpen: onOpen,
                      fallbackTitle: info?.title ?? '',
                    ),
                    final FlashcardSet cards => CardList(
                      cards: cards.cards,
                      onOpen: onOpen,
                      scrolls: false,
                    ),
                    final QuizSet quiz => StudyPaper(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: <Widget>[
                          for (final (i, q) in quiz.questions.indexed)
                            Padding(
                              padding: const EdgeInsets.only(bottom: 10),
                              child: Text('${i + 1}.  ${q.question}'),
                            ),
                        ],
                      ),
                    ),
                    final Glossary glossary => GlossaryView(
                      glossary: glossary,
                      onOpen: onOpen,
                      scrolls: false,
                    ),
                    final StudyText text => StudyPaper(
                      child: AnswerView(
                        answer: text.answer,
                        onOpen: onOpen,
                        showSources: false,
                      ),
                    ),
                  },
              ],
            ),
          ),
        ),
      ],
    );
  }
}

/// The front of the scope's AI, all of it in view at once: the sets to
/// study it by, each on its digit; the questions ready to ask; and the
/// conversations and answers kept.
class StudyOverview extends ConsumerWidget {
  const StudyOverview({required this.scope, super.key});

  /// How many conversations are listed before the rest are left to the
  /// chooser.
  static const int _listed = 6;

  final NoteLink scope;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final tones = context.tones;
    final state = ref.watch(aiSessionProvider(scope));
    final session = ref.read(aiSessionProvider(scope).notifier);

    Widget heading(String label, {Widget? action}) => Padding(
      padding: const EdgeInsets.fromLTRB(6, 12, 0, 4),
      child: Row(
        children: <Widget>[
          Expanded(child: SmallCaps(label)),
          ?action,
        ],
      ),
    );

    return ListView(
      padding: const EdgeInsets.fromLTRB(8, 0, 8, 10),
      children: <Widget>[
        heading(
          'Study',
          action: SmallButton(
            'New study profile…',
            tooltip: 'Describe anything else to make from your notes: exam '
                'tasks, a cheat sheet, a timeline',
            onPressed: () => editStudyProfile(context),
          ),
        ),
        for (final (index, profile) in studyProfilesOf(ref, state).indexed)
          _StudyRow(
            key: ValueKey<String>(profile.id),
            digit: index < 9 ? '${index + 1}' : null,
            profile: profile,
            item: state.setOf(profile.id),
            making: state.making.containsKey(profile.id),
            onShow: () => session.openProfile(profile.id),
            onMake: () => unawaited(session.make(profile)),
          ),
        heading('Ask'),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 4),
          child: Wrap(
            spacing: 6,
            runSpacing: 6,
            children: <Widget>[
              for (final action in AiAction.values)
                PillButton(
                  action.label,
                  onPressed: state.pending != null
                      ? null
                      : () => askReady(ref, scope, action),
                ),
            ],
          ),
        ),
        if (state.threads.isNotEmpty) ...<Widget>[
          heading(
            'Conversations',
            action: state.threads.length > _listed
                ? KeyHint('c  all ${state.threads.length}')
                : null,
          ),
          for (final thread in state.threads.take(_listed))
            _Line(
              title: threadTitle(thread),
              trailing: whenOf(thread.updatedAt),
              onTap: () => unawaited(session.openThread(thread.id)),
              menu: <MenuCommand>[
                MenuCommand('Delete', () => session.deleteThread(thread.id)),
              ],
            ),
        ],
        if (state.savedAnswers.isNotEmpty) ...<Widget>[
          heading('Kept answers'),
          for (final item in state.savedAnswers)
            _Line(
              title: item.title,
              trailing: whenOf(item.createdAt),
              onTap: () => session.openItem(item.id),
              menu: <MenuCommand>[
                MenuCommand('Rename', () async {
                  final title = await askName(context, item.title);
                  if (title != null) await session.renameItem(item.id, title);
                }),
                MenuCommand('Delete', () => session.deleteItem(item.id)),
              ],
            ),
        ],
        if (state.threads.isEmpty && state.savedAnswers.isEmpty)
          Padding(
            padding: const EdgeInsets.fromLTRB(6, 14, 6, 0),
            child: Text(
              'Ask below — each question starts a conversation. What is made '
              'here is kept apart from the notes, and linked back to the '
              'very sentences it comes from.',
              style: TextStyle(fontSize: 12, height: 1.4, color: tones.muted),
            ),
          ),
      ],
    );
  }
}

/// One set to study the scope by, on a line: its digit, its name, how far
/// along it is, and a button to change it, and to make it while it is not
/// made.
class _StudyRow extends ConsumerWidget {
  const _StudyRow({
    required this.digit,
    required this.profile,
    required this.item,
    required this.making,
    required this.onShow,
    required this.onMake,
    super.key,
  });

  /// The key it is opened by, if it has one.
  final String? digit;
  final StudyProfile profile;
  final AiItem? item;

  /// Whether this set is being made now.
  final bool making;

  /// Shows its page: the set, it being made, or what it would be.
  final VoidCallback onShow;
  final VoidCallback onMake;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final tones = context.tones;
    final item = this.item;
    final set = item == null ? null : StudySet.fromJson(item.body);
    final due = cardsToStudy(ref, item);
    final digit = this.digit;
    return Tooltip(
      message: profile.purpose,
      waitDuration: const Duration(milliseconds: 600),
      child: InkWell(
        onTap: onShow,
        borderRadius: Corners.controlRadius,
        hoverColor: tones.veil,
        child: SizedBox(
          height: 34,
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 6),
            child: Row(
              children: <Widget>[
                SizedBox(
                  width: 30,
                  child: digit == null
                      ? null
                      : Align(
                          alignment: Alignment.centerLeft,
                          child: KeyCap(digit),
                        ),
                ),
                Expanded(
                  child: Row(
                    children: <Widget>[
                      Flexible(
                        child: Text(
                          profile.name,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(
                            fontSize: 13,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      ),
                      const SizedBox(width: 10),
                      Expanded(
                        child: Text(
                          making
                              ? 'Being made…'
                              : due > 0
                              ? '$due to study'
                              : set == null
                              ? 'Not made yet'
                              : '${sizeOf(set)}  ·  '
                                    '${whenOf(item!.updatedAt)}',
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(
                            fontSize: 12,
                            fontWeight: due > 0 ? FontWeight.w700 : null,
                            color: due > 0 ? tones.emphasis : tones.muted,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
                SmallButton(
                  'Edit',
                  tooltip: 'Change what is asked for',
                  onPressed: () => editStudyProfile(context, profile: profile),
                ),
                if (making)
                  const Busy(width: 32)
                else if (item == null)
                  PillButton('Make', lit: true, onPressed: onMake),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// A line of the overview's lists — a conversation, an answer kept — with
/// [menu] on a right-click or a long press.
class _Line extends StatelessWidget {
  const _Line({
    required this.title,
    required this.trailing,
    required this.onTap,
    this.menu = const <MenuCommand>[],
  });

  final String title;
  final String trailing;
  final VoidCallback onTap;
  final List<MenuCommand> menu;

  void _showMenu(BuildContext context) =>
      unawaited(showCommandMenu(context, <List<MenuCommand>>[menu]));

  @override
  Widget build(BuildContext context) => GestureDetector(
    onSecondaryTap: menu.isEmpty ? null : () => _showMenu(context),
    onLongPress: menu.isEmpty ? null : () => _showMenu(context),
    child: RowTile(
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 5),
      title: Text(title),
      trailing: KeyHint(trailing),
      onTap: onTap,
    ),
  );
}

/// What a conversation is called in the lists: its title, or what it is.
String threadTitle(AiThread thread) =>
    thread.title.isEmpty ? 'Conversation' : thread.title;

/// Asks [action]'s question about [scope], as the web is set to be
/// searched.
void askReady(WidgetRef ref, NoteLink scope, AiAction action) {
  final kindName = ref.read(aiScopeInfoProvider(scope)).value?.kindName;
  unawaited(
    ref
        .read(aiSessionProvider(scope).notifier)
        .ask(
          action.promptFor(kindName ?? 'page'),
          searchWeb: ref.read(aiSettingsProvider).searchWeb,
          action: action,
        ),
  );
}

/// Asks for a new name for something kept, [current] to start from.
Future<String?> askName(BuildContext context, String current) {
  final controller = TextEditingController(text: current);
  return showAppDialog<String>(
    context: context,
    builder: (context) => AlertDialog(
      title: const Text('Rename'),
      content: TextField(
        controller: controller,
        autofocus: true,
        onSubmitted: (value) => Navigator.of(context).pop(value.trim()),
      ),
      actions: <Widget>[
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('Cancel'),
        ),
        FilledButton(
          onPressed: () => Navigator.of(context).pop(controller.text.trim()),
          child: const Text('Rename'),
        ),
      ],
    ),
  ).whenComplete(controller.dispose);
}
