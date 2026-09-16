import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../models/word.dart';
import '../../state/session_state.dart';
import '../../widgets/custom_symbols_section.dart';
import '../../widgets/dashboard_section.dart';
import '../../widgets/first_week_plan_section.dart';
import '../../widgets/word_finder_section.dart';
import 'portal_section.dart';

/// Portal "Content" tab: everything about what's on the boards —
/// vocabulary level, word search, custom symbols, the personal
/// dashboard, and the first-week plan. Mounts the same tested section
/// widgets the old caregiver hub used; only the hub's collapsible-card
/// chrome is gone (tabs already group the content).
class PortalContentTab extends StatefulWidget {
  const PortalContentTab({super.key});

  @override
  State<PortalContentTab> createState() => _PortalContentTabState();
}

class _PortalContentTabState extends State<PortalContentTab> {
  void _refresh() {
    if (mounted) setState(() {});
  }

  @override
  Widget build(BuildContext context) {
    final session = context.watch<SessionState>();
    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        PortalSection(
          title: 'Vocabulary level',
          icon: Icons.tune,
          child: _VocabularyLevelPicker(refresh: _refresh),
        ),
        PortalSection(
          title: 'Find a word',
          icon: Icons.search,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(4, 0, 4, 8),
                child: Text(
                  'Tapping a result speaks it so you can hear it — nothing '
                  'on the board changes.',
                  style: TextStyle(
                    fontSize: 13,
                    color: Theme.of(context).colorScheme.onSurfaceVariant,
                  ),
                ),
              ),
              const WordFinderSection(),
            ],
          ),
        ),
        PortalSection(
          title: 'Custom symbols',
          icon: Icons.image_outlined,
          child: CustomSymbolsSection(refresh: _refresh),
        ),
        PortalSection(
          title: 'Personal dashboard',
          icon: Icons.dashboard_outlined,
          child: DashboardSection(
            key: ValueKey(session.profiles.active?.id ?? 'none'),
            refresh: _refresh,
          ),
        ),
        PortalSection(
          title: 'First week plan',
          icon: Icons.calendar_month_outlined,
          child: _firstWeekPlan(session),
        ),
      ],
    );
  }

  Widget _firstWeekPlan(SessionState session) {
    final active = session.profiles.active;
    if (active == null) {
      return const Padding(
        padding: EdgeInsets.all(8),
        child: Text(
          'Add a communicator profile first — the plan belongs to a profile.',
        ),
      );
    }
    return FirstWeekPlanSection(
      key: ValueKey(active.id),
      profileId: active.id,
      profileName: active.name,
    );
  }
}

/// Vocabulary-level picker, migrated from the old caregiver hub.
/// Locked words stay blank in place; unlocking fills the gaps — the
/// board never rearranges.
class _VocabularyLevelPicker extends StatelessWidget {
  const _VocabularyLevelPicker({required this.refresh});

  final VoidCallback refresh;

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

  @override
  Widget build(BuildContext context) {
    final session = context.watch<SessionState>();
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            const Expanded(
              child: Padding(
                padding: EdgeInsets.only(left: 4),
                child: Text(
                  'Locked words stay blank in place. Unlocking fills the '
                  'gaps — nothing moves.',
                  style: TextStyle(fontSize: 13),
                ),
              ),
            ),
            IconButton(
              tooltip: 'Why levels work this way',
              icon: const Icon(Icons.info_outline),
              onPressed: () => showDialog(
                context: context,
                builder: (ctx) => AlertDialog(
                  title: const Text('Why levels work this way'),
                  content: const Text(
                    'Every word has a fixed position on the board — that '
                    'is what builds the motor pattern. Words above the '
                    'chosen level are left as blank cells. When you '
                    'unlock more, every word you can already see keeps '
                    'exactly the same position: the board grows into the '
                    'gaps, it never rearranges.',
                  ),
                  actions: [
                    TextButton(
                      onPressed: () => Navigator.of(ctx).pop(),
                      child: const Text('Got it'),
                    ),
                  ],
                ),
              ),
            ),
          ],
        ),
        RadioGroup<int>(
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
      ],
    );
  }
}
