import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:onevoz/models/word.dart';
import 'package:onevoz/theme/onevoz_theme.dart';
import 'package:onevoz/widgets/word_button.dart';

/// Visual proof for the responsive board: renders the REAL home grid
/// (en.json fixed positions) at phone, tablet, and desktop widths and
/// stores golden PNGs under test/goldens/. The same tiles used to be
/// fixed-size, so at phone width every cell overflowed its neighbours
/// (Adam's 2026-10-09 iPhone screenshot: tiles colliding, words split
/// mid-syllable). Run with --update-goldens to refresh.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late LanguagePack pack;

  setUpAll(() async {
    final raw = await File('assets/lang/en.json').readAsString();
    pack = LanguagePack.fromJson(jsonDecode(raw) as Map<String, dynamic>);
  });

  Widget cell(int r, int c, double scale) {
    final item = pack.itemAt(r, c, unlockedLevel: 3);
    if (item == null) return const SizedBox.shrink();
    return WordButton(item: item, scale: scale, onTap: () {});
  }

  Widget board({required double buttonScale}) {
    return MaterialApp(
      theme: OneVozTheme.childTheme(),
      home: Scaffold(
        body: GridView.count(
          crossAxisCount: pack.gridColumns,
          padding: const EdgeInsets.all(8),
          childAspectRatio: 0.92,
          children: [
            for (var r = 0; r < 8; r++)
              for (var c = 0; c < pack.gridColumns; c++)
                cell(r, c, buttonScale),
          ],
        ),
      ),
    );
  }

  Future<void> shoot(
    WidgetTester tester,
    Size size,
    String name, {
    double buttonScale = 1.2,
  }) async {
    tester.view.physicalSize = size;
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(board(buttonScale: buttonScale));
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
    await expectLater(
      find.byType(GridView),
      matchesGoldenFile('goldens/$name.png'),
    );
  }

  testWidgets('board at phone width (390x844, Large buttons)',
      (tester) async {
    await shoot(tester, const Size(390, 844), 'board_phone');
  });

  testWidgets('board at tablet width (768x1024)', (tester) async {
    await shoot(tester, const Size(768, 1024), 'board_tablet',
        buttonScale: 1.0);
  });

  testWidgets('board at desktop width (1440x900)', (tester) async {
    await shoot(tester, const Size(1440, 900), 'board_desktop',
        buttonScale: 1.0);
  });
}
