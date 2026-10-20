import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../models/change_request.dart';
import '../../state/session_state.dart';
import 'portal_section.dart';

/// Portal "Change requests" section (Profiles tab, above Care team).
///
/// In a joined family, members who aren't admins propose changes
/// instead of enacting them. Admins (the owner, and members with the
/// manage-team permission) get the inbox here: what was asked, by
/// whom, the detail of what would change, and Approve / Reject —
/// rejecting offers an optional note so the requester knows why.
/// Non-admin members see their own requests and their status.
///
/// Renders nothing for solo families and owner sessions whose family
/// has no other members — there is nobody to propose or decide.
class ChangeRequestsSection extends StatelessWidget {
  const ChangeRequestsSection({super.key});

  @override
  Widget build(BuildContext context) {
    final session = context.watch<SessionState>();
    final roster = session.teamRoster;
    final familyHasOthers =
        roster != null &&
        (roster.members.isNotEmpty || roster.invites.isNotEmpty);
    final visible =
        session.inJoinedFamily || (session.isFamilyOwner && familyHasOthers);
    if (!visible) return const SizedBox.shrink();
    return PortalSection(
      title: 'Change requests',
      icon: Icons.fact_check_outlined,
      child: session.isTeamAdmin
          ? _AdminInbox(session: session)
          : _MyRequests(session: session),
    );
  }
}

// ------------------------------------------------------------ admin inbox ---

class _AdminInbox extends StatelessWidget {
  const _AdminInbox({required this.session});

  final SessionState session;

  @override
  Widget build(BuildContext context) {
    final pending = session.pendingChangeRequests;
    final decided = session.decidedChangeRequests;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text(
          'Changes your care team asked to make. Nothing here takes '
          'effect unless you approve it.',
        ),
        const SizedBox(height: 8),
        if (pending.isEmpty)
          const Text(
            'No changes waiting for review.',
            style: TextStyle(fontStyle: FontStyle.italic),
          ),
        for (final request in pending)
          _PendingRequestTile(session: session, request: request),
        if (decided.isNotEmpty) ...[
          const SizedBox(height: 8),
          ExpansionTile(
            tilePadding: EdgeInsets.zero,
            title: Text('Decided (${decided.length})'),
            children: [
              for (final request in decided)
                _DecidedTile(session: session, request: request),
            ],
          ),
        ],
      ],
    );
  }
}

class _PendingRequestTile extends StatelessWidget {
  const _PendingRequestTile({required this.session, required this.request});

  final SessionState session;
  final ChangeRequest request;

  @override
  Widget build(BuildContext context) {
    final detail = changeRequestDetailLines(session, request);
    return Card(
      margin: const EdgeInsets.only(bottom: 8),
      child: ExpansionTile(
        tilePadding: const EdgeInsets.symmetric(horizontal: 12),
        title: Text(request.summary),
        subtitle: Text(
          '${request.authorName} · ${_relativeTime(request.createdAt)}',
        ),
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                for (final line in detail)
                  Padding(
                    padding: const EdgeInsets.only(bottom: 4),
                    child: Text('• $line'),
                  ),
                const SizedBox(height: 8),
                Row(
                  mainAxisAlignment: MainAxisAlignment.end,
                  children: [
                    TextButton(
                      onPressed: () => _reject(context),
                      child: const Text('Reject'),
                    ),
                    const SizedBox(width: 8),
                    FilledButton(
                      onPressed: () =>
                          session.approveChangeRequest(request.id),
                      child: const Text('Approve'),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Future<void> _reject(BuildContext context) async {
    final controller = TextEditingController();
    final note = await showDialog<String>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Reject this change?'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(request.summary),
            const SizedBox(height: 12),
            TextField(
              controller: controller,
              autofocus: true,
              maxLines: 3,
              decoration: const InputDecoration(
                labelText: 'Let them know why (optional)',
                border: OutlineInputBorder(),
              ),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(ctx).pop(controller.text),
            child: const Text('Reject'),
          ),
        ],
      ),
    );
    if (note == null) return;
    await session.rejectChangeRequest(request.id, note: note);
  }
}

// --------------------------------------------------------- requester view ---

class _MyRequests extends StatelessWidget {
  const _MyRequests({required this.session});

  final SessionState session;

  @override
  Widget build(BuildContext context) {
    final mine = session.myChangeRequests;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text(
          'Changes you asked an admin to approve. They take effect '
          'only when an admin approves them.',
        ),
        const SizedBox(height: 8),
        if (mine.isEmpty)
          const Text(
            'You haven\u2019t sent any changes for approval.',
            style: TextStyle(fontStyle: FontStyle.italic),
          ),
        for (final request in mine) _DecidedTile(session: session, request: request),
      ],
    );
  }
}

/// One request row for history/requester lists: summary, status chip,
/// who decided, and the reviewer's note when there is one.
class _DecidedTile extends StatelessWidget {
  const _DecidedTile({required this.session, required this.request});

  final SessionState session;
  final ChangeRequest request;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final (chipLabel, chipColor) = switch (request.status) {
      ChangeRequest.statusApproved => ('Approved', Colors.green),
      ChangeRequest.statusRejected => ('Rejected', scheme.error),
      _ => ('Pending', Colors.orange),
    };
    return ListTile(
      contentPadding: EdgeInsets.zero,
      title: Text(request.summary),
      subtitle: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            request.isPending
                ? '${request.authorName} · '
                      '${_relativeTime(request.createdAt)}'
                : '${request.status == ChangeRequest.statusApproved ? 'Approved' : 'Rejected'}'
                      ' by ${request.decidedByName ?? 'an admin'} · '
                      '${_relativeTime(request.decidedAt ?? request.createdAt)}',
          ),
          if (request.reviewerNote != null)
            Text(
              'Note from ${request.decidedByName ?? 'the admin'}: '
              '"${request.reviewerNote}"',
              style: const TextStyle(fontStyle: FontStyle.italic),
            ),
        ],
      ),
      trailing: Chip(
        label: Text(chipLabel),
        labelStyle: TextStyle(color: chipColor, fontSize: 12),
        side: BorderSide(color: chipColor),
        visualDensity: VisualDensity.compact,
      ),
    );
  }
}

// ---------------------------------------------------------------- detail ---

/// Plain-language detail lines for what approving [request] would do,
/// derived from its payload. Best-effort by design: a line that can't
/// be derived is skipped, never a crash — the summary always shows.
List<String> changeRequestDetailLines(
  SessionState session,
  ChangeRequest request,
) {
  final lines = <String>[];
  final payload = request.payload;
  try {
    final profilesRaw = payload['profiles'];
    if (profilesRaw is List) {
      for (final entry in profilesRaw.whereType<Map>()) {
        lines.addAll(_profileDetailLines(session, Map<String, dynamic>.from(entry)));
      }
    }
    final profileDeletes = payload['profileDeletes'];
    if (profileDeletes is List) {
      for (final key in profileDeletes.whereType<String>()) {
        final name = session.profiles.bySyncKey(key)?.name;
        lines.add(
          name != null
              ? 'Removes the profile "$name" and its boards'
              : 'Removes a profile',
        );
      }
    }
    final dashboardsRaw = payload['dashboards'];
    if (dashboardsRaw is Map) {
      for (final entry in dashboardsRaw.values.whereType<Map>()) {
        final dash = Map<String, dynamic>.from(entry);
        final cells = dash['cells'];
        final labels = <String>[];
        if (cells is List) {
          for (final c in cells.whereType<Map>()) {
            final label = (c['label'] ?? c['speakText'])?.toString() ?? '';
            if (label.isNotEmpty) labels.add(label);
          }
        }
        final shown = labels.take(8).join(', ');
        lines.add(
          'Board will have ${labels.length} button'
          '${labels.length == 1 ? '' : 's'}'
          '${shown.isEmpty ? '' : ': $shown'}'
          '${labels.length > 8 ? ', …' : ''}',
        );
        if (dash['enabled'] == true) {
          lines.add('The board becomes the home board');
        }
      }
    }
    final dashboardDeletes = payload['dashboardDeletes'];
    if (dashboardDeletes is List && dashboardDeletes.isNotEmpty) {
      lines.add('Deletes the personal board');
    }
    final goalsRaw = payload['goals'];
    if (goalsRaw is List) {
      for (final entry in goalsRaw.whereType<Map>()) {
        final goal = Map<String, dynamic>.from(entry);
        final title = goal['title']?.toString() ?? '';
        final comments = goal['comments'];
        final commentCount = comments is List ? comments.length : 0;
        lines.add(
          'Goal: "$title"'
          '${goal['achieved'] == true ? ' (marked achieved)' : ''}'
          '${commentCount > 0 ? ' — $commentCount comment${commentCount == 1 ? '' : 's'}' : ''}',
        );
      }
    }
    final goalTombs = payload['goal_tombstones'];
    if (goalTombs is List && goalTombs.isNotEmpty) {
      lines.add('Deletes a goal');
    }
    final zonesRaw = payload['safe_zones'];
    if (zonesRaw is List) {
      for (final entry in zonesRaw.whereType<Map>()) {
        final zone = Map<String, dynamic>.from(entry);
        final radius = (zone['radius_m'] as num?)?.round();
        lines.add(
          'Safe zone "${zone['name'] ?? ''}"'
          '${radius != null ? ' — $radius m radius' : ''}'
          '${zone['enabled'] == false ? ' (turned off)' : ''}',
        );
      }
    }
    final zoneTombs = payload['safe_zone_tombstones'];
    if (zoneTombs is List && zoneTombs.isNotEmpty) {
      lines.add('Removes a safe zone');
    }
    final vocab = payload['vocabLevel'];
    if (vocab is int) {
      lines.add('Vocabulary level: $vocab');
    }
  } catch (_) {
    // Detail is a courtesy; the summary line always renders.
  }
  return lines;
}

List<String> _profileDetailLines(
  SessionState session,
  Map<String, dynamic> entry,
) {
  final lines = <String>[];
  final name = entry['name']?.toString() ?? 'Profile';
  final local = session.profiles.bySyncKey(entry['syncKey']?.toString() ?? '');
  String modeLabel(Object? v) => switch (v) {
    'build' => 'Build',
    'type' => 'Type',
    _ => 'Tap',
  };
  if (local == null) {
    lines.add('New profile "$name" (mode: ${modeLabel(entry['mode'])})');
    return lines;
  }
  void diff(String label, Object? next, Object? current) {
    if ('$next' != '$current') lines.add('$label: $current → $next');
  }

  diff('Mode', modeLabel(entry['mode']), modeLabel(local.communicationMode.name));
  diff('Build length', entry['buildMaxSymbols'], local.buildMaxSymbols);
  diff(
    'Predictions',
    entry['predictionEnabled'] == true ? 'on' : 'off',
    local.predictionEnabled ? 'on' : 'off',
  );
  diff(
    'Word limits',
    entry['wordLimitsEnabled'] == true ? 'on' : 'off',
    local.wordLimitsEnabled ? 'on' : 'off',
  );
  final contacts = entry['contacts'];
  if (contacts is List && contacts.length != local.contacts.length) {
    lines.add(
      'Safety contacts: ${local.contacts.length} → ${contacts.length}',
    );
  }
  final phrases = entry['callPhrases'];
  if (phrases is List && phrases.length != local.callPhrases.length) {
    lines.add('Call phrases: ${local.callPhrases.length} → ${phrases.length}');
  }
  diff(
    'Location sharing',
    entry['locationSharingEnabled'] == true ? 'on' : 'off',
    local.locationSharingEnabled ? 'on' : 'off',
  );
  diff('Name', entry['name'], local.name);
  if (lines.isEmpty) lines.add('Updates settings for "$name"');
  return lines;
}

String _relativeTime(DateTime when) {
  final diff = DateTime.now().difference(when);
  if (diff.inMinutes < 1) return 'just now';
  if (diff.inMinutes < 60) return '${diff.inMinutes} min ago';
  if (diff.inHours < 24) return '${diff.inHours} h ago';
  if (diff.inDays < 7) return '${diff.inDays} d ago';
  return '${when.month}/${when.day}/${when.year}';
}
