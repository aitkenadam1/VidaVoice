import 'package:flutter_test/flutter_test.dart';
import 'package:onevoz/models/safe_zone.dart';

SafeZone _zone({
  String id = 'zone_abcdef0123456789abcdef0123456789',
  String name = 'Home',
  double lat = 40.123,
  double lng = -111.456,
  double radiusM = 300,
  bool enabled = true,
  bool notifyEnter = true,
  bool notifyExit = true,
  DateTime? updatedTs,
}) =>
    SafeZone(
      id: id,
      name: name,
      lat: lat,
      lng: lng,
      radiusM: radiusM,
      enabled: enabled,
      notifyEnter: notifyEnter,
      notifyExit: notifyExit,
      updatedTs: updatedTs ?? DateTime.fromMillisecondsSinceEpoch(1000),
    );

void main() {
  group('SafeZone.newId', () {
    test('generates opaque zone_<uuid> ids', () {
      final a = SafeZone.newId();
      final b = SafeZone.newId();
      expect(a, startsWith('zone_'));
      expect(b, startsWith('zone_'));
      expect(a, isNot(equals(b)));
      // The generated id must pass the model's own validation.
      expect(_zone(id: a).validate(), isEmpty);
    });
  });

  group('SafeZone.validate', () {
    test('accepts a well-formed zone', () {
      expect(_zone().validate(), isEmpty);
      expect(_zone().isValid, isTrue);
    });

    test('rejects an empty name', () {
      final problems = _zone(name: '   ').validate();
      expect(problems, isNotEmpty);
      expect(problems.join(' '), contains('name'));
    });

    test('rejects a name over 60 characters', () {
      final problems = _zone(name: 'x' * 61).validate();
      expect(problems.join(' '), contains('60'));
    });

    test('rejects out-of-range coordinates', () {
      expect(_zone(lat: 91).validate(), isNotEmpty);
      expect(_zone(lat: -91).validate(), isNotEmpty);
      expect(_zone(lng: 181).validate(), isNotEmpty);
      expect(_zone(lng: -181).validate(), isNotEmpty);
      expect(_zone(lat: 90, lng: -180).validate(), isEmpty);
    });

    test('rejects a radius outside 50 m – 2 km', () {
      expect(_zone(radiusM: 49).validate(), isNotEmpty);
      expect(_zone(radiusM: 2001).validate(), isNotEmpty);
      expect(_zone(radiusM: 50).validate(), isEmpty);
      expect(_zone(radiusM: 2000).validate(), isEmpty);
      expect(_zone(radiusM: 300).validate(), isEmpty);
    });

    test('rejects a malformed id', () {
      expect(_zone(id: 'home-1').validate(), isNotEmpty);
      expect(_zone(id: '').validate(), isNotEmpty);
    });
  });

  group('SafeZone serialization', () {
    test('round-trips through toJson/fromJson', () {
      final zone = _zone();
      final restored = SafeZone.fromJson(zone.toJson());
      expect(restored, equals(zone));
    });

    test('fromJson throws FormatException on invalid data', () {
      expect(
        () => SafeZone.fromJson({..._zone().toJson(), 'name': ''}),
        throwsFormatException,
      );
      expect(
        () => SafeZone.fromJson({..._zone().toJson(), 'lat': 999}),
        throwsFormatException,
      );
      expect(
        () => SafeZone.fromJson({'id': 'nope'}),
        throwsFormatException,
      );
    });

    test('fromJson skips nothing silently: notify flags default true', () {
      final json = _zone().toJson()
        ..remove('notify_enter')
        ..remove('notify_exit');
      final restored = SafeZone.fromJson(json);
      expect(restored.notifyEnter, isTrue);
      expect(restored.notifyExit, isTrue);
    });
  });

  group('SafeZone.copyWith and equality', () {
    test('copyWith replaces only the given fields', () {
      final zone = _zone();
      final renamed = zone.copyWith(name: 'School');
      expect(renamed.name, 'School');
      expect(renamed.lat, zone.lat);
      expect(renamed.id, zone.id);
    });

    test('equality is by value', () {
      expect(_zone(), equals(_zone()));
      expect(_zone(name: 'A'), isNot(equals(_zone(name: 'B'))));
      expect(_zone().hashCode, equals(_zone().hashCode));
    });
  });

  group('SafeZone.merge', () {
    SafeZone atZone(String id, String name, int tsMs) =>
    
        _zone(id: id, name: name, updatedTs: DateTime.fromMillisecondsSinceEpoch(tsMs));

    test('keeps the newest updated_ts per id', () {
      final local = [atZone('zone_a', 'Home-old', 1000)];
      final remote = [atZone('zone_a', 'Home-new', 2000)];
      final merged = SafeZone.merge(local, remote);
      expect(merged, hasLength(1));
      expect(merged.single.name, 'Home-new');
    });

    test('keeps the local version when it is newer', () {
      final local = [atZone('zone_a', 'Home-local', 3000)];
      final remote = [atZone('zone_a', 'Home-remote', 2000)];
      final merged = SafeZone.merge(local, remote);
      expect(merged.single.name, 'Home-local');
    });

    test('unions zones that exist on only one side', () {
      final local = [atZone('zone_a', 'Home', 1000)];
      final remote = [atZone('zone_b', 'School', 1000)];
      final merged = SafeZone.merge(local, remote);
      expect(merged.map((z) => z.id), containsAll(['zone_a', 'zone_b']));
    });

    test('a zone missing remotely is kept (no tombstones in P1)', () {
      final local = [atZone('zone_a', 'Home', 1000)];
      final merged = SafeZone.merge(local, const []);
      expect(merged, hasLength(1));
    });

    test('ties go to remote so devices converge deterministically', () {
      final local = [atZone('zone_a', 'Home-local', 1000)];
      final remote = [atZone('zone_a', 'Home-remote', 1000)];
      final merged = SafeZone.merge(local, remote);
      expect(merged.single.name, 'Home-remote');
    });

    test('result is sorted by name', () {
      final merged = SafeZone.merge(
        [atZone('zone_b', 'Zoo', 1000)],
        [atZone('zone_a', 'Home', 1000)],
      );
      expect(merged.map((z) => z.name).toList(), ['Home', 'Zoo']);
    });
  });
}
