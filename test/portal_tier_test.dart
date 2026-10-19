import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:onevoz/models/word.dart';
import 'package:onevoz/screens/caregiver_portal_screen.dart';
import 'package:onevoz/services/device_role_service.dart';
import 'package:onevoz/services/elevenlabs_key_store.dart';
import 'package:onevoz/services/proxy_client.dart';
import 'package:onevoz/services/tts_service.dart';
import 'package:onevoz/state/session_state.dart';

class _FakeTts extends TtsService {
  @override
  bool get usesCloudVoice => false;
  @override
  Future<void> speak(String text, {bool ignoreThrottle = false}) async {}
  @override
  Future<void> stop() async {}
}

class _FakeSecureStore implements SecureValueStore {
  final Map<String, String> map = {};
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

Future<SessionState> _makeSession() async {
  SharedPreferences.setMockInitialValues({
    'vidavoice.onboardingComplete': true,
  });
  final store = _FakeSecureStore();
  final session = SessionState(
    tts: _FakeTts(),
    proxy: ProxyClient(baseUrl: 'https://proxy.test'),
    proxyAuth: ProxyAuthStore(store: store),
    deviceRoleService: DeviceRoleService(store: store),
  );
  session.pack = _loadPack('en');
  session.status = BootStatus.ready;
  session.onboardingComplete = true;
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
  group('PortalTier', () {
    test('includes is cumulative and fromName defaults to basic', () {
      expect(PortalTier.basic.includes(PortalTier.basic), isTrue);
      expect(PortalTier.basic.includes(PortalTier.moderate), isFalse);
      expect(PortalTier.moderate.includes(PortalTier.basic), isTrue);
      expect(PortalTier.advanced.includes(PortalTier.moderate), isTrue);
      expect(PortalTier.fromName(null), PortalTier.basic);
      expect(PortalTier.fromName('bogus'), PortalTier.basic);
      expect(PortalTier.fromName('advanced'), PortalTier.advanced);
    });

    test('setPortalTier persists the choice', () async {
      final session = await _makeSession();
      expect(session.portalTier, PortalTier.basic);
      await session.setPortalTier(PortalTier.moderate);
      expect(session.portalTier, PortalTier.moderate);
      final prefs = await SharedPreferences.getInstance();
      expect(prefs.getString('vidavoice.portal.tier'), 'moderate');
    });
  });

  group('portal tier folding', () {
    testWidgets('basic shows four tabs and the essential sections only', (
      tester,
    ) async {
      final session = await _makeSession();
      await _pumpPortal(tester, session);
      // Tabs: Content, Profiles, Safety, Account — no Devices/Alerts/
      // Settings yet.
      expect(find.text('Content'), findsWidgets);
      expect(find.text('Profiles'), findsWidgets);
      expect(find.text('Devices'), findsNothing);
      expect(find.text('Alerts'), findsNothing);
      // Content tab essentials are here; moderate sections are folded.
      expect(find.text('Personal dashboard'), findsOneWidget);
      expect(find.text('First week plan'), findsOneWidget);
      expect(find.text('Vocabulary level'), findsNothing);
      expect(find.text('Custom symbols'), findsNothing);
      // The switcher explains itself in Basic.
      expect(find.textContaining('Showing the essentials'), findsOneWidget);
    });

    testWidgets('moderate adds Devices and Settings tabs and sections', (
      tester,
    ) async {
      final session = await _makeSession();
      session.portalTier = PortalTier.moderate;
      await _pumpPortal(tester, session);
      expect(find.text('Devices'), findsWidgets);
      expect(find.text('Alerts'), findsNothing);
      expect(find.text('Vocabulary level'), findsOneWidget);
      expect(find.text('Custom symbols'), findsOneWidget);
      // Settings tab: voice is here, advanced sections still folded.
      await tester.tap(find.text('Settings'));
      await tester.pumpAndSettle();
      expect(find.text('Voice & speech'), findsOneWidget);
      expect(find.text('Backup & sync'), findsNothing);
      expect(find.text('Device sync'), findsNothing);
    });

    testWidgets('the switcher raises the tier live', (tester) async {
      final session = await _makeSession();
      await _pumpPortal(tester, session);
      expect(find.text('Alerts'), findsNothing);
      await tester.tap(find.text('Advanced'));
      await tester.pumpAndSettle();
      expect(session.portalTier, PortalTier.advanced);
      expect(find.text('Alerts'), findsWidgets);
      expect(find.text('Devices'), findsWidgets);
    });

    testWidgets('lowering the tier on a folded tab lands safely', (
      tester,
    ) async {
      final session = await _makeSession();
      session.portalTier = PortalTier.advanced;
      await _pumpPortal(tester, session);
      await tester.tap(find.text('Alerts'));
      await tester.pumpAndSettle();
      expect(find.text('Alert history'), findsOneWidget);
      await session.setPortalTier(PortalTier.basic);
      await tester.pumpAndSettle();
      // No crash, no dangling index: the portal shows a visible tab.
      expect(find.text('Alerts'), findsNothing);
      expect(find.text('Personal dashboard'), findsOneWidget);
    });
  });
}
