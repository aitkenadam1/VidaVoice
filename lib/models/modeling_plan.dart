/// The caregiver's guided first week.
///
/// The single biggest predictor of AAC success is how communication partners
/// use the device — and every competitor review in the blueprint (§1) says
/// onboarding is where the market is weakest. v0.02 shipped these as seven
/// static tips a caregiver could scroll past. Here they become a plan: one
/// habit per day, each with a concrete thing to try before bedtime.
///
/// Content is deliberately static and local. Progress lives per profile in
/// [ModelingPlanService] — no account, no network.
library;

/// One day of the plan: the habit, why it works, and today's task.
class ModelingDay {
  const ModelingDay({
    required this.day,
    required this.title,
    required this.body,
    required this.tryIt,
  });

  /// 1-based day number.
  final int day;

  /// The habit being taught.
  final String title;

  /// Why it works — the same coaching text the tips carried in v0.02.
  final String body;

  /// One concrete action, small enough to finish today.
  final String tryIt;
}

/// The seven-day plan. Order is the teaching order and should not be shuffled:
/// modeling comes before wait time, which comes before not forcing repetition.
class ModelingPlan {
  const ModelingPlan._();

  static const int days = 7;

  static const List<ModelingDay> all = [
    ModelingDay(
      day: 1,
      title: 'Model, don’t quiz',
      body:
          'Use VidaVoice to talk WITH them, not test them. When you hand them '
          'juice, tap “I want juice” yourself. They learn by watching '
          'you use it.',
      tryIt:
          'Pick ONE routine today — snack, bath or bedtime. During it, tap '
          'two or three words on the board yourself. Don’t ask them to tap '
          'anything at all.',
    ),
    ModelingDay(
      day: 2,
      title: 'Follow their lead',
      body:
          'Talk about whatever has their attention right now — not what you '
          'wish they’d notice. If they’re staring at the dog, model '
          '“I see dog”.',
      tryIt:
          'Three times today, notice what they are already looking at and tap a '
          'word about THAT — even if it is the ceiling fan.',
    ),
    ModelingDay(
      day: 3,
      title: 'One step ahead',
      body:
          'If they use one word, you model two. They tap “juice” '
          '— you tap “want juice”. Always just one step beyond '
          'where they are.',
      tryIt:
          'Every time they tap one word today, tap that same word plus one '
          'more. Never more than one extra.',
    ),
    ModelingDay(
      day: 4,
      title: 'Presume competence',
      body:
          'Talk about everything, all day — feelings, jokes, plans — '
          'exactly like you would with any child. Don’t limit topics to '
          'needs and wants.',
      tryIt:
          'Model one word today that is NOT a want or a need — try '
          '“funny”, “my turn”, “uh-oh” or '
          '“silly”. Comment on something instead of asking for it.',
    ),
    ModelingDay(
      day: 5,
      title: 'Give wait time',
      body:
          'After you model, silently count to 10. Processing takes time — '
          'don’t rush to fill the silence or answer for them.',
      tryIt:
          'After each thing you model today, count to 10 in your head before '
          'you say or do anything else. It will feel much longer than it is.',
    ),
    ModelingDay(
      day: 6,
      title: 'Never force repetition',
      body:
          'Don’t demand “say it on the app”. If they don’t '
          'respond, just model the word once more yourself and move on.',
      tryIt:
          'If they don’t respond today, model the word once more and move '
          'on. Notice how it feels not to push — that feeling is the habit '
          'you are building.',
    ),
    ModelingDay(
      day: 7,
      title: 'Keep it within reach, all day',
      body:
          'The voice should be available everywhere — not just at the '
          'therapy table. Communication doesn’t keep office hours.',
      tryIt:
          'Take the device to three places you don’t usually take it — '
          'the car, the kitchen, outside. Leave it within their reach in each.',
    ),
  ];

  static ModelingDay dayNumber(int day) => all[day.clamp(1, days) - 1];
}

/// One profile's progress through the plan. Plain data; persisted as JSON.
class ModelingProgress {
  ModelingProgress({this.startedOn, Set<int>? completedDays})
    : completedDays = completedDays ?? <int>{};

  /// Date the caregiver started, or null if they haven't yet.
  final DateTime? startedOn;

  /// Day numbers marked done. A set, so days can be done out of order —
  /// real weeks are not tidy.
  final Set<int> completedDays;

  bool get started => startedOn != null;
  bool get finished => completedDays.length >= ModelingPlan.days;
  bool isDone(int day) => completedDays.contains(day);

  /// The day the plan suggests today, from the calendar days elapsed.
  ///
  /// Caps at day 7 and never runs backwards. A caregiver who misses days is
  /// not punished for it — the suggestion moves on, the unfinished days stay
  /// available, and nothing is hidden.
  int get suggestedDay {
    if (startedOn == null) return 1;
    final start = DateTime(startedOn!.year, startedOn!.month, startedOn!.day);
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    final elapsed = today.difference(start).inDays;
    return (elapsed + 1).clamp(1, ModelingPlan.days);
  }

  Map<String, dynamic> toJson() => {
    'startedOn': startedOn?.toIso8601String(),
    'completedDays': completedDays.toList()..sort(),
  };

  factory ModelingProgress.fromJson(Map<String, dynamic> json) {
    final raw = json['startedOn'] as String?;
    return ModelingProgress(
      startedOn: raw == null ? null : DateTime.tryParse(raw),
      completedDays: {
        for (final d in (json['completedDays'] as List? ?? []))
          (d as num).toInt(),
      },
    );
  }
}
