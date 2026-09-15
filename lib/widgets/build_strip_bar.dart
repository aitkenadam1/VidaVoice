import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../services/profile_service.dart';
import '../state/session_state.dart';
import 'message_bar.dart';

/// Picks the composition surface for the active profile's mode: Build gets
/// the phrase strip; Tap (and Type, until Phase 4 ships its own screen)
/// keep the classic sentence [MessageBar].
class CompositionBar extends StatelessWidget {
  const CompositionBar({super.key});

  @override
  Widget build(BuildContext context) {
    final isBuild = context.select<SessionState, bool>(
      (s) =>
          s.profiles.active?.communicationMode == CommunicationMode.build,
    );
    return isBuild ? const BuildStripBar() : const MessageBar();
  }
}

/// The Build-mode composition surface (Phase 3 of the modes plan): the
/// visible, ordered phrase strip plus Clear and a prominent Speak button.
///
/// Speech happens only from Speak — every other control here is silent by
/// construction. Strip units are large targets; each announces itself to
/// screen readers when added, removed, or spoken.
class BuildStripBar extends StatelessWidget {
  const BuildStripBar({super.key});

  @override
  Widget build(BuildContext context) {
    final session = context.watch<SessionState>();
    final theme = Theme.of(context);
    final strip = session.buildStrip;
    final max = session.buildMax;
    final hasUnits = strip.isNotEmpty;

    return Container(
      decoration: BoxDecoration(
        color: theme.colorScheme.surfaceContainer,
        border: Border(top: BorderSide(color: theme.dividerColor)),
      ),
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 8),
      child: SafeArea(
        top: false,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Semantics(
              label: hasUnits
                  ? 'Phrase: ${strip.map((e) => e.text).join(', ')}. '
                        '${strip.length} of $max symbols.'
                  : 'Phrase strip is empty. Tap symbols to add them.',
              child: Container(
                constraints: const BoxConstraints(minHeight: 56),
                padding: const EdgeInsets.symmetric(
                  horizontal: 4,
                  vertical: 6,
                ),
                child: hasUnits
                    ? Wrap(
                        spacing: 8,
                        runSpacing: 8,
                        children: [
                          for (var i = 0; i < strip.length; i++)
                            _StripChip(index: i, text: strip[i].text),
                        ],
                      )
                    : Text(
                        'Tap symbols to build a phrase…',
                        style: theme.textTheme.bodyMedium?.copyWith(
                          color: theme.hintColor,
                        ),
                      ),
              ),
            ),
            if (session.buildNotice != null)
              Padding(
                padding: const EdgeInsets.only(top: 2),
                child: Text(
                  session.buildNotice!,
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: theme.colorScheme.error,
                  ),
                ),
              ),
            const SizedBox(height: 4),
            Row(
              children: [
                Expanded(
                  child: Text(
                    hasUnits ? '${strip.length} of $max' : 'Max $max symbols',
                    style: theme.textTheme.bodySmall?.copyWith(
                      color: theme.hintColor,
                    ),
                  ),
                ),
                TextButton(
                  onPressed: hasUnits ? session.buildClear : null,
                  child: const Text('Clear'),
                ),
                const SizedBox(width: 8),
                FilledButton.icon(
                  onPressed: hasUnits ? session.buildSpeak : null,
                  icon: const Icon(Icons.volume_up),
                  label: const Padding(
                    padding: EdgeInsets.symmetric(
                      horizontal: 12,
                      vertical: 8,
                    ),
                    child: Text('Speak', style: TextStyle(fontSize: 17)),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

/// One strip unit. Tapping the whole chip removes it (tap-to-remove); the
/// semantic label says exactly that so screen-reader users get the same
/// affordance.
class _StripChip extends StatelessWidget {
  const _StripChip({required this.index, required this.text});

  final int index;
  final String text;

  @override
  Widget build(BuildContext context) {
    final session = context.read<SessionState>();
    final scheme = Theme.of(context).colorScheme;
    return Semantics(
      key: ValueKey('build-strip-$index'),
      button: true,
      label: "Remove '$text' from phrase",
      child: InkWell(
        borderRadius: BorderRadius.circular(14),
        onTap: () => session.buildRemoveAt(index),
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
          decoration: BoxDecoration(
            color: scheme.primaryContainer,
            borderRadius: BorderRadius.circular(14),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(text, style: const TextStyle(fontSize: 16)),
              const SizedBox(width: 6),
              const Icon(Icons.close, size: 16),
            ],
          ),
        ),
      ),
    );
  }
}
