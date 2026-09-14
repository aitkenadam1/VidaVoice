import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:vidavoice/main.dart';
import 'package:vidavoice/models/word.dart';
import 'package:vidavoice/services/tts_service.dart';
import 'package:vidavoice/state/session_state.dart';

/// TTS double: never touches the platform channel.
class _FakeTts extends TtsService {
  @override
  Future<bool> init({
    required String language,
    double rate = 0.5,
    double pitch = 1.0,
  }) async => true;

  @override
  Future<void> setLanguage(String language) async {}

  @override
  Future<void> setRate(double rate) async {}

  @override
  Future<void> setPitch(double pitch) async {}

  @override
  Future<void> speak(String text) async {}
}

/// TTS double for a device with no voice engine: init reports unavailable,
/// and speak silently no-ops (the base implementation already guards on
/// readiness, which stays false).
class _NoVoiceTts extends TtsService {
  @override
  Future<bool> init({
    required String language,
    double rate = 0.5,
    double pitch = 1.0,
  }) async => false;
}

/// First UI coverage for the app, built on the [SessionState] construction
/// seam (injectable TTS; no platform channels).
///
/// NOTE: `SessionState.boot()` is deliberately NOT exercised here — this
/// sandbox's flutter_tester cannot serve rootBundle assets, so the pack is
/// loaded from disk exactly like the unit tests do and injected directly.
/// On a normal dev machine `boot()` should be covered too.
void main() {
  LanguagePack loadPackFromFile() {
    final raw = File('assets/lang/en.json').readAsStringSync();
    final pack = LanguagePack.fromJson(
      Map<String, dynamic>.from(json.decode(raw) as Map),
    );
    pack.validate();
    return pack;
  }

  Future<SessionState> makeSession() async {
    SharedPreferences.setMockInitialValues({
      'vidavoice.onboardingComplete': true,
    });
    final session = SessionState(tts: _FakeTts());
    session.pack = loadPackFromFile();
    session.status = BootStatus.ready;
    session.onboardingComplete = true; // normally read from prefs in boot()
    return session;
  }

  /// Wide surface so the emoji-fallback cells (no pictograms in this
  /// sandbox's flutter_tester) have room and don't overflow.
  void useWideSurface(WidgetTester tester) {
    tester.view.physicalSize = const Size(1600, 2400);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
  }

  testWidgets('board renders, tap builds a sentence', (tester) async {
    useWideSurface(tester);
    final session = await makeSession();
    await session.setUnlockedLevel(LanguagePack.maxSupportedLevel);

    await tester.pumpWidget(VidaVoiceApp(session: session));
    await tester.pump();

    // A level-1 core word is on the board.
    expect(find.text('want'), findsOneWidget);

    // Tapping it appends to the sentence bar (button + bar = 2).
    await tester.tap(find.text('want'));
    await tester.pump();
    expect(session.sentenceIds, contains('core.want'));
    expect(find.text('want'), findsNWidgets(2));
  });

  testWidgets('progressive reveal hides locked words, keeps positions', (
    tester,
  ) async {
    useWideSurface(tester);
    final session = await makeSession();
    await session.setUnlockedLevel(1);

    await tester.pumpWidget(VidaVoiceApp(session: session));
    await tester.pump();

    // The grid is lazy: only on-screen cells exist. 'want' is level 1 and
    // on the first rows, so it works as the always-visible anchor.
    final starter = session.pack.homeItems.firstWhere(
      (i) => i.id == 'core.want',
    );
    // Any level-3 word with a unique label works as the locked word.
    final homeLabels = session.pack.homeItems
        .where((i) => !i.isFolder)
        .map((i) => i.label)
        .toList();
    final locked = session.pack.homeItems.firstWhere(
      (i) =>
          !i.isFolder &&
          i.level == 3 &&
          homeLabels.where((l) => l == i.label).length == 1,
    );

    expect(find.text(starter.label), findsOneWidget);
    expect(
      find.text(locked.label),
      findsNothing,
      reason: '${locked.id} must be hidden at level 1',
    );

    // Unlock everything: the locked word appears (scroll it into view),
    // the starter word does not move.
    await session.setUnlockedLevel(3);
    await tester.pump();
    await tester.scrollUntilVisible(
      find.text(locked.label),
      600,
      scrollable: find.byType(Scrollable).first,
    );
    expect(find.text(locked.label), findsOneWidget);
    await tester.scrollUntilVisible(
      find.text(starter.label),
      -600,
      scrollable: find.byType(Scrollable).first,
    );
    expect(find.text(starter.label), findsOneWidget);
  });

  testWidgets('no TTS engine: board boots with a dismissible banner', (
    tester,
  ) async {
    useWideSurface(tester);
    SharedPreferences.setMockInitialValues({
      'vidavoice.onboardingComplete': true,
    });
    final session = SessionState(tts: _NoVoiceTts());
    session.pack = loadPackFromFile();
    session.status = BootStatus.ready;
    session.onboardingComplete = true;
    // boot() would set this from the init() result; the seam bypasses boot().
    session.ttsAvailable = false;
    await session.setUnlockedLevel(LanguagePack.maxSupportedLevel);

    await tester.pumpWidget(VidaVoiceApp(session: session));
    await tester.pump();

    // The board is fully there despite no voice...
    expect(find.text('want'), findsOneWidget);
    // ...with the localized banner explaining why nothing speaks.
    expect(
      find.text(session.pack.ttsUnavailableBanner),
      findsOneWidget,
    );

    // Dismissing removes the banner but keeps the board.
    await tester.tap(find.byIcon(Icons.close));
    await tester.pump();
    expect(find.text(session.pack.ttsUnavailableBanner), findsNothing);
    expect(find.text('want'), findsOneWidget);

    // Tapping words still builds the sentence; speak silently no-ops.
    await tester.tap(find.text('want'));
    await tester.pump();
    expect(session.sentenceIds, contains('core.want'));
    session.speakSentence(); // must not throw
    await tester.pump();
  });
}
