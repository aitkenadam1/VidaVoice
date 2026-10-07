import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:onevoz/main.dart';
import 'package:onevoz/models/calling_safety.dart';
import 'package:onevoz/models/word.dart';
import 'package:onevoz/screens/build_board_screen.dart';
import 'package:onevoz/screens/home_board_screen.dart';
import 'package:onevoz/screens/portal/profiles_tab.dart';
import 'package:onevoz/screens/type_board_screen.dart';
import 'package:onevoz/services/device_role_service.dart';
import 'package:onevoz/services/elevenlabs_key_store.dart';
import 'package:onevoz/services/profile_service.dart';
import 'package:onevoz/services/proxy_client.dart';
import 'package:onevoz/services/tts_service.dart';
import 'package:onevoz/state/session_state.dart';
import 'package:onevoz/widgets/call_shortcut_button.dart';
import 'package:onevoz/widgets/emergency_shortcut_button.dart';
import 'package:onevoz/widgets/mode_switch_gate.dart';

/// Pinning tests for the 2026-10-07 independent app review: the
/// communicator boards must carry no Settings route and no sign-out
/// (B1), and removing a profile must ask first (M3). The mode-switch
/// gate must prove THIS family's caregiver (m2).

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

Future<SessionState> _makeAppSession({
  DeviceRole? role,
  CommunicationMode mode = CommunicationMode.tap,
}) async {
  SharedPreferences.setMockInitialValues({
    'vidavoice.onboardingComplete': true,
  });
  final store = _FakeSecureStore();
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
  final active = session.profiles.active;
  if (active != null && mode != CommunicationMode.tap) {
    await session.profiles.setCommunicationMode(active.id, mode);
  }
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
  group('B1: communicator boards have no Settings route or sign-out', () {
    for (final (mode, boardType) in <(CommunicationMode, Type)>[
      (CommunicationMode.tap, HomeBoardScreen),
      (CommunicationMode.build, BuildBoardScreen),
      (CommunicationMode.type, TypeBoardScreen),
    ]) {
      testWidgets('mode ${mode.name}: no settings gear, no sign out', (
        tester,
      ) async {
        final session = await _makeAppSession(
          role: DeviceRole.communicator,
          mode: mode,
        );
        await _pumpApp(tester, session);

        expect(find.byType(boardType), findsOneWidget);
        // The Settings gear used to push SettingsScreen, which carries the
        // account sign-out and API-key forms. None of that may be
        // reachable from an AAC board.
        expect(find.byIcon(Icons.settings), findsNothing);
        expect(find.text('Sign out'), findsNothing);
      });
    }
  });

  group('M3: removing a profile asks first', () {
    testWidgets('cancel keeps the profile; confirm removes it', (
      tester,
    ) async {
      SharedPreferences.setMockInitialValues({});
      final session = SessionState(tts: _FakeTts());
      await session.profiles.load();
      await session.profiles.addProfile('Second');
      expect(session.profiles.profiles, hasLength(2));

      await tester.pumpWidget(
        ChangeNotifierProvider<SessionState>.value(
          value: session,
          child: const MaterialApp(
            home: Scaffold(body: PortalProfilesTab()),
          ),
        ),
      );
      await tester.pumpAndSettle();

      // Both profiles show a remove button (more than one exists).
      expect(find.byTooltip('Remove profile'), findsWidgets);

      await tester.tap(find.byTooltip('Remove profile').first);
      await tester.pumpAndSettle();
      // A confirmation dialog must appear before anything is deleted.
      expect(find.text('Remove profile'), findsWidgets);
      expect(find.text('Cancel'), findsOneWidget);

      await tester.tap(find.text('Cancel'));
      await tester.pumpAndSettle();
      expect(session.profiles.profiles, hasLength(2));

      await tester.tap(find.byTooltip('Remove profile').first);
      await tester.pumpAndSettle();
      await tester.tap(find.widgetWithText(FilledButton, 'Remove profile'));
      await tester.pumpAndSettle();
      expect(session.profiles.profiles, hasLength(1));
    });
  });

  group('m1: the call sheet itself shows the number', () {
    testWidgets('contact name and phone number both appear', (tester) async {
      SharedPreferences.setMockInitialValues({});
      final session = SessionState(tts: _FakeTts());
      await session.profiles.load();
      final p = session.profiles.active!;
      // Two call contacts: with exactly one, the button dials directly
      // and the sheet never opens. The sheet is the multi-contact path.
      await session.profiles.setContacts(p.id, const [
        SafetyContact(id: 'mom', name: 'Mom', phone: '555-0100', kind: 'mom'),
        SafetyContact(id: 'dad', name: 'Dad', phone: '555-0102', kind: 'dad'),
      ]);
      session.pack = _loadPack('en');

      await tester.pumpWidget(
        ChangeNotifierProvider<SessionState>.value(
          value: session,
          child: MaterialApp(
            home: Scaffold(
              appBar: AppBar(
                actions: const [CallShortcutButton(), EmergencyShortcutButton()],
              ),
            ),
          ),
        ),
      );
      await tester.pump();

      await tester.tap(find.byIcon(Icons.call));
      await tester.pumpAndSettle();

      expect(find.text('Who do you want to call?'), findsOneWidget);
      expect(find.text('Mom'), findsOneWidget);
      expect(find.text('Dad'), findsOneWidget);
      // The numbers are visible on the sheet itself — before any tap on a
      // contact — not only on the confirm screen one step later.
      expect(find.text('555-0100'), findsOneWidget);
      expect(find.text('555-0102'), findsOneWidget);
    });
  });

  group('m2: the gate proves this family\'s caregiver', () {
    SessionState gateSession({required String sessionFamily}) {
      final session = SessionState(
        tts: _FakeTts(),
        proxy: ProxyClient(
          client: MockClient((request) async {
            if (request.url.path == '/v1/auth/login') {
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
        proxyAuth: ProxyAuthStore(store: _FakeSecureStore()),
        deviceRoleService: DeviceRoleService(store: _FakeSecureStore()),
      );
      session.proxyFamilyId = sessionFamily;
      session.deviceRole = DeviceRole.communicator;
      return session;
    }

    Future<void> pumpGate(WidgetTester tester, SessionState session) async {
      await tester.pumpWidget(
        ChangeNotifierProvider<SessionState>.value(
          value: session,
          child: MaterialApp(
            home: Scaffold(
              body: ModeSwitchGate(
                targetRole: DeviceRole.caregiver,
                offerSignOut: true,
                onVerified: () {},
              ),
            ),
          ),
        ),
      );
      await tester.enterText(
        find.widgetWithText(TextField, 'Email or username'),
        'someone@example.com',
      );
      await tester.enterText(
        find.widgetWithText(TextField, 'Account password'),
        'correct-horse',
      );
      await tester.tap(find.text('Switch to caregiver mode'));
      await tester.pumpAndSettle();
    }

    testWidgets('a valid login from a DIFFERENT family is refused', (
      tester,
    ) async {
      final session = gateSession(sessionFamily: 'fam_mine');
      await pumpGate(tester, session);

      expect(find.textContaining('different family'), findsOneWidget);
      expect(find.text('Password confirmed'), findsNothing);
      expect(session.deviceRole, DeviceRole.communicator);
    });

    testWidgets('this family\'s caregiver passes', (tester) async {
      final session = gateSession(sessionFamily: 'fam_1');
      await pumpGate(tester, session);

      expect(find.text('Password confirmed'), findsOneWidget);
    });
  });
}
