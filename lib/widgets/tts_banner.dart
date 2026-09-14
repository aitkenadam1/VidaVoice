import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../state/session_state.dart';

/// Non-blocking "no voice engine" banner. Shown on the board screens when
/// TTS is unavailable (bare Fire tablets, missing voice data): the board
/// still works — words build sentences — but nothing can be spoken.
/// Dismissible per session; the text comes from the language pack.
class TtsBanner extends StatelessWidget {
  const TtsBanner({super.key});

  @override
  Widget build(BuildContext context) {
    final session = context.watch<SessionState>();
    if (session.ttsAvailable || session.ttsBannerDismissed) {
      return const SizedBox.shrink();
    }
    final theme = Theme.of(context);
    return Container(
      width: double.infinity,
      color: theme.colorScheme.errorContainer,
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
      child: Row(
        children: [
          Icon(
            Icons.volume_off_outlined,
            size: 20,
            color: theme.colorScheme.onErrorContainer,
          ),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              session.pack.ttsUnavailableBanner,
              style: theme.textTheme.bodySmall?.copyWith(
                color: theme.colorScheme.onErrorContainer,
              ),
            ),
          ),
          IconButton(
            tooltip: 'Dismiss',
            visualDensity: VisualDensity.compact,
            icon: Icon(
              Icons.close,
              size: 20,
              color: theme.colorScheme.onErrorContainer,
            ),
            onPressed: () => context.read<SessionState>().dismissTtsBanner(),
          ),
        ],
      ),
    );
  }
}
