import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:onevoz/models/safe_zone.dart';
import 'package:onevoz/services/dashboard_service.dart';
import 'package:onevoz/services/dashboard_sync_service.dart';
import 'package:onevoz/services/profile_service.dart';
import 'package:onevoz/services/proxy_client.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Fake sync backend: stores the encrypted dashboard blob opaquely.
/// Lets tests drive the full safe-zone sync flow without a network.
class _FakeSyncServer {
  Map<String, dynamic>? stored;
  int version = 0;

  /// The raw PUT body of the last blob upload, for privacy assertions.
  String? lastPutBody;

  Future<http.Response> handler(http.Request req) async {
    final path = req.url.path;
    if (path == '/v1/sync/dashboards') {
      if (req.method == 'PUT') {
        lastPutBody = req.body;
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
  );
  await sync.loadPersisted();
  sync.setKey(key);
  return sync;
}

SafeZone _zone(String id, String name, int tsMs) => SafeZone(
      id: id,
      name: name,
      lat: 40.1,
      lng: -111.5,
      radiusM: 300,
      enabled: true,
      notifyEnter: true,
      notifyExit: true,
      updatedTs: DateTime.fromMillisecondsSinceEpoch(tsMs),
    );

void main() {
  final key = List<int>.generate(32, (i) => i);

  group('safe zones in the encrypted payload', () {
    test('buildPayload carries safe_zones with full zone fields', () async {
      final server = _FakeSyncServer();
      final device = await _makeDevice(server, key);
      await device.upsertSafeZone(_zone('zone_aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa', 'Home', 1000));

      final payload = device.buildPayload();
      final zones = payload['safe_zones'] as List;
      expect(zones, hasLength(1));
      final z = zones.single as Map<String, dynamic>;
      expect(z['id'], 'zone_aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa');
      expect(z['name'], 'Home');
      expect(z['lat'], 40.1);
      expect(z['radius_m'], 300);
      expect(z['enabled'], isTrue);
      expect(z['notify_enter'], isTrue);
      expect(z['notify_exit'], isTrue);
      expect(z['updated_ts'], 1000);
    });

    test('upsertSafeZone rejects invalid zones without touching state',
        () async {
      final server = _FakeSyncServer();
      final device = await _makeDevice(server, key);
      final bad = _zone('zone_aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa', '', 1000);
      expect(() => device.upsertSafeZone(bad), throwsArgumentError);
      expect(device.safeZones, isEmpty);
    });

    test('removeSafeZone drops the zone', () async {
      final server = _FakeSyncServer();
      final device = await _makeDevice(server, key);
      await device.upsertSafeZone(_zone('zone_aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa', 'Home', 1000));
      await device.removeSafeZone('zone_aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa');
      expect(device.safeZones, isEmpty);
    });
  });

  group('safe zones sync round-trip', () {
    test('zones pushed by A arrive on B, encrypted on the wire', () async {
      final server = _FakeSyncServer();
      final a = await _makeDevice(server, key);
      await a.upsertSafeZone(_zone('zone_aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa', 'Home', 1000));
      await a.upsertSafeZone(_zone('zone_bbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbb', 'School', 1000));
      await a.pushNow();

      // Privacy: the server must never see plaintext zone content.
      final body = server.lastPutBody ?? '';
      expect(body, isNot(contains('Home')));
      expect(body, isNot(contains('School')));
      expect(body, isNot(contains('zone_aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa')));

      final b = await _makeDevice(server, key);
      final result = await b.pullNow();
      expect(result.safeZonesChanged, isTrue);
      expect(result.changed, isTrue);
      expect(b.safeZones.map((z) => z.name), containsAll(['Home', 'School']));
      final home = b.safeZones.firstWhere((z) => z.id == 'zone_aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa');
      expect(home.lat, 40.1);
      expect(home.radiusM, 300);
      expect(home.enabled, isTrue);
    });

    test('conflicting edits resolve last-writer-wins by updated_ts',
        () async {
      final server = _FakeSyncServer();
      final a = await _makeDevice(server, key);
      await a.upsertSafeZone(_zone('zone_aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa', 'Home', 1000));
      await a.pushNow();

      final b = await _makeDevice(server, key);
      await b.pullNow();
      expect(b.safeZones.single.name, 'Home');

      // A renames the zone and pushes while B is "offline".
      await a.upsertSafeZone(_zone('zone_aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa', 'Stale', 1500));
      await a.pushNow();

      // B edits locally with a NEWER timestamp, then pulls: the merge
      // compares per-zone updated_ts, so B's newer edit wins over the
      // older remote one.
      await b.upsertSafeZone(_zone('zone_aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa', 'Casa', 2000));
      await b.pullNow();
      expect(b.safeZones.single.name, 'Casa');

      // B pushes; a fresh device converges on the winner.
      await b.pushNow();
      final c = await _makeDevice(server, key);
      await c.pullNow();
      expect(c.safeZones.single.name, 'Casa');
    });

    test('a deleted zone stays deleted everywhere', () async {
      final server = _FakeSyncServer();
      final a = await _makeDevice(server, key);
      await a.upsertSafeZone(
          _zone('zone_aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa', 'Home', 1000));
      await a.pushNow();

      // C learns the zone now and goes stale — it never syncs again
      // until after the deletion.
      final c = await _makeDevice(server, key);
      await c.pullNow();
      expect(c.safeZones, hasLength(1));

      // B learns the zone, then A deletes it and publishes.
      final b = await _makeDevice(server, key);
      await b.pullNow();
      expect(b.safeZones, hasLength(1));
      await a.removeSafeZone('zone_aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa');
      expect(a.safeZones, isEmpty);
      await a.pushNow();

      // B pulls: the deletion propagates.
      final result = await b.pullNow();
      expect(result.safeZonesChanged, isTrue);
      expect(b.safeZones, isEmpty);

      // C (never saw the deletion) re-publishes its stale copy; the
      // tombstone still wins — the zone does not come back on A.
      await c.pushNow();
      await a.pullNow();
      expect(a.safeZones, isEmpty);
    });

    test('a zone edited after deletion comes back', () async {
      final server = _FakeSyncServer();
      final a = await _makeDevice(server, key);
      await a.upsertSafeZone(
          _zone('zone_aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa', 'Home', 1000));
      await a.pushNow();

      final b = await _makeDevice(server, key);
      await b.pullNow();
      await a.removeSafeZone('zone_aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa');
      await a.pushNow();
      await b.pullNow();
      expect(b.safeZones, isEmpty);

      // B deliberately re-creates the zone — an edit stamped after the
      // deletion — and that newer write wins over the tombstone.
      final later = DateTime.now()
          .add(const Duration(days: 1))
          .millisecondsSinceEpoch;
      await b.upsertSafeZone(
          _zone('zone_aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa', 'Home again', later));
      await b.pushNow();
      await a.pullNow();
      expect(a.safeZones.map((z) => z.name), ['Home again']);
    });

    test('malformed remote zone entries are skipped, merge survives',
        () async {
      final server = _FakeSyncServer();
      final a = await _makeDevice(server, key);
      await a.upsertSafeZone(_zone('zone_aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa', 'Home', 1000));
      await a.pushNow();

      // Tamper the stored blob: inject a garbage zone entry alongside the
      // real one, re-encrypting with the family key (simulates a buggy
      // older client, not a server attack — the server can't re-encrypt).
      final stored = server.stored!;
      final clear = await DashboardSyncService.decrypt(
        key,
        stored['ciphertext'] as String,
        stored['nonce'] as String,
      );
      final payload = json.decode(clear) as Map<String, dynamic>;
      (payload['safe_zones'] as List).add({'id': 'bogus', 'name': ''});
      final reblob = await DashboardSyncService.encrypt(
        key,
        json.encode(payload),
      );
      server.stored = {
        ...stored,
        'ciphertext': reblob.ciphertext,
        'nonce': reblob.nonce,
      };

      final b = await _makeDevice(server, key);
      final result = await b.pullNow();
      expect(result.safeZonesChanged, isTrue);
      expect(b.safeZones.map((z) => z.id), ['zone_aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa']);
    });

    test('blobs without safe_zones keep local zones (migration-safe)',
        () async {
      final server = _FakeSyncServer();
      final a = await _makeDevice(server, key);
      // Push an old-style blob: encrypt a payload with no safe_zones key.
      final blob = await DashboardSyncService.encrypt(
        key,
        json.encode(a.buildPayload()..remove('safe_zones')),
      );
      server.stored = {
        'ciphertext': blob.ciphertext,
        'nonce': blob.nonce,
        'version': 1,
      };

      final b = await _makeDevice(server, key);
      await b.upsertSafeZone(_zone('zone_aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa', 'Home', 1000));
      final result = await b.pullNow();
      expect(result.safeZonesChanged, isFalse);
      expect(b.safeZones, hasLength(1));
    });
  });

  group('safe zones local persistence', () {
    test('zones survive a service restart via local prefs', () async {
      final server = _FakeSyncServer();
      final first = await _makeDevice(server, key);
      await first.upsertSafeZone(_zone('zone_aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa', 'Home', 1000));

      // Same mock prefs, new service instance: zones reload locally.
      final profiles = ProfileService();
      final dashboards = DashboardService();
      await profiles.load();
      await dashboards.load();
      final second = DashboardSyncService(
        proxy: server.client(),
        profiles: profiles,
        dashboards: dashboards,
        prefsFactory: () async => await SharedPreferences.getInstance(),
      );
      await second.loadPersisted();
      expect(second.safeZones.map((z) => z.name), ['Home']);
    });
  });
}
