import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../models/word.dart';
import '../state/session_state.dart';
import '../widgets/message_bar.dart';
import '../widgets/word_button.dart';

/// Inside a category folder: tap a word to speak it and add it to the
/// message bar (2nd tap). The message bar stays visible so sentences can
/// be finished and replayed without leaving the folder.
class CategoryScreen extends StatelessWidget {
  const CategoryScreen({super.key, required this.folderId});

  final String folderId;

  @override
  Widget build(BuildContext context) {
    final pack = context.select<SessionState, LanguagePack>((s) => s.pack);
    final scale = context.select<SessionState, double>((s) => s.buttonScale);
    final unlockedLevel = context.select<SessionState, int>(
      (s) => s.unlockedLevel,
    );
    final session = context.read<SessionState>();
    final folder = pack.folders[folderId];
    if (folder == null) {
      return Scaffold(
        appBar: AppBar(),
        body: const Center(child: Text('Unknown folder')),
      );
    }

    return Scaffold(
      appBar: AppBar(title: Text('${folder.emoji} ${folder.label}')),
      body: Column(
        children: [
          Expanded(
            child: GridView.count(
              crossAxisCount: 4,
              padding: const EdgeInsets.all(8),
              childAspectRatio: 0.92,
              children: [
                // Locked words keep their slot instead of being filtered out:
                // folder order is a motor pattern too, so the words that ARE
                // shown must not slide up when a level is locked.
                for (final word in folder.words)
                  if (!word.visibleAt(unlockedLevel))
                    const SizedBox.shrink()
                  else
                    WordButton(
                      item: word,
                      scale: scale,
                      hasSymbol: session.symbols.hasSymbol(word.id),
                      onTap: () => session.tapWord(word),
                    ),
              ],
            ),
          ),
          const MessageBar(),
        ],
      ),
    );
  }
}
