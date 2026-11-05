part of 'ai_view.dart';

/// The questions of a conversation and their answers, and the one being
/// answered — which alone is built again as it comes.
class _Conversation extends ConsumerWidget {
  const _Conversation({
    required this.scope,
    required this.scroll,
    required this.onOpen,
  });

  final NoteLink scope;
  final ScrollController scroll;
  final void Function(Citation citation) onOpen;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final session = ref.read(aiSessionProvider(scope).notifier);
    final (:turns, :items, :answering) = ref.watch(
      aiSessionProvider(scope).select(
        (s) => (turns: s.turns, items: s.items, answering: s.pending != null),
      ),
    );
    return ListView(
      controller: scroll,
      padding: const EdgeInsets.fromLTRB(0, 8, 0, 12),
      children: <Widget>[
        for (final turn in turns)
          _Exchange(
            question: turn.question,
            answer: AiAnswer.fromJson(turn.answer),
            byline: <String>[
              turn.provider,
              turn.model,
              if (AiSession.tookOf(turn) case final took?) wholeSeconds(took),
              ?costNote(AiSession.costOf(turn.usage)),
            ].join(' · '),
            onOpen: onOpen,
            kept: items.any((item) => item.turnId == turn.id),
            onKeep: () => unawaited(session.keep(turn)),
            onAddCards: (cards) => unawaited(session.addCards(cards)),
            // One thing at a time: not while another is being answered.
            onRewrite: answering
                ? null
                : (section) =>
                      unawaited(_rewrite(context, ref, session, turn, section)),
          ),
        if (answering) _Answering(scope: scope, onOpen: onOpen),
      ],
    );
  }
}

/// The question being answered, as far as its answer has got.
class _Answering extends ConsumerWidget {
  const _Answering({required this.scope, required this.onOpen});

  final NoteLink scope;
  final void Function(Citation citation) onOpen;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final (:pending, :threadId) = ref.watch(
      aiSessionProvider(scope)
          .select((s) => (pending: s.pending, threadId: s.threadId)),
    );
    // In the conversation it was asked in, not another opened meanwhile.
    if (pending == null || (threadId != null && threadId != pending.threadId)) {
      return const SizedBox.shrink();
    }
    return _Exchange(
      question: pending.question,
      answer: pending.answer,
      pending: pending,
      onOpen: onOpen,
    );
  }
}

/// Asks how [section] of the answer to [turn] should be written again,
/// then has it written so.
Future<void> _rewrite(
  BuildContext context,
  WidgetRef ref,
  AiSession session,
  AiTurn turn,
  AnswerSection section,
) async {
  final part = AiAnswer.fromJson(turn.answer).textOf(section);
  final instruction = await _askHowToRewrite(context, part);
  if (instruction == null) return;
  await session.rewrite(
    turn,
    section,
    instruction: instruction,
    searchWeb: searchesWeb(ref, session.scope),
  );
}

/// Shows [part] and asks what should be different when it is written
/// again: the words given, empty for nothing in particular, or null to
/// leave it as it is.
Future<String?> _askHowToRewrite(BuildContext context, String part) =>
    showAppDialog<String>(
      context: context,
      builder: (context) => _RewriteDialog(part: part),
    );

/// The dialog behind [_askHowToRewrite].
class _RewriteDialog extends StatefulWidget {
  const _RewriteDialog({required this.part});

  final String part;

  @override
  State<_RewriteDialog> createState() => _RewriteDialogState();
}

class _RewriteDialogState extends State<_RewriteDialog> {
  final TextEditingController _how = TextEditingController();

  @override
  void dispose() {
    _how.dispose();
    super.dispose();
  }

  void _write() => Navigator.of(context).pop(_how.text.trim());

  @override
  Widget build(BuildContext context) {
    final tones = context.tones;
    return GlassDialog(
      title: const Text('Write this again'),
      content: SizedBox(
        width: 460,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: <Widget>[
            ConstrainedBox(
              constraints: const BoxConstraints(maxHeight: 180),
              child: Container(
                padding: const EdgeInsets.fromLTRB(10, 6, 10, 6),
                decoration: BoxDecoration(
                  border: Border(
                    left: BorderSide(color: tones.strongLine, width: 3),
                  ),
                ),
                child: SingleChildScrollView(
                  child: Text(
                    widget.part,
                    style: TextStyle(fontSize: 12.5, color: tones.muted),
                  ),
                ),
              ),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: _how,
              autofocus: true,
              minLines: 1,
              maxLines: 4,
              textInputAction: TextInputAction.done,
              decoration: const InputDecoration(
                hintText: 'What should be different? (optional)',
                helperText: 'Simpler, with an example, shorter, in German, …',
              ),
              onSubmitted: (_) => _write(),
            ),
          ],
        ),
      ),
      actions: <Widget>[
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('Cancel'),
        ),
        FilledButton(onPressed: _write, child: const Text('Write again')),
      ],
    );
  }
}

/// A question, set off to the right in the accent's tint, and its answer
/// beneath it.
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
    this.onRewrite,
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

  /// Has a section of the answer written again.
  final ValueChanged<AnswerSection>? onRewrite;

  @override
  Widget build(BuildContext context) {
    final tones = context.tones;
    final done = byline != null;
    return Padding(
      padding: const EdgeInsets.fromLTRB(14, 6, 14, 8),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: <Widget>[
          Align(
            alignment: Alignment.centerRight,
            child: FractionallySizedBox(
              widthFactor: 0.85,
              alignment: Alignment.centerRight,
              child: Align(
                alignment: Alignment.centerRight,
                child: Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 12,
                    vertical: 8,
                  ),
                  decoration: BoxDecoration(
                    color: tones.lift,
                    // The corner it comes from, as a speech bubble's.
                    borderRadius: const BorderRadius.only(
                      topLeft: Radius.circular(Corners.panel),
                      topRight: Radius.circular(Corners.panel),
                      bottomLeft: Radius.circular(Corners.panel),
                      bottomRight: Radius.circular(Corners.small),
                    ),
                  ),
                  child: SelectableText(question),
                ),
              ),
            ),
          ),
          const SizedBox(height: 8),
          if (pending != null) AnswerProgress(pending: pending!),
          if (!answer.isEmpty)
            AnswerView(
              answer: answer,
              onOpen: onOpen,
              showSources: done,
              onAddCards: onAddCards,
              onRewrite: done ? onRewrite : null,
            ),
          if (done)
            Row(
              children: <Widget>[
                Expanded(
                  child: Text(
                    byline!,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(fontSize: 11, color: tones.faint),
                  ),
                ),
                SmallButton(
                  'Copy',
                  tooltip: 'Copy the answer',
                  onPressed: () =>
                      Clipboard.setData(ClipboardData(text: answer.plainText)),
                ),
                SmallButton(
                  kept ? 'Kept' : 'Keep',
                  tooltip: kept
                      ? 'Kept, with the answers kept'
                      : 'Keep the answer, with the answers kept',
                  onPressed: kept ? null : onKeep,
                ),
              ],
            ),
        ],
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
    final tones = context.tones;
    final session = ref.read(aiSessionProvider(scope).notifier);
    final answer = AiAnswer.fromJson(item.body);
    return SingleChildScrollView(
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 20),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: <Widget>[
          Row(
            children: <Widget>[
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: <Widget>[
                    SmallCaps('Kept answer', color: tones.emphasis),
                    const SizedBox(height: 2),
                    Text(
                      item.title,
                      style: Theme.of(context).textTheme.titleMedium,
                    ),
                  ],
                ),
              ),
              SmallButton(
                'Rename',
                onPressed: () async {
                  final title = await askName(context, item.title);
                  if (title != null) await session.renameItem(item.id, title);
                },
              ),
            ],
          ),
          Padding(
            padding: const EdgeInsets.only(top: 2, bottom: 10),
            child: Text(
              'Made by ${item.provider} · ${item.model}, '
              '${whenOf(item.createdAt)}',
              style: TextStyle(fontSize: 11.5, color: tones.muted),
            ),
          ),
          AnswerView(answer: answer, onOpen: onOpen),
        ],
      ),
    );
  }
}
