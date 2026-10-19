import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../models/goal.dart';
import '../../services/profile_service.dart';
import '../../services/word_finder.dart';
import '../../state/session_state.dart';
import 'portal_section.dart';

/// Portal "Goals" section (Profiles tab): communication goals for the
/// active profile — a target date, a checkbox when it's achieved, a
/// feedback thread for the whole care team, and one-tap ways to tailor
/// the child's board toward the goal (words and phrases added here land
/// on the personal dashboard, linked to the goal).
class GoalsSection extends StatelessWidget {
  const GoalsSection({super.key});

  @override
  Widget build(BuildContext context) {
    final session = context.watch<SessionState>();
    final profile = session.profiles.active;
    return PortalSection(
      title: 'Goals',
      icon: Icons.flag_outlined,
      child: profile == null
          ? const Text(
              'Add a communicator profile first — goals belong to a profile.',
            )
          : _GoalsBody(profile: profile),
    );
  }
}

class _GoalsBody extends StatelessWidget {
  const _GoalsBody({required this.profile});

  final UserProfile profile;

  @override
  Widget build(BuildContext context) {
    final session = context.watch<SessionState>();
    final goals = session.goalsForProfile(profile);
    final canEdit = session.canEditGoals;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          'What ${profile.name} is working toward. Set a target date, '
          'check a goal off when it\u2019s reached, and let the care team '
          'leave feedback. Words and phrases you add for a goal go onto '
          '${profile.name}\u2019s personal dashboard.',
        ),
        if (!canEdit)
          const Padding(
            padding: EdgeInsets.only(top: 8),
            child: Text(
              'Your access is view-only, so goals are read-only here — '
              'you can still follow progress and the team\u2019s feedback.',
              style: TextStyle(fontStyle: FontStyle.italic),
            ),
          ),
        const SizedBox(height: 8),
        if (goals.isEmpty)
          const Padding(
            padding: EdgeInsets.symmetric(vertical: 8),
            child: Text('No goals yet.'),
          ),
        for (final goal in goals) _GoalTile(goal: goal, profile: profile),
        if (canEdit)
          Align(
            alignment: Alignment.centerLeft,
            child: Padding(
              padding: const EdgeInsets.only(top: 4),
              child: FilledButton.tonalIcon(
                icon: const Icon(Icons.add),
                label: const Text('Add goal'),
                onPressed: () => _showGoalEditor(context, session, profile),
              ),
            ),
          ),
      ],
    );
  }
}

class _GoalTile extends StatelessWidget {
  const _GoalTile({required this.goal, required this.profile});

  final ProfileGoal goal;
  final UserProfile profile;

  @override
  Widget build(BuildContext context) {
    final session = context.watch<SessionState>();
    final scheme = Theme.of(context).colorScheme;
    final now = DateTime.now();
    final overdue = goal.isOverdue(now);
    return Card(
      margin: const EdgeInsets.only(bottom: 8),
      child: ListTile(
        leading: Checkbox(
          value: goal.achieved,
          onChanged: session.canEditGoals
              ? (v) => session.setGoalAchieved(goal, v ?? false)
              : null,
        ),
        title: Text(
          goal.title,
          style: TextStyle(
            decoration: goal.achieved ? TextDecoration.lineThrough : null,
            color: goal.achieved ? scheme.onSurfaceVariant : null,
          ),
        ),
        subtitle: Text(
          _statusLine(goal, now),
          style: TextStyle(color: overdue ? scheme.error : null),
        ),
        trailing: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            if (goal.links.isNotEmpty) ...[
              Icon(Icons.dashboard_outlined, size: 18, color: scheme.primary),
              const SizedBox(width: 2),
              Text('${goal.links.length}'),
              const SizedBox(width: 10),
            ],
            if (goal.comments.isNotEmpty) ...[
              Icon(
                Icons.mode_comment_outlined,
                size: 18,
                color: scheme.primary,
              ),
              const SizedBox(width: 2),
              Text('${goal.comments.length}'),
              const SizedBox(width: 6),
            ],
            const Icon(Icons.chevron_right),
          ],
        ),
        onTap: () => showDialog(
          context: context,
          builder: (_) => _GoalDetailDialog(goalId: goal.id),
        ),
      ),
    );
  }
}

String _statusLine(ProfileGoal goal, DateTime now) {
  if (goal.achieved) {
    final at = goal.achievedAt;
    return at == null ? 'Achieved' : 'Achieved ${_fmtDate(at)}';
  }
  final target = goal.targetDate;
  if (target == null) return 'No target date';
  final days = goal.daysLeft(now) ?? 0;
  final base = 'By ${_fmtDate(target)}';
  if (days == 0) return '$base · due today';
  if (days > 0) return '$base · $days day${days == 1 ? '' : 's'} left';
  final over = -days;
  return '$base · $over day${over == 1 ? '' : 's'} overdue';
}

const _months = [
  'Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun',
  'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec',
];

String _fmtDate(DateTime d) => '${_months[d.month - 1]} ${d.day}, ${d.year}';

String _fmtDateTime(DateTime d) {
  final h = d.hour % 12 == 0 ? 12 : d.hour % 12;
  final mm = d.minute.toString().padLeft(2, '0');
  final ap = d.hour >= 12 ? 'PM' : 'AM';
  return '${_fmtDate(d)} · $h:$mm $ap';
}

// ------------------------------------------------------------ editor ---

Future<void> _showGoalEditor(
  BuildContext context,
  SessionState session,
  UserProfile profile, {
  ProfileGoal? existing,
}) async {
  final title = TextEditingController(text: existing?.title ?? '');
  final notes = TextEditingController(text: existing?.notes ?? '');
  var target = existing?.targetDate;
  await showDialog(
    context: context,
    builder: (ctx) => AlertDialog(
      title: Text(existing == null ? 'New goal' : 'Edit goal'),
      content: StatefulBuilder(
        builder: (ctx, setDialogState) => SizedBox(
          width: double.maxFinite,
          child: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                TextField(
                  controller: title,
                  autofocus: existing == null,
                  textCapitalization: TextCapitalization.sentences,
                  decoration: const InputDecoration(
                    labelText: 'Goal',
                    hintText: 'e.g. Ask for a drink with two symbols',
                    border: OutlineInputBorder(),
                  ),
                ),
                const SizedBox(height: 12),
                TextField(
                  controller: notes,
                  maxLines: 3,
                  textCapitalization: TextCapitalization.sentences,
                  decoration: const InputDecoration(
                    labelText: 'Notes (optional)',
                    hintText: 'What success looks like, who\u2019s helping…',
                    border: OutlineInputBorder(),
                  ),
                ),
                const SizedBox(height: 12),
                Row(
                  children: [
                    const Icon(Icons.event_outlined),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        target == null
                            ? 'No target date'
                            : 'Target: ${_fmtDate(target!)}',
                      ),
                    ),
                    TextButton(
                      onPressed: () async {
                        final picked = await showDatePicker(
                          context: ctx,
                          initialDate: target ?? DateTime.now(),
                          firstDate: DateTime(2020),
                          lastDate: DateTime(2100),
                        );
                        if (picked != null) {
                          setDialogState(() => target = picked);
                        }
                      },
                      child: const Text('Pick date'),
                    ),
                    if (target != null)
                      TextButton(
                        onPressed: () => setDialogState(() => target = null),
                        child: const Text('Clear'),
                      ),
                  ],
                ),
              ],
            ),
          ),
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(ctx).pop(),
          child: const Text('Cancel'),
        ),
        FilledButton(
          onPressed: () async {
            if (title.text.trim().isEmpty) return;
            if (existing == null) {
              await session.createGoal(
                profile: profile,
                title: title.text,
                notes: notes.text,
                targetDate: target,
              );
            } else {
              await session.updateGoal(
                existing,
                title: title.text,
                notes: notes.text,
                targetDate: target,
                clearTargetDate: target == null,
              );
            }
            if (ctx.mounted) Navigator.of(ctx).pop();
          },
          child: Text(existing == null ? 'Add goal' : 'Save'),
        ),
      ],
    ),
  );
  title.dispose();
  notes.dispose();
}

// ------------------------------------------------------------ detail ---

class _GoalDetailDialog extends StatelessWidget {
  const _GoalDetailDialog({required this.goalId});

  final String goalId;

  @override
  Widget build(BuildContext context) {
    final session = context.watch<SessionState>();
    ProfileGoal? goal;
    for (final g in session.dashboardSync.goals) {
      if (g.id == goalId) goal = g;
    }
    if (goal == null) {
      // Deleted (here or on another device) while open.
      return const AlertDialog(content: Text('This goal no longer exists.'));
    }
    final goal0 = goal;
    final profile = session.profiles.bySyncKey(goal0.profileSyncKey);
    final canEdit = session.canEditGoals;
    final scheme = Theme.of(context).colorScheme;
    final now = DateTime.now();
    return AlertDialog(
      title: Row(
        children: [
          Checkbox(
            value: goal0.achieved,
            onChanged: canEdit
                ? (v) => session.setGoalAchieved(goal0, v ?? false)
                : null,
          ),
          Expanded(
            child: Text(
              goal0.title,
              style: TextStyle(
                decoration: goal0.achieved
                    ? TextDecoration.lineThrough
                    : null,
              ),
            ),
          ),
          if (canEdit && profile != null)
            IconButton(
              tooltip: 'Edit goal',
              icon: const Icon(Icons.edit_outlined),
              onPressed: () =>
                  _showGoalEditor(context, session, profile, existing: goal),
            ),
        ],
      ),
      content: SizedBox(
        width: double.maxFinite,
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                _statusLine(goal, now),
                style: TextStyle(
                  color: goal0.isOverdue(now) ? scheme.error : scheme.primary,
                  fontWeight: FontWeight.w600,
                ),
              ),
              if (goal0.notes.isNotEmpty) ...[
                const SizedBox(height: 8),
                Text(goal0.notes),
              ],
              const SizedBox(height: 16),
              const Text(
                'On the board for this goal',
                style: TextStyle(fontWeight: FontWeight.bold),
              ),
              const SizedBox(height: 4),
              if (goal0.links.isEmpty)
                Text(
                  'Nothing yet. Words and phrases added here go onto '
                  '${profile?.name ?? 'the'}\u2019s personal dashboard and '
                  'stay linked to this goal0.',
                )
              else
                Wrap(
                  spacing: 6,
                  runSpacing: 6,
                  children: [
                    for (final link in goal0.links)
                      InputChip(
                        avatar: Icon(
                          link.kind == 'phrase'
                              ? Icons.chat_bubble_outline
                              : Icons.grid_view_outlined,
                          size: 16,
                        ),
                        label: Text(link.label),
                        onDeleted: canEdit
                            ? () => session.unlinkGoalItem(goal0, link.cellId)
                            : null,
                      ),
                  ],
                ),
              if (canEdit) ...[
                const SizedBox(height: 8),
                Wrap(
                  spacing: 8,
                  children: [
                    OutlinedButton.icon(
                      icon: const Icon(Icons.search),
                      label: const Text('Add words'),
                      onPressed: () => _addWordsDialog(context, session, goal0),
                    ),
                    OutlinedButton.icon(
                      icon: const Icon(Icons.chat_bubble_outline),
                      label: const Text('Add a phrase'),
                      onPressed: () =>
                          _addPhraseDialog(context, session, goal0),
                    ),
                  ],
                ),
              ],
              const SizedBox(height: 16),
              const Text(
                'Feedback & comments',
                style: TextStyle(fontWeight: FontWeight.bold),
              ),
              const SizedBox(height: 4),
              if (goal0.comments.isEmpty)
                const Text(
                  'No feedback yet. Teachers, therapists, and family can '
                  'note what they\u2019re seeing here.',
                ),
              for (final c in goal0.comments)
                Padding(
                  padding: const EdgeInsets.only(bottom: 10),
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Icon(Icons.account_circle_outlined, size: 20),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              '${c.author} · ${_fmtDateTime(c.createdAt)}',
                              style: const TextStyle(
                                fontWeight: FontWeight.w600,
                                fontSize: 12,
                              ),
                            ),
                            Text(c.text),
                          ],
                        ),
                      ),
                      if (canEdit)
                        IconButton(
                          tooltip: 'Delete comment',
                          icon: const Icon(Icons.delete_outline, size: 18),
                          onPressed: () =>
                              session.deleteGoalComment(goal0, c.id),
                        ),
                    ],
                  ),
                ),
              if (canEdit) _CommentComposer(goal: goal0),
            ],
          ),
        ),
      ),
      actions: [
        if (canEdit)
          TextButton(
            onPressed: () async {
              final confirm = await showDialog<bool>(
                context: context,
                builder: (ctx) => AlertDialog(
                  title: const Text('Delete this goal?'),
                  content: const Text(
                    'The goal and its feedback will be removed for the '
                    'whole family. Words and phrases added for it stay on '
                    'the dashboard.',
                  ),
                  actions: [
                    TextButton(
                      onPressed: () => Navigator.of(ctx).pop(false),
                      child: const Text('Keep'),
                    ),
                    FilledButton(
                      onPressed: () => Navigator.of(ctx).pop(true),
                      child: const Text('Delete'),
                    ),
                  ],
                ),
              );
              if (confirm == true && context.mounted) {
                await session.deleteGoal(goal0);
                if (context.mounted) Navigator.of(context).pop();
              }
            },
            child: Text('Delete goal', style: TextStyle(color: scheme.error)),
          ),
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('Close'),
        ),
      ],
    );
  }
}

class _CommentComposer extends StatefulWidget {
  const _CommentComposer({required this.goal});

  final ProfileGoal goal;

  @override
  State<_CommentComposer> createState() => _CommentComposerState();
}

class _CommentComposerState extends State<_CommentComposer> {
  final _controller = TextEditingController();

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final session = context.read<SessionState>();
    return Row(
      crossAxisAlignment: CrossAxisAlignment.end,
      children: [
        Expanded(
          child: TextField(
            controller: _controller,
            textCapitalization: TextCapitalization.sentences,
            decoration: const InputDecoration(
              labelText: 'Add feedback or a comment',
              border: OutlineInputBorder(),
            ),
            onSubmitted: (_) => _send(session),
          ),
        ),
        const SizedBox(width: 8),
        IconButton.filled(
          tooltip: 'Post comment',
          icon: const Icon(Icons.send),
          onPressed: () => _send(session),
        ),
      ],
    );
  }

  Future<void> _send(SessionState session) async {
    final text = _controller.text;
    if (text.trim().isEmpty) return;
    _controller.clear();
    await session.addGoalComment(widget.goal, text);
  }
}

// ------------------------------------------------------- add to board ---

Future<void> _addWordsDialog(
  BuildContext context,
  SessionState session,
  ProfileGoal goal,
) async {
  final query = TextEditingController();
  final added = <String>{};
  await showDialog(
    context: context,
    builder: (ctx) => StatefulBuilder(
      builder: (ctx, setDialogState) {
        final hits = findWords(session.pack, query.text).take(30).toList();
        return AlertDialog(
          title: const Text('Add words for this goal'),
          content: SizedBox(
            width: double.maxFinite,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                TextField(
                  controller: query,
                  autofocus: true,
                  decoration: const InputDecoration(
                    labelText: 'Search words',
                    prefixIcon: Icon(Icons.search),
                    border: OutlineInputBorder(),
                  ),
                  onChanged: (_) => setDialogState(() {}),
                ),
                const SizedBox(height: 8),
                Flexible(
                  child: ListView.builder(
                    shrinkWrap: true,
                    itemCount: hits.length,
                    itemBuilder: (ctx, i) {
                      final hit = hits[i];
                      final wasAdded = added.contains(hit.item.id);
                      return ListTile(
                        dense: true,
                        title: Text(hit.item.label),
                        subtitle: Text(hit.location),
                        trailing: wasAdded
                            ? const Icon(Icons.check, color: Colors.green)
                            : const Icon(Icons.add),
                        onTap: wasAdded
                            ? null
                            : () async {
                                await session.addGoalWord(
                                  goal,
                                  wordId: hit.item.id,
                                  label: hit.item.label,
                                );
                                added.add(hit.item.id);
                                setDialogState(() {});
                              },
                      );
                    },
                  ),
                ),
              ],
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(ctx).pop(),
              child: const Text('Done'),
            ),
          ],
        );
      },
    ),
  );
  query.dispose();
}

Future<void> _addPhraseDialog(
  BuildContext context,
  SessionState session,
  ProfileGoal goal,
) async {
  final controller = TextEditingController();
  final text = await showDialog<String>(
    context: context,
    builder: (ctx) => AlertDialog(
      title: const Text('Add a phrase for this goal'),
      content: TextField(
        controller: controller,
        autofocus: true,
        textCapitalization: TextCapitalization.sentences,
        decoration: const InputDecoration(
          labelText: 'Phrase',
          hintText: 'e.g. I want a snack, please',
          border: OutlineInputBorder(),
        ),
        onSubmitted: (v) => Navigator.of(ctx).pop(v),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(ctx).pop(),
          child: const Text('Cancel'),
        ),
        FilledButton(
          onPressed: () => Navigator.of(ctx).pop(controller.text),
          child: const Text('Add phrase'),
        ),
      ],
    ),
  );
  controller.dispose();
  if (text != null && text.trim().isNotEmpty) {
    await session.addGoalPhrase(goal, text: text);
  }
}
