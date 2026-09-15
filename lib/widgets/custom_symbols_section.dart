import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../models/word.dart';
import '../services/word_finder.dart';
import '../state/session_state.dart';
import 'pick_button_image.dart';
import 'symbol_image.dart';

/// Custom symbols for the caregiver hub: search any word or quick phrase
/// and give it a personal image for the active profile — a photo of their
/// own cup, a family picture for "grandma". The standard board is shared,
/// so these overrides live per profile and never change what other
/// profiles see. Removing an override restores the standard symbol.
class CustomSymbolsSection extends StatefulWidget {
  const CustomSymbolsSection({super.key, required this.refresh});

  final VoidCallback refresh;

  @override
  State<CustomSymbolsSection> createState() => _CustomSymbolsSectionState();
}

class _CustomSymbolsSectionState extends State<CustomSymbolsSection> {
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
    final profile = session.profiles.active;
    if (profile == null) {
      return const Padding(
        padding: EdgeInsets.all(16),
        child: Text('Add a communicator profile first.'),
      );
    }
    final query = _query.trim();
    final hits = findWords(session.pack, query);
    const maxShown = 20;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(12, 0, 12, 8),
          child: Text(
            'Give ${profile.name} a personal image for any word or quick '
            'phrase. It only changes their board — other profiles keep the '
            'standard symbols.',
            style: const TextStyle(fontSize: 13),
          ),
        ),
        Card(
          child: Padding(
            padding: const EdgeInsets.all(12),
            child: TextField(
              controller: _controller,
              textInputAction: TextInputAction.search,
              decoration: const InputDecoration(
                labelText: 'Search words and phrases',
                hintText: 'Type a label…',
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
                    child: Text('No words or phrases match that search.'),
                  )
                : Column(
                    children: [
                      for (final hit in hits.take(maxShown))
                        _hitTile(session, profile.id, hit),
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

  Widget _hitTile(SessionState session, String profileId, WordMatch hit) {
    final item = hit.item;
    final override = session.symbolOverrides.imageFor(profileId, item.id);
    return ListTile(
      dense: true,
      leading: SymbolImage(
        item: item,
        hasSymbol: session.symbols.hasSymbol(item.id),
        overrideData: override,
        size: 32,
      ),
      title: Text(item.label),
      subtitle: Text(
        '${hit.location}${override != null ? ' · custom image' : ''}',
      ),
      trailing: override != null
          ? IconButton(
              tooltip: 'Restore standard symbol',
              icon: const Icon(Icons.restore_outlined),
              onPressed: () async {
                await session.symbolOverrides.remove(profileId, item.id);
                session.symbolsChanged();
                widget.refresh();
              },
            )
          : TextButton(
              onPressed: () => _setImage(session, profileId, item),
              child: const Text('Set image'),
            ),
    );
  }

  Future<void> _setImage(
    SessionState session,
    String profileId,
    BoardItem item,
  ) async {
    String? prepared;
    try {
      prepared = await pickButtonImage();
    } on ButtonImageException catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text(e.message)));
      }
      return;
    }
    if (prepared == null) return; // user cancelled
    await session.symbolOverrides.set(profileId, item.id, prepared);
    session.symbolsChanged();
    widget.refresh();
  }
}
