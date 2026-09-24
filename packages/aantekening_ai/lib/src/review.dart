/// When to see a flashcard again: spaced repetition, as Anki and SuperMemo
/// do it, so each card comes back just before it would be forgotten.
library;

import 'dart:math' as math;

/// How well a card was remembered.
enum Grade {
  /// Not at all: it is learnt again, from the start.
  again('Again'),

  /// With effort.
  hard('Hard'),

  /// As it should be.
  good('Good'),

  /// Without a thought.
  easy('Easy');

  const Grade(this.label);

  final String label;
}

/// What is known of how a card is learnt, and when it is next due.
class CardReview {
  const CardReview({
    required this.due,
    this.interval = Duration.zero,
    this.ease = startingEase,
    this.reviews = 0,
    this.lapses = 0,
    this.learning = true,
  });

  /// A card not yet studied: due now.
  factory CardReview.fresh(DateTime now) => CardReview(due: now);

  /// How much longer each gap is than the last, for a card remembered
  /// well; it falls as a card is found hard and rises as it is found easy.
  static const double startingEase = 2.5;
  static const double _minEase = 1.3;

  /// The gaps of a card being learnt, before it is only reviewed.
  static const List<Duration> _steps = <Duration>[
    Duration(minutes: 1),
    Duration(minutes: 10),
  ];

  /// When it is next to be seen.
  final DateTime due;

  /// The gap between its last two showings, for a card being reviewed.
  final Duration interval;
  final double ease;
  final int reviews;

  /// How often it was forgotten once learnt.
  final int lapses;

  /// Whether it is still being learnt, in steps of minutes, rather than
  /// reviewed in steps of days.
  final bool learning;

  /// Whether it has been studied at all.
  bool get isNew => reviews == 0;

  bool isDue(DateTime now) => !due.isAfter(now);

  /// Whether it is learnt well enough to last a few weeks.
  bool get isMature => !learning && interval >= const Duration(days: 21);

  /// Its state after it was remembered as [grade] at [now].
  CardReview after(Grade grade, DateTime now) {
    final gap = next(grade);
    // A new card remembered goes on to the next step; one past it is
    // learnt, and reviewed in days from then on.
    final stillLearning = learning
        ? grade == Grade.again ||
              grade == Grade.hard ||
              (grade == Grade.good && reviews == 0)
        : grade == Grade.again;
    return CardReview(
      due: now.add(gap),
      interval: stillLearning ? interval : gap,
      ease: switch (grade) {
        Grade.again when !learning => math.max(_minEase, ease - 0.2),
        Grade.hard when !learning => math.max(_minEase, ease - 0.15),
        Grade.easy => ease + 0.15,
        _ => ease,
      },
      reviews: reviews + 1,
      lapses: lapses + (grade == Grade.again && !learning ? 1 : 0),
      learning: stillLearning,
    );
  }

  /// How long until it is seen again, if it is remembered as [grade] now.
  Duration next(Grade grade) {
    if (learning) {
      return switch (grade) {
        Grade.again => _steps.first,
        Grade.hard => _steps.last,
        // Out of learning: a day, or four for a card that was easy.
        Grade.good => reviews == 0 ? _steps.last : const Duration(days: 1),
        Grade.easy => const Duration(days: 4),
      };
    }
    final days = math.max(1, interval.inHours / 24);
    return switch (grade) {
      Grade.again => _steps.last,
      Grade.hard => Duration(hours: (days * 1.2 * 24).round()),
      Grade.good => Duration(hours: (days * ease * 24).round()),
      Grade.easy => Duration(hours: (days * ease * 1.3 * 24).round()),
    };
  }

  Map<String, Object?> toJson() => <String, Object?>{
    'due': due.millisecondsSinceEpoch,
    'interval': interval.inMinutes,
    'ease': ease,
    'reviews': reviews,
    'lapses': lapses,
    'learning': learning,
  };

  static CardReview fromJson(Map<String, Object?> json) => CardReview(
    due: DateTime.fromMillisecondsSinceEpoch(json['due'] as int? ?? 0),
    interval: Duration(minutes: json['interval'] as int? ?? 0),
    ease: (json['ease'] as num?)?.toDouble() ?? startingEase,
    reviews: json['reviews'] as int? ?? 0,
    lapses: json['lapses'] as int? ?? 0,
    learning: json['learning'] as bool? ?? true,
  );
}

/// [gap] as a person says it: "1 min", "10 min", "4 days", "2 mo".
String describeGap(Duration gap) {
  if (gap < const Duration(hours: 1)) {
    return '${math.max(1, gap.inMinutes)} min';
  }
  if (gap < const Duration(days: 1)) return '${gap.inHours} h';
  final days = (gap.inHours / 24).round();
  if (days < 30) return '$days ${days == 1 ? 'day' : 'days'}';
  if (days < 365) return '${(days / 30).round()} mo';
  return '${(days / 365).toStringAsFixed(1)} y';
}
