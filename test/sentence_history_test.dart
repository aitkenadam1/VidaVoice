import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:vidavoice/main.dart';
import 'package:vidavoice/models/word.dart';
import 'package:vidavoice/services/history_service.dart';
import 'package:vidavoice/services/tts_service.dart';
import 'package:vidavoice/state/session_state.dart';

class _FakeTts extends TtsService {
  int speakCalls = 0;
  String? lastSpoken;

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
  Future<void> speak(String text) async {
    speakCalls++;
    lastSpoken = text;
  }
  @override
  Future<List<TtsVoice>> getVoices() async => const [];

  @override
  Future<void> setVoice(TtsVoice voice) async {}

  @override
  Future<void> clearVoice() async {}

}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() {
    SharedPreferences.setMockInitialValues({});
  });

  group('HistoryService', () {
    test('records entries newest-first', () async {
      final history = HistoryService();
      await history.load('p1');

      await history.record('p1', ['core.want'], 'want', 'en');
      await history.record('p1', ['core.go'], 'go', 'en');

      expect(history.entries.length, 2);
      expect(history.entries.first.text, 'go');
      expect(history.entries.last.text, 'want');
      expect(history.entries.first.ids, ['core.go']);
      expect(history.entries.first.locale, 'en');
    });

    test('caps at 50 entries', () async {
      final history = HistoryService();
      await history.load('p1');
      for (var i = 0; i < 60; i++) {
        await history.record('p1', ['core.want'], 'sentence $i', 'en');
      }
      expect(history.entries.length, HistoryService.maxEntries);
      expect(history.entries.first.text, 'sentence 59');
    });

    test('history is per-profile', () async {
      final history = HistoryService();
      await history.load('p1');
      await history.record('p1', ['core.want'], 'want', 'en');

      await history.load('p2');
      expect(history.entries, isEmpty);

      await history.load('p1');
      expect(history.entries.length, 1);
    });

    test('persists across instances', () async {
      final history = HistoryService();
      await history.load('p1');
      await history.record('p1', ['core.want', 'core.go'], 'want go', 'es');

      final reloaded = HistoryService();
      await reloaded.load('p1');
      expect(reloaded.entries.length, 1);
      expect(reloaded.entries.first.text, 'want go');
      expect(reloaded.entries.first.ids, ['core.want', 'core.go']);
      expect(reloaded.entries.first.locale, 'es');
    });

    test('ignores empty recordings', () async {
      final history = HistoryService();
      await history.load('p1');
      await history.record('p1', [], '', 'en');
      await history.record('p1', ['core.want'], '', 'en');
      expect(history.entries, isEmpty);
    });

    test('corrupt storage loads empty instead of throwing', () async {
      SharedPreferences.setMockInitialValues({
        'vidavoice.history.p1.v1': 'not-json{{{',
      });
      final history = HistoryService();
      await history.load('p1'); // must not throw — boot must survive
      expect(history.entries, isEmpty);
    });

    test('clear removes the history', () async {
      final history = HistoryService();
      await history.load('p1');
      await history.record('p1', ['core.want'], 'want', 'en');
      await history.clear('p1');
      expect(history.entries, isEmpty);

      final reloaded = HistoryService();
      await reloaded.load('p1');
      expect(reloaded.entries, isEmpty);
    });
  });

  group('SessionState sentence history', () {
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
      await session.setUnlockedLevel(LanguagePack.maxSupportedLevel);
      return session;
    }

    test('speakSentence records the sentence in history', () async {
      final session = await makeSession();
      await session.history.load('p1');
      await session.profiles.load();

      session.tapWord(session.pack.wordById('core.want'));
      session.speakSentence();
      await Future<void>.delayed(Duration.zero); // fire-and-forget record

      expect(session.history.entries.length, 1);
      expect(session.history.entries.first.text, 'want');
      expect(session.history.entries.first.ids, ['core.want']);
      expect(session.history.entries.first.locale, 'en');
    });

    test('empty sentence is never recorded', () async {
      final session = await makeSession();
      await session.history.load('p1');
      session.speakSentence();
      await Future<void>.delayed(Duration.zero);
      expect(session.history.entries, isEmpty);
    });

    testWidgets('history affordance opens sheet; tap replays sentence', (
      tester,
    ) async {
      tester.view.physicalSize = const Size(1600, 2400);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);

      final session = await makeSession();
      await session.history.load('p1');
      await session.profiles.load();

      await tester.pumpWidget(VidaVoiceApp(session: session));
      await tester.pump();

      // Build a sentence and speak it.
      await tester.tap(find.text('want'));
      await tester.pump();
      await tester.tap(find.widgetWithText(FilledButton, 'Speak'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 50));

      // The history button opens the bottom sheet with the spoken sentence.
      await tester.tap(find.byTooltip('Recent sentences'));
      await tester.pumpAndSettle();
      expect(find.text('Recent sentences'), findsOneWidget);
      expect(find.text('want'), findsWidgets);

      // Tapping the entry reloads the sentence bar and speaks it again.
      session.clearSentence();
      await tester.pump();
      final fake = session.tts as _FakeTts;
      fake.speakCalls = 0;
      await tester.tap(find.widgetWithText(ListTile, 'want').first);
      await tester.pumpAndSettle();
      expect(session.sentenceIds, ['core.want']);
      expect(fake.speakCalls, greaterThanOrEqualTo(1));
      expect(fake.lastSpoken, 'want');
    });
  });
}
