import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/testing.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:onevoz/models/dashboard.dart';
import 'package:onevoz/models/word.dart';
import 'package:onevoz/screens/caregiver_screen.dart';
import 'package:onevoz/screens/onboarding_screen.dart';
import 'package:onevoz/services/elevenlabs_key_store.dart';
import 'package:onevoz/services/profile_service.dart';
import 'package:onevoz/services/proxy_client.dart';
import 'package:onevoz/services/tts_service.dart';
import 'package:onevoz/state/session_state.dart';
import 'package:onevoz/widgets/communication_mode_widgets.dart';

/// Phase 2 (communication modes): mode selection in onboarding and the
/// caregiver hub, the explicit-save contract, and the never-speaking
/// sandbox preview.
///
/// Conventions: run from the project root with `flutter test`.

/// TTS double that records every speak call — the tests assert it stays
/// empty wherever speech must not happen.
class _RecordingTts extends TtsService {
  final List<String> spoken = [];

  @override
  Future<bool> init({
    required String language,
    double rate = 0.5,
    double pitch = 1.0,
  }) async => true;

  @override
  Future<void> setLanguage(String language) async {}

  @override
  Future<void> setRate(double rate) async {}

  @override
  Future<void> setPitch(double pitch) async {}

  @override
  Future<void> speak(String text) async {
    spoken.add(text);
  }

  @override
  Future<List<TtsVoice>> getVoices() async => const [];

  @override
  Future<void> setVoice(TtsVoice voice) async {
    currentVoice = voice;
  }

  @override
  Future<void> clearVoice() async {
    currentVoice = null;
  }
}

/// In-memory keychain double for ProxyAuthStore.
class _FakeSecureStore implements SecureValueStore {
  final map = <String, String>{};

  @override
  Future<String?> read(String key) async => map[key];

  @override
  Future<void> write(String key, String value) async => map[key] = value;

  @override
  Future<void> delete(String key) async => map.remove(key);
}

/// Opens the sandbox preview for one mode. Used instead of re-pumping the
/// app per mode (a stale dialog route survives pumpWidget and silently
/// absorbs taps).
class _PreviewOpener extends StatelessWidget {
  const _PreviewOpener({required this.mode});

  final CommunicationMode mode;

  @override
  Widget build(BuildContext context) {
    return TextButton(
      key: ValueKey('open-preview-${mode.name}'),
      onPressed: () => showModePreviewDialog(context, mode),
      child: Text('Open ${mode.name} preview'),
    );
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  const sectionIds = [
    'level',
    'finder',
    'symbols',
    'profiles',
    'dashboard',
    'plan',
    'activity',
    'usage',
    'tips',
    'data',
    'devices',
    'more',
  ];

  /// Onboarding-capable session: proxy unreachable, account deferrable.
  Future<SessionState> makeOnboardingSession() async {
    SharedPreferences.setMockInitialValues({});
    final session = SessionState(
      tts: _RecordingTts(),
      proxy: ProxyClient(
        client: MockClient((_) async => throw const SocketException('nope')),
        baseUrl: 'https://proxy.test',
      ),
      proxyAuth: ProxyAuthStore(store: _FakeSecureStore()),
    );
    await session.profiles.load();
    return session;
  }

  Future<void> pumpOnboarding(WidgetTester tester, SessionState session) async {
    await tester.pumpWidget(
      ChangeNotifierProvider<SessionState>.value(
        value: session,
        child: const MaterialApp(home: OnboardingScreen()),
      ),
    );
    await tester.pumpAndSettle();
  }

  Future<void> tapFormButton(WidgetTester tester, Finder finder) async {
    await tester.ensureVisible(finder);
    await tester.pumpAndSettle();
    await tester.tap(finder);
    await tester.pumpAndSettle();
  }

  /// Walk welcome → account (defer) → profile → mode, landing on the mode
  /// step without saving anything.
  Future<void> goToModeStep(WidgetTester tester, SessionState session) async {
    await pumpOnboarding(tester, session);
    await tester.tap(find.text('Continue'));
    await tester.pumpAndSettle();
    expect(find.text('Your OneVoz account'), findsOneWidget);
    await tapFormButton(
      tester,
      find.text('Continue with on-device voices for now'),
    );
    expect(find.text('Who will use OneVoz?'), findsOneWidget);
    await tester.tap(find.text('Continue'));
    await tester.pumpAndSettle();
    expect(
      find.text('How does this person communicate best right now?'),
      findsOneWidget,
    );
  }

  group('onboarding mode step', () {
    testWidgets('Skip for now leaves the profile in Tap', (tester) async {
      final session = await makeOnboardingSession();
      await pumpOnboarding(tester, session);
      await tester.tap(find.text('Skip for now'));
      await tester.pumpAndSettle();

      expect(session.onboardingComplete, isTrue);
      expect(
        session.profiles.active!.communicationMode,
        CommunicationMode.tap,
      );
    });

    testWidgets('walking every page without saving leaves Tap', (
      tester,
    ) async {
      final session = await makeOnboardingSession();
      await pumpOnboarding(tester, session);
      // Pages: welcome, account (defer), profile, mode, import, customize,
      // voice, tour. The account page hides the global Continue, so the
      // form's defer button advances it.
      var sawModeStep = false;
      for (var i = 0; i < 8; i++) {
        await tester.pumpAndSettle();
        if (find.text('Your OneVoz account').evaluate().isNotEmpty) {
          await tapFormButton(
            tester,
            find.text('Continue with on-device voices for now'),
          );
        } else if (find
            .text('How does this person communicate best right now?')
            .evaluate()
            .isNotEmpty) {
          // The choice step is genuinely visited — and deliberately left
          // untouched (no "Save mode" press).
          sawModeStep = true;
          await tester.tap(find.text('Continue'));
        } else if (find.text('Start communicating').evaluate().isNotEmpty) {
          await tester.tap(find.text('Start communicating'));
        } else {
          await tester.tap(find.text('Continue'));
        }
      }
      await tester.pumpAndSettle();

      expect(sawModeStep, isTrue);
      expect(session.onboardingComplete, isTrue);
      // No mobility/access step exists in onboarding and nothing derived a
      // mode: the untouched profile is still Tap.
      expect(
        session.profiles.active!.communicationMode,
        CommunicationMode.tap,
      );
    });

    testWidgets('explicit Save mode persists the chosen mode', (
      tester,
    ) async {
      final session = await makeOnboardingSession();
      await goToModeStep(tester, session);

      final option = find.byKey(const ValueKey('mode-option-build'));
      await tester.ensureVisible(option);
      await tester.pumpAndSettle();
      await tester.tap(option);
      await tester.pumpAndSettle();

      final save = find.text('Save mode');
      await tester.ensureVisible(save);
      await tester.pumpAndSettle();
      await tester.tap(save);
      await tester.pumpAndSettle();

      expect(
        session.profiles.active!.communicationMode,
        CommunicationMode.build,
      );
      expect(find.text('Saved: Build mode'), findsOneWidget);

      // The save survives a fresh load.
      final reloaded = ProfileService();
      await reloaded.load();
      expect(reloaded.active!.communicationMode, CommunicationMode.build);
    });

    testWidgets('choosing without saving writes nothing', (tester) async {
      final session = await makeOnboardingSession();
      await goToModeStep(tester, session);

      final option = find.byKey(const ValueKey('mode-option-type'));
      await tester.ensureVisible(option);
      await tester.pumpAndSettle();
      await tester.tap(option);
      await tester.pumpAndSettle();

      // Radio moved, but no explicit save: the profile is untouched.
      expect(
        session.profiles.active!.communicationMode,
        CommunicationMode.tap,
      );
    });
  });

  group('caregiver hub mode editor', () {
    Future<SessionState> makeHubSession({required List<String> collapsed}) async {
      // Seed the saved order too: the hub's upgrade path re-applies the
      // default collapsed state to any section missing from the saved
      // order, which would re-collapse 'profiles'.
      SharedPreferences.setMockInitialValues({
        'vidavoice.caregiver.order': sectionIds,
        'vidavoice.caregiver.collapsed': collapsed,
      });
      final raw = File('assets/lang/en.json').readAsStringSync();
      final pack = LanguagePack.fromJson(
        Map<String, dynamic>.from(json.decode(raw) as Map),
      );
      pack.validate();
      final session = SessionState(tts: _RecordingTts());
      session.pack = pack;
      session.status = BootStatus.ready;
      await session.profiles.load();
      return session;
    }

    testWidgets('save changes only the mode', (tester) async {
      final session = await makeHubSession(
        collapsed: sectionIds.where((id) => id != 'profiles').toList(),
      );
      final id = session.profiles.active!.id;

      // Give the profile real content: a dashboard cell, usage taps, a
      // history entry, and a chosen voice.
      await session.dashboards.load();
      final dash = session.dashboards.ensureFor(id);
      dash.cells.add(
        const DashboardCell(
          id: 'cell-1',
          label: 'Juice',
          speakText: 'juice',
          emoji: '\u{1F9C3}',
        ),
      );
      await session.dashboards.save(dash);
      await session.usage.load();
      await session.usage.recordTap('water');
      await session.history.load(id);
      await session.history.record(id, ['water'], 'water', 'en');
      await session.tts.setVoice(
        const TtsVoice(name: 'Test Voice', locale: 'en-US'),
      );

      final beforeJson = Map<String, dynamic>.from(
        session.profiles.active!.toJson(),
      );
      final cellsBefore = session
          .dashboards
          .forProfile(id)!
          .cells
          .map((c) => c.id)
          .toList();
      final usageBefore = session.usage.countFor('water');
      final historyBefore = session.history.entries.length;
      final voiceBefore = session.tts.currentVoice?.name;

      await tester.pumpWidget(
        ChangeNotifierProvider<SessionState>.value(
          value: session,
          child: const MaterialApp(home: CaregiverScreen()),
        ),
      );
      await tester.pumpAndSettle();

      // Per-profile picker: choose Type for the (only) profile and save.
      final option = find.byKey(const ValueKey('mode-option-type'));
      await tester.scrollUntilVisible(
        option,
        400,
        scrollable: find.byType(Scrollable).first,
      );
      await tester.pumpAndSettle();
      await tester.tap(option);
      await tester.pumpAndSettle();
      expect(find.text('Current: Tap'), findsOneWidget);
      await tester.tap(find.text('Save mode'));
      await tester.pumpAndSettle();

      expect(
        session.profiles.active!.communicationMode,
        CommunicationMode.type,
      );

      // The profile JSON changed in exactly one field...
      final afterJson = Map<String, dynamic>.from(
        session.profiles.active!.toJson(),
      );
      beforeJson.remove('mode');
      afterJson.remove('mode');
      expect(afterJson, beforeJson);

      // ...and everything else the communicator owns is untouched.
      expect(
        session.dashboards.forProfile(id)!.cells.map((c) => c.id).toList(),
        cellsBefore,
      );
      expect(session.usage.countFor('water'), usageBefore);
      expect(session.history.entries.length, historyBefore);
      expect(session.tts.currentVoice?.name, voiceBefore);
    });

    testWidgets('hub shows each profile\u2019s current mode', (tester) async {
      final session = await makeHubSession(
        collapsed: sectionIds.where((id) => id != 'profiles').toList(),
      );
      final id = session.profiles.active!.id;
      await session.profiles.setCommunicationMode(id, CommunicationMode.build);

      await tester.pumpWidget(
        ChangeNotifierProvider<SessionState>.value(
          value: session,
          child: const MaterialApp(home: CaregiverScreen()),
        ),
      );
      await tester.pumpAndSettle();

      await tester.scrollUntilVisible(
        find.text('Current: Build'),
        400,
        scrollable: find.byType(Scrollable).first,
      );
      expect(find.text('Current: Build'), findsOneWidget);
    });
  });

  group('sandbox preview', () {
    testWidgets('try-before-saving never speaks, in any mode', (
      tester,
    ) async {
      final tts = _RecordingTts();
      final session = SessionState(tts: tts);
      await session.profiles.load();

      // One pump for the whole test: re-pumping the app in a loop leaves
      // the previous dialog route stale in the tree, so each mode gets its
      // own opener button on a single screen instead.
      await tester.pumpWidget(
        ChangeNotifierProvider<SessionState>.value(
          value: session,
          child: MaterialApp(
            home: Scaffold(
              body: Column(
                children: [
                  for (final mode in CommunicationMode.values)
                    _PreviewOpener(mode: mode),
                ],
              ),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();

      for (final mode in CommunicationMode.values) {
        final title =
            '${mode.name[0].toUpperCase()}${mode.name.substring(1)} '
            'mode \u2014 preview';
        await tester.tap(find.byKey(ValueKey('open-preview-${mode.name}')));
        await tester.pumpAndSettle();
        expect(find.text(title), findsOneWidget);

        // Exercise every interactive element the sandbox offers.
        switch (mode) {
          case CommunicationMode.tap:
            await tester.tap(
              find.byKey(const ValueKey('sandbox-tile-water')),
            );
            await tester.pumpAndSettle();
          case CommunicationMode.build:
            await tester.tap(find.byKey(const ValueKey('sandbox-add-more')));
            await tester.pumpAndSettle();
            await tester.tap(find.byKey(const ValueKey('sandbox-strip-0')));
            await tester.pumpAndSettle();
          case CommunicationMode.type:
            await tester.tap(
              find.byKey(const ValueKey('sandbox-predict-want')),
            );
            await tester.pumpAndSettle();
        }

        await tester.tap(find.text('Close'));
        await tester.pumpAndSettle();

        expect(
          tts.spoken,
          isEmpty,
          reason: 'sandbox preview for $mode must never call tts.speak',
        );
      }
    });
  });

  group('mode mutation guardrails', () {
    test('only setCommunicationMode changes the mode', () async {
      SharedPreferences.setMockInitialValues({'vidavoice.profiles.v1': '[]'});
      final s = ProfileService();
      await s.load();
      final id = s.active!.id;

      await s.setCommunicationMode(id, CommunicationMode.type);

      // Every other ProfileService path must leave the mode alone.
      await s.renameActive('Sam');
      await s.setBuildMaxSymbols(id, 9);
      await s.setPredictionEnabled(id, false);
      await s.setNudgePreference(id, ModeNudgePreference.off);
      final other = await s.addProfile('Alex');
      await s.setActive(id);
      await s.removeProfile(other.id);

      final kept = s.profiles.firstWhere((p) => p.id == id);
      expect(kept.communicationMode, CommunicationMode.type);
      expect(kept.name, 'Sam');
      expect(kept.buildMaxSymbols, 9);
      // A brand-new profile still starts in Tap.
      SharedPreferences.setMockInitialValues({'vidavoice.profiles.v1': '[]'});
      final fresh = ProfileService();
      await fresh.load();
      expect(fresh.active!.communicationMode, CommunicationMode.tap);
    });
  });
}
