import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:onevoz/models/calling_safety.dart';
import 'package:onevoz/services/dashboard_service.dart';
import 'package:onevoz/services/dashboard_sync_service.dart';
import 'package:onevoz/services/profile_service.dart';
import 'package:onevoz/services/proxy_client.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Minimal fake sync backend: stores the last pushed blob, serves it back.
class _FakeSyncServer {
  Map<String, dynamic>? stored;

  Future<http.Response> handler(http.Request req) async {
    if (req.url.path == '/v1/sync/dashboards') {
      if (req.method == 'PUT') {
        stored = json.decode(req.body) as Map<String, dynamic>;
        return http.Response(json.encode({'version': 1}), 200);
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

  Future<void> storeEncrypted(
    List<int> key,
    Map<String, dynamic> payload,
  ) async {
    final blob = await DashboardSyncService.encrypt(
      key,
      json.encode(payload),
    );
    stored = {
      'ciphertext': blob.ciphertext,
      'nonce': blob.nonce,
      'version': 1,
    };
  }
}

Future<
  ({
    DashboardSyncService sync,
    ProfileService profiles,
    DashboardService dashboards,
  })
>
_makeDevice(_FakeSyncServer server, List<int> key) async {
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
  return (sync: sync, profiles: profiles, dashboards: dashboards);
}

/// A remote payload entry for one profile, keyed to [profile]'s syncKey.
Map<String, dynamic> _remoteEntry(
  UserProfile profile, {
  required DateTime updatedAt,
  Object? contacts,
  Object? callPhrases,
  Object? emergency,
  Object? safety,
}) => {
  'syncKey': profile.syncKey,
  'name': profile.name,
  'mode': 'tap',
  'buildMaxSymbols': 4,
  'predictionEnabled': true,
  'nudgePreference': 'allowed',
  'updatedAt': updatedAt.toIso8601String(),
  'contacts': contacts ?? const [],
  'callPhrases': callPhrases ?? const [],
  'emergency': emergency ?? const {},
  'safety': safety ?? const {},
};

Map<String, dynamic> _remotePayload(List<Map<String, dynamic>> profiles) => {
  'version': 1,
  'updatedAt': DateTime.now().toIso8601String(),
  'mirrorActiveProfile': false,
  'profiles': profiles,
  'dashboards': {},
};

void main() {
  group('calling/safety models', () {
    test('SafetyContact round-trips through JSON', () {
      const c = SafetyContact(
        id: 'c1',
        name: 'Mom',
        phone: '555-0100',
        imageData: 'aGVsbG8=',
        kind: 'mom',
      );
      final back = SafetyContact.fromJson(c.toJson());
      expect(back.id, 'c1');
      expect(back.name, 'Mom');
      expect(back.phone, '555-0100');
      expect(back.imageData, 'aGVsbG8=');
      expect(back.kind, 'mom');
    });

    test('SafetyContact fromJson is migration-safe on optional keys', () {
      final c = SafetyContact.fromJson({'id': 'c2'});
      expect(c.name, '');
      expect(c.phone, '');
      expect(c.imageData, isNull);
      expect(c.kind, 'custom');
    });

    test('SafetyContact fromJson throws on a bad id (skipped by callers)',
        () {
      expect(() => SafetyContact.fromJson({'id': ''}), throwsFormatException);
      expect(() => SafetyContact.fromJson({'name': 'x'}), throwsFormatException);
    });

    test('CallPhrase round-trips through JSON', () {
      const p = CallPhrase(id: 'p1', text: 'Hi, this is {child_name}');
      final back = CallPhrase.fromJson(p.toJson());
      expect(back.id, 'p1');
      expect(back.text, 'Hi, this is {child_name}');
    });

    test('EmergencyProfileData defaults emergencyEnabled to true', () {
      const e = EmergencyProfileData();
      expect(e.emergencyEnabled, isTrue);
      expect(e.childName, '');
      expect(e.medicalNotes, '');
      final back = EmergencyProfileData.fromJson({});
      expect(back.emergencyEnabled, isTrue);
    });

    test('SafetySettings defaults both toggles on', () {
      const s = SafetySettings();
      expect(s.aiSuggestions, isTrue);
      expect(s.preferOwnPhrases, isTrue);
      final back = SafetySettings.fromJson({});
      expect(back.aiSuggestions, isTrue);
      expect(back.preferOwnPhrases, isTrue);
    });
  });

  group('defaultCallPhrases', () {
    test('contains the five starter phrases', () {
      final phrases = defaultCallPhrases();
      expect(phrases.map((p) => p.text), [
        'Hi, this is {child_name}',
        'I need help',
        "I'm okay",
        'Please call my mom',
        "I'm lost",
      ]);
    });

    test('new profiles are seeded with the starter bank', () async {
      SharedPreferences.setMockInitialValues({});
      final profiles = ProfileService();
      await profiles.load();
      // load()'s empty-default profile
      expect(
        profiles.profiles.first.callPhrases.map((p) => p.text),
        defaultCallPhrases().map((p) => p.text),
      );
      // addProfile
      final added = await profiles.addProfile('Second');
      expect(
        added.callPhrases.map((p) => p.text),
        defaultCallPhrases().map((p) => p.text),
      );
    });
  });

  test('staticQuickAnswers contains the six answers', () {
    expect(staticQuickAnswers, [
      'Yes',
      'No',
      "I don't know",
      'Please repeat that',
      'I need help',
      'Hold on',
    ]);
  });

  group('resolvePlaceholders', () {
    const e = EmergencyProfileData(
      childName: 'Leo',
      homeAddress: '123 Main St',
      parentName: 'Ann',
      parentPhone: '555-0101',
    );

    test('replaces all four profile placeholders', () {
      expect(
        resolvePlaceholders(
          '{child_name} lives at {home_address}; {parent_name} {parent_phone}',
          e,
        ),
        'Leo lives at 123 Main St; Ann 555-0101',
      );
    });

    test('resolves {gps} with a provided location', () {
      expect(
        resolvePlaceholders('Meet me at {gps}', e, gps: '40.7128,-74.0060'),
        'Meet me at 40.7128,-74.0060',
      );
    });

    test('resolves {gps} to empty string when no location is given', () {
      expect(resolvePlaceholders('Meet me at {gps}', e), 'Meet me at ');
    });
  });

  group('composeEmergencySms', () {
    const full = EmergencyProfileData(
      childName: 'Leo',
      homeAddress: '123 Main St',
      parentName: 'Ann',
      parentPhone: '555-0101',
    );

    test('includes the GPS segment when a location is provided', () {
      expect(
        composeEmergencySms(full, gps: '40.7128,-74.0060'),
        'EMERGENCY - Leo is nonverbal, please communicate by text. '
        'Address: 123 Main St. Parent: Ann 555-0101. '
        'GPS: 40.7128,-74.0060. Map: https://maps.google.com/?q=40.7128,-74.0060',
      );
    });

    test('omits the GPS segment without a location, no trailing junk', () {
      final sms = composeEmergencySms(full);
      expect(sms.endsWith('555-0101.'), isTrue);
      expect(sms.contains('GPS'), isFalse);
      expect(
        sms,
        'EMERGENCY - Leo is nonverbal, please communicate by text. '
        'Address: 123 Main St. Parent: Ann 555-0101.',
      );
    });

    test('skips empty fields gracefully', () {
      final sms = composeEmergencySms(
        const EmergencyProfileData(childName: 'Leo'),
      );
      expect(
        sms,
        'EMERGENCY - Leo is nonverbal, please communicate by text.',
      );
      expect(sms.endsWith('.'), isTrue);
    });

    test('blank gps is treated as no location', () {
      final sms = composeEmergencySms(full, gps: '   ');
      expect(sms.contains('GPS'), isFalse);
    });

    test('parent name or phone alone still renders the parent segment', () {
      final sms = composeEmergencySms(
        const EmergencyProfileData(
          childName: 'Leo',
          parentPhone: '555-0101',
        ),
      );
      expect(sms, contains('Parent: 555-0101.'));
    });
  });

  group('UserProfile fromJson migration', () {
    test('pre-feature profile JSON yields safe defaults', () {
      final p = UserProfile.fromJson({
        'id': 'p-1',
        'name': 'Leo',
        'syncKey': 'sk-1',
        'mode': 'build',
        'buildMaxSymbols': 6,
        'predictionEnabled': false,
        'nudgePreference': 'off',
        'updatedAt': '2026-09-01T00:00:00.000',
      });
      expect(p.contacts, isEmpty);
      expect(p.callPhrases, isEmpty);
      expect(p.emergency.childName, '');
      expect(p.emergency.emergencyEnabled, isTrue);
      expect(p.safety.aiSuggestions, isTrue);
      expect(p.safety.preferOwnPhrases, isTrue);
    });

    test('malformed entries are skipped, never throw', () {
      final p = UserProfile.fromJson({
        'id': 'p-1',
        'name': 'Leo',
        'contacts': [
          {'id': 'c1', 'name': 'Mom'},
          {'name': 'no id here'},
          'not a map',
        ],
        'callPhrases': [
          {'id': 'ok', 'text': 'yes'},
          {'id': ''},
        ],
        'emergency': 'not a map',
        'safety': 42,
      });
      expect(p.contacts.map((c) => c.id), ['c1']);
      expect(p.callPhrases.map((c) => c.id), ['ok']);
      expect(p.emergency.childName, '');
      expect(p.safety.aiSuggestions, isTrue);
    });

    test('well-formed new fields round-trip through toJson/fromJson',
        () async {
      SharedPreferences.setMockInitialValues({});
      final profiles = ProfileService();
      await profiles.load();
      final p = profiles.active!;
      await profiles.setContacts(p.id, [
        const SafetyContact(id: 'c1', name: 'Mom', phone: '5', kind: 'mom'),
      ]);
      await profiles.setCallPhrases(p.id, [
        const CallPhrase(id: 'h', text: 'hi'),
      ]);
      await profiles.setEmergency(
        p.id,
        const EmergencyProfileData(childName: 'Leo', parentPhone: '5'),
      );
      await profiles.setSafety(
        p.id,
        const SafetySettings(aiSuggestions: false),
      );
      final back = UserProfile.fromJson(p.toJson());
      expect(back.contacts.single.name, 'Mom');
      expect(back.callPhrases.single.text, 'hi');
      expect(back.emergency.childName, 'Leo');
      expect(back.safety.aiSuggestions, isFalse);
      expect(back.safety.preferOwnPhrases, isTrue);
    });
  });

  group('sync payload', () {
    test('buildPayload includes calling/safety JSON per profile', () async {
      final server = _FakeSyncServer();
      final key = List<int>.filled(32, 7);
      final device = await _makeDevice(server, key);
      final p = device.profiles.active!;
      await device.profiles.setContacts(p.id, [
        const SafetyContact(
          id: 'c1',
          name: 'Mom',
          phone: '555-0100',
          kind: 'mom',
        ),
      ]);
      await device.profiles.setCallPhrases(p.id, [
        const CallPhrase(id: 'h', text: 'Hi, this is {child_name}'),
      ]);
      await device.profiles.setEmergency(
        p.id,
        const EmergencyProfileData(
          childName: 'Leo',
          homeAddress: '123 Main St',
          parentName: 'Ann',
          parentPhone: '555-0101',
        ),
      );
      await device.profiles.setSafety(
        p.id,
        const SafetySettings(aiSuggestions: false),
      );

      final payload = device.sync.buildPayload();
      final entry =
          (payload['profiles'] as List).first as Map<String, dynamic>;
      expect(entry['contacts'], [
        {
          'id': 'c1',
          'name': 'Mom',
          'phone': '555-0100',
          'kind': 'mom',
        },
      ]);
      expect(entry['callPhrases'], [
        {'id': 'h', 'text': 'Hi, this is {child_name}'},
      ]);
      expect(entry['emergency'], {
        'childName': 'Leo',
        'homeAddress': '123 Main St',
        'parentName': 'Ann',
        'parentPhone': '555-0101',
        'medicalNotes': '',
        'emergencyEnabled': true,
      });
      expect(entry['safety'], {
        'aiSuggestions': false,
        'preferOwnPhrases': true,
      });
    });

    test('newer remote calling/safety data is applied', () async {
      final server = _FakeSyncServer();
      final key = List<int>.filled(32, 7);
      final device = await _makeDevice(server, key);
      final p = device.profiles.active!;
      // Older local values.
      await device.profiles.setEmergency(
        p.id,
        const EmergencyProfileData(childName: 'Local'),
      );

      await server.storeEncrypted(key, _remotePayload([
        _remoteEntry(
          p,
          updatedAt: DateTime.now().add(const Duration(hours: 1)),
          contacts: [
            {
              'id': 'c9',
              'name': 'Grandpa',
              'phone': '555-9999',
              'kind': 'grandparent',
            },
          ],
          callPhrases: [
            {'id': 'r1', 'text': 'Remote phrase'},
          ],
          emergency: {
            'childName': 'Remote',
            'homeAddress': '9 Pine',
            'parentName': 'Dad',
            'parentPhone': '555-1111',
            'medicalNotes': '',
            'emergencyEnabled': true,
          },
          safety: {'aiSuggestions': false, 'preferOwnPhrases': false},
        ),
      ]));

      final result = await device.sync.pullNow();
      expect(result.profilesChanged, isTrue);
      final updated = device.profiles.active!;
      expect(updated.contacts.single.name, 'Grandpa');
      expect(updated.contacts.single.kind, 'grandparent');
      expect(updated.callPhrases.single.text, 'Remote phrase');
      expect(updated.emergency.childName, 'Remote');
      expect(updated.emergency.homeAddress, '9 Pine');
      expect(updated.safety.aiSuggestions, isFalse);
      expect(updated.safety.preferOwnPhrases, isFalse);
    });

    test('older remote calling/safety data does NOT clobber local', () async {
      final server = _FakeSyncServer();
      final key = List<int>.filled(32, 7);
      final device = await _makeDevice(server, key);
      final p = device.profiles.active!;
      // Newer local values.
      await device.profiles.setContacts(p.id, [
        const SafetyContact(
          id: 'local-c',
          name: 'Mom',
          phone: '555-0100',
          kind: 'mom',
        ),
      ]);
      await device.profiles.setEmergency(
        p.id,
        const EmergencyProfileData(childName: 'Local'),
      );

      await server.storeEncrypted(key, _remotePayload([
        _remoteEntry(
          p,
          updatedAt: DateTime.now().subtract(const Duration(hours: 1)),
          contacts: [
            {
              'id': 'remote-c',
              'name': 'Dad',
              'phone': '555-2222',
              'kind': 'dad',
            },
          ],
          emergency: {'childName': 'Remote'},
        ),
      ]));

      final result = await device.sync.pullNow();
      expect(result.profilesChanged, isFalse);
      final kept = device.profiles.active!;
      expect(kept.contacts.single.id, 'local-c');
      expect(kept.emergency.childName, 'Local');
    });

    test('unknown remote profile is created with the new fields', () async {
      final server = _FakeSyncServer();
      final key = List<int>.filled(32, 7);
      final device = await _makeDevice(server, key);
      final before = device.profiles.profiles.length;

      await server.storeEncrypted(key, _remotePayload([
        _remoteEntry(
          device.profiles.active!,
          updatedAt: DateTime.now(),
        )
          ..['syncKey'] = 'brand-new-sync-key'
          ..['name'] = 'New Kid'
          ..['contacts'] = [
            {'id': 'nc', 'name': 'Aunt', 'phone': '5', 'kind': 'custom'},
          ]
          ..['emergency'] = {'childName': 'New Kid'},
      ]));

      final result = await device.sync.pullNow();
      expect(result.profilesChanged, isTrue);
      expect(device.profiles.profiles.length, before + 1);
      final created = device.profiles.bySyncKey('brand-new-sync-key')!;
      expect(created.name, 'New Kid');
      expect(created.contacts.single.name, 'Aunt');
      expect(created.emergency.childName, 'New Kid');
    });
  });

  group('telUri / smsUri', () {
    test('telUri strips formatting but keeps a single leading +', () {
      expect(telUri('+1 555 010 2030').toString(), 'tel:+15550102030');
      expect(telUri('(555) 010-2030').toString(), 'tel:5550102030');
      expect(telUri('911').toString(), 'tel:911');
    });

    test('smsUri uses &body= on iOS and ?body= on Android', () {
      expect(
        smsUri('911', 'hi there', iosStyle: true).toString(),
        'sms:911&body=hi%20there',
      );
      expect(
        smsUri('911', 'hi there', iosStyle: false).toString(),
        'sms:911?body=hi%20there',
      );
    });

    test('smsUri encodes special characters in the body', () {
      final uri = smsUri('911', 'EMERGENCY - Al & Bo', iosStyle: false);
      expect(uri.toString(), contains('body=EMERGENCY%20-%20Al%20%26%20Bo'));
    });
  });
}
