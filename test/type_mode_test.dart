import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/testing.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:onevoz/main.dart';
import 'package:onevoz/models/word.dart';
import 'package:onevoz/screens/home_board_screen.dart';
import 'package:onevoz/screens/build_board_screen.dart';
import 'package:onevoz/screens/type_board_screen.dart';
import 'package:onevoz/services/prediction_service.dart';
import 'package:onevoz/services/profile_service.dart';
import 'package:onevoz/services/proxy_client.dart';
import 'package:onevoz/services/tts_service.dart';
import 'package:onevoz/state/session_state.dart';

/// Phase 4 (communication modes): Type mode with on-device prediction.
///
/// DOCUMENTED DESIGN CHOICES (also in TypeBoardScreen's doc comment):
/// * Tapping a saved phrase FILLS the text field — it does not speak.
///   Type mode's loop is "type or choose -> edit -> speak".
/// * Tapping a history entry REFILLS the text field — it does not speak.
///   Refill + Speak replays with speech behind exactly one intentional
///   action.
/// * Speak keeps the text in the field (repeatable/editable); the Clear
///   control empties it explicitly. Nothing is discarded silently.
///
/// Conventions: run from the project root with `flutter test`.

/// TTS double that records every speak call — the tests assert it stays
/// empty wherever speech must not happen, and holds exactly the final
/// text wherever speech must happen.
class _RecordingTts extends TtsService {
  final List<String> spoken = [];

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
  Future<List<TtsVoice>> getVoices() async => const [];
}

/// Any HTTP use throws: proves prediction/learning never touch the
/// network.
class _ThrowingHttpOverrides extends HttpOverrides {
  @override
  HttpClient createHttpClient(SecurityContext? context) =>
      throw const SocketException('network disabled in test');
}

LanguagePack loadPackFromFile() {
  final raw = File('assets/lang/en.json').readAsStringSync();
  final pack = LanguagePack.fromJson(
    Map<String, dynamic>.from(json.decode(raw) as Map),
  );
  pack.validate();
  return pack;
}

/// Deterministic stub for the 10k vocabulary (the real asset is a bundled
/// JSON the tests never load). Level-first, then alphabetical — the same
/// contract as the generated asset.
const stubVocab = [
  VocabLabel(label: 'want', level: 1),
  VocabLabel(label: 'water', level: 1),
  VocabLabel(label: 'apple', level: 2),
  VocabLabel(label: 'zebra', level: 3),
];

Future<SessionState> makeSession(
  TtsService tts, {
  bool deadNetwork = false,
  void Function()? onProxyRequest,
}) async {
  SharedPreferences.setMockInitialValues({});
  final session = SessionState(
    tts: tts,
    // deadNetwork: the proxy client throws on any request, proving the
    // Type path never needs the network.
    proxy: deadNetwork
        ? ProxyClient(
            client: MockClient((_) async {
              onProxyRequest?.call();
              throw const SocketException('nope');
            }),
            baseUrl: 'https://proxy.test',
          )
        : null,
  );
  session.pack = loadPackFromFile();
  session.status = BootStatus.ready;
  session.onboardingComplete = true;
  await session.profiles.load();
  await session.prediction.load(session.profiles.active!.id);
  await session.history.load(session.profiles.active!.id);
  return session;
}

Future<SessionState> makeTypeSession(
  TtsService tts, {
  bool deadNetwork = false,
}) async {
  final session = await makeSession(tts, deadNetwork: deadNetwork);
  await session.profiles.setCommunicationMode(
    session.profiles.active!.id,
    CommunicationMode.type,
  );
  return session;
}

void useWideSurface(WidgetTester tester) {
  tester.view.physicalSize = const Size(1600, 2400);
  tester.view.devicePixelRatio = 1.0;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);
}

Future<void> pumpTypeScreen(WidgetTester tester, SessionState session) async {
  await tester.pumpWidget(
    ChangeNotifierProvider.value(
      value: session,
      child: const MaterialApp(
        home: TypeBoardScreen(vocabOverride: stubVocab),
      ),
    ),
  );
  await tester.pumpAndSettle();
}

String fieldText(WidgetTester tester) =>
    tester.widget<TextField>(find.byKey(const ValueKey('type-field')))
        .controller!
        .text;

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() {
    SharedPreferences.setMockInitialValues({});
  });

  group('prediction engine (pure)', () {
    test('tokenize lowercases and strips edge punctuation', () {
      expect(PredictionService.tokenize('Hello, WORLD!'), ['hello', 'world']);
      expect(PredictionService.tokenize("don't stop"), ["don't", 'stop']);
      expect(PredictionService.tokenize('  '), isEmpty);
    });

    test('empty field suggests learned sentence starters first', () async {
      final service = PredictionService();
      await service.load('p1');
      await service.learn('p1', 'Hello world', 'en');
      await service.learn('p1', 'Hello again', 'en');
      await service.learn('p1', 'Good morning', 'en');

      final s = service.suggest(
        profileId: 'p1',
        text: '',
        locale: 'en',
        vocab: stubVocab,
      );
      // hello started 2 sentences, good started 1.
      expect(s.first, 'hello');
      expect(s, contains('good'));
      // Vocab pads the rest, never duplicating.
      expect(s.toSet().length, s.length);
    });

    test('empty field with no history falls back to vocab order', () async {
      final service = PredictionService();
      await service.load('p1');
      final s = service.suggest(
        profileId: 'p1',
        text: '',
        locale: 'en',
        vocab: stubVocab,
      );
      expect(s, ['want', 'water', 'apple', 'zebra']);
    });

    test('partial word: learned completions beat vocab fallback', () async {
      final service = PredictionService();
      await service.load('p1');
      await service.learn('p1', 'I want juice', 'en');
      await service.learn('p1', 'I want milk', 'en');

      final s = service.suggest(
        profileId: 'p1',
        text: 'I wan',
        locale: 'en',
        vocab: stubVocab,
      );
      // 'want' was learned (count 2); the vocab 'want' must not duplicate
      // it or outrank it.
      expect(s.first, 'want');
      expect(s.where((w) => w == 'want').length, 1);
    });

    test('partial word with no learned match uses vocab prefix', () async {
      final service = PredictionService();
      await service.load('p1');
      final s = service.suggest(
        profileId: 'p1',
        text: 'wa',
        locale: 'en',
        vocab: stubVocab,
      );
      expect(s, ['want', 'water']);
    });

    test('next word: learned followers beat vocab fallback', () async {
      final service = PredictionService();
      await service.load('p1');
      await service.learn('p1', 'I want juice', 'en');
      await service.learn('p1', 'I want milk', 'en');

      final s = service.suggest(
        profileId: 'p1',
        text: 'I want ',
        locale: 'en',
        vocab: stubVocab,
      );
      // Both followed 'want' once; milk was spoken more recently.
      expect(s.sublist(0, 2), ['milk', 'juice']);
      // Vocab pads after the learned candidates.
      expect(s[2], 'want');
    });

    test('next word with no learned match falls back to vocab', () async {
      final service = PredictionService();
      await service.load('p1');
      final s = service.suggest(
        profileId: 'p1',
        text: 'something new ',
        locale: 'en',
        vocab: stubVocab,
      );
      expect(s.first, 'want');
    });

    test('corrupt ranks blob loads empty instead of throwing', () async {
      SharedPreferences.setMockInitialValues({
        'vidavoice.predictionRanks.p1.v1': 'not-json{{{',
      });
      final service = PredictionService();
      await service.load('p1'); // must not throw
      expect(service.learnedWordCount('p1'), 0);
      final s = service.suggest(
        profileId: 'p1',
        text: 'wa',
        locale: 'en',
        vocab: stubVocab,
      );
      expect(s, ['want', 'water']);
    });

    test('learned ranks persist across service instances', () async {
      final first = PredictionService();
      await first.load('p1');
      await first.learn('p1', 'I want juice', 'en');

      final second = PredictionService();
      await second.load('p1');
      expect(second.learnedWordCount('p1'), greaterThan(0));
      final s = second.suggest(
        profileId: 'p1',
        text: 'I want ',
        locale: 'en',
        vocab: const [],
      );
      expect(s.first, 'juice');
    });
  });

  group('typeSpeak (session)', () {
    test('speaks exactly the typed text and records history', () async {
      final tts = _RecordingTts();
      final session = await makeTypeSession(tts);

      await session.typeSpeak('  hello world  ');

      expect(tts.spoken, ['hello world']);
      expect(session.history.entries.length, 1);
      final entry = session.history.entries.first;
      expect(entry.text, 'hello world');
      // Typed entries carry no board ids — and are still real history.
      expect(entry.ids, isEmpty);
      expect(entry.locale, 'en');
    });

    test('empty text never speaks and never records', () async {
      final tts = _RecordingTts();
      final session = await makeTypeSession(tts);

      await session.typeSpeak('   ');

      expect(tts.spoken, isEmpty);
      expect(session.history.entries, isEmpty);
    });

    test('spoken typed text feeds prediction ranks', () async {
      final tts = _RecordingTts();
      final session = await makeTypeSession(tts);
      final pid = session.profiles.active!.id;

      await session.typeSpeak('I want juice');

      expect(session.prediction.learnedWordCount(pid), greaterThan(0));
      final s = session.prediction.suggest(
        profileId: pid,
        text: 'I want ',
        locale: 'en',
        vocab: const [],
      );
      expect(s.first, 'juice');
    });

    test('replayHistory speaks a typed entry directly', () async {
      final tts = _RecordingTts();
      final session = await makeTypeSession(tts);

      await session.typeSpeak('hello world');
      tts.spoken.clear();

      session.replayHistory(session.history.entries.first);
      expect(tts.spoken, ['hello world']);
    });
  });

  group('cross-profile isolation', () {
    test("profile A's history never influences profile B's predictions",
        () async {
      final tts = _RecordingTts();
      final session = await makeTypeSession(tts);
      final aId = session.profiles.active!.id;

      // 'quokka' is learned AND absent from the stub vocab, so any
      // appearance in B's suggestions would prove a leak.
      await session.typeSpeak('quokka time');
      final learned = session.prediction.suggest(
        profileId: aId,
        text: 'qu',
        locale: 'en',
        vocab: stubVocab,
      );
      expect(learned, ['quokka']);

      final b = await session.profiles.addProfile('B');
      await session.switchProfile(b.id);

      final bSuggest = session.prediction.suggest(
        profileId: b.id,
        text: 'qu',
        locale: 'en',
        vocab: stubVocab,
      );
      expect(bSuggest, isNot(contains('quokka')));
      expect(bSuggest, isEmpty);
      expect(session.prediction.learnedWordCount(b.id), 0);

      // And A's ranks survived the round trip through storage.
      await session.switchProfile(aId);
      final aAgain = session.prediction.suggest(
        profileId: aId,
        text: 'qu',
        locale: 'en',
        vocab: stubVocab,
      );
      expect(aAgain, ['quokka']);
    });
  });

  group('caregiver prediction controls', () {
    test('clear history keeps learned ranks; reset learning keeps history',
        () async {
      final tts = _RecordingTts();
      final session = await makeTypeSession(tts);
      final pid = session.profiles.active!.id;

      await session.typeSpeak('I want juice');
      expect(session.history.entries.length, 1);

      // Clear history: learned ranks must survive.
      await session.clearHistoryFor(pid);
      expect(session.history.entries, isEmpty);
      var s = session.prediction.suggest(
        profileId: pid,
        text: 'I want ',
        locale: 'en',
        vocab: const [],
      );
      expect(s.first, 'juice');

      // Rebuild history, then reset learning: history must survive.
      await session.typeSpeak('I want juice');
      expect(session.history.entries.length, 1);
      await session.resetLearningFor(pid);
      expect(session.history.entries.length, 1);
      expect(session.history.entries.first.text, 'I want juice');
      s = session.prediction.suggest(
        profileId: pid,
        text: 'I want ',
        locale: 'en',
        vocab: const [],
      );
      expect(s, isNot(contains('juice')));
    });

    test('clearing a non-active profile keeps active entries in memory',
        () async {
      final tts = _RecordingTts();
      final session = await makeTypeSession(tts);
      final aId = session.profiles.active!.id;
      await session.typeSpeak('active profile message');

      final b = await session.profiles.addProfile('B');
      await session.switchProfile(b.id);
      await session.typeSpeak('other profile message');
      await session.switchProfile(aId);

      // Clear B's history while A is active: A's in-memory entries stay.
      await session.clearHistoryFor(b.id);
      expect(
        session.history.entries.map((e) => e.text),
        ['active profile message'],
      );
    });

    test('disabling prediction stops learning and clears ranks', () async {
      final tts = _RecordingTts();
      final session = await makeTypeSession(tts);
      final pid = session.profiles.active!.id;

      await session.typeSpeak('I want juice');
      expect(session.prediction.learnedWordCount(pid), greaterThan(0));

      await session.setPredictionEnabled(pid, false);
      expect(session.profiles.active!.predictionEnabled, isFalse);
      // Disabling clears the already-learned ranks.
      expect(session.prediction.learnedWordCount(pid), 0);

      // Speaking while disabled accumulates nothing...
      await session.typeSpeak('I want milk');
      expect(session.prediction.learnedWordCount(pid), 0);
      // ...but history still records (history is not learning).
      expect(session.history.entries.first.text, 'I want milk');

      // Re-enabling resumes learning.
      await session.setPredictionEnabled(pid, true);
      await session.typeSpeak('I want milk');
      expect(session.prediction.learnedWordCount(pid), greaterThan(0));
    });

    test('other modes do not learn while prediction is disabled', () async {
      final tts = _RecordingTts();
      final session = await makeTypeSession(tts);
      final pid = session.profiles.active!.id;
      await session.setPredictionEnabled(pid, false);

      session.tapWord(session.pack.wordById('core.want'));
      session.speakSentence();
      // speakSentence logs fire-and-forget; flush microtasks.
      await Future<void>.delayed(Duration.zero);

      expect(session.history.entries.length, 1);
      expect(session.prediction.learnedWordCount(pid), 0);
    });
  });

  group('network boundary', () {
    test(
        'prediction, learning, and the full offline flow make zero network '
        'calls; only the final text reaches speech', () async {
      HttpOverrides.global = _ThrowingHttpOverrides();
      addTearDown(() => HttpOverrides.global = null);

      var proxyCalls = 0;
      final tts = _RecordingTts();
      final session = await makeSession(
        tts,
        deadNetwork: true,
        onProxyRequest: () => proxyCalls++,
      );
      await session.profiles.setCommunicationMode(
        session.profiles.active!.id,
        CommunicationMode.type,
      );
      final pid = session.profiles.active!.id;

      // Learning + prediction under a network that throws on any use.
      await session.prediction.learn(pid, 'I want juice', 'en');
      final s = session.prediction.suggest(
        profileId: pid,
        text: 'I wa',
        locale: 'en',
        vocab: stubVocab,
      );
      expect(s.first, 'want');

      // Draft handling never speaks: only the explicit Speak does, with
      // exactly the final text.
      await session.typeSpeak('I want juice');
      expect(tts.spoken, ['I want juice']);
      expect(proxyCalls, 0);
    });

    testWidgets('offline full flow on the Type screen', (tester) async {
      HttpOverrides.global = _ThrowingHttpOverrides();
      addTearDown(() => HttpOverrides.global = null);
      useWideSurface(tester);

      var proxyCalls = 0;
      final tts = _RecordingTts();
      final session = await makeSession(
        tts,
        deadNetwork: true,
        onProxyRequest: () => proxyCalls++,
      );
      await session.profiles.setCommunicationMode(
        session.profiles.active!.id,
        CommunicationMode.type,
      );
      await pumpTypeScreen(tester, session);

      // Typing shows vocab-fallback predictions with no connectivity.
      await tester.enterText(
        find.byKey(const ValueKey('type-field')),
        'wa',
      );
      await tester.pump();
      expect(
        find.byKey(const ValueKey('type-predict-want')),
        findsOneWidget,
      );
      expect(tts.spoken, isEmpty);

      // Prediction tap composes; Speak speaks exactly the composed text.
      await tester.tap(find.byKey(const ValueKey('type-predict-want')));
      await tester.pump();
      expect(fieldText(tester), 'want ');
      expect(tts.spoken, isEmpty);

      await tester.tap(find.byKey(const ValueKey('type-speak')));
      await tester.pumpAndSettle();
      expect(tts.spoken, ['want']);
      expect(session.history.entries.first.text, 'want');
      expect(proxyCalls, 0);
    });
  });

  group('type screen widgets', () {
    testWidgets('nothing speaks until Speak is pressed', (tester) async {
      useWideSurface(tester);
      final tts = _RecordingTts();
      final session = await makeTypeSession(tts);
      await pumpTypeScreen(tester, session);

      await tester.enterText(
        find.byKey(const ValueKey('type-field')),
        'hello',
      );
      await tester.pump();
      // Speak is enabled once there is text...
      final speak = tester.widget<FilledButton>(
        find.byKey(const ValueKey('type-speak')),
      );
      expect(speak.onPressed, isNotNull);
      // ...but typing alone never spoke.
      expect(tts.spoken, isEmpty);

      await tester.tap(find.byKey(const ValueKey('type-speak')));
      await tester.pumpAndSettle();
      expect(tts.spoken, ['hello']);
    });

    testWidgets('Speak is disabled for empty text', (tester) async {
      useWideSurface(tester);
      final tts = _RecordingTts();
      final session = await makeTypeSession(tts);
      await pumpTypeScreen(tester, session);

      final speak = tester.widget<FilledButton>(
        find.byKey(const ValueKey('type-speak')),
      );
      expect(speak.onPressed, isNull);
      expect(tts.spoken, isEmpty);
    });

    testWidgets('prediction chip completes the word without speaking',
        (tester) async {
      useWideSurface(tester);
      final tts = _RecordingTts();
      final session = await makeTypeSession(tts);
      await pumpTypeScreen(tester, session);

      await tester.enterText(
        find.byKey(const ValueKey('type-field')),
        'I wan',
      );
      await tester.pump();
      expect(
        find.byKey(const ValueKey('type-predict-want')),
        findsOneWidget,
      );

      await tester.tap(find.byKey(const ValueKey('type-predict-want')));
      await tester.pump();
      expect(fieldText(tester), 'I want ');
      expect(tts.spoken, isEmpty);
    });

    testWidgets('saved phrase tap fills the field without speaking',
        (tester) async {
      useWideSurface(tester);
      final tts = _RecordingTts();
      final session = await makeTypeSession(tts);
      final firstPhrase = session.pack.phrases.first.label;
      await pumpTypeScreen(tester, session);

      await tester.tap(find.byKey(const ValueKey('type-phrases-button')));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const ValueKey('type-phrase-0')));
      await tester.pumpAndSettle();

      // DOCUMENTED CHOICE: the phrase fills the field; nothing spoke.
      expect(fieldText(tester), firstPhrase);
      expect(tts.spoken, isEmpty);
    });

    testWidgets('history entry tap refills the field without speaking',
        (tester) async {
      useWideSurface(tester);
      final tts = _RecordingTts();
      final session = await makeTypeSession(tts);
      await session.typeSpeak('refill me please');
      tts.spoken.clear();
      await pumpTypeScreen(tester, session);

      await tester.tap(find.byKey(const ValueKey('type-history-button')));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const ValueKey('type-history-entry-0')));
      await tester.pumpAndSettle();

      // DOCUMENTED CHOICE: the entry refills the field; nothing spoke.
      expect(fieldText(tester), 'refill me please');
      expect(tts.spoken, isEmpty);

      // Refill + Speak replays with speech behind one intentional action.
      await tester.tap(find.byKey(const ValueKey('type-speak')));
      await tester.pumpAndSettle();
      expect(tts.spoken, ['refill me please']);
    });

    testWidgets('clear control empties the field explicitly', (tester) async {
      useWideSurface(tester);
      final tts = _RecordingTts();
      final session = await makeTypeSession(tts);
      await pumpTypeScreen(tester, session);

      await tester.enterText(
        find.byKey(const ValueKey('type-field')),
        'hello',
      );
      await tester.pump();
      await tester.tap(find.byKey(const ValueKey('type-clear')));
      await tester.pump();
      expect(fieldText(tester), isEmpty);
      expect(tts.spoken, isEmpty);
    });

    testWidgets('button scale grows type and touch targets', (tester) async {
      useWideSurface(tester);
      final tts = _RecordingTts();
      final session = await makeTypeSession(tts);
      await session.setButtonScale(1.5);
      await pumpTypeScreen(tester, session);

      await tester.enterText(
        find.byKey(const ValueKey('type-field')),
        'wa',
      );
      await tester.pump();

      final field = tester.widget<TextField>(
        find.byKey(const ValueKey('type-field')),
      );
      expect(field.style!.fontSize, 20 * 1.5);
      final speak = tester.widget<FilledButton>(
        find.byKey(const ValueKey('type-speak')),
      );
      final minSize =
          (speak.style!.minimumSize!.resolve(const <WidgetState>{}));
      expect(minSize!.height, 60 * 1.5);
      expect(tts.spoken, isEmpty);
    });
  });

  group('mode routing', () {
    test('homeScreenFor routes each mode to its own surface', () async {
      final tts = _RecordingTts();
      final session = await makeSession(tts);
      final pid = session.profiles.active!.id;

      // Default (tap) keeps the classic board.
      expect(homeScreenFor(session), isA<HomeBoardScreen>());

      await session.profiles.setCommunicationMode(pid, CommunicationMode.type);
      expect(homeScreenFor(session), isA<TypeBoardScreen>());

      await session.profiles.setCommunicationMode(pid, CommunicationMode.build);
      expect(homeScreenFor(session), isA<BuildBoardScreen>());

      // And back to tap — mode switches never strand the profile.
      await session.profiles.setCommunicationMode(pid, CommunicationMode.tap);
      expect(homeScreenFor(session), isA<HomeBoardScreen>());
    });

    testWidgets('type profile opens the Type surface in the app',
        (tester) async {
      useWideSurface(tester);
      final tts = _RecordingTts();
      final session = await makeSession(tts);
      await session.profiles.setCommunicationMode(
        session.profiles.active!.id,
        CommunicationMode.type,
      );

      await tester.pumpWidget(OneVozApp(session: session));
      await tester.pumpAndSettle();

      expect(find.byType(TypeBoardScreen), findsOneWidget);
      expect(find.byKey(const ValueKey('type-field')), findsOneWidget);
      expect(find.byKey(const ValueKey('type-speak')), findsOneWidget);
    });
  });
}
