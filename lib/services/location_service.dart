import 'dart:async';

import 'package:geolocator/geolocator.dart';

/// Phase 1 calling & safety: device location.
///
/// The calling & safety UI codes against the [LocationService] abstraction
/// so that the GPS implementation can be swapped without touching any
/// screen or widget:
///
/// - `{gps}` placeholders resolve to null until then. Callers degrade
///   honestly: phrase cards show "location unavailable", and
///   [composeEmergencySms] omits the GPS line from the SMS entirely
///   (see lib/models/calling_safety.dart).
/// - Nothing in the [NoopLocationService] path touches platform channels,
///   so widget tests stay hermetic. [GpsLocationService] takes an
///   injectable [PositionProvider] so unit tests can drive it without
///   touching geolocator's platform channels.
abstract class LocationService {
  const LocationService();

  /// Current coordinates as a human-readable string (e.g. "40.7128,-74.0060"),
  /// or null when location is unavailable / not yet implemented.
  Future<String?> currentCoords() async =>
      (await currentFix())?.coordsString;

  /// The full GPS fix (coordinates, accuracy, timestamp), or null when
  /// location is unavailable. Never throws — failures resolve to null.
  Future<GpsFix?> currentFix();

  /// Whether location is currently obtainable (permission granted and
  /// services on). Never throws: any failure reads as "no".
  ///
  /// The base implementation probes with a real fix — honest on every
  /// platform and cheap enough at 2A cadences. Used by the caregiver UI
  /// to explain *why* location is unavailable instead of showing a dead
  /// control.
  Future<bool> get hasPermission async {
    try {
      return await currentFix() != null;
    } catch (_) {
      return false;
    }
  }
}

/// A single GPS fix: coordinates plus the platform-reported accuracy radius
/// in meters. Accuracy lets the UI show an honesty radius on the caregiver
/// map instead of pretending the pin is exact.
class GpsFix {
  const GpsFix({
    required this.latitude,
    required this.longitude,
    required this.accuracyMeters,
    required this.timestamp,
  });

  final double latitude;
  final double longitude;
  final double accuracyMeters;
  final DateTime timestamp;

  /// "lat,lon" with 6 decimal places (~10cm) — the wire format used in
  /// `{gps}` placeholder resolution and the emergency SMS.
  String get coordsString =>
      '${latitude.toStringAsFixed(6)},${longitude.toStringAsFixed(6)}';
}

/// Injected for tests: resolves one GPS fix or throws on any failure
/// (denied permission, disabled service, timeout, platform error).
typedef PositionProvider = Future<GpsFix?> Function({
  required Duration timeLimit,
});

/// Phase 2A implementation: real GPS via geolocator.
///
/// HONESTY CONTRACT: this class NEVER throws out of [currentCoords] /
/// [currentFix]. Any failure — permission denied, location services off,
/// timeout, platform error — resolves to null, and every consumer treats
/// null as "location unavailable" and says so out loud. The emergency
/// screen must never hang waiting for GPS: the platform lookup is capped
/// at [lookupTimeout] (10s).
class GpsLocationService extends LocationService {
  const GpsLocationService({PositionProvider? positionProvider})
    : _provider = positionProvider ?? _geolocatorProvider;

  final PositionProvider _provider;

  /// Maximum time a GPS lookup may take before giving up. The emergency
  /// screen calls [currentCoords] in initState — it must resolve fast
  /// enough that the screen never appears to stall.
  static const lookupTimeout = Duration(seconds: 10);

  static Future<GpsFix?> _geolocatorProvider({
    required Duration timeLimit,
  }) async {
    final serviceEnabled = await Geolocator.isLocationServiceEnabled();
    if (!serviceEnabled) return null;
    var permission = await Geolocator.checkPermission();
    if (permission == LocationPermission.denied) {
      permission = await Geolocator.requestPermission();
    }
    if (permission == LocationPermission.denied ||
        permission == LocationPermission.deniedForever) {
      return null;
    }
    final position = await Geolocator.getCurrentPosition(
      locationSettings: const LocationSettings(
        accuracy: LocationAccuracy.high,
        timeLimit: lookupTimeout,
      ),
    ).timeout(timeLimit);
    return GpsFix(
      latitude: position.latitude,
      longitude: position.longitude,
      accuracyMeters: position.accuracy,
      timestamp: position.timestamp,
    );
  }

  /// The full fix (with accuracy + timestamp) for the caregiver map and
  /// share sessions. Same never-throw contract as [currentCoords].
  @override
  Future<GpsFix?> currentFix() async {
    try {
      return await _provider(timeLimit: lookupTimeout);
    } catch (_) {
      return null;
    }
  }
}

/// Phase 1 implementation: always reports "unavailable".
///
/// The UI must never claim a location it does not have — every consumer
/// treats a null return as "location unavailable" and says so out loud.
/// Still used in widget tests and as the fallback when the caregiver
/// hasn't granted permission.
class NoopLocationService implements LocationService {
  const NoopLocationService();

  @override
  Future<String?> currentCoords() async => null;

  @override
  Future<GpsFix?> currentFix() async => null;

  @override
  Future<bool> get hasPermission async => false;
}
