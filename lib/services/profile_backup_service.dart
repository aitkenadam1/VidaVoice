import 'dart:convert';
import 'dart:io';

import 'package:shared_preferences/shared_preferences.dart';

import 'elevenlabs_service.dart';
import 'elevenlabs_voice_store.dart';
import 'symbol_override_service.dart';

/// One exported profile backup: everything needed to restore a communicator
/// profile on this device or another one.
///
/// The file is plain JSON (human-inspectable, no proprietary format). Device
/// settings are included because voice rate, pitch and the unlocked level
/// are part of "how this profile was set up" — but on import they are only
/// applied in replace mode; merge mode leaves the device's settings alone.
class ProfileBackup {
  ProfileBackup({
    required this.profileId,
    required this.profileName,
    required this.exportedAt,
    required this.locale,
    required this.speechRate,
    required this.speechPitch,
    required this.buttonScale,
    required this.unlockedLevel,
    required this.onboardingComplete,
    required this.usageCounts,
    required this.usageDays,
    required this.historyEntries,
    required this.planDays,
    required this.customSymbols,
    required this.elevenLabsVoices,
  });

  static const format = 'vidavoice-profile-backup';
  static const version = 1;

  final String profileId;
  final String profileName;
  final DateTime exportedAt;

  final String locale;
  final double speechRate;
  final double speechPitch;
  final double buttonScale;
  final int unlockedLevel;
  final bool onboardingComplete;

  /// word id -> lifetime taps (device-wide, as stored).
  final Map<String, int> usageCounts;

  /// yyyy-MM-dd -> word id -> taps (device-wide, as stored).
  final Map<String, Map<String, int>> usageDays;

  /// Raw history entry maps (validated shape, newest first).
  final List<Map<String, dynamic>> historyEntries;

  /// Completed first-week plan days (1..7).
  final List<int> planDays;

  /// Per-profile custom button images: vocabulary/phrase item id ->
  /// base64 JPEG (see SymbolOverrideService). Empty when the profile has
  /// none, or when the backup predates the custom-symbols feature.
  final Map<String, String> customSymbols;

  /// Saved ElevenLabs cloud voices for the profile. The ids only resolve
  /// with an API key (kept in secure storage, never in backups); without
  /// one they are inert and speech falls back on-device.
  final List<SavedElevenLabsVoice> elevenLabsVoices;

  Map<String, dynamic> toJson() => {
    'format': format,
    'version': version,
    'exportedAt': exportedAt.millisecondsSinceEpoch,
    'profile': {'id': profileId, 'name': profileName},
    'settings': {
      'locale': locale,
      'speechRate': speechRate,
      'speechPitch': speechPitch,
      'buttonScale': buttonScale,
      'unlockedLevel': unlockedLevel,
      'onboardingComplete': onboardingComplete,
    },
    'usage': {'counts': usageCounts, 'days': usageDays},
    'history': historyEntries,
    'planDays': planDays,
    'customSymbols': customSymbols,
    'elevenLabsVoices': [for (final v in elevenLabsVoices) v.toJson()],
  };

  /// Parses and validates a backup. Throws [BackupFormatException] on
  /// anything corrupt, truncated, or from an unknown format — the caller
  /// must show the error and touch nothing.
  factory ProfileBackup.fromJson(Map<String, dynamic> json) {
    String req(String what) => throw BackupFormatException(
      'Backup is not a OneVoz profile backup ($what).',
    );
    if (json['format'] != format) req('missing format marker');
    if (json['version'] != version) {
      throw BackupFormatException(
        'Backup version ${json['version']} is not supported by this app.',
      );
    }
    final profile = json['profile'];
    if (profile is! Map) req('missing profile block');
    final profileId = profile['id'];
    final profileName = profile['name'];
    if (profileId is! String || profileId.isEmpty) {
      req('profile id is missing');
    }
    if (profileName is! String) req('profile name is missing');

    final settings = json['settings'];
    if (settings is! Map) req('missing settings block');
    double num01(String key) {
      final v = settings[key];
      if (v is! num) req('settings.$key is missing');
      return (v as num).toDouble();
    }

    final usage = json['usage'];
    if (usage is! Map) req('missing usage block');
    Map<String, int> intMap(dynamic raw, String what) {
      if (raw is! Map) req(what);
      final out = <String, int>{};
      (raw as Map).forEach((k, v) {
        if (k is! String || v is! int || v <= 0) req('$what has a bad entry');
        out[k] = v;
      });
      return out;
    }

    final days = <String, Map<String, int>>{};
    final rawDays = usage['days'];
    if (rawDays is! Map) req('usage.days is missing');
    (rawDays as Map).forEach((day, bucket) {
      if (day is! String || !RegExp(r'^\d{4}-\d{2}-\d{2}$').hasMatch(day)) {
        req('usage.days has a bad day key');
      }
      days[day] = intMap(bucket, 'usage.days[$day]');
    });

    final history = <Map<String, dynamic>>[];
    final rawHistory = json['history'];
    if (rawHistory is! List) req('history is missing');
    for (final entry in rawHistory as List) {
      if (entry is! Map) req('a history entry is malformed');
      final m = Map<String, dynamic>.from(entry);
      final ids = m['ids'];
      final text = m['text'];
      final spokenAt = m['spokenAt'];
      if (ids is! List ||
          ids.any((e) => e is! String) ||
          text is! String ||
          text.isEmpty ||
          spokenAt is! num) {
        req('a history entry is malformed');
      }
      history.add(m);
    }

    final planDays = <int>[];
    final rawPlan = json['planDays'];
    if (rawPlan is! List) req('planDays is missing');
    for (final d in rawPlan as List) {
      if (d is! int || d < 1 || d > 7 || planDays.contains(d)) {
        req('planDays has a bad day');
      }
      planDays.add(d);
    }

    final unlocked = settings['unlockedLevel'];
    if (unlocked is! int || unlocked < 1 || unlocked > 3) {
      req('settings.unlockedLevel is out of range');
    }
    final locale = settings['locale'];
    if (locale is! String || locale.isEmpty) req('settings.locale is missing');
    final onboarding = settings['onboardingComplete'];
    if (onboarding is! bool) req('settings.onboardingComplete is missing');

    final exportedAt = json['exportedAt'];
    if (exportedAt is! num) req('exportedAt is missing');

    // Optional so backups written before the custom-symbols feature still
    // decode; those simply restore with no custom images.
    final customSymbols = <String, String>{};
    final rawSymbols = json['customSymbols'];
    if (rawSymbols != null) {
      if (rawSymbols is! Map) req('customSymbols is malformed');
      for (final e in (rawSymbols as Map).entries) {
        final k = e.key;
        final v = e.value;
        if (k is! String || k.isEmpty || v is! String || v.isEmpty) {
          req('customSymbols has a bad entry');
        }
        customSymbols[k] = v;
      }
    }

    // Optional so backups written before these features still decode.
    final elevenLabsVoices = <SavedElevenLabsVoice>[];
    final rawVoices = json['elevenLabsVoices'];
    if (rawVoices != null) {
      if (rawVoices is! List) req('elevenLabsVoices is malformed');
      for (final e in rawVoices as List) {
        if (e is! Map) req('elevenLabsVoices has a bad entry');
        try {
          elevenLabsVoices.add(
            SavedElevenLabsVoice.fromJson(Map<String, dynamic>.from(e as Map)),
          );
        } on ElevenLabsException {
          req('elevenLabsVoices has a bad entry');
        }
      }
    }

    return ProfileBackup(
      profileId: profileId,
      profileName: profileName,
      exportedAt: DateTime.fromMillisecondsSinceEpoch(exportedAt.toInt()),
      locale: locale,
      speechRate: num01('speechRate'),
      speechPitch: num01('speechPitch'),
      buttonScale: num01('buttonScale'),
      unlockedLevel: unlocked,
      onboardingComplete: onboarding,
      usageCounts: intMap(usage['counts'], 'usage.counts'),
      usageDays: days,
      historyEntries: history,
      planDays: planDays,
      customSymbols: customSymbols,
      elevenLabsVoices: elevenLabsVoices,
    );
  }

  String encode() => json.encode(toJson());

  static ProfileBackup decode(String raw) {
    late final Map<String, dynamic> json;
    try {
      final decoded = jsonDecode(raw);
      if (decoded is! Map) {
        throw const FormatException('top level is not an object');
      }
      json = Map<String, dynamic>.from(decoded);
    } on FormatException catch (e) {
      throw BackupFormatException('File is not valid JSON: ${e.message}');
    }
    return ProfileBackup.fromJson(json);
  }

  int get totalTaps => usageCounts.values.fold(0, (a, b) => a + b);
}

/// Thrown when an import file is corrupt or not a OneVoz backup.
/// Carries a message safe to show the caregiver.
class BackupFormatException implements Exception {
  const BackupFormatException(this.message);
  final String message;
  @override
  String toString() => 'BackupFormatException: $message';
}

/// Builds and applies profile backups against SharedPreferences.
///
/// The prefs factory is injectable so tests can run against
/// `SharedPreferences.setMockInitialValues`. Only keys belonging to the
/// backup's profile id (plus the profile list itself, usage, and — in
/// replace mode — device settings) are ever written; other profiles are
/// never touched.
class ProfileBackupService {
  ProfileBackupService({Future<SharedPreferences> Function()? prefsFactory})
    : _prefsFactory = prefsFactory ?? SharedPreferences.getInstance;

  final Future<SharedPreferences> Function() _prefsFactory;

  static const _kProfiles = 'vidavoice.profiles.v1';
  static const _kUsageCounts = 'vidavoice.usageCounts.v1';
  static const _kUsageDays = 'vidavoice.usageDays.v1';
  static const _kLocale = 'vidavoice.locale';
  static const _kRate = 'vidavoice.speechRate';
  static const _kPitch = 'vidavoice.speechPitch';
  static const _kScale = 'vidavoice.buttonScale';
  static const _kLevel = 'vidavoice.unlockedLevel';
  static const _kOnboarding = 'vidavoice.onboardingComplete';

  static String _historyKey(String profileId) =>
      'vidavoice.history.$profileId.v1';
  static String _planKey(String profileId) =>
      'vidavoice.firstWeekPlan.$profileId.v1';

  /// Reads everything that belongs to [profileId] into a backup.
  Future<ProfileBackup> build(String profileId) async {
    final prefs = await _prefsFactory();
    final profileName = _profileName(prefs, profileId) ?? 'My Voice';

    List<Map<String, dynamic>> history = [];
    final rawHistory = prefs.getString(_historyKey(profileId));
    if (rawHistory != null) {
      try {
        final decoded = json.decode(rawHistory) as List;
        for (final e in decoded) {
          if (e is Map) history.add(Map<String, dynamic>.from(e));
        }
      } on FormatException {
        history = [];
      }
    }

    final planDays = <int>[];
    final rawPlan = prefs.getString(_planKey(profileId));
    if (rawPlan != null) {
      try {
        for (final e in json.decode(rawPlan) as List) {
          final d = (e as num).toInt();
          if (d >= 1 && d <= 7 && !planDays.contains(d)) planDays.add(d);
        }
      } on FormatException {
        planDays.clear();
      }
    }

    Map<String, int> intMap(String key) {
      final out = <String, int>{};
      final raw = prefs.getString(key);
      if (raw == null) return out;
      try {
        (json.decode(raw) as Map).forEach((k, v) {
          if (k is String && v is int && v > 0) out[k] = v;
        });
      } on FormatException {
        out.clear();
      }
      return out;
    }

    final days = <String, Map<String, int>>{};
    final rawDays = prefs.getString(_kUsageDays);
    if (rawDays != null) {
      try {
        (json.decode(rawDays) as Map).forEach((day, bucket) {
          if (day is String && bucket is Map) {
            final b = <String, int>{};
            bucket.forEach((k, v) {
              if (k is String && v is int && v > 0) b[k] = v;
            });
            if (b.isNotEmpty) days[day] = b;
          }
        });
      } on FormatException {
        days.clear();
      }
    }

    return ProfileBackup(
      profileId: profileId,
      profileName: profileName,
      exportedAt: DateTime.now(),
      locale: prefs.getString(_kLocale) ?? 'en',
      speechRate: prefs.getDouble(_kRate) ?? 1.0,
      speechPitch: prefs.getDouble(_kPitch) ?? 1.0,
      buttonScale: prefs.getDouble(_kScale) ?? 1.0,
      unlockedLevel: prefs.getInt(_kLevel) ?? 1,
      onboardingComplete: prefs.getBool(_kOnboarding) ?? false,
      usageCounts: intMap(_kUsageCounts),
      usageDays: days,
      historyEntries: history,
      planDays: planDays,
      customSymbols: await _customSymbols(prefs, profileId),
      elevenLabsVoices: await ElevenLabsVoiceStore(
        prefsFactory: () async => prefs,
      ).load(profileId),
    );
  }

  /// The profile's custom button images, read straight from the override
  /// blob. A corrupt blob yields no symbols rather than failing the backup.
  Future<Map<String, String>> _customSymbols(
    SharedPreferences prefs,
    String profileId,
  ) async {
    final overrides = SymbolOverrideService(prefsFactory: () async => prefs);
    await overrides.load();
    return overrides.sliceFor(profileId);
  }

  /// Writes a backup file into [dir]; returns the file. The file name is
  /// safe for sharing (no spaces or special characters).
  Future<File> writeToDirectory(ProfileBackup backup, Directory dir) async {
    final safeName = backup.profileName
        .toLowerCase()
        .replaceAll(RegExp(r'[^a-z0-9]+'), '-')
        .replaceAll(RegExp(r'^-+|-+$'), '');
    final stamp =
        '${backup.exportedAt.year}'
        '${backup.exportedAt.month.toString().padLeft(2, '0')}'
        '${backup.exportedAt.day.toString().padLeft(2, '0')}';
    final file = File(
      '${dir.path}/onevoz-backup-${safeName.isEmpty ? 'profile' : safeName}-$stamp.json',
    );
    await file.writeAsString(backup.encode(), encoding: utf8);
    return file;
  }

  /// Applies [backup].
  ///
  /// * Replace (`merge: false`): the profile's history, plan, usage,
  ///   custom symbols, saved cloud voices and device settings are
  ///   overwritten with the backup. Returns the device settings so the
  ///   caller can push them through the live session.
  /// * Merge (`merge: true`): usage counts and day buckets are summed,
  ///   history is concatenated (newest first, capped), plan days are
  ///   unioned, custom symbols are unioned (the backup wins on conflict),
  ///   saved cloud voices are unioned by id (the backup wins on conflict),
  ///   device settings are left alone.
  ///
  /// If the backup's profile id is unknown on this device it is added to
  /// the profile list (import onto a fresh device). Nothing belonging to
  /// any other profile is touched.
  Future<ProfileBackup> apply(
    ProfileBackup backup, {
    required bool merge,
  }) async {
    final prefs = await _prefsFactory();
    await _ensureProfile(prefs, backup);
    final overrides = SymbolOverrideService(prefsFactory: () async => prefs);
    await overrides.load();
    final voiceStore = ElevenLabsVoiceStore(prefsFactory: () async => prefs);

    if (merge) {
      await _mergeUsage(prefs, backup);
      await _mergeHistory(prefs, backup);
      await _mergePlan(prefs, backup);
      await overrides.mergeSlice(backup.profileId, backup.customSymbols);
      await _mergeElevenLabsVoices(voiceStore, backup);
    } else {
      await prefs.setString(
        _historyKey(backup.profileId),
        json.encode(backup.historyEntries),
      );
      await prefs.setString(
        _planKey(backup.profileId),
        json.encode(backup.planDays),
      );
      await prefs.setString(_kUsageCounts, json.encode(backup.usageCounts));
      await prefs.setString(_kUsageDays, json.encode(backup.usageDays));
      await overrides.replaceSlice(backup.profileId, backup.customSymbols);
      await voiceStore.save(backup.profileId, backup.elevenLabsVoices);
    }
    return backup;
  }

  /// Unions saved cloud voices by id; the backup wins on conflict.
  Future<void> _mergeElevenLabsVoices(
    ElevenLabsVoiceStore voiceStore,
    ProfileBackup backup,
  ) async {
    final existing = await voiceStore.load(backup.profileId);
    final ids = {for (final v in backup.elevenLabsVoices) v.id};
    await voiceStore.save(backup.profileId, [
      for (final v in existing)
        if (!ids.contains(v.id)) v,
      ...backup.elevenLabsVoices,
    ]);
  }

  String? _profileName(SharedPreferences prefs, String profileId) {
    final raw = prefs.getString(_kProfiles);
    if (raw == null) return null;
    try {
      for (final e in json.decode(raw) as List) {
        final m = Map<String, dynamic>.from(e as Map);
        if (m['id'] == profileId) return m['name'] as String?;
      }
    } on FormatException {
      return null;
    }
    return null;
  }

  Future<void> _ensureProfile(
    SharedPreferences prefs,
    ProfileBackup backup,
  ) async {
    final raw = prefs.getString(_kProfiles);
    List<Map<String, dynamic>> list = [];
    if (raw != null) {
      try {
        list = [
          for (final e in json.decode(raw) as List)
            Map<String, dynamic>.from(e as Map),
        ];
      } on FormatException {
        list = [];
      }
    }
    if (!list.any((m) => m['id'] == backup.profileId)) {
      list.add({'id': backup.profileId, 'name': backup.profileName});
      await prefs.setString(_kProfiles, json.encode(list));
    }
  }

  Future<void> _mergeUsage(
    SharedPreferences prefs,
    ProfileBackup backup,
  ) async {
    final counts = _readIntMap(prefs.getString(_kUsageCounts));
    backup.usageCounts.forEach((k, v) => counts[k] = (counts[k] ?? 0) + v);
    final days = _readDayMap(prefs.getString(_kUsageDays));
    backup.usageDays.forEach((day, bucket) {
      final target = days.putIfAbsent(day, () => <String, int>{});
      bucket.forEach((k, v) => target[k] = (target[k] ?? 0) + v);
    });
    await prefs.setString(_kUsageCounts, json.encode(counts));
    await prefs.setString(_kUsageDays, json.encode(days));
  }

  Future<void> _mergeHistory(
    SharedPreferences prefs,
    ProfileBackup backup,
  ) async {
    final key = _historyKey(backup.profileId);
    final existing = <Map<String, dynamic>>[];
    final raw = prefs.getString(key);
    if (raw != null) {
      try {
        for (final e in json.decode(raw) as List) {
          if (e is Map) existing.add(Map<String, dynamic>.from(e));
        }
      } on FormatException {
        existing.clear();
      }
    }
    final seen = <String>{};
    String sig(Map<String, dynamic> e) =>
        '${e['spokenAt']}|${(e['ids'] as List).join(',')}';
    final merged = <Map<String, dynamic>>[];
    for (final e in [...backup.historyEntries, ...existing]) {
      if (seen.add(sig(e))) merged.add(e);
    }
    merged.sort(
      (a, b) => (b['spokenAt'] as num).compareTo(a['spokenAt'] as num),
    );
    final capped = merged.take(50).toList();
    await prefs.setString(key, json.encode(capped));
  }

  Future<void> _mergePlan(SharedPreferences prefs, ProfileBackup backup) async {
    final key = _planKey(backup.profileId);
    final days = <int>{...backup.planDays};
    final raw = prefs.getString(key);
    if (raw != null) {
      try {
        for (final e in json.decode(raw) as List) {
          final d = (e as num).toInt();
          if (d >= 1 && d <= 7) days.add(d);
        }
      } on FormatException {
        // keep backup days only
      }
    }
    await prefs.setString(key, json.encode(days.toList()));
  }

  Map<String, int> _readIntMap(String? raw) {
    final out = <String, int>{};
    if (raw == null) return out;
    try {
      (json.decode(raw) as Map).forEach((k, v) {
        if (k is String && v is int && v > 0) out[k] = v;
      });
    } on FormatException {
      out.clear();
    }
    return out;
  }

  Map<String, Map<String, int>> _readDayMap(String? raw) {
    final out = <String, Map<String, int>>{};
    if (raw == null) return out;
    try {
      (json.decode(raw) as Map).forEach((day, bucket) {
        if (day is String && bucket is Map) {
          final b = <String, int>{};
          bucket.forEach((k, v) {
            if (k is String && v is int && v > 0) b[k] = v;
          });
          if (b.isNotEmpty) out[day] = b;
        }
      });
    } on FormatException {
      out.clear();
    }
    return out;
  }
}
