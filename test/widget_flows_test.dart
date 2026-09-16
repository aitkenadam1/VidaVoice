import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:onevoz/main.dart';
import 'package:onevoz/models/word.dart';
import 'package:onevoz/screens/caregiver_screen.dart';
import 'package:onevoz/services/elevenlabs_key_store.dart';
import 'package:onevoz/services/caregiver_pin_service.dart';
import 'package:onevoz/services/proxy_client.dart';
import 'package:onevoz/services/tts_service.dart';
import 'package:onevoz/state/session_state.dart';

class _FakeTts extends TtsService {
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
  Future<void> speak(String text) async {}
  @override
  Future<List<TtsVoice>> getVoices() async => const [];

  @override
  Future<void> setVoice(TtsVoice voice) async {}

  @override
  Future<void> clearVoice() async {}
}

/// Widget coverage for the flows in docs/MORNING-TEST.md that had no
/// coverage: folder open/return, onboarding complete/skip, Spanish label
/// rendering, and level-2 unlock mid-session.
/// In-memory keychain double: on desktop test runners the real secure
/// storage backend hangs instead of completing, so widget tests that run
/// the real signup flow inject this through SessionState.
class _FakeSecureStore implements SecureValueStore {
  final map = <String, String>{};

  @override
  Future<String?> read(String key) async => map[key];

  @override
  Future<void> write(String key, String value) async => map[key] = value;

  @override
  Future<void> delete(String key) async => map.remove(key);
}

void main() {

/// The hub sits behind the caregiver PIN gate (PIN pre-set before the hub
/// pumps): unlock via the on-screen pad.
Future<void> unlockGate(WidgetTester tester) async {
  await tester.pumpAndSettle();
  for (final ch in '1234'.split('')) {
    await tester.tap(find.text(ch));
    await tester.pump(const Duration(milliseconds: 50));
  }
  await tester.pumpAndSettle();
}

  LanguagePack loadPackFromFile(String locale) {
    final raw = File('assets/lang/$locale.json').readAsStringSync();
    final pack = LanguagePack.fromJson(
      Map<String, dynamic>.from(json.decode(raw) as Map),
    );
    pack.validate();
    return pack;
  }

  Future<SessionState> makeSession({
    String locale = 'en',
    bool onboardingComplete = true,
    ProxyClient? proxy,
    bool signedIn = true,
  }) async {
    SharedPreferences.setMockInitialValues({
      'vidavoice.onboardingComplete': onboardingComplete,
    });
    final session = SessionState(
      caregiverPin: CaregiverPinService(store: _FakeSecureStore()),
      tts: _FakeTts(),
      proxy: proxy,
      proxyAuth: ProxyAuthStore(store: _FakeSecureStore()),
    );
    session.pack = loadPackFromFile(locale);
    session.status = BootStatus.ready;
    session.onboardingComplete = onboardingComplete;
    // Login gate: the board needs a session. Tests that exercise the
    // pre-sign-in flow (e.g. the onboarding walkthrough) pass signedIn:
    // false.
    session.proxySignedIn = signedIn;
    await session.profiles.load();
    await session.plan.load(session.profiles.active?.id ?? '');
    return session;
  }

  /// Fake voice-proxy backend for the onboarding walkthrough's required
  /// account step (signup → device register → sync salt).
  ProxyClient walkthroughProxy() {
    Future<http.Response> handler(http.Request req) async {
      final path = req.url.path;
      if (path == '/v1/auth/signup') {
        return http.Response(
          json.encode({
            'token': 'tok-1',
            'token_type': 'Bearer',
            'expires_in': 3600,
            'family_id': 'fam-1',
            'profile_ids': ['p1'],
            'caregiver_id': 'cg-1',
            'sync_salt': base64.encode(utf8.encode('walkthrough-salt')),
          }),
          201,
        );
      }
      if (path == '/v1/devices/register') {
        return http.Response(
          json.encode({
            'device': {'install_id': 'install-1'},
            'device_slots': 3,
            'subscription_tier': 'base',
            'devices_used': 1,
          }),
          201,
        );
      }
      if (path == '/v1/sync/dashboards') {
        if (req.method == 'PUT') {
          return http.Response(json.encode({'version': 1}), 200);
        }
        return http.Response(json.encode({'error': 'no_sync_data'}), 404);
      }
      return http.Response('not found', 404);
    }

    return ProxyClient(
      client: MockClient(handler),
      baseUrl: 'https://proxy.test',
    );
  }

  Finder fieldWithLabel(String label) => find.byWidgetPredicate(
    (w) => w is TextField && (w.decoration?.labelText == label),
  );

  void useWideSurface(WidgetTester tester) {
    tester.view.physicalSize = const Size(1600, 2400);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
  }

  testWidgets('folder open and return keeps the sentence', (tester) async {
    useWideSurface(tester);
    final session = await makeSession();
    await session.setUnlockedLevel(LanguagePack.maxSupportedLevel);

    await tester.pumpWidget(OneVozApp(session: session));
    await tester.pump();

    // Tap a home word, then open the Food folder.
    await tester.tap(find.text('want'));
    await tester.pump();
    await tester.tap(find.text('Food'));
    await tester.pumpAndSettle();
    expect(find.text('Food', skipOffstage: false), findsWidgets);

    // Tap a food word inside the folder: the sentence grows.
    await tester.tap(find.text('apple').first);
    await tester.pump();
    expect(session.sentenceIds, ['core.want', 'food.apple']);

    // Going back to the home board keeps the sentence intact.
    await tester.pageBack();
    await tester.pumpAndSettle();
    expect(session.sentenceIds, ['core.want', 'food.apple']);
    expect(find.text('want'), findsWidgets);
  });

  testWidgets('onboarding: skip lands on the home board', (tester) async {
    useWideSurface(tester);
    final session = await makeSession(onboardingComplete: false);

    await tester.pumpWidget(OneVozApp(session: session));
    await tester.pump();
    expect(find.text('Welcome to OneVoz'), findsOneWidget);

    await tester.tap(find.text('Skip for now'));
    await tester.pumpAndSettle();
    expect(find.text('want'), findsOneWidget);
    expect(session.onboardingComplete, isTrue);
  });

  testWidgets('onboarding: full walkthrough completes and renames profile', (
    tester,
  ) async {
    useWideSurface(tester);
    final session = await makeSession(
      onboardingComplete: false,
      proxy: walkthroughProxy(),
      signedIn: false,
    );

    await tester.pumpWidget(OneVozApp(session: session));
    await tester.pump();
    expect(find.text('Welcome to OneVoz'), findsOneWidget);

    // Page 2 (account): create the caregiver account — required, no
    // defer path.
    await tester.tap(find.text('Continue'));
    await tester.pumpAndSettle();
    expect(find.text('Your OneVoz account'), findsOneWidget);
    await tester.enterText(fieldWithLabel('Email'), 'caregiver@example.org');
    await tester.enterText(fieldWithLabel('Username'), 'maya_mom');
    await tester.enterText(fieldWithLabel('Password'), 'a-strong-password-1');
    await tester.tap(find.text('Create account'));
    // The real signup derives the sync key with 600k PBKDF2 iterations.
    // The KDF yields via short delayed futures that need fake time to
    // advance; pumpAndSettle stops once the busy indicator disappears
    // (the form flips to its signed-in state), so drive the clock
    // manually until the wizard advances.
    for (var i = 0; i < 10; i++) {
      await tester.pump(const Duration(seconds: 1));
      if (find.text('Who will use OneVoz?').evaluate().isNotEmpty) break;
    }
    await tester.pumpAndSettle();
    expect(session.proxySignedIn, isTrue);

    // Page 3: enter the communicator's name.
    expect(find.text('Who will use OneVoz?'), findsOneWidget);
    await tester.enterText(find.byType(TextField), 'Maya');

    // Page 4: communication-mode choice (skippable — left untouched here,
    // so the profile stays in Tap).
    await tester.tap(find.text('Continue'));
    await tester.pumpAndSettle();
    expect(
      find.text('How does this person communicate best right now?'),
      findsOneWidget,
    );

    // Pages 5 and 6: import, then customization (both skippable).
    await tester.tap(find.text('Continue'));
    await tester.pumpAndSettle();
    expect(find.text('Bring a board from another app?'), findsOneWidget);
    await tester.tap(find.text('Continue'));
    await tester.pumpAndSettle();
    expect(find.text('Make it theirs'), findsOneWidget);

    // Pages 7 and 8: voice speed, then the tour.
    await tester.tap(find.text('Continue'));
    await tester.pumpAndSettle();
    expect(find.text('Choose a voice speed'), findsOneWidget);
    await tester.tap(find.text('Continue'));
    await tester.pumpAndSettle();
    expect(find.text('Start communicating'), findsOneWidget);

    await tester.tap(find.text('Start communicating'));
    await tester.pumpAndSettle();
    expect(find.text('want'), findsOneWidget);
    expect(session.onboardingComplete, isTrue);
    expect(session.profiles.activeName, 'Maya');
    // beginPolling() started a real periodic timer on signup; dispose the
    // session before the test ends so no timer outlives the widget tree.
    session.dispose();
  });

  testWidgets('Spanish pack renders Spanish labels on the board', (
    tester,
  ) async {
    useWideSurface(tester);
    final session = await makeSession(locale: 'es');
    await session.setUnlockedLevel(LanguagePack.maxSupportedLevel);

    await tester.pumpWidget(OneVozApp(session: session));
    await tester.pump();

    // 'quiero' is the Spanish label for core.want.
    expect(find.text('quiero'), findsWidgets);
    // The English label must not appear on the Spanish board.
    expect(find.text('want'), findsNothing);

    // Tapping speaks/adds the Spanish-labeled word by its stable id.
    await tester.tap(find.text('quiero').first);
    await tester.pump();
    expect(session.sentenceIds, ['core.want']);
    expect(session.sentence.first.label, 'quiero');
  });

  testWidgets('unlocking level 2 mid-session fills empty cells in place', (
    tester,
  ) async {
    useWideSurface(tester);
    final session = await makeSession();
    await session.setUnlockedLevel(1);

    await tester.pumpWidget(OneVozApp(session: session));
    await tester.pump();

    final homeLabels = session.pack.homeItems
        .where((i) => !i.isFolder)
        .map((i) => i.label)
        .toList();
    final level2Word = session.pack.homeItems.firstWhere(
      (i) =>
          !i.isFolder &&
          i.level == 2 &&
          homeLabels.where((l) => l == i.label).length == 1,
    );
    final starter = session.pack.homeItems.firstWhere(
      (i) => i.id == 'core.want',
    );

    expect(find.text(starter.label), findsOneWidget);
    expect(find.text(level2Word.label), findsNothing);

    // Unlock mid-session: the level-2 word appears without moving the
    // level-1 word.
    await session.setUnlockedLevel(2);
    await tester.pump();
    await tester.scrollUntilVisible(
      find.text(level2Word.label),
      600,
      scrollable: find.byType(Scrollable).first,
    );
    expect(find.text(level2Word.label), findsOneWidget);
    await tester.scrollUntilVisible(
      find.text(starter.label),
      -600,
      scrollable: find.byType(Scrollable).first,
    );
    expect(find.text(starter.label), findsOneWidget);
  });

  testWidgets('caregiver activity summary renders with usage data', (
    tester,
  ) async {
    useWideSurface(tester);
    SharedPreferences.setMockInitialValues({
      'vidavoice.onboardingComplete': true,
    });
    final session = SessionState(
      caregiverPin: CaregiverPinService(store: _FakeSecureStore()),
      tts: _FakeTts(),
    );
    session.pack = loadPackFromFile('en');
    session.status = BootStatus.ready;
    session.onboardingComplete = true;
    session.proxySignedIn = true; // login gate: the board needs a session
    await session.setUnlockedLevel(LanguagePack.maxSupportedLevel);
    await session.profiles.load();
    await session.plan.load(session.profiles.active?.id ?? '');
    await session.usage.load();
    await session.usage.recordTap('core.want');
    await session.usage.recordTap('core.want');
    await session.usage.recordTap('core.go');
    // Pre-set the gate PIN before the hub pumps (the gate snapshots hasPin
    // in initState).
    await session.caregiverPin.setPin('1234');

    await tester.pumpWidget(
      ChangeNotifierProvider.value(
        value: session,
        child: const MaterialApp(home: CaregiverScreen()),
      ),
    );
    await tester.pumpAndSettle();
    await unlockGate(tester);

    // The hub starts with sections collapsed; expand Activity summary first.
    await tester.tap(find.text('Activity summary'));
    await tester.pumpAndSettle();

    expect(find.text('Activity summary'), findsOneWidget);
    expect(find.text('Top this week'), findsOneWidget);
    // Taps today = 3, words today = 2, streak = 1 day.
    expect(find.text('3'), findsWidgets);
    expect(find.text('taps today'), findsOneWidget);
    expect(find.text('words today'), findsOneWidget);
    expect(find.text('First-week plan: 0 of 7 days done'), findsOneWidget);
    // Top this week: want x2 first.
    expect(find.text('want'), findsWidgets);
  });
}
