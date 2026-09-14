import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../state/session_state.dart';

/// Read-only activity dashboard for the caregiver hub, computed from the
/// existing persisted tap data: taps today, distinct words today, the
/// day streak, first-week plan progress, and the top 5 words this week.
class ActivitySummarySection extends StatelessWidget {
  const ActivitySummarySection({super.key});

  @override
  Widget build(BuildContext context) {
    final session = context.watch<SessionState>();
    final usage = session.usage;
    final profileId = session.profiles.active?.id;
    final planDone = profileId == null
        ? 0
        : session.plan.completedCount(profileId);

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                _stat(context, '${usage.tapsToday()}', 'taps today'),
                _stat(context, '${usage.wordsToday()}', 'words today'),
                _stat(
                  context,
                  '${usage.tapStreak()}',
                  usage.tapStreak() == 1 ? 'day in a row' : 'days in a row',
                ),
              ],
            ),
            const Divider(height: 24),
            Row(
              children: [
                const Icon(Icons.calendar_month_outlined, size: 20),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    'First-week plan: $planDone of 7 days done',
                    style: const TextStyle(fontSize: 14),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 12),
            Text(
              'Top this week',
              style: Theme.of(
                context,
              ).textTheme.titleSmall?.copyWith(fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 4),
            ..._topWeekRows(session),
          ],
        ),
      ),
    );
  }

  Widget _stat(BuildContext context, String value, String label) {
    return Expanded(
      child: Column(
        children: [
          Text(
            value,
            style: Theme.of(context).textTheme.headlineSmall?.copyWith(
              fontWeight: FontWeight.bold,
            ),
          ),
          const SizedBox(height: 2),
          Text(
            label,
            style: Theme.of(context).textTheme.bodySmall,
            textAlign: TextAlign.center,
          ),
        ],
      ),
    );
  }

  List<Widget> _topWeekRows(SessionState session) {
    final top = session.usage.topSinceDays(7, 5);
    if (top.isEmpty) {
      return const [
        Padding(
          padding: EdgeInsets.symmetric(vertical: 8),
          child: Text(
            'No taps this week yet.',
            style: TextStyle(fontSize: 13),
          ),
        ),
      ];
    }
    return [
      for (var i = 0; i < top.length; i++)
        Padding(
          padding: const EdgeInsets.symmetric(vertical: 4),
          child: Row(
            children: [
              CircleAvatar(
                radius: 13,
                child: Text('${i + 1}', style: const TextStyle(fontSize: 11)),
              ),
              const SizedBox(width: 12),
              Expanded(child: Text(_labelFor(session, top[i].key))),
              Text(
                '\u00d7${top[i].value}',
                style: const TextStyle(fontWeight: FontWeight.bold),
              ),
            ],
          ),
        ),
    ];
  }

  String _labelFor(SessionState session, String id) {
    try {
      return session.pack.wordById(id).label;
    } catch (_) {
      return id; // word removed from a newer pack; show the raw id
    }
  }
}
