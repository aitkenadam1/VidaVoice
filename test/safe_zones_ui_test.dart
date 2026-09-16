import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:latlong2/latlong.dart';
import 'package:onevoz/models/safe_zone.dart';
import 'package:onevoz/screens/safe_zone_editor_screen.dart';
import 'package:onevoz/widgets/safe_zones_card.dart';

SafeZone _zone({
  String id = 'zone_aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa',
  String name = 'Home',
  double radiusM = 300,
  bool enabled = true,
  bool notifyEnter = true,
  bool notifyExit = false,
}) =>
    SafeZone(
      id: id,
      name: name,
      lat: 40.123,
      lng: -111.456,
      radiusM: radiusM,
      enabled: enabled,
      notifyEnter: notifyEnter,
      notifyExit: notifyExit,
      updatedTs: DateTime.fromMillisecondsSinceEpoch(1000),
    );

Widget _wrap(Widget child) => MaterialApp(home: Scaffold(body: child));

void main() {
  group('SafeZonesCard', () {
    testWidgets('empty state invites adding a zone', (tester) async {
      var added = false;
      await tester.pumpWidget(
        _wrap(
          SafeZonesCard(
            zones: const [],
            onAdd: () => added = true,
            onEdit: (_) {},
            onToggle: (z, v) async {},
          ),
        ),
      );
      expect(find.text('Safe zones'), findsOneWidget);
      expect(find.textContaining('No safe zones yet'), findsOneWidget);
      await tester.tap(find.text('Add safe zone'));
      expect(added, isTrue);
    });

    testWidgets('lists zones with radius and notifies detail', (tester) async {
      await tester.pumpWidget(
        _wrap(
          SafeZonesCard(
            zones: [_zone(), _zone(id: 'zone_bbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbb', name: 'School', radiusM: 500, enabled: false, notifyEnter: false, notifyExit: true)],
            onAdd: () {},
            onEdit: (_) {},
            onToggle: (z, v) async {},
          ),
        ),
      );
      expect(find.text('Home'), findsOneWidget);
      expect(find.text('School'), findsOneWidget);
      expect(find.textContaining('300 m radius'), findsOneWidget);
      expect(find.textContaining('500 m radius'), findsOneWidget);
      expect(find.textContaining('notifies on arrival'), findsOneWidget);
      expect(find.textContaining('notifies on leaving'), findsOneWidget);
    });

    testWidgets('tapping a row opens the editor; switch toggles', (tester) async {
      SafeZone? edited;
      SafeZone? toggled;
      bool? toggledTo;
      await tester.pumpWidget(
        _wrap(
          SafeZonesCard(
            zones: [_zone()],
            onAdd: () {},
            onEdit: (z) => edited = z,
            onToggle: (z, v) async {
              toggled = z;
              toggledTo = v;
            },
          ),
        ),
      );
      await tester.tap(find.text('Home'));
      expect(edited?.id, _zone().id);

      await tester.tap(find.byType(Switch));
      await tester.pump();
      expect(toggled?.id, _zone().id);
      expect(toggledTo, isFalse);
    });

    testWidgets('syncing row shows a spinner instead of the switch',
        (tester) async {
      await tester.pumpWidget(
        _wrap(
          SafeZonesCard(
            zones: [_zone()],
            onAdd: () {},
            onEdit: (_) {},
            onToggle: (z, v) async {},
            syncingIds: {_zone().id},
          ),
        ),
      );
      expect(find.byType(CircularProgressIndicator), findsOneWidget);
      expect(find.byType(Switch), findsNothing);
    });

    testWidgets('states the P1 honesty note', (tester) async {
      await tester.pumpWidget(
        _wrap(
          SafeZonesCard(
            zones: const [],
            onAdd: () {},
            onEdit: (_) {},
            onToggle: (z, v) async {},
          ),
        ),
      );
      expect(
        find.textContaining('nothing watches these zones yet'),
        findsOneWidget,
      );
    });
  });

  group('SafeZoneEditorScreen (create)', () {
    Future<void> pumpEditor(
      WidgetTester tester, {
      SafeZone? existing,
      Future<void> Function(SafeZone)? onSave,
      Future<void> Function(SafeZone)? onDelete,
      Future<LatLng?> Function()? getCurrentLocation,
      List<SafeZone>? saved,
    }) async {
      await tester.pumpWidget(
        MaterialApp(
          home: SafeZoneEditorScreen(
            existing: existing,
            onSave: (z) async {
              saved?.add(z);
              await onSave?.call(z);
            },
            onDelete: onDelete,
            getCurrentLocation: getCurrentLocation ?? () async => null,
          ),
        ),
      );
      await tester.pumpAndSettle();
    }

    /// The save button sits at the bottom of the editor's ListView, so
    /// scroll it into view before tapping (test viewport is 800x600).
    /// skipOffstage:false — the button starts below the fold.
    Future<void> tapSave(WidgetTester tester) async {
      final save = find.byKey(const Key('zone_save_button'));
      final list = find.byType(ListView);
      for (var i = 0;
          i < 6 && save.evaluate().isEmpty;
          i++) {
        await tester.drag(list, const Offset(0, -400));
        await tester.pumpAndSettle();
      }
      await tester.tap(save);
      await tester.pump();
    }

    testWidgets('save with nothing filled shows inline errors', (tester) async {
      await pumpEditor(tester);
      await tapSave(tester);
      await tester.pump();
      // The error box renders at the top of the form, scrolled offstage
      // after the save button was brought into view.
      expect(
        find.textContaining(
          'Give the zone a name',
          skipOffstage: false,
        ),
        findsOneWidget,
      );
      expect(
        find.textContaining(
          'Place the zone center',
          skipOffstage: false,
        ),
        findsOneWidget,
      );
    });

    testWidgets('valid input saves a zone with defaults', (tester) async {
      final saved = <SafeZone>[];
      await pumpEditor(tester, saved: saved);
      await tester.enterText(
        find.byKey(const Key('zone_name_field')),
        'Home',
      );
      await tester.enterText(
        find.byKey(const Key('zone_lat_field')),
        '40.123',
      );
      await tester.enterText(
        find.byKey(const Key('zone_lng_field')),
        '-111.456',
      );
      await tapSave(tester);
      await tester.pumpAndSettle();

      expect(saved, hasLength(1));
      final z = saved.single;
      expect(z.name, 'Home');
      expect(z.lat, 40.123);
      expect(z.lng, -111.456);
      expect(z.radiusM, SafeZone.defaultRadiusM);
      expect(z.enabled, isTrue);
      expect(z.notifyEnter, isTrue);
      expect(z.notifyExit, isTrue);
      expect(z.id, startsWith('zone_'));
      // Popped: the editor is gone.
      expect(find.text('New safe zone'), findsNothing);
    });

    testWidgets('radius slider changes the saved radius', (tester) async {
      final saved = <SafeZone>[];
      await pumpEditor(tester, saved: saved);
      await tester.enterText(
        find.byKey(const Key('zone_name_field')),
        'Park',
      );
      await tester.enterText(find.byKey(const Key('zone_lat_field')), '40.1');
      await tester.enterText(find.byKey(const Key('zone_lng_field')), '-111.5');
      // Drag the slider right; radius must grow above the 300 m default.
      await tester.drag(find.byType(Slider), const Offset(200, 0));
      await tester.pumpAndSettle();
      await tapSave(tester);
      await tester.pumpAndSettle();
      expect(saved.single.radiusM, greaterThan(300));
      expect(saved.single.radiusM, lessThanOrEqualTo(2000));
    });

    testWidgets('Use mine with no fix explains honestly', (tester) async {
      await pumpEditor(tester, getCurrentLocation: () async => null);
      await tester.tap(find.text('Use mine'));
      await tester.pump();
      expect(
        find.textContaining('can\u2019t get your location right now'),
        findsOneWidget,
      );
    });

    testWidgets('Use mine with a fix fills the coordinates', (tester) async {
      final saved = <SafeZone>[];
      await pumpEditor(
        tester,
        saved: saved,
        getCurrentLocation: () async => const LatLng(41.5, -112.5),
      );
      await tester.tap(find.text('Use mine'));
      await tester.pump();
      await tester.enterText(
        find.byKey(const Key('zone_name_field')),
        'Cabin',
      );
      await tapSave(tester);
      await tester.pumpAndSettle();
      expect(saved.single.lat, 41.5);
      expect(saved.single.lng, -112.5);
    });
  });

  group('SafeZoneEditorScreen (edit)', () {
    testWidgets('prefills existing values; delete asks then deletes',
        (tester) async {
      final deleted = <SafeZone>[];
      final existing = _zone();
      await tester.pumpWidget(
        MaterialApp(
          home: SafeZoneEditorScreen(
            existing: existing,
            onSave: (_) async {},
            onDelete: (z) async => deleted.add(z),
            getCurrentLocation: () async => null,
          ),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.text('Edit safe zone'), findsOneWidget);
      final nameField = tester.widget<TextField>(
        find.byKey(const Key('zone_name_field')),
      );
      expect(nameField.controller!.text, 'Home');

      await tester.tap(find.byTooltip('Delete zone'));
      await tester.pumpAndSettle();
      expect(find.textContaining('Delete \u201cHome\u201d?'), findsOneWidget);

      await tester.tap(find.text('Delete'));
      await tester.pumpAndSettle();
      expect(deleted, hasLength(1));
      expect(deleted.single.id, existing.id);
    });

    testWidgets('delete can be cancelled', (tester) async {
      var deleteCalls = 0;
      await tester.pumpWidget(
        MaterialApp(
          home: SafeZoneEditorScreen(
            existing: _zone(),
            onSave: (_) async {},
            onDelete: (_) async => deleteCalls++,
            getCurrentLocation: () async => null,
          ),
        ),
      );
      await tester.pumpAndSettle();
      await tester.tap(find.byTooltip('Delete zone'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Keep it'));
      await tester.pumpAndSettle();
      expect(deleteCalls, 0);
      // Still on the editor.
      expect(find.text('Edit safe zone'), findsOneWidget);
    });

    testWidgets('create mode has no delete action', (tester) async {
      await tester.pumpWidget(
        MaterialApp(
          home: SafeZoneEditorScreen(
            onSave: (_) async {},
            getCurrentLocation: () async => null,
          ),
        ),
      );
      await tester.pumpAndSettle();
      expect(find.byTooltip('Delete zone'), findsNothing);
    });
  });
}
