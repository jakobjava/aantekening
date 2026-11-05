part of 'ai_session.dart';

/// The study sets of an [AiSession]: made from the notes alongside
/// anything else, kept, and their flashcards added to and edited.
mixin _StudySets on _AiSessionCore {
  /// What makes each set being made, by the id of its profile.
  final Map<String, StreamSubscription<AgentProgress>> _makers =
      <String, StreamSubscription<AgentProgress>>{};

  /// Shows kept thing [id].
  void openItem(String id);

  /// Shows the study set of profile [id]: as it is being made, as it was
  /// kept, or, not made yet, what it would be and a way to make it.
  void openProfile(String id) {
    final item = state.setOf(id);
    if (item != null && !state.making.containsKey(id)) {
      openItem(item.id);
      return;
    }
    state = state.copyWith(
      itemId: () => null,
      threadId: () => null,
      turns: const <AiTurn>[],
      shownProfile: () => id,
      shownPodcast: () => null,
    );
  }

  /// Makes a study set as [profile] describes it from the notes of the
  /// scope, shown as it is written, and keeps it — in place of the one made
  /// before, what was learnt of its cards carried over. Made alongside
  /// anything else going on; its page shows it coming, and anything else
  /// can be looked at meanwhile.
  Future<void> make(StudyProfile profile) async {
    final id = profile.id;
    if (state.making.containsKey(id)) {
      openProfile(id);
      return;
    }
    final starting = 'set $id';
    if (!_starting.add(starting)) return;
    final _Ready? ready;
    try {
      ready = await _ready('Choose a model first.');
    } finally {
      _starting.remove(starting);
    }
    if (ready == null) return;
    final (:model, :reader, :info) = ready;
    void write(PendingTurn? pending) => _setMaking(id, pending);
    write(
      PendingTurn(
        question: profile.name,
        local: model.config.local,
        profile: profile,
      ),
    );
    state = state.copyWith(
      itemId: () => null,
      threadId: () => null,
      turns: const <AiTurn>[],
      shownProfile: () => id,
      shownPodcast: () => null,
      error: () => null,
    );
    StreamSubscription<AgentProgress>? making;
    await _follow(
      holdingProvider(
        model.provider,
        _agent(model, reader).make(profile, scope: info),
      ),
      read: () => state.making[id],
      write: write,
      started: (subscription) => _makers[id] = making = subscription,
      onDone: (progress) async {
        if (progress.study case final set?) {
          await _keepSet(
            set,
            profile: profile,
            provider: model.config.name,
            model: model.config.model,
            usage: _usageOf(progress),
          );
        }
      },
    );
    // Another may have been started once this one was kept.
    if (identical(_makers[id], making)) _makers.remove(id);
  }

  /// Stops making the set of profile [id], keeping the one made before, if
  /// any.
  Future<void> stopMaking(String id) async {
    _setMaking(id, null);
    await _makers.remove(id)?.cancel();
  }

  /// Keeps how far making the set of profile [id] has got, or with null
  /// that it is no longer being made.
  void _setMaking(String id, PendingTurn? pending) => state = state.copyWith(
    making: <String, PendingTurn>{
      for (final entry in state.making.entries)
        if (entry.key != id) entry.key: entry.value,
      id: ?pending,
    },
  );

  /// Keeps [set] as the scope's set of [profile], and shows it if its page
  /// is showing.
  Future<void> _keepSet(
    StudySet set, {
    required StudyProfile profile,
    required String provider,
    required String model,
    Map<String, Object?>? usage,
  }) async {
    final store = await _store;
    final earlier = state.setOf(profile.id);
    var kept = set;
    if (earlier == null) {
      final item = await store.ai.addItem(
        scope,
        kind: profile.id,
        title: profile.name,
        body: set.toJson(),
        provider: provider,
        model: model,
        usage: usage,
      );
      await _shown(profile.id, item.id);
      return;
    }
    if ((set, earlier.studySet) case (
      final FlashcardSet made,
      final FlashcardSet before,
    )) {
      final cards = made.keepingIdsOf(before);
      kept = cards;
      await store.ai.forgetReviews(
        earlier.id,
        keep: <String>{for (final card in cards.cards) card.id},
      );
    }
    await store.ai.updateItem(
      earlier.id,
      body: kept.toJson(),
      title: profile.name,
      usage: usage,
    );
    ref.invalidate(cardReviewsProvider(earlier.id));
    await _shown(profile.id, earlier.id);
  }

  /// Once the set of profile [id] is kept as [itemId]: shown in place of
  /// its page, if that is showing.
  Future<void> _shown(String id, String itemId) async {
    _setMaking(id, null);
    await _load();
    if (state.shownProfile == id) {
      state = state.copyWith(itemId: () => itemId, shownProfile: () => null);
    }
  }

  /// Adds [cards] — from an answer, say — to the scope's flashcards.
  Future<void> addCards(List<StudyCard> cards) async {
    final model = await ref.read(aiModelProvider.future);
    final profile = ref
        .read(aiSettingsProvider)
        .studyProfiles
        .firstWhere((profile) => profile.id == StudyKind.flashcards.name);
    final earlier = state.setOf(profile.id);
    final before = earlier?.studySet;
    final set = FlashcardSet(cards);
    if (earlier == null || before is! FlashcardSet) {
      await _keepSet(
        set,
        profile: profile,
        provider: model?.config.name ?? '',
        model: model?.config.model ?? '',
      );
      return;
    }
    final store = await _store;
    await store.ai.updateItem(earlier.id, body: set.addedTo(before).toJson());
    await _load();
  }

  /// Keeps [set] as what kept thing [id] holds: a card edited or taken out.
  Future<void> updateSet(String id, StudySet set) async {
    final store = await _store;
    await store.ai.updateItem(id, body: set.toJson());
    if (set is FlashcardSet) {
      await store.ai.forgetReviews(
        id,
        keep: <String>{for (final card in set.cards) card.id},
      );
      ref.invalidate(cardReviewsProvider(id));
    }
    await _load();
  }
}

/// How each card of kept set [itemId] is learnt, and grading them.
class CardReviews extends AsyncNotifier<Map<String, CardReview>> {
  CardReviews(this.itemId);

  final String itemId;

  @override
  Future<Map<String, CardReview>> build() async {
    final store = await ref.watch(storeProvider.future);
    return <String, CardReview>{
      for (final entry in (await store.ai.reviewsOf(itemId)).entries)
        entry.key: CardReview.fromJson(entry.value),
    };
  }

  /// How card [cardId] is learnt now: as it was, or new.
  CardReview of(String cardId, DateTime now) =>
      state.value?[cardId] ?? CardReview.fresh(now);

  /// Keeps that card [cardId] was remembered as [grade] at [now], and
  /// returns what it comes to.
  Future<CardReview> grade(String cardId, Grade grade, DateTime now) async {
    final next = of(cardId, now).after(grade, now);
    state = AsyncData(<String, CardReview>{...?state.value, cardId: next});
    final store = await ref.read(storeProvider.future);
    await store.ai.saveReview(
      itemId,
      cardId,
      state: next.toJson(),
      dueAt: next.due.millisecondsSinceEpoch,
    );
    return next;
  }
}

final cardReviewsProvider =
    AsyncNotifierProvider.family<CardReviews, Map<String, CardReview>, String>(
      CardReviews.new,
    );

/// How many cards not yet studied a session brings in, besides those due.
const int newCardsPerSession = 20;

/// How many of kept set [item]'s cards a session would study now — those
/// due, and new ones up to [newCardsPerSession] — or 0 for a set that is
/// not flashcards.
int cardsToStudy(WidgetRef ref, AiItem? item) {
  final set = item?.studySet;
  if (item == null || set is! FlashcardSet) return 0;
  final status = deckStatus(
    set.cards,
    ref.watch(cardReviewsProvider(item.id)).value ??
        const <String, CardReview>{},
    DateTime.now(),
  );
  return status.due + status.fresh.clamp(0, newCardsPerSession);
}

/// How far along [cards] are, by [reviews], at [now].
({int due, int fresh, int learnt}) deckStatus(
  List<StudyCard> cards,
  Map<String, CardReview> reviews,
  DateTime now,
) {
  var due = 0;
  var fresh = 0;
  var learnt = 0;
  for (final card in cards) {
    final review = reviews[card.id];
    if (review == null) {
      fresh++;
    } else if (review.isDue(now)) {
      due++;
    } else if (!review.learning) {
      learnt++;
    }
  }
  return (due: due, fresh: fresh, learnt: learnt);
}
