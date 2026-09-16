import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:onevoz/models/calling_safety.dart';
import 'package:onevoz/screens/call_confirm_screen.dart';
import 'package:onevoz/screens/call_screen.dart';
import 'package:onevoz/screens/emergency_screen.dart';
import 'package:onevoz/services/tts_service.dart';
import 'package:onevoz/state/session_state.dart';
import 'package:onevoz/widgets/hold_to_confirm_button.dart';

/// TTS double: never touches the platform channel; records what was asked.
class _FakeTts extends TtsService {
  String? lastSpoken;
  int stopCalls = 0;

  @override
  Future<void> speak(String text) async {
    lastSpoken = text;
  }

  @override
  Future<void> stop() async {
    stopCalls++;
  }
}

/// 1x1 transparent PNG, base64 — exercises the photo path without assets.
const _tinyPng =
    'iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAYAAAAfFcSJAAAADUlEQVR42mP8z8BQDwAEhQGAhKmMIQAAAABJRU5ErkJggg==';

void main() {
  SessionState makeSession(_FakeTts tts) {
    SharedPreferences.setMockInitialValues({});
    return SessionState(tts: tts);
  }

  Future<void> pumpScreen(
    WidgetTester tester,
    SessionState session,
    Widget screen,
  ) async {
    await tester.pumpWidget(
      ChangeNotifierProvider<SessionState>.value(
        value: session,
        child: MaterialApp(home: screen),
      ),
    );
    await tester.pump();
  }

  testWidgets('hold-to-confirm completes after a full 2s hold', (tester) async {
    var confirmed = false;
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: HoldToConfirmButton(
            onConfirmed: () => confirmed = true,
          ),
        ),
      ),
    );

    final gesture = await tester.startGesture(
      tester.getCenter(find.byType(HoldToConfirmButton)),
    );
    await tester.pump(const Duration(seconds: 2));
    expect(confirmed, isTrue);
    await gesture.up();
  });

  testWidgets('releasing early cancels the hold', (tester) async {
    var confirmed = false;
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: HoldToConfirmButton(
            onConfirmed: () => confirmed = true,
          ),
        ),
      ),
    );

    final gesture = await tester.startGesture(
      tester.getCenter(find.byType(HoldToConfirmButton)),
    );
    await tester.pump(const Duration(seconds: 1));
    await gesture.up();
    // Well past the hold duration: nothing must have fired.
    await tester.pump(const Duration(seconds: 3));
    expect(confirmed, isFalse);
  });

  testWidgets('call confirm screen renders photo, name, Call and Cancel', (
    tester,
  ) async {
    const contact = SafetyContact(
      id: 'mom',
      name: 'Mom',
      phone: '555-0100',
      imageData: _tinyPng,
      kind: 'mom',
    );
    final session = makeSession(_FakeTts());
    await pumpScreen(tester, session, const CallConfirmScreen(contact: contact));

    expect(find.text('Call Mom?'), findsOneWidget);
    expect(find.text('555-0100'), findsOneWidget);
    expect(find.text('Call'), findsOneWidget);
    expect(find.text('Cancel'), findsOneWidget);
    // Photo path renders the avatar (MemoryImage) instead of the fallback.
    expect(find.byType(CircleAvatar), findsOneWidget);
  });

  testWidgets('emergency screen renders all five actions when enabled', (
    tester,
  ) async {
    const emergency = EmergencyProfileData(
      childName: 'Alex',
      homeAddress: '123 Main St',
      parentName: 'Sam',
      parentPhone: '555-0101',
      emergencyEnabled: true,
    );
    const contacts = [
      SafetyContact(id: 'mom', name: 'Mom', phone: '555-0100', kind: 'mom'),
      SafetyContact(id: 'dad', name: 'Dad', phone: '555-0102', kind: 'dad'),
    ];
    final session = makeSession(_FakeTts());
    await pumpScreen(
      tester,
      session,
      const EmergencyScreen(emergency: emergency, contacts: contacts),
    );

    expect(find.text('Call 911'), findsOneWidget);
    expect(find.text('Text 911'), findsOneWidget);
    expect(find.text('Call Mom'), findsOneWidget);
    expect(find.text('Call Dad'), findsOneWidget);
    expect(find.text('Show my emergency card'), findsOneWidget);
    // Honest copy: complements Emergency SOS, never replaces it. It sits
    // below the fold, so scroll it into the ListView's cache extent first.
    await tester.scrollUntilVisible(
      find.textContaining("never replaces calling 911"),
      300,
    );
    expect(find.textContaining("never replaces calling 911"), findsOneWidget);
  });

  testWidgets('call screen speaks phrase cards with placeholders resolved', (
    tester,
  ) async {
    final tts = _FakeTts();
    final session = makeSession(tts);
    await pumpScreen(
      tester,
      session,
      const CallScreen(
        phrases: [CallPhrase(id: 'intro', text: 'Hi, this is {child_name}')],
        emergency: EmergencyProfileData(childName: 'Alex'),
        safety: SafetySettings(aiSuggestions: false),
      ),
    );

    await tester.tap(find.text('Hi, this is Alex'));
    await tester.pump();
    expect(tts.lastSpoken, 'Hi, this is Alex');
    // Quick answers are always one tap away.
    expect(find.text('Yes'), findsOneWidget);
    expect(find.text('Hold on'), findsOneWidget);
    // Suggestions stay hidden when the caregiver switched them off.
    expect(find.text('Dispatcher says…'), findsNothing);
  });

  testWidgets('dispatcher field yields speakable suggestion cards', (
    tester,
  ) async {
    final tts = _FakeTts();
    final session = makeSession(tts);
    await pumpScreen(
      tester,
      session,
      const CallScreen(
        phrases: [],
        emergency: EmergencyProfileData(
          childName: 'Alex',
          homeAddress: '123 Main St',
        ),
        safety: SafetySettings(aiSuggestions: true),
      ),
    );

    await tester.enterText(find.byType(TextField), 'where are you');
    await tester.pump();
    // Address intent -> home address card with placeholders resolved.
    expect(find.text('My address is 123 Main St'), findsOneWidget);
    // The gradient hero pushes the card below the test viewport's fold —
    // scroll it into view like a real user would before tapping.
    // The gradient hero pushes the card below the test viewport's fold —
    // drag the list like a real user would before tapping.
    await tester.drag(find.byType(ListView), const Offset(0, -600));
    await tester.pump();

    await tester.tap(find.text('My address is 123 Main St'));
    await tester.pump();
    expect(tts.lastSpoken, 'My address is 123 Main St');

    // Undo stops the voice. Let the SnackBar finish its entrance animation
    // before tapping, or the tap lands below the viewport and misses.
    await tester.pump(const Duration(milliseconds: 500));
    await tester.tap(find.text('Undo'));
    await tester.pump();
    expect(tts.stopCalls, 1);
  });

  testWidgets('emergency card is honest about missing GPS', (tester) async {
    const emergency = EmergencyProfileData(
      childName: 'Alex',
      homeAddress: '123 Main St',
      parentName: 'Sam',
      parentPhone: '555-0101',
      medicalNotes: 'Carries an EpiPen.',
    );
    final session = makeSession(_FakeTts());
    await pumpScreen(
      tester,
      session,
      const EmergencyCardScreen(emergency: emergency, gps: null),
    );

    expect(find.text('Alex'), findsOneWidget);
    expect(find.text('123 Main St'), findsOneWidget);
    expect(find.text('location unavailable'), findsOneWidget);
    expect(find.textContaining('555-0101'), findsOneWidget);
    expect(find.text('Carries an EpiPen.'), findsOneWidget);
  });
}
