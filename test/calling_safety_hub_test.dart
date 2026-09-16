import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:onevoz/models/word.dart';
import 'package:onevoz/screens/calling_safety_hub_screen.dart';
import 'package:onevoz/screens/calling_safety_setup_screen.dart';
import 'package:onevoz/services/elevenlabs_key_store.dart';
import 'package:onevoz/services/proxy_client.dart';
import 'package:onevoz/services/tts_service.dart';
import 'package:onevoz/state/session_state.dart';

/// TTS double: never touches the platform channel.
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

/// In-memory keychain double: on desktop test runners the real secure
/// storage backend hangs instead of completing.
class _FakeSecureStore implements SecureValueStore {
  final map = <String, String>{};

  @override
  Future<String?> read(String key) async => map[key];

  @override
  Future<void> write(String key, String value) async => map[key] = value;

  @override
  Future<void> delete(String key) async => map.remove(key);
}

/// Widget coverage for the Calling & Safety hub and guided setup flow.
///
/// Hermetic: in-memory prefs, fake TTS, fake secure store, pack loaded
/// from disk. `SessionState.boot()` is deliberately not exercised — the
/// flutter_tester cannot serve rootBundle assets.
void main() {
  LanguagePack loadPackFromFile() {
    final raw = File('assets/lang/en.json').readAsStringSync();
    final pack = LanguagePack.fromJson(
      Map<String, dynamic>.from(json.decode(raw) as Map),
    );
    pack.validate();
    return pack;
  }

  Future<SessionState> makeSession() async {
    SharedPreferences.setMockInitialValues({
      'vidavoice.onboardingComplete': true,
    });
    final session = SessionState(
      tts: _FakeTts(),
      proxyAuth: ProxyAuthStore(store: _FakeSecureStore()),
    );
    session.pack = loadPackFromFile();
    session.status = BootStatus.ready;
    session.onboardingComplete = true;
    session.proxySignedIn = true;
    await session.profiles.load();
    return session;
  }

  Widget wrap(SessionState session, Widget home) {
    return ChangeNotifierProvider.value(
      value: session,
      child: MaterialApp(home: home),
    );
  }

  /// Scrolls the hub's outer ListView until [text] is visible. The outer
  /// scrollable is passed explicitly because the phrase bank's inner
  /// ReorderableListView makes the default scrollable lookup ambiguous.
  Future<void> scrollHubTo(WidgetTester tester, String text) async {
    final outer = find.byType(Scrollable).first;
    await tester.scrollUntilVisible(find.text(text), 500, scrollable: outer);
    await tester.pumpAndSettle();
  }

  testWidgets('setup flow renders step 1 (contacts)', (tester) async {
    final session = await makeSession();
    await tester.pumpWidget(
      wrap(session, const CallingSafetySetupScreen()),
    );
    await tester.pumpAndSettle();

    expect(find.text('Who should they be able to call?'), findsOneWidget);
    expect(find.text('Add contact'), findsOneWidget);
    // Skip is always visible; Back is hidden on the first step.
    expect(find.text('Skip for now'), findsOneWidget);
    expect(find.text('Back'), findsNothing);
    expect(find.text('Continue'), findsOneWidget);
  });

  testWidgets('Skip advances through the steps to Done', (tester) async {
    final session = await makeSession();
    await tester.pumpWidget(
      wrap(session, const CallingSafetySetupScreen()),
    );
    await tester.pumpAndSettle();

    // Step 1 -> step 2 (phrases).
    await tester.tap(find.text('Skip for now'));
    await tester.pumpAndSettle();
    expect(find.text('What should they be able to say?'), findsOneWidget);
    expect(find.text('Phrase placeholders'), findsOneWidget);

    // Step 2 -> step 3 (emergency). Back is now visible.
    await tester.tap(find.text('Skip for now'));
    await tester.pumpAndSettle();
    expect(find.text('Emergency details'), findsOneWidget);
    expect(find.text('Back'), findsOneWidget);
    // The honest-limit note rides along on the emergency step.
    expect(
      find.textContaining('never replaces calling 911 directly'),
      findsOneWidget,
    );

    // Step 3 -> Done summary.
    await tester.tap(find.text('Skip for now'));
    await tester.pumpAndSettle();
    expect(find.text('You\u2019re all set'), findsOneWidget);
    expect(find.text('Back to hub'), findsOneWidget);
    // Skip disappears on Done; only the way back remains.
    expect(find.text('Skip for now'), findsNothing);
  });

  testWidgets('Back returns to the previous step', (tester) async {
    final session = await makeSession();
    await tester.pumpWidget(
      wrap(session, const CallingSafetySetupScreen()),
    );
    await tester.pumpAndSettle();

    await tester.tap(find.text('Continue'));
    await tester.pumpAndSettle();
    expect(find.text('What should they be able to say?'), findsOneWidget);

    await tester.tap(find.text('Back'));
    await tester.pumpAndSettle();
    expect(find.text('Who should they be able to call?'), findsOneWidget);
  });

  testWidgets('adding a contact shows it in the step list', (tester) async {
    final session = await makeSession();
    await tester.pumpWidget(
      wrap(session, const CallingSafetySetupScreen()),
    );
    await tester.pumpAndSettle();

    await tester.tap(find.text('Add contact'));
    await tester.pumpAndSettle();
    await tester.enterText(
      find.widgetWithText(TextField, 'Name').first,
      'Grandma',
    );
    await tester.enterText(
      find.widgetWithText(TextField, 'Phone number').first,
      '+1 555 010 2030',
    );
    // The Add button enables only once both fields are non-empty; pump so
    // the setState from the phone field's onChanged rebuilds the button
    // before tapping (real devices pump continuously; the harness does not).
    await tester.pump();
    await tester.tap(find.widgetWithText(FilledButton, 'Add'));
    await tester.pumpAndSettle();

    expect(find.text('Grandma'), findsOneWidget);
    expect(find.text('+1 555 010 2030'), findsOneWidget);
    // Profile data round-trips through the ProfileService mutator.
    final profile = session.profiles.active!;
    expect(profile.contacts.length, 1);
    expect(profile.contacts.single.name, 'Grandma');
  });

  testWidgets('hub renders all four sections plus the limits card', (
    tester,
  ) async {
    final session = await makeSession();
    await tester.pumpWidget(
      wrap(session, const CallingSafetyHubScreen()),
    );
    await tester.pumpAndSettle();

    // The hub is a lazily-built ListView: scroll each section into view
    // before asserting (off-viewport cards aren't in the element tree, and
    // far-off-viewport cards are disposed again after scrolling past).
    // NOTE: scrollUntilVisible only scrolls downward, so each card is
    // asserted while it is on screen, in top-to-bottom order.
    await scrollHubTo(tester, 'Contacts');
    expect(find.text('Contacts'), findsOneWidget);

    await scrollHubTo(tester, 'Call phrases');
    expect(find.text('Call phrases'), findsOneWidget);

    await scrollHubTo(tester, 'Emergency details');
    expect(find.text('Emergency details'), findsOneWidget);
    expect(
      tester
          .widget<SwitchListTile>(
            find.widgetWithText(SwitchListTile, 'Emergency button'),
          )
          .value,
      isTrue,
    );
    await scrollHubTo(tester, 'Safety');
    expect(find.text('Safety'), findsOneWidget);
    expect(find.text('AI phrase suggestions'), findsOneWidget);
    expect(find.text('Prefer my phrases'), findsOneWidget);
    expect(
      tester
          .widget<SwitchListTile>(
            find.widgetWithText(SwitchListTile, 'AI phrase suggestions'),
          )
          .value,
      isTrue,
    );
    expect(
      tester
          .widget<SwitchListTile>(
            find.widgetWithText(SwitchListTile, 'Prefer my phrases'),
          )
          .value,
      isTrue,
    );
    // Below the fold in the hub's ListView: scroll into view before asserting.
    await scrollHubTo(tester, 'Good to know');
    expect(find.text('Good to know'), findsOneWidget);
    expect(find.text('Run guided setup again'), findsOneWidget);
  });

  testWidgets('hub shows the honest-limit notes verbatim', (tester) async {
    final session = await makeSession();
    await tester.pumpWidget(
      wrap(session, const CallingSafetyHubScreen()),
    );
    await tester.pumpAndSettle();

    await scrollHubTo(tester, 'Good to know');

    expect(
      find.textContaining(
        'Text-to-911 works only where your local 911 center accepts texts',
      ),
      findsOneWidget,
    );
    expect(
      find.textContaining('never replaces calling 911 directly'),
      findsOneWidget,
    );
    expect(
      find.textContaining('best-effort on Android'),
      findsOneWidget,
    );
  });

  testWidgets('toggling a safety preference persists it', (tester) async {
    final session = await makeSession();
    await tester.pumpWidget(
      wrap(session, const CallingSafetyHubScreen()),
    );
    await tester.pumpAndSettle();

    await scrollHubTo(tester, 'AI phrase suggestions');
    await tester.tap(find.text('AI phrase suggestions'));
    await tester.pumpAndSettle();

    expect(session.profiles.active!.safety.aiSuggestions, isFalse);
  });
}
