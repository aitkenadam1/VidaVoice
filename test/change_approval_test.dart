import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:onevoz/models/change_request.dart';
import 'package:onevoz/models/dashboard.dart';
import 'package:onevoz/models/goal.dart';
import 'package:onevoz/models/safe_zone.dart';
import 'package:onevoz/models/team.dart';
import 'package:onevoz/screens/portal/change_requests_section.dart';
import 'package:onevoz/services/dashboard_service.dart';
import 'package:onevoz/services/dashboard_sync_service.dart';
import 'package:onevoz/services/elevenlabs_key_store.dart';
import 'package:onevoz/services/profile_service.dart';
import 'package:onevoz/services/proxy_client.dart';
import 'package:onevoz/services/tts_service.dart';
import 'package:onevoz/state/session_state.dart';

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

/// Minimal fake backend: just the encrypted sync-blob endpoints.
class _FakeSyncServer {
  Map<String, dynamic>? stored;
  int version = 0;

  Future<http.Response> handler(http.Request req) async {
    if (req.url.path == '/v1/sync/dashboards') {
      if (req.method == 'PUT') {
        final body = json.decode(req.body) as Map<String, dynamic>;
        version += 1;
        stored = {...body, 'version': version};
        return http.Response(json.encode({'version': version}), 200);
      }
      if (req.method == 'GET') {
        if (stored == null) {
          return http.Response(json.encode({'error': 'no_sync_data'}), 404);
        }
        return http.Response(json.encode(stored), 200);
      }
    }
    return http.Response('not found', 404);
  }

  ProxyClient client() {
    final proxy = ProxyClient(
      client: MockClient(handler),
      baseUrl: 'https://proxy.test',
    );
    proxy.setToken('tok-test');
    return proxy;
  }
}

ChangeRequest _request({
  String id = 'chg-1',
  String authorMemberId = 'cg-sam',
  String authorName = 'sam',
  String kind = 'dashboard_cell',
  String summary = "Add the word 'more' to Emma's board",
  Map<String, dynamic> payload = const {},
  String status = ChangeRequest.statusPending,
  String? decidedByName,
  DateTime? decidedAt,
  String? reviewerNote,
  DateTime? createdAt,
}) {
  return ChangeRequest(
    id: id,
    authorMemberId: authorMemberId,
    authorName: authorName,
    createdAt: createdAt ?? DateTime(2026, 10, 20, 9),
    kind: kind,
    summary: summary,
    payload: payload,
    status: status,
    decidedByName: decidedByName,
    decidedAt: decidedAt,
    reviewerNote: reviewerNote,
  );
}

/// A session wired to fakes (no boot): profiles loaded, nothing else.
Future<SessionState> _makeSession({ProxyClient? proxy}) async {
  SharedPreferences.setMockInitialValues({});
  final session = SessionState(
    tts: _FakeTts(),
    proxy: proxy,
    proxyAuth: ProxyAuthStore(store: _FakeSecureStore()),
    secureStore: _FakeSecureStore(),
  );
  await session.profiles.load();
  return session;
}

/// Puts [session] in a joined family as a NON-admin member with the
/// full edit permission set (everything except manage-team).
void _joinAsMember(
  SessionState session, {
  TeamPermissions permissions = const TeamPermissions(
    dashboard: true,
    content: true,
    profiles: true,
    safety: true,
  ),
  String caregiverId = 'cg-sam',
}) {
  session.proxySignedIn = true;
  session.accountHomeFamilyId = 'fam-sams-home';
  session.proxyFamilyId = 'fam-joined';
  session.teamRoster = TeamRoster(
    familyId: 'fam-joined',
    youCaregiverId: caregiverId,
    youIsOwner: false,
    youRole: TeamRoles.family,
    youPermissions: permissions,
    owner: TeamMember(
      caregiverId: 'cg-owner',
      email: 'mom@example.org',
      username: 'mom',
      role: 'owner',
      permissions: TeamPermissions.all,
      isOwner: true,
      createdAt: 1,
    ),
    members: [
      TeamMember(
        caregiverId: caregiverId,
        email: 'sam@example.org',
        username: 'sam',
        role: TeamRoles.family,
        permissions: permissions,
        isOwner: false,
        createdAt: 2,
      ),
    ],
    invites: const [],
  );
}

/// Flips [session] to the family OWNER of the joined family (same
/// family id becomes home), keeping the roster's owner identity.
void _becomeOwner(SessionState session) {
  session.proxySignedIn = true;
  session.accountHomeFamilyId = 'fam-joined';
  session.proxyFamilyId = 'fam-joined';
  session.teamRoster = const TeamRoster(
    familyId: 'fam-joined',
    youCaregiverId: 'cg-owner',
    youIsOwner: true,
    youRole: null,
    youPermissions: TeamPermissions.all,
    owner: TeamMember(
      caregiverId: 'cg-owner',
      email: 'mom@example.org',
      username: 'mom',
      role: 'owner',
      permissions: TeamPermissions.all,
      isOwner: true,
      createdAt: 1,
    ),
    members: [
      TeamMember(
        caregiverId: 'cg-sam',
        email: 'sam@example.org',
        username: 'sam',
        role: TeamRoles.family,
        permissions: TeamPermissions(
          dashboard: true,
          content: true,
          profiles: true,
          safety: true,
        ),
        isOwner: false,
        createdAt: 2,
      ),
    ],
    invites: [],
  );
}

SafeZone _zone(String name) => SafeZone(
  id: SafeZone.newId(),
  name: name,
  lat: 40.5,
  lng: -111.9,
  radiusM: 300,
  enabled: true,
  notifyEnter: true,
  notifyExit: true,
  updatedTs: DateTime.now(),
);

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('change request model', () {
    test('JSON round-trips every field including payload', () {
      final request = _request(
        payload: {
          'dashboards': {
            'sk-1': {
              'id': 'dash-1',
              'profileId': 'p-1',
              'name': 'My board',
              'cells': [
                {'id': 'c1', 'wordId': 'core.more', 'label': 'more'},
              ],
              'enabled': false,
              'updatedAt': '2026-10-20T09:00:00.000',
            },
          },
        },
        status: ChangeRequest.statusRejected,
        decidedByName: 'mom',
        decidedAt: DateTime(2026, 10, 20, 10),
        reviewerNote: 'Not yet — still learning "want".',
      );
      final back = ChangeRequest.fromJson(
        Map<String, dynamic>.from(
          json.decode(json.encode(request.toJson())) as Map,
        ),
      );
      expect(back.id, 'chg-1');
      expect(back.authorMemberId, 'cg-sam');
      expect(back.authorName, 'sam');
      expect(back.kind, 'dashboard_cell');
      expect(back.summary, contains('more'));
      expect(back.status, ChangeRequest.statusRejected);
      expect(back.decidedByName, 'mom');
      expect(back.reviewerNote, contains('Not yet'));
      final dashboards = back.payload['dashboards'] as Map;
      final dash = dashboards['sk-1'] as Map;
      expect((dash['cells'] as List).single['label'], 'more');
    });

    test('tolerant parse defaults unknown status to pending', () {
      final back = ChangeRequest.fromJson({
        'id': 'chg-x',
        'createdAt': 123,
        'status': 'bogus',
        'payload': 'not-a-map',
      });
      expect(back.status, ChangeRequest.statusPending);
      expect(back.payload, isEmpty);
      expect(back.authorName, 'Team member');
    });

    test('merge unions by id — proposals from both sides survive', () {
      final a = _request(id: 'r-a');
      final b = _request(id: 'r-b', summary: 'Another change');
      final merged = ChangeRequest.merge([a], [b]);
      expect(merged.map((r) => r.id), containsAll(['r-a', 'r-b']));
      expect(ChangeRequest.merge([a, b], const []).length, 2);
    });

    test('merge: a decided copy beats a pending copy of the same id', () {
      final pending = _request(id: 'r-1');
      final decided = _request(
        id: 'r-1',
        status: ChangeRequest.statusApproved,
        decidedByName: 'mom',
        decidedAt: DateTime(2026, 10, 20, 11),
      );
      expect(
        ChangeRequest.merge([pending], [decided]).single.status,
        ChangeRequest.statusApproved,
      );
      // And the reverse direction: a stale pending copy can never
      // un-decide a request the local side already decided.
      expect(
        ChangeRequest.merge([decided], [pending]).single.status,
        ChangeRequest.statusApproved,
      );
    });

    test('merge: between two decided copies the later decision wins', () {
      final early = _request(
        id: 'r-1',
        status: ChangeRequest.statusApproved,
        decidedByName: 'mom',
        decidedAt: DateTime(2026, 10, 20, 10),
      );
      final late = _request(
        id: 'r-1',
        status: ChangeRequest.statusRejected,
        decidedByName: 'dad',
        decidedAt: DateTime(2026, 10, 20, 12),
        reviewerNote: 'Changed our minds',
      );
      final merged = ChangeRequest.merge([early], [late]).single;
      expect(merged.status, ChangeRequest.statusRejected);
      expect(merged.decidedByName, 'dad');
      expect(
        ChangeRequest.merge([late], [early]).single.status,
        ChangeRequest.statusRejected,
      );
    });
  });

  group('change request sync storage', () {
    Future<
      ({
        DashboardSyncService sync,
        ProfileService profiles,
        DashboardService dashboards,
      })
    >
    makeDevice(_FakeSyncServer server, _FakeSecureStore store) async {
      SharedPreferences.setMockInitialValues({});
      final profiles = ProfileService();
      final dashboards = DashboardService();
      await profiles.load();
      await dashboards.load();
      final sync = DashboardSyncService(
        proxy: server.client(),
        profiles: profiles,
        dashboards: dashboards,
        prefsFactory: () async => await SharedPreferences.getInstance(),
        secureStore: store,
      );
      await sync.loadPersisted();
      sync.setKey(List<int>.generate(32, (i) => i));
      return (sync: sync, profiles: profiles, dashboards: dashboards);
    }

    test('requests persist locally across service restarts', () async {
      final server = _FakeSyncServer();
      final store = _FakeSecureStore();
      final device = await makeDevice(server, store);
      await device.sync.upsertChangeRequest(_request(id: 'chg-persist'));

      final reloaded = await makeDevice(server, store);
      expect(reloaded.sync.changeRequests.single.id, 'chg-persist');
      expect(reloaded.sync.changeRequests.single.summary, contains('more'));
    });

    test('applyChangePayload replays dashboard + profile upserts', () async {
      final server = _FakeSyncServer();
      final device = await makeDevice(server, _FakeSecureStore());
      final profile = device.profiles.active!;
      final dashboard = PersonalDashboard(
        id: 'dash-${profile.id}',
        profileId: profile.id,
        name: 'My board',
        cells: const [
          DashboardCell(id: 'c1', wordId: 'core.more', label: 'more'),
        ],
        updatedAt: DateTime(2020), // ancient: approval must re-stamp
      );
      final result = await device.sync.applyChangePayload({
        'dashboards': {profile.syncKey: dashboard.toJson()},
      });
      expect(result.dashboardsChanged, isTrue);
      final applied = device.dashboards.forProfile(profile.id);
      expect(applied!.cells.single.label, 'more');
    });

    test(
      'applyChangePayload goal tombstone deletes and a stale push '
      'cannot resurrect',
      () async {
        final server = _FakeSyncServer();
        final a = await makeDevice(server, _FakeSecureStore());
        final profile = a.profiles.active!;
        final goal = ProfileGoal(
          id: 'goal-1',
          profileSyncKey: profile.syncKey,
          title: 'Ask for a drink',
          createdAt: DateTime(2026, 10, 19),
          updatedAt: DateTime(2026, 10, 19),
        );
        await a.sync.upsertGoal(goal);
        await a.sync.syncNow();

        final b = await makeDevice(server, _FakeSecureStore());
        await b.sync.syncNow();
        expect(b.sync.goals, hasLength(1));

        // Admin approval of a delete request replays the tombstone.
        await a.sync.applyChangePayload({
          'goal_tombstones': [
            {'id': 'goal-1', 'deleted_ts': 0},
          ],
        });
        expect(a.sync.goals, isEmpty);
        await a.sync.syncNow();

        // B is stale and re-publishes the goal; A's tombstone wins.
        await b.sync.pushNow();
        await a.sync.syncNow();
        expect(a.sync.goals, isEmpty);
        await b.sync.syncNow();
        expect(b.sync.goals, isEmpty);
      },
    );
  });

  group('session gating', () {
    test(
      'gated member cell add leaves state unchanged, files one request',
      () async {
        final session = await _makeSession();
        final profile = session.profiles.active!;
        _joinAsMember(session);
        expect(session.requiresChangeApproval, isTrue);
        expect(session.isTeamAdmin, isFalse);

        await session.addDashboardCell(
          profile.id,
          const DashboardCell(
            id: 'cell-1',
            wordId: 'core.more',
            label: 'more',
          ),
        );

        // Family state byte-identical: no dashboard was written.
        expect(session.dashboards.forProfile(profile.id), isNull);
        final requests = session.pendingChangeRequests;
        expect(requests, hasLength(1));
        expect(requests.single.summary, "Add the word 'more' to My Voice's board");
        expect(requests.single.authorMemberId, 'cg-sam');
        expect(requests.single.authorName, 'sam');
        expect(session.approvalNoticeCount, 1);
        // The proposal carries the would-be dashboard.
        final dashJson =
            (requests.single.payload['dashboards'] as Map)[profile.syncKey]
                as Map;
        expect((dashJson['cells'] as List).single['label'], 'more');
      },
    );

    test(
      'gated member profile edit and safe-zone add are proposed, '
      'not applied',
      () async {
        final session = await _makeSession();
        final profile = session.profiles.active!;
        _joinAsMember(session);

        await session.setCommunicationMode(
          profile.id,
          CommunicationMode.build,
        );
        expect(profile.communicationMode, CommunicationMode.tap);
        await session.saveSafeZone(_zone('Park'), isNew: true);
        expect(session.dashboardSync.safeZones, isEmpty);

        final requests = session.pendingChangeRequests;
        expect(requests, hasLength(2));
        expect(
          requests.map((r) => r.summary),
          containsAll([
            "Change My Voice's mode to Build",
            "Add the safe zone 'Park'",
          ]),
        );
        // The mode proposal carries the would-be profile entry.
        final modeRequest = requests.firstWhere(
          (r) => r.summary.contains('mode'),
        );
        final entry =
            (modeRequest.payload['profiles'] as List).single as Map;
        expect(entry['mode'], 'build');
      },
    );

    test('gated member goal create + comment are proposed', () async {
      final session = await _makeSession();
      final profile = session.profiles.active!;
      // A goal created while owner (ungated), then the member joins.
      final goal = (await session.createGoal(
        profile: profile,
        title: 'Ask for a drink',
      ))!;
      _joinAsMember(session);

      expect(
        await session.createGoal(profile: profile, title: 'Second goal'),
        isNull,
      );
      await session.addGoalComment(goal, 'Used it at school!');

      expect(session.goalsForProfile(profile), hasLength(1));
      expect(session.goalsForProfile(profile).single.comments, isEmpty);
      final requests = session.pendingChangeRequests;
      expect(requests, hasLength(2));
      expect(
        requests.map((r) => r.kind),
        containsAll(['goal', 'goal_comment']),
      );
      expect(
        requests.map((r) => r.summary),
        contains("Comment on the goal 'Ask for a drink': "
            "'Used it at school!'"),
      );
    });

    test('gated member vocabulary level is proposed, not applied', () async {
      final session = await _makeSession();
      _joinAsMember(session);
      final before = session.unlockedLevel;
      await session.setUnlockedLevel(3);
      expect(session.unlockedLevel, before);
      expect(session.pendingChangeRequests, hasLength(1));
      expect(session.pendingChangeRequests.single.kind, 'vocab_level');
      expect(session.pendingChangeRequests.single.payload['vocabLevel'], 3);
    });

    test('admin member (manage-team) changes apply instantly', () async {
      final session = await _makeSession();
      final profile = session.profiles.active!;
      _joinAsMember(
        session,
        permissions: const TeamPermissions(
          dashboard: true,
          content: true,
          profiles: true,
          safety: true,
          team: true,
        ),
      );
      expect(session.isTeamAdmin, isTrue);
      expect(session.requiresChangeApproval, isFalse);

      await session.addDashboardCell(
        profile.id,
        const DashboardCell(id: 'cell-1', wordId: 'core.more', label: 'more'),
      );
      expect(
        session.dashboards.forProfile(profile.id)!.cells,
        hasLength(1),
      );
      expect(session.changeRequests, isEmpty);
    });

    test('owner session changes apply instantly, no requests', () async {
      final session = await _makeSession();
      final profile = session.profiles.active!;
      expect(session.isFamilyOwner, isTrue);
      await session.addDashboardCell(
        profile.id,
        const DashboardCell(id: 'cell-1', wordId: 'core.more', label: 'more'),
      );
      await session.saveSafeZone(_zone('Home'), isNew: true);
      expect(session.dashboards.forProfile(profile.id)!.cells, hasLength(1));
      expect(session.dashboardSync.safeZones, hasLength(1));
      expect(session.changeRequests, isEmpty);
    });

    test('view-only member cannot mutate and files no request', () async {
      final session = await _makeSession();
      final profile = session.profiles.active!;
      _joinAsMember(session, permissions: TeamPermissions.none);
      expect(session.canEditGoals, isFalse);
      expect(
        await session.createGoal(profile: profile, title: 'Nope'),
        isNull,
      );
      await session.saveSafeZone(_zone('Park'), isNew: true);
      expect(session.changeRequests, isEmpty);
      expect(session.dashboardSync.safeZones, isEmpty);
    });
  });

  group('decisions', () {
    test('approve applies the payload and records the decider', () async {
      final session = await _makeSession();
      final profile = session.profiles.active!;
      _joinAsMember(session);
      await session.addDashboardCell(
        profile.id,
        const DashboardCell(id: 'cell-1', wordId: 'core.more', label: 'more'),
      );
      final request = session.pendingChangeRequests.single;

      _becomeOwner(session);
      await session.approveChangeRequest(request.id);

      expect(
        session.dashboards.forProfile(profile.id)!.cells.single.label,
        'more',
      );
      final decided = session.changeRequests.single;
      expect(decided.status, ChangeRequest.statusApproved);
      expect(decided.decidedByName, 'mom');
      expect(decided.decidedAt, isNotNull);
      expect(session.pendingChangeRequests, isEmpty);
    });

    test('a non-admin cannot decide', () async {
      final session = await _makeSession();
      final profile = session.profiles.active!;
      _joinAsMember(session);
      await session.addDashboardCell(
        profile.id,
        const DashboardCell(id: 'cell-1', wordId: 'core.more', label: 'more'),
      );
      final request = session.pendingChangeRequests.single;
      await session.approveChangeRequest(request.id);
      await session.rejectChangeRequest(request.id, note: 'sneaky');
      expect(session.pendingChangeRequests, hasLength(1));
      expect(session.dashboards.forProfile(profile.id), isNull);
    });

    test(
      'reject leaves state unchanged; requester sees status and note',
      () async {
        final session = await _makeSession();
        final profile = session.profiles.active!;
        _joinAsMember(session);
        await session.setCommunicationMode(
          profile.id,
          CommunicationMode.build,
        );
        final request = session.pendingChangeRequests.single;

        _becomeOwner(session);
        await session.rejectChangeRequest(
          request.id,
          note: 'Still working on Tap for now.',
        );
        expect(profile.communicationMode, CommunicationMode.tap);

        // Back on the member's side: their list shows the rejection
        // and the admin's note.
        _joinAsMember(session);
        final mine = session.myChangeRequests;
        expect(mine, hasLength(1));
        expect(mine.single.status, ChangeRequest.statusRejected);
        expect(mine.single.reviewerNote, 'Still working on Tap for now.');
        expect(mine.single.decidedByName, 'mom');
      },
    );

    test(
      'approve of a safe-zone delete replays the tombstone',
      () async {
        final session = await _makeSession();
        final zone = _zone('Park');
        await session.dashboardSync.upsertSafeZone(zone);
        expect(session.dashboardSync.safeZones, hasLength(1));

        _joinAsMember(session);
        await session.deleteSafeZone(zone);
        expect(session.dashboardSync.safeZones, hasLength(1));
        final request = session.pendingChangeRequests.single;

        _becomeOwner(session);
        await session.approveChangeRequest(request.id);
        expect(session.dashboardSync.safeZones, isEmpty);
      },
    );
  });

  group('two-device flow', () {
    Future<List<int>> familyKey() => DashboardSyncService.deriveSyncKey(
      'correct horse battery staple',
      base64.encode(utf8.encode('family-salt-00000000000000077')),
      iterations: 2000,
    );

    test(
      'member proposes on one device; owner approves on another; '
      'the change and the decision converge back',
      () async {
        final server = _FakeSyncServer();
        final key = await familyKey();

        // Owner device: a profile named Emma, published to the family.
        final owner = await _makeSession(proxy: server.client());
        _becomeOwner(owner);
        owner.dashboardSync.setKey(key);
        await owner.profiles.renameActive('Emma');
        final emmaKey = owner.profiles.active!.syncKey;
        await owner.dashboardSync.syncNow();

        // Member device: joins (fields + roster), pulls the family.
        final member = await _makeSession(proxy: server.client());
        _joinAsMember(member);
        member.dashboardSync.setKey(key);
        await member.dashboardSync.syncNow();
        final emmaOnMember = member.profiles.bySyncKey(emmaKey)!;

        // The member's edit becomes a request, not a change.
        await member.addDashboardCell(
          emmaOnMember.id,
          const DashboardCell(
            id: 'cell-more',
            wordId: 'core.more',
            label: 'more',
          ),
        );
        expect(member.dashboards.forProfile(emmaOnMember.id), isNull);
        await member.dashboardSync.pushNow();

        // The owner pulls: the request is in the inbox; the board is
        // still unchanged.
        await owner.dashboardSync.syncNow();
        expect(owner.pendingChangeRequests, hasLength(1));
        final emmaOnOwner = owner.profiles.bySyncKey(emmaKey)!;
        expect(owner.dashboards.forProfile(emmaOnOwner.id), isNull);

        // Approve on the owner's device and publish.
        await owner.approveChangeRequest(
          owner.pendingChangeRequests.single.id,
        );
        expect(
          owner.dashboards.forProfile(emmaOnOwner.id)!.cells.single.label,
          'more',
        );
        await owner.dashboardSync.pushNow();

        // The member's device converges: board applied, decision seen.
        await member.dashboardSync.syncNow();
        expect(
          member.dashboards.forProfile(emmaOnMember.id)!.cells.single.label,
          'more',
        );
        expect(member.myChangeRequests.single.status, ChangeRequest.statusApproved);
        expect(member.myChangeRequests.single.decidedByName, 'mom');
      },
    );

    test(
      'concurrent proposals from two members both survive interleaved '
      'pushes (union merge)',
      () async {
        final server = _FakeSyncServer();
        final key = await familyKey();

        final owner = await _makeSession(proxy: server.client());
        _becomeOwner(owner);
        owner.dashboardSync.setKey(key);
        await owner.profiles.renameActive('Emma');
        final emmaKey = owner.profiles.active!.syncKey;
        await owner.dashboardSync.syncNow();

        Future<SessionState> memberDevice(String caregiverId) async {
          final s = await _makeSession(proxy: server.client());
          _joinAsMember(s, caregiverId: caregiverId);
          s.dashboardSync.setKey(key);
          await s.dashboardSync.syncNow();
          return s;
        }

        final sam = await memberDevice('cg-sam');
        final jo = await memberDevice('cg-jo');
        final emmaSam = sam.profiles.bySyncKey(emmaKey)!;
        final emmaJo = jo.profiles.bySyncKey(emmaKey)!;

        // Sam proposes and publishes.
        await sam.addDashboardCell(
          emmaSam.id,
          const DashboardCell(id: 'c-a', wordId: 'food.apple', label: 'apple'),
        );
        await sam.dashboardSync.pushNow();

        // Jo, who has NOT pulled Sam's proposal, proposes and pushes a
        // blob that does not contain it.
        await jo.addDashboardCell(
          emmaJo.id,
          const DashboardCell(
            id: 'c-z',
            wordId: 'animals.zebra',
            label: 'zebra',
          ),
        );
        await jo.dashboardSync.pushNow();

        // Convergence: after everyone syncs, both proposals exist on
        // every device — neither was dropped by the other's push.
        await sam.dashboardSync.syncNow();
        await sam.dashboardSync.pushNow();
        await owner.dashboardSync.syncNow();
        await jo.dashboardSync.syncNow();

        for (final device in [sam, jo, owner]) {
          final ids = device.changeRequests.map((r) => r.summary).toList();
          expect(
            ids,
            containsAll([
              "Add the word 'apple' to Emma's board",
              "Add the word 'zebra' to Emma's board",
            ]),
            reason: 'every device converges on both proposals',
          );
        }
      },
    );
  });

  group('change requests section widget', () {
    Future<SessionState> widgetSession() async {
      final session = await _makeSession();
      return session;
    }

    testWidgets('admin inbox renders a pending request; approve applies', (
      tester,
    ) async {
      final session = await widgetSession();
      final profile = session.profiles.active!;
      _becomeOwner(session);
      await session.dashboardSync.upsertChangeRequest(
        _request(
          payload: {
            'dashboards': {
              profile.syncKey: PersonalDashboard(
                id: 'dash-${profile.id}',
                profileId: profile.id,
                name: 'My board',
                cells: const [
                  DashboardCell(
                    id: 'cell-1',
                    wordId: 'core.more',
                    label: 'more',
                  ),
                ],
              ).toJson(),
            },
          },
        ),
      );

      await tester.pumpWidget(
        ChangeNotifierProvider<SessionState>.value(
          value: session,
          child: const MaterialApp(
            home: Scaffold(
              body: SingleChildScrollView(child: ChangeRequestsSection()),
            ),
          ),
        ),
      );
      await tester.pump();
      expect(find.text('Change requests'), findsOneWidget);
      expect(find.text("Add the word 'more' to Emma's board"), findsOneWidget);

      await tester.tap(find.text("Add the word 'more' to Emma's board"));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Approve'));
      await tester.pumpAndSettle();

      expect(
        session.dashboards.forProfile(profile.id)!.cells.single.label,
        'more',
      );
      expect(session.pendingChangeRequests, isEmpty);
      expect(find.text('No changes waiting for review.'), findsOneWidget);
    });

    testWidgets('member view shows own requests with a pending chip', (
      tester,
    ) async {
      final session = await widgetSession();
      _joinAsMember(session);
      await session.dashboardSync.upsertChangeRequest(_request());

      await tester.pumpWidget(
        ChangeNotifierProvider<SessionState>.value(
          value: session,
          child: const MaterialApp(
            home: Scaffold(
              body: SingleChildScrollView(child: ChangeRequestsSection()),
            ),
          ),
        ),
      );
      await tester.pump();
      expect(find.text('Change requests'), findsOneWidget);
      expect(find.text("Add the word 'more' to Emma's board"), findsOneWidget);
      expect(find.text('Pending'), findsOneWidget);
    });

    testWidgets('renders nothing for a solo family', (tester) async {
      final session = await widgetSession();
      await tester.pumpWidget(
        ChangeNotifierProvider<SessionState>.value(
          value: session,
          child: const MaterialApp(
            home: Scaffold(
              body: SingleChildScrollView(child: ChangeRequestsSection()),
            ),
          ),
        ),
      );
      await tester.pump();
      expect(find.text('Change requests'), findsNothing);
    });
  });
}
