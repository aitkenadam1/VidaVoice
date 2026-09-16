import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:onevoz/models/calling_safety.dart';
import 'package:onevoz/screens/call_confirm_screen.dart';
import 'package:onevoz/screens/emergency_screen.dart';
import 'package:onevoz/services/tts_service.dart';
import 'package:onevoz/state/session_state.dart';
import 'package:onevoz/widgets/call_shortcut_button.dart';
import 'package:onevoz/widgets/emergency_shortcut_button.dart';

/// TTS double: never touches the platform channel.
class _FakeTts extends TtsService {
  @override
  Future<void> speak(String text) async {}

  @override
  Future<void> stop() async {}
}

const _mom = SafetyContact(
  id: 'mom',
  name: 'Mom',
  phone: '555-0100',
  kind: 'mom',
);

const _dad = SafetyContact(
  id: 'dad',
  name: 'Dad',
  phone: '555-0102',
  kind: 'dad',
);

const _noEmergency = EmergencyProfileData(emergencyEnabled: false);

void main() {
  Future<SessionState> makeSession() async {
    SharedPreferences.setMockInitialValues({});
    final session = SessionState(tts: _FakeTts());
    await session.profiles.load();
    return session;
  }

  Future<void> pumpBar(WidgetTester tester, SessionState session) async {
    await tester.pumpWidget(
      ChangeNotifierProvider<SessionState>.value(
        value: session,
        child: MaterialApp(
          home: Scaffold(
            appBar: AppBar(
              actions: const [
                CallShortcutButton(),
                EmergencyShortcutButton(),
              ],
            ),
          ),
        ),
      ),
    );
    await tester.pump();
  }

  group('call shortcut button', () {
    testWidgets('hidden when the profile has no call contacts', (tester) async {
      final session = await makeSession();
      final p = await session.profiles.addProfile('Kid');
      await session.profiles.setEmergency(p.id, _noEmergency);

      await pumpBar(tester, session);

      expect(find.byIcon(Icons.call), findsNothing);
    });

    testWidgets('hidden with no contacts even when emergency is on', (
      tester,
    ) async {
      final session = await makeSession();
      await session.profiles.addProfile('Kid');
      // EmergencyProfileData defaults emergencyEnabled to true.

      await pumpBar(tester, session);

      expect(find.byIcon(Icons.call), findsNothing);
      // Emergency has its own button now.
      expect(find.byIcon(Icons.emergency), findsOneWidget);
    });

    testWidgets('single contact goes straight to call confirmation', (
      tester,
    ) async {
      final session = await makeSession();
      final p = await session.profiles.addProfile('Kid');
      await session.profiles.setEmergency(p.id, _noEmergency);
      await session.profiles.setContacts(p.id, [_mom]);

      await pumpBar(tester, session);
      await tester.tap(find.byIcon(Icons.call));
      await tester.pumpAndSettle();

      expect(find.byType(CallConfirmScreen), findsOneWidget);
      expect(find.text('Call Mom?'), findsOneWidget);
    });

    testWidgets('multiple contacts open a picker sheet', (tester) async {
      final session = await makeSession();
      final p = await session.profiles.addProfile('Kid');
      await session.profiles.setEmergency(p.id, _noEmergency);
      await session.profiles.setContacts(p.id, [_mom, _dad]);

      await pumpBar(tester, session);
      await tester.tap(find.byIcon(Icons.call));
      await tester.pumpAndSettle();

      // Picker — not call confirmation yet.
      expect(find.text('Who do you want to call?'), findsOneWidget);
      expect(find.byType(CallConfirmScreen), findsNothing);

      await tester.tap(find.text('Dad'));
      await tester.pumpAndSettle();

      expect(find.byType(CallConfirmScreen), findsOneWidget);
      expect(find.text('Call Dad?'), findsOneWidget);
    });
  });

  group('emergency shortcut button', () {
    testWidgets('hidden when emergency is disabled', (tester) async {
      final session = await makeSession();
      final p = await session.profiles.addProfile('Kid');
      await session.profiles.setEmergency(p.id, _noEmergency);

      await pumpBar(tester, session);

      expect(find.byIcon(Icons.emergency), findsNothing);
    });

    testWidgets('tap opens the emergency screen directly', (tester) async {
      final session = await makeSession();
      await session.profiles.addProfile('Kid');
      // Emergency on by default.

      await pumpBar(tester, session);
      await tester.tap(find.byIcon(Icons.emergency));
      await tester.pumpAndSettle();

      expect(find.byType(EmergencyScreen), findsOneWidget);
    });
  });
}
