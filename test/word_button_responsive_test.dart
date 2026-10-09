import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:onevoz/models/word.dart';
import 'package:onevoz/widgets/dashboard_tile.dart';
import 'package:onevoz/widgets/word_button.dart';

/// Regression: on a phone-width board (8 columns across ~390pt) the tile
/// content used to be fixed-size (38pt symbol + 12pt label), so every
/// cell overflowed and tiles painted over their neighbours, splitting
/// words mid-syllable ("plea/se"). Tile content must now scale with the
/// cell at every button-size setting, never overflow, and never split a
/// word across lines.
void main() {
  BoardItem item(String label) => BoardItem(
    id: 'core.${label.replaceAll(' ', '_')}',
    label: label,
    type: BoardItemType.word,
    category: 'core',
    row: 0,
    col: 0,
    emoji: '🔤',
  );

  Widget host(Widget child, {double w = 47, double h = 51}) {
    return MaterialApp(
      home: Scaffold(
        body: Center(
          child: SizedBox(width: w, height: h, child: child),
        ),
      ),
    );
  }

  for (final scale in [0.85, 1.0, 1.2]) {
    testWidgets('word button fits a phone-size cell (scale $scale)', (
      tester,
    ) async {
      await tester.pumpWidget(
        host(WordButton(item: item('finished'), scale: scale, onTap: () {})),
      );
      expect(tester.takeException(), isNull);
    });

    testWidgets('dashboard tile fits a phone-size cell (scale $scale)', (
      tester,
    ) async {
      await tester.pumpWidget(
        host(
          DashboardTile(label: "Grandma's house", scale: scale, onTap: () {}),
        ),
      );
      expect(tester.takeException(), isNull);
    });
  }

  testWidgets('8-column phone board does not overflow or split words', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(390 * 3, 844 * 3);
    tester.view.devicePixelRatio = 3.0;
    addTearDown(tester.view.reset);
    const labels = [
      'I',
      'you',
      'want',
      'please',
      'finished',
      'again',
      'help',
      'more',
    ];
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: GridView.count(
            crossAxisCount: 8,
            childAspectRatio: 0.92,
            padding: const EdgeInsets.all(8),
            children: [
              for (final label in labels)
                WordButton(item: item(label), scale: 1.2, onTap: () {}),
            ],
          ),
        ),
      ),
    );
    expect(tester.takeException(), isNull);
    // Every label renders as one un-split string on a single line.
    for (final label in labels) {
      final text = tester.widget<Text>(find.text(label));
      expect(text.maxLines, 1, reason: label);
    }
  });

  testWidgets('large cells still render (tablet/desktop)', (tester) async {
    await tester.pumpWidget(
      host(
        WordButton(item: item('juice'), scale: 1.2, onTap: () {}),
        w: 220,
        h: 200,
      ),
    );
    expect(tester.takeException(), isNull);
  });
}
