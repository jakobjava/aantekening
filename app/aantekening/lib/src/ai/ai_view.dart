/// A notebook's, section's or page's AI: asking about it, and what was
/// kept of the answers.
library;

import 'dart:async';

import 'package:aantekening_ai/aantekening_ai.dart';
import 'package:aantekening_core/aantekening_core.dart';
import 'package:aantekening_store/aantekening_store.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../links/note_links.dart';
import 'ai_session.dart';
import 'ai_settings_dialog.dart';
import 'ai_state.dart';
import 'answer_progress.dart';
import 'answer_view.dart';
import 'flashcards_view.dart';
import 'study_pages.dart';
import 'study_style.dart';

/// The AI of [scope], in place of the page: what was kept about it and its
/// conversations down the side, the conversation showing, and a line at the
/// foot to ask in.
///
/// Everything here is the AI's, drawn apart from the notes — never on the
/// page, never in its text — and each answer shows where each part of it
/// comes from.
class AiView extends ConsumerWidget {
  const AiView({required this.scope, super.key});

  final NoteLink scope;

  /// How wide the window is at least for the list down the side to show.
  static const double railFrom = 760;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final scheme = Theme.of(context).colorScheme;
    return Material(
      color: scheme.surfaceContainerLowest,
      child: LayoutBuilder(
        builder: (context, constraints) {
          final rail = constraints.maxWidth >= railFrom;
          return Row(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: <Widget>[
              if (rail) ...<Widget>[
                SizedBox(width: 244, child: _Rail(scope: scope)),
                const VerticalDivider(width: 1),
              ],
              Expanded(
                child: _Main(scope: scope, backToOverview: !rail),
              ),
            ],
          );
        },
      ),
    );
  }
}

// -------------------------------------------------------------------- rail

/// The way round the scope's AI: its overview, each kind of set to study,
/// its conversations, and the answers kept.
class _Rail extends ConsumerWidget {
  const _Rail({required this.scope});

  final NoteLink scope;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final scheme = Theme.of(context).colorScheme;
    final state = ref.watch(aiSessionProvider(scope));
    final session = ref.read(aiSessionProvider(scope).notifier);

    Widget heading(String label, {Widget? action}) => Padding(
      padding: const EdgeInsets.fromLTRB(10, 18, 4, 4),
      child: Row(
        children: <Widget>[
          Expanded(child: SmallCaps(label)),
          ?action,
        ],
      ),
    );

    Widget entry({
      required Widget leading,
      required String title,
      required bool selected,
      required VoidCallback? onTap,
      Widget? trailing,
      List<Widget> menu = const <Widget>[],
    }) => Padding(
      padding: const EdgeInsets.symmetric(vertical: 1),
      child: Material(
        color: selected
            ? scheme.secondaryContainer.withValues(alpha: 0.7)
            : Colors.transparent,
        borderRadius: BorderRadius.circular(9),
        child: InkWell(
          borderRadius: BorderRadius.circular(9),
          onTap: onTap,
          child: Padding(
            padding: EdgeInsets.fromLTRB(8, 7, menu.isEmpty ? 8 : 0, 7),
            child: Row(
              children: <Widget>[
                leading,
                const SizedBox(width: 10),
                Expanded(
                  child: Text(
                    title,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      fontSize: 13.5,
                      fontWeight: selected ? FontWeight.w600 : null,
                    ),
                  ),
                ),
                ?trailing,
                if (menu.isNotEmpty)
                  MenuAnchor(
                    menuChildren: menu,
                    builder: (context, controller, _) => SizedBox.square(
                      dimension: 28,
                      child: IconButton(
                        padding: EdgeInsets.zero,
                        icon: const Icon(Icons.more_horiz_rounded, size: 17),
                        tooltip: 'More',
                        onPressed: () => controller.isOpen
                            ? controller.close()
                            : controller.open(),
                      ),
                    ),
                  ),
              ],
            ),
          ),
        ),
      ),
    );

    Widget count(String text, {Color? color}) => Text(
      text,
      style: TextStyle(
        fontSize: 12,
        fontWeight: color == null ? null : FontWeight.w700,
        color: color ?? scheme.outline,
      ),
    );

    return ListView(
      padding: const EdgeInsets.fromLTRB(8, 10, 8, 16),
      children: <Widget>[
        entry(
          leading: Icon(
            Icons.space_dashboard_outlined,
            size: 20,
            color: scheme.onSurfaceVariant,
          ),
          title: 'Overview',
          selected: state.atOverview,
          onTap: session.newThread,
        ),
        heading('Study'),
        for (final kind in StudyKind.values)
          Builder(
            builder: (context) {
              final item = state.setOf(kind);
              final set = item == null ? null : StudySet.fromJson(item.body);
              final making = state.making.containsKey(kind);
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
              return entry(
                leading: StudyBadge(kind, size: 26),
                title: kind.label,
                selected:
                    state.shownKind == kind ||
                    (item != null && state.itemId == item.id),
                onTap: () => session.openKind(kind),
                trailing: making
                    ? const SizedBox.square(
                        dimension: 14,
                        child: CircularProgressIndicator(strokeWidth: 1.8),
                      )
                    : due > 0
                    ? count('$due', color: kind.accent(scheme))
                    : set == null
                    ? Icon(Icons.add_rounded, size: 17, color: scheme.outline)
                    : set is StudySummary
                    ? Icon(Icons.check_rounded, size: 16, color: scheme.outline)
                    : count('${set.size}'),
              );
            },
          ),
        heading(
          'Conversations',
          action: SizedBox.square(
            dimension: 28,
            child: IconButton(
              padding: EdgeInsets.zero,
              icon: const Icon(Icons.add_rounded, size: 18),
              tooltip: 'Ask something new',
              onPressed: session.newThread,
            ),
          ),
        ),
        if (state.threads.isEmpty)
          Padding(
            padding: const EdgeInsets.fromLTRB(10, 2, 10, 0),
            child: Text(
              'Ask below — each question starts one.',
              style: TextStyle(fontSize: 12, color: scheme.outline),
            ),
          ),
        for (final thread in state.threads)
          entry(
            leading: Icon(
              Icons.forum_outlined,
              size: 18,
              color: scheme.onSurfaceVariant,
            ),
            title: thread.title.isEmpty ? 'Conversation' : thread.title,
            selected: state.itemId == null && state.threadId == thread.id,
            onTap: () => unawaited(session.openThread(thread.id)),
            menu: <Widget>[
              MenuItemButton(
                leadingIcon: const Icon(Icons.delete_outline_rounded),
                onPressed: () => session.deleteThread(thread.id),
                child: const Text('Delete'),
              ),
            ],
          ),
        if (state.savedAnswers.isNotEmpty) ...<Widget>[
          heading('Kept answers'),
          for (final item in state.savedAnswers)
            entry(
              leading: Icon(
                Icons.bookmark_outline_rounded,
                size: 18,
                color: scheme.onSurfaceVariant,
              ),
              title: item.title,
              selected: state.itemId == item.id,
              onTap: () => session.openItem(item.id),
              menu: <Widget>[
                MenuItemButton(
                  leadingIcon: const Icon(
                    Icons.drive_file_rename_outline_rounded,
                  ),
                  onPressed: () async {
                    final title = await _askName(context, item.title);
                    if (title != null) await session.renameItem(item.id, title);
                  },
                  child: const Text('Rename'),
                ),
                MenuItemButton(
                  leadingIcon: const Icon(Icons.delete_outline_rounded),
                  onPressed: () => session.deleteItem(item.id),
                  child: const Text('Delete'),
                ),
              ],
            ),
        ],
      ],
    );
  }
}

Future<String?> _askName(BuildContext context, String current) {
  final controller = TextEditingController(text: current);
  return showDialog<String>(
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

// -------------------------------------------------------------------- main

class _Main extends ConsumerStatefulWidget {
  const _Main({required this.scope, required this.backToOverview});

  final NoteLink scope;

  /// Whether to offer a way back to the overview, where the list down the
  /// side, which has one, is not shown.
  final bool backToOverview;

  @override
  ConsumerState<_Main> createState() => _MainState();
}

class _MainState extends ConsumerState<_Main> {
  final ScrollController _scroll = ScrollController();

  @override
  void dispose() {
    _scroll.dispose();
    super.dispose();
  }

  /// Keeps the newest of the answer in view as it arrives, unless the
  /// person has scrolled up to read.
  void _follow() {
    if (!_scroll.hasClients) return;
    final position = _scroll.position;
    if (position.maxScrollExtent - position.pixels < 120) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (_scroll.hasClients) {
          _scroll.jumpTo(_scroll.position.maxScrollExtent);
        }
      });
    }
  }

  void _open(Citation citation) =>
      unawaited(ref.read(noteLinksProvider).open(citation.uri, newTab: true));

  @override
  Widget build(BuildContext context) {
    final scope = widget.scope;
    final state = ref.watch(aiSessionProvider(scope));
    final model = ref.watch(aiModelProvider);
    ref.listen(aiSessionProvider(scope), (_, _) => _follow());

    final item = state.item;
    final shownKind = state.shownKind;
    final set = item == null ? null : StudySet.fromJson(item.body);
    final Widget page;
    if (!state.loaded || model.isLoading) {
      page = const Center(child: CircularProgressIndicator());
    } else if (item != null && set != null) {
      page = StudySetPage(scope: scope, item: item, set: set, onOpen: _open);
    } else if (item != null) {
      page = _ItemReader(scope: scope, item: item, onOpen: _open);
    } else if (shownKind != null) {
      page = switch (state.making[shownKind]) {
        final making? => StudyDraftPage(
          scope: scope,
          pending: making,
          onOpen: _open,
        ),
        null => StudyKindPage(scope: scope, kind: shownKind),
      };
    } else if (model.value == null) {
      page = const _ChooseModel();
    } else if (state.atOverview) {
      page = StudyOverview(scope: scope);
    } else {
      page = _Conversation(
        scope: scope,
        state: state,
        scroll: _scroll,
        onOpen: _open,
      );
    }
    return Column(
      children: <Widget>[
        if (widget.backToOverview && !state.atOverview)
          Align(
            alignment: Alignment.centerLeft,
            child: Padding(
              padding: const EdgeInsets.fromLTRB(8, 6, 8, 0),
              child: TextButton.icon(
                icon: const Icon(Icons.arrow_back_rounded, size: 18),
                label: const Text('Overview'),
                onPressed: ref
                    .read(aiSessionProvider(scope).notifier)
                    .newThread,
              ),
            ),
          ),
        Expanded(child: page),
        if (state.error != null) _ErrorLine(message: state.error!),
        _Composer(scope: scope),
      ],
    );
  }
}

class _ErrorLine extends StatelessWidget {
  const _ErrorLine({required this.message});

  final String message;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Container(
      width: double.infinity,
      margin: const EdgeInsets.fromLTRB(16, 0, 16, 6),
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      decoration: BoxDecoration(
        color: scheme.errorContainer,
        borderRadius: BorderRadius.circular(8),
      ),
      child: Text(message, style: TextStyle(color: scheme.onErrorContainer)),
    );
  }
}

/// Before a model is chosen: what the AI does, and where to choose one.
class _ChooseModel extends ConsumerWidget {
  const _ChooseModel();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final scheme = Theme.of(context).colorScheme;
    return Center(
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 460),
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: <Widget>[
              Icon(
                Icons.auto_awesome_rounded,
                size: 40,
                color: scheme.tertiary,
              ),
              const SizedBox(height: 12),
              Text(
                'Ask about your notes',
                style: Theme.of(context).textTheme.titleLarge,
              ),
              const SizedBox(height: 8),
              Text(
                'Choose a model to answer: one running on this computer, where '
                'your notes stay, or a provider you trust. Answers come from '
                'your notes first and say where each part comes from.',
                textAlign: TextAlign.center,
                style: TextStyle(color: scheme.onSurfaceVariant, height: 1.4),
              ),
              const SizedBox(height: 16),
              FilledButton.icon(
                icon: const Icon(Icons.tune_rounded),
                label: const Text('Choose a model'),
                onPressed: () => showAiSettings(context),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// The questions of a conversation and their answers, and the one being
/// answered.
class _Conversation extends ConsumerWidget {
  const _Conversation({
    required this.scope,
    required this.state,
    required this.scroll,
    required this.onOpen,
  });

  final NoteLink scope;
  final AiSessionState state;
  final ScrollController scroll;
  final void Function(Citation citation) onOpen;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final session = ref.read(aiSessionProvider(scope).notifier);
    final pending = state.pending;
    return ListView(
      controller: scroll,
      padding: const EdgeInsets.fromLTRB(0, 16, 0, 24),
      children: <Widget>[
        for (final turn in state.turns)
          _Exchange(
            question: turn.question,
            answer: AiAnswer.fromJson(turn.answer),
            byline: <String>[
              turn.provider,
              turn.model,
              if (AiSession.tookOf(turn) case final took?) wholeSeconds(took),
            ].join(' · '),
            onOpen: onOpen,
            kept: session.isKept(turn),
            onKeep: () => unawaited(session.keep(turn)),
            onAddCards: (cards) => unawaited(session.addCards(cards)),
          ),
        if (pending != null)
          _Exchange(
            question: pending.question,
            answer: pending.answer,
            pending: pending,
            onOpen: onOpen,
          ),
      ],
    );
  }
}

/// A question, and its answer beneath it.
class _Exchange extends StatelessWidget {
  const _Exchange({
    required this.question,
    required this.answer,
    required this.onOpen,
    this.byline,
    this.pending,
    this.kept = false,
    this.onKeep,
    this.onAddCards,
  });

  final String question;
  final AiAnswer answer;
  final void Function(Citation citation) onOpen;

  /// Who answered.
  final String? byline;

  /// How the answer is coming along, while it comes.
  final PendingTurn? pending;
  final bool kept;
  final VoidCallback? onKeep;
  final ValueChanged<List<StudyCard>>? onAddCards;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final done = byline != null;
    return Center(
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 760),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 8),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: <Widget>[
              Align(
                alignment: Alignment.centerRight,
                child: Container(
                  constraints: const BoxConstraints(maxWidth: 560),
                  padding: const EdgeInsets.symmetric(
                    horizontal: 14,
                    vertical: 10,
                  ),
                  decoration: BoxDecoration(
                    color: scheme.primaryContainer.withValues(alpha: 0.6),
                    borderRadius: BorderRadius.circular(14),
                  ),
                  child: SelectableText(question),
                ),
              ),
              const SizedBox(height: 12),
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: <Widget>[
                  Padding(
                    padding: const EdgeInsets.only(top: 2, right: 10),
                    child: CircleAvatar(
                      radius: 13,
                      backgroundColor: scheme.tertiaryContainer,
                      child: Icon(
                        Icons.auto_awesome_rounded,
                        size: 14,
                        color: scheme.onTertiaryContainer,
                      ),
                    ),
                  ),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: <Widget>[
                        if (pending != null) AnswerProgress(pending: pending!),
                        if (!answer.isEmpty)
                          AnswerView(
                            answer: answer,
                            onOpen: onOpen,
                            showSources: done,
                            onAddCards: onAddCards,
                          ),
                        if (done)
                          Row(
                            children: <Widget>[
                              Text(
                                byline!,
                                style: TextStyle(
                                  fontSize: 11.5,
                                  color: scheme.outline,
                                ),
                              ),
                              const Spacer(),
                              IconButton(
                                icon: const Icon(Icons.copy_rounded, size: 17),
                                tooltip: 'Copy the answer',
                                visualDensity: VisualDensity.compact,
                                onPressed: () => Clipboard.setData(
                                  ClipboardData(text: answer.plainText),
                                ),
                              ),
                              TextButton.icon(
                                icon: Icon(
                                  kept
                                      ? Icons.bookmark_rounded
                                      : Icons.bookmark_add_outlined,
                                  size: 18,
                                ),
                                label: Text(kept ? 'Kept' : 'Keep'),
                                onPressed: kept ? null : onKeep,
                              ),
                            ],
                          ),
                      ],
                    ),
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

/// Something kept, read again: its answer, and what it came from.
class _ItemReader extends ConsumerWidget {
  const _ItemReader({
    required this.scope,
    required this.item,
    required this.onOpen,
  });

  final NoteLink scope;
  final AiItem item;
  final void Function(Citation citation) onOpen;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final scheme = Theme.of(context).colorScheme;
    final session = ref.read(aiSessionProvider(scope).notifier);
    final answer = AiAnswer.fromJson(item.body);
    final made = DateTime.fromMillisecondsSinceEpoch(item.createdAt);
    return SingleChildScrollView(
      padding: const EdgeInsets.fromLTRB(20, 20, 20, 32),
      child: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 760),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: <Widget>[
              Row(
                children: <Widget>[
                  Icon(Icons.bookmark_rounded, color: scheme.primary),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Text(
                      item.title,
                      style: Theme.of(context).textTheme.titleLarge,
                    ),
                  ),
                  IconButton(
                    icon: const Icon(Icons.drive_file_rename_outline_rounded),
                    tooltip: 'Rename',
                    onPressed: () async {
                      final title = await _askName(context, item.title);
                      if (title != null) {
                        await session.renameItem(item.id, title);
                      }
                    },
                  ),
                  IconButton(
                    icon: const Icon(Icons.close_rounded),
                    tooltip: 'Back to the overview',
                    onPressed: session.newThread,
                  ),
                ],
              ),
              Padding(
                padding: const EdgeInsets.only(left: 34, bottom: 14),
                child: Text(
                  'Made by ${item.provider} · ${item.model}, '
                  '${made.year}-${made.month.toString().padLeft(2, '0')}-${made.day.toString().padLeft(2, '0')}',
                  style: TextStyle(fontSize: 12, color: scheme.outline),
                ),
              ),
              AnswerView(answer: answer, onOpen: onOpen),
            ],
          ),
        ),
      ),
    );
  }
}

/// The line to ask in: what is asked is about the scope, and may search the
/// web where that is set up.
class _Composer extends ConsumerStatefulWidget {
  const _Composer({required this.scope});

  final NoteLink scope;

  @override
  ConsumerState<_Composer> createState() => _ComposerState();
}

class _ComposerState extends ConsumerState<_Composer> {
  final TextEditingController _text = TextEditingController();
  final FocusNode _focus = FocusNode();
  bool? _web;

  @override
  void dispose() {
    _text.dispose();
    _focus.dispose();
    super.dispose();
  }

  bool _webAvailable(AiModel? model, AsyncValue<WebSearch?> search) =>
      model != null &&
      (model.config.kind == ProviderKind.anthropic || search.value != null);

  void _send() {
    final question = _text.text.trim();
    if (question.isEmpty) return;
    final settings = ref.read(aiSettingsProvider);
    final model = ref.read(aiModelProvider).value;
    final web =
        (_web ?? settings.searchWeb) &&
        _webAvailable(model, ref.read(webSearchProvider));
    _text.clear();
    unawaited(
      ref
          .read(aiSessionProvider(widget.scope).notifier)
          .ask(question, searchWeb: web),
    );
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final pending = ref.watch(
      aiSessionProvider(widget.scope).select((s) => s.pending),
    );
    final info = ref.watch(aiScopeInfoProvider(widget.scope)).value;
    final model = ref.watch(aiModelProvider).value;
    final search = ref.watch(webSearchProvider);
    final available = _webAvailable(model, search);
    final web =
        (_web ?? ref.watch(aiSettingsProvider.select((s) => s.searchWeb))) &&
        available;

    return Container(
      padding: const EdgeInsets.fromLTRB(16, 6, 16, 12),
      child: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 800),
          child: Container(
            decoration: BoxDecoration(
              color: scheme.surface,
              borderRadius: BorderRadius.circular(16),
              border: Border.all(color: scheme.outlineVariant),
              boxShadow: const <BoxShadow>[
                BoxShadow(
                  color: Color(0x14000000),
                  blurRadius: 8,
                  offset: Offset(0, 2),
                ),
              ],
            ),
            padding: const EdgeInsets.fromLTRB(14, 4, 6, 6),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: <Widget>[
                CallbackShortcuts(
                  bindings: <ShortcutActivator, VoidCallback>{
                    const SingleActivator(LogicalKeyboardKey.enter): _send,
                  },
                  child: TextField(
                    controller: _text,
                    focusNode: _focus,
                    minLines: 1,
                    maxLines: 8,
                    enabled: model != null,
                    decoration: InputDecoration(
                      border: InputBorder.none,
                      enabledBorder: InputBorder.none,
                      focusedBorder: InputBorder.none,
                      disabledBorder: InputBorder.none,
                      filled: false,
                      hintText: model == null
                          ? 'Choose a model to ask'
                          : 'Ask about ${info == null ? 'this' : '“${info.title}”'}…',
                    ),
                  ),
                ),
                Row(
                  children: <Widget>[
                    Tooltip(
                      message: available
                          ? 'Let this answer search the web. What it finds is cited as the web.'
                          : 'Set up web search in the AI settings',
                      child: FilterChip(
                        avatar: const Icon(Icons.public_rounded, size: 16),
                        label: const Text('Web'),
                        selected: web,
                        visualDensity: VisualDensity.compact,
                        onSelected: available
                            ? (on) => setState(() => _web = on)
                            : null,
                      ),
                    ),
                    const SizedBox(width: 6),
                    const _ModelChip(),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        info == null
                            ? ''
                            : 'Starts from this ${info.kindName}, then all your notes',
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(fontSize: 12, color: scheme.outline),
                      ),
                    ),
                    if (pending != null)
                      IconButton.filledTonal(
                        icon: const Icon(Icons.stop_rounded),
                        tooltip: 'Stop',
                        onPressed: () => unawaited(
                          ref
                              .read(aiSessionProvider(widget.scope).notifier)
                              .stop(),
                        ),
                      )
                    else
                      IconButton.filled(
                        icon: const Icon(Icons.arrow_upward_rounded),
                        tooltip: 'Ask (Enter)',
                        onPressed: model == null ? null : _send,
                      ),
                  ],
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// Who answers, and where the notes go to be answered: opens the settings
/// to choose.
class _ModelChip extends ConsumerWidget {
  const _ModelChip();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final model = ref.watch(aiModelProvider).value;
    final local = model?.config.local ?? true;
    return ConstrainedBox(
      constraints: const BoxConstraints(maxWidth: 260),
      child: ActionChip(
        avatar: Icon(
          local ? Icons.computer_rounded : Icons.cloud_outlined,
          size: 16,
        ),
        label: Text(
          model == null ? 'Choose a model' : model.config.model,
          overflow: TextOverflow.ellipsis,
        ),
        visualDensity: VisualDensity.compact,
        tooltip: model == null
            ? 'Choose which model answers'
            : local
            ? '${model.config.name}: answers come from a model on this computer'
            : 'Questions, and the notes they are about, go to ${model.config.name}',
        onPressed: () => showAiSettings(context),
      ),
    );
  }
}
