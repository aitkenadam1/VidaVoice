/// Team access models: the people who work with the communicator
/// (therapists, doctors, teachers, family) and what each may do in the
/// family. Mirrors the worker's /v1/team contract; permissions are the
/// truth, roles are presets/labels.
library;

class TeamPermissions {
  const TeamPermissions({
    this.dashboard = false,
    this.content = false,
    this.profiles = false,
    this.safety = false,
    this.team = false,
  });

  final bool dashboard;
  final bool content;
  final bool profiles;
  final bool safety;
  final bool team;

  static const none = TeamPermissions();

  static const all = TeamPermissions(
    dashboard: true,
    content: true,
    profiles: true,
    safety: true,
    team: true,
  );

  factory TeamPermissions.fromJson(Map<String, dynamic> json) {
    return TeamPermissions(
      dashboard: json['dashboard'] == true,
      content: json['content'] == true,
      profiles: json['profiles'] == true,
      safety: json['safety'] == true,
      team: json['team'] == true,
    );
  }

  Map<String, dynamic> toJson() => {
    'dashboard': dashboard,
    'content': content,
    'profiles': profiles,
    'safety': safety,
    'team': team,
  };

  TeamPermissions copyWith({
    bool? dashboard,
    bool? content,
    bool? profiles,
    bool? safety,
    bool? team,
  }) {
    return TeamPermissions(
      dashboard: dashboard ?? this.dashboard,
      content: content ?? this.content,
      profiles: profiles ?? this.profiles,
      safety: safety ?? this.safety,
      team: team ?? this.team,
    );
  }

  /// True when the holder may change anything at all (i.e. not view-only).
  bool get canEditAnything =>
      dashboard || content || profiles || safety || team;

  /// Plain-language summary of the editing powers, for the roster and
  /// the invite email. View-only yields "view-only access".
  String describe() {
    final parts = <String>[];
    if (dashboard) parts.add('edit the communication board');
    if (content) parts.add('add and edit words and phrases');
    if (profiles) parts.add('manage profiles');
    if (safety) parts.add('manage safety contacts and safe zones');
    if (team) parts.add('invite and manage team members');
    if (parts.isEmpty) return 'view-only access';
    return 'can ${parts.join(', ')}';
  }

  @override
  bool operator ==(Object other) =>
      other is TeamPermissions &&
      other.dashboard == dashboard &&
      other.content == content &&
      other.profiles == profiles &&
      other.safety == safety &&
      other.team == team;

  @override
  int get hashCode => Object.hash(dashboard, content, profiles, safety, team);
}

/// The invite-time role presets (same values the server applies).
class TeamRoles {
  static const speechTherapist = 'speech_therapist';
  static const therapist = 'therapist';
  static const teacher = 'teacher';
  static const doctor = 'doctor';
  static const family = 'family';
  static const custom = 'custom';

  static const labels = <String, String>{
    speechTherapist: 'Speech therapist',
    therapist: 'Therapist',
    teacher: 'Teacher',
    doctor: 'Doctor',
    family: 'Family member',
    custom: 'Custom',
  };

  static const presets = <String, TeamPermissions>{
    speechTherapist: TeamPermissions(dashboard: true, content: true),
    therapist: TeamPermissions(dashboard: true, content: true),
    teacher: TeamPermissions(dashboard: true),
    doctor: TeamPermissions(),
    family: TeamPermissions(dashboard: true, content: true, profiles: true),
    custom: TeamPermissions(),
  };

  static String label(String role) => labels[role] ?? role;
}

class TeamMember {
  const TeamMember({
    required this.caregiverId,
    required this.email,
    required this.username,
    required this.role,
    required this.permissions,
    required this.isOwner,
    required this.createdAt,
  });

  final String caregiverId;
  final String? email;
  final String? username;
  final String role;
  final TeamPermissions permissions;
  final bool isOwner;
  final int createdAt;

  factory TeamMember.fromJson(Map<String, dynamic> json) {
    return TeamMember(
      caregiverId: json['caregiver_id']?.toString() ?? '',
      email: json['email']?.toString(),
      username: json['username']?.toString(),
      role: json['role']?.toString() ?? 'custom',
      permissions: json['permissions'] is Map
          ? TeamPermissions.fromJson(
              Map<String, dynamic>.from(json['permissions'] as Map),
            )
          : TeamPermissions.none,
      isOwner: json['is_owner'] == true,
      createdAt: (json['created_at'] as num?)?.toInt() ?? 0,
    );
  }

  String get displayName => username ?? email ?? 'Team member';
}

class TeamInvite {
  const TeamInvite({
    required this.id,
    required this.email,
    required this.role,
    required this.permissions,
    required this.status,
    required this.expiresAt,
    required this.createdAt,
  });

  final String id;
  final String email;
  final String role;
  final TeamPermissions permissions;
  final String status;
  final int expiresAt;
  final int createdAt;

  factory TeamInvite.fromJson(Map<String, dynamic> json) {
    return TeamInvite(
      id: json['id']?.toString() ?? '',
      email: json['email']?.toString() ?? '',
      role: json['role']?.toString() ?? 'custom',
      permissions: json['permissions'] is Map
          ? TeamPermissions.fromJson(
              Map<String, dynamic>.from(json['permissions'] as Map),
            )
          : TeamPermissions.none,
      status: json['status']?.toString() ?? 'pending',
      expiresAt: (json['expires_at'] as num?)?.toInt() ?? 0,
      createdAt: (json['created_at'] as num?)?.toInt() ?? 0,
    );
  }
}

/// The roster + the caller's own standing in the current family.
class TeamRoster {
  const TeamRoster({
    required this.familyId,
    required this.youCaregiverId,
    required this.youIsOwner,
    required this.youRole,
    required this.youPermissions,
    required this.owner,
    required this.members,
    required this.invites,
  });

  final String familyId;
  final String? youCaregiverId;
  final bool youIsOwner;
  final String? youRole;
  final TeamPermissions youPermissions;
  final TeamMember? owner;
  final List<TeamMember> members;
  final List<TeamInvite> invites;

  factory TeamRoster.fromJson(Map<String, dynamic> json) {
    final you = json['you'] is Map
        ? Map<String, dynamic>.from(json['you'] as Map)
        : const <String, dynamic>{};
    return TeamRoster(
      familyId: json['family_id']?.toString() ?? '',
      youCaregiverId: you['caregiver_id']?.toString(),
      youIsOwner: you['is_owner'] == true,
      youRole: you['role']?.toString(),
      youPermissions: you['permissions'] is Map
          ? TeamPermissions.fromJson(
              Map<String, dynamic>.from(you['permissions'] as Map),
            )
          : TeamPermissions.none,
      owner: json['owner'] is Map
          ? TeamMember.fromJson(Map<String, dynamic>.from(json['owner'] as Map))
          : null,
      members: json['members'] is List
          ? (json['members'] as List)
                .whereType<Map>()
                .map((m) => TeamMember.fromJson(Map<String, dynamic>.from(m)))
                .toList()
          : const [],
      invites: json['invites'] is List
          ? (json['invites'] as List)
                .whereType<Map>()
                .map((m) => TeamInvite.fromJson(Map<String, dynamic>.from(m)))
                .toList()
          : const [],
    );
  }
}

/// One family the signed-in account can enter (home or joined).
class TeamFamily {
  const TeamFamily({
    required this.familyId,
    required this.role,
    required this.isOwner,
    required this.permissions,
    required this.isCurrent,
  });

  final String familyId;
  final String role;
  final bool isOwner;
  final TeamPermissions permissions;
  final bool isCurrent;

  factory TeamFamily.fromJson(Map<String, dynamic> json) {
    return TeamFamily(
      familyId: json['family_id']?.toString() ?? '',
      role: json['role']?.toString() ?? 'custom',
      isOwner: json['is_owner'] == true,
      permissions: json['permissions'] is Map
          ? TeamPermissions.fromJson(
              Map<String, dynamic>.from(json['permissions'] as Map),
            )
          : TeamPermissions.none,
      isCurrent: json['is_current'] == true,
    );
  }
}

/// The result of accepting an invite or entering a family: a fresh
/// family-scoped session plus the wrapped sync key (when the owner
/// shared it with the invite).
class TeamEntry {
  const TeamEntry({
    required this.familyId,
    required this.token,
    required this.expiresAt,
    required this.profileIds,
    required this.role,
    required this.isOwner,
    required this.permissions,
    this.wrappedKey,
    this.wrapSalt,
  });

  final String familyId;
  final String token;
  final int expiresAt;
  final List<String> profileIds;
  final String role;
  final bool isOwner;
  final TeamPermissions permissions;

  /// Family sync key wrapped for the invitee (base64 ciphertext), and
  /// its AES-GCM nonce (carried in the wrap_salt field). Opaque pair.
  final String? wrappedKey;
  final String? wrapSalt;

  factory TeamEntry.fromJson(Map<String, dynamic> json) {
    final ids = json['profile_ids'];
    return TeamEntry(
      familyId: json['family_id']?.toString() ?? '',
      token: json['token']?.toString() ?? '',
      expiresAt: (json['expires_at'] as num?)?.toInt() ?? 0,
      profileIds: ids is List
          ? ids.map((e) => e.toString()).toList()
          : const [],
      role: json['role']?.toString() ?? 'custom',
      isOwner: json['is_owner'] == true,
      permissions: json['permissions'] is Map
          ? TeamPermissions.fromJson(
              Map<String, dynamic>.from(json['permissions'] as Map),
            )
          : TeamPermissions.none,
      wrappedKey: json['wrapped_key']?.toString(),
      wrapSalt: json['wrap_salt']?.toString(),
    );
  }
}

/// What an invite creation returns to the owner's app. When the app
/// generated the token itself (for key wrapping), the server echoes
/// neither the token nor the URL — the app already has both.
class InviteCreated {
  const InviteCreated({
    required this.invite,
    this.inviteToken,
    this.inviteUrl,
    this.emailStatus = 'link_only',
  });

  final TeamInvite invite;
  final String? inviteToken;
  final String? inviteUrl;

  /// 'sent' when the server emailed the invitation (Resend); anything
  /// else means the caregiver should share the link themselves.
  final String emailStatus;

  bool get emailed => emailStatus == 'sent';

  factory InviteCreated.fromJson(Map<String, dynamic> json) {
    return InviteCreated(
      invite: json['invite'] is Map
          ? TeamInvite.fromJson(
              Map<String, dynamic>.from(json['invite'] as Map),
            )
          : const TeamInvite(
              id: '',
              email: '',
              role: 'custom',
              permissions: TeamPermissions.none,
              status: 'pending',
              expiresAt: 0,
              createdAt: 0,
            ),
      inviteToken: json['invite_token']?.toString(),
      inviteUrl: json['invite_url']?.toString(),
      emailStatus: json['email_status']?.toString() ?? 'link_only',
    );
  }
}
