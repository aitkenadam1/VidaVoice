import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:onevoz/main.dart';
import 'package:onevoz/models/word.dart';
import 'package:onevoz/screens/build_board_screen.dart';
import 'package:onevoz/screens/caregiver_portal_screen.dart';
import 'package:onevoz/screens/device_role_screen.dart';
import 'package:onevoz/screens/home_board_screen.dart';
import 'package:onevoz/screens/type_board_screen.dart';
import 'package:onevoz/services/device_role_service.dart';
import 'package:onevoz/services/elevenlabs_key_store.dart';
import 'package:onevoz/services/profile_service.dart';
import 'package:onevoz/services/proxy_client.dart';
import 'package:onevoz/services/tts_service.dart';
import 'package:onevoz/state/session_state.dart';
import 'package:onevoz/widgets/board_device_bar.dart';

/// Communicator-board device bar (Adam, 2026-10-20): the boards carry
/// two labeled buttons — "Caregiver Portal" (the existing account
/// gate: email/username + password, same-family only) and "Log out"
/// (confirmation, then the existing sign-out). These tests pump the
/// real app router so the assertions cover the actual landing spots,
/// not just the widgets.

/// TTS double: never touches the platform channel.
class _FakeTts extends TtsService {
  @override
  Future<bool> init({
    required String language,
    double rate = 0.5,
    double pitch = 1.0,
  }) async => true;

  @override
  Future<void> speak(String text) async {}

  @override
  Future<List<TtsVoice>> getVoices() async => const [];
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

/// Proxy double for the gate's verification login: 'correct-horse'
/// belongs to THIS family (fam_1), 'other-family' is a valid account
/// in a DIFFERENT family, anything else is a 401.
ProxyClient _fakeProxy() => ProxyClient(
  client: MockClient((request) async {
    if (request.url.path == '/v1/auth/login' && request.method == 'POST') {
      final body = json.decode(request.body) as Map<String, dynamic>;
      final password = body['password'];
      if (password == 'correct-horse' || password == 'other-family') {
        return http.Response(
          json.encode({
            'token': 'tok-verified',
            'family_id': password == 'correct-horse' ? 'fam_1' : 'fam_2',
            'profile_ids': <String>[],
          }),
          200,
        );
      }
      return http.Response(
        json.encode({
          'error': {
            'code': 'invalid_credentials',
            'message': 'Wrong email or password.',
          },
        }),
        401,
      );
    }
    return http.Response('not found', 404);
  }),
  baseUrl: 'https://proxy.test',
);

LanguagePack _loadPack() {
  final raw = File('assets/lang/en.json').readAsStringSync();
  final pack = LanguagePack.fromJson(
    Map<String, dynamic>.from(json.decode(raw) as Map),
  );
  pack.validate();
  return pack;
}

/// A signed-in communicator session on family fam_1, ready to render
/// boards through the real app router.
Future<SessionState> _makeBoardSession({CommunicationMode? mode}) async {
  SharedPreferences.setMockInitialValues({});
  final session = SessionState(
    tts: _FakeTts(),
    proxy: _fakeProxy(),
    // The real platform keychain hangs in widget tests; the sign-out
    // and role paths get the same in-memory fake the gate tests use.
    proxyAuth: ProxyAuthStore(store: _FakeSecureStore()),
    deviceRoleService: DeviceRoleService(store: _FakeSecureStore()),
  );
  session.pack = _loadPack();
  session.status = BootStatus.ready;
  session.onboardingComplete = true;
  session.proxySignedIn = true;
  session.proxyFamilyId = 'fam_1';
  session.deviceRole = DeviceRole.communicator;
  await session.profiles.load();
  if (mode != null) {
    await session.profiles.setCommunicationMode(
      session.profiles.active!.id,
      mode,
    );
  }
  return session;
}

void _useWideSurface(WidgetTester tester) {
  tester.view.physicalSize = const Size(1600, 2400);
  tester.view.devicePixelRatio = 1.0;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);
}

Finder _portalButton() => find.widgetWithText(TextButton, 'Caregiver Portal');
Finder _logOutButton() => find.widgetWithText(TextButton, 'Log out');

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('BoardDeviceBar presence', () {
    testWidgets('both buttons are visible on the Tap home board', (
      tester,
    ) async {
      _useWideSurface(tester);
      final session = await _makeBoardSession();
      await tester.pumpWidget(OneVozApp(session: session));
      await tester.pumpAndSettle();

      expect(find.byType(HomeBoardScreen), findsOneWidget);
      expect(find.byType(BoardDeviceBar), findsOneWidget);
      expect(_portalButton(), findsOneWidget);
      expect(_logOutButton(), findsOneWidget);
    });

    testWidgets('both buttons are visible on the Build board', (
      tester,
    ) async {
      _useWideSurface(tester);
      final session = await _makeBoardSession(mode: CommunicationMode.build);
      await tester.pumpWidget(OneVozApp(session: session));
      await tester.pumpAndSettle();

      expect(find.byType(BuildBoardScreen), findsOneWidget);
      expect(_portalButton(), findsOneWidget);
      expect(_logOutButton(), findsOneWidget);
    });

    testWidgets('both buttons are visible on the Type board', (
      tester,
    ) async {
      _useWideSurface(tester);
      final session = await _makeBoardSession(mode: CommunicationMode.type);
      await tester.pumpWidget(OneVozApp(session: session));
      await tester.pumpAndSettle();

      expect(find.byType(TypeBoardScreen), findsOneWidget);
      expect(_portalButton(), findsOneWidget);
      expect(_logOutButton(), findsOneWidget);
    });
  });

  group('Caregiver Portal button (existing account gate)', () {
    Future<void> openGate(WidgetTester tester, SessionState session) async {
      _useWideSurface(tester);
      await tester.pumpWidget(OneVozApp(session: session));
      await tester.pumpAndSettle();
      await tester.tap(_portalButton());
      await tester.pumpAndSettle();
      // The credential prompt is the existing gate form.
      expect(
        find.widgetWithText(TextField, 'Email or username'),
        findsOneWidget,
      );
      expect(
        find.widgetWithText(TextField, 'Account password'),
        findsOneWidget,
      );
    }

    testWidgets('wrong password shows the error and does NOT open the '
        'Portal', (tester) async {
      final session = await _makeBoardSession();
      await openGate(tester, session);

      await tester.enterText(
        find.widgetWithText(TextField, 'Email or username'),
        'caregiver@example.com',
      );
      await tester.enterText(
        find.widgetWithText(TextField, 'Account password'),
        'wrong',
      );
      await tester.tap(find.text('Switch to caregiver mode'));
      await tester.pumpAndSettle();

      expect(find.text('Wrong email or password.'), findsOneWidget);
      expect(find.byType(CaregiverPortalScreen), findsNothing);
      expect(session.deviceRole, DeviceRole.communicator);
    });

    testWidgets('a valid account from a DIFFERENT family is refused', (
      tester,
    ) async {
      final session = await _makeBoardSession();
      await openGate(tester, session);

      await tester.enterText(
        find.widgetWithText(TextField, 'Email or username'),
        'sibling@example.com',
      );
      await tester.enterText(
        find.widgetWithText(TextField, 'Account password'),
        'other-family',
      );
      await tester.tap(find.text('Switch to caregiver mode'));
      await tester.pumpAndSettle();

      expect(
        find.textContaining('belongs to a different family'),
        findsOneWidget,
      );
      expect(find.byType(CaregiverPortalScreen), findsNothing);
      expect(session.deviceRole, DeviceRole.communicator);
    });

    testWidgets('correct credentials switch the device to the Portal', (
      tester,
    ) async {
      final session = await _makeBoardSession();
      await openGate(tester, session);

      await tester.enterText(
        find.widgetWithText(TextField, 'Email or username'),
        'caregiver@example.com',
      );
      await tester.enterText(
        find.widgetWithText(TextField, 'Account password'),
        'correct-horse',
      );
      await tester.tap(find.text('Switch to caregiver mode'));
      await tester.pumpAndSettle();

      expect(session.deviceRole, DeviceRole.caregiver);
      expect(find.byType(CaregiverPortalScreen), findsOneWidget);
      expect(find.byType(HomeBoardScreen), findsNothing);
    });
  });

  group('Log out button', () {
    testWidgets('asks for confirmation; cancel keeps the session', (
      tester,
    ) async {
      _useWideSurface(tester);
      final session = await _makeBoardSession();
      await tester.pumpWidget(OneVozApp(session: session));
      await tester.pumpAndSettle();

      await tester.tap(_logOutButton());
      await tester.pumpAndSettle();

      expect(find.text('Log out?'), findsOneWidget);
      await tester.tap(find.text('Cancel'));
      await tester.pumpAndSettle();

      expect(session.proxySignedIn, isTrue);
      expect(session.deviceRole, DeviceRole.communicator);
      expect(find.byType(HomeBoardScreen), findsOneWidget);
    });

    testWidgets('confirming signs out and leaves the board behind', (
      tester,
    ) async {
      _useWideSurface(tester);
      final session = await _makeBoardSession();
      await tester.pumpWidget(OneVozApp(session: session));
      await tester.pumpAndSettle();

      await tester.tap(_logOutButton());
      await tester.pumpAndSettle();
      await tester.tap(find.widgetWithText(FilledButton, 'Log out'));
      await tester.pumpAndSettle();

      expect(session.proxySignedIn, isFalse);
      expect(session.deviceRole, isNull);
      expect(find.byType(HomeBoardScreen), findsNothing);
      // The existing sign-out clears the device role too, so the flow
      // lands on the device-role question; the sign-in gate follows it.
      expect(find.byType(DeviceRoleScreen), findsOneWidget);
    });
  });
}
