import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/testing.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:onevoz/main.dart';
import 'package:onevoz/models/dashboard.dart';
import 'package:onevoz/models/word.dart';
import 'package:onevoz/screens/build_board_screen.dart';
import 'package:onevoz/screens/category_screen.dart';
import 'package:onevoz/screens/home_board_screen.dart';
import 'package:onevoz/screens/type_board_screen.dart';
import 'package:onevoz/services/profile_service.dart';
import 'package:onevoz/services/proxy_client.dart';
import 'package:onevoz/services/tts_service.dart';
import 'package:onevoz/state/session_state.dart';
import 'package:onevoz/widgets/build_strip_bar.dart';
import 'package:onevoz/widgets/communication_mode_widgets.dart';
import 'package:onevoz/widgets/word_button.dart';

/// Phase 3 (communication modes): the Build-mode phrase strip.
///
/// DOCUMENTED DESIGN CHOICE — phrase-type items (BoardItem.isPhrase): a
/// phrase joins the strip as ONE unit and speaks only when the
/// communicator presses Speak. Speaking it immediately would break Build
/// mode's defining contract (speech only after an intentional Speak), so
/// it behaves as a single composed symbol rather than the Tap-mode atomic
/// utterance. Locked in by the 'phrase-type items join the strip' tests.
///
/// Conventions: run from the project root with `flutter test`.

/// TTS double that records every speak call — the tests assert it stays
/// empty wherever speech must not happen.
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

LanguagePack loadPackFromFile() {
  final raw = File('assets/lang/en.json').readAsStringSync();
  final pack = LanguagePack.fromJson(
    Map<String, dynamic>.from(json.decode(raw) as Map),
  );
  pack.validate();
  return pack;
}

Future<SessionState> makeSession(
  TtsService tts, {
  bool deadNetwork = false,
}) async {
  SharedPreferences.setMockInitialValues({});
  final session = SessionState(
    tts: tts,
    // deadNetwork: the proxy client throws on any request, proving the
    // Build path never needs the network.
    proxy: deadNetwork
        ? ProxyClient(
            client: MockClient(
              (_) async => throw const SocketException('nope'),
            ),
            baseUrl: 'https://proxy.test',
          )
        : null,
  );
  session.pack = loadPackFromFile();
  session.status = BootStatus.ready;
  session.onboardingComplete = true;
  await session.profiles.load();
  return session;
}

Future<SessionState> makeBuildSession(
  TtsService tts, {
  bool deadNetwork = false,
}) async {
  final session = await makeSession(tts, deadNetwork: deadNetwork);
  await session.profiles.setCommunicationMode(
    session.profiles.active!.id,
    CommunicationMode.build,
  );
  return session;
}

void useWideSurface(WidgetTester tester) {
  tester.view.physicalSize = const Size(1600, 2400);
  tester.view.devicePixelRatio = 1.0;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('build strip (session)', () {
    test('tapBoardItem adds in order and never speaks in build mode', () async {
      final tts = _RecordingTts();
      final session = await makeBuildSession(tts);
      await session.usage.load();

      session.tapBoardItem(session.pack.wordById('core.i'));
      session.tapBoardItem(session.pack.wordById('core.want'));
      // A folder tap inside the pack (not a folder TILE) also collects.
      session.tapBoardItem(session.pack.wordById('food.apple'));

      expect(
        session.buildStrip.map((e) => e.text).toList(),
        ['I', 'want', 'apple'],
      );
      expect(tts.spoken, isEmpty);
      // Build taps must not leak into Tap's sentence bar.
      expect(session.sentenceIds, isEmpty);
      // Taps still count toward "most used" activity.
      expect(session.usage.countFor('core.i'), 1);
    });

    test('folder tiles never reach the strip', () async {
      final tts = _RecordingTts();
      final session = await makeBuildSession(tts);

      session.tapBoardItem(session.pack.wordById('folder.food'));

      expect(session.buildStrip, isEmpty);
      expect(tts.spoken, isEmpty);
    });

    test('tap-to-remove and clear keep order and stay silent', () async {
      final tts = _RecordingTts();
      final session = await makeBuildSession(tts);

      session.tapBoardItem(session.pack.wordById('core.i'));
      session.tapBoardItem(session.pack.wordById('core.want'));
      session.tapBoardItem(session.pack.wordById('core.go'));

      session.buildRemoveAt(1);
      expect(
        session.buildStrip.map((e) => e.text).toList(),
        ['I', 'go'],
      );
      // Out-of-range removal is a safe no-op.
      session.buildRemoveAt(9);
      expect(session.buildStrip.length, 2);

      session.buildClear();
      expect(session.buildStrip, isEmpty);
      expect(tts.spoken, isEmpty);
      // Clearing an empty strip is a no-op, not an error.
      session.buildClear();
      expect(tts.spoken, isEmpty);
    });

    test('max length enforcement rejects with feedback, never speaks',
        () async {
      final tts = _RecordingTts();
      final session = await makeBuildSession(tts);
      final id = session.profiles.active!.id;
      await session.profiles.setBuildMaxSymbols(id, 3);
      expect(session.buildMax, 3);

      session.buildAdd(session.pack.wordById('core.i'));
      session.buildAdd(session.pack.wordById('core.want'));
      session.buildAdd(session.pack.wordById('core.go'));
      expect(session.buildStripFull, isTrue);

      // The 4th tap is rejected: strip unchanged, TTS untouched, and the
      // rejection is communicated — not silent, not spoken.
      final added = session.buildAdd(session.pack.wordById('core.more'));
      expect(added, isFalse);
      expect(
        session.buildStrip.map((e) => e.text).toList(),
        ['I', 'want', 'go'],
      );
      expect(tts.spoken, isEmpty);
      expect(session.buildNotice, contains('full'));

      // After removing one unit there is room again and the notice clears.
      session.buildRemoveAt(0);
      final retry = session.buildAdd(session.pack.wordById('core.more'));
      expect(retry, isTrue);
      expect(
        session.buildStrip.map((e) => e.text).toList(),
        ['want', 'go', 'more'],
      );
      expect(session.buildNotice, isNull);
    });

    test('speak speaks exactly the composed text and records history',
        () async {
      final tts = _RecordingTts();
      final session = await makeBuildSession(tts);
      final id = session.profiles.active!.id;
      await session.history.load(id);

      session.buildAdd(session.pack.wordById('core.i'));
      session.buildAdd(session.pack.wordById('core.want'));
      // Nothing speaks before the button.
      expect(tts.spoken, isEmpty);
      expect(session.history.entries, isEmpty);

      session.buildSpeak();

      expect(tts.spoken, ['I want']);
      // Exactly one utterance, exactly the composed text.
      expect(tts.spoken.length, 1);
      expect(session.history.entries.length, 1);
      expect(session.history.entries.single.text, 'I want');
      expect(session.history.entries.single.ids, ['core.i', 'core.want']);
      // The strip is kept so the message can be replayed.
      expect(session.buildStrip.length, 2);
    });

    test('empty strip speak is a silent no-op', () async {
      final tts = _RecordingTts();
      final session = await makeBuildSession(tts);
      session.buildSpeak();
      expect(tts.spoken, isEmpty);
    });

    test('phrase-type items join the strip as one unit (documented choice)',
        () async {
      final tts = _RecordingTts();
      final session = await makeBuildSession(tts);

      session.tapBoardItem(session.pack.wordById('phrase.ineedhelp'));

      // One strip unit, NOT spoken immediately — the whole point of Build.
      expect(session.buildStrip.length, 1);
      expect(session.buildStrip.single.text, 'I need help');
      expect(session.buildStrip.single.wordId, 'phrase.ineedhelp');
      expect(tts.spoken, isEmpty);

      session.buildSpeak();
      expect(tts.spoken, ['I need help']);
    });

    test('dashboard custom text joins the strip in build mode', () async {
      final tts = _RecordingTts();
      final session = await makeBuildSession(tts);
      const cell = DashboardCell(
        id: 'c1',
        label: 'Hi',
        speakText: 'hi sweetie',
        emoji: '👋',
      );

      session.tapDashboardCell(cell);

      expect(session.buildStrip.length, 1);
      expect(session.buildStrip.single.text, 'hi sweetie');
      expect(session.buildStrip.single.wordId, isNull);
      expect(tts.spoken, isEmpty);

      session.buildSpeak();
      expect(tts.spoken, ['hi sweetie']);
      // Ad-hoc text has no vocabulary id, but the composed message was
      // intentionally sent to speech, so it IS spoken history (Phase 4:
      // HistoryService.record stores entries with empty ids). Caregivers
      // see the full message in activity; only the unit's ids are absent.
      expect(session.history.entries, hasLength(1));
      expect(session.history.entries.single.text, 'hi sweetie');
      expect(session.history.entries.single.ids, isEmpty);
    });

    test('dashboard custom text still speaks immediately in tap mode',
        () async {
      final tts = _RecordingTts();
      final session = await makeSession(tts);
      const cell = DashboardCell(
        id: 'c1',
        label: 'Hi',
        speakText: 'hi sweetie',
        emoji: '👋',
      );

      session.tapDashboardCell(cell);

      expect(tts.spoken, ['hi sweetie']);
      expect(session.buildStrip, isEmpty);
    });

    test('mode switch preserves dashboard, voice, and history', () async {
      final tts = _RecordingTts();
      final session = await makeSession(tts);
      final id = session.profiles.active!.id;

      // Real content in Tap mode.
      await session.dashboards.load();
      final dash = session.dashboards.ensureFor(id);
      dash.cells.add(
        const DashboardCell(
          id: 'cell-1',
          label: 'Juice',
          speakText: 'juice',
          emoji: '🧃',
        ),
      );
      await session.dashboards.save(dash);
      await session.tts.setVoice(
        const TtsVoice(name: 'Test Voice', locale: 'en-US'),
      );
      await session.history.load(id);
      session.tapWord(session.pack.wordById('core.want'));
      session.speakSentence();
      final cellsBefore = session
          .dashboards
          .forProfile(id)!
          .cells
          .map((c) => c.id)
          .toList();

      // Tap -> Build: composition surface changes, nothing else.
      await session.profiles.setCommunicationMode(id, CommunicationMode.build);
      session.tapBoardItem(session.pack.wordById('core.i'));
      expect(
        session.buildStrip.map((e) => e.text).toList(),
        ['I'],
      );
      expect(tts.spoken, ['want', 'want']);
      session.buildSpeak();
      expect(tts.spoken.last, 'I');

      // Build -> Tap: the strip stays (composition state), and all saved
      // content is exactly where it was.
      await session.profiles.setCommunicationMode(id, CommunicationMode.tap);
      expect(
        session.dashboards.forProfile(id)!.cells.map((c) => c.id).toList(),
        cellsBefore,
      );
      expect(session.tts.currentVoice?.name, 'Test Voice');
      expect(session.history.entries.length, 2);
      // History is newest-first.
      expect(session.history.entries.map((e) => e.text).toList(),
          ['I', 'want']);
    });

    test('full build flow works with a dead network', () async {
      final tts = _RecordingTts();
      final session = await makeBuildSession(tts, deadNetwork: true);
      final id = session.profiles.active!.id;
      await session.history.load(id);

      session.tapBoardItem(session.pack.wordById('core.i'));
      session.tapBoardItem(session.pack.wordById('core.want'));
      session.buildRemoveAt(1);
      session.tapBoardItem(session.pack.wordById('core.more'));
      session.buildSpeak();

      expect(tts.spoken, ['I more']);
      expect(session.history.entries.single.text, 'I more');
      // And the session never needed the network to get here.
      expect(session.proxySignedIn, isFalse);
    });
  });

  group('buildMaxSymbols (caregiver control)', () {
    test('clamps to 2..12 and defaults to 4', () async {
      SharedPreferences.setMockInitialValues({});
      final s = ProfileService();
      await s.load();
      final id = s.active!.id;

      expect(s.active!.buildMaxSymbols, 4);

      await s.setBuildMaxSymbols(id, 99);
      expect(s.active!.buildMaxSymbols, 12);
      await s.setBuildMaxSymbols(id, 0);
      expect(s.active!.buildMaxSymbols, 2);
      await s.setBuildMaxSymbols(id, 7);
      expect(s.active!.buildMaxSymbols, 7);

      // The clamp survives a fresh load.
      final reloaded = ProfileService();
      await reloaded.load();
      expect(reloaded.active!.buildMaxSymbols, 7);
    });

    testWidgets('slider drafts locally; save writes via setBuildMaxSymbols',
        (tester) async {
      final tts = _RecordingTts();
      final session = await makeSession(tts);
      final id = session.profiles.active!.id;

      await tester.pumpWidget(
        ChangeNotifierProvider<SessionState>.value(
          value: session,
          child: MaterialApp(
            home: Scaffold(
              body: BuildLengthEditor(
                key: ValueKey('build-length-$id'),
                profileId: id,
              ),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.text('Maximum phrase length'), findsOneWidget);
      expect(find.text('Current: 4 symbols'), findsOneWidget);

      // Dragging the slider only drafts — the saved value is untouched
      // until the explicit Save.
      await tester.drag(find.byType(Slider), const Offset(300, 0));
      await tester.pumpAndSettle();
      expect(session.profiles.active!.buildMaxSymbols, 4);

      await tester.tap(find.text('Save maximum'));
      await tester.pumpAndSettle();

      final saved = session.profiles.active!.buildMaxSymbols;
      expect(saved, inInclusiveRange(5, 12));
      expect(find.text('Current: $saved symbols'), findsOneWidget);
    });
  });

  group('build board (widget)', () {
    Future<void> pumpBuildBoard(
      WidgetTester tester,
      SessionState session,
    ) async {
      await tester.pumpWidget(OneVozApp(session: session));
      await tester.pumpAndSettle();
    }

    testWidgets('tapping words builds the strip; Speak speaks composed text',
        (tester) async {
      useWideSurface(tester);
      final tts = _RecordingTts();
      final session = await makeBuildSession(tts);
      await pumpBuildBoard(tester, session);

      expect(find.byType(BuildBoardScreen), findsOneWidget);
      expect(find.byType(HomeBoardScreen), findsNothing);

      await tester.tap(find.widgetWithText(WordButton, 'I'));
      await tester.pump();
      await tester.tap(find.widgetWithText(WordButton, 'want'));
      await tester.pump();

      expect(tts.spoken, isEmpty);
      expect(find.byKey(const ValueKey('build-strip-0')), findsOneWidget);
      expect(find.byKey(const ValueKey('build-strip-1')), findsOneWidget);

      await tester.tap(find.text('Speak'));
      await tester.pump();

      expect(tts.spoken, ['I want']);
    });

    testWidgets('tap-to-remove on a strip chip removes that unit',
        (tester) async {
      useWideSurface(tester);
      final tts = _RecordingTts();
      final session = await makeBuildSession(tts);
      await pumpBuildBoard(tester, session);

      await tester.tap(find.widgetWithText(WordButton, 'I'));
      await tester.pump();
      await tester.tap(find.widgetWithText(WordButton, 'want'));
      await tester.pump();
      expect(session.buildStrip.length, 2);

      // Chips carry an accessible remove label.
      final node = tester.getSemantics(
        find.byKey(const ValueKey('build-strip-1')),
      );
      expect(node.label, contains("Remove 'want' from phrase"));

      await tester.tap(find.byKey(const ValueKey('build-strip-1')));
      await tester.pump();
      expect(
        session.buildStrip.map((e) => e.text).toList(),
        ['I'],
      );
      expect(tts.spoken, isEmpty);
    });

    testWidgets('full strip rejects with visible feedback, never speaks',
        (tester) async {
      useWideSurface(tester);
      final tts = _RecordingTts();
      final session = await makeBuildSession(tts);
      await session.profiles.setBuildMaxSymbols(
        session.profiles.active!.id,
        2,
      );
      await pumpBuildBoard(tester, session);

      await tester.tap(find.widgetWithText(WordButton, 'I'));
      await tester.pump();
      await tester.tap(find.widgetWithText(WordButton, 'want'));
      await tester.pump();
      await tester.tap(find.widgetWithText(WordButton, 'go'));
      await tester.pump();

      // The rejected word never joins the strip, never speaks — and the
      // limit is visible on screen, not silent.
      expect(session.buildStrip.length, 2);
      expect(tts.spoken, isEmpty);
      expect(find.textContaining('Phrase strip is full'), findsOneWidget);
      expect(find.text('2 of 2'), findsOneWidget);
    });

    testWidgets('clear empties the strip', (tester) async {
      useWideSurface(tester);
      final tts = _RecordingTts();
      final session = await makeBuildSession(tts);
      await pumpBuildBoard(tester, session);

      await tester.tap(find.widgetWithText(WordButton, 'I'));
      await tester.pump();
      expect(session.buildStrip.length, 1);

      await tester.tap(find.text('Clear'));
      await tester.pump();

      expect(session.buildStrip, isEmpty);
      expect(tts.spoken, isEmpty);
      expect(find.byKey(const ValueKey('build-strip-0')), findsNothing);
    });
  });

  group('category folders in build mode', () {
    testWidgets('folder taps collect into the strip; bar is the strip bar',
        (tester) async {
      useWideSurface(tester);
      final tts = _RecordingTts();
      final session = await makeBuildSession(tts);

      await tester.pumpWidget(
        ChangeNotifierProvider<SessionState>.value(
          value: session,
          child: const MaterialApp(
            home: CategoryScreen(folderId: 'folder.food'),
          ),
        ),
      );
      await tester.pumpAndSettle();

      // The composition bar follows the mode: strip bar, not message bar.
      expect(find.byType(BuildStripBar), findsOneWidget);
      expect(find.byType(CompositionBar), findsOneWidget);

      await tester.tap(find.text('apple').first);
      await tester.pump();

      expect(tts.spoken, isEmpty);
      expect(
        session.buildStrip.map((e) => e.text).toList(),
        ['apple'],
      );
      expect(find.byKey(const ValueKey('build-strip-0')), findsOneWidget);

      await tester.tap(find.text('Speak'));
      await tester.pump();
      expect(tts.spoken, ['apple']);
    });

    testWidgets('tap mode folders still speak immediately (no regression)',
        (tester) async {
      useWideSurface(tester);
      final tts = _RecordingTts();
      final session = await makeSession(tts);

      await tester.pumpWidget(
        ChangeNotifierProvider<SessionState>.value(
          value: session,
          child: const MaterialApp(
            home: CategoryScreen(folderId: 'folder.food'),
          ),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.byType(BuildStripBar), findsNothing);

      await tester.tap(find.text('apple').first);
      await tester.pump();

      expect(tts.spoken, ['apple']);
      expect(session.sentenceIds, ['food.apple']);
    });
  });

  group('mode routing', () {
    test('homeScreenFor routes build to the build board', () async {
      final tapTts = _RecordingTts();
      final tapSession = await makeSession(tapTts);
      expect(homeScreenFor(tapSession), isA<HomeBoardScreen>());

      final buildTts = _RecordingTts();
      final buildSession = await makeBuildSession(buildTts);
      expect(homeScreenFor(buildSession), isA<BuildBoardScreen>());

      // Phase 4 shipped the Type screen: Type profiles get TypeBoardScreen.
      await tapSession.profiles.setCommunicationMode(
        tapSession.profiles.active!.id,
        CommunicationMode.type,
      );
      expect(homeScreenFor(tapSession), isA<TypeBoardScreen>());
    });

    testWidgets('OneVozApp switches surfaces when the mode changes',
        (tester) async {
      useWideSurface(tester);
      final tts = _RecordingTts();
      final session = await makeBuildSession(tts);

      await tester.pumpWidget(OneVozApp(session: session));
      await tester.pumpAndSettle();
      expect(find.byType(BuildBoardScreen), findsOneWidget);

      await session.profiles.setCommunicationMode(
        session.profiles.active!.id,
        CommunicationMode.tap,
      );
      session.notifyListeners();
      await tester.pumpAndSettle();

      expect(find.byType(HomeBoardScreen), findsOneWidget);
      expect(find.byType(BuildBoardScreen), findsNothing);
    });

    testWidgets('tap home board still speaks immediately (no regression)',
        (tester) async {
      useWideSurface(tester);
      final tts = _RecordingTts();
      final session = await makeSession(tts);

      await tester.pumpWidget(OneVozApp(session: session));
      await tester.pumpAndSettle();
      expect(find.byType(HomeBoardScreen), findsOneWidget);

      await tester.tap(find.text('want'));
      await tester.pump();

      expect(tts.spoken, ['want']);
      expect(session.sentenceIds, ['core.want']);
    });
  });
}
