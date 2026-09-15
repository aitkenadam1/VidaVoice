import 'dart:convert';

import 'package:shared_preferences/shared_preferences.dart';

/// How this communicator composes messages.
///
/// Stored per profile. It is NEVER derived from mobility answers, grid
/// size, or any other signal — it only changes through an explicit
/// caregiver save (onboarding choice or profile settings).
enum CommunicationMode { tap, build, type }

/// Whether OneVoz may show caregiver-facing mode-progression nudges for
/// this profile. Stored per profile; defaults to [allowed].
enum ModeNudgePreference { allowed, paused, off }

/// One communicator profile (local only for now; cloud sync is planned).
class UserProfile {
  UserProfile({required this.id, required this.name});

  final String id;
  String name;

  /// The profile's communication mode. Defaults to [CommunicationMode.tap]
  /// for profiles written before the modes feature existed.
  CommunicationMode communicationMode = CommunicationMode.tap;

  /// Maximum symbols the caregiver allows in a Build-mode phrase strip.
  /// Default 4; clamped to [minBuildMaxSymbols]..[maxBuildMaxSymbols].
  int buildMaxSymbols = ProfileService.defaultBuildMaxSymbols;

  /// Whether Type-mode prediction learns from this profile's spoken
  /// history (on-device only). Default true.
  bool predictionEnabled = true;

  /// Caregiver's nudge preference for this profile. Default [allowed].
  ModeNudgePreference modeNudgePreference = ModeNudgePreference.allowed;

  Map<String, dynamic> toJson() => {
    'id': id,
    'name': name,
    'mode': communicationMode.name,
    'buildMaxSymbols': buildMaxSymbols,
    'predictionEnabled': predictionEnabled,
    'nudgePreference': modeNudgePreference.name,
  };

  factory UserProfile.fromJson(Map<String, dynamic> json) {
    final profile = UserProfile(
      id: json['id'] as String,
      name: json['name'] as String,
    );
    // Migration-safe: any missing or unknown value falls back to the
    // safe default instead of throwing — a pre-modes profile opens as
    // Tap with the standard defaults.
    profile.communicationMode = switch (json['mode']) {
      'build' => CommunicationMode.build,
      'type' => CommunicationMode.type,
      _ => CommunicationMode.tap,
    };
    final max = json['buildMaxSymbols'];
    profile.buildMaxSymbols = max is int
        ? max.clamp(
            ProfileService.minBuildMaxSymbols,
            ProfileService.maxBuildMaxSymbols,
          )
        : ProfileService.defaultBuildMaxSymbols;
    final prediction = json['predictionEnabled'];
    profile.predictionEnabled = prediction is bool ? prediction : true;
    profile.modeNudgePreference = switch (json['nudgePreference']) {
      'paused' => ModeNudgePreference.paused,
      'off' => ModeNudgePreference.off,
      _ => ModeNudgePreference.allowed,
    };
    return profile;
  }
}

/// Local profile store backed by SharedPreferences.
class ProfileService {
  static const _kProfiles = 'vidavoice.profiles.v1';
  static const _kActive = 'vidavoice.activeProfile.v1';

  /// Default maximum Build-mode phrase length for a new profile.
  static const defaultBuildMaxSymbols = 4;

  /// Bounds for the caregiver-set Build-mode phrase length.
  static const minBuildMaxSymbols = 2;
  static const maxBuildMaxSymbols = 12;

  final List<UserProfile> _profiles = [];
  String? _activeId;

  List<UserProfile> get profiles => List.unmodifiable(_profiles);

  UserProfile? get active {
    for (final p in _profiles) {
      if (p.id == _activeId) return p;
    }
    return _profiles.isEmpty ? null : _profiles.first;
  }

  String get activeName => active?.name ?? 'My Voice';

  /// Per-process counter mixed into generated profile ids. Profile ids were
  /// previously `p-<millisecondsSinceEpoch>` alone, so two profiles created
  /// in the same millisecond (fast devices, tests) collided — and a
  /// duplicate id makes [removeProfile] wipe both profiles at once.
  /// Stored ids are opaque strings, so the longer format is compatible.
  static int _profileIdCounter = 0;

  static String _newProfileId() =>
      'p-${DateTime.now().microsecondsSinceEpoch}-${_profileIdCounter++}';

  Future<void> load() async {
    final prefs = await SharedPreferences.getInstance();
    _profiles.clear();
    final raw = prefs.getString(_kProfiles);
    if (raw != null) {
      for (final entry in json.decode(raw) as List) {
        _profiles.add(
          UserProfile.fromJson(Map<String, dynamic>.from(entry as Map)),
        );
      }
    }
    if (_profiles.isEmpty) {
      _profiles.add(
        UserProfile(
          id: _newProfileId(),
          name: 'My Voice',
        ),
      );
    }
    _activeId = prefs.getString(_kActive);
    if (!_profiles.any((p) => p.id == _activeId)) {
      _activeId = _profiles.first.id;
    }
    await _persist(prefs);
  }

  Future<UserProfile> addProfile(String name) async {
    final profile = UserProfile(
      id: _newProfileId(),
      name: name,
    );
    _profiles.add(profile);
    _activeId = profile.id;
    await _persist(await SharedPreferences.getInstance());
    return profile;
  }

  Future<void> renameActive(String name) async {
    final a = active;
    if (a == null) return;
    a.name = name;
    await _persist(await SharedPreferences.getInstance());
  }

  /// Explicit caregiver save only: this is the ONLY path that may change
  /// a profile's communication mode. Nothing else in the app (mobility
  /// answers, migrations, nudges) may call it or set the field directly.
  Future<void> setCommunicationMode(String id, CommunicationMode mode) async {
    final p = _byId(id);
    if (p == null) return;
    p.communicationMode = mode;
    await _persist(await SharedPreferences.getInstance());
  }

  /// Caregiver-set maximum Build-mode phrase length for [id].
  /// Clamped to [minBuildMaxSymbols]..[maxBuildMaxSymbols].
  Future<void> setBuildMaxSymbols(String id, int max) async {
    final p = _byId(id);
    if (p == null) return;
    p.buildMaxSymbols = max.clamp(minBuildMaxSymbols, maxBuildMaxSymbols);
    await _persist(await SharedPreferences.getInstance());
  }

  /// Whether Type-mode prediction learns from [id]'s spoken history.
  Future<void> setPredictionEnabled(String id, bool enabled) async {
    final p = _byId(id);
    if (p == null) return;
    p.predictionEnabled = enabled;
    await _persist(await SharedPreferences.getInstance());
  }

  /// The caregiver's mode-nudge preference for [id].
  Future<void> setNudgePreference(String id, ModeNudgePreference pref) async {
    final p = _byId(id);
    if (p == null) return;
    p.modeNudgePreference = pref;
    await _persist(await SharedPreferences.getInstance());
  }

  UserProfile? _byId(String id) {
    for (final p in _profiles) {
      if (p.id == id) return p;
    }
    return null;
  }

  Future<void> setActive(String id) async {
    if (_profiles.any((p) => p.id == id)) {
      _activeId = id;
      await _persist(await SharedPreferences.getInstance());
    }
  }

  Future<void> removeProfile(String id) async {
    if (_profiles.length <= 1) return;
    _profiles.removeWhere((p) => p.id == id);
    if (_activeId == id) _activeId = _profiles.first.id;
    await _persist(await SharedPreferences.getInstance());
  }

  Future<void> _persist(SharedPreferences prefs) async {
    await prefs.setString(
      _kProfiles,
      json.encode(_profiles.map((p) => p.toJson()).toList()),
    );
    if (_activeId != null) {
      await prefs.setString(_kActive, _activeId!);
    }
  }
}
