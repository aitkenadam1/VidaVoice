import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../models/word.dart';
import '../state/session_state.dart';
import '../widgets/first_week_plan_section.dart';

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
      'Adds describing and asking words — colors, numbers, animals, when, '
          'how, why, hot, cold, fast, and more verbs. Move here once they '
          'are combining two words.',
    ),
    (
      'Level 3 — Full board',
      'Every word in the pack, including time words, opposites and the small '
          'connecting words (and, but, because).',
    ),
  ];
  static const _tips = [
    (
      'Model, don\u2019t quiz',
      'Use VidaVoice to talk WITH them, not test them. When you hand them '
          'juice, tap \u201cI want juice\u201d yourself. They learn by watching you use it.',
    ),
    (
      'Follow their lead',
      'Talk about whatever has their attention right now — not what you wish '
          'they\u2019d notice. If they\u2019re staring at the dog, model \u201cI see dog\u201d.',
    ),
    (
      'One step ahead',
      'If they use one word, you model two. They tap \u201cjuice\u201d — you tap '
          '\u201cwant juice\u201d. Always just one step beyond where they are.',
    ),
    (
      'Presume competence',
      'Talk about everything, all day — feelings, jokes, plans — exactly like '
          'you would with any child. Don\u2019t limit topics to needs and wants.',
    ),
    (
      'Give wait time',
      'After you model, silently count to 10. Processing takes time — don\u2019t '
          'rush to fill the silence or answer for them.',
    ),
    (
      'Never force repetition',
      'Don\u2019t demand \u201csay it on the app\u201d. If they don\u2019t respond, just model '
          'the word once more yourself and move on.',
    ),
    (
      'Keep it within reach, all day',
      'The voice should be available everywhere — not just at the therapy '
          'table. Communication doesn\u2019t keep office hours.',
    ),
  ];

  static const _planned = [
    'Custom words and personal folders (photos from the camera)',
    'Weekly progress view (usage trends over time)',
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
          Builder(
            builder: (context) {
              final active = profiles.active;
              if (active == null) return const SizedBox.shrink();
              return FirstWeekPlanSection(
                key: ValueKey(active.id),
                profileId: active.id,
                profileName: active.name,
              );
            },
          ),
          const SizedBox(height: 16),
          _sectionTitle(context, 'Most used words'),
          _mostUsedWordsCard(session),
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
          _sectionTitle(context, 'Modeling tips'),
          const Padding(
            padding: EdgeInsets.only(bottom: 8, left: 4),
            child: Text(
              'The single biggest factor in AAC success is how communication '
              'partners use the device. These are the habits that work:',
              style: TextStyle(fontSize: 13),
            ),
          ),
          for (final (title, body) in _tips)
            Card(
              margin: const EdgeInsets.symmetric(vertical: 4),
              child: ExpansionTile(
                leading: const Icon(Icons.lightbulb_outline),
                title: Text(
                  title,
                  style: const TextStyle(fontWeight: FontWeight.bold),
                ),
                children: [
                  Padding(
                    padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
                    child: Text(body),
                  ),
                ],
              ),
            ),
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

  Widget _mostUsedWordsCard(SessionState session) {
    final top = session.usage.top(10);
    if (top.isEmpty) {
      return const Card(
        child: Padding(
          padding: EdgeInsets.all(16),
          child: Text(
            'No taps recorded yet. Words tapped on the board will show up '
            'here, most-used first.',
            style: TextStyle(fontSize: 13),
          ),
        ),
      );
    }
    return Card(
      child: Column(
        children: [
          for (var i = 0; i < top.length; i++)
            _usageRow(session, i + 1, top[i].key, top[i].value),
        ],
      ),
    );
  }

  Widget _usageRow(SessionState session, int rank, String id, int count) {
    String label;
    try {
      label = session.pack.wordById(id).label;
    } catch (_) {
      label = id; // word removed from a newer pack; show the raw id
    }
    return ListTile(
      dense: true,
      leading: CircleAvatar(
        radius: 14,
        child: Text('$rank', style: const TextStyle(fontSize: 12)),
      ),
      title: Text(label),
      trailing: Text(
        '\u00d7$count',
        style: const TextStyle(fontWeight: FontWeight.bold),
      ),
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
