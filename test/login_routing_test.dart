import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:onevoz/main.dart';
import 'package:onevoz/models/word.dart';
import 'package:onevoz/screens/home_board_screen.dart';
import 'package:onevoz/screens/sign_in_gate_screen.dart';
import 'package:onevoz/services/elevenlabs_key_store.dart';
import 'package:onevoz/services/device_role_service.dart';
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
  Future<void> speak(String text) async {}
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

void main() {
  LanguagePack loadPackFromFile(String locale) {
    final raw = File('assets/lang/$locale.json').readAsStringSync();
    final pack = LanguagePack.fromJson(
      Map<String, dynamic>.from(json.decode(raw) as Map),
    );
    pack.validate();
    return pack;
  }

  Future<SessionState> makeSession({
    bool onboardingComplete = true,
    bool signedIn = false,
    Future<http.Response> Function(http.Request)? proxyHandler,
    _FakeSecureStore? secureStore,
    DeviceRole? role = DeviceRole.communicator,
  }) async {
    SharedPreferences.setMockInitialValues({
      'vidavoice.onboardingComplete': onboardingComplete,
    });
    final store = secureStore ?? _FakeSecureStore();
    final roleService = DeviceRoleService(store: store);
    if (role != null) await roleService.writeRole(role);
    final session = SessionState(
      tts: _FakeTts(),
      proxy: ProxyClient(
        client: MockClient(
          proxyHandler ?? (_) async => throw const SocketException('offline'),
        ),
        baseUrl: 'https://proxy.test',
      ),
      proxyAuth: ProxyAuthStore(store: store),
      deviceRoleService: roleService,
    );
    session.deviceRole = role;
    session.pack = loadPackFromFile('en');
    session.status = BootStatus.ready;
    session.onboardingComplete = onboardingComplete;
    session.proxySignedIn = signedIn;
    if (signedIn) {
      // A signed-in session carries a token (real sign-ins always set
      // one). The mock backend stays offline by default.
      session.proxy.setToken('tok-test');
    }
    await session.profiles.load();
    await session.plan.load(session.profiles.active?.id ?? '');
    return session;
  }

  Future<void> pumpApp(WidgetTester tester, SessionState session) async {
    tester.view.physicalSize = const Size(1600, 2400);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    await tester.pumpWidget(OneVozApp(session: session));
    await tester.pumpAndSettle();
  }

  group('login routing', () {
    testWidgets('onboarded without a session shows the sign-in gate', (
      tester,
    ) async {
      final session = await makeSession(signedIn: false);
      await pumpApp(tester, session);

      expect(find.byType(SignInGateScreen), findsOneWidget);
      expect(find.text('Sign in to OneVoz'), findsOneWidget);
      expect(find.byType(HomeBoardScreen), findsNothing);
    });

    testWidgets('onboarded with a cached session shows the board', (
      tester,
    ) async {
      final session = await makeSession(signedIn: true);
      await pumpApp(tester, session);

      expect(find.byType(HomeBoardScreen), findsOneWidget);
      expect(find.byType(SignInGateScreen), findsNothing);
    });

    testWidgets('incomplete onboarding routes to the wizard, not the gate', (
      tester,
    ) async {
      final session = await makeSession(
        onboardingComplete: false,
        signedIn: false,
      );
      await pumpApp(tester, session);

      expect(find.text('Welcome to OneVoz'), findsOneWidget);
      expect(find.byType(SignInGateScreen), findsNothing);
    });

    testWidgets(
      'signed out with no device role sees the role question first',
      (tester) async {
        // Post-sign-out state: the role question (per-device) precedes
        // the sign-in gate (per-account).
        final session = await makeSession(signedIn: false, role: null);
        await pumpApp(tester, session);

        expect(find.text('Who is this device for?'), findsOneWidget);
        expect(find.byType(SignInGateScreen), findsNothing);
      },
    );
  });

  group('cached session', () {
    test('boot restores the session while offline', () async {
      // A stored token means the caregiver signed in before; the proxy
      // is unreachable (offline) but boot must keep the session.
      final store = _FakeSecureStore();
      await store.write('vidavoice.proxy.token', 'tok-cached');
      await store.write('vidavoice.proxy.familyId', 'fam-1');
      final session = await makeSession(
        signedIn: false, // boot must restore this from the stored token
        secureStore: store,
      );

      await session.boot();

      expect(session.status, BootStatus.ready);
      expect(
        session.proxySignedIn,
        isTrue,
        reason:
            'a cached token keeps the session offline; '
            'AAC must never be blocked by a cloud failure',
      );
    });

    test('boot without any cached token stays signed out', () async {
      final session = await makeSession(signedIn: false);

      await session.boot();

      expect(session.status, BootStatus.ready);
      expect(session.proxySignedIn, isFalse);
    });
  });
}
