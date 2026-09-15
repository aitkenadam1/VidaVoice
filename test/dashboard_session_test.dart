import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:vidavoice/models/dashboard.dart';
import 'package:vidavoice/models/word.dart';
import 'package:vidavoice/services/dashboard_service.dart';
import 'package:vidavoice/services/tts_service.dart';
import 'package:vidavoice/state/session_state.dart';

/// TTS double that records what it was asked to speak.
class _RecordingTts extends TtsService {
  final spoken = <String>[];

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
}

/// Session-level dashboard behavior: the B2 fallback (a vocab cell whose
/// word left the pack speaks its stored label instead of going silent)
/// and the "Show all words" / "Back to my board" toggle.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  LanguagePack loadPackFromFile() {
    final raw = File('assets/lang/en.json').readAsStringSync();
    final pack = LanguagePack.fromJson(
      Map<String, dynamic>.from(json.decode(raw) as Map),
    );
    pack.validate();
    return pack;
  }

  Future<SessionState> makeSession(_RecordingTts tts) async {
    SharedPreferences.setMockInitialValues({});
    final session = SessionState(tts: tts);
    session.pack = loadPackFromFile();
    session.status = BootStatus.ready;
    await session.profiles.addProfile('Tester');
    return session;
  }

  Future<void> enableDashboard(SessionState session, String profileId) async {
    final dashboard = session.dashboards.ensureFor(profileId);
    dashboard.cells.add(
      const DashboardCell(id: 'c1', wordId: 'core.want', label: 'want'),
    );
    dashboard.enabled = true;
    await session.dashboards.save(dashboard);
  }

  test('tapDashboardCell speaks the stored label when the word is gone (B2)',
      () async {
    final tts = _RecordingTts();
    final session = await makeSession(tts);
    session.tapDashboardCell(
      const DashboardCell(
        id: 'c1',
        wordId: 'nope.vanished',
        label: 'stored words',
      ),
    );
    expect(tts.spoken, ['stored words']);
    // A dead word must never join the sentence bar.
    expect(session.sentenceIds, isEmpty);
  });

  test('tapDashboardCell on a live word behaves like the board', () async {
    final tts = _RecordingTts();
    final session = await makeSession(tts);
    final label = session.pack.wordById('core.want').label;
    session.tapDashboardCell(
      const DashboardCell(id: 'c1', wordId: 'core.want', label: 'want'),
    );
    expect(tts.spoken, [label]);
    expect(session.sentenceIds, ['core.want']);
  });

  test('"Show all words" bypasses and "Back to my board" restores', () async {
    final tts = _RecordingTts();
    final session = await makeSession(tts);
    final profileId = session.profiles.active!.id;
    await enableDashboard(session, profileId);

    expect(session.showDashboard, isTrue);
    expect(session.canRestoreDashboard, isFalse);

    session.bypassDashboard();
    expect(session.showDashboard, isFalse);
    expect(session.canRestoreDashboard, isTrue);

    session.restoreDashboard();
    expect(session.showDashboard, isTrue);
    expect(session.canRestoreDashboard, isFalse);
  });

  test('restore is a no-op when no dashboard is enabled', () async {
    final tts = _RecordingTts();
    final session = await makeSession(tts);
    session.bypassDashboard();
    expect(session.showDashboard, isFalse);
    expect(session.canRestoreDashboard, isFalse);
    session.restoreDashboard(); // must not throw
    expect(session.showDashboard, isFalse);
  });

  test('backfillLabels heals legacy cells whose word still resolves',
      () async {
    final tts = _RecordingTts();
    final session = await makeSession(tts);
    final profileId = session.profiles.active!.id;
    final dashboard = session.dashboards.ensureFor(profileId);
    dashboard.cells.addAll(const [
      // Legacy 0a03d75 cell: wordId only, no stored label.
      DashboardCell(id: 'legacy', wordId: 'core.want'),
      // Word already gone: nothing to backfill from, must not throw.
      DashboardCell(id: 'gone', wordId: 'nope.vanished'),
      // Already has a label: untouched.
      DashboardCell(id: 'kept', wordId: 'core.want', label: 'mine'),
      // Custom button: untouched.
      DashboardCell(id: 'custom', label: 'hi'),
    ]);
    await session.dashboards.save(dashboard);

    await session.dashboards.backfillLabels(session.pack);

    final cells = {for (final c in dashboard.cells) c.id: c};
    final wantLabel = session.pack.wordById('core.want').label;
    expect(cells['legacy']!.label, wantLabel);
    expect(cells['gone']!.label, isEmpty);
    expect(cells['kept']!.label, 'mine');
    expect(cells['custom']!.label, 'hi');

    // The heal persists: a fresh load (next boot) sees the stored label.
    final fresh = DashboardService();
    await fresh.load();
    final reloaded = {
      for (final c in fresh.forProfile(profileId)!.cells) c.id: c,
    };
    expect(reloaded['legacy']!.label, wantLabel);
    expect(reloaded['gone']!.label, isEmpty);
  });
}
