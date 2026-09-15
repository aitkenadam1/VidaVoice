import 'dart:convert';

import 'package:shared_preferences/shared_preferences.dart';

/// One day of the guided first-week plan.
class PlanDay {
  const PlanDay({
    required this.day,
    required this.title,
    required this.body,
    required this.tryIt,
  });

  /// 1..7
  final int day;
  final String title;
  final String body;

  /// Concrete practice prompt for the caregiver, for that day.
  final String tryIt;
}

/// The 7-day guided modeling plan: the same research-backed habits as the
/// static tips list, each paired with one concrete thing to try that day.
/// Order is intentional — each day builds on the last.
const List<PlanDay> firstWeekPlan = [
  PlanDay(
    day: 1,
    title: 'Model, don\u2019t quiz',
    body: 'Use OneVoz to talk WITH them, not test them. They learn by '
        'watching you use it — not by being quizzed on it.',
    tryIt: 'At the next meal, tap \u201cI want\u201d + a food on the app yourself '
        'before handing anything over. Do it 3 times today. Don\u2019t ask them '
        'to tap anything at all \u2014 today is for watching.',
  ),
  PlanDay(
    day: 2,
    title: 'Follow their lead',
    body: 'Talk about whatever has their attention right now — not what you '
        'wish they\u2019d notice. Attention is where learning happens.',
    tryIt: 'Watch what they look at for 2 minutes. Model 5 words about '
        'exactly that thing on the app \u2014 even if it\u2019s the ceiling fan.',
  ),
  PlanDay(
    day: 3,
    title: 'One step ahead',
    body: 'If they use one word, you model two. Always just one step beyond '
        'where they are — never a whole sentence ahead.',
    tryIt: 'Every time they tap one word today, you add one more. They tap '
        '\u201cjuice\u201d \u2014 you tap \u201cwant juice\u201d.',
  ),
  PlanDay(
    day: 4,
    title: 'Presume competence',
    body: 'Talk about everything, all day — feelings, jokes, plans — exactly '
        'like you would with any child. Don\u2019t limit topics to needs and wants.',
    tryIt: 'Model one word today that is NOT a want or a need \u2014 try '
        '\u201cfunny\u201d, \u201cmy turn\u201d, \u201cuh-oh\u201d or \u201csilly\u201d. '
        'Comment on something instead of asking for it.',
  ),
  PlanDay(
    day: 5,
    title: 'Give wait time',
    body: 'After you model, silently count to 10. Processing takes time — '
        'don\u2019t rush to fill the silence or answer for them.',
    tryIt: 'After every model today, count silently to 10 before saying '
        'anything else. Practice it 5 times. It will feel much longer '
        'than it is.',
  ),
  PlanDay(
    day: 6,
    title: 'Never force repetition',
    body: 'Don\u2019t demand \u201csay it on the app\u201d. If they don\u2019t respond, '
        'just model the word once more yourself and move on.',
    tryIt: 'If they don\u2019t respond to a model today, smile, model once '
        'more yourself, and move on. Notice how it feels.',
  ),
  PlanDay(
    day: 7,
    title: 'Keep it within reach, all day',
    body: 'The voice should be available everywhere — not just at the therapy '
        'table. Communication doesn\u2019t keep office hours.',
    tryIt: 'Carry the device everywhere today \u2014 car, park, store. Model '
        'at least once in 3 different places.',
  ),
];

/// Per-profile completion of the first-week plan, stored locally.
///
/// Keyed by profile id so each communicator tracks their own week.
class FirstWeekPlanService {
  static String _key(String profileId) =>
      'vidavoice.firstWeekPlan.$profileId.v1';

  final Map<String, Set<int>> _doneByProfile = {};

  /// Days (1..7) marked done for [profileId].
  Set<int> doneDays(String profileId) =>
      Set.unmodifiable(_doneByProfile[profileId] ?? const <int>{});

  int completedCount(String profileId) => doneDays(profileId).length;

  Future<void> load(String profileId) async {
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getString(_key(profileId));
    final done = <int>{};
    if (raw != null) {
      for (final entry in json.decode(raw) as List) {
        final day = (entry as num).toInt();
        if (day >= 1 && day <= 7) done.add(day);
      }
    }
    _doneByProfile[profileId] = done;
  }

  Future<void> setDone(String profileId, int day, bool done) async {
    if (day < 1 || day > 7) return;
    final set = _doneByProfile.putIfAbsent(profileId, () => <int>{});
    if (done) {
      set.add(day);
    } else {
      set.remove(day);
    }
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_key(profileId), json.encode(set.toList()));
  }

  Future<void> reset(String profileId) async {
    _doneByProfile[profileId] = <int>{};
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(_key(profileId));
  }
}
