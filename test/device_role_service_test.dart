import 'package:flutter_test/flutter_test.dart';
import 'package:onevoz/services/device_role_service.dart';
import 'package:onevoz/services/elevenlabs_key_store.dart';

/// In-memory stand-in for the platform keychain.
class _FakeSecureStore implements SecureValueStore {
  final map = <String, String>{};

  @override
  Future<String?> read(String key) async => map[key];

  @override
  Future<void> write(String key, String value) async => map[key] = value;

  @override
  Future<void> delete(String key) async => map.remove(key);
}

void main() {
  group('DeviceRoleService', () {
    test('reads null before any role is chosen', () async {
      final svc = DeviceRoleService(store: _FakeSecureStore());
      expect(await svc.readRole(), isNull);
    });

    test('write then read round-trips both roles', () async {
      final svc = DeviceRoleService(store: _FakeSecureStore());
      await svc.writeRole(DeviceRole.communicator);
      expect(await svc.readRole(), DeviceRole.communicator);
      await svc.writeRole(DeviceRole.caregiver);
      expect(await svc.readRole(), DeviceRole.caregiver);
    });

    test('unrecognized stored value reads as null (ask again)', () async {
      final store = _FakeSecureStore();
      store.map[DeviceRoleService.storageKey] = 'admin';
      final svc = DeviceRoleService(store: store);
      expect(await svc.readRole(), isNull);
    });

    test('clearRole forgets the choice', () async {
      final svc = DeviceRoleService(store: _FakeSecureStore());
      await svc.writeRole(DeviceRole.caregiver);
      await svc.clearRole();
      expect(await svc.readRole(), isNull);
    });
  });
}
