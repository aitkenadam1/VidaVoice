import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:onevoz/models/word.dart';
import 'package:onevoz/screens/type_board_screen.dart';
import 'package:onevoz/services/blocked_words.dart';
import 'package:onevoz/services/dashboard_service.dart';
import 'package:onevoz/services/dashboard_sync_service.dart';
import 'package:onevoz/services/device_role_service.dart';
import 'package:onevoz/services/elevenlabs_key_store.dart';
import 'package:onevoz/services/prediction_service.dart';
import 'package:onevoz/services/profile_service.dart';
import 'package:onevoz/services/proxy_client.dart';
import 'package:onevoz/services/tts_service.dart';
import 'package:onevoz/state/session_state.dart';
import 'package:onevoz/widgets/communication_mode_widgets.dart';

/// Caregiver word limits for Type mode (Adam, 2026-10-20).
///
/// Pins, end to end:
/// * the profile model round-trip (local JSON + the encrypted sync
///   serialization) — limits default OFF, custom words normalized;
/// * the pure matcher — whole-word only, case/punctuation tolerant, so
///   "class"/"damnation"/"shiitake" never trigger on a substring;
/// * prediction filtering — blocked words are never offered;
/// * the speak path — Speak, prefetch, and typed-history replay only
///   ever synthesize the masked text while limits are on.
///
/// Conventions: run from the project root with `flutter test`.

class _RecordingTts extends TtsService {
  final List<String> spoken = [];
  final List<String> prefetched = [];

  @override
  Future<bool> init({
    required String language,
    double rate = 0.5,
    double pitch = 1.0,
  }) async => true;

  @override
  Future<void> speak(String text) async {
    spoken.add(text);
  }

  @override
  Future<void> prefetch(String text) async {
    prefetched.add(text);
  }

  @override
  Future<List<TtsVoice>> getVoices() async => const [];
}

LanguagePack loadPackFromFile() {
  final raw = File('assets/lang/en.json').readAsStringSync();
  final pack = LanguagePack.fromJson(
    Map<String, dynamic>.from(json.decode(raw) as Map),
  );
  pack.validate();
  return pack;
}

Future<SessionState> makeSession(TtsService tts) async {
  SharedPreferences.setMockInitialValues({});
  final session = SessionState(tts: tts, proxy: null);
  session.pack = loadPackFromFile();
  session.status = BootStatus.ready;
  session.onboardingComplete = true;
  session.proxySignedIn = true;
  session.deviceRole = DeviceRole.communicator;
  await session.profiles.load();
  await session.prediction.load(session.profiles.active!.id);
  await session.history.load(session.profiles.active!.id);
  await session.profiles.setCommunicationMode(
    session.profiles.active!.id,
    CommunicationMode.type,
  );
  return session;
}

// ------------------------------------------------------------ sync rig --

class _FakeSecureStore implements SecureValueStore {
  final map = <String, String>{};

  @override
  Future<String?> read(String key) async => map[key];

  @override
  Future<void> write(String key, String value) async => map[key] = value;

  @override
  Future<void> delete(String key) async => map.remove(key);
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
    secureStore: _FakeSecureStore(),
  );
  await sync.loadPersisted();
  sync.setKey(key);
  return (sync: sync, profiles: profiles, dashboards: dashboards);
}

// ---------------------------------------------------------------- main --

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() {
    SharedPreferences.setMockInitialValues({});
  });

  group('profile model', () {
    test('word limits survive a toJson/fromJson round-trip', () {
      final p = UserProfile(id: 'p1', name: 'Maya', syncKey: 'sk-1');
      p.wordLimitsEnabled = true;
      p.customBlockedWords = ['homework', 'fortnite'];

      final back = UserProfile.fromJson(
        Map<String, dynamic>.from(json.decode(json.encode(p.toJson())) as Map),
      );

      expect(back.wordLimitsEnabled, isTrue);
      expect(back.customBlockedWords, ['homework', 'fortnite']);
    });

    test('pre-feature JSON opens with limits off and no custom words', () {
      final back = UserProfile.fromJson({
        'id': 'p-old',
        'name': 'Old',
        'syncKey': 'sk-old',
      });
      expect(back.wordLimitsEnabled, isFalse);
      expect(back.customBlockedWords, isEmpty);
    });

    test('fromJson normalizes the custom list (case, dupes, junk)', () {
      final back = UserProfile.fromJson({
        'id': 'p2',
        'name': 'Two',
        'wordLimitsEnabled': true,
        'customBlockedWords': [' Homework ', 'HOMEWORK', '', 42, 'fortnite'],
      });
      expect(back.wordLimitsEnabled, isTrue);
      expect(back.customBlockedWords, ['homework', 'fortnite']);
    });

    test('setWordLimits persists across a reload', () async {
      final profiles = ProfileService();
      await profiles.load();
      final id = profiles.active!.id;

      await profiles.setWordLimits(
        id,
        enabled: true,
        customWords: ['Homework', ' homework ', 'Fortnite'],
      );

      final reloaded = ProfileService();
      await reloaded.load();
      expect(reloaded.active!.wordLimitsEnabled, isTrue);
      expect(reloaded.active!.customBlockedWords, ['homework', 'fortnite']);
    });
  });

  group('blocked words (pure)', () {
    test('built-in list matches case and punctuation variants', () {
      expect(isBlockedWord('damn'), isTrue);
      expect(isBlockedWord('DAMN'), isTrue);
      expect(isBlockedWord('Damn!'), isTrue);
      expect(isBlockedWord('  shit. '), isTrue);
      expect(isBlockedWord('darn'), isFalse);
      expect(isBlockedWord('hello'), isFalse);
      expect(isBlockedWord(''), isFalse);
    });

    test('whole-word only: a blocked substring never triggers', () {
      // 'damn' is built in; these merely contain it or a custom word.
      expect(isBlockedWord('damnation'), isFalse);
      expect(isBlockedWord('class', custom: ['ass']), isFalse);
      expect(isBlockedWord('shiitake'), isFalse);
      expect(isBlockedWord('concatenate', custom: ['cat']), isFalse);
      expect(isBlockedWord('ass'), isTrue);
      expect(isBlockedWord('cat', custom: ['cat']), isTrue);
    });

    test('custom words match case-insensitively', () {
      expect(isBlockedWord('homework', custom: ['Homework']), isTrue);
      expect(isBlockedWord('HOMEWORK!', custom: ['homework']), isTrue);
      expect(isBlockedWord('homework', custom: ['fortnite']), isFalse);
    });

    test('normalizeBlockedWords trims, lowercases, dedupes', () {
      expect(
        normalizeBlockedWords([' Foo ', 'FOO', '', '  ', 'bar']),
        ['foo', 'bar'],
      );
    });

    test('maskBlockedWords masks only blocked words, keeps punctuation', () {
      expect(maskBlockedWords('What the damn!'), 'What the $blockedWordMask!');
      expect(maskBlockedWords('DAMN it all'), '$blockedWordMask it all');
      expect(
        maskBlockedWords('oh, damn... really?'),
        'oh, $blockedWordMask... really?',
      );
      expect(maskBlockedWords('god-damn'), 'god-$blockedWordMask');
    });

    test('maskBlockedWords is the identity for clean text', () {
      const clean = 'I want some juice, please!';
      expect(maskBlockedWords(clean), clean);
      expect(containsBlockedWord(clean), isFalse);
      expect(containsBlockedWord('well damn'), isTrue);
    });

    test('a possessive of a blocked word is masked too', () {
      expect(
        maskBlockedWords("that damn's mine"),
        'that $blockedWordMask mine',
      );
    });

    test('custom words are masked', () {
      expect(
        maskBlockedWords('no homework today', custom: ['homework']),
        'no $blockedWordMask today',
      );
    });
  });

  group('prediction filtering (pure)', () {
    test('blocked suggestions are removed, order kept', () {
      expect(
        filterBlockedSuggestions(['want', 'damn', 'apple', 'hell']),
        ['want', 'apple'],
      );
    });

    test('a phrase containing a blocked word is removed', () {
      expect(
        filterBlockedSuggestions(['ice cream', 'say damn', 'more juice']),
        ['ice cream', 'more juice'],
      );
    });

    test('substring lookalikes and clean words survive', () {
      expect(
        filterBlockedSuggestions(['shiitake', 'class'], custom: ['ass']),
        ['shiitake', 'class'],
      );
    });

    test('custom words are filtered too', () {
      expect(
        filterBlockedSuggestions(['homework', 'play'], custom: ['homework']),
        ['play'],
      );
    });
  });

  group('sync', () {
    test('word limits round-trip between two devices', () async {
      final server = _FakeSyncServer();
      final key = List<int>.generate(32, (i) => i);

      final a = await _makeDevice(server, key);
      final syncKey = a.profiles.active!.syncKey;
      // A distinct name keeps B off the name-fallback path (both stock
      // profiles are "My Voice"), so B imports A's profile wholesale —
      // the deterministic route, same as the goals sync tests.
      await a.profiles.renameActive('Wordy');
      await a.profiles.setWordLimits(
        a.profiles.active!.id,
        enabled: true,
        customWords: ['Homework', '  Fortnite '],
      );
      await a.sync.syncNow();

      final b = await _makeDevice(server, key);
      await b.sync.syncNow();

      final onB = b.profiles.bySyncKey(syncKey);
      expect(onB, isNotNull);
      expect(onB!.wordLimitsEnabled, isTrue);
      expect(onB.customBlockedWords, ['homework', 'fortnite']);
    });
  });

  group('session speak path', () {
    test('limits off: typeSpeak speaks the typed text untouched', () async {
      final tts = _RecordingTts();
      final session = await makeSession(tts);

      final spoken = await session.typeSpeak('damn it all');

      expect(spoken, 'damn it all');
      expect(tts.spoken, ['damn it all']);
      expect(session.history.entries.first.text, 'damn it all');
    });

    test('limits on: typeSpeak speaks and records the masked text', () async {
      final tts = _RecordingTts();
      final session = await makeSession(tts);
      final id = session.profiles.active!.id;
      await session.setWordLimits(id, enabled: true, customWords: const []);

      final spoken = await session.typeSpeak('damn it all');

      expect(spoken, '$blockedWordMask it all');
      expect(tts.spoken, ['$blockedWordMask it all']);
      // History and learning see only what was actually spoken.
      expect(session.history.entries.first.text, '$blockedWordMask it all');
    });

    test('limits on: sanitizeTypedText masks built-in and custom words', () async {
      final session = await makeSession(_RecordingTts());
      final id = session.profiles.active!.id;

      expect(session.sanitizeTypedText('damn homework'), 'damn homework');
      await session.setWordLimits(
        id,
        enabled: true,
        customWords: ['homework'],
      );
      expect(
        session.sanitizeTypedText('damn homework'),
        '$blockedWordMask $blockedWordMask',
      );
    });

    test('limits on: replaying a pre-limits typed entry is masked', () async {
      final tts = _RecordingTts();
      final session = await makeSession(tts);
      final id = session.profiles.active!.id;

      await session.typeSpeak('damn it'); // recorded with limits off
      await session.setWordLimits(id, enabled: true, customWords: const []);
      tts.spoken.clear();

      session.replayHistory(session.history.entries.first);
      expect(tts.spoken, ['$blockedWordMask it']);
    });
  });

  group('type board (widget)', () {
    const wlVocab = [
      VocabLabel(label: 'want', level: 1),
      VocabLabel(label: 'damn', level: 1),
      VocabLabel(label: 'apple', level: 2),
    ];

    Future<void> pumpBoard(WidgetTester tester, SessionState session) async {
      await tester.pumpWidget(
        ChangeNotifierProvider.value(
          value: session,
          child: const MaterialApp(
            home: TypeBoardScreen(vocabOverride: wlVocab),
          ),
        ),
      );
      await tester.pumpAndSettle();
    }

    testWidgets('predictions hide blocked words while limits are on', (
      tester,
    ) async {
      final session = await makeSession(_RecordingTts());
      await session.setWordLimits(
        session.profiles.active!.id,
        enabled: true,
        customWords: const [],
      );
      await pumpBoard(tester, session);

      expect(find.byKey(const ValueKey('type-predict-damn')), findsNothing);
      expect(find.byKey(const ValueKey('type-predict-want')), findsOneWidget);
      expect(find.byKey(const ValueKey('type-predict-apple')), findsOneWidget);
    });

    testWidgets('predictions show everything while limits are off', (
      tester,
    ) async {
      final session = await makeSession(_RecordingTts());
      await pumpBoard(tester, session);

      expect(find.byKey(const ValueKey('type-predict-damn')), findsOneWidget);
    });

    testWidgets('speak masks the field, speaks masked, gentle notice', (
      tester,
    ) async {
      final tts = _RecordingTts();
      final session = await makeSession(tts);
      await session.setWordLimits(
        session.profiles.active!.id,
        enabled: true,
        customWords: const [],
      );
      await pumpBoard(tester, session);

      await tester.enterText(
        find.byKey(const ValueKey('type-field')),
        'damn it',
      );
      await tester.pump();
      await tester.tap(find.byKey(const ValueKey('type-speak')));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 300));

      expect(tts.spoken, ['$blockedWordMask it']);
      final field = tester.widget<TextField>(
        find.byKey(const ValueKey('type-field')),
      );
      expect(field.controller!.text, '$blockedWordMask it');
      expect(
        find.text('A word was hidden by caregiver word limits'),
        findsOneWidget,
      );
      // Flush the snackbar + prefetch timers before the test ends.
      await tester.pump(const Duration(seconds: 5));
    });

    testWidgets('prefetch synthesizes only the masked text', (tester) async {
      final tts = _RecordingTts();
      final session = await makeSession(tts);
      await session.setWordLimits(
        session.profiles.active!.id,
        enabled: true,
        customWords: const [],
      );
      await pumpBoard(tester, session);

      await tester.enterText(
        find.byKey(const ValueKey('type-field')),
        'damn it',
      );
      // The prefetch debounce is 700 ms.
      await tester.pump(const Duration(milliseconds: 800));

      expect(tts.prefetched, ['$blockedWordMask it']);
      expect(tts.spoken, isEmpty);
    });
  });

  group('portal editor (widget)', () {
    testWidgets('toggle on, add and remove a custom word', (tester) async {
      final session = await makeSession(_RecordingTts());
      final pid = session.profiles.active!.id;

      await tester.pumpWidget(
        ChangeNotifierProvider.value(
          value: session,
          child: MaterialApp(
            home: Scaffold(body: WordLimitsEditor(profileId: pid)),
          ),
        ),
      );
      await tester.pumpAndSettle();

      // Off by default: no custom-word controls yet.
      expect(
        find.byKey(ValueKey('word-limits-add-field-$pid')),
        findsNothing,
      );

      await tester.tap(find.byKey(ValueKey('word-limits-toggle-$pid')));
      await tester.pumpAndSettle();
      expect(session.profiles.active!.wordLimitsEnabled, isTrue);
      expect(
        find.byKey(ValueKey('word-limits-add-field-$pid')),
        findsOneWidget,
      );

      await tester.enterText(
        find.byKey(ValueKey('word-limits-add-field-$pid')),
        'Homework',
      );
      await tester.tap(find.byKey(ValueKey('word-limits-add-$pid')));
      await tester.pumpAndSettle();
      // Stored normalized (trimmed, lowercased, deduped).
      expect(session.profiles.active!.customBlockedWords, ['homework']);
      expect(
        find.byKey(const ValueKey('word-limits-chip-homework')),
        findsOneWidget,
      );

      final chip = tester.widget<InputChip>(
        find.byKey(const ValueKey('word-limits-chip-homework')),
      );
      chip.onDeleted!();
      await tester.pumpAndSettle();
      expect(session.profiles.active!.customBlockedWords, isEmpty);

      // Flush the toggle snackbar's timer before the test ends.
      await tester.pump(const Duration(seconds: 5));
    });
  });
}
