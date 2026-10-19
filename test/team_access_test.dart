import 'dart:convert';

import 'package:crypto/crypto.dart' as crypto;
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:onevoz/models/team.dart';
import 'package:onevoz/screens/portal/team_section.dart';
import 'package:onevoz/services/elevenlabs_key_store.dart';
import 'package:onevoz/services/proxy_client.dart';
import 'package:onevoz/services/tts_service.dart';
import 'package:onevoz/state/session_state.dart';

/// Team access, app side: invite creation wraps the family sync key with
/// the invite token (server only ever sees hashes and ciphertext), and
/// accepting switches the session into the joined family with that key.

class _FakeSecureStore implements SecureValueStore {
  final map = <String, String>{};
  @override
  Future<String?> read(String key) async => map[key];
  @override
  Future<void> write(String key, String value) async => map[key] = value;
  @override
  Future<void> delete(String key) async => map.remove(key);
}

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

/// A two-family fake backend. Family A is the owner's (child's) family;
/// family B is the therapist's own. Captures the invite creation body
/// so tests can verify the wrapping contract end to end.
class _TeamServer {
  Map<String, dynamic>? inviteBody;
  int version = 0;

  /// Email-flow emulation: the "server" generates this token, records
  /// that an email went out, and accepts the wrapped key afterwards.
  static const serverToken = 'server-generated-token-abc';
  String? emailedTo;
  String? attachedWrappedKey;
  String? attachedWrapSalt;

  static String saltB64(String seed) =>
      base64.encode(utf8.encode(seed.padRight(32, '0').substring(0, 32)));

  Map<String, dynamic> _roster({required bool memberView}) => {
    'family_id': 'fam-A',
    'you': memberView
        ? {
            'caregiver_id': 'cg-B',
            'is_owner': false,
            'role': 'speech_therapist',
            'permissions': {
              'dashboard': true,
              'content': true,
              'profiles': false,
              'safety': false,
              'team': false,
            },
          }
        : {
            'caregiver_id': 'cg-A',
            'is_owner': true,
            'role': 'owner',
            'permissions': {
              'dashboard': true,
              'content': true,
              'profiles': true,
              'safety': true,
              'team': true,
            },
          },
    'owner': {
      'caregiver_id': 'cg-A',
      'email': 'owner@example.org',
      'username': 'owner',
      'role': 'owner',
      'permissions': {
        'dashboard': true,
        'content': true,
        'profiles': true,
        'safety': true,
        'team': true,
      },
      'is_owner': true,
      'created_at': 1,
    },
    'members': memberView
        ? [
            {
              'caregiver_id': 'cg-B',
              'email': 'speech@example.org',
              'username': 'speech.pro',
              'role': 'speech_therapist',
              'permissions': {
                'dashboard': true,
                'content': true,
                'profiles': false,
                'safety': false,
                'team': false,
              },
              'is_owner': false,
              'created_at': 2,
            },
          ]
        : const [],
    'invites': const [],
  };

  Future<http.Response> handler(http.Request req) async {
    final path = req.url.path;
    final auth = req.headers['authorization'] ?? '';
    Map<String, dynamic> body() =>
        req.body.isEmpty ? {} : json.decode(req.body) as Map<String, dynamic>;

    if (path == '/v1/auth/login') {
      final id = body()['identifier'];
      if (id == 'owner@example.org') {
        return http.Response(
          json.encode({
            'token': 'tok-A',
            'family_id': 'fam-A',
            'profile_ids': ['pa1'],
            'caregiver_id': 'cg-A',
            'sync_salt': saltB64('salt-A'),
          }),
          200,
        );
      }
      return http.Response(
        json.encode({
          'token': 'tok-B',
          'family_id': 'fam-B',
          'profile_ids': ['pb1'],
          'caregiver_id': 'cg-B',
          'sync_salt': saltB64('salt-B'),
        }),
        200,
      );
    }
    if (path == '/v1/devices/register') {
      return http.Response(
        json.encode({
          'device': {'install_id': 'install-1'},
          'devices_used': 1,
        }),
        201,
      );
    }
    if (path == '/v1/sync/dashboards' && req.method == 'GET') {
      return http.Response(json.encode({'error': 'no_sync_data'}), 404);
    }
    if (path == '/v1/sync/dashboards' && req.method == 'PUT') {
      version += 1;
      return http.Response(json.encode({'version': version}), 200);
    }
    if (path == '/v1/team/invites' && req.method == 'POST') {
      inviteBody = body();
      final byEmail = inviteBody!['deliver'] == 'email';
      if (byEmail) emailedTo = inviteBody!['email'] as String?;
      return http.Response(
        json.encode({
          'invite': {
            'id': 'inv_1',
            'email': inviteBody!['email'],
            'role': inviteBody!['role'],
            'permissions': inviteBody!['permissions'],
            'status': 'pending',
            'expires_at': 9999999999999,
            'created_at': 1,
          },
          'invite_token': byEmail ? serverToken : null,
          'invite_url': byEmail
              ? 'https://onevoz.me/join#invite=$serverToken'
              : null,
          'email_status': byEmail ? 'sent' : 'link_only',
        }),
        201,
      );
    }
    if (path.startsWith('/v1/team/invites/') &&
        path.endsWith('/wrapped-key') &&
        req.method == 'POST') {
      attachedWrappedKey = body()['wrapped_key'] as String?;
      attachedWrapSalt = body()['wrap_salt'] as String?;
      return http.Response(json.encode({'ok': true}), 200);
    }
    if (path == '/v1/team/accept') {
      return http.Response(
        json.encode({
          'family_id': 'fam-A',
          'token': 'tok-A-member',
          'expires_at': 9999999999999,
          'profile_ids': ['pa1'],
          'role': 'speech_therapist',
          'permissions': {
            'dashboard': true,
            'content': true,
            'profiles': false,
            'safety': false,
            'team': false,
          },
          'wrapped_key': attachedWrappedKey ?? inviteBody?['wrapped_key'],
          'wrap_salt': attachedWrapSalt ?? inviteBody?['wrap_salt'],
        }),
        200,
      );
    }
    if (path == '/v1/team/enter') {
      final fam = body()['family_id'];
      if (fam == 'fam-B') {
        return http.Response(
          json.encode({
            'family_id': 'fam-B',
            'token': 'tok-B',
            'expires_at': 9999999999999,
            'profile_ids': ['pb1'],
            'role': 'owner',
            'is_owner': true,
            'permissions': {
              'dashboard': true,
              'content': true,
              'profiles': true,
              'safety': true,
              'team': true,
            },
          }),
          200,
        );
      }
      return http.Response(
        json.encode({
          'family_id': 'fam-A',
          'token': 'tok-A-member',
          'expires_at': 9999999999999,
          'profile_ids': ['pa1'],
          'role': 'speech_therapist',
          'is_owner': false,
          'permissions': {
            'dashboard': true,
            'content': true,
            'profiles': false,
            'safety': false,
            'team': false,
          },
        }),
        200,
      );
    }
    if (path == '/v1/team' && req.method == 'GET') {
      return http.Response(
        json.encode(_roster(memberView: auth.contains('tok-A-member'))),
        200,
      );
    }
    if (path == '/v1/team/families') {
      final inA = auth.contains('tok-A-member');
      return http.Response(
        json.encode({
          'families': [
            {
              'family_id': 'fam-B',
              'role': 'owner',
              'is_owner': true,
              'permissions': {
                'dashboard': true,
                'content': true,
                'profiles': true,
                'safety': true,
                'team': true,
              },
              'is_current': !inA,
            },
            {
              'family_id': 'fam-A',
              'role': 'speech_therapist',
              'is_owner': false,
              'permissions': {
                'dashboard': true,
                'content': true,
                'profiles': false,
                'safety': false,
                'team': false,
              },
              'is_current': inA,
            },
          ],
        }),
        200,
      );
    }
    return http.Response('not found', 404);
  }
}

Future<SessionState> _session(_TeamServer server, ProxyAuthStore auth) async {
  SharedPreferences.setMockInitialValues({});
  final session = SessionState(
    tts: _FakeTts(),
    proxy: ProxyClient(
      client: MockClient(server.handler),
      baseUrl: 'https://proxy.test',
    ),
    proxyAuth: auth,
    secureStore: _FakeSecureStore(),
  );
  await session.profiles.load();
  return session;
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('team models', () {
    test('permissions describe() speaks plainly', () {
      expect(TeamPermissions.none.describe(), 'view-only access');
      expect(
        const TeamPermissions(dashboard: true, content: true).describe(),
        'can edit the communication board, add and edit words and phrases',
      );
      expect(TeamRoles.presets[TeamRoles.doctor], TeamPermissions.none);
      expect(
        TeamRoles.presets[TeamRoles.speechTherapist],
        const TeamPermissions(dashboard: true, content: true),
      );
    });

    test('invite email draft reads grammatically for both access kinds', () {
      final editor = inviteEmailDraft(
        roleLabel: 'Speech therapist',
        permissions: const TeamPermissions(dashboard: true, content: true),
      );
      expect(
        editor.body,
        contains(
          'you will be able to edit the communication board, '
          'add and edit words and phrases.',
        ),
      );
      final viewer = inviteEmailDraft(
        roleLabel: 'Doctor',
        permissions: TeamPermissions.none,
      );
      expect(viewer.body, contains('you will have view-only access.'));
    });

    test('invite token parsing accepts links and bare tokens', () {
      expect(
        SessionState.parseInviteToken('https://onevoz.me/join#invite=abc123'),
        'abc123',
      );
      expect(SessionState.parseInviteToken('  abc123  '), 'abc123');
      expect(
        SessionState.parseInviteToken('https://onevoz.me/join#invite=a&x=1'),
        'a',
      );
    });
  });

  group('invite wrap + accept + switch', () {
    test(
      'the full circle: owner wraps the sync key, member unwraps on accept',
      () async {
        final server = _TeamServer();

        // --- owner signs in to family A and creates an invite ---
        final ownerAuth = ProxyAuthStore(store: _FakeSecureStore());
        final owner = await _session(server, ownerAuth);
        await owner.signIn(
          identifier: 'owner@example.org',
          password: 'owner-password',
        );
        expect(owner.proxyFamilyId, 'fam-A');
        expect(owner.accountHomeFamilyId, 'fam-A');
        final familyKeyB64 = await ownerAuth.readSyncKey();
        expect(familyKeyB64, isNotNull);

        final outcome = await owner.createTeamInvite(
          email: 'speech@example.org',
          role: TeamRoles.speechTherapist,
          permissions: TeamRoles.presets[TeamRoles.speechTherapist]!,
        );
        final token = SessionState.parseInviteToken(outcome.link);
        expect(token, isNotEmpty);
        // Email flow: the server generated the token and emailed the
        // invite; the create call carried no token material at all,
        // and the wrapped key arrived via the wrapped-key endpoint.
        expect(outcome.created.emailed, isTrue);
        expect(server.emailedTo, 'speech@example.org');
        expect(token, _TeamServer.serverToken);
        expect(server.inviteBody!['token_hash'], isNull);
        expect(server.inviteBody!['wrapped_key'], isNull);
        expect(server.attachedWrappedKey, isNotNull);
        expect(server.attachedWrapSalt, isNotNull);

        // --- therapist signs in to their own family B and accepts ---
        final memberAuth = ProxyAuthStore(store: _FakeSecureStore());
        final member = await _session(server, memberAuth);
        await member.signIn(
          identifier: 'speech@example.org',
          password: 'therapist-password',
        );
        expect(member.proxyFamilyId, 'fam-B');

        await member.acceptInvite(outcome.link);
        expect(member.proxyFamilyId, 'fam-A');
        expect(member.inJoinedFamily, isTrue);
        expect(member.isFamilyOwner, isFalse);
        // The unwrapped key is the owner's family sync key, byte-exact.
        expect(await memberAuth.readFamilySyncKey('fam-A'), familyKeyB64);
        expect(member.dashboardSync.hasKey, isTrue);
        expect(base64.encode(member.dashboardSync.keyBytes!), familyKeyB64);

        // Roster-driven permissions: dashboard yes, safety no.
        await member.loadTeam();
        expect(member.canEditDashboard, isTrue);
        expect(member.canEditContent, isTrue);
        expect(member.canManageSafety, isFalse);
        expect(member.canEditProfiles, isFalse);

        // --- switch back home: owner of fam-B again ---
        await member.switchToFamily('fam-B');
        expect(member.proxyFamilyId, 'fam-B');
        expect(member.inJoinedFamily, isFalse);
        expect(member.isFamilyOwner, isTrue);
        expect(member.canManageSafety, isTrue);
      },
      timeout: const Timeout(Duration(minutes: 3)),
    );
  });

  group('per-family credential slots', () {
    test('family tokens and keys persist and die with clear()', () async {
      final store = ProxyAuthStore(store: _FakeSecureStore());
      await store.writeFamilyToken('fam-A', 'tok-A');
      await store.writeFamilySyncKey('fam-A', 'a2V5');
      await store.writeHomeFamilyId('fam-B');
      expect(await store.readFamilyToken('fam-A'), 'tok-A');
      expect(await store.readFamilySyncKey('fam-A'), 'a2V5');
      expect(await store.readHomeFamilyId(), 'fam-B');
      await store.clear();
      expect(await store.readFamilyToken('fam-A'), isNull);
      expect(await store.readFamilySyncKey('fam-A'), isNull);
      expect(await store.readHomeFamilyId(), isNull);
    });
  });
}
