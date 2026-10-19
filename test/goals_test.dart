import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:onevoz/models/goal.dart';
import 'package:onevoz/models/team.dart';
import 'package:onevoz/screens/portal/goals_section.dart';
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

Future<
  ({
    DashboardSyncService sync,
    ProfileService profiles,
    DashboardService dashboards,
  })
>
_makeDevice(
  _FakeSyncServer server,
  List<int> key, {
  _FakeSecureStore? store,
}) async {
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
    secureStore: store ?? _FakeSecureStore(),
  );
  await sync.loadPersisted();
  sync.setKey(key);
  return (sync: sync, profiles: profiles, dashboards: dashboards);
}

ProfileGoal _goal({
  required String id,
  required String profileSyncKey,
  String title = 'Ask for a drink',
  DateTime? targetDate,
  bool achieved = false,
  DateTime? updatedAt,
  List<GoalComment>? comments,
  List<GoalLink>? links,
}) {
  final now = DateTime(2026, 10, 19, 12);
  return ProfileGoal(
    id: id,
    profileSyncKey: profileSyncKey,
    title: title,
    targetDate: targetDate,
    achieved: achieved,
    achievedAt: achieved ? now : null,
    createdAt: now,
    updatedAt: updatedAt ?? now,
    comments: comments,
    links: links,
  );
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('goal model', () {
    test('JSON round-trips every field', () {
      final goal = _goal(
        id: 'goal-1',
        profileSyncKey: 'sk-1',
        targetDate: DateTime(2026, 12, 1),
        comments: [
          GoalComment(
            id: 'c1',
            author: 'Speech therapist',
            text: 'Used it twice at school!',
            createdAt: DateTime(2026, 10, 19, 9, 30),
          ),
        ],
        links: const [
          GoalLink(kind: 'word', cellId: 'cell-1', label: 'juice'),
          GoalLink(kind: 'phrase', cellId: 'cell-2', label: 'I want juice'),
        ],
      );
      final back = ProfileGoal.fromJson(
        Map<String, dynamic>.from(
          json.decode(json.encode(goal.toJson())) as Map,
        ),
      );
      expect(back.id, 'goal-1');
      expect(back.profileSyncKey, 'sk-1');
      expect(back.title, 'Ask for a drink');
      expect(back.targetDate, DateTime(2026, 12, 1));
      expect(back.comments.single.author, 'Speech therapist');
      expect(back.comments.single.text, 'Used it twice at school!');
      expect(back.links.length, 2);
      expect(back.links.last.kind, 'phrase');
    });

    test('tolerant parse skips bad comments and links, keeps the goal', () {
      final back = ProfileGoal.fromJson({
        'id': 'goal-2',
        'profileSyncKey': 'sk-1',
        'title': 'Wave hello',
        'comments': [
          {'noId': true},
          {'id': 'ok', 'author': 'Mom', 'text': 'Waved today', 'createdAt': '2026-10-19T08:00:00.000'},
        ],
        'links': [
          {'kind': 'word'},
          {'kind': 'word', 'cellId': 'cell-9', 'label': 'hello'},
        ],
      });
      expect(back.comments.single.id, 'ok');
      expect(back.links.single.cellId, 'cell-9');
    });

    test('daysLeft and overdue follow the calendar, achieved excluded', () {
      final now = DateTime(2026, 10, 19, 15, 45);
      expect(
        _goal(id: 'g', profileSyncKey: 's', targetDate: DateTime(2026, 10, 22))
            .daysLeft(now),
        3,
      );
      final overdue = _goal(
        id: 'g',
        profileSyncKey: 's',
        targetDate: DateTime(2026, 10, 17),
      );
      expect(overdue.daysLeft(now), -2);
      expect(overdue.isOverdue(now), isTrue);
      final done = _goal(
        id: 'g',
        profileSyncKey: 's',
        targetDate: DateTime(2026, 10, 17),
        achieved: true,
      );
      expect(done.daysLeft(now), isNull);
      expect(done.isOverdue(now), isFalse);
    });

    test('merge is last-writer-wins per goal id', () {
      final t0 = DateTime(2026, 10, 19, 10);
      final t1 = DateTime(2026, 10, 19, 11);
      final local = _goal(id: 'g1', profileSyncKey: 's', title: 'Old', updatedAt: t0);
      final remote = _goal(id: 'g1', profileSyncKey: 's', title: 'New', updatedAt: t1);
      expect(ProfileGoal.merge([local], [remote]).single.title, 'New');
      expect(ProfileGoal.merge([remote], [local]).single.title, 'New');
    });
  });

  group('goal sync', () {
    test('goals round-trip between two devices, comments included', () async {
      final server = _FakeSyncServer();
      final key = await DashboardSyncService.deriveSyncKey(
        'correct horse battery staple',
        base64.encode(utf8.encode('family-salt-00000000000000001')),
        iterations: 2000,
      );

      final a = await _makeDevice(server, key);
      await a.profiles.renameActive('Maya');
      final syncKey = a.profiles.active!.syncKey;
      await a.sync.syncNow();

      final goal = _goal(id: 'goal-rt', profileSyncKey: syncKey);
      await a.sync.upsertGoal(goal);
      await a.sync.syncNow();

      final b = await _makeDevice(server, key);
      final result = await b.sync.syncNow();
      expect(result.goalsChanged, isTrue);
      final onB = b.sync.goalsForSyncKey(syncKey);
      expect(onB.single.title, 'Ask for a drink');

      // B comments; A pulls and sees it.
      final withComment = onB.single.copyWith(
        comments: [
          GoalComment(
            id: 'c-1',
            author: 'Speech therapist',
            text: 'Did it at school today!',
            createdAt: DateTime.now(),
          ),
        ],
        updatedAt: DateTime.now().add(const Duration(seconds: 1)),
      );
      await b.sync.upsertGoal(withComment);
      await b.sync.syncNow();
      await a.sync.syncNow();
      final onA = a.sync.goalsForSyncKey(syncKey);
      expect(onA.single.comments.single.text, 'Did it at school today!');
    });

    test('deletion propagates and a stale push cannot resurrect', () async {
      final server = _FakeSyncServer();
      final key = await DashboardSyncService.deriveSyncKey(
        'correct horse battery staple',
        base64.encode(utf8.encode('family-salt-00000000000000002')),
        iterations: 2000,
      );

      final a = await _makeDevice(server, key);
      await a.profiles.renameActive('Maya');
      final syncKey = a.profiles.active!.syncKey;
      await a.sync.upsertGoal(_goal(id: 'goal-del', profileSyncKey: syncKey));
      await a.sync.syncNow();

      final b = await _makeDevice(server, key);
      await b.sync.syncNow();
      expect(b.sync.goals, hasLength(1));

      await a.sync.removeGoal('goal-del');
      await a.sync.syncNow();

      // B is stale: it pushes its pre-delete state over the server blob.
      await b.sync.pushNow();
      // A pulls that stale blob — its tombstone must keep the goal dead.
      await a.sync.syncNow();
      expect(a.sync.goals, isEmpty);

      // And once B converges, the goal is gone for B too.
      await b.sync.syncNow();
      expect(b.sync.goals, isEmpty);
    });

    test('goals persist locally across service restarts', () async {
      final server = _FakeSyncServer();
      final key = List<int>.generate(32, (i) => i);
      final store = _FakeSecureStore();
      final device = await _makeDevice(server, key, store: store);
      await device.sync.upsertGoal(
        _goal(id: 'goal-local', profileSyncKey: 'sk-x'),
      );

      final reloaded = await _makeDevice(server, key, store: store);
      expect(reloaded.sync.goals.single.id, 'goal-local');
    });
  });

  group('session goals', () {
    Future<SessionState> makeSession() async {
      SharedPreferences.setMockInitialValues({});
      final session = SessionState(
        tts: _FakeTts(),
        proxyAuth: ProxyAuthStore(store: _FakeSecureStore()),
        secureStore: _FakeSecureStore(),
      );
      await session.profiles.load();
      await session.profiles.addProfile('Maya');
      return session;
    }

    test('create, check off, reopen, comment, delete', () async {
      final session = await makeSession();
      final profile = session.profiles.active!;
      final goal = await session.createGoal(
        profile: profile,
        title: 'Ask for a drink',
        targetDate: DateTime(2026, 12, 1),
      );
      expect(goal, isNotNull);
      expect(session.goalsForProfile(profile).single.title, 'Ask for a drink');
      expect(
        await session.createGoal(profile: profile, title: '   '),
        isNull,
      );

      await session.setGoalAchieved(goal!, true);
      var current = session.goalsForProfile(profile).single;
      expect(current.achieved, isTrue);
      expect(current.achievedAt, isNotNull);

      await session.setGoalAchieved(current, false);
      current = session.goalsForProfile(profile).single;
      expect(current.achieved, isFalse);
      expect(current.achievedAt, isNull);

      await session.addGoalComment(current, 'Used it at school!');
      current = session.goalsForProfile(profile).single;
      expect(current.comments.single.text, 'Used it at school!');
      expect(current.comments.single.author, 'Caregiver');

      await session.deleteGoal(current);
      expect(session.goalsForProfile(profile), isEmpty);
    });

    test('adding words and phrases tailors the board and links them', () async {
      final session = await makeSession();
      final profile = session.profiles.active!;
      final goal = (await session.createGoal(
        profile: profile,
        title: 'Order a snack',
      ))!;

      final wordCell = await session.addGoalWord(
        goal,
        wordId: 'food.juice',
        label: 'juice',
      );
      expect(wordCell, isNotNull);
      var dashboard = session.dashboards.forProfile(profile.id);
      expect(dashboard!.cells.single.wordId, 'food.juice');

      var current = session.goalsForProfile(profile).single;
      expect(current.links.single.kind, 'word');
      expect(current.links.single.cellId, wordCell!.id);

      final phraseCell = await session.addGoalPhrase(
        current,
        text: 'I want a snack, please',
      );
      expect(phraseCell, isNotNull);
      dashboard = session.dashboards.forProfile(profile.id);
      expect(dashboard!.cells.length, 2);
      expect(dashboard.cells.last.customText, 'I want a snack, please');

      current = session.goalsForProfile(profile).single;
      expect(current.links.length, 2);
      expect(current.links.last.kind, 'phrase');

      // Unlinking drops only the bookkeeping; the board keeps the item.
      await session.unlinkGoalItem(current, phraseCell!.id);
      current = session.goalsForProfile(profile).single;
      expect(current.links.length, 1);
      expect(session.dashboards.forProfile(profile.id)!.cells.length, 2);
    });

    test('view-only team member can read but not write goals', () async {
      final session = await makeSession();
      final profile = session.profiles.active!;
      final goal = (await session.createGoal(
        profile: profile,
        title: 'Say hello',
      ))!;

      // Become a view-only (doctor) member of someone else's family.
      session.proxySignedIn = true;
      session.accountHomeFamilyId = 'fam-home';
      session.proxyFamilyId = 'fam-joined';
      session.teamRoster = const TeamRoster(
        familyId: 'fam-joined',
        youCaregiverId: 'cg-doc',
        youIsOwner: false,
        youRole: TeamRoles.doctor,
        youPermissions: TeamPermissions.none,
        owner: null,
        members: [],
        invites: [],
      );
      expect(session.inJoinedFamily, isTrue);
      expect(session.canEditGoals, isFalse);

      // Reads still work; every write is refused.
      expect(session.goalsForProfile(profile).single.title, 'Say hello');
      expect(await session.createGoal(profile: profile, title: 'Nope'), isNull);
      await session.addGoalComment(goal, 'Should not land');
      await session.setGoalAchieved(goal, true);
      final current = session.goalsForProfile(profile).single;
      expect(current.comments, isEmpty);
      expect(current.achieved, isFalse);
    });

    test('member comments are attributed by roster username', () async {
      final session = await makeSession();
      final profile = session.profiles.active!;
      final goal = (await session.createGoal(
        profile: profile,
        title: 'Use two symbols',
      ))!;

      session.proxySignedIn = true;
      session.accountHomeFamilyId = 'fam-home';
      session.proxyFamilyId = 'fam-joined';
      session.teamRoster = TeamRoster(
        familyId: 'fam-joined',
        youCaregiverId: 'cg-therapist',
        youIsOwner: false,
        youRole: TeamRoles.speechTherapist,
        youPermissions: TeamRoles.presets[TeamRoles.speechTherapist]!,
        owner: null,
        members: [
          TeamMember(
            caregiverId: 'cg-therapist',
            email: 'speech@example.org',
            username: 'speech.sam',
            role: TeamRoles.speechTherapist,
            permissions: TeamRoles.presets[TeamRoles.speechTherapist]!,
            isOwner: false,
            createdAt: DateTime(2026, 10, 1).millisecondsSinceEpoch,
          ),
        ],
        invites: const [],
      );
      expect(session.canEditGoals, isTrue);
      await session.addGoalComment(goal, 'Great session today.');
      final current = session.goalsForProfile(profile).single;
      expect(current.comments.single.author, 'speech.sam');
    });
  });

  group('goals section widget', () {
    testWidgets('renders goals and the checkbox checks off', (tester) async {
      SharedPreferences.setMockInitialValues({});
      final session = SessionState(
        tts: _FakeTts(),
        proxyAuth: ProxyAuthStore(store: _FakeSecureStore()),
        secureStore: _FakeSecureStore(),
      );
      await session.profiles.load();
      await session.profiles.addProfile('Maya');
      final profile = session.profiles.active!;
      final goal = (await session.createGoal(
        profile: profile,
        title: 'Ask for a drink',
        targetDate: DateTime(2026, 12, 1),
      ))!;

      await tester.pumpWidget(
        ChangeNotifierProvider<SessionState>.value(
          value: session,
          child: const MaterialApp(
            home: Scaffold(body: SingleChildScrollView(child: GoalsSection())),
          ),
        ),
      );
      await tester.pump();
      expect(find.text('Goals'), findsOneWidget);
      expect(find.text('Ask for a drink'), findsOneWidget);
      expect(find.textContaining('By Dec 1, 2026'), findsOneWidget);
      expect(find.text('Add goal'), findsOneWidget);

      await tester.tap(find.byType(Checkbox).first);
      await tester.pump();
      expect(session.goalsForProfile(profile).single.achieved, isTrue);
      expect(find.textContaining('Achieved'), findsOneWidget);
      expect(goal.achieved, isFalse); // original snapshot untouched
    });
  });
}
