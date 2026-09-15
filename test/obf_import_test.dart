import 'dart:convert';

import 'package:archive/archive.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:onevoz/services/obf_import_service.dart';
import 'package:onevoz/widgets/dashboard_tile.dart';

/// Unit tests for Open Board Format import + the dashboard tile.
/// Run from the project root: `flutter test test/obf_import_test.dart`.
///
/// The OBF fixtures below are hand-written but spec-shaped
/// (openboardformat.org): grid order, buttons with labels/vocalizations/
/// colors/image refs, board links, inline and zipped images.
String _obfJson({String? imageEntry}) {
  return json.encode({
    'format': 'open-board-format',
    'id': 'board-1',
    'name': 'Test Board',
    'locale': 'en',
    'grid': {
      'rows': 2,
      'columns': 2,
      'order': [
        ['b1', 'b2'],
        ['b3', 'b4'],
      ],
    },
    'buttons': [
      {
        'id': 'b1',
        'label': 'Hello',
        'vocalization': 'Hello there',
        'background_color': '#ff0000',
        'image_id': 'img1',
      },
      {
        'id': 'b2',
        'label': 'More',
      },
      {
        'id': 'b3',
        'label': 'Food page',
        'load_board': {'id': 'board-2', 'name': 'Food'},
      },
      {
        'id': 'b4',
        'label': '   ',
        'vocalization': '',
      },
    ],
    'images': [
      if (imageEntry != null) json.decode(imageEntry),
    ],
  });
}

List<int> _obzBytes() {
  final obf = utf8.encode(
    _obfJson(
      imageEntry: json.encode({'id': 'img1', 'path': 'pics/photo.png'}),
    ),
  );
  final png = List<int>.filled(100, 7);
  final archive = Archive()
    ..addFile(ArchiveFile('board.obf', obf.length, obf))
    ..addFile(ArchiveFile('pics/photo.png', png.length, png));
  return ZipEncoder().encode(archive);
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('imports a minimal .obf in grid order', () {
    final report = ObfImportService().importBytes(
      utf8.encode(
        _obfJson(
          imageEntry: json.encode({
            'id': 'img1',
            'content_type': 'image/png',
            // data-URI prefix must be stripped; payload is a PNG header.
            'data': 'data:image/png;base64,iVBORw0KGgo=',
          }),
        ),
      ),
      profileId: 'p1',
      fileName: 'board.obf',
    );

    expect(report.buttonCount, 2);
    expect(report.skippedLinkCount, 1); // the board-link button
    expect(report.imageCount, 1);
    expect(report.dashboard.name, 'Test Board');
    expect(report.dashboard.source, 'OBF import: board.obf');

    final first = report.dashboard.cells[0];
    expect(first.label, 'Hello');
    expect(first.customText, 'Hello there');
    expect(first.color, 0xFFFF0000);
    expect(first.imageData, 'iVBORw0KGgo=');

    final second = report.dashboard.cells[1];
    expect(second.label, 'More');
    expect(second.customText, 'More');
  });

  test('board-link skips are reported as warnings', () {
    final report = ObfImportService().importBytes(
      utf8.encode(_obfJson()),
      profileId: 'p1',
      fileName: 'board.obf',
    );
    expect(
      report.warnings.any((w) => w.contains('1 button') && w.contains('skipped')),
      isTrue,
    );
  });

  test('imports a .obz with images by path', () {
    final report = ObfImportService().importBytes(
      _obzBytes(),
      profileId: 'p1',
      fileName: 'board.obz',
    );
    expect(report.buttonCount, 2);
    expect(report.imageCount, 1);
    final first = report.dashboard.cells[0];
    expect(first.imageData, base64.encode(List<int>.filled(100, 7)));
  });

  test('garbage bytes throw a plain-language error', () {
    expect(
      () => ObfImportService().importBytes(
        [0x00, 0x01, 0x02, 0x03],
        profileId: 'p1',
        fileName: 'weird.bin',
      ),
      throwsA(isA<ObfImportError>()),
    );
  });

  test('JSON without buttons throws', () {
    expect(
      () => ObfImportService().importBytes(
        utf8.encode('{"format":"open-board-format","name":"Empty"}'),
        profileId: 'p1',
        fileName: 'empty.obf',
      ),
      throwsA(isA<ObfImportError>()),
    );
  });

  test('a board of only links throws', () {
    final onlyLinks = json.encode({
      'format': 'open-board-format',
      'name': 'Links',
      'grid': {
        'order': [
          ['b1'],
        ],
      },
      'buttons': [
        {
          'id': 'b1',
          'label': 'Next',
          'load_board': {'id': 'b2'},
        },
      ],
    });
    expect(
      () => ObfImportService().importBytes(
        utf8.encode(onlyLinks),
        profileId: 'p1',
        fileName: 'links.obf',
      ),
      throwsA(isA<ObfImportError>()),
    );
  });

  test('oversized images are skipped with a warning', () {
    final big = base64.encode(List<int>.filled(300 * 1024, 9));
    final report = ObfImportService().importBytes(
      utf8.encode(
        _obfJson(
          imageEntry: json.encode({'id': 'img1', 'data': big}),
        ),
      ),
      profileId: 'p1',
      fileName: 'big.obf',
    );
    expect(report.imageCount, 0);
    expect(report.dashboard.cells[0].imageData, isNull);
    expect(
      report.warnings.any((w) => w.contains('large image')),
      isTrue,
    );
  });

  test('unparseable colors keep the default', () {
    final json = jsonDecode(_obfJson()) as Map<String, dynamic>;
    (json['buttons'] as List)[0]['background_color'] = 'not-a-color';
    final report = ObfImportService().importBytes(
      utf8.encode(jsonEncode(json)),
      profileId: 'p1',
      fileName: 'colors.obf',
    );
    expect(report.dashboard.cells[0].color, isNull);
    expect(
      report.warnings.any((w) => w.contains('colors')),
      isTrue,
    );
  });

  testWidgets('DashboardTile shows label and emoji', (tester) async {
    await tester.pumpWidget(
      const MaterialApp(
        home: Scaffold(
          body: DashboardTile(label: 'Hi', emoji: '👋', onTap: _noop),
        ),
      ),
    );
    expect(find.text('Hi'), findsOneWidget);
    expect(find.text('👋'), findsOneWidget);
  });

  testWidgets('DashboardTile falls back to emoji on bad image data',
      (tester) async {
    await tester.pumpWidget(
      const MaterialApp(
        home: Scaffold(
          body: DashboardTile(
            label: 'X',
            // Valid base64, not a valid image.
            imageData: 'aGVsbG8=',
            emoji: '🔤',
            onTap: _noop,
          ),
        ),
      ),
    );
    await tester.pump();
    expect(find.text('🔤'), findsOneWidget);
  });

  test('blank placeholder buttons do not trigger the truncation warning (3)',
      () {
    // The shared fixture has 4 grid buttons: 2 imported, 1 link, 1 blank.
    final report = ObfImportService().importBytes(
      utf8.encode(_obfJson()),
      profileId: 'p1',
      fileName: 'placeholders.obf',
    );
    expect(report.buttonCount, 2);
    expect(report.truncated, isFalse);
    expect(
      report.warnings.any((w) => w.contains('very large')),
      isFalse,
    );
  });

  test('versioned format values pass the prefix check without warning (4)',
      () {
    final json = jsonDecode(_obfJson()) as Map<String, dynamic>;
    json['format'] = 'open-board-format-v0.1';
    final ok = ObfImportService().importBytes(
      utf8.encode(jsonEncode(json)),
      profileId: 'p1',
      fileName: 'versioned.obf',
    );
    expect(
      ok.warnings.any((w) => w.contains('Open Board Format standard')),
      isFalse,
    );

    json['format'] = 'something-else-entirely';
    final warned = ObfImportService().importBytes(
      utf8.encode(jsonEncode(json)),
      profileId: 'p1',
      fileName: 'other.obf',
    );
    expect(
      warned.warnings.any((w) => w.contains('Open Board Format standard')),
      isTrue,
    );
  });

  test('rgb() and rgba() button colors are parsed (5)', () {
    final json = jsonDecode(_obfJson()) as Map<String, dynamic>;
    final buttons = json['buttons'] as List;
    buttons[0]['background_color'] = 'rgb(255, 0, 0)';
    buttons[1]['background_color'] = 'rgba(0, 255, 0, 0.5)';
    final report = ObfImportService().importBytes(
      utf8.encode(jsonEncode(json)),
      profileId: 'p1',
      fileName: 'css-colors.obf',
    );
    expect(report.dashboard.cells[0].color, 0xFFFF0000);
    expect(report.dashboard.cells[1].color, 0x8000FF00);
    expect(
      report.warnings.any((w) => w.contains('colors')),
      isFalse,
    );
  });

  test('a multi-board .obz picks one board deterministically and says which',
      () {
    final first = utf8.encode(_obfJson());
    final secondJson = jsonDecode(_obfJson()) as Map<String, dynamic>;
    secondJson['name'] = 'Second Board';
    final second = utf8.encode(jsonEncode(secondJson));
    final archive = Archive()
      ..addFile(ArchiveFile('zebra.obf', second.length, second))
      ..addFile(ArchiveFile('alpha.obf', first.length, first));
    final report = ObfImportService().importBytes(
      ZipEncoder().encode(archive),
      profileId: 'p1',
      fileName: 'multi.obz',
    );
    // Sorted by name: alpha.obf wins over zebra.obf regardless of order.
    expect(report.dashboard.name, 'Test Board');
    expect(
      report.warnings.any((w) => w.contains('2 boards') && w.contains('alpha.obf')),
      isTrue,
    );
  });

  test('a multi-board .obz honors the manifest root board', () {
    final first = utf8.encode(_obfJson());
    final secondJson = jsonDecode(_obfJson()) as Map<String, dynamic>;
    secondJson['name'] = 'Second Board';
    final second = utf8.encode(jsonEncode(secondJson));
    final manifest = utf8.encode(jsonEncode({'root': 'boards/zebra.obf'}));
    final archive = Archive()
      ..addFile(ArchiveFile('boards/zebra.obf', second.length, second))
      ..addFile(ArchiveFile('boards/alpha.obf', first.length, first))
      ..addFile(ArchiveFile('manifest.json', manifest.length, manifest));
    final report = ObfImportService().importBytes(
      ZipEncoder().encode(archive),
      profileId: 'p1',
      fileName: 'multi.obz',
    );
    // The manifest root wins over alphabetical order.
    expect(report.dashboard.name, 'Second Board');
    expect(
      report.warnings.any(
        (w) => w.contains('2 boards') && w.contains('root board'),
      ),
      isTrue,
    );
  });
}

void _noop() {}
