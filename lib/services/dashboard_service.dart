import 'dart:convert';

import 'package:shared_preferences/shared_preferences.dart';

import '../models/dashboard.dart';

/// Per-profile personal dashboards, persisted locally.
///
/// One dashboard per profile. The service is a thin store — ordering and
/// editing live in the caregiver UI; the home board only reads.
class DashboardService {
  static const _kDashboards = 'vidavoice.dashboards.v1';

  final Map<String, PersonalDashboard> _byProfile = {};

  PersonalDashboard? forProfile(String profileId) => _byProfile[profileId];

  bool isEnabled(String profileId) =>
      _byProfile[profileId]?.enabled ?? false;

  Future<void> load() async {
    _byProfile.clear();
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getString(_kDashboards);
    if (raw == null) return;
    try {
      final decoded = json.decode(raw) as Map;
      decoded.forEach((profileId, boardJson) {
        if (profileId is! String || boardJson is! Map) return;
        try {
          _byProfile[profileId] = PersonalDashboard.fromJson(
            Map<String, dynamic>.from(boardJson),
          );
        } on Object {
          // One corrupt dashboard must not break boot or the others.
          // (Object, not just FormatException: a wrong field type throws
          // _TypeError, and anything here must fail closed.)
        }
      });
    } on Object {
      // Corrupt blob: start fresh rather than breaking boot.
      _byProfile.clear();
    }
  }

  Future<void> _persist() async {
    final prefs = await SharedPreferences.getInstance();
    final map = <String, dynamic>{
      for (final entry in _byProfile.entries) entry.key: entry.value.toJson(),
    };
    await prefs.setString(_kDashboards, json.encode(map));
  }

  /// Returns the profile's dashboard, creating an empty one when needed.
  /// The caller must [save] after mutating it.
  PersonalDashboard ensureFor(String profileId, {String name = 'My board'}) {
    return _byProfile.putIfAbsent(
      profileId,
      () => PersonalDashboard(
        id: 'dash-$profileId',
        profileId: profileId,
        name: name,
      ),
    );
  }

  Future<void> save(PersonalDashboard dashboard) async {
    dashboard.updatedAt = DateTime.now();
    _byProfile[dashboard.profileId] = dashboard;
    await _persist();
  }

  Future<void> delete(String profileId) async {
    _byProfile.remove(profileId);
    await _persist();
  }

  Future<void> setEnabled(String profileId, bool enabled) async {
    final dashboard = _byProfile[profileId];
    if (dashboard == null) return;
    dashboard.enabled = enabled;
    await _persist();
  }

  /// A fresh stable id for a cell added to [dashboard].
  int _cellSeq = 0;
  String newCellId(PersonalDashboard dashboard) =>
      'cell-${DateTime.now().microsecondsSinceEpoch}-'
      '${_cellSeq++}-${dashboard.cells.length}';
}
