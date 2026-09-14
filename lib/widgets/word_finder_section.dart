import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../services/word_finder.dart';
import '../state/session_state.dart';

/// Word finder for the caregiver hub: with ~300 words nobody can find
/// anything by scanning. Type a label (current language, case-insensitive)
/// and see where each match lives plus its vocabulary level. Read-only —
/// tapping a result just previews the word aloud; nothing changes.
class WordFinderSection extends StatefulWidget {
  const WordFinderSection({super.key});

  @override
  State<WordFinderSection> createState() => _WordFinderSectionState();
}

class _WordFinderSectionState extends State<WordFinderSection> {
  final _controller = TextEditingController();
  String _query = '';

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final session = context.watch<SessionState>();
    final query = _query.trim();
    final hits = findWords(session.pack, query);
    const maxShown = 20;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Card(
          child: Padding(
            padding: const EdgeInsets.all(12),
            child: TextField(
              controller: _controller,
              textInputAction: TextInputAction.search,
              decoration: const InputDecoration(
                labelText: 'Search words',
                hintText: 'Type a word label…',
                prefixIcon: Icon(Icons.search),
                border: OutlineInputBorder(),
              ),
              onChanged: (v) => setState(() => _query = v),
            ),
          ),
        ),
        if (query.isNotEmpty) ...[
          const SizedBox(height: 8),
          Card(
            child: hits.isEmpty
                ? const Padding(
                    padding: EdgeInsets.all(16),
                    child: Text('No words match that search.'),
                  )
                : Column(
                    children: [
                      for (final hit in hits.take(maxShown))
                        _hitTile(context, session, hit),
                      if (hits.length > maxShown)
                        Padding(
                          padding: const EdgeInsets.all(12),
                          child: Text(
                            '…and ${hits.length - maxShown} more — '
                            'keep typing to narrow it down.',
                            style: const TextStyle(fontSize: 13),
                          ),
                        ),
                    ],
                  ),
          ),
        ],
      ],
    );
  }

  Widget _hitTile(BuildContext context, SessionState session, WordMatch hit) {
    final hiddenNow = !hit.item.visibleAt(session.unlockedLevel);
    return ListTile(
      dense: true,
      leading: const Icon(Icons.text_fields_outlined),
      title: Text(hit.item.label),
      subtitle: Text(
        '${hit.location} · Level ${hit.item.level}'
        '${hiddenNow ? ' · hidden at the current level' : ''}',
      ),
      trailing: const Icon(Icons.volume_up_outlined),
      onTap: () => session.tts.speak(hit.item.label),
    );
  }
}
