import 'dart:convert';

import 'package:archive/archive.dart';

import '../models/dashboard.dart';

/// Thrown when picked bytes are not a readable board file. The message is
/// shown to the caregiver, so keep it plain-language.
class ObfImportError extends Error {
  ObfImportError(this.message);

  final String message;

  @override
  String toString() => 'ObfImportError: $message';
}

/// What an import produced, plus everything the caregiver should know.
class ObfImportReport {
  const ObfImportReport({
    required this.dashboard,
    required this.buttonCount,
    required this.skippedLinkCount,
    required this.imageCount,
    this.truncated = false,
    this.warnings = const [],
  });

  final PersonalDashboard dashboard;
  final int buttonCount;
  final int skippedLinkCount;
  final int imageCount;
  final bool truncated;
  final List<String> warnings;
}

/// Imports Open Board Format boards into a [PersonalDashboard].
///
/// OBF (openboardformat.org) is the open standard AAC apps like CoughDrop
/// export: a `.obf` JSON file, or a `.obz` zip containing the JSON plus its
/// images. Proprietary backups (Proloquo2Go, TouchChat) are not readable
/// and are rejected with a plain-language error.
///
/// Mapping decisions (deliberate, documented):
/// - Every imported button becomes a custom cell that speaks its text
///   immediately when tapped — atomic, like a quick phrase. Imported
///   buttons do NOT join the sentence bar (we can't know which source
///   buttons were sentence-builders), so review the import before handing
///   the board to the communicator. We do NOT fuzzy-match labels to our
///   vocabulary: a wrong match on a communication device is worse than no
///   match.
/// - Buttons that link to another board (`load_board`) are skipped — this
///   app has no multi-board navigation. The report says how many.
/// - A multi-board package imports one board: the manifest's root board
///   when the package declares one, otherwise the alphabetically first
///   .obf (deterministic). The report names the board that was used.
/// - Sounds are ignored; speech always comes from the device TTS voice.
/// - Images are embedded as base64 in the dashboard (capped per image) so
///   the board works offline and on web with no file I/O.
class ObfImportService {
  /// Pathological boards are truncated rather than imported whole.
  static const maxCells = 300;

  /// Images bigger than this are skipped (with a warning) — dashboards
  /// live in SharedPreferences and must stay portable.
  static const maxImageBytes = 250 * 1024;

  ObfImportReport importBytes(
    List<int> bytes, {
    required String profileId,
    required String fileName,
  }) {
    final isZip =
        bytes.length >= 4 &&
        bytes[0] == 0x50 &&
        bytes[1] == 0x4B &&
        bytes[2] == 0x03 &&
        bytes[3] == 0x04;
    final media = <String, List<int>>{};
    final String jsonText;
    var obfBoardCount = 0;
    var obfBoardName = '';
    var usedManifestRoot = false;
    if (isZip) {
      Archive archive;
      try {
        archive = ZipDecoder().decodeBytes(bytes);
      } catch (_) {
        throw ObfImportError('"$fileName" is not a readable zip file.');
      }
      final obfCandidates = <ArchiveFile>[];
      ArchiveFile? manifestFile;
      for (final file in archive.files) {
        if (!file.isFile) continue;
        final lower = file.name.toLowerCase();
        if (lower.endsWith('.obf')) {
          obfCandidates.add(file);
        } else {
          if (lower == 'manifest.json' || lower.endsWith('/manifest.json')) {
            manifestFile ??= file;
          }
          if (!_isNoiseFile(lower)) {
            media[file.name] = file.content;
          }
        }
      }
      if (obfCandidates.isEmpty) {
        throw ObfImportError('"$fileName" has no board (.obf) inside it.');
      }
      // The OBF package manifest names the root board: honor it when it
      // points at a board in this package. Otherwise fall back to a
      // deterministic alphabetical choice so the same file always imports
      // the same board. Either way the caregiver is told which board was
      // used.
      final rootPath = _manifestRoot(manifestFile);
      final rootMatch = rootPath == null
          ? const <ArchiveFile>[]
          : obfCandidates.where((f) => _samePath(f.name, rootPath)).toList();
      ArchiveFile obfFile;
      if (rootMatch.isNotEmpty) {
        obfFile = rootMatch.first;
        usedManifestRoot = true;
      } else {
        obfCandidates.sort((a, b) => a.name.compareTo(b.name));
        obfFile = obfCandidates.first;
      }
      obfBoardCount = obfCandidates.length;
      obfBoardName = obfFile.name;
      try {
        jsonText = utf8.decode(obfFile.content);
      } catch (_) {
        throw ObfImportError('The board inside "$fileName" is not text.');
      }
    } else {
      try {
        jsonText = utf8.decode(bytes);
      } catch (_) {
        throw ObfImportError('"$fileName" is not a readable text file.');
      }
    }

    final dynamic decoded;
    try {
      decoded = json.decode(jsonText);
    } catch (_) {
      throw ObfImportError(
        '"$fileName" is not a board file. Export an Open Board Format '
        '(.obf or .obz) file from the other app and try again.',
      );
    }
    if (decoded is! Map) {
      throw ObfImportError('"$fileName" is not a board file.');
    }
    final board = Map<String, dynamic>.from(decoded);

    final warnings = <String>[];
    final format = board['format'];
    // Prefix match: the standard declares 'open-board-format' and versioned
    // values (e.g. 'open-board-format-v0.1') must not trip the warning.
    if (format is String &&
        format.isNotEmpty &&
        !format.startsWith('open-board-format')) {
      warnings.add(
        'This file does not declare the Open Board Format standard — '
        'importing it anyway, but check the result carefully.',
      );
    }
    if (obfBoardCount > 1) {
      warnings.add(
        usedManifestRoot
            ? 'The file contained $obfBoardCount boards; '
                '"$obfBoardName" was imported (the package\'s root board).'
            : 'The file contained $obfBoardCount boards; '
                '"$obfBoardName" was imported. Export a single board to choose a '
                'different one.',
      );
    }

    final buttonsJson = board['buttons'];
    if (buttonsJson is! List || buttonsJson.isEmpty) {
      throw ObfImportError('"$fileName" has no buttons to import.');
    }
    final buttons = <String, Map<String, dynamic>>{};
    for (final entry in buttonsJson) {
      if (entry is Map) {
        final map = Map<String, dynamic>.from(entry);
        final id = map['id']?.toString();
        if (id != null && id.isNotEmpty) buttons[id] = map;
      }
    }
    if (buttons.isEmpty) {
      throw ObfImportError('"$fileName" has no usable buttons.');
    }

    // Button order: the grid's row-major order, then any buttons the grid
    // didn't reference (some exporters are sloppy).
    final orderedIds = <String>[];
    final grid = board['grid'];
    if (grid is Map) {
      final order = Map<String, dynamic>.from(grid)['order'];
      if (order is List) {
        for (final row in order) {
          if (row is List) {
            for (final cell in row) {
              final id = cell?.toString();
              if (id != null &&
                  id.isNotEmpty &&
                  buttons.containsKey(id) &&
                  !orderedIds.contains(id)) {
                orderedIds.add(id);
              }
            }
          }
        }
      }
    }
    for (final id in buttons.keys) {
      if (!orderedIds.contains(id)) orderedIds.add(id);
    }

    final images = _indexImages(board['images'], media, warnings);

    final boardName = (board['name'] as String?)?.trim();
    final dashboard = PersonalDashboard(
      id: 'dash-$profileId',
      profileId: profileId,
      name: boardName != null && boardName.isNotEmpty ? boardName : 'Imported board',
      source: 'OBF import: $fileName',
    );

    var skippedLinks = 0;
    var skippedBlank = 0;
    var imageCount = 0;
    for (final id in orderedIds) {
      if (dashboard.cells.length >= maxCells) break;
      final button = buttons[id]!;
      // Board links have no meaning here — count and skip.
      if (button['load_board'] is Map) {
        skippedLinks++;
        continue;
      }
      final label = (button['label'] as String?)?.trim() ?? '';
      final vocalization = (button['vocalization'] as String?)?.trim() ?? '';
      final speakText = vocalization.isNotEmpty ? vocalization : label;
      // Blank placeholder cells are grid filler, not content — skip them
      // without counting toward truncation.
      if (label.isEmpty && speakText.isEmpty) {
        skippedBlank++;
        continue;
      }

      String? imageData;
      final imageId = button['image_id']?.toString();
      if (imageId != null && images.containsKey(imageId)) {
        imageData = images[imageId];
        if (imageData != null) imageCount++;
      }

      dashboard.cells.add(
        DashboardCell(
          id: 'cell-$id',
          label: label.isNotEmpty ? label : speakText,
          speakText: speakText,
          emoji: _emojiFor(label),
          imageData: imageData,
          color: _parseColor(button['background_color'], warnings),
        ),
      );
    }

    if (dashboard.cells.isEmpty) {
      throw ObfImportError(
        '"$fileName" had no importable buttons'
        '${skippedLinks > 0 ? ' (its $skippedLinks buttons only link to other boards)' : ''}.',
      );
    }

    final truncated =
        orderedIds.length >
        dashboard.cells.length + skippedLinks + skippedBlank;
    if (skippedLinks > 0) {
      warnings.add(
        '$skippedLinks button${skippedLinks == 1 ? '' : 's'} linked to other '
        'boards and ${skippedLinks == 1 ? 'was' : 'were'} skipped — this app '
        'has one board per dashboard.',
      );
    }
    if (truncated) {
      warnings.add(
        'The board was very large; only the first $maxCells buttons were imported.',
      );
    }

    return ObfImportReport(
      dashboard: dashboard,
      buttonCount: dashboard.cells.length,
      skippedLinkCount: skippedLinks,
      imageCount: imageCount,
      truncated: truncated,
      warnings: warnings,
    );
  }

  /// macOS zips love to include these; they are never board media.
  bool _isNoiseFile(String lowerName) =>
      lowerName.startsWith('__macosx/') || lowerName.endsWith('.ds_store');

  /// The root-board path declared by the OBF package manifest, if any.
  /// Anything unparseable is ignored — the caller falls back to a
  /// deterministic choice.
  String? _manifestRoot(ArchiveFile? manifestFile) {
    if (manifestFile == null) return null;
    try {
      final decoded = json.decode(utf8.decode(manifestFile.content));
      if (decoded is Map) {
        final root = Map<String, dynamic>.from(decoded)['root'];
        if (root is String && root.trim().isNotEmpty) return root.trim();
      }
    } catch (_) {
      // Not a readable manifest; fall back below.
    }
    return null;
  }

  /// True when two zip entry paths name the same file, ignoring a
  /// leading './' or '/' and backslash separators.
  bool _samePath(String a, String b) {
    String norm(String p) =>
        p.replaceAll('\\', '/').replaceFirst(RegExp(r'^(\./|/)+'), '');
    return norm(a) == norm(b);
  }

  /// image id -> base64 payload (data URIs stripped, oversized skipped).
  Map<String, String?> _indexImages(
    dynamic imagesJson,
    Map<String, List<int>> media,
    List<String> warnings,
  ) {
    final result = <String, String?>{};
    if (imagesJson is! List) return result;
    for (final entry in imagesJson) {
      if (entry is! Map) continue;
      final image = Map<String, dynamic>.from(entry);
      final id = image['id']?.toString();
      if (id == null || id.isEmpty) continue;
      List<int>? bytes;
      final data = image['data'] as String?;
      if (data != null && data.isNotEmpty) {
        final payload = data.contains(',') ? data.split(',').last : data;
        try {
          bytes = base64.decode(payload.replaceAll(RegExp(r'\s'), ''));
        } catch (_) {
          warnings.add('One image could not be decoded and was skipped.');
          result[id] = null;
          continue;
        }
      } else {
        final path = image['path'] as String?;
        if (path != null && media.containsKey(path)) {
          bytes = media[path];
        } else if ((image['url'] as String?)?.isNotEmpty ?? false) {
          warnings.add(
            'One image lives on the internet and was skipped — imports stay offline.',
          );
          result[id] = null;
          continue;
        }
      }
      if (bytes == null || bytes.isEmpty) {
        result[id] = null;
        continue;
      }
      if (bytes.length > maxImageBytes) {
        warnings.add(
          'One large image was skipped to keep the board portable.',
        );
        result[id] = null;
        continue;
      }
      result[id] = base64.encode(bytes);
    }
    return result;
  }

  /// Parses `#rrggbb` / `#aarrggbb` (the OBF convention) and CSS
  /// `rgb(r, g, b)` / `rgba(r, g, b, a)` (common in real AAC exports).
  /// Anything else keeps the default card color; one warning covers all.
  int? _parseColor(dynamic raw, List<String> warnings) {
    if (raw is! String) return null;
    final text = raw.trim();
    final hex = text.replaceFirst('#', '');
    if (RegExp(r'^[0-9a-fA-F]{6}$|^[0-9a-fA-F]{8}$').hasMatch(hex)) {
      final argb = hex.length == 6 ? 'ff$hex' : hex;
      return int.parse(argb, radix: 16);
    }
    final rgb = RegExp(
      r'^rgba?\(\s*(\d{1,3})\s*,\s*(\d{1,3})\s*,\s*(\d{1,3})'
      r'\s*(?:,\s*([\d.]+)\s*)?\)$',
    ).firstMatch(text);
    if (rgb != null) {
      final r = int.parse(rgb.group(1)!).clamp(0, 255);
      final g = int.parse(rgb.group(2)!).clamp(0, 255);
      final b = int.parse(rgb.group(3)!).clamp(0, 255);
      var a = 255;
      final alphaRaw = rgb.group(4);
      if (alphaRaw != null) {
        final alpha = double.tryParse(alphaRaw);
        if (alpha != null) {
          // CSS alpha is 0–1; tolerate a 0–255 value too.
          a = alpha <= 1.0
              ? (alpha * 255).round().clamp(0, 255)
              : alpha.round().clamp(0, 255);
        }
      }
      return (a << 24) | (r << 16) | (g << 8) | b;
    }
    if (!warnings.any((w) => w.startsWith('Some button colors'))) {
      warnings.add(
        'Some button colors were not understood and kept the default.',
      );
    }
    return null;
  }

  /// A best-effort emoji so imageless buttons aren't blank grey squares.
  String _emojiFor(String label) {
    final lower = label.toLowerCase();
    if (lower.contains('yes')) return '✅';
    if (lower.contains('no')) return '❌';
    if (lower.contains('help')) return '🆘';
    if (lower.contains('eat') || lower.contains('food') || lower.contains('hungry')) {
      return '🍽️';
    }
    if (lower.contains('drink') || lower.contains('thirsty')) return '🥤';
    if (lower.contains('bathroom') || lower.contains('toilet')) return '🚻';
    if (lower.contains('pain') || lower.contains('hurt')) return '🤕';
    if (lower.contains('happy')) return '😊';
    if (lower.contains('sad')) return '😢';
    if (lower.contains('play')) return '🧸';
    if (lower.contains('sleep') || lower.contains('tired')) return '😴';
    if (lower.contains('more')) return '➕';
    if (lower.contains('stop') || lower.contains('done') || lower.contains('finish')) {
      return '🛑';
    }
    if (lower.contains('go')) return '🏃';
    if (lower.contains('want')) return '🙋';
    if (lower.contains('like') || lower.contains('love')) return '❤️';
    return '🔤';
  }
}
