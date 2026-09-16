import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../models/dashboard.dart';
import '../models/word.dart';

/// Per-profile personal dashboards, persisted locally.
///
/// One dashboard per profile. The service is a thin store — ordering and
/// editing live in the caregiver UI; the home board only reads.
///
/// Dashboards are synced across the family's devices end-to-end encrypted
/// (see DashboardSyncService): the payload keys dashboards by the
/// profile's [syncKey](../../profile_service.dart), and this service
/// attaches them to local profile ids on merge.
class DashboardService {
  static const _kDashboards = 'vidavoice.dashboards.v1';

  /// Fired after every persisted change (not after [load]). The dashboard
  /// sync engine uses it to schedule an encrypted push.
  VoidCallback? onChanged;

  void _notifyChanged() => onChanged?.call();

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

  /// One-time backfill for vocab cells stored before the label fallback
  /// existed (B2): when a cell has a wordId but no stored label and the
  /// word still resolves in [pack], store the label so the cell stays
  /// speakable if the word ever leaves a later pack. Cells whose word is
  /// already gone are left alone — nothing to backfill from. Persists
  /// only when something changed; idempotent, safe to run every boot
  /// (it also heals dashboards restored from profile backups).
  Future<void> backfillLabels(LanguagePack pack) async {
    var changed = false;
    for (final dashboard in _byProfile.values) {
      for (var i = 0; i < dashboard.cells.length; i++) {
        final cell = dashboard.cells[i];
        final wordId = cell.wordId;
        if (wordId == null || cell.label.isNotEmpty) continue;
        try {
          final label = pack.wordById(wordId).label;
          dashboard.cells[i] = DashboardCell(
            id: cell.id,
            wordId: cell.wordId,
            label: label,
            speakText: cell.speakText,
            emoji: cell.emoji,
            imageData: cell.imageData,
            color: cell.color,
          );
          changed = true;
        } on Object {
          // Word already gone from this pack — nothing to backfill from.
        }
      }
    }
    if (changed) await _persist();
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
    _notifyChanged();
  }

  Future<void> delete(String profileId) async {
    _byProfile.remove(profileId);
    await _persist();
    _notifyChanged();
  }

  Future<void> setEnabled(String profileId, bool enabled) async {
    final dashboard = _byProfile[profileId];
    if (dashboard == null) return;
    dashboard.enabled = enabled;
    await _persist();
    _notifyChanged();
  }

  /// Replaces the local dashboard for [localProfileId] with a copy of a
  /// dashboard that arrived over sync. The synced dashboard's own
  /// profileId is meaningless on this device (profile ids are local), so
  /// the copy is re-keyed to the local profile while keeping the synced
  /// content, name, enabled flag, and updatedAt.
  Future<void> replaceFor(
    String localProfileId,
    PersonalDashboard source,
  ) async {
    _byProfile[localProfileId] = PersonalDashboard(
      id: source.id,
      profileId: localProfileId,
      name: source.name,
      cells: List.of(source.cells),
      enabled: source.enabled,
      source: source.source,
      updatedAt: source.updatedAt,
    );
    await _persist();
  }

  /// A fresh stable id for a cell added to [dashboard].
  int _cellSeq = 0;
  String newCellId(PersonalDashboard dashboard) =>
      'cell-${DateTime.now().microsecondsSinceEpoch}-'
      '${_cellSeq++}-${dashboard.cells.length}';
}
