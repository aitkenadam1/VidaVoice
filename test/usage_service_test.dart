import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:voicesimple/services/usage_service.dart';

/// Unit tests for tap counting + local persistence.
/// Run from the project root: `flutter test`.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() {
    SharedPreferences.setMockInitialValues({});
  });

  test('recordTap counts taps per word id', () async {
    final usage = UsageService();
    await usage.load();

    await usage.recordTap('core.want');
    await usage.recordTap('core.want');
    await usage.recordTap('core.go');

    expect(usage.countFor('core.want'), 2);
    expect(usage.countFor('core.go'), 1);
    expect(usage.countFor('core.never'), 0);
    expect(usage.totalTaps, 3);
  });

  test('top() returns most-tapped first, capped at n', () async {
    final usage = UsageService();
    await usage.load();

    await usage.recordTap('core.go');
    await usage.recordTap('core.want');
    await usage.recordTap('core.want');
    await usage.recordTap('core.want');

    final top2 = usage.top(2);
    expect(top2.length, 2);
    expect(top2[0].key, 'core.want');
    expect(top2[0].value, 3);
    expect(top2[1].key, 'core.go');
  });

  test('counts persist across service instances', () async {
    final usage = UsageService();
    await usage.load();
    await usage.recordTap('core.want');
    await usage.recordTap('core.want');

    final reloaded = UsageService();
    await reloaded.load();
    expect(reloaded.countFor('core.want'), 2);
  });

  test('clear resets all counts', () async {
    final usage = UsageService();
    await usage.load();
    await usage.recordTap('core.want');
    await usage.clear();

    expect(usage.countFor('core.want'), 0);
    expect(usage.totalTaps, 0);
    expect(usage.top(10), isEmpty);

    final reloaded = UsageService();
    await reloaded.load();
    expect(reloaded.totalTaps, 0);
  });

  test('corrupt storage loads as zero counts instead of throwing', () async {
    SharedPreferences.setMockInitialValues({
      'vidavoice.usageCounts.v1': 'not-json{{{',
    });
    final usage = UsageService();
    await usage.load(); // must not throw — the app has to boot regardless
    expect(usage.totalTaps, 0);
  });
}
