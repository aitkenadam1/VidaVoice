/// Phase 1 calling & safety: device location.
///
/// Phase 1 ships with [NoopLocationService] only. The calling & safety UI
/// codes against this abstraction so that Phase 2 can plug a real GPS
/// implementation in here without touching any screen or widget:
///
/// - `{gps}` placeholders resolve to null until then. Callers degrade
///   honestly: phrase cards show "location unavailable", and
///   [composeEmergencySms] omits the GPS line from the SMS entirely
///   (see lib/models/calling_safety.dart).
/// - Nothing in this file touches platform channels, so widget tests stay
///   hermetic.
abstract class LocationService {
  /// Current coordinates as a human-readable string (e.g. "40.7128,-74.0060"),
  /// or null when location is unavailable / not yet implemented.
  Future<String?> currentCoords();
}

/// Phase 1 implementation: always reports "unavailable".
///
/// The UI must never claim a location it does not have — every consumer
/// treats a null return as "location unavailable" and says so out loud.
class NoopLocationService implements LocationService {
  const NoopLocationService();

  @override
  Future<String?> currentCoords() async => null;
}
