import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:onevoz/models/safe_zone.dart';
import 'package:onevoz/models/word.dart';
import 'package:onevoz/screens/caregiver_portal_screen.dart';
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

/// In-memory keychain double.
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

/// Mutable fake device registry backing the MockClient.
class _FakeDeviceBackend {
  final devices = <Map<String, dynamic>>[
    {
      'install_id': 'dev-self',
      'device_name': 'Caregiver phone',
      'platform': 'iOS',
      'last_seen_at': '2026-09-16T20:00:00.000Z',
    },
    {
      'install_id': 'dev-lost',
      'device_name': 'Lost iPad',
      'platform': 'iOS',
      'last_seen_at': '2026-09-10T12:00:00.000Z',
    },
  ];
  final deletedPaths = <String>[];

  MockClient get client => MockClient((request) async {
    final path = request.url.path;
    if (request.method == 'GET' && path == '/v1/devices') {
      return http.Response(
        json.encode({
          'device_slots': 3,
          'subscription_tier': 'base',
          'devices_used': devices.length,
          'devices': devices,
        }),
        200,
      );
    }
    if (request.method == 'DELETE' && path.startsWith('/v1/devices/')) {
      deletedPaths.add(path);
      devices.removeWhere(
        (d) => d['install_id'] == path.split('/').last,
      );
      return http.Response('{}', 200);
    }
    return http.Response('not found', 404);
  });
}

Future<SessionState> _makeSession(_FakeDeviceBackend backend) async {
  SharedPreferences.setMockInitialValues({
    'vidavoice.onboardingComplete': true,
  });
  final store = _FakeSecureStore();
  // Pin the install id so the fake backend can mark "this device".
  store.map['vidavoice.proxy.installId'] = 'dev-self';
  final session = SessionState(
    tts: _FakeTts(),
    proxy: ProxyClient(client: backend.client, baseUrl: 'https://proxy.test'),
    proxyAuth: ProxyAuthStore(store: store),
    deviceRoleService: DeviceRoleService(store: store),
  );
  session.pack = _loadPack('en');
  session.status = BootStatus.ready;
  session.onboardingComplete = true;
  session.proxySignedIn = true;
  session.proxy.setToken('tok-test');
  session.deviceRole = DeviceRole.caregiver;
  await session.profiles.load();
  return session;
}

Future<void> _pumpPortal(WidgetTester tester, SessionState session) async {
  tester.view.physicalSize = const Size(1400, 2400);
  tester.view.devicePixelRatio = 1.0;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);
  await tester.pumpWidget(
    ChangeNotifierProvider.value(
      value: session,
      child: const MaterialApp(home: CaregiverPortalScreen()),
    ),
  );
  await tester.pumpAndSettle();
}

void main() {
  group('CaregiverPortalScreen', () {
    testWidgets('renders all five tabs', (tester) async {
      final session = await _makeSession(_FakeDeviceBackend());
      await _pumpPortal(tester, session);

      expect(find.text('Caregiver Portal'), findsOneWidget);
      for (final label in [
        'Devices',
        'Safe Zones',
        'Alerts',
        'Profiles',
        'Account',
      ]) {
        expect(find.text(label), findsWidgets);
      }
    });

    testWidgets('devices tab lists devices and marks this one', (
      tester,
    ) async {
      final session = await _makeSession(_FakeDeviceBackend());
      await _pumpPortal(tester, session);

      expect(find.text('Caregiver phone'), findsOneWidget);
      expect(find.text('Lost iPad'), findsOneWidget);
      expect(find.text('This device'), findsOneWidget);
      expect(
        find.text('2 of 3 device licenses in use.'),
        findsOneWidget,
      );
    });

    testWidgets('revoking a device calls delete and refreshes the list', (
      tester,
    ) async {
      final backend = _FakeDeviceBackend();
      final session = await _makeSession(backend);
      await _pumpPortal(tester, session);

      // Revoke the lost iPad.
      await tester.tap(find.widgetWithText(TextButton, 'Revoke').last);
      await tester.pumpAndSettle();
      expect(find.text('Revoke "Lost iPad"?'), findsOneWidget);
      await tester.tap(find.text('Revoke device'));
      await tester.pumpAndSettle();

      expect(backend.deletedPaths, contains('/v1/devices/dev-lost'));
      expect(find.text('Lost iPad'), findsNothing);
      expect(find.text('Caregiver phone'), findsOneWidget);
    });

    testWidgets('a device can be assigned to a profile', (tester) async {
      final session = await _makeSession(_FakeDeviceBackend());
      await _pumpPortal(tester, session);

      await tester.tap(find.text('Assign to profile').first);
      await tester.pumpAndSettle();
      await tester.tap(find.text('My Voice').last);
      await tester.pumpAndSettle();

      expect(
        session.dashboardSync.deviceAssignments['dev-self'],
        isNotNull,
      );
      expect(find.text('For My Voice'), findsOneWidget);
    });

    testWidgets('safe zones tab mounts the zone list', (tester) async {
      final session = await _makeSession(_FakeDeviceBackend());
      await session.dashboardSync.upsertSafeZone(
        SafeZone(
          id: 'zone_aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa',
          name: 'Home',
          lat: 40.1,
          lng: -111.9,
          radiusM: 300,
          enabled: true,
          notifyEnter: true,
          notifyExit: false,
          updatedTs: DateTime.fromMillisecondsSinceEpoch(1000),
        ),
      );
      await _pumpPortal(tester, session);

      await tester.tap(find.text('Safe Zones'));
      await tester.pumpAndSettle();

      expect(find.text('Safe zones'), findsOneWidget);
      expect(find.text('Home'), findsOneWidget);
    });

    testWidgets('alerts tab is a visible coming-soon placeholder', (
      tester,
    ) async {
      final session = await _makeSession(_FakeDeviceBackend());
      await _pumpPortal(tester, session);

      await tester.tap(find.text('Alerts'));
      await tester.pumpAndSettle();

      expect(find.text('Coming soon'), findsOneWidget);
      expect(find.text('Alert history'), findsOneWidget);
    });

    testWidgets('profiles tab lists profiles read-only', (tester) async {
      final session = await _makeSession(_FakeDeviceBackend());
      await _pumpPortal(tester, session);

      await tester.tap(find.text('Profiles'));
      await tester.pumpAndSettle();

      expect(find.text('My Voice'), findsWidgets);
      expect(find.textContaining('Tap to speak'), findsOneWidget);
    });

    testWidgets('account tab offers mode switch and sign out', (
      tester,
    ) async {
      final session = await _makeSession(_FakeDeviceBackend());
      await _pumpPortal(tester, session);

      await tester.tap(find.text('Account'));
      await tester.pumpAndSettle();

      expect(find.text('Switch to communicator mode'), findsOneWidget);
      expect(find.text('Sign out'), findsOneWidget);
    });

    testWidgets('offline devices tab shows an honest error with retry', (
      tester,
    ) async {
      SharedPreferences.setMockInitialValues({
        'vidavoice.onboardingComplete': true,
      });
      final store = _FakeSecureStore();
      final session = SessionState(
        tts: _FakeTts(),
        proxy: ProxyClient(
          client: MockClient(
            (_) async => throw const SocketException('offline'),
          ),
          baseUrl: 'https://proxy.test',
        ),
        proxyAuth: ProxyAuthStore(store: store),
        deviceRoleService: DeviceRoleService(store: store),
      );
      session.pack = _loadPack('en');
      session.status = BootStatus.ready;
      session.proxySignedIn = true;
      session.proxy.setToken('tok-test');
      session.deviceRole = DeviceRole.caregiver;
      await session.profiles.load();
      await _pumpPortal(tester, session);

      expect(find.textContaining('Couldn\u2019t reach'), findsOneWidget);
      expect(find.text('Try again'), findsOneWidget);
    });
  });
}
