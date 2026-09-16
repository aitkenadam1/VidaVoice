import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:onevoz/models/word.dart';
import 'package:onevoz/screens/caregiver_screen.dart';
import 'package:onevoz/services/caregiver_pin_service.dart';
import 'package:onevoz/services/elevenlabs_key_store.dart';
import 'package:onevoz/services/tts_service.dart';
import 'package:onevoz/state/session_state.dart';
import 'package:onevoz/widgets/location_request_prompt.dart';

class _FakeTts extends TtsService {
  @override
  Future<void> speak(String text) async {}

  @override
  Future<void> stop() async {}
}

/// In-memory stand-in for the platform keychain.
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
  LanguagePack loadPackFromFile(String locale) {
    final raw = File('assets/lang/$locale.json').readAsStringSync();
    final pack = LanguagePack.fromJson(
      Map<String, dynamic>.from(json.decode(raw) as Map),
    );
    pack.validate();
    return pack;
  }

  Future<SessionState> makeSession({CaregiverPinService? pin}) async {
    SharedPreferences.setMockInitialValues({});
    final session = SessionState(
      tts: _FakeTts(),
      caregiverPin: pin ?? CaregiverPinService(store: _FakeSecureStore()),
    );
    await session.profiles.load();
    // CaregiverScreen needs the vocabulary pack, like the real boot path.
    session.pack = loadPackFromFile('en');
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

  /// Taps the on-screen PIN pad digits in order.
  Future<void> enterPin(WidgetTester tester, String pin) async {
    for (final ch in pin.split('')) {
      await tester.tap(find.text(ch));
      await tester.pump(const Duration(milliseconds: 50));
    }
    await tester.pumpAndSettle();
  }

  group('caregiver PIN gate', () {
    testWidgets('first open asks to create a PIN, then unlocks the hub', (
      tester,
    ) async {
      final session = await makeSession();
      await pumpHub(tester, session);

      expect(find.text('Create a caregiver PIN'), findsOneWidget);
      // The hub is not visible behind the gate.
      expect(find.text('Vocabulary level'), findsNothing);

      await enterPin(tester, '4829');
      expect(find.text('Confirm your PIN'), findsOneWidget);

      await enterPin(tester, '4829');
      // Gate open: the hub renders.
      expect(find.text('Vocabulary level'), findsOneWidget);
      expect(await session.caregiverPin.hasPin(), isTrue);
      session.dispose();
    });

    testWidgets('mismatched confirmation restarts creation', (tester) async {
      final session = await makeSession();
      await pumpHub(tester, session);

      await enterPin(tester, '1111');
      await enterPin(tester, '2222');

      expect(find.textContaining('didn\u2019t match'), findsOneWidget);
      expect(find.text('Create a caregiver PIN'), findsOneWidget);
      expect(await session.caregiverPin.hasPin(), isFalse);
      session.dispose();
    });

    testWidgets('wrong PIN stays locked; right PIN unlocks', (tester) async {
      final pin = CaregiverPinService(store: _FakeSecureStore());
      await pin.setPin('9999');
      final session = await makeSession(pin: pin);
      await pumpHub(tester, session);

      expect(find.text('Caregiver access'), findsOneWidget);

      await enterPin(tester, '1234');
      expect(find.textContaining('Wrong PIN'), findsOneWidget);
      expect(find.text('Vocabulary level'), findsNothing);

      await enterPin(tester, '9999');
      expect(find.text('Vocabulary level'), findsOneWidget);
      session.dispose();
    });

    testWidgets('gate re-arms: reopening the hub asks for the PIN again', (
      tester,
    ) async {
      final pin = CaregiverPinService(store: _FakeSecureStore());
      await pin.setPin('1357');
      final session = await makeSession(pin: pin);

      // First visit: unlock.
      await pumpHub(tester, session);
      await enterPin(tester, '1357');
      expect(find.text('Vocabulary level'), findsOneWidget);

      // Leave and come back: the gate is back (per-visit unlock — in the
      // real app, popping the hub disposes it; pushing a fresh one
      // re-arms the gate).
      await tester.pumpWidget(Container());
      await tester.pumpAndSettle();
      await pumpHub(tester, session);
      expect(find.text('Caregiver access'), findsOneWidget);
      expect(find.text('Vocabulary level'), findsNothing);
      session.dispose();
    });
  });

  group('child boards', () {
    testWidgets('no sharing status on the boards — request prompt only', (
      tester,
    ) async {
      final session = await makeSession();
      await tester.pumpWidget(
        ChangeNotifierProvider<SessionState>.value(
          value: session,
          child: const MaterialApp(
            home: Scaffold(body: LocationRequestPrompt()),
          ),
        ),
      );
      await tester.pumpAndSettle();

      // No pending request and no active session: renders nothing. The
      // old "Sharing location · Stop" status no longer exists on the
      // child's boards at all — it lives in the caregiver hub.
      expect(find.textContaining('Sharing location'), findsNothing);
      expect(
        find.text('Your caregiver is asking to see your location.'),
        findsNothing,
      );
      session.dispose();
    });
  });
}
