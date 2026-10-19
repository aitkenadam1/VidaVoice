import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:onevoz/models/dashboard.dart';
import 'package:onevoz/models/word.dart';
import 'package:onevoz/screens/board_preview_screen.dart';
import 'package:onevoz/services/profile_service.dart';
import 'package:onevoz/services/tts_service.dart';
import 'package:onevoz/state/session_state.dart';
import 'package:onevoz/widgets/dashboard_tile.dart';
import 'package:onevoz/widgets/word_button.dart';

/// Portal board preview: the caregiver sees (and hears) the active
/// profile's board without a mode switch, and preview taps must never
/// leak into the real session (no sentence, no build strip, no usage).
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

LanguagePack _loadPack() {
  final raw = File('assets/lang/en.json').readAsStringSync();
  final pack = LanguagePack.fromJson(
    Map<String, dynamic>.from(json.decode(raw) as Map),
  );
  pack.validate();
  return pack;
}

Future<SessionState> _makeSession(
  TtsService tts, {
  CommunicationMode mode = CommunicationMode.tap,
  bool withDashboard = false,
}) async {
  SharedPreferences.setMockInitialValues({});
  final session = SessionState(tts: tts);
  session.pack = _loadPack();
  session.status = BootStatus.ready;
  session.onboardingComplete = true;
  session.proxySignedIn = true;
  await session.profiles.load();
  await session.dashboards.load();
  if (mode != CommunicationMode.tap) {
    await session.profiles.setCommunicationMode(
      session.profiles.active!.id,
      mode,
    );
  }
  if (withDashboard) {
    final id = session.profiles.active!.id;
    final dashboard = session.dashboards.ensureFor(id);
    dashboard.cells.add(DashboardCell(id: 'c1', wordId: 'food.juice'));
    dashboard.cells.add(
      const DashboardCell(id: 'c2', label: 'Grandma', emoji: '👵'),
    );
    await session.dashboards.save(dashboard);
    await session.dashboards.setEnabled(id, true);
  }
  return session;
}

Widget _host(SessionState session) {
  return ChangeNotifierProvider<SessionState>.value(
    value: session,
    child: const MaterialApp(home: BoardPreviewScreen()),
  );
}

void _wideSurface(WidgetTester tester) {
  tester.view.physicalSize = const Size(1600, 2400);
  tester.view.devicePixelRatio = 1.0;
  addTearDown(tester.view.reset);
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('dashboard profile previews its dashboard, not the grid', (
    tester,
  ) async {
    _wideSurface(tester);
    final tts = _RecordingTts();
    final session = await _makeSession(tts, withDashboard: true);
    await tester.pumpWidget(_host(session));
    await tester.pumpAndSettle();

    expect(find.textContaining('Preview —'), findsOneWidget);
    // Dashboard cells render; a full-grid-only word does not.
    expect(find.byType(DashboardTile), findsOneWidget);
    expect(find.widgetWithText(DashboardTile, 'Grandma'), findsOneWidget);
    expect(find.byType(WordButton), findsOneWidget); // the juice cell
    // The toggle to the full board is offered.
    expect(find.text('Show all words'), findsOneWidget);
  });

  testWidgets('tap mode: taps speak and collect; session stays clean', (
    tester,
  ) async {
    _wideSurface(tester);
    final tts = _RecordingTts();
    final session = await _makeSession(tts, withDashboard: true);
    await session.usage.load();
    await tester.pumpWidget(_host(session));
    await tester.pumpAndSettle();

    await tester.tap(find.widgetWithText(DashboardTile, 'Grandma'));
    await tester.pumpAndSettle();
    expect(tts.spoken, ['Grandma']);

    // Nothing leaked into the real session.
    expect(session.sentenceIds, isEmpty);
    expect(session.buildStrip, isEmpty);
    expect(session.usage.countFor('food.juice'), 0);
  });

  testWidgets('build mode: taps collect silently; Speak speaks the strip', (
    tester,
  ) async {
    _wideSurface(tester);
    final tts = _RecordingTts();
    final session = await _makeSession(
      tts,
      mode: CommunicationMode.build,
      withDashboard: true,
    );
    await tester.pumpWidget(_host(session));
    await tester.pumpAndSettle();

    await tester.tap(find.byType(WordButton).first);
    await tester.pumpAndSettle();
    expect(tts.spoken, isEmpty);

    await tester.tap(find.text('Speak'));
    await tester.pumpAndSettle();
    expect(tts.spoken, ['juice']);
    // Still nothing in the real session's build strip.
    expect(session.buildStrip, isEmpty);
  });

  testWidgets('no dashboard: full grid previews; toggle shows dashboard', (
    tester,
  ) async {
    _wideSurface(tester);
    final tts = _RecordingTts();
    final session = await _makeSession(tts, withDashboard: true);
    await tester.pumpWidget(_host(session));
    await tester.pumpAndSettle();

    await tester.tap(find.text('Show all words'));
    await tester.pumpAndSettle();
    expect(find.byType(WordButton), findsWidgets);
    expect(find.text('Back to my board'), findsOneWidget);

    await tester.tap(find.text('Back to my board'));
    await tester.pumpAndSettle();
    expect(find.byType(DashboardTile), findsOneWidget);
  });
}
