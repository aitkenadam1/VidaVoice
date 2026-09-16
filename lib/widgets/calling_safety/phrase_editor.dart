import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../models/calling_safety.dart';
import '../../state/session_state.dart';

/// Phrase bank editor for the Calling & Safety hub and guided setup flow.
///
/// Phrases are what the communicator can say on a call. Placeholders like
/// {child_name} are filled in from the Emergency details below at call
/// time. Writes through [ProfileService.setCallPhrases]; the session's
/// onChanged wiring schedules the encrypted sync push automatically.
class PhraseBankEditor extends StatefulWidget {
  const PhraseBankEditor({super.key, required this.profileId, this.onChanged});

  final String profileId;
  final VoidCallback? onChanged;

  @override
  State<PhraseBankEditor> createState() => _PhraseBankEditorState();
}

class _PhraseBankEditorState extends State<PhraseBankEditor> {
  static int _idCounter = 0;
  bool _saving = false;

  List<CallPhrase> _phrases(SessionState session) {
    for (final p in session.profiles.profiles) {
      if (p.id == widget.profileId) return List.of(p.callPhrases);
    }
    return const [];
  }

  Future<void> _save(SessionState session, List<CallPhrase> phrases) async {
    setState(() => _saving = true);
    try {
      await session.profiles.setCallPhrases(widget.profileId, phrases);
    } finally {
      if (mounted) setState(() => _saving = false);
    }
    widget.onChanged?.call();
  }

  Future<void> _addDialog(SessionState session) async {
    final text = await _phraseDialog(context, null);
    if (text == null || text.trim().isEmpty || !mounted) return;
    final sessionNow = context.read<SessionState>();
    await _save(sessionNow, [
      ..._phrases(sessionNow),
      CallPhrase(
        id: 'cp-${DateTime.now().microsecondsSinceEpoch}-${_idCounter++}',
        text: text.trim(),
      ),
    ]);
  }

  Future<void> _editDialog(SessionState session, CallPhrase phrase) async {
    final text = await _phraseDialog(context, phrase);
    if (text == null || text.trim().isEmpty || !mounted) return;
    final sessionNow = context.read<SessionState>();
    await _save(sessionNow, [
      for (final p in _phrases(sessionNow))
        if (p.id == phrase.id) CallPhrase(id: p.id, text: text.trim()) else p,
    ]);
  }

  Future<void> _deleteDialog(SessionState session, CallPhrase phrase) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Remove phrase?'),
        content: Text(
          '\u201c${phrase.text}\u201d will be removed from the '
          'phrase bank.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(false),
            child: const Text('Keep'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(ctx).pop(true),
            child: const Text('Remove'),
          ),
        ],
      ),
    );
    if (confirmed != true || !mounted) return;
    final sessionNow = context.read<SessionState>();
    await _save(sessionNow, [
      for (final p in _phrases(sessionNow))
        if (p.id != phrase.id) p,
    ]);
  }

  Future<void> _restoreStarters(SessionState session) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Restore starter phrases?'),
        content: const Text(
          'This replaces the current phrase bank with the starter set. '
          'Your own phrases will be lost.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(ctx).pop(true),
            child: const Text('Restore'),
          ),
        ],
      ),
    );
    if (confirmed != true || !mounted) return;
    await _save(context.read<SessionState>(), defaultCallPhrases());
  }

  Future<void> _reorder(int oldIndex, int newIndex) async {
    final session = context.read<SessionState>();
    final phrases = _phrases(session);
    final moved = phrases.removeAt(oldIndex);
    phrases.insert(newIndex, moved);
    await _save(session, phrases);
  }

  @override
  Widget build(BuildContext context) {
    final session = context.watch<SessionState>();
    final phrases = _phrases(session);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const _PlaceholderHelpCard(),
        if (phrases.isEmpty)
          const Padding(
            padding: EdgeInsets.fromLTRB(12, 8, 12, 8),
            child: Text(
              'The phrase bank is empty. Add the sentences they should be '
              'able to say on a call — or restore the starter set.',
              style: TextStyle(fontSize: 13),
            ),
          )
        else
          ReorderableListView.builder(
            shrinkWrap: true,
            physics: const NeverScrollableScrollPhysics(),
            itemCount: phrases.length,
            // onReorderItem (not the deprecated onReorder) already adjusts
            // newIndex for the removed item — no manual correction needed.
            onReorderItem: _reorder,
            itemBuilder: (ctx, index) {
              final phrase = phrases[index];
              return ListTile(
                key: ValueKey(phrase.id),
                contentPadding: const EdgeInsets.symmetric(horizontal: 12),
                leading: const Icon(Icons.drag_handle),
                title: Text(phrase.text),
                trailing: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    IconButton(
                      tooltip: 'Edit phrase',
                      icon: const Icon(Icons.edit_outlined),
                      onPressed: _saving
                          ? null
                          : () => _editDialog(session, phrase),
                    ),
                    IconButton(
                      tooltip: 'Remove phrase',
                      icon: const Icon(Icons.delete_outline),
                      onPressed: _saving
                          ? null
                          : () => _deleteDialog(session, phrase),
                    ),
                  ],
                ),
                onTap: _saving ? null : () => _editDialog(session, phrase),
              );
            },
          ),
        Padding(
          padding: const EdgeInsets.fromLTRB(8, 4, 8, 0),
          child: Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              OutlinedButton.icon(
                icon: const Icon(Icons.add),
                label: const Text('Add phrase'),
                onPressed: _saving ? null : () => _addDialog(session),
              ),
              TextButton.icon(
                icon: const Icon(Icons.restart_alt, size: 18),
                label: const Text('Restore starter phrases'),
                onPressed: _saving ? null : () => _restoreStarters(session),
              ),
            ],
          ),
        ),
        if (_saving)
          const Padding(
            padding: EdgeInsets.fromLTRB(12, 8, 12, 0),
            child: LinearProgressIndicator(),
          ),
      ],
    );
  }
}

/// Add/edit dialog for one call phrase. Returns the phrase text, or null
/// when the caregiver cancels.
Future<String?> _phraseDialog(BuildContext context, CallPhrase? initial) {
  final controller = TextEditingController(text: initial?.text ?? '');
  return showDialog<String>(
    context: context,
    builder: (ctx) => AlertDialog(
      title: Text(initial == null ? 'Add phrase' : 'Edit phrase'),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          TextField(
            controller: controller,
            autofocus: true,
            maxLines: 3,
            minLines: 1,
            textCapitalization: TextCapitalization.sentences,
            decoration: const InputDecoration(
              labelText: 'Phrase',
              hintText: 'e.g. Hi, this is {child_name}. I need help.',
              border: OutlineInputBorder(),
            ),
            onSubmitted: (_) => Navigator.of(ctx).pop(controller.text),
          ),
          const SizedBox(height: 8),
          const Text(
            'You can use placeholders like {child_name} and {gps} — '
            'they are filled in automatically when the phrase is used. '
            'See the placeholder guide above.',
            style: TextStyle(fontSize: 12),
          ),
        ],
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(ctx).pop(),
          child: const Text('Cancel'),
        ),
        FilledButton(
          onPressed: () => Navigator.of(ctx).pop(controller.text),
          child: Text(initial == null ? 'Add' : 'Save'),
        ),
      ],
    ),
  );
}

/// Plain-language guide to the placeholders a phrase can contain. Static
/// reference — the actual filling-in happens at call time.
class _PlaceholderHelpCard extends StatelessWidget {
  const _PlaceholderHelpCard();

  static const _rows = [
    ('{child_name}', 'The child\u2019s name, from Emergency details below.'),
    ('{home_address}', 'The home address, from Emergency details below.'),
    (
      '{parent_name}',
      'The parent or caregiver name, from Emergency details below.',
    ),
    (
      '{parent_phone}',
      'The parent or caregiver phone, from Emergency details below.',
    ),
    (
      '{gps}',
      'Location is not available in this version — phrases show '
          '\u201clocation unavailable\u201d where {gps} appears.',
    ),
  ];

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(8, 4, 8, 8),
      child: Card(
        margin: EdgeInsets.zero,
        child: ExpansionTile(
          leading: const Icon(Icons.info_outline),
          title: const Text(
            'Phrase placeholders',
            style: TextStyle(fontWeight: FontWeight.w600, fontSize: 14),
          ),
          subtitle: const Text(
            'Words in {braces} fill in automatically',
            style: TextStyle(fontSize: 12),
          ),
          children: [
            for (final (token, explanation) in _rows)
              ListTile(
                dense: true,
                title: Text(
                  token,
                  style: const TextStyle(
                    fontFamily: 'monospace',
                    fontWeight: FontWeight.bold,
                    fontSize: 13,
                  ),
                ),
                subtitle: Text(
                  explanation,
                  style: const TextStyle(fontSize: 12),
                ),
              ),
            const Padding(
              padding: EdgeInsets.fromLTRB(16, 0, 16, 12),
              child: Text(
                'Example: \u201cHi, this is {child_name}. I\u2019m at '
                '{home_address}.\u201d becomes \u201cHi, this is Alex. '
                'I\u2019m at 123 Main St.\u201d when spoken.',
                style: TextStyle(fontSize: 12),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
