import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:voicesimple/screens/onboarding_screen.dart';
import 'package:voicesimple/services/elevenlabs_key_store.dart';
import 'package:voicesimple/services/proxy_client.dart';
import 'package:voicesimple/services/tts_service.dart';
import 'package:voicesimple/state/session_state.dart';

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

Map<String, dynamic> _authBody() => {
  'token': 'tok-1',
  'token_type': 'Bearer',
  'expires_in': 3600,
  'family_id': 'fam-1',
  'profile_ids': ['p1'],
  'caregiver_id': 'cg-1',
};

Map<String, dynamic> _registrationBody() => {
  'device': {'install_id': 'install-1'},
  'device_slots': 3,
  'subscription_tier': 'base',
  'devices_used': 1,
};

void main() {
  Future<SessionState> makeSession({
    Future<http.Response> Function(http.Request)? proxyHandler,
  }) async {
    SharedPreferences.setMockInitialValues({});
    final session = SessionState(
      tts: _FakeTts(),
      proxy: ProxyClient(
        client: MockClient(
          proxyHandler ?? (_) async => throw const SocketException('nope'),
        ),
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

  /// Welcome page -> account page.
  Future<void> goToAccountPage(WidgetTester tester) async {
    await tester.tap(find.text('Continue'));
    await tester.pumpAndSettle();
    expect(find.text('Your VoiceSimple account'), findsOneWidget);
  }

  Future<void> tapFormButton(WidgetTester tester, Finder finder) async {
    await tester.ensureVisible(finder);
    await tester.pumpAndSettle();
    await tester.tap(finder);
    await tester.pumpAndSettle();
  }

  Finder fieldWithLabel(String label) => find.byWidgetPredicate(
    (w) => w is TextField && (w.decoration?.labelText == label),
  );

  Future<void> fillSignup(
    WidgetTester tester, {
    String email = 'caregiver@example.org',
    String username = 'maya_mom',
    String password = 'a-strong-password-1',
  }) async {
    await tester.enterText(fieldWithLabel('Email'), email);
    await tester.enterText(fieldWithLabel('Username'), username);
    await tester.enterText(fieldWithLabel('Password'), password);
    await tester.pump();
  }

  group('onboarding skip paths', () {
    testWidgets('Skip for now completes onboarding from the welcome page', (
      tester,
    ) async {
      final session = await makeSession();
      await pumpOnboarding(tester, session);
      await tester.tap(find.text('Skip for now'));
      await tester.pumpAndSettle();
      expect(session.onboardingComplete, isTrue);
      expect(session.proxySignedIn, isFalse);
    });

    testWidgets('Continue walks every page and finishes', (tester) async {
      final session = await makeSession();
      await pumpOnboarding(tester, session);
      // Pages: welcome, account (defer), profile, import, customize,
      // voice, tour. The account page hides the global Continue, so the
      // form's defer button advances it.
      for (var i = 0; i < 7; i++) {
        await tester.pumpAndSettle();
        if (find.text('Your VoiceSimple account').evaluate().isNotEmpty) {
          await tapFormButton(
            tester,
            find.text('Continue with on-device voices for now'),
          );
        } else if (find.text('Start communicating').evaluate().isNotEmpty) {
          await tester.tap(find.text('Start communicating'));
        } else {
          await tester.tap(find.text('Continue'));
        }
      }
      await tester.pumpAndSettle();
      expect(session.onboardingComplete, isTrue);
      expect(session.accountDeferred, isTrue);
    });
  });

  group('account step', () {
    testWidgets('defer continues without an account and sets accountDeferred', (
      tester,
    ) async {
      final session = await makeSession();
      await pumpOnboarding(tester, session);
      await goToAccountPage(tester);

      await tapFormButton(
        tester,
        find.text('Continue with on-device voices for now'),
      );

      expect(session.accountDeferred, isTrue);
      expect(session.proxySignedIn, isFalse);
      // Advanced to the profile-name step.
      expect(find.text('Who will use VoiceSimple?'), findsOneWidget);
    });

    testWidgets('offline signup shows plain-language error, stays on step', (
      tester,
    ) async {
      final session = await makeSession(); // default handler: unreachable
      await pumpOnboarding(tester, session);
      await goToAccountPage(tester);

      await fillSignup(tester);
      await tapFormButton(tester, find.text('Create account'));

      expect(
        find.textContaining('Couldn\u2019t reach the VoiceSimple service'),
        findsOneWidget,
      );
      expect(session.proxySignedIn, isFalse);
      // Still on the account step — nothing advanced behind our back.
      expect(find.text('Your VoiceSimple account'), findsOneWidget);
    });

    testWidgets('successful signup signs in and advances', (tester) async {
      final session = await makeSession(
        proxyHandler: (req) async {
          if (req.url.path == '/v1/auth/signup') {
            return http.Response(json.encode(_authBody()), 201);
          }
          if (req.url.path == '/v1/devices/register') {
            return http.Response(json.encode(_registrationBody()), 201);
          }
          return http.Response('not found', 404);
        },
      );
      await pumpOnboarding(tester, session);
      await goToAccountPage(tester);

      await fillSignup(tester);
      await tapFormButton(tester, find.text('Create account'));

      expect(session.proxySignedIn, isTrue);
      expect(session.proxyFamilyId, 'fam-1');
      expect(session.accountDeferred, isFalse);
      // Speech meters against the server-issued profile id, never the
      // app's local profile UUIDs.
      expect(session.tts.proxyProfileIdProvider?.call(), 'p1');
      await session.signOut();
      expect(session.tts.proxyProfileIdProvider?.call(), isNull);
      expect(find.text('Who will use VoiceSimple?'), findsOneWidget);
    });

    testWidgets('login 401 maps to a plain-language message', (tester) async {
      final session = await makeSession(
        proxyHandler: (_) async => http.Response(
          json.encode({
            'error': {'code': 'invalid_credentials', 'message': 'Nope.'},
          }),
          401,
        ),
      );
      await pumpOnboarding(tester, session);
      await goToAccountPage(tester);

      await tapFormButton(
        tester,
        find.widgetWithText(SegmentedButton<bool>, 'Log in'),
      ); // switch to login mode
      await tester.enterText(fieldWithLabel('Email or username'), 'maya_mom');
      await tester.enterText(fieldWithLabel('Password'), 'wrong-password-1');
      await tester.pump();
      // The segmented control has a "Log in" segment AND the submit
      // button says "Log in" — tap the submit (FilledButton) one.
      await tapFormButton(tester, find.widgetWithText(FilledButton, 'Log in'));

      expect(
        find.text(
          'That email/username and password didn\u2019t match. Try again.',
        ),
        findsOneWidget,
      );
      expect(session.proxySignedIn, isFalse);
    });

    testWidgets('local validation catches a weak password before the network', (
      tester,
    ) async {
      var calls = 0;
      final session = await makeSession(
        proxyHandler: (_) async {
          calls++;
          return http.Response('{}', 200);
        },
      );
      await pumpOnboarding(tester, session);
      await goToAccountPage(tester);

      await fillSignup(tester, password: 'short');
      await tapFormButton(tester, find.text('Create account'));

      expect(calls, 0);
      expect(
        find.text('Use a password of at least 10 characters.'),
        findsOneWidget,
      );
    });
  });
}
