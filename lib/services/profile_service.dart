import 'dart:convert';
import 'dart:math' as math;

import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../models/calling_safety.dart';

/// How this communicator composes messages.
///
/// Stored per profile. It is NEVER derived from mobility answers, grid
/// size, or any other signal — it only changes through an explicit
/// caregiver save (onboarding choice or profile settings).
enum CommunicationMode { tap, build, type }

/// Whether OneVoz may show caregiver-facing mode-progression nudges for
/// this profile. Stored per profile; defaults to [allowed].
enum ModeNudgePreference { allowed, paused, off }

/// One communicator profile (local store; cloud sync of dashboard content
/// and profile settings is end-to-end encrypted — see
/// DashboardSyncService).
class UserProfile {
  UserProfile({required this.id, required this.name, String? syncKey})
    : syncKey = syncKey ?? _newSyncKey();

  final String id;
  String name;

  /// Stable cross-device identity for sync. Survives renames: dashboards
  /// and settings follow the [syncKey], not the local [id] or [name].
  /// Backfilled for profiles written before sync existed. Reassigned only
  /// by [ProfileService.adoptSyncKey] during name-fallback convergence.
  String syncKey;

  /// Last local content change. Drives last-write-wins merging during
  /// sync — bumped by every mutating method below, never by [load].
  DateTime updatedAt = DateTime.now();

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

  /// Phase 1 calling & safety: trusted contacts the child can call.
  /// Default empty; seeded only by caregiver saves and sync merges.
  List<SafetyContact> contacts = [];

  /// Phase 1 calling & safety: pre-written phrases for calls. New
  /// profiles are seeded with [defaultCallPhrases] at creation.
  List<CallPhrase> callPhrases = [];

  /// Phase 1 calling & safety: the child's emergency details (drives
  /// the emergency SMS and phrase placeholder resolution).
  EmergencyProfileData emergency = const EmergencyProfileData();

  /// Phase 1 calling & safety: behavior toggles for the calling flow.
  SafetySettings safety = const SafetySettings();

  Map<String, dynamic> toJson() => {
    'id': id,
    'name': name,
    'syncKey': syncKey,
    'mode': communicationMode.name,
    'buildMaxSymbols': buildMaxSymbols,
    'predictionEnabled': predictionEnabled,
    'nudgePreference': modeNudgePreference.name,
    'contacts': contacts.map((c) => c.toJson()).toList(),
    'callPhrases': callPhrases.map((p) => p.toJson()).toList(),
    'emergency': emergency.toJson(),
    'safety': safety.toJson(),
    'updatedAt': updatedAt.toIso8601String(),
  };

  factory UserProfile.fromJson(Map<String, dynamic> json) {
    final profile = UserProfile(
      id: json['id'] as String,
      name: json['name'] as String,
      syncKey: json['syncKey'] is String && (json['syncKey'] as String).isNotEmpty
          ? json['syncKey'] as String
          : null,
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
    // Migration-safe: calling/safety keys are optional; a pre-feature
    // profile opens with empty lists and the safe defaults. Malformed
    // entries are skipped, never thrown.
    profile.contacts = _parseSafetyContacts(json['contacts']);
    profile.callPhrases = _parseCallPhrases(json['callPhrases']);
    profile.emergency = _parseEmergency(json['emergency']);
    profile.safety = _parseSafetySettings(json['safety']);
    final updatedRaw = json['updatedAt'];
    if (updatedRaw is String) {
      profile.updatedAt =
          DateTime.tryParse(updatedRaw) ?? DateTime.now();
    }
    return profile;
  }

  /// Bump the content-change timestamp. Called by every mutating method;
  /// never by [load], so a plain reload doesn't look like a newer edit.
  void touch() {
    updatedAt = DateTime.now();
  }
}

/// Generates a v4-style UUID without pulling in the proxy client.
String _newSyncKey() {
  final r = _secureRandom();
  final bytes = List<int>.generate(16, (_) => r.nextInt(256));
  bytes[6] = (bytes[6] & 0x0f) | 0x40;
  bytes[8] = (bytes[8] & 0x3f) | 0x80;
  String hex(int n) => n.toRadixString(16).padLeft(2, '0');
  final s = bytes.map(hex).join();
  return '${s.substring(0, 8)}-${s.substring(8, 12)}-'
      '${s.substring(12, 16)}-${s.substring(16, 20)}-${s.substring(20)}';
}

math.Random _secureRandom() => math.Random.secure();

/// Parses the calling/safety lists from a stored profile map. Missing or
/// malformed entries are skipped — a corrupt entry must never break the
/// whole profile load.
List<SafetyContact> _parseSafetyContacts(Object? raw) {
  final out = <SafetyContact>[];
  if (raw is! List) return out;
  for (final entry in raw) {
    try {
      if (entry is Map) {
        out.add(
          SafetyContact.fromJson(Map<String, dynamic>.from(entry)),
        );
      }
    } catch (_) {}
  }
  return out;
}

List<CallPhrase> _parseCallPhrases(Object? raw) {
  final out = <CallPhrase>[];
  if (raw is! List) return out;
  for (final entry in raw) {
    try {
      if (entry is Map) {
        out.add(CallPhrase.fromJson(Map<String, dynamic>.from(entry)));
      }
    } catch (_) {}
  }
  return out;
}

EmergencyProfileData _parseEmergency(Object? raw) {
  if (raw is Map) {
    try {
      return EmergencyProfileData.fromJson(Map<String, dynamic>.from(raw));
    } catch (_) {}
  }
  return const EmergencyProfileData();
}

SafetySettings _parseSafetySettings(Object? raw) {
  if (raw is Map) {
    try {
      return SafetySettings.fromJson(Map<String, dynamic>.from(raw));
    } catch (_) {}
  }
  return const SafetySettings();
}

/// Local profile store backed by SharedPreferences.
class ProfileService {
  static const _kProfiles = 'vidavoice.profiles.v1';
  static const _kActive = 'vidavoice.activeProfile.v1';

  /// Fired after every persisted content change (not after [load]).
  /// The dashboard sync engine uses it to schedule an encrypted push.
  VoidCallback? onChanged;

  void _notifyChanged() => onChanged?.call();

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
      final profile = UserProfile(
        id: _newProfileId(),
        name: 'My Voice',
      );
      profile.callPhrases = defaultCallPhrases();
      _profiles.add(profile);
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
    profile.callPhrases = defaultCallPhrases();
    _profiles.add(profile);
    _activeId = profile.id;
    await _persist(await SharedPreferences.getInstance());
    _notifyChanged();
    return profile;
  }

  /// Adds a profile that arrived over sync. Unlike [addProfile] it does
  /// NOT steal the active profile — the active profile only changes when
  /// the family's mirror toggle is on (handled by the sync engine).
  Future<UserProfile> addImportedProfile({
    required String syncKey,
    required String name,
  }) async {
    final profile = UserProfile(
      id: _newProfileId(),
      name: name,
      syncKey: syncKey,
    );
    _profiles.add(profile);
    await _persist(await SharedPreferences.getInstance());
    return profile;
  }

  Future<void> renameActive(String name) async {
    final a = active;
    if (a == null) return;
    a.name = name;
    a.touch();
    await _persist(await SharedPreferences.getInstance());
    _notifyChanged();
  }

  /// Explicit caregiver save only: this is the ONLY path that may change
  /// a profile's communication mode. Nothing else in the app (mobility
  /// answers, migrations, nudges) may call it or set the field directly.
  Future<void> setCommunicationMode(String id, CommunicationMode mode) async {
    final p = _byId(id);
    if (p == null) return;
    p.communicationMode = mode;
    p.touch();
    await _persist(await SharedPreferences.getInstance());
    _notifyChanged();
  }

  /// Caregiver-set maximum Build-mode phrase length for [id].
  /// Clamped to [minBuildMaxSymbols]..[maxBuildMaxSymbols].
  Future<void> setBuildMaxSymbols(String id, int max) async {
    final p = _byId(id);
    if (p == null) return;
    p.buildMaxSymbols = max.clamp(minBuildMaxSymbols, maxBuildMaxSymbols);
    p.touch();
    await _persist(await SharedPreferences.getInstance());
    _notifyChanged();
  }

  /// Whether Type-mode prediction learns from [id]'s spoken history.
  Future<void> setPredictionEnabled(String id, bool enabled) async {
    final p = _byId(id);
    if (p == null) return;
    p.predictionEnabled = enabled;
    p.touch();
    await _persist(await SharedPreferences.getInstance());
    _notifyChanged();
  }

  /// The caregiver's mode-nudge preference for [id].
  Future<void> setNudgePreference(String id, ModeNudgePreference pref) async {
    final p = _byId(id);
    if (p == null) return;
    p.modeNudgePreference = pref;
    p.touch();
    await _persist(await SharedPreferences.getInstance());
    _notifyChanged();
  }

  /// Replaces the safety contacts for [id] (Phase 1 calling).
  Future<void> setContacts(String id, List<SafetyContact> contacts) async {
    final p = _byId(id);
    if (p == null) return;
    p.contacts = List<SafetyContact>.of(contacts);
    p.touch();
    await _persist(await SharedPreferences.getInstance());
    _notifyChanged();
  }

  /// Replaces the call phrases for [id] (Phase 1 calling).
  Future<void> setCallPhrases(String id, List<CallPhrase> phrases) async {
    final p = _byId(id);
    if (p == null) return;
    p.callPhrases = List<CallPhrase>.of(phrases);
    p.touch();
    await _persist(await SharedPreferences.getInstance());
    _notifyChanged();
  }

  /// Replaces the emergency profile data for [id] (Phase 1 safety).
  Future<void> setEmergency(String id, EmergencyProfileData emergency) async {
    final p = _byId(id);
    if (p == null) return;
    p.emergency = emergency;
    p.touch();
    await _persist(await SharedPreferences.getInstance());
    _notifyChanged();
  }

  /// Replaces the safety settings for [id] (Phase 1 calling).
  Future<void> setSafety(String id, SafetySettings safety) async {
    final p = _byId(id);
    if (p == null) return;
    p.safety = safety;
    p.touch();
    await _persist(await SharedPreferences.getInstance());
    _notifyChanged();
  }

  UserProfile? _byId(String id) {
    for (final p in _profiles) {
      if (p.id == id) return p;
    }
    return null;
  }

  /// Find a profile by its cross-device [syncKey].
  UserProfile? bySyncKey(String syncKey) {
    for (final p in _profiles) {
      if (p.syncKey == syncKey) return p;
    }
    return null;
  }

  /// Find a profile by name, case-insensitive, trimmed. Used only as a
  /// fallback when a synced [syncKey] has no local match (e.g. the profile
  /// was created on another device before sync keys existed).
  UserProfile? byName(String name) {
    final want = name.trim().toLowerCase();
    if (want.isEmpty) return null;
    for (final p in _profiles) {
      if (p.name.trim().toLowerCase() == want) return p;
    }
    return null;
  }

  /// Reassigns a profile's sync identity during name-fallback convergence
  /// (see DashboardSyncService): the local profile adopts the synced key
  /// so both devices converge on one identity. Intentionally does NOT
  /// bump [UserProfile.updatedAt]: the content timestamp drives
  /// last-write-wins in the sync merge, and an identity change must not
  /// masquerade as newer content.
  Future<void> adoptSyncKey(UserProfile profile, String syncKey) async {
    profile.syncKey = syncKey;
    await _persist(await SharedPreferences.getInstance());
    _notifyChanged();
  }

  /// Applies profile settings that arrived over sync (last-write-wins is
  /// decided by the caller comparing [UserProfile.updatedAt]).
  Future<void> applySyncedSettings(
    UserProfile profile, {
    required String name,
    required CommunicationMode mode,
    required int buildMaxSymbols,
    required bool predictionEnabled,
    required ModeNudgePreference nudgePreference,
    required DateTime updatedAt,
    required List<SafetyContact> contacts,
    required List<CallPhrase> callPhrases,
    required EmergencyProfileData emergency,
    required SafetySettings safety,
  }) async {
    profile.name = name;
    profile.communicationMode = mode;
    profile.buildMaxSymbols = buildMaxSymbols.clamp(
      minBuildMaxSymbols,
      maxBuildMaxSymbols,
    );
    profile.predictionEnabled = predictionEnabled;
    profile.modeNudgePreference = nudgePreference;
    profile.contacts = List<SafetyContact>.of(contacts);
    profile.callPhrases = List<CallPhrase>.of(callPhrases);
    profile.emergency = emergency;
    profile.safety = safety;
    profile.updatedAt = updatedAt;
    await _persist(await SharedPreferences.getInstance());
  }

  Future<void> setActive(String id) async {
    if (_profiles.any((p) => p.id == id)) {
      _activeId = id;
      await _persist(await SharedPreferences.getInstance());
      // The active profile is part of the synced payload (when the
      // family's mirror toggle is on), so switching profiles schedules a
      // push like any other profile change.
      _notifyChanged();
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
