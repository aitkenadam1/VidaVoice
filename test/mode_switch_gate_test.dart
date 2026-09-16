import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:provider/provider.dart';
import 'package:onevoz/services/device_role_service.dart';
import 'package:onevoz/services/elevenlabs_key_store.dart';
import 'package:onevoz/services/proxy_client.dart';
import 'package:onevoz/services/tts_service.dart';
import 'package:onevoz/state/session_state.dart';
import 'package:onevoz/widgets/mode_switch_gate.dart';

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

/// Proxy double: only /v1/auth/login is implemented. The password
/// 'correct-horse' verifies; anything else is a 401.
SessionState _makeSession() => SessionState(
  tts: _FakeTts(),
  proxy: ProxyClient(
    client: MockClient((request) async {
      if (request.url.path == '/v1/auth/login' && request.method == 'POST') {
        final body = json.decode(request.body) as Map<String, dynamic>;
        if (body['password'] == 'correct-horse') {
          return http.Response(
            json.encode({
              'token': 'tok-verified',
              'family_id': 'fam_1',
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
  ),
  // The sign-out path clears stored auth state: the real platform
  // keychain hangs (never resolves) in widget tests, so it gets the
  // same fake every other secure store here uses.
  proxyAuth: ProxyAuthStore(store: _FakeSecureStore()),
  deviceRoleService: DeviceRoleService(store: _FakeSecureStore()),
);

Future<void> _pumpGate(
  WidgetTester tester,
  SessionState session,
  DeviceRole target,
  void Function() onVerified, {
  bool offerSignOut = false,
}) async {
  await tester.pumpWidget(
    ChangeNotifierProvider.value(
      value: session,
      child: MaterialApp(
        home: Scaffold(
          body: ModeSwitchGate(
            targetRole: target,
            offerSignOut: offerSignOut,
            onVerified: onVerified,
          ),
        ),
      ),
    ),
  );
}

/// Fills the gate form and verifies with the correct password; on
/// offerSignOut gates this lands on the post-verify choice, not the
/// portal.
Future<void> _verifyWithCorrectPassword(WidgetTester tester) async {
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
}

void main() {
  group('ModeSwitchGate', () {
    testWidgets(
      'correct password verifies, persists the role, and calls back',
      (tester) async {
        final session = _makeSession();
        var verified = false;
        await _pumpGate(
          tester,
          session,
          DeviceRole.communicator,
          () => verified = true,
        );

        await tester.enterText(
          find.widgetWithText(TextField, 'Email or username'),
          'caregiver@example.com',
        );
        await tester.enterText(
          find.widgetWithText(TextField, 'Account password'),
          'correct-horse',
        );
        await tester.tap(find.text('Switch to communicator mode'));
        await tester.pumpAndSettle();

        expect(verified, isTrue);
        expect(session.deviceRole, DeviceRole.communicator);
      },
    );

    testWidgets(
      'wrong password shows the server message and keeps the role',
      (tester) async {
        final session = _makeSession();
        var verified = false;
        await _pumpGate(
          tester,
          session,
          DeviceRole.communicator,
          () => verified = true,
        );

        await tester.enterText(
          find.widgetWithText(TextField, 'Email or username'),
          'caregiver@example.com',
        );
        await tester.enterText(
          find.widgetWithText(TextField, 'Account password'),
          'wrong',
        );
        await tester.tap(find.text('Switch to communicator mode'));
        await tester.pumpAndSettle();

        expect(verified, isFalse);
        expect(session.deviceRole, isNull);
        expect(find.text('Wrong email or password.'), findsOneWidget);
      },
    );

    testWidgets('empty fields are refused without a network call', (
      tester,
    ) async {
      final session = _makeSession();
      var verified = false;
      await _pumpGate(
        tester,
        session,
        DeviceRole.caregiver,
        () => verified = true,
      );

      await tester.tap(find.text('Switch to caregiver mode'));
      await tester.pumpAndSettle();

      expect(verified, isFalse);
      expect(
        find.text('Enter your email/username and password.'),
        findsOneWidget,
      );
    });

    testWidgets(
      'verification does not disturb the active auth session',
      (tester) async {
        final session = _makeSession();
        // Simulate a signed-in session: the token the app is actually
        // using. A verification login must not sign this out.
        session.proxy.setToken('tok-original');
        session.proxySignedIn = true;
        await _pumpGate(
          tester,
          session,
          DeviceRole.communicator,
          () {},
        );

        await tester.enterText(
          find.widgetWithText(TextField, 'Email or username'),
          'caregiver@example.com',
        );
        await tester.enterText(
          find.widgetWithText(TextField, 'Account password'),
          'correct-horse',
        );
        await tester.tap(find.text('Switch to communicator mode'));
        await tester.pumpAndSettle();

        // Still signed in: the gate is a credential check, not a session
        // change.
        expect(session.proxySignedIn, isTrue);
      },
    );
  });

  group('ModeSwitchGate with sign-out offered (communicator-side entry)', () {
    testWidgets(
      'verified password shows both options and defers the role switch',
      (tester) async {
        final session = _makeSession();
        var verified = false;
        await _pumpGate(
          tester,
          session,
          DeviceRole.caregiver,
          () => verified = true,
          offerSignOut: true,
        );

        await _verifyWithCorrectPassword(tester);

        // Choice, not an immediate switch: no role persisted yet, no
        // callback fired.
        expect(find.text('Password confirmed'), findsOneWidget);
        expect(find.text('Open Caregiver Portal'), findsOneWidget);
        expect(find.text('Sign out this device'), findsOneWidget);
        expect(session.deviceRole, isNull);
        expect(verified, isFalse);
      },
    );

    testWidgets(
      'Open Caregiver Portal persists the role and calls back',
      (tester) async {
        final session = _makeSession();
        var verified = false;
        await _pumpGate(
          tester,
          session,
          DeviceRole.caregiver,
          () => verified = true,
          offerSignOut: true,
        );

        await _verifyWithCorrectPassword(tester);
        await tester.tap(find.text('Open Caregiver Portal'));
        await tester.pumpAndSettle();

        expect(verified, isTrue);
        expect(session.deviceRole, DeviceRole.caregiver);
      },
    );

    testWidgets(
      'sign-out confirms first, then clears the session and the role',
      (tester) async {
        final session = _makeSession();
        session.proxy.setToken('tok-original');
        session.proxySignedIn = true;
        session.deviceRole = DeviceRole.communicator;
        var verified = false;
        await _pumpGate(
          tester,
          session,
          DeviceRole.caregiver,
          () => verified = true,
          offerSignOut: true,
        );

        await _verifyWithCorrectPassword(tester);
        await tester.tap(find.text('Sign out this device'));
        await tester.pumpAndSettle();

        // Confirm dialog gates the destructive action.
        expect(find.text('Sign out this device?'), findsOneWidget);
        await tester.tap(find.text('Sign out'));
        await tester.pumpAndSettle();

        expect(verified, isFalse);
        expect(session.proxySignedIn, isFalse);
        expect(session.deviceRole, isNull);
        expect(
          await session.deviceRoleService.readRole(),
          isNull,
          reason: 'stored role cleared so the next launch asks again',
        );
      },
    );

    testWidgets(
      'canceling the sign-out confirm keeps the session intact',
      (tester) async {
        final session = _makeSession();
        session.proxy.setToken('tok-original');
        session.proxySignedIn = true;
        session.deviceRole = DeviceRole.communicator;
        var verified = false;
        await _pumpGate(
          tester,
          session,
          DeviceRole.caregiver,
          () => verified = true,
          offerSignOut: true,
        );

        await _verifyWithCorrectPassword(tester);
        await tester.tap(find.text('Sign out this device'));
        await tester.pumpAndSettle();

        expect(find.text('Sign out this device?'), findsOneWidget);
        await tester.tap(find.text('Cancel'));
        await tester.pumpAndSettle();

        // Nothing happened: still signed in, role untouched, choice
        // still on screen.
        expect(session.proxySignedIn, isTrue);
        expect(session.deviceRole, DeviceRole.communicator);
        expect(verified, isFalse);
        expect(find.text('Open Caregiver Portal'), findsOneWidget);
      },
    );
  });
}
