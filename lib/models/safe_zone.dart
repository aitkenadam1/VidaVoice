import 'dart:math';

/// A named circular safe zone, defined by a caregiver in the PIN-gated hub.
///
/// Zone definitions travel inside the existing end-to-end encrypted family
/// sync blob ([DashboardSyncService] payload doc type `safe_zones`). The
/// server stores only ciphertext: names, centers, and radii never leave a
/// device unencrypted. The [id] is the opaque native-geofence identifier —
/// the OS receives the id only, never the name.
///
/// Phase 2B scope: P1 covers the model + sync + hub editor. The child's
/// device does not watch these zones yet, so no enter/exit alerts are sent
/// by this phase.
class SafeZone {
  SafeZone({
    required this.id,
    required this.name,
    required this.lat,
    required this.lng,
    required this.radiusM,
    required this.enabled,
    required this.notifyEnter,
    required this.notifyExit,
    required this.updatedTs,
  });

  /// `zone_<uuid>` — opaque, also the native geofence id. The OS never
  /// sees the zone name.
  final String id;

  final String name;
  final double lat;
  final double lng;

  /// Geofence radius in meters.
  final double radiusM;

  final bool enabled;
  final bool notifyEnter;
  final bool notifyExit;

  /// Last local mutation, milliseconds-precision. Merge is last-writer-
  /// wins by this timestamp, matched by [id].
  final DateTime updatedTs;

  static const double minRadiusM = 50;
  static const double maxRadiusM = 2000;
  static const double defaultRadiusM = 300;
  static const int maxNameLength = 60;

  static final RegExp _idPattern = RegExp(r'^zone_[0-9a-fA-F\-]{1,64}$');
  static final _random = Random.secure();

  /// Generates a new opaque zone id (`zone_<32 hex chars>`).
  static String newId() {
    final bytes = List<int>.generate(16, (_) => _random.nextInt(256));
    final hex = bytes
        .map((b) => b.toRadixString(16).padLeft(2, '0'))
        .join();
    return 'zone_$hex';
  }

  /// Human-readable validation problems; empty means the zone is valid.
  /// Pure — safe to call from tests and UI without throwing.
  List<String> validate() {
    final problems = <String>[];
    if (!_idPattern.hasMatch(id)) {
      problems.add('Zone id must look like zone_<uuid>.');
    }
    final trimmed = name.trim();
    if (trimmed.isEmpty) {
      problems.add('Give the zone a name.');
    } else if (trimmed.length > maxNameLength) {
      problems.add('Name must be $maxNameLength characters or fewer.');
    }
    if (lat.isNaN || lat < -90 || lat > 90) {
      problems.add('Latitude must be between -90 and 90.');
    }
    if (lng.isNaN || lng < -180 || lng > 180) {
      problems.add('Longitude must be between -180 and 180.');
    }
    if (radiusM.isNaN || radiusM < minRadiusM || radiusM > maxRadiusM) {
      problems.add(
        'Radius must be between ${minRadiusM.round()} m and '
        '${(maxRadiusM / 1000).round()} km.',
      );
    }
    return problems;
  }

  bool get isValid => validate().isEmpty;

  factory SafeZone.fromJson(Map<String, dynamic> json) {
    final zone = SafeZone(
      id: json['id']?.toString() ?? '',
      name: json['name']?.toString() ?? '',
      lat: (json['lat'] as num?)?.toDouble() ?? double.nan,
      lng: (json['lng'] as num?)?.toDouble() ?? double.nan,
      radiusM: (json['radius_m'] as num?)?.toDouble() ?? double.nan,
      enabled: json['enabled'] == true,
      notifyEnter: json['notify_enter'] != false,
      notifyExit: json['notify_exit'] != false,
      updatedTs: _parseTs(json['updated_ts']),
    );
    final problems = zone.validate();
    if (problems.isNotEmpty) {
      throw FormatException('Invalid safe zone: ${problems.join(' ')}');
    }
    return zone;
  }

  Map<String, dynamic> toJson() => {
        'id': id,
        'name': name,
        'lat': lat,
        'lng': lng,
        'radius_m': radiusM,
        'enabled': enabled,
        'notify_enter': notifyEnter,
        'notify_exit': notifyExit,
        'updated_ts': updatedTs.millisecondsSinceEpoch,
      };

  SafeZone copyWith({
    String? id,
    String? name,
    double? lat,
    double? lng,
    double? radiusM,
    bool? enabled,
    bool? notifyEnter,
    bool? notifyExit,
    DateTime? updatedTs,
  }) {
    return SafeZone(
      id: id ?? this.id,
      name: name ?? this.name,
      lat: lat ?? this.lat,
      lng: lng ?? this.lng,
      radiusM: radiusM ?? this.radiusM,
      enabled: enabled ?? this.enabled,
      notifyEnter: notifyEnter ?? this.notifyEnter,
      notifyExit: notifyExit ?? this.notifyExit,
      updatedTs: updatedTs ?? this.updatedTs,
    );
  }

  /// Merges two zone lists by [id], last-writer-wins on [updatedTs]
  /// (ties go to [remote] so devices converge deterministically).
  /// Zones present only on one side are kept — P1 has no tombstones, so a
  /// zone deleted on one device can be re-adopted from another device's
  /// blob until delete propagation lands.
  static List<SafeZone> merge(List<SafeZone> local, List<SafeZone> remote) {
    final byId = <String, SafeZone>{
      for (final z in local) z.id: z,
    };
    for (final z in remote) {
      final existing = byId[z.id];
      if (existing == null ||
          !z.updatedTs.isBefore(existing.updatedTs)) {
        byId[z.id] = z;
      }
    }
    final merged = byId.values.toList()
      ..sort((a, b) => a.name.toLowerCase().compareTo(b.name.toLowerCase()));
    return merged;
  }

  static DateTime _parseTs(Object? v) {
    if (v is int) return DateTime.fromMillisecondsSinceEpoch(v);
    if (v is num) return DateTime.fromMillisecondsSinceEpoch(v.toInt());
    if (v is String) return DateTime.tryParse(v) ?? DateTime.now();
    return DateTime.now();
  }

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is SafeZone &&
          id == other.id &&
          name == other.name &&
          lat == other.lat &&
          lng == other.lng &&
          radiusM == other.radiusM &&
          enabled == other.enabled &&
          notifyEnter == other.notifyEnter &&
          notifyExit == other.notifyExit &&
          updatedTs.millisecondsSinceEpoch ==
              other.updatedTs.millisecondsSinceEpoch;

  @override
  int get hashCode => Object.hash(
        id,
        name,
        lat,
        lng,
        radiusM,
        enabled,
        notifyEnter,
        notifyExit,
        updatedTs.millisecondsSinceEpoch,
      );

  @override
  String toString() =>
      'SafeZone(id: $id, name: $name, radiusM: $radiusM, enabled: $enabled)';
}
