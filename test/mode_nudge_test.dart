import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:onevoz/models/word.dart';
import 'package:onevoz/services/nudge_service.dart';
import 'package:onevoz/services/profile_service.dart';
import 'package:onevoz/services/tts_service.dart';
import 'package:onevoz/state/session_state.dart';
import 'package:onevoz/widgets/communication_mode_widgets.dart';

/// Phase 5 (communication modes): caregiver progression nudges.
///
/// Conventions: run from the project root with `flutter test`.
///
/// DOCUMENTED DESIGN CHOICES pinned by these tests:
/// * Build -> Type eligibility = [ModeNudgeService.buildFullSpeakThreshold]
///   (20) intentional Speak presses with the phrase strip at the
///   caregiver-set maximum length. Partial-strip speaks do NOT count.
/// * Tap -> Build eligibility = [ModeNudgeService.tapSpeakThreshold]
///   (250) intentional Tap-mode speaks. Single taps accumulate fast, so
///   the bar is a couple of weeks of regular use — an optional discovery
///   nudge, not a readiness claim.
/// * Type mode is never eligible (no next mode to preview).
/// * Dismissal and sandbox previews both suppress the nudge for
///   [ModeNudgeService.nudgeCooldownDays] (30) days, then the profile may
///   become eligible again because the counters are kept.
/// * ModeNudgePreference.off is the durable "do not suggest again"; it
///   overrides eligibility forever. Counters are kept so re-allowing
///   later still works.
/// * ModeNudgePreference.paused suppresses display only — eligibility
///   state is preserved so unpausing can surface it without recounting.
/// * Only integer COUNTS are stored; no utterance text ever enters the
///   nudge store, so nothing leaves the device.

UserProfile makeProfile(CommunicationMode mode) {
  final profile = UserProfile(id: 'p-nudge-test', name: 'Test Kid');
  profile.communicationMode = mode;
  return profile;
}

Future<ModeNudgeService> makeService({
  required DateTime Function() clock,
  Map<String, Object>? seed,
}) async {
  SharedPreferences.setMockInitialValues(seed ?? {});
  final svc = ModeNudgeService(clock: clock);
  await svc.load();
  return svc;
}

class _RecordingTts extends TtsService {
  final List<String> spoken = [];

  @override
  Future<bool> init({
    required String language,
    double rate = 0.5,
    double pitch = 1.0,
  }) async => true;

  @override
  Future<void> speak(String text) async {
    spoken.add(text);
  }

  @override
  Future<List<TtsVoice>> getVoices() async => const [];
}

Future<SessionState> makeSession({
  required DateTime Function() clock,
  required CommunicationMode mode,
}) async {
  SharedPreferences.setMockInitialValues({});
  final session = SessionState(tts: _RecordingTts(), nudgeClock: clock);
  session.onboardingComplete = true;
  await session.profiles.load();
  await session.profiles.setCommunicationMode(
    session.profiles.active!.id,
    mode,
  );
  await session.nudge.load();
  return session;
}

BoardItem wordItem(String id, String label) => BoardItem(
  id: id,
  label: label,
  type: BoardItemType.word,
  category: 'test',
  row: 0,
  col: 0,
  emoji: '',
);

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('eligibility', () {
    test('below threshold -> not eligible (build profile)', () async {
      var now = DateTime(2026, 9, 15, 12);
      final svc = await makeService(clock: () => now);
      final profile = makeProfile(CommunicationMode.build);
      for (var i = 0; i < ModeNudgeService.buildFullSpeakThreshold - 1; i++) {
        await svc.recordBuildSpeak(
          profileId: profile.id,
          stripLength: profile.buildMaxSymbols,
          maxLength: profile.buildMaxSymbols,
        );
      }
      expect(svc.suggestionFor(profile), isNull);
    });

    test('threshold reached -> eligible, build suggests type', () async {
      var now = DateTime(2026, 9, 15, 12);
      final svc = await makeService(clock: () => now);
      final profile = makeProfile(CommunicationMode.build);
      for (var i = 0; i < ModeNudgeService.buildFullSpeakThreshold; i++) {
        await svc.recordBuildSpeak(
          profileId: profile.id,
          stripLength: profile.buildMaxSymbols,
          maxLength: profile.buildMaxSymbols,
        );
      }
      final suggestion = svc.suggestionFor(profile);
      expect(suggestion, isNotNull);
      expect(suggestion!.profileId, profile.id);
      expect(suggestion.currentMode, CommunicationMode.build);
      expect(suggestion.targetMode, CommunicationMode.type);
    });

    test('partial-strip speaks do not count toward eligibility', () async {
      var now = DateTime(2026, 9, 15, 12);
      final svc = await makeService(clock: () => now);
      final profile = makeProfile(CommunicationMode.build);
      // Far more partial speaks than the threshold — still not eligible.
      for (var i = 0; i < ModeNudgeService.buildFullSpeakThreshold * 5; i++) {
        await svc.recordBuildSpeak(
          profileId: profile.id,
          stripLength: profile.buildMaxSymbols - 1,
          maxLength: profile.buildMaxSymbols,
        );
      }
      expect(svc.suggestionFor(profile), isNull);
      expect(svc.countsFor(profile.id).buildFullSpeaks, 0);
    });

    test('tap profile: threshold reached -> eligible, tap suggests build',
        () async {
      var now = DateTime(2026, 9, 15, 12);
      final svc = await makeService(clock: () => now);
      final profile = makeProfile(CommunicationMode.tap);
      for (var i = 0; i < ModeNudgeService.tapSpeakThreshold; i++) {
        await svc.recordTapSpeak(profile.id);
      }
      final suggestion = svc.suggestionFor(profile);
      expect(suggestion, isNotNull);
      expect(suggestion!.currentMode, CommunicationMode.tap);
      expect(suggestion.targetMode, CommunicationMode.build);
    });

    test('tap profile: one below threshold -> not eligible', () async {
      var now = DateTime(2026, 9, 15, 12);
      final svc = await makeService(clock: () => now);
      final profile = makeProfile(CommunicationMode.tap);
      for (var i = 0; i < ModeNudgeService.tapSpeakThreshold - 1; i++) {
        await svc.recordTapSpeak(profile.id);
      }
      expect(svc.suggestionFor(profile), isNull);
    });

    test('tap speaks do not make a build profile eligible for tap', () async {
      var now = DateTime(2026, 9, 15, 12);
      final svc = await makeService(clock: () => now);
      final profile = makeProfile(CommunicationMode.build);
      for (var i = 0; i < ModeNudgeService.tapSpeakThreshold; i++) {
        await svc.recordTapSpeak(profile.id);
      }
      expect(svc.suggestionFor(profile), isNull);
    });

    test('type profile is never eligible (no next mode)', () async {
      var now = DateTime(2026, 9, 15, 12);
      final svc = await makeService(clock: () => now);
      final profile = makeProfile(CommunicationMode.type);
      for (var i = 0; i < ModeNudgeService.tapSpeakThreshold; i++) {
        await svc.recordTapSpeak(profile.id);
      }
      for (var i = 0; i < ModeNudgeService.buildFullSpeakThreshold; i++) {
        await svc.recordBuildSpeak(
          profileId: profile.id,
          stripLength: 4,
          maxLength: 4,
        );
      }
      expect(svc.suggestionFor(profile), isNull);
    });

    test('custom buildMaxSymbols is honored: full strip = that length',
        () async {
      var now = DateTime(2026, 9, 15, 12);
      final svc = await makeService(clock: () => now);
      final profile = makeProfile(CommunicationMode.build);
      profile.buildMaxSymbols = 6;
      for (var i = 0; i < ModeNudgeService.buildFullSpeakThreshold; i++) {
        await svc.recordBuildSpeak(
          profileId: profile.id,
          stripLength: 6,
          maxLength: 6,
        );
      }
      expect(svc.suggestionFor(profile), isNotNull);
      // Speaks at the OLD default of 4 would be partial for this profile.
      final svc2 = await makeService(clock: () => now);
      for (var i = 0; i < ModeNudgeService.buildFullSpeakThreshold; i++) {
        await svc2.recordBuildSpeak(
          profileId: 'other',
          stripLength: 4,
          maxLength: 6,
        );
      }
      final other = UserProfile(id: 'other', name: 'Other');
      other.communicationMode = CommunicationMode.build;
      other.buildMaxSymbols = 6;
      expect(svc2.suggestionFor(other), isNull);
    });
  });

  group('state machine', () {
    test('dismissed -> 30-day cooldown, then eligible again', () async {
      var now = DateTime(2026, 9, 15, 12);
      final svc = await makeService(clock: () => now);
      final profile = makeProfile(CommunicationMode.build);
      for (var i = 0; i < ModeNudgeService.buildFullSpeakThreshold; i++) {
        await svc.recordBuildSpeak(
          profileId: profile.id,
          stripLength: profile.buildMaxSymbols,
          maxLength: profile.buildMaxSymbols,
        );
      }
      expect(svc.suggestionFor(profile), isNotNull);

      await svc.dismiss(profile.id);
      expect(svc.suggestionFor(profile), isNull);

      // Day 29 of the cooldown: still suppressed.
      now = now.add(const Duration(days: 29));
      expect(svc.suggestionFor(profile), isNull);

      // Day 30: cooldown expired; counters still satisfy -> eligible again.
      now = now.add(const Duration(days: 1, seconds: 1));
      final again = svc.suggestionFor(profile);
      expect(again, isNotNull);
      expect(again!.targetMode, CommunicationMode.type);
    });

    test('preview behaves like dismissal: cooldown, mode unchanged',
        () async {
      var now = DateTime(2026, 9, 15, 12);
      final svc = await makeService(clock: () => now);
      final profile = makeProfile(CommunicationMode.build);
      for (var i = 0; i < ModeNudgeService.buildFullSpeakThreshold; i++) {
        await svc.recordBuildSpeak(
          profileId: profile.id,
          stripLength: profile.buildMaxSymbols,
          maxLength: profile.buildMaxSymbols,
        );
      }
      expect(svc.suggestionFor(profile), isNotNull);

      await svc.recordPreview(profile.id);
      expect(svc.suggestionFor(profile), isNull);
      expect(profile.communicationMode, CommunicationMode.build);

      // After the cooldown the profile may be suggested again.
      now = now.add(
        Duration(days: ModeNudgeService.nudgeCooldownDays, seconds: 1),
      );
      expect(svc.suggestionFor(profile), isNotNull);
      expect(profile.communicationMode, CommunicationMode.build);
    });

    test('do-not-suggest (off) persists across a simulated restart',
        () async {
      var now = DateTime(2026, 9, 15, 12);
      final seed = <String, Object>{};
      var svc = await makeService(clock: () => now, seed: seed);
      final profile = makeProfile(CommunicationMode.build);
      for (var i = 0; i < ModeNudgeService.buildFullSpeakThreshold; i++) {
        await svc.recordBuildSpeak(
          profileId: profile.id,
          stripLength: profile.buildMaxSymbols,
          maxLength: profile.buildMaxSymbols,
        );
      }
      expect(svc.suggestionFor(profile), isNotNull);

      profile.modeNudgePreference = ModeNudgePreference.off;
      expect(svc.suggestionFor(profile), isNull);

      // Simulated restart: fresh service instance, same prefs store.
      final prefs = await SharedPreferences.getInstance();
      final storedBlob = prefs.getString(ModeNudgeService.storageKey);
      SharedPreferences.setMockInitialValues({
        ModeNudgeService.storageKey: ?storedBlob,
      });
      final restarted = ModeNudgeService(clock: () => now);
      await restarted.load();
      final restartedProfile = makeProfile(CommunicationMode.build);
      restartedProfile.modeNudgePreference = ModeNudgePreference.off;
      expect(restarted.suggestionFor(restartedProfile), isNull);
      // Even far in the future, off overrides eligibility forever.
      final farFuture = ModeNudgeService(
        clock: () => now.add(const Duration(days: 3650)),
      );
      await farFuture.load();
      expect(farFuture.suggestionFor(restartedProfile), isNull);
    });

    test('paused suppresses without erasing eligibility; unpausing resurfaces',
        () async {
      var now = DateTime(2026, 9, 15, 12);
      final svc = await makeService(clock: () => now);
      final profile = makeProfile(CommunicationMode.build);
      for (var i = 0; i < ModeNudgeService.buildFullSpeakThreshold; i++) {
        await svc.recordBuildSpeak(
          profileId: profile.id,
          stripLength: profile.buildMaxSymbols,
          maxLength: profile.buildMaxSymbols,
        );
      }
      expect(svc.suggestionFor(profile), isNotNull);

      profile.modeNudgePreference = ModeNudgePreference.paused;
      expect(svc.suggestionFor(profile), isNull);

      // Unpause: the SAME eligibility state resurfaces — no recounting.
      profile.modeNudgePreference = ModeNudgePreference.allowed;
      expect(svc.suggestionFor(profile), isNotNull);
    });
  });

  group('hard guardrail: nothing changes the mode', () {
    test('full nudge lifecycle never changes communicationMode', () async {
      var now = DateTime(2026, 9, 15, 12);
      final svc = await makeService(clock: () => now);
      final profile = makeProfile(CommunicationMode.build);

      for (var i = 0; i < ModeNudgeService.buildFullSpeakThreshold; i++) {
        await svc.recordBuildSpeak(
          profileId: profile.id,
          stripLength: profile.buildMaxSymbols,
          maxLength: profile.buildMaxSymbols,
        );
      }
      expect(profile.communicationMode, CommunicationMode.build);
      expect(svc.suggestionFor(profile), isNotNull);
      expect(profile.communicationMode, CommunicationMode.build);

      await svc.dismiss(profile.id);
      expect(profile.communicationMode, CommunicationMode.build);

      await svc.recordPreview(profile.id);
      expect(profile.communicationMode, CommunicationMode.build);

      await svc.removeProfile(profile.id);
      expect(profile.communicationMode, CommunicationMode.build);

      // The preference path is durable off, not a mode change.
      profile.modeNudgePreference = ModeNudgePreference.off;
      expect(profile.communicationMode, CommunicationMode.build);
    });

    test('nudge_service.dart source contains no mode-changing code path',
        () {
      var source = File('lib/services/nudge_service.dart').readAsStringSync();
      // Strip comments first: doc comments may legitimately NAME the only
      // allowed mode-changing path (the explicit caregiver save) — what the
      // guardrail pins is that no CODE here calls or performs it.
      source = source.replaceAll(RegExp(r'/\*[\s\S]*?\*/'), '');
      source = source
          .split('\n')
          .where((line) => !line.trimLeft().startsWith('//'))
          .join('\n');
      expect(
        source.contains('setCommunicationMode'),
        isFalse,
        reason:
            'nudge service must never call ProfileService.setCommunicationMode',
      );
      expect(
        RegExp(r'communicationMode\s*=(?![=>])').hasMatch(source),
        isFalse,
        reason: 'nudge service must never assign communicationMode',
      );
    });
  });

  group('privacy: counts only, never utterances', () {
    test('stored blob holds only integer counts — no message text', () async {
      var now = DateTime(2026, 9, 15, 12);
      final svc = await makeService(clock: () => now);
      const profileId = 'p-privacy';
      // Speak events whose composed text is known: 'I want juice please'.
      for (var i = 0; i < 3; i++) {
        await svc.recordBuildSpeak(
          profileId: profileId,
          stripLength: 4,
          maxLength: 4,
        );
      }
      await svc.recordTapSpeak(profileId);
      await svc.dismiss(profileId);

      final prefs = await SharedPreferences.getInstance();
      final raw = prefs.getString(ModeNudgeService.storageKey);
      expect(raw, isNotNull);
      for (final word in ['juice', 'want', 'please', 'I']) {
        expect(
          raw!.contains(word),
          isFalse,
          reason: 'utterance text must never reach the nudge store',
        );
      }
      final decoded = json.decode(raw!) as Map<String, dynamic>;
      final record = Map<String, dynamic>.from(decoded[profileId] as Map);
      expect(record['buildFullSpeaks'], 3);
      expect(record['tapSpeaks'], 1);
      expect(record.keys, everyElement(isIn(<String>{
        'buildFullSpeaks',
        'tapSpeaks',
        'snoozedUntilMillis',
      })));
      for (final value in record.values) {
        expect(value, isA<int>());
      }
    });

    test('nudge service imports no network library (offline by construction)',
        () {
      final source = File(
        'lib/services/nudge_service.dart',
      ).readAsStringSync();
      expect(source.contains('package:http'), isFalse);
      expect(source.contains('dart:io'), isFalse);
    });
  });

  group('migration', () {
    test('pre-nudge profile: no record -> not eligible, no seeded history',
        () async {
      var now = DateTime(2026, 9, 15, 12);
      final svc = await makeService(clock: () => now);
      final profile = makeProfile(CommunicationMode.build);
      expect(svc.suggestionFor(profile), isNull);
      expect(svc.countsFor(profile.id).buildFullSpeaks, 0);
      expect(svc.countsFor(profile.id).tapSpeaks, 0);
    });

    test('pre-modes profile JSON defaults nudge preference to allowed',
        () async {
      final profile = UserProfile.fromJson({
        'id': 'p-old',
        'name': 'Old Profile',
        // No 'nudgePreference' key: written before the modes feature.
      });
      expect(profile.modeNudgePreference, ModeNudgePreference.allowed);
      expect(profile.communicationMode, CommunicationMode.tap);
    });

    test('corrupt nudge blob starts fresh instead of breaking', () async {
      var now = DateTime(2026, 9, 15, 12);
      final svc = await makeService(
        clock: () => now,
        seed: {ModeNudgeService.storageKey: 'not-json{{{'},
      );
      final profile = makeProfile(CommunicationMode.build);
      expect(svc.suggestionFor(profile), isNull);
    });
  });

  group('SessionState wiring', () {
    test('buildSpeak counts only full-strip speaks', () async {
      var now = DateTime(2026, 9, 15, 12);
      final session = await makeSession(
        clock: () => now,
        mode: CommunicationMode.build,
      );
      final id = session.profiles.active!.id;
      final max = session.profiles.active!.buildMaxSymbols;

      // Partial-strip speak: does not count.
      session.buildAdd(wordItem('core.i', 'I'));
      session.buildAdd(wordItem('core.want', 'want'));
      session.buildSpeak();
      expect(session.nudge.countsFor(id).buildFullSpeaks, 0);

      // Full-strip speak: counts.
      session.buildClear();
      for (var i = 0; i < max; i++) {
        session.buildAdd(wordItem('core.word$i', 'word$i'));
      }
      session.buildSpeak();
      // Fire-and-forget recording may still be in flight; settle it.
      await Future<void>.delayed(Duration.zero);
      expect(session.nudge.countsFor(id).buildFullSpeaks, 1);
      final tts = session.tts as _RecordingTts;
      expect(tts.spoken, isNotEmpty);
    });

    test('tapWord in tap mode counts; build mode never counts taps',
        () async {
      var now = DateTime(2026, 9, 15, 12);
      final tapSession = await makeSession(
        clock: () => now,
        mode: CommunicationMode.tap,
      );
      final tapId = tapSession.profiles.active!.id;
      tapSession.tapWord(wordItem('core.want', 'want'));
      await Future<void>.delayed(Duration.zero);
      expect(tapSession.nudge.countsFor(tapId).tapSpeaks, 1);

      final buildSession = await makeSession(
        clock: () => now,
        mode: CommunicationMode.build,
      );
      final buildId = buildSession.profiles.active!.id;
      // In Build mode tapWord is not the speak path (buildSpeak is); even
      // if called directly, the tap-mode counter must not move.
      buildSession.tapWord(wordItem('core.want', 'want'));
      await Future<void>.delayed(Duration.zero);
      expect(buildSession.nudge.countsFor(buildId).tapSpeaks, 0);
    });

    test('removeProfile drops the nudge record', () async {
      var now = DateTime(2026, 9, 15, 12);
      final svc = await makeService(clock: () => now);
      const id = 'p-gone';
      await svc.recordTapSpeak(id);
      expect(svc.countsFor(id).tapSpeaks, 1);
      await svc.removeProfile(id);
      expect(svc.countsFor(id).tapSpeaks, 0);
    });
  });

  group('nudge preference editor', () {
    Future<SessionState> makeHubSession() async {
      SharedPreferences.setMockInitialValues({});
      final session = SessionState(
        tts: _RecordingTts(),
        nudgeClock: () => DateTime(2026, 9, 15, 12),
      );
      await session.profiles.load();
      return session;
    }

    Future<void> pumpEditor(WidgetTester tester, SessionState session) async {
      final id = session.profiles.active!.id;
      await tester.pumpWidget(
        ChangeNotifierProvider<SessionState>.value(
          value: session,
          child: MaterialApp(
            home: Scaffold(
              body: NudgePreferenceEditor(profileId: id),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
    }

    testWidgets('Save is disabled while the draft matches the saved value',
        (tester) async {
      final session = await makeHubSession();
      await pumpEditor(tester, session);
      expect(find.text('Progression suggestions'), findsOneWidget);
      final save = find.widgetWithText(FilledButton, 'Save');
      expect(tester.widget<FilledButton>(save).enabled, isFalse);
    });

    testWidgets('explicit Save persists the new preference', (tester) async {
      final session = await makeHubSession();
      await pumpEditor(tester, session);

      await tester.tap(find.text('Off'));
      await tester.pumpAndSettle();
      final save = find.widgetWithText(FilledButton, 'Save');
      expect(tester.widget<FilledButton>(save).enabled, isTrue);
      await tester.tap(save);
      await tester.pumpAndSettle();

      expect(
        session.profiles.active!.modeNudgePreference,
        ModeNudgePreference.off,
      );
      // Draft now matches the saved value, so Save disables again.
      expect(tester.widget<FilledButton>(save).enabled, isFalse);
    });

    testWidgets('a declined preference can be re-enabled from the hub',
        (tester) async {
      final session = await makeHubSession();
      final id = session.profiles.active!.id;
      await session.profiles.setNudgePreference(id, ModeNudgePreference.off);
      await pumpEditor(tester, session);

      await tester.tap(find.text('On'));
      await tester.pumpAndSettle();
      await tester.tap(find.widgetWithText(FilledButton, 'Save'));
      await tester.pumpAndSettle();

      expect(
        session.profiles.active!.modeNudgePreference,
        ModeNudgePreference.allowed,
      );
    });

    testWidgets('Pausing suppresses the suggestion without erasing counts',
        (tester) async {
      final svc = ModeNudgeService(clock: () => DateTime(2026, 9, 15, 12));
      await svc.load();
      final profile = makeProfile(CommunicationMode.build);
      for (var i = 0; i < ModeNudgeService.buildFullSpeakThreshold; i++) {
        await svc.recordBuildSpeak(
          profileId: profile.id,
          stripLength: 4,
          maxLength: 4,
        );
      }
      profile.modeNudgePreference = ModeNudgePreference.paused;
      expect(svc.suggestionFor(profile), isNull);

      profile.modeNudgePreference = ModeNudgePreference.allowed;
      final suggestion = svc.suggestionFor(profile);
      expect(suggestion, isNotNull);
      expect(suggestion!.targetMode, CommunicationMode.type);
    });
  });
}
