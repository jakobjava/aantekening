/// How the cards of a kept set of flashcards are learnt: graded, due and
/// new, kept apart from the set itself.
library;

import 'package:aantekening_ai/aantekening_ai.dart';
import 'package:aantekening_store/aantekening_store.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../providers.dart';
import 'ai_session.dart' show KeptItem;

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
