import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../state/session_state.dart';
import '../../widgets/activity_summary_section.dart';
import '../../widgets/backup_section.dart';
import '../../widgets/device_sync_section.dart';
import '../settings_screen.dart';
import 'portal_section.dart';

/// Portal "Settings" tab: voice & speech, backup & sync, device sync,
/// activity, modeling tips, and setup/roadmap.
///
/// Mounts the same tested section widgets the old caregiver hub used.
/// "Voices" opens the full Settings screen (voice choice, rate/pitch,
/// neural and cloud voices), which is shared with the board-side
/// settings entry.
class PortalSettingsTab extends StatelessWidget {
  const PortalSettingsTab({super.key});

  @override
  Widget build(BuildContext context) {
    final session = context.watch<SessionState>();
    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        PortalSection(
          title: 'Voice & speech',
          icon: Icons.record_voice_over_outlined,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Padding(
                padding: EdgeInsets.fromLTRB(4, 0, 4, 8),
                child: Text(
                  'Language, speaking voice, speed and pitch, neural and '
                  'cloud voices.',
                  style: TextStyle(fontSize: 13),
                ),
              ),
              OutlinedButton.icon(
                icon: const Icon(Icons.settings_outlined),
                label: const Text('Open voice & speech settings'),
                onPressed: () {
                  Navigator.of(context).push(
                    MaterialPageRoute(
                      builder: (_) => const SettingsScreen(),
                    ),
                  );
                },
              ),
            ],
          ),
        ),
        PortalSection(
          title: 'Backup & sync',
          icon: Icons.backup_outlined,
          child: BackupSection(
            onImported: () async {
              await session.reloadProfileData();
              await session.usage.load();
            },
          ),
        ),
        PortalSection(
          title: 'Device sync',
          icon: Icons.sync_outlined,
          child: const DeviceSyncSection(),
        ),
        PortalSection(
          title: 'Activity',
          icon: Icons.insights_outlined,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const ActivitySummarySection(),
              const SizedBox(height: 8),
              const Text(
                'Most used words',
                style: TextStyle(
                  fontSize: 15,
                  fontWeight: FontWeight.bold,
                ),
              ),
              _MostUsedWords(session: session),
            ],
          ),
        ),
        const PortalSection(
          title: 'Modeling tips',
          icon: Icons.lightbulb_outline,
          child: _ModelingTips(),
        ),
        PortalSection(
          title: 'Setup & what\u2019s next',
          icon: Icons.more_horiz,
          child: _SetupAndNext(session: session),
        ),
      ],
    );
  }
}

/// Most-used-words list, migrated from the old caregiver hub.
class _MostUsedWords extends StatelessWidget {
  const _MostUsedWords({required this.session});

  final SessionState session;

  @override
  Widget build(BuildContext context) {
    final top = session.usage.top(10);
    if (top.isEmpty) {
      return const Padding(
        padding: EdgeInsets.all(8),
        child: Text(
          'No taps recorded yet. Words tapped on the board will show up '
          'here, most-used first.',
          style: TextStyle(fontSize: 13),
        ),
      );
    }
    return Column(
      children: [
        for (var i = 0; i < top.length; i++)
          _usageRow(session, i + 1, top[i].key, top[i].value),
      ],
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
}

/// Modeling tips, migrated verbatim from the old caregiver hub.
class _ModelingTips extends StatelessWidget {
  const _ModelingTips();

  static const _tips = [
    (
      'Model, don\u2019t quiz',
      'Use OneVoz to talk WITH them, not test them. When you hand them '
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

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Padding(
          padding: EdgeInsets.fromLTRB(4, 0, 4, 4),
          child: Text(
            'How you use the device matters more than any setting. These '
            'are the habits that work:',
            style: TextStyle(fontSize: 13),
          ),
        ),
        for (final (title, body) in _tips)
          ExpansionTile(
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
      ],
    );
  }
}

/// Re-run setup + roadmap + credits, migrated from the old hub.
/// Roadmap items stay non-tappable with explicit "Coming soon" chips —
/// they are promises, not buttons.
class _SetupAndNext extends StatelessWidget {
  const _SetupAndNext({required this.session});

  final SessionState session;

  // Curated from the old hub's roadmap: backup & sync shipped (it's
  // mounted above), so only genuinely unbuilt items remain.
  static const _planned = [
    'Custom words and personal folders (photos from the camera)',
  ];

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        ListTile(
          leading: const Icon(Icons.replay_outlined),
          title: const Text('Re-run setup'),
          subtitle: const Text(
            'Run the first-run wizard again (welcome, account, import, '
            'voice, quick tour).',
          ),
          onTap: () async {
            // No pop: the portal is the router's root, and
            // reopenOnboarding notifies — the router rebuilds straight
            // into the onboarding flow. After it completes, the role
            // and sign-in gates skip (state is preserved) and the
            // portal returns.
            await session.reopenOnboarding();
          },
        ),
        const Divider(),
        for (final item in _planned)
          ListTile(
            dense: true,
            leading: const Icon(Icons.schedule_outlined),
            title: Text(item),
            // Not tappable on purpose: these are roadmap items, not
            // features. The chip makes "what's coming" unmistakable
            // so nothing looks like a dead button.
            trailing: Container(
              padding: const EdgeInsets.symmetric(
                horizontal: 10,
                vertical: 4,
              ),
              decoration: BoxDecoration(
                color: Theme.of(context)
                    .colorScheme
                    .surfaceContainerHighest,
                borderRadius: BorderRadius.circular(99),
              ),
              child: const Text(
                'Coming soon',
                style: TextStyle(fontSize: 11),
              ),
            ),
          ),
        const Padding(
          padding: EdgeInsets.fromLTRB(16, 12, 16, 4),
          child: Text(
            'Word symbols: ARASAAC (CC BY-NC-SA), https://arasaac.org',
            style: TextStyle(fontSize: 12),
            textAlign: TextAlign.center,
          ),
        ),
      ],
    );
  }
}
