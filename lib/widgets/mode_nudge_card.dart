import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../services/nudge_service.dart';
import '../services/profile_service.dart';
import '../state/session_state.dart';
import 'communication_mode_widgets.dart';

/// The ONE caregiver-facing mode-progression suggestion (Phase 5 of the
/// modes plan).
///
/// * Renders ONLY in the caregiver hub (per-profile card), and ONLY when
///   [ModeNudgeService.suggestionFor] returns a suggestion. It never
///   appears on the communicator's board, is never a banner, and never a
///   blocking modal.
/// * The preview button opens the Phase-2 never-speaking sandbox preview
///   for the suggested mode. Opening it records a cooldown identical to
///   dismissal; the saved mode is untouched.
/// * "Not now" dismisses for 30 days; "Don't suggest again" writes the
///   durable per-profile [ModeNudgePreference.off] (the existing profile
///   preference), which overrides eligibility forever.
/// * Copy is deliberately gentle and states, in plain language, that the
///   mode will not change on its own.
class ModeNudgeCard extends StatelessWidget {
  const ModeNudgeCard({
    super.key,
    required this.profileId,
    required this.onChanged,
  });

  final String profileId;
  final VoidCallback onChanged;

  @override
  Widget build(BuildContext context) {
    final session = context.watch<SessionState>();
    UserProfile? profile;
    for (final p in session.profiles.profiles) {
      if (p.id == profileId) profile = p;
    }
    if (profile == null) return const SizedBox.shrink();
    final suggestion = session.nudge.suggestionFor(profile);
    if (suggestion == null) return const SizedBox.shrink();

    final scheme = Theme.of(context).colorScheme;
    final targetTitle = switch (suggestion.targetMode) {
      CommunicationMode.tap => 'Tap',
      CommunicationMode.build => 'Build',
      CommunicationMode.type => 'Type',
    };
    final signal = switch (suggestion.currentMode) {
      CommunicationMode.build =>
        'has pressed Speak with a full phrase strip ${ModeNudgeService.buildFullSpeakThreshold} times — consistently building complete messages.',
      CommunicationMode.tap =>
        'has been using Tap mode regularly and knows the board well. Trying Build mode is an easy next step to explore.',
      CommunicationMode.type =>
        '', // unreachable: Type has no next mode, so never suggested
    };

    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 4, 16, 16),
      child: Card(
        color: scheme.secondaryContainer,
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Row(
                children: [
                  Icon(Icons.trending_up, color: scheme.onSecondaryContainer),
                  const SizedBox(width: 8),
                  const Expanded(
                    child: Text(
                      'A thought about their progress',
                      style: TextStyle(
                        fontWeight: FontWeight.bold,
                        fontSize: 15,
                      ),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 8),
              Text(
                '${profile.name} $signal\n\n'
                'Would you like to preview $targetTitle mode? Nothing '
                'changes unless you choose it — the mode stays exactly as '
                'it is until you press "Save mode".',
                style: TextStyle(
                  fontSize: 13,
                  color: scheme.onSecondaryContainer,
                ),
              ),
              const SizedBox(height: 12),
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: [
                  FilledButton.icon(
                    icon: const Icon(Icons.preview_outlined),
                    label: Text('Preview $targetTitle mode'),
                    onPressed: () async {
                      // Marking a preview counts as a dismissal: same
                      // 30-day cooldown, saved mode untouched.
                      await session.nudge.recordPreview(profileId);
                      onChanged();
                      if (context.mounted) {
                        await showModePreviewDialog(
                          context,
                          suggestion.targetMode,
                        );
                      }
                    },
                  ),
                  OutlinedButton(
                    child: const Text('Not now'),
                    onPressed: () async {
                      await session.nudge.dismiss(profileId);
                      onChanged();
                      if (context.mounted) {
                        ScaffoldMessenger.of(context).showSnackBar(
                          const SnackBar(
                            content: Text(
                              'Suggestion paused for 30 days.',
                            ),
                          ),
                        );
                      }
                    },
                  ),
                  TextButton(
                    child: const Text('Don\u2019t suggest again'),
                    onPressed: () async {
                      await session.profiles.setNudgePreference(
                        profileId,
                        ModeNudgePreference.off,
                      );
                      onChanged();
                      if (context.mounted) {
                        ScaffoldMessenger.of(context).showSnackBar(
                          const SnackBar(
                            content: Text(
                              'You won\u2019t see mode suggestions for this profile again.',
                            ),
                          ),
                        );
                      }
                    },
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}
