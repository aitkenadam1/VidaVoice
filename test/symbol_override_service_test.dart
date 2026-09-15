import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:voicesimple/services/symbol_override_service.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  SymbolOverrideService fresh() =>
      SymbolOverrideService(prefsFactory: SharedPreferences.getInstance);

  test('set/get/remove round trip', () async {
    SharedPreferences.setMockInitialValues({});
    final svc = fresh();
    await svc.load();
    expect(svc.imageFor('p1', 'w_eat'), isNull);
    expect(svc.has('p1', 'w_eat'), isFalse);

    await svc.set('p1', 'w_eat', 'base64data');
    expect(svc.imageFor('p1', 'w_eat'), 'base64data');
    expect(svc.has('p1', 'w_eat'), isTrue);
    expect(svc.countFor('p1'), 1);

    // Other profiles and other words are unaffected.
    expect(svc.imageFor('p2', 'w_eat'), isNull);
    expect(svc.imageFor('p1', 'w_drink'), isNull);

    await svc.remove('p1', 'w_eat');
    expect(svc.imageFor('p1', 'w_eat'), isNull);
    expect(svc.countFor('p1'), 0);
  });

  test('overrides survive a reload', () async {
    SharedPreferences.setMockInitialValues({});
    final first = fresh();
    await first.load();
    await first.set('p1', 'w_eat', 'img1');
    await first.set('p1', 'w_drink', 'img2');

    final second = fresh();
    await second.load();
    expect(second.imageFor('p1', 'w_eat'), 'img1');
    expect(second.imageFor('p1', 'w_drink'), 'img2');
    expect(second.countFor('p1'), 2);
  });

  test('corrupt storage blob starts empty instead of failing', () async {
    SharedPreferences.setMockInitialValues({
      SymbolOverrideService.storageKey: 'not-json{{{',
    });
    final svc = fresh();
    await svc.load();
    expect(svc.countFor('p1'), 0);
    // Still usable afterwards.
    await svc.set('p1', 'w_eat', 'img1');
    expect(svc.imageFor('p1', 'w_eat'), 'img1');
  });

  test('wrong-typed entries in the blob are skipped', () async {
    SharedPreferences.setMockInitialValues({
      SymbolOverrideService.storageKey:
          '{"p1": {"w_eat": "img1", "bad": 42, "": "empty-key"}, "p2": [1,2]}',
    });
    final svc = fresh();
    await svc.load();
    expect(svc.imageFor('p1', 'w_eat'), 'img1');
    expect(svc.has('p1', 'bad'), isFalse);
    expect(svc.countFor('p2'), 0);
  });
}
