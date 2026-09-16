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

    test('merge unions assignments; remote wins on conflict', () async {
      final server = _FakeSyncServer();
      final key = List.filled(32, 7);
      final a = await _makeDevice(server, key);
      await a.setDeviceAssignment('dev-a', 'profile-1');
      await a.setDeviceAssignment('dev-b', 'profile-9');
      await a.pushNow();

      // A genuinely separate device: wipe local prefs, then assign
      // dev-b differently and add dev-c before pulling.
      SharedPreferences.setMockInitialValues({});
      final b = await _makeDevice(server, key);
      await b.setDeviceAssignment('dev-b', 'profile-2');
      await b.setDeviceAssignment('dev-c', 'profile-3');
      final result = await b.pullNow();
      expect(result.assignmentsChanged, isTrue);
      expect(
        b.deviceAssignments,
        {'dev-a': 'profile-1', 'dev-b': 'profile-9', 'dev-c': 'profile-3'},
      );
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
}
