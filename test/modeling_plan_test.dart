import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:vidavoice/models/modeling_plan.dart';

/// The caregiver's first-week plan is the app's onboarding differentiator
/// (blueprint §1: "nobody owns onboarding"). These pin the content shape and
/// the day-advance logic, which is the only part with real behaviour.
void main() {
  group('plan content', () {
    test('is exactly seven days, numbered 1..7 in order', () {
      expect(ModelingPlan.all.length, ModelingPlan.days);
      expect(
        ModelingPlan.all.map((d) => d.day).toList(),
        [1, 2, 3, 4, 5, 6, 7],
      );
    });

    test('every day has a habit, a reason, and something to try', () {
      for (final day in ModelingPlan.all) {
        expect(day.title.trim(), isNotEmpty, reason: 'day ${day.day}');
        expect(day.body.trim(), isNotEmpty, reason: 'day ${day.day}');
        expect(
          day.tryIt.trim(),
          isNotEmpty,
          reason: 'day ${day.day} has no "try it today" prompt',
        );
      }
    });

    test('dayNumber clamps instead of throwing', () {
      expect(ModelingPlan.dayNumber(1).day, 1);
      expect(ModelingPlan.dayNumber(7).day, 7);
      expect(ModelingPlan.dayNumber(0).day, 1);
      expect(ModelingPlan.dayNumber(99).day, 7);
    });
  });

  group('progress', () {
    test('starts unstarted, on day 1, with nothing done', () {
      final progress = ModelingProgress();
      expect(progress.started, isFalse);
      expect(progress.finished, isFalse);
      expect(progress.suggestedDay, 1);
      expect(progress.completedDays, isEmpty);
    });

    test('suggested day follows the calendar and caps at day 7', () {
      ModelingProgress startedDaysAgo(int days) => ModelingProgress(
        startedOn: DateTime.now().subtract(Duration(days: days)),
      );
      expect(startedDaysAgo(0).suggestedDay, 1);
      expect(startedDaysAgo(1).suggestedDay, 2);
      expect(startedDaysAgo(6).suggestedDay, 7);
      // A caregiver who comes back after a fortnight lands on day 7, not day 15.
      expect(startedDaysAgo(14).suggestedDay, 7);
      expect(startedDaysAgo(400).suggestedDay, 7);
    });

    test('days can be completed out of order', () {
      final progress = ModelingProgress(completedDays: {3, 1});
      expect(progress.isDone(1), isTrue);
      expect(progress.isDone(2), isFalse);
      expect(progress.isDone(3), isTrue);
      expect(progress.finished, isFalse);
    });

    test('finished only once every day is ticked', () {
      expect(ModelingProgress(completedDays: {1, 2, 3, 4, 5, 6}).finished,
          isFalse);
      expect(
        ModelingProgress(completedDays: {1, 2, 3, 4, 5, 6, 7}).finished,
        isTrue,
      );
    });

    test('survives a JSON round trip', () {
      final started = DateTime(2026, 9, 14, 8, 30);
      final original = ModelingProgress(
        startedOn: started,
        completedDays: {1, 2, 5},
      );
      final restored = ModelingProgress.fromJson(
        Map<String, dynamic>.from(
          json.decode(json.encode(original.toJson())) as Map,
        ),
      );
      expect(restored.startedOn, started);
      expect(restored.completedDays, {1, 2, 5});
      expect(restored.started, isTrue);
    });

    test('a malformed stored record degrades instead of throwing', () {
      final restored = ModelingProgress.fromJson({
        'startedOn': 'not-a-date',
        'completedDays': null,
      });
      expect(restored.startedOn, isNull);
      expect(restored.started, isFalse);
      expect(restored.completedDays, isEmpty);
      expect(restored.suggestedDay, 1);
    });
  });
}
