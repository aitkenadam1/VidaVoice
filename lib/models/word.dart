/// Data model for the language-pack board.
///
/// Motor planning is sacred: every home-grid position (row/col) is declared
/// in the language-pack JSON and NEVER computed at runtime.
/// [LanguagePack.validate] enforces the 2-tap budget — every word is on the
/// home grid (1 tap) or in exactly one folder (2 taps).
library;

/// A validation failure. Packs that fail must never ship.
class PackValidationError extends Error {
  PackValidationError(this.message);

  final String message;

  @override
  String toString() => 'PackValidationError: $message';
}

enum BoardItemType { word, folder }

/// One tappable cell on the home grid.
class BoardItem {
  const BoardItem({
    required this.id,
    required this.label,
    required this.type,
    required this.category,
    required this.row,
    required this.col,
    required this.emoji,
  });

  /// Language-independent id, e.g. "core.want". Bilingual users keep the
  /// same motor position across languages because ids don't change.
  final String id;
  final String label;
  final BoardItemType type;
  final String category;

  /// FIXED grid position from the language pack. Never computed, never moved.
  final int row;
  final int col;

  /// v0.01 symbol stand-in. Replaced by ARASAAC/Mulberry assets later;
  /// the id stays the same so motor positions survive the swap.
  final String emoji;

  bool get isFolder => type == BoardItemType.folder;

  factory BoardItem.fromJson(Map<String, dynamic> json) {
    final typeStr = json['type'] as String;
    return BoardItem(
      id: json['id'] as String,
      label: json['label'] as String,
      type: typeStr == 'folder' ? BoardItemType.folder : BoardItemType.word,
      category: (json['category'] as String?) ?? 'core',
      row: (json['row'] as num?)?.toInt() ?? -1,
      col: (json['col'] as num?)?.toInt() ?? -1,
      emoji: (json['emoji'] as String?) ?? '🔤',
    );
  }
}

/// A category folder: its tile lives on the home grid, its words are one tap
/// deeper. Folder words carry no grid position; JSON order is display order.
class FolderPack {
  const FolderPack({
    required this.id,
    required this.label,
    required this.emoji,
    required this.words,
  });

  final String id;
  final String label;
  final String emoji;
  final List<BoardItem> words;

  factory FolderPack.fromJson(String id, Map<String, dynamic> json) {
    final wordsJson = json['words'] as List<dynamic>;
    return FolderPack(
      id: id,
      label: json['label'] as String,
      emoji: (json['emoji'] as String?) ?? '📁',
      words: wordsJson.map((w) {
        final m = Map<String, dynamic>.from(w as Map);
        return BoardItem.fromJson({...m, 'type': 'word', 'category': 'folder'});
      }).toList(),
    );
  }
}

/// A versioned language pack: vocabulary + grid + TTS config for one locale.
class LanguagePack {
  const LanguagePack({
    required this.locale,
    required this.displayName,
    required this.ttsLocale,
    required this.version,
    required this.gridColumns,
    required this.homeItems,
    required this.folders,
  });

  final String locale;
  final String displayName;
  final String ttsLocale;
  final int version;
  final int gridColumns;
  final List<BoardItem> homeItems;
  final Map<String, FolderPack> folders;

  /// Grid rows implied by the fixed positions declared in [homeItems].
  int get gridRows {
    var max = 0;
    for (final item in homeItems) {
      if (item.row + 1 > max) max = item.row + 1;
    }
    return max;
  }

  /// The item at a fixed grid position, or null for an empty cell.
  BoardItem? itemAt(int row, int col) {
    for (final item in homeItems) {
      if (item.row == row && item.col == col) return item;
    }
    return null;
  }

  /// Look up any word (home grid or folder) by its language-independent id.
  BoardItem wordById(String id) {
    for (final item in homeItems) {
      if (item.id == id) return item;
    }
    for (final folder in folders.values) {
      for (final word in folder.words) {
        if (word.id == id) return word;
      }
    }
    throw PackValidationError('Unknown word id $id.');
  }

  factory LanguagePack.fromJson(Map<String, dynamic> json) {
    final itemsJson = json['items'] as List<dynamic>;
    final foldersJson = Map<String, dynamic>.from(json['folders'] as Map);
    final folders = <String, FolderPack>{};
    foldersJson.forEach((key, value) {
      folders[key] = FolderPack.fromJson(
        key,
        Map<String, dynamic>.from(value as Map),
      );
    });
    return LanguagePack(
      locale: json['locale'] as String,
      displayName: json['displayName'] as String,
      ttsLocale: (json['ttsLocale'] as String?) ?? (json['locale'] as String),
      version: (json['version'] as num).toInt(),
      gridColumns: (json['gridColumns'] as num).toInt(),
      homeItems: itemsJson
          .map((e) => BoardItem.fromJson(Map<String, dynamic>.from(e as Map)))
          .toList(),
      folders: folders,
    );
  }

  /// Enforces the fixed-position invariant and the 2-tap navigation budget.
  /// Throws [PackValidationError] on any violation — callers should fail fast.
  void validate() {
    final seenCells = <String>{};
    final seenIds = <String>{};
    final folderIdsOnGrid = <String>{};

    for (final item in homeItems) {
      if (item.row < 0 || item.col < 0 || item.col >= gridColumns) {
        throw PackValidationError(
          'Item ${item.id} has invalid grid position '
          '(${item.row}, ${item.col}).',
        );
      }
      final cell = '${item.row}:${item.col}';
      if (!seenCells.add(cell)) {
        throw PackValidationError(
          'Duplicate grid position $cell — motor-planning violation.',
        );
      }
      if (!seenIds.add(item.id)) {
        throw PackValidationError('Duplicate item id ${item.id}.');
      }
      if (item.isFolder) folderIdsOnGrid.add(item.id);
    }

    for (final entry in folders.entries) {
      if (!folderIdsOnGrid.contains(entry.key)) {
        throw PackValidationError(
          'Folder ${entry.key} has no folder tile on the home grid.',
        );
      }
      for (final word in entry.value.words) {
        if (word.isFolder) {
          throw PackValidationError(
            'Nested folders are not allowed (${word.id}). 2-tap budget.',
          );
        }
        if (!seenIds.add(word.id)) {
          throw PackValidationError(
            'Word ${word.id} appears in more than one place. '
            '2-tap budget violated.',
          );
        }
      }
    }

    for (final folderId in folderIdsOnGrid) {
      if (!folders.containsKey(folderId)) {
        throw PackValidationError(
          'Folder tile $folderId has no word list in "folders".',
        );
      }
    }
  }
}
