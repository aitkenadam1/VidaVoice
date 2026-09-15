import 'dart:convert';

import 'package:shared_preferences/shared_preferences.dart';

import 'profile_service.dart';

/// A caregiver-facing suggestion to preview the next communication mode.
///
/// Returned by [ModeNudgeService.suggestionFor]. It is display-only: it
/// carries the target mode for the preview button, never a command to
/// change the profile's saved mode.
class NudgeSuggestion {
  const NudgeSuggestion({
    required this.profileId,
    required this.currentMode,
    required this.targetMode,
  });

  final String profileId;
  final CommunicationMode currentMode;
  final CommunicationMode targetMode;
}

/// Local eligibility counters and the caregiver-nudge state machine
/// (Phase 5 of the modes plan).
///
/// # What is stored
/// Only integer COUNTS per profile, in one JSON blob
/// (`vidavoice.modeNudge.v1`): how many times the profile pressed Speak
/// in Build mode with a full strip, and how many times it spoke in Tap
/// mode. Message text is NEVER recorded — there is no key or value that
/// could hold an utterance, so there is nothing to redact, clear, or
/// leak.
///
/// # Documented eligibility rules (named constants below)
/// * Build -> Type: the profile must be in Build mode and must have
///   pressed Speak at least [buildFullSpeakThreshold] times with the
///   phrase strip at the caregiver-set maximum length (a full,
///   deliberate message each time — the plan's headline signal for
///   "building longer messages consistently").
/// * Tap -> Build: the profile must be in Tap mode and must have spoken
///   at least [tapSpeakThreshold] times. The threshold is deliberately
///   high (a couple of weeks of regular use): sustained Tap use shows
///   the communicator knows the board and the app rhythm, so trying the
///   next composition surface is a fair, low-pressure question. This is
///   an optional discovery nudge, not a readiness claim.
/// * Type -> (none): Type is the top of the progression; a Type profile
///   is never eligible, because there is no "next mode" to preview.
///
/// # State machine (per profile, documented and test-pinned)
/// ```
/// notEligible --(threshold reached)--> eligible
/// eligible    --(caregiver dismisses)--> dismissed (30-day cooldown;
///              may become eligible again when the cooldown expires and
///              the counters still satisfy the threshold)
/// eligible    --("do not suggest")--> off (durable, per-profile
///              ModeNudgePreference.off — overrides eligibility forever;
///              counters are kept so re-allowing later still works)
/// eligible    --(sandbox preview opened)--> previewed (treated exactly
///              like dismissed: 30-day cooldown, mode untouched)
/// any         --(preference = paused)--> suppressed display only:
///              eligibility state is NOT erased, so unpausing can surface
///              the suggestion again without new counting.
/// ```
///
/// # Guardrails
/// * This file NEVER changes a profile's communication mode. It does not
///   call `ProfileService.setCommunicationMode` and never assigns
///   `profile.communicationMode`; a test scans this source file to pin
///   that. The only code path that may change a mode is the explicit
///   caregiver save (`ProfileService.setCommunicationMode`), unchanged.
/// * Local only: SharedPreferences, no HTTP, no analytics. The counters
///   contain no text, so "nothing leaves the device" holds trivially —
///   there is nothing to leave.
/// * Migration-safe: profiles that existed before this feature load with
///   no record here, so they start at zero counts and are not eligible.
///   Eligibility is never seeded retroactively (invented history would
///   be a false claim about the communicator).
class ModeNudgeService {
  ModeNudgeService({DateTime Function()? clock})
    : _clock = clock ?? DateTime.now;

  /// How many full-strip Build speaks make a Build profile eligible to
  /// preview Type mode. Twenty deliberate, full-length messages is enough
  /// to say "consistently", not "once by accident".
  static const buildFullSpeakThreshold = 20;

  /// How many Tap-mode speaks make a Tap profile eligible to preview
  /// Build mode. Kept deliberately high: this is routine daily use
  /// (single taps add up fast), so the bar for "sustained" is a couple
  /// of weeks of regular use, not a single afternoon.
  static const tapSpeakThreshold = 250;

  /// How long a dismissal (or a sandbox preview) suppresses the nudge
  /// for a profile before it may become eligible again.
  static const nudgeCooldownDays = 30;

  static const storageKey = 'vidavoice.modeNudge.v1';

  final DateTime Function() _clock;

  /// Per-profile nudge records. Kept in memory and mirrored to
  /// [storageKey] on every mutation.
  final Map<String, _NudgeRecord> _records = {};

  /// Loads all persisted nudge records. Corrupt blobs start empty rather
  /// than breaking boot; unknown profiles start with no record.
  Future<void> load() async {
    final prefs = await SharedPreferences.getInstance();
    _records.clear();
    final raw = prefs.getString(storageKey);
    if (raw != null) {
      try {
        final decoded = json.decode(raw) as Map<String, dynamic>;
        for (final entry in decoded.entries) {
          final record = _NudgeRecord.tryParse(entry.value);
          if (record != null) _records[entry.key] = record;
        }
      } on FormatException {
        // Corrupt blob: start fresh with zero counts.
      }
    }
  }

  /// Records one intentional Build-mode Speak. Only increments the
  /// full-strip counter when [stripLength] reached the profile's
  /// caregiver-set [maxLength] — partial strips do not count toward
  /// eligibility. Stores no text.
  ///
  /// Callers must call this only for real Build-mode speaks (the
  /// SessionState call site is the only place Build speaks happen);
  /// the method itself only ever touches integer counters.
  Future<void> recordBuildSpeak({
    required String profileId,
    required int stripLength,
    required int maxLength,
  }) async {
    if (stripLength <= 0 || maxLength <= 0) return;
    if (stripLength < maxLength) return; // partial strip: not evidence
    final record = _records.putIfAbsent(profileId, _NudgeRecord.new);
    record.buildFullSpeaks++;
    await _persist();
  }

  /// Records one intentional speak in Tap mode. Single taps accumulate
  /// quickly, so the eligibility threshold ([tapSpeakThreshold]) is set
  /// accordingly. Stores no text.
  Future<void> recordTapSpeak(String profileId) async {
    final record = _records.putIfAbsent(profileId, _NudgeRecord.new);
    record.tapSpeaks++;
    await _persist();
  }

  /// The nudge to show for [profile], or null when nothing should be
  /// shown. Null covers: no next mode (Type), counters below threshold,
  /// cooldown active, preference paused/off, or no record at all.
  ///
  /// `paused` suppresses display WITHOUT erasing counters or cooldown
  /// state, so switching the preference back to `allowed` can surface
  /// the same suggestion without recounting.
  NudgeSuggestion? suggestionFor(UserProfile profile) {
    if (profile.modeNudgePreference != ModeNudgePreference.allowed) {
      return null;
    }
    final target = _nextMode(profile.communicationMode);
    if (target == null) return null;
    final record = _records[profile.id];
    if (record == null) return null;
    if (record.buildFullSpeaks < buildFullSpeakThreshold &&
        profile.communicationMode == CommunicationMode.build) {
      return null;
    }
    if (record.tapSpeaks < tapSpeakThreshold &&
        profile.communicationMode == CommunicationMode.tap) {
      return null;
    }
    final snoozed = record.snoozedUntilMillis;
    if (snoozed != null && _clock().millisecondsSinceEpoch < snoozed) {
      return null; // 30-day cooldown after dismiss or preview
    }
    return NudgeSuggestion(
      profileId: profile.id,
      currentMode: profile.communicationMode,
      targetMode: target,
    );
  }

  /// Caregiver dismissed the nudge: suppress it for [nudgeCooldownDays],
  /// then allow it to become eligible again if the counters still
  /// satisfy the threshold. Eligibility state (counts) is kept.
  Future<void> dismiss(String profileId) async {
    final record = _records.putIfAbsent(profileId, _NudgeRecord.new);
    record.snoozedUntilMillis =
        _clock().millisecondsSinceEpoch +
        Duration(days: nudgeCooldownDays).inMilliseconds;
    await _persist();
  }

  /// The caregiver opened the sandbox preview for the suggested mode.
  /// Treated exactly like a dismissal: 30-day cooldown, and — by
  /// construction — the saved mode is not touched here.
  Future<void> recordPreview(String profileId) => dismiss(profileId);

  /// Forgets everything stored for [profileId] (used when a profile is
  /// deleted). Note: setting the profile's nudge preference to `off`
  /// ("do not suggest again") does NOT call this — the counters are
  /// kept so re-allowing later still works.
  Future<void> removeProfile(String profileId) async {
    if (_records.remove(profileId) != null) await _persist();
  }

  /// The next mode a nudge could suggest, or null when the profile is
  /// already at the top of the progression. Used by [suggestionFor].
  static CommunicationMode? _nextMode(CommunicationMode current) => switch (current) {
    CommunicationMode.tap => CommunicationMode.build,
    CommunicationMode.build => CommunicationMode.type,
    CommunicationMode.type => null,
  };

  /// Test-visible snapshot of the counts for [profileId]. Counters only —
  /// this is also what the privacy tests inspect.
  ({int buildFullSpeaks, int tapSpeaks}) countsFor(String profileId) {
    final record = _records[profileId];
    return (
      buildFullSpeaks: record?.buildFullSpeaks ?? 0,
      tapSpeaks: record?.tapSpeaks ?? 0,
    );
  }

  Future<void> _persist() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(
      storageKey,
      json.encode({
        for (final e in _records.entries) e.key: e.value.toJson(),
      }),
    );
  }
}

/// One profile's nudge record: integer counts and an optional
/// cooldown timestamp. There is deliberately no field for text — an
/// utterance cannot be stored here even by accident.
class _NudgeRecord {
  int buildFullSpeaks = 0;
  int tapSpeaks = 0;
  int? snoozedUntilMillis;

  Map<String, dynamic> toJson() => {
    'buildFullSpeaks': buildFullSpeaks,
    'tapSpeaks': tapSpeaks,
    if (snoozedUntilMillis != null) 'snoozedUntilMillis': snoozedUntilMillis,
  };

  static _NudgeRecord? tryParse(Object? raw) {
    if (raw is! Map) return null;
    final map = Map<String, dynamic>.from(raw);
    final record = _NudgeRecord();
    final build = map['buildFullSpeaks'];
    final tap = map['tapSpeaks'];
    if (build is! int || tap is! int || build < 0 || tap < 0) return null;
    record.buildFullSpeaks = build;
    record.tapSpeaks = tap;
    final snoozed = map['snoozedUntilMillis'];
    record.snoozedUntilMillis = snoozed is int ? snoozed : null;
    return record;
  }
}
