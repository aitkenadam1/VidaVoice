import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../models/modeling_plan.dart';
import '../models/word.dart';
import '../state/session_state.dart';

/// Caregiver hub: communicator profiles, modeling tips (the core
/// differentiator — teaching partners HOW to model), setup replay,
/// and the honest roadmap of what's still planned.
class CaregiverScreen extends StatefulWidget {
  const CaregiverScreen({super.key});

  @override
  State<CaregiverScreen> createState() => _CaregiverScreenState();
}

class _CaregiverScreenState extends State<CaregiverScreen> {
  /// What each vocabulary level adds, in caregiver language. Index 0 = level 1.
  static const _levelInfo = [
    (
      'Level 1 — Starter',
      'The words that get a first message across: want, more, stop, help, go, '
          'yes, no, and the four folders. Everything else is left blank on '
          'purpose, so there is less to scan.',
    ),
    (
      'Level 2 — Growing',
      'Adds describing and asking words — when, how, why, hot, cold, fast, '
          'and more verbs. Move here once they are combining two words.',
    ),
    (
      'Level 3 — Full board',
      'Every word in the pack, including time words, opposites and the small '
          'connecting words (and, but, because).',
    ),
  ];

  static const _planned = [
    'Custom words and personal folders (photos from the camera)',
    'Usage insights: most-used words, weekly progress',
    'Backup & sync across devices',
  ];

  @override
  Widget build(BuildContext context) {
    final session = context.watch<SessionState>();
    final profiles = session.profiles;
    return Scaffold(
      appBar: AppBar(title: const Text('Caregiver')),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          _sectionTitle(context, 'Communicator profiles'),
          Card(
            child: Column(
              children: [
                for (final p in profiles.profiles)
                  ListTile(
                    leading: const Icon(Icons.person_outline),
                    title: Text(p.name),
                    trailing: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        if (p.id == profiles.active?.id)
                          const Icon(Icons.check, color: Colors.green)
                        else
                          TextButton(
                            onPressed: () async {
                              await profiles.setActive(p.id);
                              if (mounted) setState(() {});
                            },
                            child: const Text('Switch'),
                          ),
                        if (profiles.profiles.length > 1)
                          IconButton(
                            tooltip: 'Remove profile',
                            icon: const Icon(Icons.delete_outline),
                            onPressed: () async {
                              await profiles.removeProfile(p.id);
                              if (mounted) setState(() {});
                            },
                          ),
                      ],
                    ),
                  ),
                Padding(
                  padding: const EdgeInsets.all(8),
                  child: OutlinedButton.icon(
                    icon: const Icon(Icons.add),
                    label: const Text('Add profile'),
                    onPressed: () => _addProfileDialog(context, session),
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 16),
          _sectionTitle(context, 'Vocabulary level'),
          const Padding(
            padding: EdgeInsets.only(bottom: 8, left: 4),
            child: Text(
              'Words above the chosen level are left as blank cells. Every '
              'word you can already see keeps exactly the same position when '
              'you unlock more — the board grows into the gaps, it never '
              'rearranges. That is what protects the motor pattern.',
              style: TextStyle(fontSize: 13),
            ),
          ),
          Card(
            child: RadioGroup<int>(
              groupValue: session.unlockedLevel,
              onChanged: (v) {
                if (v != null) session.setUnlockedLevel(v);
              },
              child: Column(
                children: [
                  for (
                    var level = LanguagePack.minSupportedLevel;
                    level <= LanguagePack.maxSupportedLevel;
                    level++
                  )
                    RadioListTile<int>(
                      value: level,
                      title: Text(_levelInfo[level - 1].$1),
                      subtitle: Text(_levelInfo[level - 1].$2),
                      isThreeLine: true,
                    ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 16),
          _sectionTitle(context, 'Your first week'),
          _firstWeek(context, session),
          const SizedBox(height: 16),
          _sectionTitle(context, 'Setup'),
          Card(
            child: ListTile(
              leading: const Icon(Icons.replay_outlined),
              title: const Text('Replay setup tour'),
              subtitle: const Text(
                'Run the first-run wizard again (welcome, voice, quick tour).',
              ),
              onTap: () {
                session.reopenOnboarding();
                Navigator.of(context).pop();
              },
            ),
          ),
          const SizedBox(height: 16),
          _sectionTitle(context, 'Planned next'),
          Card(
            child: Column(
              children: [
                for (final item in _planned)
                  ListTile(
                    leading: Icon(Icons.schedule_outlined),
                    title: Text(item),
                  ),
              ],
            ),
          ),
          const SizedBox(height: 16),
          const Padding(
            padding: EdgeInsets.symmetric(horizontal: 4),
            child: Text(
              'Word symbols: ARASAAC (CC BY-NC-SA), https://arasaac.org',
              style: TextStyle(fontSize: 12),
              textAlign: TextAlign.center,
            ),
          ),
        ],
      ),
    );
  }

  /// The guided first week: one habit per day, each with something concrete
  /// to try before bedtime. Progress is per profile and stored locally.
  Widget _firstWeek(BuildContext context, SessionState session) {
    final progress = session.modelingProgress;
    final today = progress.suggestedDay;
    final done = progress.completedDays.length;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Padding(
          padding: const EdgeInsets.only(bottom: 8, left: 4),
          child: Text(
            progress.started
                ? 'One habit a day for ${ModelingPlan.days} days. Miss a day '
                      'and nothing is lost — the days stay here until you tick '
                      'them off.'
                : 'The single biggest factor in AAC success is how '
                      'communication partners use the device. This is seven '
                      'days of short, practical habits — about two minutes '
                      'each.',
            style: const TextStyle(fontSize: 13),
          ),
        ),
        if (!progress.started)
          Card(
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                children: [
                  Text(
                    'Start the first week with ${session.profiles.activeName}',
                    style: const TextStyle(fontWeight: FontWeight.bold),
                    textAlign: TextAlign.center,
                  ),
                  const SizedBox(height: 12),
                  FilledButton.icon(
                    icon: const Icon(Icons.play_arrow),
                    label: const Text('Start day 1'),
                    onPressed: session.startModelingPlan,
                  ),
                ],
              ),
            ),
          )
        else
          Card(
            color: Theme.of(context).colorScheme.secondaryContainer,
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    progress.finished
                        ? 'All ${ModelingPlan.days} days done'
                        : 'Today — day $today of ${ModelingPlan.days}',
                    style: const TextStyle(
                      fontWeight: FontWeight.bold,
                      fontSize: 16,
                    ),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    progress.finished
                        ? 'These habits are the whole method — come back to any '
                              'day whenever you want a refresher.'
                        : ModelingPlan.dayNumber(today).tryIt,
                  ),
                  const SizedBox(height: 8),
                  LinearProgressIndicator(value: done / ModelingPlan.days),
                  const SizedBox(height: 4),
                  Text('$done of ${ModelingPlan.days} days done'),
                ],
              ),
            ),
          ),
        const SizedBox(height: 8),
        for (final day in ModelingPlan.all)
          Card(
            margin: const EdgeInsets.symmetric(vertical: 4),
            child: ExpansionTile(
              initiallyExpanded: progress.started && day.day == today,
              leading: Icon(
                progress.isDone(day.day)
                    ? Icons.check_circle
                    : Icons.lightbulb_outline,
                color: progress.isDone(day.day) ? Colors.green : null,
              ),
              title: Text(
                'Day ${day.day} — ${day.title}',
                style: const TextStyle(fontWeight: FontWeight.bold),
              ),
              children: [
                Padding(
                  padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(day.body),
                      const SizedBox(height: 12),
                      Container(
                        width: double.infinity,
                        padding: const EdgeInsets.all(12),
                        decoration: BoxDecoration(
                          color: Theme.of(
                            context,
                          ).colorScheme.surfaceContainerHighest,
                          borderRadius: BorderRadius.circular(8),
                        ),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            const Text(
                              'Try it today',
                              style: TextStyle(fontWeight: FontWeight.bold),
                            ),
                            const SizedBox(height: 4),
                            Text(day.tryIt),
                          ],
                        ),
                      ),
                      const SizedBox(height: 8),
                      Align(
                        alignment: Alignment.centerRight,
                        child: TextButton.icon(
                          icon: Icon(
                            progress.isDone(day.day)
                                ? Icons.undo
                                : Icons.check_circle_outline,
                          ),
                          label: Text(
                            progress.isDone(day.day)
                                ? 'Mark not done'
                                : 'I did this',
                          ),
                          onPressed: () => session.setModelingDayDone(
                            day.day,
                            !progress.isDone(day.day),
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        if (progress.started)
          Align(
            alignment: Alignment.centerRight,
            child: TextButton.icon(
              icon: const Icon(Icons.restart_alt),
              label: const Text('Restart the week'),
              onPressed: session.resetModelingPlan,
            ),
          ),
      ],
    );
  }

  Widget _sectionTitle(BuildContext context, String title) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Text(
        title,
        style: Theme.of(context).textTheme.titleMedium
            ?.copyWith(fontWeight: FontWeight.bold),
      ),
    );
  }

  Future<void> _addProfileDialog(
    BuildContext context,
    SessionState session,
  ) async {
    final controller = TextEditingController();
    final name = await showDialog<String>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('New profile'),
        content: TextField(
          controller: controller,
          autofocus: true,
          textCapitalization: TextCapitalization.words,
          decoration: const InputDecoration(
            labelText: 'First name',
            border: OutlineInputBorder(),
          ),
          onSubmitted: (_) => Navigator.of(ctx).pop(controller.text),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(ctx).pop(controller.text),
            child: const Text('Add'),
          ),
        ],
      ),
    );
    if (name != null && name.trim().isNotEmpty) {
      await session.profiles.addProfile(name.trim());
      if (mounted) setState(() {});
    }
  }
}
