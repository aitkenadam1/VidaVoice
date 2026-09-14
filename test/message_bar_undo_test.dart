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
  @override
  Future<List<TtsVoice>> getVoices() async => const [];

  @override
  Future<void> setVoice(TtsVoice voice) async {}

  @override
  Future<void> clearVoice() async {}

}

/// Widget coverage for the message-bar undo affordance:
/// tap removes the last word, long-press clears the sentence,
/// and editing never pollutes sentence history (only spoken
/// sentences are recorded).
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
    session.onboardingComplete = true;
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

  testWidgets('undo removes last word, speak records only spoken text', (
    tester,
  ) async {
    useWideSurface(tester);
    final session = await makeSession();
    await session.setUnlockedLevel(LanguagePack.maxSupportedLevel);

    await tester.pumpWidget(VidaVoiceApp(session: session));
    await tester.pump();

    // Build "want you" from the home board ('want' is unique until tapped).
    await tester.tap(find.text('want'));
    await tester.pump();
    await tester.tap(find.text('you'));
    await tester.pump();
    expect(session.sentenceIds, ['core.want', 'core.you']);

    // Undo removes only the last word; history stays empty (no speech yet).
    await tester.tap(find.byIcon(Icons.backspace_outlined));
    await tester.pump();
    expect(session.sentenceIds, ['core.want']);
    expect(session.history.entries, isEmpty);

    // Speak still works and records exactly what was spoken.
    await tester.tap(find.text('Speak'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 100));
    expect(session.history.entries, hasLength(1));
    expect(session.history.entries.first.text, 'want');
  });

  testWidgets('long-press undo clears the whole sentence', (tester) async {
    useWideSurface(tester);
    final session = await makeSession();
    await session.setUnlockedLevel(LanguagePack.maxSupportedLevel);

    await tester.pumpWidget(VidaVoiceApp(session: session));
    await tester.pump();

    await tester.tap(find.text('want'));
    await tester.pump();
    await tester.tap(find.text('you'));
    await tester.pump();
    expect(session.sentenceIds, hasLength(2));

    await tester.longPress(find.byIcon(Icons.backspace_outlined));
    await tester.pump();
    expect(session.sentenceIds, isEmpty);
    // Nothing was spoken, so nothing was recorded.
    expect(session.history.entries, isEmpty);
  });
}
