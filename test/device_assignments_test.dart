import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:onevoz/services/dashboard_service.dart';
import 'package:onevoz/services/dashboard_sync_service.dart';
import 'package:onevoz/services/profile_service.dart';
import 'package:onevoz/services/proxy_client.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Fake sync backend: stores the encrypted dashboard blob opaquely.
class _FakeSyncServer {
  Map<String, dynamic>? stored;
  int version = 0;

  Future<http.Response> handler(http.Request req) async {
    final path = req.url.path;
    if (path == '/v1/sync/dashboards') {
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

Future<DashboardSyncService> _makeDevice(
  _FakeSyncServer server,
  List<int> key,
) async {
  final profiles = ProfileService();
  final dashboards = DashboardService();
  await profiles.load();
  await dashboards.load();
  final sync = DashboardSyncService(
    proxy: server.client(),
    profiles: profiles,
    dashboards: dashboards,
    prefsFactory: () async => await SharedPreferences.getInstance(),
  );
  await sync.loadPersisted();
  sync.setKey(key);
  return sync;
}

/// Same device factory, but the test keeps the [ProfileService] handle
/// so it can reason about local ids vs syncKeys.
Future<(DashboardSyncService, ProfileService)> _makeDeviceWithProfiles(
  _FakeSyncServer server,
  List<int> key,
) async {
  final profiles = ProfileService();
  final dashboards = DashboardService();
  await profiles.load();
  await dashboards.load();
  final sync = DashboardSyncService(
    proxy: server.client(),
    profiles: profiles,
    dashboards: dashboards,
    prefsFactory: () async => await SharedPreferences.getInstance(),
  );
  await sync.loadPersisted();
  sync.setKey(key);
  return (sync, profiles);
}

void main() {
  // One shared mock-prefs store per test: _makeDevice must NOT reset it,
  // or a "second device" would wipe the first device's persisted state.
  setUp(() => SharedPreferences.setMockInitialValues({}));

  group('device_assignments sync', () {
    test('set/clear round-trips locally', () async {
      final sync = await _makeDevice(_FakeSyncServer(), List.filled(32, 7));
      expect(sync.deviceAssignments, isEmpty);
      await sync.setDeviceAssignment('dev-a', 'profile-1');
      expect(sync.deviceAssignments, {'dev-a': 'profile-1'});
      await sync.setDeviceAssignment('dev-a', null);
      expect(sync.deviceAssignments, isEmpty);
    });

    test('assignments survive a local reload', () async {
      final server = _FakeSyncServer();
      final key = List.filled(32, 7);
      final first = await _makeDevice(server, key);
      await first.setDeviceAssignment('dev-a', 'profile-1');
      final second = await _makeDevice(server, key);
      expect(second.deviceAssignments, {'dev-a': 'profile-1'});
    });

    test('assignments travel inside the encrypted blob and converge', () async {
      final server = _FakeSyncServer();
      final key = List.filled(32, 7);
      final a = await _makeDevice(server, key);
      await a.setDeviceAssignment('dev-a', 'profile-1');
      await a.pushNow();

      // A genuinely fresh device: wipe local prefs (same server, same key).
      SharedPreferences.setMockInitialValues({});
      final b = await _makeDevice(server, key);
      final result = await b.pullNow();
      expect(result.assignmentsChanged, isTrue);
      expect(b.deviceAssignments, {'dev-a': 'profile-1'});
    });

    test('merge unions assignments; newest write wins on conflict', () async {
      final server = _FakeSyncServer();
      final key = List.filled(32, 7);
      final a = await _makeDevice(server, key);
      await a.setDeviceAssignment('dev-a', 'profile-1');
      await a.setDeviceAssignment('dev-b', 'profile-9');
      await a.pushNow();

      // A genuinely separate device: wipe local prefs, then assign
      // dev-b differently and add dev-c before pulling. B's dev-b write
      // is NEWER than A's, so per-install last-write-wins keeps it —
      // the old blind "remote wins" merge would have silently undone
      // the caregiver's most recent change.
      SharedPreferences.setMockInitialValues({});
      final b = await _makeDevice(server, key);
      await b.setDeviceAssignment('dev-b', 'profile-2');
      await b.setDeviceAssignment('dev-c', 'profile-3');
      final result = await b.pullNow();
      expect(result.assignmentsChanged, isTrue);
      expect(
        b.deviceAssignments,
        {'dev-a': 'profile-1', 'dev-b': 'profile-2', 'dev-c': 'profile-3'},
      );
    });

    test('a cleared assignment stays cleared across devices', () async {
      final server = _FakeSyncServer();
      final key = List.filled(32, 7);
      final a = await _makeDevice(server, key);
      await a.setDeviceAssignment('dev-a', 'profile-1');
      await a.pushNow();

      // Device C learns the assignment now — and never syncs again
      // until after the clear, so it holds only the older copy.
      SharedPreferences.setMockInitialValues({});
      final c = await _makeDevice(server, key);
      await c.pullNow();
      expect(c.deviceAssignments, {'dev-a': 'profile-1'});

      // B learns the assignment, then clears it and publishes.
      SharedPreferences.setMockInitialValues({});
      final b = await _makeDevice(server, key);
      await b.pullNow();
      expect(b.deviceAssignments, {'dev-a': 'profile-1'});
      await b.setDeviceAssignment('dev-a', null);
      expect(b.deviceAssignments, isEmpty);
      await b.pushNow();

      // A pulls: the clear propagates; the assignment does not return.
      await a.pullNow();
      expect(a.deviceAssignments, isEmpty);

      // C (never saw the clear) re-publishes its older copy; the
      // tombstone still wins on the next merge.
      await c.pushNow();
      await a.pullNow();
      expect(a.deviceAssignments, isEmpty);
    });

    test('blobs without the key leave local assignments untouched', () async {
      final server = _FakeSyncServer();
      final key = List.filled(32, 7);
      // Seed the server with a blob that predates device_assignments.
      final seeder = await _makeDevice(server, key);
      await seeder.pushNow();

      final local = await _makeDevice(server, key);
      await local.setDeviceAssignment('dev-a', 'profile-1');
      final result = await local.pullNow();
      expect(result.assignmentsChanged, isFalse);
      expect(local.deviceAssignments, {'dev-a': 'profile-1'});
    });
  });

  group('syncKey identity', () {
    test('setting an assignment by local id stores the syncKey', () async {
      final (sync, profiles) = await _makeDeviceWithProfiles(
        _FakeSyncServer(),
        List.filled(32, 7),
      );
      final kid = profiles.active!;
      await sync.setDeviceAssignment('dev-a', kid.id);
      // Stored value is the stable cross-device identity, not the
      // device-local id (which no other device could resolve).
      expect(sync.deviceAssignments, {'dev-a': kid.syncKey});
      expect(kid.syncKey, isNot(kid.id));
    });

    test('a legacy persisted blob migrates to syncKeys on load', () async {
      final server = _FakeSyncServer();
      final key = List.filled(32, 7);
      final (first, firstProfiles) = await _makeDeviceWithProfiles(server, key);
      final kid = firstProfiles.active!;
      // Simulate a pre-syncKey build: the persisted assignments name
      // the profile by its LOCAL id.
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString(
        'vidavoice.sync.deviceAssignments',
        json.encode({'dev-a': kid.id}),
      );
      // A fresh service instance over the same stored state (the
      // upgraded app's next launch).
      final (second, _) = await _makeDeviceWithProfiles(server, key);
      expect(second.deviceAssignments, {'dev-a': kid.syncKey});
    });

    test('assignments converge across devices by syncKey', () async {
      final server = _FakeSyncServer();
      final key = List.filled(32, 7);
      final (a, aProfiles) = await _makeDeviceWithProfiles(server, key);
      final kid = await aProfiles.addProfile('Kid');
      await a.setDeviceAssignment('tablet-1', kid.id);
      expect(a.deviceAssignments, {'tablet-1': kid.syncKey});
      await a.pushNow();

      // A genuinely fresh device: wipe local prefs (same server, same key).
      SharedPreferences.setMockInitialValues({});
      final (b, bProfiles) = await _makeDeviceWithProfiles(server, key);
      final result = await b.pullNow();
      expect(result.assignmentsChanged, isTrue);
      expect(b.deviceAssignments, {'tablet-1': kid.syncKey});
      // And the value RESOLVES on this device: the profile itself
      // synced in under the same syncKey.
      expect(bProfiles.bySyncKey(kid.syncKey)?.name, 'Kid');
    });

    test('a remote legacy value upgrades on merge when known here', () async {
      final server = _FakeSyncServer();
      final key = List.filled(32, 7);
      // Device B and its profile; a pre-upgrade build on B would have
      // written this LOCAL id into the blob.
      final (b, bProfiles) = await _makeDeviceWithProfiles(server, key);
      final kid = bProfiles.active!;
      // A genuinely separate writer (fresh local state) does not know
      // B's local id, so it passes the legacy value through untouched —
      // the blob now carries it, like a pre-upgrade writer would.
      SharedPreferences.setMockInitialValues({});
      final (writer, _) = await _makeDeviceWithProfiles(server, key);
      await writer.setDeviceAssignment('dev-a', kid.id);
      expect(writer.deviceAssignments, {'dev-a': kid.id});
      await writer.pushNow();

      final result = await b.pullNow();
      expect(result.assignmentsChanged, isTrue);
      // B recognizes its own local id and upgrades it to the syncKey.
      expect(b.deviceAssignments, {'dev-a': kid.syncKey});
    });
  });
}
