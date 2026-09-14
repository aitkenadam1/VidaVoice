import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../state/session_state.dart';
import 'history_sheet.dart';

/// Pinned bottom bar: the accumulated sentence plus Speak / Clear / Undo.
/// Visible on the home board and inside category folders.
class MessageBar extends StatelessWidget {
  const MessageBar({super.key});

  @override
  Widget build(BuildContext context) {
    final session = context.watch<SessionState>();
    final theme = Theme.of(context);
    final sentenceText = session.sentence.map((w) => w.label).join(' ');
    final hasWords = sentenceText.isNotEmpty;

    return Container(
      decoration: BoxDecoration(
        color: theme.colorScheme.surfaceContainer,
        border: Border(top: BorderSide(color: theme.dividerColor)),
      ),
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 8),
      child: SafeArea(
        top: false,
        child: Row(
          children: [
            Expanded(
              child: hasWords
                  ? SingleChildScrollView(
                      scrollDirection: Axis.horizontal,
                      child: Text(
                        sentenceText,
                        style: theme.textTheme.titleMedium,
                      ),
                    )
                  : Text(
                      'Tap words to build a sentence…',
                      style: theme.textTheme.bodyMedium?.copyWith(
                        color: theme.hintColor,
                      ),
                    ),
            ),
            IconButton(
              tooltip: 'Recent sentences',
              icon: const Icon(Icons.history_outlined),
              onPressed: () => showModalBottomSheet(
                context: context,
                showDragHandle: false,
                builder: (_) => const HistorySheet(),
              ),
            ),
            IconButton(
              tooltip: 'Undo last word',
              icon: const Icon(Icons.backspace_outlined),
              onPressed: hasWords ? session.undoLast : null,
            ),
            TextButton(
              onPressed: hasWords ? session.clearSentence : null,
              child: const Text('Clear'),
            ),
            const SizedBox(width: 4),
            FilledButton.icon(
              onPressed: hasWords ? () => session.speakSentence() : null,
              icon: const Icon(Icons.volume_up),
              label: const Text('Speak'),
            ),
          ],
        ),
      ),
    );
  }
}
