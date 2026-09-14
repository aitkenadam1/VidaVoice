import 'dart:convert';

import 'package:shared_preferences/shared_preferences.dart';

/// One communicator profile (local only for now; cloud sync is planned).
class UserProfile {
  UserProfile({required this.id, required this.name});

  final String id;
  String name;

  Map<String, dynamic> toJson() => {'id': id, 'name': name};

  factory UserProfile.fromJson(Map<String, dynamic> json) =>
      UserProfile(id: json['id'] as String, name: json['name'] as String);
}

/// Local profile store backed by SharedPreferences.
class ProfileService {
  static const _kProfiles = 'vidavoice.profiles.v1';
  static const _kActive = 'vidavoice.activeProfile.v1';

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
          id: 'p-${DateTime.now().millisecondsSinceEpoch}',
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
      id: 'p-${DateTime.now().millisecondsSinceEpoch}',
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
