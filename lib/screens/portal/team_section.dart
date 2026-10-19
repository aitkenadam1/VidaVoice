import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';

import '../../models/team.dart';
import '../../services/proxy_client.dart';
import '../../state/session_state.dart';
import 'portal_section.dart';

/// The invite email a caregiver sends a new team member. The system
/// doesn't send email yet — creating an invite produces this message
/// with a one-time link the caregiver shares themselves. Copy approved
/// by Adam before any automated sending is connected.
({String subject, String body}) inviteEmailDraft({
  required String roleLabel,
  required TeamPermissions permissions,
  String link = '[invite link]',
}) {
  final access = permissions.describe();
  final accessSentence = permissions.canEditAnything
      ? 'you will have $access.'
      : 'you will have view-only access.';
  return (
    subject: "You've been invited to join a care team on OneVoz",
    body:
        'Hello,\n\n'
        "You've been invited to join a family's care team on OneVoz — the "
        'free communication app from VidaCare that gives nonverbal children '
        'and adults a voice.\n\n'
        'As a $roleLabel, $accessSentence\n\n'
        'To accept:\n'
        '1. Create your free OneVoz account using this email address.\n'
        '2. Open this invite link: $link\n\n'
        'The link works for 7 days and can only be used with this email '
        'address.\n\n'
        "If you weren't expecting this invitation, you can simply ignore "
        'this message.\n\n'
        '— VidaCare\n'
        'One voice. A brighter tomorrow.',
  );
}

String _fmtDate(int ms) {
  final d = DateTime.fromMillisecondsSinceEpoch(ms).toLocal();
  return '${d.month}/${d.day}/${d.year}';
}

/// Five permission switches with plain-language descriptions.
class PermissionToggles extends StatelessWidget {
  const PermissionToggles({
    super.key,
    required this.value,
    required this.onChanged,
  });

  final TeamPermissions value;
  final ValueChanged<TeamPermissions> onChanged;

  @override
  Widget build(BuildContext context) {
    Widget toggle(
      String title,
      String subtitle,
      bool v,
      ValueChanged<bool> set,
    ) {
      return SwitchListTile(
        contentPadding: EdgeInsets.zero,
        title: Text(title),
        subtitle: Text(subtitle),
        value: v,
        onChanged: set,
      );
    }

    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        toggle(
          'Edit communication board',
          'Change the home board and personal dashboard.',
          value.dashboard,
          (v) => onChanged(value.copyWith(dashboard: v)),
        ),
        toggle(
          'Add & edit words and phrases',
          'Custom words, phrases, and vocabulary level.',
          value.content,
          (v) => onChanged(value.copyWith(content: v)),
        ),
        toggle(
          'Manage profiles',
          'Add profiles and change communication modes.',
          value.profiles,
          (v) => onChanged(value.copyWith(profiles: v)),
        ),
        toggle(
          'Manage safety',
          'Emergency contacts and safe zones.',
          value.safety,
          (v) => onChanged(value.copyWith(safety: v)),
        ),
        toggle(
          'Manage team',
          'Invite people and revoke invites.',
          value.team,
          (v) => onChanged(value.copyWith(team: v)),
        ),
      ],
    );
  }
}

/// Portal "Care team" section (Profiles tab): roster, pending invites,
/// invite creation with email preview, permission editing, removal.
class TeamSection extends StatefulWidget {
  const TeamSection({super.key});

  @override
  State<TeamSection> createState() => _TeamSectionState();
}

class _TeamSectionState extends State<TeamSection> {
  @override
  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    // didChangeDependencies (not just initState): it re-fires when the
    // session instance is swapped, so the roster loads for the new
    // session too instead of spinning on the old one's absence.
    final session = context.read<SessionState>();
    if (session.proxySignedIn && !session.teamLoadAttempted) {
      session.loadTeam();
    }
  }

  void _snack(String message) {
    if (!mounted) return;
    ScaffoldMessenger.of(context)
        .showSnackBar(SnackBar(content: Text(message)));
  }

  Future<void> _copyLink(String link) async {
    await Clipboard.setData(ClipboardData(text: link));
    _snack('Invite link copied — send it to the person you invited.');
  }

  Future<void> _inviteDialog(SessionState session) async {
    final emailController = TextEditingController();
    var role = TeamRoles.speechTherapist;
    var permissions = TeamRoles.presets[role]!;
    final result = await showDialog<bool>(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setLocal) => AlertDialog(
          title: const Text('Invite to the care team'),
          content: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                TextField(
                  controller: emailController,
                  keyboardType: TextInputType.emailAddress,
                  autocorrect: false,
                  decoration: const InputDecoration(
                    labelText: 'Email address',
                    border: OutlineInputBorder(),
                  ),
                ),
                const SizedBox(height: 12),
                DropdownButtonFormField<String>(
                  initialValue: role,
                  decoration: const InputDecoration(
                    labelText: 'Role',
                    border: OutlineInputBorder(),
                  ),
                  items: [
                    for (final entry in TeamRoles.labels.entries)
                      DropdownMenuItem(
                        value: entry.key,
                        child: Text(entry.value),
                      ),
                  ],
                  onChanged: (v) {
                    if (v == null) return;
                    setLocal(() {
                      role = v;
                      permissions = TeamRoles.presets[v]!;
                    });
                  },
                ),
                const SizedBox(height: 8),
                PermissionToggles(
                  value: permissions,
                  onChanged: (p) => setLocal(() => permissions = p),
                ),
              ],
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(ctx).pop(false),
              child: const Text('Cancel'),
            ),
            TextButton(
              onPressed: () {
                final draft = inviteEmailDraft(
                  roleLabel: TeamRoles.label(role),
                  permissions: permissions,
                );
                showDialog(
                  context: ctx,
                  builder: (inner) => AlertDialog(
                    title: const Text('Invite email preview'),
                    content: SingleChildScrollView(
                      child: SelectableText(
                        'Subject: ${draft.subject}\n\n${draft.body}',
                      ),
                    ),
                    actions: [
                      TextButton(
                        onPressed: () => Navigator.of(inner).pop(),
                        child: const Text('Back'),
                      ),
                    ],
                  ),
                );
              },
              child: const Text('Preview email'),
            ),
            FilledButton(
              onPressed: () => Navigator.of(ctx).pop(true),
              child: const Text('Create invite'),
            ),
          ],
        ),
      ),
    );
    if (result != true || !mounted) return;
    final email = emailController.text.trim();
    if (email.isEmpty || !email.contains('@')) {
      _snack('Enter a valid email address first.');
      return;
    }
    try {
      final outcome = await session.createTeamInvite(
        email: email,
        role: role,
        permissions: permissions,
      );
      if (!mounted) return;
      await showDialog(
        context: context,
        builder: (ctx) => AlertDialog(
          title: const Text('Invite ready'),
          content: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Send this link to $email. Email sending isn\u2019t '
                  'connected yet, so share it yourself for now — the link '
                  'only works with their email address and expires in 7 '
                  'days.',
                ),
                const SizedBox(height: 12),
                SelectableText(outcome.link),
                const SizedBox(height: 12),
                const Text(
                  'This link is shown only once. If you lose it, revoke '
                  'the invite below and create a new one.',
                  style: TextStyle(fontSize: 12),
                ),
              ],
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(ctx).pop(),
              child: const Text('Done'),
            ),
            FilledButton.icon(
              icon: const Icon(Icons.copy, size: 18),
              label: const Text('Copy link'),
              onPressed: () {
                Navigator.of(ctx).pop();
                _copyLink(outcome.link);
              },
            ),
          ],
        ),
      );
    } on ProxyException catch (e) {
      _snack(e.message);
    } catch (_) {
      _snack('Could not create the invite. Check your connection and retry.');
    }
  }

  Future<void> _editMemberDialog(
    SessionState session,
    TeamMember member,
  ) async {
    var permissions = member.permissions;
    var role = member.role;
    final saved = await showDialog<bool>(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setLocal) => AlertDialog(
          title: Text(member.email ?? member.displayName),
          content: SingleChildScrollView(
            child: PermissionToggles(
              value: permissions,
              onChanged: (p) => setLocal(() {
                permissions = p;
                role = TeamRoles.custom;
              }),
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(ctx).pop(false),
              child: const Text('Cancel'),
            ),
            FilledButton(
              onPressed: () => Navigator.of(ctx).pop(true),
              child: const Text('Save'),
            ),
          ],
        ),
      ),
    );
    if (saved != true || !mounted) return;
    try {
      await session.updateTeamMember(
        member.caregiverId,
        role: role,
        permissions: permissions,
      );
      _snack('Permissions updated.');
    } on ProxyException catch (e) {
      _snack(e.message);
    }
  }

  Future<void> _removeMember(SessionState session, TeamMember member) async {
    final confirm = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text('Remove ${member.email ?? 'this member'}?'),
        content: const Text(
          'They lose access to this family right away. Their own account '
          'and their own family are not affected.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(ctx).pop(true),
            child: const Text('Remove'),
          ),
        ],
      ),
    );
    if (confirm != true || !mounted) return;
    try {
      await session.removeTeamMember(member.caregiverId);
      _snack('Team member removed.');
    } on ProxyException catch (e) {
      _snack(e.message);
    }
  }

  Future<void> _leaveFamily(SessionState session) async {
    final confirm = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Leave this family?'),
        content: const Text(
          'You will lose access to this family\u2019s boards and team. '
          'You can be invited again later.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(ctx).pop(true),
            child: const Text('Leave'),
          ),
        ],
      ),
    );
    if (confirm != true || !mounted) return;
    final myId = session.teamRoster?.youCaregiverId;
    final home = session.accountHomeFamilyId;
    if (myId == null || home == null) return;
    try {
      await session.removeTeamMember(myId);
      await session.switchToFamily(home);
      _snack('You left the family.');
    } on ProxyException catch (e) {
      _snack(e.message);
    }
  }

  @override
  Widget build(BuildContext context) {
    final session = context.watch<SessionState>();
    final roster = session.teamRoster;
    return PortalSection(
      title: 'Care team',
      icon: Icons.groups_outlined,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            'The people who work with your communicator — therapists, '
            'teachers, doctors, family. Each person joins with their own '
            'free account and only the access you choose.',
          ),
          const SizedBox(height: 8),
          if (!session.proxySignedIn)
            const Text('Sign in to manage your care team.')
          else if (roster == null && session.teamLoadFailed)
            Row(
              children: [
                const Icon(Icons.cloud_off_outlined, size: 18),
                const SizedBox(width: 8),
                const Expanded(
                  child: Text(
                    'Couldn\u2019t load your care team. Check your '
                    'connection and retry.',
                  ),
                ),
                TextButton(
                  onPressed: () => session.loadTeam(),
                  child: const Text('Retry'),
                ),
              ],
            )
          else if (roster == null)
            Row(
              children: [
                const SizedBox(
                  width: 16,
                  height: 16,
                  child: CircularProgressIndicator(strokeWidth: 2),
                ),
                const SizedBox(width: 8),
                const Text('Loading your care team…'),
                const Spacer(),
                TextButton(
                  onPressed: () => session.loadTeam(),
                  child: const Text('Retry'),
                ),
              ],
            )
          else ...[
            // Your own standing.
            ListTile(
              contentPadding: EdgeInsets.zero,
              leading: const Icon(Icons.person_outline),
              title: Text(
                roster.youIsOwner
                    ? 'You — family owner'
                    : 'You — ${TeamRoles.label(roster.youRole ?? 'custom')}',
              ),
              subtitle: Text(
                roster.youIsOwner
                    ? 'Full access to everything in this family.'
                    : 'Your access: ${roster.youPermissions.describe()}.',
              ),
            ),
            if (session.inJoinedFamily && !session.syncKeyShared)
              const Padding(
                padding: EdgeInsets.only(bottom: 8),
                child: Text(
                  'Board sync isn\u2019t shared with your account yet — '
                  'ask the family owner to send you a fresh invite link.',
                  style: TextStyle(color: Colors.orange),
                ),
              ),
            if (roster.owner != null && !roster.youIsOwner)
              ListTile(
                contentPadding: EdgeInsets.zero,
                leading: const Icon(Icons.star_outline),
                title: Text(roster.owner!.email ?? 'Family owner'),
                subtitle: const Text('Family owner'),
              ),
            for (final member in roster.members)
              ListTile(
                contentPadding: EdgeInsets.zero,
                leading: const Icon(Icons.person_outline),
                title: Text(member.email ?? member.displayName),
                subtitle: Text(
                  '${TeamRoles.label(member.role)} — '
                  '${member.permissions.describe()}',
                ),
                trailing: roster.youIsOwner
                    ? Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          IconButton(
                            tooltip: 'Edit permissions',
                            icon: const Icon(Icons.tune),
                            onPressed: () => _editMemberDialog(session, member),
                          ),
                          IconButton(
                            tooltip: 'Remove from team',
                            icon: const Icon(Icons.person_remove_outlined),
                            onPressed: () => _removeMember(session, member),
                          ),
                        ],
                      )
                    : null,
              ),
            if (roster.invites.isNotEmpty) ...[
              const Divider(),
              const Text(
                'Pending invites',
                style: TextStyle(fontWeight: FontWeight.bold),
              ),
              for (final invite in roster.invites)
                ListTile(
                  contentPadding: EdgeInsets.zero,
                  leading: const Icon(Icons.mail_outline),
                  title: Text(invite.email),
                  subtitle: Text(
                    '${TeamRoles.label(invite.role)} — expires '
                    '${_fmtDate(invite.expiresAt)}. The link was shown '
                    'when the invite was created.',
                  ),
                  trailing: session.canManageTeam
                      ? TextButton(
                          onPressed: () async {
                            try {
                              await session.revokeTeamInvite(invite.id);
                              _snack('Invite revoked.');
                            } on ProxyException catch (e) {
                              _snack(e.message);
                            }
                          },
                          child: const Text('Revoke'),
                        )
                      : null,
                ),
            ],
            const SizedBox(height: 8),
            Wrap(
              spacing: 8,
              children: [
                if (session.canManageTeam)
                  FilledButton.icon(
                    icon: const Icon(Icons.person_add_alt_1, size: 18),
                    label: const Text('Invite someone'),
                    onPressed: () => _inviteDialog(session),
                  ),
                if (session.inJoinedFamily)
                  OutlinedButton.icon(
                    icon: const Icon(Icons.exit_to_app, size: 18),
                    label: const Text('Leave this family'),
                    onPressed: () => _leaveFamily(session),
                  ),
              ],
            ),
          ],
        ],
      ),
    );
  }
}

/// Account-tab card: the families this account can enter, switching
/// between them, and joining a new one with an invite link.
class FamiliesCard extends StatefulWidget {
  const FamiliesCard({super.key});

  @override
  State<FamiliesCard> createState() => _FamiliesCardState();
}

class _FamiliesCardState extends State<FamiliesCard> {
  bool _busy = false;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final session = context.read<SessionState>();
    if (session.proxySignedIn && !session.teamLoadAttempted) {
      session.loadTeam();
    }
  }

  void _snack(String message) {
    if (!mounted) return;
    ScaffoldMessenger.of(context)
        .showSnackBar(SnackBar(content: Text(message)));
  }

  Future<void> _joinDialog(SessionState session) async {
    final controller = TextEditingController();
    final link = await showDialog<String>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Join a family'),
        content: TextField(
          controller: controller,
          autocorrect: false,
          decoration: const InputDecoration(
            labelText: 'Invite link',
            hintText: 'https://onevoz.me/join#invite=…',
            border: OutlineInputBorder(),
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(ctx).pop(controller.text),
            child: const Text('Join'),
          ),
        ],
      ),
    );
    if (link == null || link.trim().isEmpty || !mounted) return;
    setState(() => _busy = true);
    try {
      await session.acceptInvite(link);
      _snack('Welcome — you joined the family\u2019s care team.');
    } on ProxyException catch (e) {
      _snack(e.message);
    } catch (_) {
      _snack('Could not accept that invite. Check the link and retry.');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final session = context.watch<SessionState>();
    if (!session.proxySignedIn) return const SizedBox.shrink();
    final families = session.myFamilies;
    return Card(
      margin: EdgeInsets.zero,
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Row(
              children: [
                Icon(Icons.groups_outlined, size: 20),
                SizedBox(width: 8),
                Text(
                  'Your families',
                  style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
                ),
              ],
            ),
            const SizedBox(height: 8),
            if (families.isEmpty && session.teamLoadFailed)
              Row(
                children: [
                  const Expanded(
                    child: Text('Couldn\u2019t load your families.'),
                  ),
                  TextButton(
                    onPressed: () => session.loadTeam(),
                    child: const Text('Retry'),
                  ),
                ],
              )
            else if (families.isEmpty)
              const Text('Loading your families…')
            else
              for (final family in families)
                ListTile(
                  contentPadding: EdgeInsets.zero,
                  leading: Icon(
                    family.isOwner ? Icons.star_outline : Icons.person_outline,
                  ),
                  title: Text(
                    family.isOwner
                        ? 'Your family'
                        : 'Care team — ${TeamRoles.label(family.role)}',
                  ),
                  subtitle: Text(
                    family.isOwner
                        ? 'You own this family.'
                        : 'Access: ${family.permissions.describe()}.',
                  ),
                  trailing: family.isCurrent
                      ? const Chip(label: Text('Current'))
                      : TextButton(
                          onPressed: _busy
                              ? null
                              : () async {
                                  setState(() => _busy = true);
                                  try {
                                    await session.switchToFamily(
                                      family.familyId,
                                    );
                                    _snack('Switched family.');
                                  } on ProxyException catch (e) {
                                    _snack(e.message);
                                  } finally {
                                    if (mounted) {
                                      setState(() => _busy = false);
                                    }
                                  }
                                },
                          child: const Text('Switch'),
                        ),
                ),
            const SizedBox(height: 4),
            if (session.pendingInviteToken != null) ...[
              FilledButton.icon(
                icon: const Icon(Icons.mail_outline, size: 18),
                label: const Text('Join the family that invited you'),
                onPressed: _busy
                    ? null
                    : () async {
                        setState(() => _busy = true);
                        final outcome = await session.acceptPendingInvite();
                        if (mounted) {
                          setState(() => _busy = false);
                          if (outcome != null) _snack(outcome);
                        }
                      },
              ),
              const SizedBox(height: 8),
            ],
            OutlinedButton.icon(
              icon: const Icon(Icons.link, size: 18),
              label: const Text('Join a family with an invite link'),
              onPressed: _busy ? null : () => _joinDialog(session),
            ),
          ],
        ),
      ),
    );
  }
}
