import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/testing.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:onevoz/main.dart';
import 'package:onevoz/models/word.dart';
import 'package:onevoz/screens/caregiver_portal_screen.dart';
import 'package:onevoz/screens/device_role_screen.dart';
import 'package:onevoz/screens/home_board_screen.dart';
import 'package:onevoz/services/device_role_service.dart';
import 'package:onevoz/services/elevenlabs_key_store.dart';
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

LanguagePack _loadPack(String locale) {
  final raw = File('assets/lang/$locale.json').readAsStringSync();
  final pack = LanguagePack.fromJson(
    Map<String, dynamic>.from(json.decode(raw) as Map),
  );
  pack.validate();
  return pack;
}

Future<SessionState> _makeSession({
  _FakeSecureStore? secureStore,
  DeviceRole? role,
}) async {
  SharedPreferences.setMockInitialValues({
    'vidavoice.onboardingComplete': true,
  });
  final store = secureStore ?? _FakeSecureStore();
  final roleService = DeviceRoleService(store: store);
  if (role != null) await roleService.writeRole(role);
  final session = SessionState(
    tts: _FakeTts(),
    proxy: ProxyClient(
      client: MockClient(
        (_) async => throw const SocketException('offline'),
      ),
      baseUrl: 'https://proxy.test',
    ),
    proxyAuth: ProxyAuthStore(store: store),
    deviceRoleService: roleService,
  );
  session.pack = _loadPack('en');
  session.status = BootStatus.ready;
  session.onboardingComplete = true;
  session.proxySignedIn = true;
  session.proxy.setToken('tok-test');
  session.deviceRole = role;
  await session.profiles.load();
  return session;
}

Future<void> _pumpApp(WidgetTester tester, SessionState session) async {
  tester.view.physicalSize = const Size(1600, 2400);
  tester.view.devicePixelRatio = 1.0;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);
  await tester.pumpWidget(OneVozApp(session: session));
  await tester.pumpAndSettle();
}

void main() {
  group('device role routing', () {
    testWidgets('signed in with no role shows the role question', (
      tester,
    ) async {
      final session = await _makeSession();
      await _pumpApp(tester, session);

      expect(find.byType(DeviceRoleScreen), findsOneWidget);
      expect(find.text('Who is this device for?'), findsOneWidget);
      // No portal, no boards yet.
      expect(find.byType(CaregiverPortalScreen), findsNothing);
      expect(find.byType(HomeBoardScreen), findsNothing);
    });

    testWidgets('choosing Communicator routes to the boards', (tester) async {
      final session = await _makeSession();
      await _pumpApp(tester, session);

      await tester.tap(find.text('Communicator'));
      await tester.pumpAndSettle();

      expect(session.deviceRole, DeviceRole.communicator);
      expect(find.byType(HomeBoardScreen), findsOneWidget);
      expect(find.byType(CaregiverPortalScreen), findsNothing);
    });

    testWidgets('choosing Caregiver routes to the portal', (tester) async {
      final session = await _makeSession();
      await _pumpApp(tester, session);

      await tester.tap(find.text('Caregiver'));
      await tester.pumpAndSettle();

      expect(session.deviceRole, DeviceRole.caregiver);
      expect(find.byType(CaregiverPortalScreen), findsOneWidget);
      expect(find.byType(HomeBoardScreen), findsNothing);
    });

    testWidgets('a persisted role skips the question on next boot', (
      tester,
    ) async {
      final store = _FakeSecureStore();
      // First "boot": answer the question.
      final first = await _makeSession(secureStore: store);
      await _pumpApp(tester, first);
      await tester.tap(find.text('Caregiver'));
      await tester.pumpAndSettle();
      expect(find.byType(CaregiverPortalScreen), findsOneWidget);

      // Second "boot" with the same device storage: straight to portal.
      final second = await _makeSession(secureStore: store);
      // Simulate boot() reading the persisted role.
      second.deviceRole = await second.deviceRoleService.readRole();
      await _pumpApp(tester, second);

      expect(find.byType(DeviceRoleScreen), findsNothing);
      expect(find.byType(CaregiverPortalScreen), findsOneWidget);
    });

    testWidgets('communicator boards carry no portal entry point', (
      tester,
    ) async {
      final session = await _makeSession(role: DeviceRole.communicator);
      await _pumpApp(tester, session);

      expect(find.byType(HomeBoardScreen), findsOneWidget);
      // The old hub button is gone; the portal is unreachable by tap.
      expect(find.byTooltip('Caregiver'), findsNothing);
      expect(find.byType(CaregiverPortalScreen), findsNothing);
    });
  });

  group('DeviceRoleScreen', () {
    testWidgets('both options are tappable and persist', (tester) async {
      final session = await _makeSession();
      await tester.pumpWidget(
        ChangeNotifierProvider.value(
          value: session,
          child: const MaterialApp(home: DeviceRoleScreen()),
        ),
      );

      expect(find.text('Communicator'), findsOneWidget);
      expect(find.text('Caregiver'), findsOneWidget);

      await tester.tap(find.text('Communicator'));
      await tester.pumpAndSettle();
      expect(session.deviceRole, DeviceRole.communicator);
      expect(
        await session.deviceRoleService.readRole(),
        DeviceRole.communicator,
      );
    });
  });
}
