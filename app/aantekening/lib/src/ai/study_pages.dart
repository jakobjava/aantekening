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

import 'ai_session.dart';
import 'ai_state.dart';
import 'answer_progress.dart';
import 'flashcards_view.dart';
import 'glossary_view.dart';
import 'quiz_view.dart';
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

/// Kept set [item], [set], on a page of its own: its head, and the set as
/// its kind is used.
class StudySetPage extends ConsumerWidget {
  const StudySetPage({
    required this.scope,
    required this.item,
    required this.set,
    required this.onOpen,
    super.key,
  });

  final NoteLink scope;
  final AiItem item;
  final StudySet set;
  final void Function(Citation citation) onOpen;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final session = ref.read(aiSessionProvider(scope).notifier);
    final info = ref.watch(aiScopeInfoProvider(scope)).value;
    final kind = set.kind;
    return Column(
      children: <Widget>[
        StudyHeader(
          kind: kind,
          title: kind.label,
          subtitle: <String>[
            ?info?.title,
            sizeOf(set),
            'made ${whenOf(item.updatedAt)}'
                '${item.model.isEmpty ? '' : ' by ${item.model}'}',
          ].join('  ·  '),
          actions: <Widget>[
            TextButton.icon(
              icon: const Icon(Icons.refresh_rounded, size: 18),
              label: const Text('Make again'),
              onPressed: () async {
                if (kind == StudyKind.flashcards &&
                    !await _confirm(
                      context,
                      'Make the flashcards again?',
                      'Cards that ask the same keep what you learnt of '
                          'them; the others start afresh.',
                    )) {
                  return;
                }
                unawaited(session.make(kind));
              },
            ),
            IconButton(
              icon: const Icon(Icons.delete_outline_rounded),
              tooltip: 'Delete',
              onPressed: () async {
                if (await _confirm(
                  context,
                  'Delete the ${kind.label.toLowerCase()}?',
                  kind == StudyKind.flashcards
                      ? 'What you learnt of the cards goes with them.'
                      : 'You can make them again at any time.',
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
          },
        ),
      ],
    );
  }
}

Future<bool> _confirm(BuildContext context, String title, String body) async =>
    await showDialog<bool>(
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

/// A kind of set not made yet: what it is, and a button to make it — so
/// looking at it never sets a model to work by itself.
class StudyKindPage extends ConsumerWidget {
  const StudyKindPage({required this.scope, required this.kind, super.key});

  final NoteLink scope;
  final StudyKind kind;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final info = ref.watch(aiScopeInfoProvider(scope)).value;
    final model = ref.watch(aiModelProvider).value;
    final accent = kind.accent(scheme);
    return Center(
      child: SingleChildScrollView(
        padding: const EdgeInsets.all(24),
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 460),
          child: Column(
            children: <Widget>[
              StudyBadge(kind, size: 64),
              const SizedBox(height: 16),
              Text(
                kind.label,
                style: theme.textTheme.headlineSmall?.copyWith(
                  fontWeight: FontWeight.w700,
                ),
              ),
              const SizedBox(height: 8),
              Text(
                kind.purpose,
                textAlign: TextAlign.center,
                style: TextStyle(color: scheme.onSurfaceVariant, height: 1.45),
              ),
              const SizedBox(height: 6),
              Text(
                'Made from “${info?.title ?? ''}”'
                '${model == null ? '' : ' by ${model.config.model}'}. You can '
                'look at anything else while it is made.',
                textAlign: TextAlign.center,
                style: TextStyle(fontSize: 12.5, color: scheme.outline),
              ),
              const SizedBox(height: 20),
              FilledButton.icon(
                style: FilledButton.styleFrom(
                  backgroundColor: accent,
                  minimumSize: const Size(0, 44),
                ),
                icon: const Icon(Icons.auto_awesome_rounded, size: 18),
                label: Text('Make the ${kind.label.toLowerCase()}'),
                onPressed: model == null
                    ? null
                    : () => unawaited(
                        ref.read(aiSessionProvider(scope).notifier).make(kind),
                      ),
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
    final kind = pending.study!;
    final info = ref.watch(aiScopeInfoProvider(scope)).value;
    final model = ref.watch(aiModelProvider).value;
    final draft = pending.progress.study;
    return Column(
      children: <Widget>[
        StudyHeader(
          kind: kind,
          title: 'Making the ${kind.label.toLowerCase()}',
          subtitle: <String>[
            'from “${info?.title ?? ''}”',
            if (model != null) 'with ${model.config.model}',
            '— look at anything else meanwhile',
          ].join('  '),
          actions: <Widget>[
            TextButton.icon(
              icon: const Icon(Icons.stop_rounded, size: 18),
              label: const Text('Stop'),
              onPressed: () => unawaited(
                ref.read(aiSessionProvider(scope).notifier).stopMaking(kind),
              ),
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
                      padding: const EdgeInsets.fromLTRB(24, 0, 24, 12),
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
                  },
              ],
            ),
          ),
        ),
      ],
    );
  }
}

/// The front of the scope's AI: what can be made to learn from it, and how
/// far along each is; the cards due; questions to ask; and the
/// conversations and answers kept.
class StudyOverview extends ConsumerWidget {
  const StudyOverview({required this.scope, super.key});

  final NoteLink scope;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final state = ref.watch(aiSessionProvider(scope));
    final session = ref.read(aiSessionProvider(scope).notifier);
    final info = ref.watch(aiScopeInfoProvider(scope)).value;
    final web = ref.watch(aiSettingsProvider.select((s) => s.searchWeb));
    final kindName = info?.kindName ?? 'page';

    return LayoutBuilder(
      builder: (context, constraints) {
        final columns = constraints.maxWidth > 720 ? 2 : 1;
        final width =
            (constraints.maxWidth.clamp(0, 860) - 48 - 16 * (columns - 1)) /
            columns;
        return SingleChildScrollView(
          padding: const EdgeInsets.fromLTRB(24, 28, 24, 24),
          child: Center(
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 812),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: <Widget>[
                  SmallCaps('Study this $kindName'),
                  const SizedBox(height: 4),
                  Text(
                    info?.title ?? '',
                    style: theme.textTheme.headlineMedium?.copyWith(
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                  const SizedBox(height: 6),
                  Text(
                    'Made from your notes, kept apart from them, and linked '
                    'back to the very sentences they come from.',
                    style: TextStyle(color: scheme.onSurfaceVariant),
                  ),
                  const SizedBox(height: 22),
                  Wrap(
                    spacing: 16,
                    runSpacing: 16,
                    children: <Widget>[
                      for (final kind in StudyKind.values)
                        SizedBox(
                          width: width,
                          child: _StudyTile(
                            key: ValueKey<StudyKind>(kind),
                            kind: kind,
                            item: state.setOf(kind),
                            making: state.making.containsKey(kind),
                            onShow: () => session.openKind(kind),
                            onMake: () => unawaited(session.make(kind)),
                          ),
                        ),
                    ],
                  ),
                  const SizedBox(height: 30),
                  const SmallCaps('Ask about it'),
                  const SizedBox(height: 10),
                  Wrap(
                    spacing: 8,
                    runSpacing: 8,
                    children: <Widget>[
                      for (final action in AiAction.values)
                        ActionChip(
                          avatar: Icon(_iconOf(action), size: 17),
                          label: Text(action.label),
                          onPressed: state.pending != null
                              ? null
                              : () => unawaited(
                                  session.ask(
                                    action.promptFor(kindName),
                                    searchWeb: web,
                                    action: action,
                                  ),
                                ),
                        ),
                    ],
                  ),
                  if (state.threads.isNotEmpty) ...<Widget>[
                    const SizedBox(height: 26),
                    const SmallCaps('Conversations'),
                    const SizedBox(height: 6),
                    for (final thread in state.threads.take(5))
                      _Line(
                        icon: Icons.forum_outlined,
                        title: thread.title.isEmpty
                            ? 'Conversation'
                            : thread.title,
                        trailing: whenOf(thread.updatedAt),
                        onTap: () => unawaited(session.openThread(thread.id)),
                      ),
                  ],
                  if (state.savedAnswers.isNotEmpty) ...<Widget>[
                    const SizedBox(height: 22),
                    const SmallCaps('Kept answers'),
                    const SizedBox(height: 6),
                    for (final item in state.savedAnswers)
                      _Line(
                        icon: Icons.bookmark_outline_rounded,
                        title: item.title,
                        trailing: whenOf(item.createdAt),
                        onTap: () => session.openItem(item.id),
                      ),
                  ],
                ],
              ),
            ),
          ),
        );
      },
    );
  }

  static IconData _iconOf(AiAction action) => switch (action) {
    AiAction.explain => Icons.lightbulb_outline_rounded,
    AiAction.test => Icons.assignment_outlined,
    AiAction.tutor => Icons.record_voice_over_outlined,
    AiAction.connect => Icons.hub_outlined,
  };
}

/// One kind of set on the overview: what it is for, whether it is made and
/// how far along it is, and a button to open or make it.
class _StudyTile extends ConsumerWidget {
  const _StudyTile({
    required this.kind,
    super.key,
    required this.item,
    required this.making,
    required this.onShow,
    required this.onMake,
  });

  final StudyKind kind;
  final AiItem? item;

  /// Whether this set is being made now.
  final bool making;

  /// Shows its page: the set, it being made, or what it would be.
  final VoidCallback onShow;
  final VoidCallback onMake;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final accent = kind.accent(scheme);
    final item = this.item;
    final set = item == null ? null : StudySet.fromJson(item.body);
    final due = switch ((item, set)) {
      (final AiItem item, final FlashcardSet cards) => () {
        final status = deckStatus(
          cards.cards,
          ref.watch(cardReviewsProvider(item.id)).value ??
              const <String, CardReview>{},
          DateTime.now(),
        );
        return status.due + status.fresh.clamp(0, newCardsPerSession);
      }(),
      _ => 0,
    };
    final open = switch (kind) {
      StudyKind.summary => 'Read',
      StudyKind.flashcards => due > 0 ? 'Study $due' : 'Open',
      StudyKind.quiz => 'Take the quiz',
      StudyKind.terms => 'Open',
    };

    return Material(
      color: scheme.surface,
      borderRadius: BorderRadius.circular(16),
      child: InkWell(
        borderRadius: BorderRadius.circular(16),
        onTap: onShow,
        child: Container(
          padding: const EdgeInsets.fromLTRB(18, 16, 14, 14),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(16),
            border: Border.all(color: scheme.outlineVariant),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: <Widget>[
              Row(
                children: <Widget>[
                  StudyBadge(kind, size: 40),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Text(
                      kind.label,
                      style: theme.textTheme.titleMedium?.copyWith(
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ),
                  if (due > 0)
                    Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 8,
                        vertical: 3,
                      ),
                      decoration: BoxDecoration(
                        color: accent,
                        borderRadius: BorderRadius.circular(10),
                      ),
                      child: Text(
                        '$due to study',
                        style: const TextStyle(
                          fontSize: 11.5,
                          fontWeight: FontWeight.w700,
                          color: Colors.white,
                        ),
                      ),
                    ),
                ],
              ),
              const SizedBox(height: 10),
              Text(
                kind.purpose,
                maxLines: 2,
                style: TextStyle(
                  fontSize: 13,
                  height: 1.4,
                  color: scheme.onSurfaceVariant,
                ),
              ),
              const SizedBox(height: 14),
              Row(
                children: <Widget>[
                  Expanded(
                    child: Text(
                      making
                          ? 'Being made…'
                          : set == null
                          ? 'Not made yet'
                          : '${sizeOf(set)}  ·  ${whenOf(item!.updatedAt)}',
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(fontSize: 12, color: scheme.outline),
                    ),
                  ),
                  if (making)
                    const SizedBox.square(
                      dimension: 18,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  else if (item != null)
                    FilledButton.tonal(
                      style: FilledButton.styleFrom(
                        visualDensity: VisualDensity.compact,
                        backgroundColor: accent.withValues(alpha: 0.14),
                        foregroundColor: accent,
                      ),
                      onPressed: onShow,
                      child: Text(open),
                    )
                  else
                    FilledButton.icon(
                      style: FilledButton.styleFrom(
                        visualDensity: VisualDensity.compact,
                        backgroundColor: accent,
                      ),
                      icon: const Icon(Icons.auto_awesome_rounded, size: 16),
                      label: const Text('Make'),
                      onPressed: onMake,
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

/// A line of the overview's lists: a conversation, a kept answer.
class _Line extends StatelessWidget {
  const _Line({
    required this.icon,
    required this.title,
    required this.trailing,
    required this.onTap,
  });

  final IconData icon;
  final String title;
  final String trailing;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return InkWell(
      borderRadius: BorderRadius.circular(8),
      onTap: onTap,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 8),
        child: Row(
          children: <Widget>[
            Icon(icon, size: 17, color: scheme.onSurfaceVariant),
            const SizedBox(width: 10),
            Expanded(
              child: Text(title, maxLines: 1, overflow: TextOverflow.ellipsis),
            ),
            Text(
              trailing,
              style: TextStyle(fontSize: 12, color: scheme.outline),
            ),
          ],
        ),
      ),
    );
  }
}
