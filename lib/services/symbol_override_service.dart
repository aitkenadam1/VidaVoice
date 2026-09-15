import 'dart:convert';

import 'package:shared_preferences/shared_preferences.dart';

/// Per-profile image overrides for standard vocabulary buttons and quick
/// phrases.
///
/// The standard board is shared: its ARASAAC pictograms and emoji are the
/// same for every profile. A caregiver can still give *their* communicator
/// a personal symbol for any word or phrase — a photo of their own cup, a
/// family picture for "grandma" — without changing what any other profile
/// sees. Overrides are keyed by the canonical item id, so they survive
/// language switches.
///
/// Storage: one JSON blob in SharedPreferences,
/// `{profileId: {itemId: base64Image}}`. Images are expected to come from
/// [ButtonImage.prepare], already downscaled.
class SymbolOverrideService {
  SymbolOverrideService({Future<SharedPreferences> Function()? prefsFactory})
    : _prefsFactory = prefsFactory ?? SharedPreferences.getInstance;

  final Future<SharedPreferences> Function() _prefsFactory;

  static const storageKey = 'vidavoice.symbol_overrides.v1';

  final Map<String, Map<String, String>> _overrides = {};

  Future<void> load() async {
    _overrides.clear();
    final prefs = await _prefsFactory();
    final raw = prefs.getString(storageKey);
    if (raw == null || raw.isEmpty) return;
    try {
      final decoded = json.decode(raw);
      if (decoded is! Map) return;
      for (final profileEntry in decoded.entries) {
        final profileId = profileEntry.key;
        final items = profileEntry.value;
        if (profileId is! String || items is! Map) continue;
        final bucket = <String, String>{};
        for (final itemEntry in items.entries) {
          final itemId = itemEntry.key;
          final data = itemEntry.value;
          if (itemId is String &&
              itemId.isNotEmpty &&
              data is String &&
              data.isNotEmpty) {
            bucket[itemId] = data;
          }
        }
        if (bucket.isNotEmpty) _overrides[profileId] = bucket;
      }
    } catch (_) {
      // Corrupt blob: start empty rather than failing boot.
      _overrides.clear();
    }
  }

  /// The override image for [itemId] on [profileId], or null when the
  /// standard symbol applies.
  String? imageFor(String profileId, String itemId) =>
      _overrides[profileId]?[itemId];

  bool has(String profileId, String itemId) =>
      _overrides[profileId]?.containsKey(itemId) ?? false;

  /// How many overrides [profileId] currently has (for caregiver UI
  /// summaries).
  int countFor(String profileId) => _overrides[profileId]?.length ?? 0;

  Future<void> set(String profileId, String itemId, String base64Image) async {
    final bucket = _overrides.putIfAbsent(profileId, () => {});
    bucket[itemId] = base64Image;
    await _persist();
  }

  Future<void> remove(String profileId, String itemId) async {
    final bucket = _overrides[profileId];
    if (bucket == null) return;
    bucket.remove(itemId);
    if (bucket.isEmpty) _overrides.remove(profileId);
    await _persist();
  }

  /// A copy of the profile's overrides (itemId -> base64 image). Used by
  /// profile backup/restore.
  Map<String, String> sliceFor(String profileId) =>
      Map<String, String>.from(_overrides[profileId] ?? const {});

  /// Replaces the profile's overrides wholesale (backup restore in replace
  /// mode). An empty slice clears the profile's overrides.
  Future<void> replaceSlice(String profileId, Map<String, String> slice) async {
    if (slice.isEmpty) {
      _overrides.remove(profileId);
    } else {
      _overrides[profileId] = Map<String, String>.from(slice);
    }
    await _persist();
  }

  /// Unions [slice] into the profile's overrides; incoming entries win on
  /// key conflict (backup merge mode).
  Future<void> mergeSlice(String profileId, Map<String, String> slice) async {
    if (slice.isEmpty) return;
    final bucket = _overrides.putIfAbsent(profileId, () => {});
    bucket.addAll(slice);
    await _persist();
  }

  /// Drops everything stored for [profileId]. Call when the profile is
  /// deleted so orphaned image blobs don't accumulate.
  Future<void> removeProfile(String profileId) async {
    if (_overrides.remove(profileId) != null) await _persist();
  }

  Future<void> _persist() async {
    final prefs = await _prefsFactory();
    await prefs.setString(storageKey, json.encode(_overrides));
  }
}
