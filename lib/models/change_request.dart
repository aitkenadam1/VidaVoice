/// Care-team change requests: in a joined family, a member who is not
/// an admin (the owner, or a member holding the manage-team permission)
/// no longer changes family data directly. Their edits are captured as
/// change requests that an admin approves or rejects — a rejection can
/// carry a note the requester sees, so they know why.
///
/// Requests ride the family's end-to-end encrypted sync blob exactly
/// like goals (see DashboardSyncService): the server only ever stores
/// ciphertext. A request's [payload] is a fragment of the sync payload
/// shapes (profile entries, dashboards, goals, safe zones, tombstones,
/// plus admin-local extras like profile deletes), so approving replays
/// it through the very merge a remote sync would use.
library;

/// One proposed change to family data, awaiting (or having received)
/// an admin's decision.
class ChangeRequest {
  const ChangeRequest({
    required this.id,
    required this.authorMemberId,
    required this.authorName,
    required this.createdAt,
    required this.kind,
    required this.summary,
    required this.payload,
    this.status = statusPending,
    this.decidedByName,
    this.decidedAt,
    this.reviewerNote,
  });

  static const statusPending = 'pending';
  static const statusApproved = 'approved';
  static const statusRejected = 'rejected';

  final String id;

  /// The requesting member's caregiver id (TeamRoster.youCaregiverId on
  /// their device). Empty only for requests written before the roster
  /// was loaded — matching for "my requests" is by this id.
  final String authorMemberId;

  /// Display name snapshot of the requester inside the family.
  final String authorName;

  /// When the request was made (ms-precision timestamp).
  final DateTime createdAt;

  /// Machine kind of the change: 'dashboard_cell', 'dashboard',
  /// 'profile', 'profile_add', 'profile_remove', 'goal', 'goal_comment',
  /// 'safe_zone', 'vocab_level', … Used for icons/grouping; the payload
  /// is the source of truth for what approval replays.
  final String kind;

  /// Plain-language one-liner for the admin inbox and the requester's
  /// own list, e.g. "Add the word 'more' to Emma's board".
  final String summary;

  /// Entity operations in sync-payload shapes. Keys (all optional):
  /// 'profiles' (list of synced profile entries), 'profileDeletes'
  /// (list of profile syncKeys), 'dashboards' (syncKey → dashboard
  /// JSON), 'goals' (list of goal JSON), 'goal_tombstones',
  /// 'safe_zones', 'safe_zone_tombstones' (tombstones are
  /// {id, deleted_ts} maps), and 'vocabLevel' (int).
  final Map<String, dynamic> payload;

  /// [statusPending], [statusApproved], or [statusRejected].
  final String status;

  /// Display name of the admin who decided, once decided.
  final String? decidedByName;

  /// When the decision was made. Null while pending.
  final DateTime? decidedAt;

  /// The admin's optional note on the decision — the rejection reason
  /// the requester asked to see. Null when no note was left.
  final String? reviewerNote;

  bool get isPending => status == statusPending;
  bool get isDecided => !isPending;

  ChangeRequest copyWith({
    String? status,
    String? decidedByName,
    DateTime? decidedAt,
    String? reviewerNote,
  }) {
    return ChangeRequest(
      id: id,
      authorMemberId: authorMemberId,
      authorName: authorName,
      createdAt: createdAt,
      kind: kind,
      summary: summary,
      payload: payload,
      status: status ?? this.status,
      decidedByName: decidedByName ?? this.decidedByName,
      decidedAt: decidedAt ?? this.decidedAt,
      reviewerNote: reviewerNote ?? this.reviewerNote,
    );
  }

  Map<String, dynamic> toJson() => {
    'id': id,
    'authorMemberId': authorMemberId,
    'authorName': authorName,
    'createdAt': createdAt.millisecondsSinceEpoch,
    'kind': kind,
    'summary': summary,
    'payload': payload,
    'status': status,
    if (decidedByName != null) 'decidedByName': decidedByName,
    if (decidedAt != null) 'decidedAt': decidedAt!.millisecondsSinceEpoch,
    if (reviewerNote != null) 'reviewerNote': reviewerNote,
  };

  factory ChangeRequest.fromJson(Map<String, dynamic> json) {
    final id = json['id'];
    if (id is! String || id.isEmpty) {
      throw const FormatException('ChangeRequest needs a String id.');
    }
    final payloadRaw = json['payload'];
    final statusRaw = json['status'];
    return ChangeRequest(
      id: id,
      authorMemberId: _str(json, 'authorMemberId'),
      authorName: _str(json, 'authorName', 'Team member'),
      createdAt: _msDate(json['createdAt']),
      kind: _str(json, 'kind', 'change'),
      summary: _str(json, 'summary'),
      payload: payloadRaw is Map
          ? Map<String, dynamic>.from(payloadRaw)
          : const {},
      status:
          (statusRaw == statusApproved || statusRaw == statusRejected)
          ? statusRaw as String
          : statusPending,
      decidedByName: _strOrNull(json, 'decidedByName'),
      decidedAt: json['decidedAt'] == null
          ? null
          : _msDate(json['decidedAt']),
      reviewerNote: _strOrNull(json, 'reviewerNote'),
    );
  }

  /// Union-merges two request lists by [id]: a request present on
  /// either side survives — a merge must never drop a proposal another
  /// device made. When both sides hold the same id, a decided copy
  /// beats a pending one (a decision is never un-made by a stale
  /// device still holding the pending copy), and between two decided
  /// copies the later [decidedAt] wins (ties go to [remote], matching
  /// the goal/zone merge policy).
  ///
  /// Result order: pending first by creation (the admin's work queue),
  /// then decided by decision time, newest first (history).
  static List<ChangeRequest> merge(
    List<ChangeRequest> local,
    List<ChangeRequest> remote,
  ) {
    final byId = <String, ChangeRequest>{for (final r in local) r.id: r};
    for (final r in remote) {
      final existing = byId[r.id];
      if (existing == null || _winsRemote(r, existing)) {
        byId[r.id] = r;
      }
    }
    return sortForDisplay(byId.values.toList());
  }

  static bool _winsRemote(ChangeRequest remote, ChangeRequest local) {
    if (remote.isDecided != local.isDecided) return remote.isDecided;
    if (remote.isDecided) {
      final rd = remote.decidedAt?.millisecondsSinceEpoch ?? 0;
      final ld = local.decidedAt?.millisecondsSinceEpoch ?? 0;
      return rd >= ld;
    }
    // Two pending copies of one request are the same proposal (payloads
    // are immutable once written); take remote for determinism.
    return true;
  }

  static List<ChangeRequest> sortForDisplay(List<ChangeRequest> requests) {
    final sorted = List<ChangeRequest>.of(requests);
    sorted.sort((a, b) {
      if (a.isPending != b.isPending) return a.isPending ? -1 : 1;
      if (a.isPending) return a.createdAt.compareTo(b.createdAt);
      final ad = a.decidedAt ?? a.createdAt, bd = b.decidedAt ?? b.createdAt;
      return bd.compareTo(ad);
    });
    return sorted;
  }
}

String _str(Map<String, dynamic> json, String key, [String fallback = '']) =>
    json[key] is String ? json[key] as String : fallback;

String? _strOrNull(Map<String, dynamic> json, String key) =>
    json[key] is String && (json[key] as String).isNotEmpty
    ? json[key] as String
    : null;

DateTime _msDate(Object? v) {
  if (v is int) return DateTime.fromMillisecondsSinceEpoch(v);
  if (v is num) return DateTime.fromMillisecondsSinceEpoch(v.toInt());
  if (v is String) {
    return DateTime.tryParse(v) ??
        DateTime.fromMillisecondsSinceEpoch(int.tryParse(v) ?? 0);
  }
  return DateTime.fromMillisecondsSinceEpoch(0);
}
