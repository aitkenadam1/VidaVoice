import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:onevoz/services/elevenlabs_service.dart';
import 'package:onevoz/services/elevenlabs_voice_store.dart';
import 'package:onevoz/services/profile_backup_service.dart';
import 'package:onevoz/services/profile_service.dart';

void main() {
  const maya = SavedElevenLabsVoice(id: 'cv-1', name: 'Maya', locale: 'en');
  const narrator = SavedElevenLabsVoice(
    id: 'v-9',
    name: 'Narrator',
    locale: 'en',
  );

  ProfileBackupService service() => ProfileBackupService();
  ElevenLabsVoiceStore voiceStore() => ElevenLabsVoiceStore();

  ProfileBackup sampleBackup(List<SavedElevenLabsVoice> voices) =>
      ProfileBackup(
        profileId: 'p-1',
        profileName: 'Alex',
        exportedAt: DateTime(2026, 9, 15),
        locale: 'en',
        speechRate: 1.0,
        speechPitch: 1.0,
        buttonScale: 1.0,
        unlockedLevel: 1,
        onboardingComplete: true,
        usageCounts: const {},
        usageDays: const {},
        historyEntries: const [],
        planDays: const [],
        customSymbols: const {},
        elevenLabsVoices: voices,
        communicationMode: CommunicationMode.tap,
        buildMaxSymbols: 4,
        predictionEnabled: true,
        nudgePreference: ModeNudgePreference.allowed,
      );

  setUp(() {
    // Reset before every test: the mock store is rebuilt from these values.
    SharedPreferences.setMockInitialValues({
      'vidavoice.profiles.v1': json.encode([
        {'id': 'p-1', 'name': 'Alex'},
        {'id': 'p-2', 'name': 'Sam'},
      ]),
    });
  });

  test('build captures the profile\'s cloud voices only', () async {
    await voiceStore().add('p-1', maya);
    await voiceStore().add('p-2', narrator);
    final backup = await service().build('p-1');
    expect(backup.elevenLabsVoices.map((v) => v.id), ['cv-1']);
  });

  test('replace restore overwrites the profile\'s cloud voices', () async {
    await voiceStore().add('p-1', narrator);
    await voiceStore().add('p-2', narrator);
    await service().apply(sampleBackup([maya]), merge: false);
    expect((await voiceStore().load('p-1')).map((v) => v.id), ['cv-1']);
    // Other profiles untouched.
    expect((await voiceStore().load('p-2')).map((v) => v.id), ['v-9']);
  });

  test('merge unions by id, backup wins on conflict', () async {
    await voiceStore().add(
      'p-1',
      const SavedElevenLabsVoice(id: 'cv-1', name: 'Old name', locale: 'en'),
    );
    await voiceStore().add('p-1', narrator);
    await service().apply(sampleBackup([maya]), merge: true);
    final loaded = await voiceStore().load('p-1');
    expect(loaded.map((v) => v.id).toSet(), {'cv-1', 'v-9'});
    expect(loaded.firstWhere((v) => v.id == 'cv-1').name, 'Maya');
  });

  test('backups without the field decode with an empty voice list', () {
    final map = Map<String, dynamic>.from(sampleBackup([maya]).toJson())
      ..remove('elevenLabsVoices');
    final backup = ProfileBackup.decode(json.encode(map));
    expect(backup.elevenLabsVoices, isEmpty);
  });

  test('malformed voice entries are rejected', () {
    final map = Map<String, dynamic>.from(sampleBackup([maya]).toJson())
      ..['elevenLabsVoices'] = [
        {'id': '', 'name': 'x'},
      ];
    expect(
      () => ProfileBackup.decode(json.encode(map)),
      throwsA(isA<BackupFormatException>()),
    );
  });
}
