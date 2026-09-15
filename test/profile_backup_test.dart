import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:onevoz/services/profile_backup_service.dart';
import 'package:onevoz/services/profile_service.dart';
import 'package:onevoz/state/session_state.dart';
import 'package:onevoz/widgets/backup_section.dart';

/// Tests for profile backup/restore: serialization, validation of corrupt
/// files, replace/merge import, and the widget import flow with a fake
/// file layer. Run from the project root: `flutter test`.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  ProfileBackup sampleBackup() => ProfileBackup(
    profileId: 'p-1',
    profileName: 'Alex',
    exportedAt: DateTime(2026, 9, 10),
    locale: 'es',
    speechRate: 0.9,
    speechPitch: 1.1,
    buttonScale: 1.2,
    unlockedLevel: 2,
    onboardingComplete: true,
    usageCounts: {'core.want': 5, 'core.go': 3},
    usageDays: {
      '2026-09-10': {'core.want': 5},
    },
    historyEntries: [
      {
        'ids': ['core.i', 'core.want', 'food.juice'],
        'text': 'I want juice',
        'locale': 'es',
        'spokenAt': 1725936000000,
      },
    ],
    planDays: [1, 2],
    customSymbols: const {},
    elevenLabsVoices: const [],
    communicationMode: CommunicationMode.tap,
    buildMaxSymbols: 4,
    predictionEnabled: true,
    nudgePreference: ModeNudgePreference.allowed,
  );

  Map<String, Object> seedPrefs() => {
    'vidavoice.profiles.v1': json.encode([
      {'id': 'p-1', 'name': 'Alex'},
      {'id': 'p-2', 'name': 'Sam'},
    ]),
    'vidavoice.history.p-1.v1': json.encode([
      {
        'ids': ['core.yes'],
        'text': 'yes',
        'locale': 'en',
        'spokenAt': 1725900000000,
      },
    ]),
    'vidavoice.history.p-2.v1': json.encode([
      {
        'ids': ['core.no'],
        'text': 'no',
        'locale': 'en',
        'spokenAt': 1725900000000,
      },
    ]),
    'vidavoice.firstWeekPlan.p-1.v1': json.encode([3]),
    'vidavoice.usageCounts.v1': json.encode({'core.want': 2, 'core.no': 7}),
    'vidavoice.usageDays.v1': json.encode({
      '2026-09-10': {'core.no': 7},
    }),
    'vidavoice.locale': 'en',
    'vidavoice.unlockedLevel': 3,
  };

  group('ProfileBackup encode/decode', () {
    test('round-trips through JSON', () {
      final decoded = ProfileBackup.decode(sampleBackup().encode());
      expect(decoded.profileId, 'p-1');
      expect(decoded.profileName, 'Alex');
      expect(decoded.locale, 'es');
      expect(decoded.speechRate, 0.9);
      expect(decoded.usageCounts, {'core.want': 5, 'core.go': 3});
      expect(decoded.historyEntries.single['text'], 'I want juice');
      expect(decoded.planDays, [1, 2]);
      expect(decoded.totalTaps, 8);
    });

    test('rejects garbage that is not JSON', () {
      expect(
        () => ProfileBackup.decode('this is not json {{{'),
        throwsA(isA<BackupFormatException>()),
      );
    });

    test('rejects valid JSON that is not a backup', () {
      expect(
        () => ProfileBackup.decode('{"hello": "world"}'),
        throwsA(isA<BackupFormatException>()),
      );
    });

    test('rejects wrong format marker and version', () {
      final json = sampleBackup().toJson();
      json['format'] = 'something-else';
      expect(
        () => ProfileBackup.fromJson(json),
        throwsA(isA<BackupFormatException>()),
      );
      final json2 = sampleBackup().toJson()..['version'] = 99;
      expect(
        () => ProfileBackup.fromJson(json2),
        throwsA(isA<BackupFormatException>()),
      );
    });

    test('rejects malformed history entries and plan days', () {
      final badHistory = sampleBackup().toJson()
        ..['history'] = [
          {'ids': 'not-a-list', 'text': 'x', 'locale': 'en', 'spokenAt': 1},
        ];
      expect(
        () => ProfileBackup.fromJson(badHistory),
        throwsA(isA<BackupFormatException>()),
      );
      final badPlan = sampleBackup().toJson()..['planDays'] = [1, 9];
      expect(
        () => ProfileBackup.fromJson(badPlan),
        throwsA(isA<BackupFormatException>()),
      );
      final badCounts = sampleBackup().toJson()
        ..['usage'] = {
          'counts': {'core.want': -3},
          'days': {},
        };
      expect(
        () => ProfileBackup.fromJson(badCounts),
        throwsA(isA<BackupFormatException>()),
      );
    });
  });

  group('ProfileBackupService', () {
    setUp(() {
      SharedPreferences.setMockInitialValues(seedPrefs());
    });

    test('build() captures profile data, usage and settings', () async {
      final service = ProfileBackupService();
      final backup = await service.build('p-1');
      expect(backup.profileName, 'Alex');
      expect(backup.historyEntries.single['text'], 'yes');
      expect(backup.planDays, [3]);
      expect(backup.usageCounts['core.no'], 7);
      expect(backup.unlockedLevel, 3);
      expect(backup.locale, 'en');
    });

    test(
      'apply() replace overwrites profile data, keeps other profiles',
      () async {
        final service = ProfileBackupService();
        await service.apply(sampleBackup(), merge: false);
        final prefs = await SharedPreferences.getInstance();

        // p-1 replaced with backup content
        final history =
            json.decode(prefs.getString('vidavoice.history.p-1.v1')!) as List;
        expect(history.single['text'], 'I want juice');
        expect(
          json.decode(prefs.getString('vidavoice.firstWeekPlan.p-1.v1')!),
          [1, 2],
        );
        expect(json.decode(prefs.getString('vidavoice.usageCounts.v1')!), {
          'core.want': 5,
          'core.go': 3,
        });

        // p-2 untouched
        final other =
            json.decode(prefs.getString('vidavoice.history.p-2.v1')!) as List;
        expect(other.single['text'], 'no');
      },
    );

    test(
      'apply() merge sums usage, unions plan, concatenates history',
      () async {
        final service = ProfileBackupService();
        await service.apply(sampleBackup(), merge: true);
        final prefs = await SharedPreferences.getInstance();

        final counts =
            json.decode(prefs.getString('vidavoice.usageCounts.v1')!) as Map;
        expect(counts['core.want'], 7); // 2 existing + 5 backup
        expect(counts['core.no'], 7); // untouched
        expect(counts['core.go'], 3); // new from backup

        final plan = json.decode(
          prefs.getString('vidavoice.firstWeekPlan.p-1.v1')!,
        ) as List;
        expect(Set.from(plan), {1, 2, 3});

        final history =
            json.decode(prefs.getString('vidavoice.history.p-1.v1')!) as List;
        expect(history.length, 2);
        // newest first
        expect(history.first['text'], 'I want juice');

        // device settings left alone in merge mode
        expect(prefs.getString('vidavoice.locale'), 'en');
        expect(prefs.getInt('vidavoice.unlockedLevel'), 3);
      },
    );

    test('apply() adds an unknown profile to the profile list', () async {
      SharedPreferences.setMockInitialValues({
        'vidavoice.profiles.v1': json.encode([
          {'id': 'p-9', 'name': 'Other'},
        ]),
      });
      final service = ProfileBackupService();
      await service.apply(sampleBackup(), merge: false);
      final prefs = await SharedPreferences.getInstance();
      final profiles =
          json.decode(prefs.getString('vidavoice.profiles.v1')!) as List;
      expect(profiles.any((p) => p['id'] == 'p-1'), isTrue);
      expect(profiles.any((p) => p['id'] == 'p-9'), isTrue);
      // and its data landed
      expect(prefs.getString('vidavoice.history.p-1.v1'), isNotNull);
    });

    test('writeToDirectory produces a shareable, decodable file', () async {
      final service = ProfileBackupService();
      final dir = await Directory.systemTemp.createTemp('vidavoice-test');
      final file = await service.writeToDirectory(sampleBackup(), dir);
      expect(file.path.endsWith('.json'), isTrue);
      expect(file.path.contains(' '), isFalse);
      final decoded = ProfileBackup.decode(await file.readAsString());
      expect(decoded.profileName, 'Alex');
      await dir.delete(recursive: true);
    });
  });

  group('BackupSection widget', () {
    Future<SessionState> makeSession() async {
      SharedPreferences.setMockInitialValues(seedPrefs());
      final session = SessionState();
      await session.profiles.load();
      return session;
    }

    Future<String> writeTempFile(String contents) async {
      final dir = await Directory.systemTemp.createTemp('vidavoice-test');
      final file = File('${dir.path}/backup.json');
      await file.writeAsString(contents);
      return file.path;
    }

    testWidgets('import with merge restores data and shows confirmation', (
      tester,
    ) async {
      final session = await makeSession();
      final path = await writeTempFile(sampleBackup().encode());
      var imported = false;

      await tester.pumpWidget(
        ChangeNotifierProvider.value(
          value: session,
          child: MaterialApp(
            home: Scaffold(
              body: BackupSection(
                pickFile: () async => path,
                onImported: () async {
                  imported = true;
                },
              ),
            ),
          ),
        ),
      );

      await tester.tap(find.text('Import backup'));
      await tester.pumpAndSettle();
      // Confirmation dialog summarizes the backup.
      expect(find.text('Restore backup?'), findsOneWidget);
      expect(find.textContaining('Alex'), findsWidgets);

      await tester.tap(find.text('Merge'));
      await tester.pumpAndSettle();

      expect(imported, isTrue);
      expect(find.textContaining('merged'), findsOneWidget);
      final prefs = await SharedPreferences.getInstance();
      final counts =
          json.decode(prefs.getString('vidavoice.usageCounts.v1')!) as Map;
      expect(counts['core.want'], 7);
    });

    testWidgets('corrupt import file shows an error and touches nothing', (
      tester,
    ) async {
      final session = await makeSession();
      final path = await writeTempFile('definitely not a backup {{{');

      await tester.pumpWidget(
        ChangeNotifierProvider.value(
          value: session,
          child: MaterialApp(
            home: Scaffold(body: BackupSection(pickFile: () async => path)),
          ),
        ),
      );

      await tester.tap(find.text('Import backup'));
      await tester.pumpAndSettle();

      // No confirmation dialog — straight to the error.
      expect(find.text('Restore backup?'), findsNothing);
      expect(find.byType(SnackBar), findsOneWidget);
      final prefs = await SharedPreferences.getInstance();
      final counts =
          json.decode(prefs.getString('vidavoice.usageCounts.v1')!) as Map;
      expect(counts, {'core.want': 2, 'core.no': 7});
    });
  });
}
