/// Communication goals for one communicator profile.
///
/// A goal is the outcome the family is working toward ("Ask for a drink
/// with two symbols", "Greet the teacher independently by December").
/// Caregivers set a target date, check the goal off when it's achieved,
/// and collect feedback and comments from the whole care team. Words and
/// phrases added to the profile's board *for* a goal are linked to it, so
/// the setup work that supports the goal stays visible in one place.
///
/// Goals ride the family's end-to-end encrypted sync blob exactly like
/// safe zones (see DashboardSyncService): the server only ever stores
/// ciphertext, and merges are last-writer-wins per goal id with delete
/// tombstones so a goal deleted on one device stays deleted.
library;

/// One feedback/comment entry on a goal. The care team uses these to
/// record what they're seeing ("Used it twice at school today!").
class GoalComment {
  const GoalComment({
    required this.id,
    required this.author,
    required this.text,
    required this.createdAt,
  });

  final String id;

  /// Display name of the commenter inside the family (their OneVoz
  /// username when known, else a role label like "Speech therapist").
  final String author;

  final String text;
  final DateTime createdAt;

  Map<String, dynamic> toJson() => {
    'id': id,
    'author': author,
    'text': text,
    'createdAt': createdAt.toIso8601String(),
  };

  factory GoalComment.fromJson(Map<String, dynamic> json) {
    final id = json['id'];
    if (id is! String || id.isEmpty) {
      throw const FormatException('GoalComment needs a String id.');
    }
    return GoalComment(
      id: id,
      author: _str(json, 'author', 'Team member'),
      text: _str(json, 'text'),
      createdAt: _date(json['createdAt']),
    );
  }
}

/// A board item that was added to support a goal: a dashboard cell on the
/// profile's personal dashboard. The label is a snapshot for display —
/// the cell itself (by [cellId]) is the live item on the board.
class GoalLink {
  const GoalLink({
    required this.kind,
    required this.cellId,
    required this.label,
  });

  /// 'word' for a vocabulary word, 'phrase' for a custom phrase button.
  final String kind;

  /// Id of the DashboardCell on the profile's dashboard.
  final String cellId;

  /// What the button says (snapshot from when it was added).
  final String label;

  Map<String, dynamic> toJson() => {
    'kind': kind,
    'cellId': cellId,
    'label': label,
  };

  factory GoalLink.fromJson(Map<String, dynamic> json) {
    final cellId = json['cellId'];
    if (cellId is! String || cellId.isEmpty) {
      throw const FormatException('GoalLink needs a String cellId.');
    }
    return GoalLink(
      kind: _str(json, 'kind', 'word'),
      cellId: cellId,
      label: _str(json, 'label'),
    );
  }
}

/// One communication goal for a profile.
class ProfileGoal {
  ProfileGoal({
    required this.id,
    required this.profileSyncKey,
    required this.title,
    this.notes = '',
    this.targetDate,
    this.achieved = false,
    this.achievedAt,
    required this.createdAt,
    required this.updatedAt,
    List<GoalComment>? comments,
    List<GoalLink>? links,
  }) : comments = comments ?? [],
       links = links ?? [];

  final String id;

  /// The profile this goal belongs to, by its stable cross-device
  /// syncKey (never a local profile id, which means nothing elsewhere).
  final String profileSyncKey;

  String title;

  /// Optional detail: what success looks like, who's working on it.
  String notes;

  /// The date the family hopes to reach this goal by (date only; the
  /// time component is ignored). Null = no target date.
  DateTime? targetDate;

  /// The checkbox: has this goal been achieved?
  bool achieved;

  /// When it was checked off. Null while not achieved.
  DateTime? achievedAt;

  final DateTime createdAt;

  /// Last mutation, ms precision. Sync merges are last-writer-wins by
  /// this timestamp per goal id (ties go to the remote side).
  DateTime updatedAt;

  /// Feedback from the care team, oldest first.
  final List<GoalComment> comments;

  /// Board items added to support this goal.
  final List<GoalLink> links;

  /// Days from [now] until the target date (negative when overdue).
  /// Null when there is no target date or the goal is achieved.
  int? daysLeft(DateTime now) {
    final t = targetDate;
    if (t == null || achieved) return null;
    final today = DateTime(now.year, now.month, now.day);
    final target = DateTime(t.year, t.month, t.day);
    return target.difference(today).inDays;
  }

  bool isOverdue(DateTime now) => (daysLeft(now) ?? 0) < 0;

  ProfileGoal copyWith({
    String? title,
    String? notes,
    DateTime? targetDate,
    bool clearTargetDate = false,
    bool? achieved,
    DateTime? achievedAt,
    bool clearAchievedAt = false,
    DateTime? updatedAt,
    List<GoalComment>? comments,
    List<GoalLink>? links,
  }) {
    return ProfileGoal(
      id: id,
      profileSyncKey: profileSyncKey,
      title: title ?? this.title,
      notes: notes ?? this.notes,
      targetDate: clearTargetDate ? null : (targetDate ?? this.targetDate),
      achieved: achieved ?? this.achieved,
      achievedAt: clearAchievedAt ? null : (achievedAt ?? this.achievedAt),
      createdAt: createdAt,
      updatedAt: updatedAt ?? this.updatedAt,
      comments: comments ?? List.of(this.comments),
      links: links ?? List.of(this.links),
    );
  }

  Map<String, dynamic> toJson() => {
    'id': id,
    'profileSyncKey': profileSyncKey,
    'title': title,
    'notes': notes,
    if (targetDate != null)
      'targetDate': DateTime(
        targetDate!.year,
        targetDate!.month,
        targetDate!.day,
      ).toIso8601String(),
    'achieved': achieved,
    if (achievedAt != null) 'achievedAt': achievedAt!.toIso8601String(),
    'createdAt': createdAt.toIso8601String(),
    'updatedAt': updatedAt.toIso8601String(),
    'comments': [for (final c in comments) c.toJson()],
    'links': [for (final l in links) l.toJson()],
  };

  factory ProfileGoal.fromJson(Map<String, dynamic> json) {
    final id = json['id'];
    final profileSyncKey = json['profileSyncKey'];
    final title = json['title'];
    if (id is! String || id.isEmpty) {
      throw const FormatException('ProfileGoal needs a String id.');
    }
    if (profileSyncKey is! String || profileSyncKey.isEmpty) {
      throw const FormatException('ProfileGoal needs a profileSyncKey.');
    }
    if (title is! String || title.isEmpty) {
      throw const FormatException('ProfileGoal needs a non-empty title.');
    }
    final comments = <GoalComment>[];
    final rawComments = json['comments'];
    if (rawComments is List) {
      for (final entry in rawComments) {
        if (entry is Map) {
          try {
            comments.add(
              GoalComment.fromJson(Map<String, dynamic>.from(entry)),
            );
          } on FormatException {
            // One bad comment is skipped; the goal survives.
          }
        }
      }
    }
    comments.sort((a, b) => a.createdAt.compareTo(b.createdAt));
    final links = <GoalLink>[];
    final rawLinks = json['links'];
    if (rawLinks is List) {
      for (final entry in rawLinks) {
        if (entry is Map) {
          try {
            links.add(GoalLink.fromJson(Map<String, dynamic>.from(entry)));
          } on FormatException {
            // One bad link is skipped; the goal survives.
          }
        }
      }
    }
    return ProfileGoal(
      id: id,
      profileSyncKey: profileSyncKey,
      title: title,
      notes: _str(json, 'notes'),
      targetDate: _dateOrNull(json['targetDate']),
      achieved: json['achieved'] == true,
      achievedAt: _dateOrNull(json['achievedAt']),
      createdAt: _date(json['createdAt']),
      updatedAt: _date(json['updatedAt']),
      comments: comments,
      links: links,
    );
  }

  /// Merges two goal lists by [id], last-writer-wins on [updatedAt]
  /// (ties go to [remote] so devices converge deterministically).
  /// Sorted for display: active goals first (soonest target date first,
  /// undated after), achieved goals last by achievement date.
  static List<ProfileGoal> merge(
    List<ProfileGoal> local,
    List<ProfileGoal> remote,
  ) {
    final byId = <String, ProfileGoal>{for (final g in local) g.id: g};
    for (final g in remote) {
      final existing = byId[g.id];
      if (existing == null || !g.updatedAt.isBefore(existing.updatedAt)) {
        byId[g.id] = g;
      }
    }
    return sortForDisplay(byId.values.toList());
  }

  static List<ProfileGoal> sortForDisplay(List<ProfileGoal> goals) {
    final sorted = List<ProfileGoal>.of(goals);
    sorted.sort((a, b) {
      if (a.achieved != b.achieved) return a.achieved ? 1 : -1;
      if (!a.achieved) {
        final ad = a.targetDate, bd = b.targetDate;
        if (ad != null && bd != null) {
          final c = ad.compareTo(bd);
          if (c != 0) return c;
        } else if (ad != null) {
          return -1;
        } else if (bd != null) {
          return 1;
        }
        return a.createdAt.compareTo(b.createdAt);
      }
      final aa = a.achievedAt ?? a.updatedAt, ba = b.achievedAt ?? b.updatedAt;
      return ba.compareTo(aa);
    });
    return sorted;
  }
}

String _str(Map<String, dynamic> json, String key, [String fallback = '']) =>
    json[key] is String ? json[key] as String : fallback;

DateTime _date(Object? v) =>
    v is String ? (DateTime.tryParse(v) ?? DateTime.now()) : DateTime.now();

DateTime? _dateOrNull(Object? v) =>
    v is String ? DateTime.tryParse(v) : null;
