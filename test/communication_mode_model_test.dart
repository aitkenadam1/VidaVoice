import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:onevoz/services/profile_backup_service.dart';
import 'package:onevoz/services/profile_service.dart';

/// Phase 1 (communication modes): the shared profile model, migration-safe
/// defaults, and backup export/import of the new fields.
///
/// Conventions: run from the project root with `flutter test`.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  ProfileService service() => ProfileService();

  test('legacy profile JSON (no mode fields) loads with Tap defaults',
      () async {
    SharedPreferences.setMockInitialValues({
      'vidavoice.profiles.v1': json.encode([
        {'id': 'p-1', 'name': 'Alex'},
      ]),
    });
    final svc = service();
    await svc.load();
    final p = svc.active!;
    expect(p.communicationMode, CommunicationMode.tap);
    expect(p.buildMaxSymbols, ProfileService.defaultBuildMaxSymbols);
    expect(p.predictionEnabled, isTrue);
    expect(p.modeNudgePreference, ModeNudgePreference.allowed);
  });

  test('unknown mode strings fall back to Tap, never throw', () async {
    SharedPreferences.setMockInitialValues({
      'vidavoice.profiles.v1': json.encode([
        {
          'id': 'p-1',
          'name': 'Alex',
          'mode': 'telepathy',
          'buildMaxSymbols': 99,
          'predictionEnabled': 'yes',
          'nudgePreference': 'someday',
        },
      ]),
    });
    final svc = service();
    await svc.load();
    final p = svc.active!;
    expect(p.communicationMode, CommunicationMode.tap);
    expect(p.buildMaxSymbols, ProfileService.maxBuildMaxSymbols);
    expect(p.predictionEnabled, isTrue);
    expect(p.modeNudgePreference, ModeNudgePreference.allowed);
  });

  test('full round trip preserves every mode field', () async {
    SharedPreferences.setMockInitialValues({'vidavoice.profiles.v1': '[]'});
    final s = service();
    await s.load();
    final id = s.active!.id;
    await s.setCommunicationMode(id, CommunicationMode.build);
    await s.setBuildMaxSymbols(id, 7);
    await s.setPredictionEnabled(id, false);
    await s.setNudgePreference(id, ModeNudgePreference.off);

    final s2 = service();
    await s2.load();
    final p = s2.active!;
    expect(p.communicationMode, CommunicationMode.build);
    expect(p.buildMaxSymbols, 7);
    expect(p.predictionEnabled, isFalse);
    expect(p.modeNudgePreference, ModeNudgePreference.off);
  });

  test('setBuildMaxSymbols clamps to the allowed range', () async {
    SharedPreferences.setMockInitialValues({'vidavoice.profiles.v1': '[]'});
    final s = service();
    await s.load();
    final id = s.active!.id;
    await s.setBuildMaxSymbols(id, 100);
    expect(s.active!.buildMaxSymbols, ProfileService.maxBuildMaxSymbols);
    await s.setBuildMaxSymbols(id, 0);
    expect(s.active!.buildMaxSymbols, ProfileService.minBuildMaxSymbols);
  });

  test('backup build carries the mode fields; restore applies them',
      () async {
    SharedPreferences.setMockInitialValues({
      'vidavoice.profiles.v1': json.encode([
        {
          'id': 'p-1',
          'name': 'Alex',
          'mode': 'type',
          'buildMaxSymbols': 6,
          'predictionEnabled': false,
          'nudgePreference': 'paused',
        },
      ]),
    });
    final backups = ProfileBackupService();
    final backup = await backups.build('p-1');
    expect(backup.communicationMode, CommunicationMode.type);
    expect(backup.buildMaxSymbols, 6);
    expect(backup.predictionEnabled, isFalse);
    expect(backup.nudgePreference, ModeNudgePreference.paused);

    final encoded = backup.encode();
    final decoded = ProfileBackup.decode(encoded);
    expect(decoded.communicationMode, CommunicationMode.type);
    expect(decoded.buildMaxSymbols, 6);

    // Restore onto a fresh device: the profile list gains the mode fields.
    SharedPreferences.setMockInitialValues({'vidavoice.profiles.v1': '[]'});
    await backups.apply(decoded, merge: false);
    final raw = (await SharedPreferences.getInstance())
        .getString('vidavoice.profiles.v1')!;
    final entry = (json.decode(raw) as List)
        .map((e) => Map<String, dynamic>.from(e as Map))
        .firstWhere((m) => m['id'] == 'p-1');
    expect(entry['mode'], 'type');
    expect(entry['buildMaxSymbols'], 6);
    expect(entry['predictionEnabled'], isFalse);
    expect(entry['nudgePreference'], 'paused');
  });

  test('pre-modes backup JSON still decodes with Tap defaults', () async {
    final legacy = {
      'format': 'vidavoice-profile-backup',
      'version': 1,
      'exportedAt': 1725936000000,
      'profile': {'id': 'p-9', 'name': 'Old'},
      'settings': {
        'locale': 'en',
        'speechRate': 1.0,
        'speechPitch': 1.0,
        'buttonScale': 1.0,
        'unlockedLevel': 1,
        'onboardingComplete': true,
      },
      'usage': {
        'counts': {},
        'days': {},
      },
      'history': [],
      'planDays': [],
    };
    final backup = ProfileBackup.fromJson(legacy);
    expect(backup.communicationMode, CommunicationMode.tap);
    expect(backup.buildMaxSymbols, ProfileService.defaultBuildMaxSymbols);
    expect(backup.predictionEnabled, isTrue);
    expect(backup.nudgePreference, ModeNudgePreference.allowed);
  });
}
