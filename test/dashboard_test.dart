import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:vidavoice/models/dashboard.dart';
import 'package:vidavoice/services/dashboard_service.dart';

/// Unit tests for the personal-dashboard model and store.
/// Run from the project root: `flutter test test/dashboard_test.dart`.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() {
    SharedPreferences.setMockInitialValues({});
  });

  test('DashboardCell JSON round trip (vocab reference)', () {
    const cell = DashboardCell(id: 'cell-1', wordId: 'core.want');
    final back = DashboardCell.fromJson(cell.toJson());
    expect(back.id, 'cell-1');
    expect(back.wordId, 'core.want');
    expect(back.isCustom, isFalse);
    expect(back.customText, isEmpty);
  });

  test('DashboardCell JSON round trip (custom with image and color)', () {
    const cell = DashboardCell(
      id: 'cell-2',
      label: 'I need help',
      speakText: 'I need help please',
      emoji: '🆘',
      imageData: 'aGVsbG8=',
      color: 0xFFFF0000,
    );
    final back = DashboardCell.fromJson(cell.toJson());
    expect(back.label, 'I need help');
    expect(back.customText, 'I need help please');
    expect(back.imageData, 'aGVsbG8=');
    expect(back.color, 0xFFFF0000);
    expect(back.isCustom, isTrue);
  });

  test('customText falls back to the label', () {
    const cell = DashboardCell(id: 'c', label: 'Hi');
    expect(cell.customText, 'Hi');
  });

  test('DashboardCell.fromJson rejects a missing id', () {
    expect(() => DashboardCell.fromJson({}), throwsFormatException);
  });

  test('DashboardCell.fromJson tolerates unknown shapes', () {
    final back = DashboardCell.fromJson({'id': 'c', 'color': 'red'});
    expect(back.color, isNull);
    expect(back.emoji, '🔤');
  });

  test('PersonalDashboard JSON round trip', () {
    final dashboard = PersonalDashboard(
      id: 'dash-p1',
      profileId: 'p1',
      name: 'Board',
      enabled: true,
      source: 'OBF import: x.obf',
      cells: const [DashboardCell(id: 'c1', wordId: 'core.go')],
    );
    final back = PersonalDashboard.fromJson(dashboard.toJson());
    expect(back.id, 'dash-p1');
    expect(back.profileId, 'p1');
    expect(back.name, 'Board');
    expect(back.enabled, isTrue);
    expect(back.source, 'OBF import: x.obf');
    expect(back.cells.length, 1);
    expect(back.cells.first.wordId, 'core.go');
  });

  test('service persists dashboards per profile', () async {
    final svc = DashboardService();
    await svc.load();

    final dashboard = svc.ensureFor('p1', name: 'Nia');
    dashboard.cells.add(
      DashboardCell(id: svc.newCellId(dashboard), wordId: 'core.want'),
    );
    await svc.save(dashboard);
    await svc.setEnabled('p1', true);

    final reloaded = DashboardService();
    await reloaded.load();
    expect(reloaded.isEnabled('p1'), isTrue);
    final back = reloaded.forProfile('p1')!;
    expect(back.name, 'Nia');
    expect(back.cells.length, 1);
    expect(back.cells.first.wordId, 'core.want');
    // Profiles are independent.
    expect(reloaded.isEnabled('p2'), isFalse);
    expect(reloaded.forProfile('p2'), isNull);
  });

  test('setEnabled on a missing dashboard is a no-op', () async {
    final svc = DashboardService();
    await svc.load();
    await svc.setEnabled('ghost', true);
    expect(svc.isEnabled('ghost'), isFalse);
  });

  test('delete removes the dashboard and persists', () async {
    final svc = DashboardService();
    await svc.load();
    final dashboard = svc.ensureFor('p1');
    await svc.save(dashboard);
    await svc.delete('p1');
    expect(svc.forProfile('p1'), isNull);

    final reloaded = DashboardService();
    await reloaded.load();
    expect(reloaded.forProfile('p1'), isNull);
  });

  test('corrupt prefs blob falls back to empty instead of breaking', () async {
    SharedPreferences.setMockInitialValues({
      'vidavoice.dashboards.v1': 'not-json{{{',
    });
    final svc = DashboardService();
    await svc.load();
    expect(svc.forProfile('p1'), isNull);
  });

  test('one corrupt dashboard does not take down the others', () async {
    SharedPreferences.setMockInitialValues({
      'vidavoice.dashboards.v1':
          '{"p1":{"id":"x"},"p2":{"id":"dash-p2","profileId":"p2","name":"Ok","cells":[]}}',
    });
    final svc = DashboardService();
    await svc.load();
    expect(svc.forProfile('p1'), isNull);
    expect(svc.forProfile('p2')!.name, 'Ok');
  });

  test('newCellId is unique across calls', () {
    final svc = DashboardService();
    final dashboard = PersonalDashboard(
      id: 'd',
      profileId: 'p',
      name: 'n',
    );
    final ids = {for (var i = 0; i < 10; i++) svc.newCellId(dashboard)};
    expect(ids.length, 10);
  });

  test('wrong field types are tolerated instead of failing boot (B1)', () async {
    // Hand-edited or cross-version data: ints where Strings/bools belong.
    // fromJson casts used to throw _TypeError here, failing app boot.
    SharedPreferences.setMockInitialValues({
      'vidavoice.dashboards.v1': jsonEncode({
        'p1': {
          'id': 'dash-p1',
          'profileId': 'p1',
          'name': 'Typed wrong',
          'enabled': 'yes',
          'source': 7,
          'updatedAt': 12345,
          'cells': [
            {
              'id': 'c1',
              'wordId': 'core.want',
              'label': 42,
              'speakText': 43,
              'emoji': 44,
              'color': 'red',
            },
          ],
        },
      }),
    });
    final svc = DashboardService();
    await svc.load(); // must not throw
    final dashboard = svc.forProfile('p1')!;
    expect(dashboard.enabled, isFalse);
    expect(dashboard.source, isNull);
    expect(dashboard.cells, hasLength(1));
    expect(dashboard.cells.single.label, isEmpty);
    expect(dashboard.cells.single.color, isNull);
    expect(dashboard.cells.single.wordId, 'core.want');
  });

  test('one bad cell is skipped, the rest of the dashboard survives (B1)', () async {
    SharedPreferences.setMockInitialValues({
      'vidavoice.dashboards.v1': jsonEncode({
        'p1': {
          'id': 'dash-p1',
          'profileId': 'p1',
          'name': 'One bad cell',
          'cells': [
            {'label': 'no id at all'},
            {'id': 'c2', 'label': 'Good'},
          ],
        },
      }),
    });
    final svc = DashboardService();
    await svc.load();
    final cells = svc.forProfile('p1')!.cells;
    expect(cells.map((c) => c.id), ['c2']);
  });

  test('vocab cell keeps its stored label through JSON (B2 fallback)', () {
    const cell = DashboardCell(
      id: 'c',
      wordId: 'core.want',
      label: 'want',
    );
    final back = DashboardCell.fromJson(cell.toJson());
    expect(back.wordId, 'core.want');
    expect(back.label, 'want');
    // The fallback tapDashboardCell uses when the word leaves the pack.
    expect(back.customText, 'want');
  });
}
