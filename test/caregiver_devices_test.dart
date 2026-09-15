import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:onevoz/models/word.dart';
import 'package:onevoz/screens/caregiver_screen.dart';
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
  Future<void> setVoice(TtsVoice voice) async {
    currentVoice = voice;
  }

  @override
  Future<void> clearVoice() async {
    currentVoice = null;
  }
}

/// The Devices card is a signed-in-only section: with no caregiver
/// account the hub must not show it at all, and signing in must reveal
/// it without restarting the app.
void main() {
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

  Future<SessionState> makeSession() async {
    // Collapse every card: only titles + one-line summaries build, so the
    // test doesn't need the heavier stores behind each section's content.
    SharedPreferences.setMockInitialValues({
      'vidavoice.caregiver.collapsed': sectionIds,
    });
    final raw = File('assets/lang/en.json').readAsStringSync();
    final pack = LanguagePack.fromJson(
      Map<String, dynamic>.from(json.decode(raw) as Map),
    );
    pack.validate();
    final session = SessionState(tts: _FakeTts());
    session.pack = pack;
    session.status = BootStatus.ready;
    await session.profiles.load();
    await session.plan.load(session.profiles.active?.id ?? '');
    return session;
  }

  Future<void> pumpHub(WidgetTester tester, SessionState session) async {
    await tester.pumpWidget(
      ChangeNotifierProvider<SessionState>.value(
        value: session,
        child: const MaterialApp(home: CaregiverScreen()),
      ),
    );
    await tester.pumpAndSettle();
  }

  testWidgets('Devices section hidden until the caregiver signs in', (
    tester,
  ) async {
    final session = await makeSession();
    expect(session.proxySignedIn, isFalse);
    await pumpHub(tester, session);

    // skipOffstage: the hub ListView lazily materializes cards, so the
    // absence check must look past the viewport too.
    expect(find.text('Devices', skipOffstage: false), findsNothing);

    session.proxySignedIn = true;
    session.notifyListeners();
    await tester.pumpAndSettle();

    // The hub ListView lazily materializes cards: scroll until the
    // Devices card is built, proving it is in the list once signed in.
    await tester.scrollUntilVisible(
      find.text('Devices'),
      600,
      scrollable: find.byType(Scrollable).first,
    );
    expect(find.text('Devices'), findsOneWidget);
  });
}
