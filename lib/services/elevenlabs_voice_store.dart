import 'dart:convert';

import 'package:shared_preferences/shared_preferences.dart';

import 'elevenlabs_service.dart';

/// Per-profile saved ElevenLabs voices (cloned voices and library voices
/// the caregiver picked). The voice ids only resolve against the
/// caregiver's ElevenLabs account — without an API key they are inert, and
/// speech falls back to on-device voices.
class ElevenLabsVoiceStore {
  ElevenLabsVoiceStore({Future<SharedPreferences> Function()? prefsFactory})
    : _prefsFactory = prefsFactory ?? SharedPreferences.getInstance;

  final Future<SharedPreferences> Function() _prefsFactory;

  static String _key(String profileId) =>
      'vidavoice.elevenlabs.voices.$profileId.v1';

  Future<List<SavedElevenLabsVoice>> load(String profileId) async {
    final prefs = await _prefsFactory();
    final raw = prefs.getString(_key(profileId));
    if (raw == null || raw.isEmpty) return const [];
    try {
      final decoded = json.decode(raw);
      if (decoded is! List) return const [];
      return [
        for (final e in decoded)
          if (e is Map<String, dynamic>) SavedElevenLabsVoice.fromJson(e),
      ];
    } catch (_) {
      // Corrupt entry: no saved voices rather than a broken picker.
      return const [];
    }
  }

  Future<void> save(String profileId, List<SavedElevenLabsVoice> voices) async {
    final prefs = await _prefsFactory();
    await prefs.setString(
      _key(profileId),
      json.encode(voices.map((v) => v.toJson()).toList()),
    );
  }

  /// Adds [voice], replacing any saved entry with the same id.
  Future<void> add(String profileId, SavedElevenLabsVoice voice) async {
    final voices = await load(profileId);
    final next = [
      for (final v in voices)
        if (v.id != voice.id) v,
      voice,
    ];
    await save(profileId, next);
  }

  Future<void> remove(String profileId, String voiceId) async {
    final voices = await load(profileId);
    final next = [
      for (final v in voices)
        if (v.id != voiceId) v,
    ];
    if (next.length != voices.length) await save(profileId, next);
  }

  /// Drops every saved voice for [profileId] (profile deletion).
  Future<void> clearProfile(String profileId) async {
    final prefs = await _prefsFactory();
    await prefs.remove(_key(profileId));
  }
}
