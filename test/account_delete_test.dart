// Account deletion (Portal → Account → Delete account): the danger
// zone renders for owners and joined members with truthful copy; the
// confirmation dialog stays disarmed until the password is entered
// AND "DELETE" is typed; a wrong password calls the endpoint once,
// shows the error, and changes nothing; the right password deletes,
// shows the confirmation, and Done tears the session down to signed
// out with the one-shot banner set.

import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:onevoz/screens/portal/account_tab.dart';
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

class _FakeSecureStore implements SecureValueStore {
  final map = <String, String>{};

  @override
  Future<String?> read(String key) async => map[key];

  @override
  Future<void> write(String key, String value) async => map[key] = value;

  @override
  Future<void> delete(String key) async => map.remove(key);
}

const _goodCredential = 'correct horse battery';

/// Fake backend: only DELETE /v1/account is implemented; it checks the
/// credential in the request body like the real worker does.
class _DeleteBackend {
  int deleteCalls = 0;
  String? lastMethod;
  String? lastPath;

  MockClient get client => MockClient((request) async {
    if (request.method == 'DELETE' && request.url.path == '/v1/account') {
      deleteCalls += 1;
      lastMethod = request.method;
      lastPath = request.url.path;
      final decoded = json.decode(request.body) as Map<String, dynamic>;
      if (decoded['password'] == _goodCredential) {
        return http.Response(
          json.encode({
            'ok': true,
            'account_deleted': true,
            'family_deleted': true,
            'family_id': 'fam_test',
          }),
          200,
        );
      }
      return http.Response(
        json.encode({
          'error': {
            'code': 'invalid_password',
            'message': 'That password is incorrect. Nothing was deleted.',
          },
        }),
        401,
      );
    }
    return http.Response('{"error":{"code":"not_found"}}', 404);
  });
}

Future<SessionState> _makeSession(_DeleteBackend backend) async {
  SharedPreferences.setMockInitialValues({'vidavoice.onboardingComplete': true});
  final store = _FakeSecureStore();
  store.map['vidavoice.proxy.installId'] = 'dev-self';
  final session = SessionState(
    tts: _FakeTts(),
    proxy: ProxyClient(client: backend.client, baseUrl: 'https://proxy.test'),
    proxyAuth: ProxyAuthStore(store: store),
    deviceRoleService: DeviceRoleService(store: store),
  );
  session.status = BootStatus.ready;
  session.onboardingComplete = true;
  session.proxySignedIn = true;
  session.proxyFamilyId = 'fam_test';
  session.proxy.setToken('tok-test');
  session.deviceRole = DeviceRole.caregiver;
  return session;
}

Future<void> _pumpTab(WidgetTester tester, SessionState session) async {
  await tester.pumpWidget(
    MaterialApp(
      home: ChangeNotifierProvider<SessionState>.value(
        value: session,
        child: const Scaffold(body: PortalAccountTab()),
      ),
    ),
  );
  await tester.pumpAndSettle();
}

Future<void> _openDialog(WidgetTester tester) async {
  final button = find.widgetWithText(OutlinedButton, 'Delete account');
  await tester.scrollUntilVisible(button, 200);
  await tester.pumpAndSettle();
  await tester.tap(button);
  await tester.pumpAndSettle();
  expect(find.text('Delete your account?'), findsOneWidget);
}

void main() {
  testWidgets('danger zone renders with owner copy', (tester) async {
    final backend = _DeleteBackend();
    final session = await _makeSession(backend);
    await _pumpTab(tester, session);

    final button = find.widgetWithText(OutlinedButton, 'Delete account');
    await tester.scrollUntilVisible(button, 200);
    await tester.pumpAndSettle();
    expect(find.text('Delete account'), findsWidgets);
    expect(find.textContaining('permanently deletes'), findsOneWidget);
    expect(backend.deleteCalls, 0);
  });

  testWidgets('danger zone uses member copy in a joined family', (
    tester,
  ) async {
    final backend = _DeleteBackend();
    final session = await _makeSession(backend);
    session.accountHomeFamilyId = 'fam_home';
    session.proxyFamilyId = 'fam_joined';
    await _pumpTab(tester, session);

    final button = find.widgetWithText(OutlinedButton, 'Delete account');
    await tester.scrollUntilVisible(button, 200);
    await tester.pumpAndSettle();
    expect(find.textContaining('permanently removes you'), findsOneWidget);
  });

  testWidgets('delete button stays disarmed until password + DELETE', (
    tester,
  ) async {
    final backend = _DeleteBackend();
    final session = await _makeSession(backend);
    await _pumpTab(tester, session);
    await _openDialog(tester);

    FilledButton deleteButton() => tester.widget<FilledButton>(
      find.widgetWithText(FilledButton, 'Delete my account'),
    );
    expect(deleteButton().onPressed, isNull);

    await tester.enterText(find.byType(TextField).first, _goodCredential);
    await tester.pumpAndSettle();
    expect(deleteButton().onPressed, isNull);

    await tester.enterText(find.byType(TextField).last, 'DELET');
    await tester.pumpAndSettle();
    expect(deleteButton().onPressed, isNull);

    await tester.enterText(find.byType(TextField).last, 'DELETE');
    await tester.pumpAndSettle();
    expect(deleteButton().onPressed, isNotNull);
    expect(backend.deleteCalls, 0);
  });

  testWidgets('wrong password: endpoint called once, error shown, '
      'session untouched', (tester) async {
    final backend = _DeleteBackend();
    final session = await _makeSession(backend);
    await _pumpTab(tester, session);
    await _openDialog(tester);

    await tester.enterText(find.byType(TextField).first, 'wrong credential');
    await tester.enterText(find.byType(TextField).last, 'DELETE');
    await tester.pumpAndSettle();
    await tester.tap(find.widgetWithText(FilledButton, 'Delete my account'));
    await tester.pumpAndSettle();

    expect(backend.deleteCalls, 1);
    expect(backend.lastMethod, 'DELETE');
    expect(backend.lastPath, '/v1/account');
    expect(
      find.text('That password is incorrect. Nothing was deleted.'),
      findsOneWidget,
    );
    // Still in the dialog, still signed in, no banner.
    expect(find.text('Delete your account?'), findsOneWidget);
    expect(session.proxySignedIn, isTrue);
    expect(session.proxy.hasToken, isTrue);
    expect(session.accountDeletedNotice, isNull);
  });

  testWidgets('successful delete: confirmation, then Done signs out '
      'with the banner set', (tester) async {
    final backend = _DeleteBackend();
    final session = await _makeSession(backend);
    await _pumpTab(tester, session);
    await _openDialog(tester);

    await tester.enterText(find.byType(TextField).first, _goodCredential);
    await tester.enterText(find.byType(TextField).last, 'DELETE');
    await tester.pumpAndSettle();
    await tester.tap(find.widgetWithText(FilledButton, 'Delete my account'));
    await tester.pumpAndSettle();

    expect(backend.deleteCalls, 1);
    expect(find.textContaining('Your account has been deleted.'), findsOneWidget);
    // Teardown hasn't run yet — the dialog owns the confirmation beat.
    expect(session.proxySignedIn, isTrue);

    await tester.tap(find.widgetWithText(FilledButton, 'Done'));
    await tester.pumpAndSettle();

    expect(session.proxySignedIn, isFalse);
    expect(session.proxy.hasToken, isFalse);
    expect(session.proxyFamilyId, isNull);
    expect(session.accountDeletedNotice, 'Your account has been deleted.');
  });
}
