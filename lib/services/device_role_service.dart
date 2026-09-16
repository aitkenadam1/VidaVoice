import 'elevenlabs_key_store.dart';

/// Which side of the family this device serves.
///
/// * [communicator] — the person using the AAC boards (e.g. the child's
///   iPad). Boards only: the Caregiver Portal does not exist on this
///   device — no routes, no entry points, no affordances in the child UI.
/// * [caregiver] — the adult managing the family. Opens the dedicated
///   Caregiver Portal (profiles, devices, safe zones, alerts, controls).
///
/// The role is per-device (not per-account) and lives in the platform
/// keychain/keystore, never in SharedPreferences. Switching roles
/// requires the OneVoz account password, verified live — see
/// [ModeSwitchGate]. Unknown stored values read back as null (ask again)
/// rather than guessing.
enum DeviceRole { communicator, caregiver }

/// Persists the device role in secure storage.
class DeviceRoleService {
  DeviceRoleService({SecureValueStore? store})
    : _store = store ?? PlatformSecureValueStore();

  static const storageKey = 'onevoz.device.role';

  final SecureValueStore _store;

  /// The stored role, or null when the device has never chosen (first
  /// launch) or the stored value is unrecognized.
  Future<DeviceRole?> readRole() async {
    final raw = await _store.read(storageKey);
    return switch (raw) {
      'communicator' => DeviceRole.communicator,
      'caregiver' => DeviceRole.caregiver,
      _ => null,
    };
  }

  Future<void> writeRole(DeviceRole role) async {
    await _store.write(
      storageKey,
      role == DeviceRole.communicator ? 'communicator' : 'caregiver',
    );
  }

  /// Clears the role (e.g. on sign-out, so the next account chooses fresh).
  Future<void> clearRole() async => _store.delete(storageKey);
}
