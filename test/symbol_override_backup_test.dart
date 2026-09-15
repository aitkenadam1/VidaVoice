import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:onevoz/services/profile_backup_service.dart';
import 'package:onevoz/services/profile_service.dart';
import 'package:onevoz/services/symbol_override_service.dart';

/// Custom button images ride along with profile backup/restore and are
/// cleaned up when a profile is deleted.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  ProfileBackupService backups() =>
      ProfileBackupService(prefsFactory: SharedPreferences.getInstance);
  SymbolOverrideService overrides() =>
      SymbolOverrideService(prefsFactory: SharedPreferences.getInstance);

  ProfileBackup sampleBackup(Map<String, String> symbols) => ProfileBackup(
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
    customSymbols: symbols,
    elevenLabsVoices: const [],
    communicationMode: CommunicationMode.tap,
    buildMaxSymbols: 4,
    predictionEnabled: true,
    nudgePreference: ModeNudgePreference.allowed,
  );

  test('build captures only the profile\'s custom symbols', () async {
    SharedPreferences.setMockInitialValues({});
    final ov = overrides();
    await ov.load();
    await ov.set('p-1', 'w_eat', 'img-eat');
    await ov.set('p-1', 'w_drink', 'img-drink');
    await ov.set('p-2', 'w_eat', 'img-other-profile');

    final backup = await backups().build('p-1');
    expect(backup.customSymbols, {'w_eat': 'img-eat', 'w_drink': 'img-drink'});
  });

  test('build with no overrides yields empty custom symbols', () async {
    SharedPreferences.setMockInitialValues({});
    final backup = await backups().build('p-1');
    expect(backup.customSymbols, isEmpty);
  });

  test(
    'replace apply restores custom symbols; other profiles untouched',
    () async {
      SharedPreferences.setMockInitialValues({});
      final ov = overrides();
      await ov.load();
      await ov.set('p-1', 'w_old', 'stale');
      await ov.set('p-2', 'w_eat', 'img-other-profile');

      await backups().apply(sampleBackup({'w_eat': 'img-eat'}), merge: false);

      final after = overrides();
      await after.load();
      expect(after.sliceFor('p-1'), {'w_eat': 'img-eat'});
      expect(after.sliceFor('p-2'), {'w_eat': 'img-other-profile'});
    },
  );

  test(
    'merge apply unions symbols with the backup winning conflicts',
    () async {
      SharedPreferences.setMockInitialValues({});
      final ov = overrides();
      await ov.load();
      await ov.set('p-1', 'w_eat', 'old-img');
      await ov.set('p-1', 'w_drink', 'keep-img');

      await backups().apply(
        sampleBackup({'w_eat': 'new-img', 'w_sleep': 'added-img'}),
        merge: true,
      );

      final after = overrides();
      await after.load();
      expect(after.sliceFor('p-1'), {
        'w_eat': 'new-img',
        'w_drink': 'keep-img',
        'w_sleep': 'added-img',
      });
    },
  );

  test('custom symbols survive an encode/decode round trip', () async {
    final backup = sampleBackup({'w_eat': 'img-eat'});
    final decoded = ProfileBackup.decode(backup.encode());
    expect(decoded.customSymbols, {'w_eat': 'img-eat'});
  });

  test('backups written before custom symbols decode to empty', () async {
    final backup = sampleBackup({'w_eat': 'img-eat'});
    // Simulate an old backup file: real JSON, minus the customSymbols key.
    final raw = json.decode(backup.encode()) as Map<String, dynamic>;
    raw.remove('customSymbols');
    final decoded = ProfileBackup.decode(json.encode(raw));
    expect(decoded.customSymbols, isEmpty);
  });

  test('malformed customSymbols block is rejected', () async {
    final backup = sampleBackup({});
    final raw = json.decode(backup.encode()) as Map<String, dynamic>;
    raw['customSymbols'] = {'w_eat': 42};
    expect(
      () => ProfileBackup.decode(json.encode(raw)),
      throwsA(isA<BackupFormatException>()),
    );
  });

  test('removeProfile drops the profile\'s slice and persists', () async {
    SharedPreferences.setMockInitialValues({});
    final ov = overrides();
    await ov.load();
    await ov.set('p-1', 'w_eat', 'img-eat');
    await ov.set('p-2', 'w_drink', 'img-drink');

    await ov.removeProfile('p-1');

    expect(ov.sliceFor('p-1'), isEmpty);
    expect(ov.sliceFor('p-2'), {'w_drink': 'img-drink'});

    final reloaded = overrides();
    await reloaded.load();
    expect(reloaded.sliceFor('p-1'), isEmpty);
    expect(reloaded.sliceFor('p-2'), {'w_drink': 'img-drink'});
  });
}
