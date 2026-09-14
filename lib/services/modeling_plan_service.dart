import 'dart:convert';

import 'package:shared_preferences/shared_preferences.dart';

import '../models/modeling_plan.dart';

/// Per-profile progress through the caregiver's first-week modeling plan.
///
/// Local only, keyed by profile id, so two communicators on a shared device
/// (a classroom tablet) each keep their own week. Nothing here goes anywhere
/// near a network.
class ModelingPlanService {
  static const _prefix = 'vidavoice.modelingPlan.v1.';

  final Map<String, ModelingProgress> _byProfile = {};

  static String _key(String profileId) => '$_prefix$profileId';

  /// Progress for [profileId], creating an empty (not-yet-started) record
  /// rather than returning null — callers always have something to render.
  ModelingProgress forProfile(String profileId) =>
      _byProfile[profileId] ?? ModelingProgress();

  /// Loads progress for the profiles that have any. Cheap: at most one small
  /// JSON blob per profile.
  Future<void> load(Iterable<String> profileIds) async {
    final prefs = await SharedPreferences.getInstance();
    _byProfile.clear();
    for (final id in profileIds) {
      final raw = prefs.getString(_key(id));
      if (raw == null) continue;
      try {
        _byProfile[id] = ModelingProgress.fromJson(
          Map<String, dynamic>.from(json.decode(raw) as Map),
        );
      } catch (_) {
        // A corrupt record must never block the board from booting.
        // Losing a caregiver's checkmarks is recoverable; a failed boot is not.
      }
    }
  }

  Future<void> start(String profileId) async {
    final current = forProfile(profileId);
    if (current.started) return;
    await _save(
      profileId,
      ModelingProgress(
        startedOn: DateTime.now(),
        completedDays: current.completedDays,
      ),
    );
  }

  Future<void> setDayDone(String profileId, int day, bool done) async {
    final current = forProfile(profileId);
    final days = Set<int>.from(current.completedDays);
    if (done) {
      days.add(day);
    } else {
      days.remove(day);
    }
    await _save(
      profileId,
      // Ticking a day before pressing Start counts as starting.
      ModelingProgress(
        startedOn: current.startedOn ?? (done ? DateTime.now() : null),
        completedDays: days,
      ),
    );
  }

  Future<void> reset(String profileId) async {
    final prefs = await SharedPreferences.getInstance();
    _byProfile.remove(profileId);
    await prefs.remove(_key(profileId));
  }

  Future<void> _save(String profileId, ModelingProgress progress) async {
    final prefs = await SharedPreferences.getInstance();
    _byProfile[profileId] = progress;
    await prefs.setString(_key(profileId), json.encode(progress.toJson()));
  }
}
