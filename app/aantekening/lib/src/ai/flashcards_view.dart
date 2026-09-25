/// Learning flashcards: a card at a time, turned over to check, graded by
/// how well it was remembered, and shown again when it is about to be
/// forgotten — and every card of the set, to look through and correct.
library;

import 'dart:async';
import 'dart:math' as math;

import 'package:aantekening_ai/aantekening_ai.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../look/controls.dart';
import '../look/marks.dart';
import '../look/tones.dart';
import 'ai_session.dart';
import 'math_text.dart';
import 'sources_view.dart';

/// The flashcards of kept set [itemId]: studied, or all of them looked at.
class FlashcardsView extends ConsumerStatefulWidget {
  const FlashcardsView({
    required this.itemId,
    required this.set,
    required this.onOpen,
    required this.onChanged,
    super.key,
  });

  final String itemId;
  final FlashcardSet set;
  final void Function(Citation citation) onOpen;

  /// Keeps the set as changed: a card corrected or taken out.
  final ValueChanged<FlashcardSet> onChanged;

  @override
  ConsumerState<FlashcardsView> createState() => _FlashcardsViewState();
}

enum _Mode { study, browse }

class _FlashcardsViewState extends ConsumerState<FlashcardsView> {
  _Mode _mode = _Mode.study;

  /// Changes each time a session starts over, so it starts afresh.
  int _session = 0;

  @override
  Widget build(BuildContext context) {
    final tones = context.tones;
    final reviews =
        ref.watch(cardReviewsProvider(widget.itemId)).value ??
        const <String, CardReview>{};
    final status = deckStatus(widget.set.cards, reviews, DateTime.now());

    return Column(
      children: <Widget>[
        Padding(
          padding: const EdgeInsets.fromLTRB(24, 0, 24, 10),
          child: Row(
            children: <Widget>[
              ChoiceRow<_Mode>(
                choices: _Mode.values,
                selected: _mode,
                labelOf: (mode) => switch (mode) {
                  _Mode.study => 'Study',
                  _Mode.browse => 'All cards',
                },
                onSelected: (mode) => setState(() {
                  _mode = mode;
                  _session++;
                }),
              ),
              const SizedBox(width: 14),
              Expanded(
                child: Text.rich(
                  TextSpan(
                    children: <InlineSpan>[
                      TextSpan(
                        text: '${status.due} due',
                        style: TextStyle(
                          fontWeight: status.due > 0 ? FontWeight.w700 : null,
                          color: status.due > 0 ? tones.emphasis : null,
                        ),
                      ),
                      TextSpan(
                        text:
                            '  ·  ${status.fresh} new  ·  '
                            '${status.learnt} learnt',
                      ),
                    ],
                  ),
                  textAlign: TextAlign.end,
                  style: TextStyle(fontSize: 12.5, color: tones.muted),
                ),
              ),
            ],
          ),
        ),
        Expanded(
          child: _mode == _Mode.study
              ? _Session(
                  key: ValueKey<int>(_session),
                  itemId: widget.itemId,
                  cards: widget.set.cards,
                  onOpen: widget.onOpen,
                  onBrowse: () => setState(() => _mode = _Mode.browse),
                  onRestart: () => setState(() => _session++),
                )
              : CardList(
                  cards: widget.set.cards,
                  reviews: reviews,
                  onOpen: widget.onOpen,
                  onEdit: (card) => widget.onChanged(
                    FlashcardSet(<StudyCard>[
                      for (final c in widget.set.cards)
                        c.id == card.id ? card : c,
                    ]),
                  ),
                  onDelete: (card) => widget.onChanged(
                    FlashcardSet(<StudyCard>[
                      for (final c in widget.set.cards)
                        if (c.id != card.id) c,
                    ]),
                  ),
                ),
        ),
      ],
    );
  }
}

// ----------------------------------------------------------------- session

/// A session of study: the cards due, then new ones, each shown, turned
/// over and graded; a card forgotten comes back before the end.
class _Session extends ConsumerStatefulWidget {
  const _Session({
    required this.itemId,
    required this.cards,
    required this.onOpen,
    required this.onBrowse,
    required this.onRestart,
    super.key,
  });

  final String itemId;
  final List<StudyCard> cards;
  final void Function(Citation citation) onOpen;
  final VoidCallback onBrowse;
  final VoidCallback onRestart;

  @override
  ConsumerState<_Session> createState() => _SessionState();
}

class _SessionState extends ConsumerState<_Session> {
  final FocusNode _focus = FocusNode(debugLabel: 'flashcards');

  /// The cards still to show, the one showing first; null until the
  /// reviews are read.
  List<StudyCard>? _queue;

  /// How many different cards the session holds, and how many are done.
  int _total = 0;
  final Set<String> _done = <String>{};
  final Map<Grade, int> _grades = <Grade, int>{};
  bool _turned = false;

  /// Whether the session goes through every card, due or not, without
  /// changing when they are due.
  bool _practice = false;

  @override
  void initState() {
    super.initState();
    unawaited(_start());
  }

  @override
  void dispose() {
    _focus.dispose();
    super.dispose();
  }

  Future<void> _start({bool practice = false}) async {
    final reviews = await ref.read(cardReviewsProvider(widget.itemId).future);
    final now = DateTime.now();
    final due = <StudyCard>[];
    final fresh = <StudyCard>[];
    for (final card in widget.cards) {
      final review = reviews[card.id];
      if (review == null) {
        fresh.add(card);
      } else if (practice || review.isDue(now)) {
        due.add(card);
      }
    }
    due.sort(
      (a, b) =>
          (reviews[a.id]?.due ?? now).compareTo(reviews[b.id]?.due ?? now),
    );
    if (!mounted) return;
    setState(() {
      _practice = practice;
      _queue = practice
          ? (<StudyCard>[...widget.cards]..shuffle(math.Random()))
          : <StudyCard>[...due, ...fresh.take(newCardsPerSession)];
      _total = _queue!.length;
      _done.clear();
      _grades.clear();
      _turned = false;
    });
    _focus.requestFocus();
  }

  void _turn() {
    if (_queue?.isNotEmpty ?? false) setState(() => _turned = !_turned);
  }

  Future<void> _grade(Grade grade) async {
    final queue = _queue;
    if (queue == null || queue.isEmpty || !_turned) return;
    final card = queue.first;
    if (!_practice) {
      await ref
          .read(cardReviewsProvider(widget.itemId).notifier)
          .grade(card.id, grade, DateTime.now());
    }
    if (!mounted) return;
    setState(() {
      queue.removeAt(0);
      _grades[grade] = (_grades[grade] ?? 0) + 1;
      // Forgotten: seen again later in the session.
      if (grade == Grade.again) {
        queue.insert(math.min(queue.length, 3), card);
      } else {
        _done.add(card.id);
      }
      _turned = false;
    });
  }

  KeyEventResult _key(FocusNode node, KeyEvent event) {
    if (event is! KeyDownEvent) return KeyEventResult.ignored;
    final key = event.logicalKey;
    if (key == LogicalKeyboardKey.space || key == LogicalKeyboardKey.enter) {
      _turn();
      return KeyEventResult.handled;
    }
    final grade = switch (key) {
      LogicalKeyboardKey.digit1 || LogicalKeyboardKey.numpad1 => Grade.again,
      LogicalKeyboardKey.digit2 || LogicalKeyboardKey.numpad2 => Grade.hard,
      LogicalKeyboardKey.digit3 || LogicalKeyboardKey.numpad3 => Grade.good,
      LogicalKeyboardKey.digit4 || LogicalKeyboardKey.numpad4 => Grade.easy,
      _ => null,
    };
    if (grade == null || !_turned) return KeyEventResult.ignored;
    unawaited(_grade(grade));
    return KeyEventResult.handled;
  }

  @override
  Widget build(BuildContext context) {
    final queue = _queue;
    if (queue == null) return const Loading();
    if (_total == 0) {
      return _Finished(
        itemId: widget.itemId,
        cards: widget.cards,
        grades: const <Grade, int>{},
        onPractice: () => unawaited(_start(practice: true)),
        onBrowse: widget.onBrowse,
      );
    }
    if (queue.isEmpty) {
      return _Finished(
        itemId: widget.itemId,
        cards: widget.cards,
        grades: _grades,
        practised: _practice,
        onPractice: () => unawaited(_start(practice: true)),
        onBrowse: widget.onBrowse,
        onAgain: widget.onRestart,
      );
    }
    final card = queue.first;
    final tones = context.tones;
    final review = ref
        .read(cardReviewsProvider(widget.itemId).notifier)
        .of(card.id, DateTime.now());

    return Focus(
      focusNode: _focus,
      autofocus: true,
      onKeyEvent: _key,
      child: LayoutBuilder(
        builder: (context, constraints) => SingleChildScrollView(
          padding: const EdgeInsets.fromLTRB(24, 8, 24, 24),
          child: ConstrainedBox(
            constraints: BoxConstraints(minHeight: constraints.maxHeight - 32),
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: <Widget>[
                ConstrainedBox(
                  constraints: const BoxConstraints(maxWidth: 640),
                  child: Column(
                    children: <Widget>[
                      Row(
                        children: <Widget>[
                          Text(
                            _practice
                                ? 'Practice — due dates stay as they are'
                                : '${_done.length} of $_total',
                            style: TextStyle(
                              fontSize: 12.5,
                              color: tones.muted,
                            ),
                          ),
                          const Spacer(),
                          if (review.isNew)
                            const SmallCaps('New')
                          else if (review.learning)
                            const SmallCaps('Learning'),
                        ],
                      ),
                      const SizedBox(height: 8),
                      LinearProgressIndicator(value: _done.length / _total),
                      const SizedBox(height: 18),
                      GestureDetector(
                        onTap: () {
                          _focus.requestFocus();
                          _turn();
                        },
                        child: MouseRegion(
                          cursor: SystemMouseCursors.click,
                          child: FlipCard(
                            turned: _turned,
                            front: CardFace(
                              label: 'Question',
                              text: card.front,
                              hint: 'Click, or press Space, to turn it over',
                            ),
                            back: CardFace(
                              label: 'Answer',
                              text: card.back,
                              above: card.front,
                              footer: SourceLine(
                                sources: card.sources,
                                onOpen: widget.onOpen,
                              ),
                            ),
                          ),
                        ),
                      ),
                      const SizedBox(height: 20),
                      AnimatedSwitcher(
                        duration: const Duration(milliseconds: 180),
                        child: _turned
                            ? _GradeButtons(
                                key: const ValueKey<bool>(true),
                                review: review,
                                onGrade: (grade) => unawaited(_grade(grade)),
                              )
                            : Tooltip(
                                key: const ValueKey<bool>(false),
                                message: 'Space or Enter',
                                child: OutlinedButton(
                                  style: OutlinedButton.styleFrom(
                                    minimumSize: const Size(220, 40),
                                  ),
                                  onPressed: _turn,
                                  child: const Text('Show answer'),
                                ),
                              ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// A card showing its [front], or its [back] once [turned] over.
class FlipCard extends StatelessWidget {
  const FlipCard({
    required this.turned,
    required this.front,
    required this.back,
    super.key,
  });

  final bool turned;
  final Widget front;
  final Widget back;

  @override
  Widget build(BuildContext context) => AnimatedSwitcher(
    duration: const Duration(milliseconds: 120),
    child: KeyedSubtree(
      key: ValueKey<bool>(turned),
      child: turned ? back : front,
    ),
  );
}

/// One side of a card, as an index card is: what it is, the text large in
/// the middle, and what goes under it.
class CardFace extends StatelessWidget {
  const CardFace({
    required this.label,
    required this.text,
    this.above,
    this.hint,
    this.footer,
    super.key,
  });

  final String label;
  final String text;

  /// The question, small, over the answer on the back.
  final String? above;
  final String? hint;
  final Widget? footer;

  @override
  Widget build(BuildContext context) {
    final tones = context.tones;
    return Container(
      width: double.infinity,
      constraints: const BoxConstraints(minHeight: 300),
      decoration: BoxDecoration(
        color: tones.base,
        border: Border.all(color: tones.strongLine),
      ),
      padding: const EdgeInsets.fromLTRB(28, 18, 28, 20),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: <Widget>[
          SmallCaps(label),
          if (above != null) ...<Widget>[
            const SizedBox(height: 8),
            MathText(
              above!,
              style: TextStyle(fontSize: 14, color: tones.muted),
            ),
            const SizedBox(height: 12),
            const Divider(),
          ],
          ConstrainedBox(
            constraints: BoxConstraints(minHeight: above == null ? 190 : 130),
            child: Center(
              child: Padding(
                padding: const EdgeInsets.symmetric(vertical: 18),
                child: MathText(
                  text,
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    fontSize: 21,
                    height: 1.45,
                    fontWeight: FontWeight.w600,
                    color: tones.text,
                  ),
                ),
              ),
            ),
          ),
          ?footer,
          if (hint != null)
            Text(
              hint!,
              textAlign: TextAlign.center,
              style: TextStyle(fontSize: 12, color: tones.faint),
            ),
        ],
      ),
    );
  }
}

/// How well it was remembered: four buttons, each with its key and when
/// the card comes back.
class _GradeButtons extends StatelessWidget {
  const _GradeButtons({required this.review, required this.onGrade, super.key});

  final CardReview review;
  final ValueChanged<Grade> onGrade;

  @override
  Widget build(BuildContext context) => Row(
    children: <Widget>[
      for (final (index, grade) in Grade.values.indexed)
        Expanded(
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 4),
            child: _GradeButton(
              grade: grade,
              shortcut: '${index + 1}',
              gap: describeGap(review.next(grade)),
              onPressed: () => onGrade(grade),
            ),
          ),
        ),
    ],
  );
}

class _GradeButton extends StatelessWidget {
  const _GradeButton({
    required this.grade,
    required this.shortcut,
    required this.gap,
    required this.onPressed,
  });

  final Grade grade;

  /// The key that grades it.
  final String shortcut;
  final String gap;
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    final tones = context.tones;
    return Tooltip(
      message: 'Key $shortcut',
      child: OutlinedButton(
        onPressed: onPressed,
        style: OutlinedButton.styleFrom(
          padding: const EdgeInsets.symmetric(vertical: 10),
        ),
        child: Column(
          children: <Widget>[
            Row(
              mainAxisSize: MainAxisSize.min,
              children: <Widget>[
                KeyHint(shortcut),
                const SizedBox(width: 6),
                Text(
                  grade.label,
                  style: const TextStyle(fontWeight: FontWeight.w600),
                ),
              ],
            ),
            const SizedBox(height: 2),
            Text(gap, style: TextStyle(fontSize: 11.5, color: tones.muted)),
          ],
        ),
      ),
    );
  }
}

/// The end of a session, or nothing due: how it went, when the next cards
/// are due, and what else to do.
class _Finished extends ConsumerWidget {
  const _Finished({
    required this.itemId,
    required this.cards,
    required this.grades,
    required this.onPractice,
    required this.onBrowse,
    this.practised = false,
    this.onAgain,
  });

  final String itemId;
  final List<StudyCard> cards;
  final Map<Grade, int> grades;
  final bool practised;
  final VoidCallback onPractice;
  final VoidCallback onBrowse;
  final VoidCallback? onAgain;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final tones = context.tones;
    final reviews =
        ref.watch(cardReviewsProvider(itemId)).value ??
        const <String, CardReview>{};
    final now = DateTime.now();
    final next = <DateTime>[
      for (final card in cards)
        if (reviews[card.id] case final review? when !review.isDue(now))
          review.due,
    ]..sort();
    final studied = grades.isNotEmpty;
    return Center(
      child: SingleChildScrollView(
        padding: const EdgeInsets.all(24),
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 460),
          child: Column(
            children: <Widget>[
              Text(
                studied
                    ? (practised ? 'Practice done' : 'Session done')
                    : 'All caught up',
                style: theme.textTheme.headlineSmall,
              ),
              const SizedBox(height: 8),
              Text(
                next.isEmpty
                    ? 'No card is waiting.'
                    : 'The next card is due in '
                          '${describeGap(next.first.difference(now))}.',
                textAlign: TextAlign.center,
                style: TextStyle(color: tones.muted),
              ),
              if (studied) ...<Widget>[
                const SizedBox(height: 18),
                Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: <Widget>[
                    for (final grade in Grade.values)
                      Padding(
                        padding: const EdgeInsets.symmetric(horizontal: 10),
                        child: Column(
                          children: <Widget>[
                            Text(
                              '${grades[grade] ?? 0}',
                              style: const TextStyle(
                                fontSize: 22,
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                            Text(
                              grade.label,
                              style: TextStyle(
                                fontSize: 12,
                                color: tones.muted,
                              ),
                            ),
                          ],
                        ),
                      ),
                  ],
                ),
              ],
              const SizedBox(height: 22),
              Wrap(
                spacing: 10,
                runSpacing: 10,
                alignment: WrapAlignment.center,
                children: <Widget>[
                  if (onAgain != null && !practised)
                    FilledButton(
                      onPressed: onAgain,
                      child: const Text('Study what is due'),
                    ),
                  OutlinedButton(
                    onPressed: onPractice,
                    child: const Text('Practise all cards'),
                  ),
                  OutlinedButton(
                    onPressed: onBrowse,
                    child: const Text('See all cards'),
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

// -------------------------------------------------------------------- list

/// Every card of a set, as small cards: its question, its answer, where it
/// comes from, and when it is due — each to correct or take out.
class CardList extends StatelessWidget {
  const CardList({
    required this.cards,
    required this.onOpen,
    this.reviews = const <String, CardReview>{},
    this.onEdit,
    this.onDelete,
    this.scrolls = true,
    super.key,
  });

  /// Whether it scrolls itself, rather than lying in something that does.
  final bool scrolls;

  final List<StudyCard> cards;
  final Map<String, CardReview> reviews;
  final void Function(Citation citation) onOpen;
  final ValueChanged<StudyCard>? onEdit;
  final ValueChanged<StudyCard>? onDelete;

  @override
  Widget build(BuildContext context) => LayoutBuilder(
    builder: (context, constraints) {
      final columns = constraints.maxWidth > 900 ? 2 : 1;
      final width = math.min(
        (constraints.maxWidth - 48 - 14 * (columns - 1)) / columns,
        520.0,
      );
      final list = Padding(
        padding: const EdgeInsets.fromLTRB(24, 8, 24, 28),
        child: Center(
          child: Wrap(
            spacing: 14,
            runSpacing: 14,
            children: <Widget>[
              for (final (i, card) in cards.indexed)
                SizedBox(
                  width: width,
                  child: _SmallCard(
                    number: i + 1,
                    card: card,
                    review: reviews[card.id],
                    onOpen: onOpen,
                    onEdit: onEdit == null
                        ? null
                        : () async {
                            final edited = await _editCard(context, card);
                            if (edited != null) onEdit!(edited);
                          },
                    onDelete: onDelete == null ? null : () => onDelete!(card),
                  ),
                ),
            ],
          ),
        ),
      );
      return scrolls ? SingleChildScrollView(child: list) : list;
    },
  );
}

class _SmallCard extends StatelessWidget {
  const _SmallCard({
    required this.number,
    required this.card,
    required this.review,
    required this.onOpen,
    this.onEdit,
    this.onDelete,
  });

  final int number;
  final StudyCard card;
  final CardReview? review;
  final void Function(Citation citation) onOpen;
  final VoidCallback? onEdit;
  final VoidCallback? onDelete;

  @override
  Widget build(BuildContext context) {
    final tones = context.tones;
    final now = DateTime.now();
    final review = this.review;
    final (tag, due) = switch (review) {
      null => ('New', false),
      _ when review.isDue(now) => ('Due', true),
      _ when review.learning => ('Learning', false),
      _ => ('In ${describeGap(review.due.difference(now))}', false),
    };
    return Container(
      decoration: BoxDecoration(
        color: tones.base,
        border: Border.all(color: tones.line),
      ),
      padding: const EdgeInsets.fromLTRB(16, 10, 6, 12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: <Widget>[
          Row(
            children: <Widget>[
              Text(
                '$number',
                style: TextStyle(
                  fontSize: 12,
                  fontWeight: FontWeight.w700,
                  color: tones.muted,
                ),
              ),
              const SizedBox(width: 10),
              SmallCaps(tag, color: due ? tones.emphasis : null),
              const Spacer(),
              if (onEdit != null || onDelete != null)
                MenuAnchor(
                  menuChildren: <Widget>[
                    if (onEdit != null)
                      MenuItemButton(
                        onPressed: onEdit,
                        child: const Text('Correct'),
                      ),
                    if (onDelete != null)
                      MenuItemButton(
                        onPressed: onDelete,
                        child: const Text('Take out'),
                      ),
                  ],
                  builder: (context, controller, _) => MarkButton(
                    MarkShape.more,
                    tooltip: 'More',
                    onPressed: () => controller.isOpen
                        ? controller.close()
                        : controller.open(),
                  ),
                ),
            ],
          ),
          const SizedBox(height: 6),
          Padding(
            padding: const EdgeInsets.only(right: 10),
            child: MathText(
              card.front,
              style: const TextStyle(
                fontSize: 15,
                height: 1.4,
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
          const SizedBox(height: 6),
          Padding(
            padding: const EdgeInsets.only(right: 10),
            child: MathText(
              card.back,
              style: TextStyle(fontSize: 14, height: 1.45, color: tones.muted),
            ),
          ),
          if (card.sources.isNotEmpty) ...<Widget>[
            const SizedBox(height: 10),
            Padding(
              padding: const EdgeInsets.only(right: 10),
              child: SourceLine(sources: card.sources, onOpen: onOpen),
            ),
          ],
        ],
      ),
    );
  }
}

/// Asks for [card] corrected: its question and its answer.
Future<StudyCard?> _editCard(BuildContext context, StudyCard card) {
  final front = TextEditingController(text: card.front);
  final back = TextEditingController(text: card.back);
  return showDialog<StudyCard>(
    context: context,
    builder: (context) => AlertDialog(
      title: const Text('Correct the card'),
      content: SizedBox(
        width: 480,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: <Widget>[
            TextField(
              controller: front,
              autofocus: true,
              minLines: 1,
              maxLines: 4,
              decoration: const InputDecoration(labelText: 'Question'),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: back,
              minLines: 1,
              maxLines: 6,
              decoration: const InputDecoration(labelText: 'Answer'),
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
          onPressed: () => Navigator.of(context).pop(
            card.copyWith(front: front.text.trim(), back: back.text.trim()),
          ),
          child: const Text('Save'),
        ),
      ],
    ),
  ).whenComplete(() {
    front.dispose();
    back.dispose();
  });
}
