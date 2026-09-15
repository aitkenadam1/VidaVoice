import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:onevoz/services/usage_service.dart';

/// Unit tests for the daily activity aggregation (taps today, words today,
/// day streak, top words this week). The clock is injectable so day
/// boundaries are deterministic.
/// Run from the project root: `flutter test`.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  DateTime day(int y, int m, int d, [int h = 12]) => DateTime(y, m, d, h);

  group('daily buckets', () {
    test('tapsToday and wordsToday count only today', () async {
      // Two services sharing one mock store, each with its own clock.
      SharedPreferences.setMockInitialValues({});
      final yesterday = UsageService(clock: () => day(2026, 9, 13, 18));
      await yesterday.load();
      await yesterday.recordTap('core.want');
      await yesterday.recordTap('core.go');
      await yesterday.recordTap('core.want'); // yesterday: want x2, go x1

      final today = UsageService(clock: () => day(2026, 9, 14, 9));
      await today.load();
      await today.recordTap('core.go'); // today: go x1

      expect(today.tapsToday(), 1);
      expect(today.wordsToday(), 1);
      expect(today.countFor('core.want'), 2); // lifetime still accumulates
      expect(today.totalTaps, 4);
    });

    test('tapStreak counts consecutive tap days', () async {
      SharedPreferences.setMockInitialValues({});
      Future<UsageService> tapOn(DateTime when, List<String> ids) async {
        final u = UsageService(clock: () => when);
        await u.load();
        for (final id in ids) {
          await u.recordTap(id);
        }
        return u;
      }

      await tapOn(day(2026, 9, 12, 9), ['core.want']);
      await tapOn(day(2026, 9, 13, 9), ['core.want']);
      final u = await tapOn(day(2026, 9, 14, 9), ['core.want']);
      expect(u.tapStreak(), 3);
    });

    test('tapStreak survives a quiet today', () async {
      SharedPreferences.setMockInitialValues({});
      Future<UsageService> tapOn(DateTime when, List<String> ids) async {
        final u = UsageService(clock: () => when);
        await u.load();
        for (final id in ids) {
          await u.recordTap(id);
        }
        return u;
      }

      await tapOn(day(2026, 9, 13, 9), ['core.want']);
      final u = UsageService(clock: () => day(2026, 9, 14, 9));
      await u.load(); // no taps today
      expect(u.tapsToday(), 0);
      expect(u.tapStreak(), 1);
    });

    test('tapStreak breaks on a missed day', () async {
      SharedPreferences.setMockInitialValues({});
      Future<UsageService> tapOn(DateTime when, List<String> ids) async {
        final u = UsageService(clock: () => when);
        await u.load();
        for (final id in ids) {
          await u.recordTap(id);
        }
        return u;
      }

      await tapOn(day(2026, 9, 12, 9), ['core.want']);
      // 9/13: nothing.
      final u = await tapOn(day(2026, 9, 14, 9), ['core.want']);
      expect(u.tapStreak(), 1);
    });

    test('topSinceDays only counts the last 7 days', () async {
      SharedPreferences.setMockInitialValues({});
      Future<UsageService> tapOn(DateTime when, String id, int times) async {
        final u = UsageService(clock: () => when);
        await u.load();
        for (var i = 0; i < times; i++) {
          await u.recordTap(id);
        }
        return u;
      }

      // 10 days ago: heavy taps, must not leak into the weekly view.
      await tapOn(day(2026, 9, 4, 9), 'core.old', 20);
      await tapOn(day(2026, 9, 13, 9), 'core.want', 3);
      final u = await tapOn(day(2026, 9, 14, 9), 'core.go', 2);

      final top = u.topSinceDays(7, 5);
      expect(top.map((e) => e.key), ['core.want', 'core.go']);
      expect(top.first.value, 3);
      // Lifetime still knows about the old word.
      expect(u.countFor('core.old'), 20);
    });

    test('day buckets persist across instances', () async {
      SharedPreferences.setMockInitialValues({});
      final u1 = UsageService(clock: () => day(2026, 9, 14, 9));
      await u1.load();
      await u1.recordTap('core.want');

      final u2 = UsageService(clock: () => day(2026, 9, 14, 10));
      await u2.load();
      expect(u2.tapsToday(), 1);
      expect(u2.wordsToday(), 1);
    });

    test('old day buckets are pruned on load', () async {
      SharedPreferences.setMockInitialValues({});
      final old = UsageService(clock: () => day(2026, 1, 1, 9));
      await old.load();
      await old.recordTap('core.want');

      final now = UsageService(clock: () => day(2026, 9, 14, 9));
      await now.load();
      // January is beyond the 60-day retention: not in the weekly view…
      expect(now.topSinceDays(7, 5), isEmpty);
      // …but the lifetime count is untouched (pruning only drops day detail).
      expect(now.countFor('core.want'), 1);
    });

    test('corrupt day blob loads as zero activity instead of throwing',
        () async {
      SharedPreferences.setMockInitialValues({
        'vidavoice.usageDays.v1': 'not-json{{{',
      });
      final usage = UsageService(clock: () => day(2026, 9, 14, 9));
      await usage.load(); // must not throw
      expect(usage.tapsToday(), 0);
      expect(usage.tapStreak(), 0);
    });
  });
}
