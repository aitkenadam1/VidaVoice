/// A personal dashboard: a caregiver-curated board for one communicator
/// profile.
///
/// The standard home board never moves (motor planning is sacred). A
/// dashboard is the personal alternative: the caregiver picks the words
/// and phrases that matter most for one person, arranges them freely, and
/// can switch the profile's home board over to it. Importing an
/// Open Board Format file from another AAC app produces a dashboard too —
/// both paths converge on this model.
library;

/// One cell on a personal dashboard.
class DashboardCell {
  const DashboardCell({
    required this.id,
    this.wordId,
    this.label = '',
    this.speakText = '',
    this.emoji = '🔤',
    this.imageData,
    this.color,
  });

  /// Stable cell id (never the word id — the same word may appear twice).
  final String id;

  /// Vocabulary reference. When set, the label, symbol, and speech behavior
  /// resolve live from the current language pack: tapping behaves exactly
  /// like tapping the word on the standard board (words join the sentence
  /// bar, phrases speak whole), and the label follows language switches.
  /// Null for a free custom button.
  final String? wordId;

  /// Custom-button label (ignored when [wordId] is set).
  final String label;

  /// What TTS speaks for a custom button (ignored when [wordId] is set).
  /// Falls back to [label] when empty.
  final String speakText;

  /// Emoji shown for a custom button without an imported image.
  final String emoji;

  /// Base64-encoded image for a custom button (from an OBF import). Small
  /// images only — the importer caps them so dashboards stay portable
  /// across devices and web. Null when none.
  final String? imageData;

  /// ARGB background tint (from OBF button colors). Null = default card.
  final int? color;

  bool get isCustom => wordId == null;

  /// The text a custom button speaks. Empty when this is a vocab cell.
  String get customText =>
      speakText.isNotEmpty ? speakText : label;

  Map<String, dynamic> toJson() => {
    'id': id,
    if (wordId != null) 'wordId': wordId,
    'label': label,
    'speakText': speakText,
    'emoji': emoji,
    if (imageData != null) 'imageData': imageData,
    if (color != null) 'color': color,
  };

  factory DashboardCell.fromJson(Map<String, dynamic> json) {
    final id = json['id'];
    if (id is! String || id.isEmpty) {
      throw const FormatException('DashboardCell needs a String id.');
    }
    final wordId = json['wordId'];
    final imageData = json['imageData'];
    final color = json['color'];
    return DashboardCell(
      id: id,
      wordId: wordId is String && wordId.isNotEmpty ? wordId : null,
      label: (json['label'] as String?) ?? '',
      speakText: (json['speakText'] as String?) ?? '',
      emoji: (json['emoji'] as String?) ?? '🔤',
      imageData: imageData is String && imageData.isNotEmpty ? imageData : null,
      color: color is int ? color : null,
    );
  }
}

/// A caregiver-built (or imported) board for one profile.
class PersonalDashboard {
  PersonalDashboard({
    required this.id,
    required this.profileId,
    required this.name,
    List<DashboardCell>? cells,
    this.enabled = false,
    this.source,
    DateTime? updatedAt,
  }) : cells = cells ?? [],
       updatedAt = updatedAt ?? DateTime.now();

  final String id;
  final String profileId;
  String name;

  /// Display order = list order. The caregiver arranges these freely;
  /// motor-planning rules don't apply here because the dashboard is
  /// explicitly personal, not the shared standard board.
  final List<DashboardCell> cells;

  /// When true, this dashboard replaces the standard home board for the
  /// profile (with a session-only "show all words" escape hatch on it).
  bool enabled;

  /// Where the dashboard came from, e.g. 'OBF import: My Board'.
  /// Null for hand-built dashboards.
  String? source;

  DateTime updatedAt;

  Map<String, dynamic> toJson() => {
    'id': id,
    'profileId': profileId,
    'name': name,
    'cells': [for (final c in cells) c.toJson()],
    'enabled': enabled,
    if (source != null) 'source': source,
    'updatedAt': updatedAt.toIso8601String(),
  };

  factory PersonalDashboard.fromJson(Map<String, dynamic> json) {
    final id = json['id'];
    final profileId = json['profileId'];
    final name = json['name'];
    if (id is! String || profileId is! String || name is! String) {
      throw const FormatException(
        'PersonalDashboard needs String id/profileId/name.',
      );
    }
    final cellsJson = json['cells'];
    final cells = <DashboardCell>[];
    if (cellsJson is List) {
      for (final entry in cellsJson) {
        if (entry is Map) {
          cells.add(
            DashboardCell.fromJson(Map<String, dynamic>.from(entry)),
          );
        }
      }
    }
    DateTime updatedAt;
    try {
      updatedAt = DateTime.parse((json['updatedAt'] as String?) ?? '');
    } on FormatException {
      updatedAt = DateTime.now();
    }
    return PersonalDashboard(
      id: id,
      profileId: profileId,
      name: name,
      cells: cells,
      enabled: (json['enabled'] as bool?) ?? false,
      source: json['source'] as String?,
      updatedAt: updatedAt,
    );
  }
}
