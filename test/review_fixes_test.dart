import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:onevoz/main.dart';
import 'package:onevoz/models/word.dart';
import 'package:onevoz/screens/build_board_screen.dart';
import 'package:onevoz/screens/home_board_screen.dart';
import 'package:onevoz/services/profile_service.dart';
import 'package:onevoz/services/tts_service.dart';
import 'package:onevoz/state/session_state.dart';

/// Independent-review fixes (2026-09-15). Each test pins a defect found
/// during the consolidated review of the five modes phases:
///
/// 1. A caregiver "Save mode" must switch the home screen immediately —
///    persisting the mode is not enough when nothing rebuilds the
///    MaterialApp home. [SessionState.setCommunicationMode] persists AND
///    notifies.
/// 2. A caregiver "Save" on the phrase-length limit must take effect
///    immediately for the same reason ([SessionState.setBuildMaxSymbols]).
/// 3. The Build phrase strip is unsent composition state: it must never
///    survive a profile switch, a profile deletion, or a language change.
/// 4. Deleting a profile must delete its per-profile data too — spoken
///    history and learned prediction ranks must not linger on the device
///    for a profile that no longer exists.
class _SilentTts extends TtsService {
  @override
  Future<bool> init({
    required String language,
    double rate = 0.5,
    double pitch = 1.0,
  }) async => true;

  @override
  Future<void> speak(String text) async {}
}

Future<SessionState> makeSession() async {
  SharedPreferences.setMockInitialValues({});
  final session = SessionState(tts: _SilentTts());
  session.status = BootStatus.ready;
  session.onboardingComplete = true;
  await session.profiles.load();
  final id = session.profiles.active!.id;
  await session.history.load(id);
  await session.prediction.load(id);
  await session.nudge.load();
  return session;
}

void main() {
  // buildAdd announces via WidgetsBinding (screen-reader feedback), so
  // these pure unit tests need the test binding initialized.
  TestWidgetsFlutterBinding.ensureInitialized();
  group('review fix: mode save switches the home screen', () {
    test('setCommunicationMode persists and notifies listeners', () async {
      final session = await makeSession();
      final id = session.profiles.active!.id;
      var notified = 0;
      session.addListener(() => notified++);

      await session.setCommunicationMode(id, CommunicationMode.build);

      expect(session.profiles.active!.communicationMode,
          CommunicationMode.build);
      expect(notified, greaterThan(0),
          reason: 'the home screen must rebuild on a mode change');
      expect(homeScreenFor(session), isA<BuildBoardScreen>());

      await session.setCommunicationMode(id, CommunicationMode.tap);
      expect(homeScreenFor(session), isA<HomeBoardScreen>());
    });

    test('setBuildMaxSymbols persists and notifies listeners', () async {
      final session = await makeSession();
      final id = session.profiles.active!.id;
      var notified = 0;
      session.addListener(() => notified++);

      await session.setBuildMaxSymbols(id, 9);

      expect(session.profiles.active!.buildMaxSymbols, 9);
      expect(notified, greaterThan(0),
          reason: 'the phrase strip must re-read the limit immediately');
    });
  });

  group('review fix: build strip never crosses profiles or locales', () {
    test('switchProfile clears the strip and its notice', () async {
      final session = await makeSession();
      final a = session.profiles.active!;
      final b = await session.profiles.addProfile('B');
      await session.setCommunicationMode(a.id, CommunicationMode.build);
      final item = BoardItem(
        id: 'w-more',
        label: 'more',
        type: BoardItemType.word,
        category: 'core',
        row: 0,
        col: 0,
        emoji: '➕',
        level: 1,
      );
      expect(session.buildAdd(item), isTrue);
      expect(session.buildStrip, isNotEmpty);

      await session.switchProfile(b.id);

      expect(session.buildStrip, isEmpty);
      expect(session.buildNotice, isNull);
    });

    test('removeProfile clears the strip', () async {
      final session = await makeSession();
      final a = session.profiles.active!;
      await session.profiles.addProfile('B');
      await session.switchProfile(a.id);
      await session.setCommunicationMode(a.id, CommunicationMode.build);
      final item = BoardItem(
        id: 'w-more',
        label: 'more',
        type: BoardItemType.word,
        category: 'core',
        row: 0,
        col: 0,
        emoji: '➕',
        level: 1,
      );
      expect(session.buildAdd(item), isTrue);

      await session.removeProfile(a.id);

      expect(session.buildStrip, isEmpty);
    });
  });

  group('review fix: deleting a profile deletes its data', () {
    test('history and learned ranks are gone for the deleted id',
        () async {
      final session = await makeSession();
      final prefs = await SharedPreferences.getInstance();
      final victim = await session.profiles.addProfile('Victim');
      final vid = victim.id;

      // Seed per-profile data for the victim profile.
      await session.history.load(vid);
      await session.history.record(vid, const ['w-more'], 'more please', 'en');
      await session.prediction.load(vid);
      await session.prediction.learn(vid, 'more please', 'en');
      expect(prefs.getString('vidavoice.history.$vid.v1'), isNotNull);
      expect(prefs.getString('vidavoice.predictionRanks.$vid.v1'), isNotNull);

      await session.removeProfile(vid);

      expect(prefs.getString('vidavoice.history.$vid.v1'), isNull,
          reason: 'deleted profile history must not linger on device');
      expect(prefs.getString('vidavoice.predictionRanks.$vid.v1'), isNull,
          reason: 'deleted profile learned ranks must not linger on device');
    });
  });
}
