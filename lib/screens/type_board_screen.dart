import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../app_config.dart';
import '../services/history_service.dart';
import '../services/prediction_service.dart';
import '../state/session_state.dart';
import '../widgets/tts_banner.dart';
import 'caregiver_screen.dart';
import 'settings_screen.dart';

/// The Type-mode home screen (Phase 4 of the modes plan): a real text
/// keyboard, a deterministic on-device prediction row, saved phrases,
/// message history, and one prominent explicit Speak button.
///
/// Contracts, all pinned by tests:
/// * NOTHING speaks until the communicator presses Speak — typing,
///   tapping a prediction, tapping a saved phrase, or tapping a history
///   entry never touches the TTS layer.
/// * DOCUMENTED CHOICE — tapping a saved phrase FILLS the text field (it
///   does not speak). Type mode's loop is "type or choose → edit →
///   speak": a phrase tap is a composition shortcut, not a speak action,
///   and the communicator can edit the filled text before pressing Speak.
/// * DOCUMENTED CHOICE — tapping a history entry REFILLS the text field
///   (it does not speak). "Replay with speech" is refill + Speak, keeping
///   speech behind exactly one intentional action.
/// * DOCUMENTED CHOICE — Speak keeps the text in the field so the message
///   can be repeated or edited; nothing is ever discarded silently. The
///   Clear control empties the field explicitly.
/// * Prediction learns only from intentionally-spoken messages, per
///   profile, fully on-device. Drafts and keystrokes never leave the
///   device and never feed the model; only the final text passed to Speak
///   may reach cloud synthesis.
/// * Access settings are honored through [SessionState.buttonScale], the
///   same hook [HomeBoardScreen] uses: type size and minimum touch
///   targets scale together. (The codebase has no separate high-contrast
///   setting; the Material3 theme applies throughout.)
class TypeBoardScreen extends StatefulWidget {
  const TypeBoardScreen({super.key, this.vocabOverride});

  /// Injected 10k-vocabulary labels. Production passes nothing and the
  /// screen loads the bundled asset via the session; tests inject stubs
  /// so no asset bundle is needed.
  final List<VocabLabel>? vocabOverride;

  @override
  State<TypeBoardScreen> createState() => _TypeBoardScreenState();
}

class _TypeBoardScreenState extends State<TypeBoardScreen> {
  final TextEditingController _controller = TextEditingController();
  final FocusNode _focus = FocusNode();

  List<VocabLabel> _vocab = const [];
  List<String> _suggestions = const [];
  bool _canSpeak = false;

  @override
  void initState() {
    super.initState();
    _controller.addListener(_onTextChanged);
    _loadVocab();
  }

  Future<void> _loadVocab() async {
    final override = widget.vocabOverride;
    if (override != null) {
      _vocab = override;
    } else {
      final session = context.read<SessionState>();
      _vocab = await session.vocabLabelsFor(session.currentLocale);
    }
    if (mounted) _refreshSuggestions();
  }

  void _onTextChanged() {
    _refreshSuggestions();
  }

  void _refreshSuggestions() {
    final session = context.read<SessionState>();
    final profileId = session.profiles.active?.id ?? '';
    final suggestions = session.prediction.suggest(
      profileId: profileId,
      text: _controller.text,
      locale: session.currentLocale,
      vocab: _vocab,
    );
    if (!mounted) return;
    setState(() {
      _suggestions = suggestions;
      _canSpeak = _controller.text.trim().isNotEmpty;
    });
  }

  /// Tap a prediction chip: complete the current word locally. This is
  /// composition, never speech.
  void _applySuggestion(String word) {
    final text = _controller.text;
    final String next;
    if (text.trim().isEmpty) {
      next = '$word ';
    } else if (RegExp(r'\s$').hasMatch(text)) {
      next = '$text$word ';
    } else {
      // Replace the partial word being typed.
      final idx = text.lastIndexOf(RegExp(r'\s'));
      next = idx < 0 ? '$word ' : '${text.substring(0, idx + 1)}$word ';
    }
    _controller.value = TextEditingValue(
      text: next,
      selection: TextSelection.collapsed(offset: next.length),
    );
    // The controller listener refreshes suggestions + Speak state.
  }

  /// The one and only speech action on this screen.
  Future<void> _speak() async {
    final text = _controller.text;
    if (text.trim().isEmpty) return;
    await context.read<SessionState>().typeSpeak(text);
    // typeSpeak notifies; refresh suggestions in case the spoken message
    // changed the learned ranking.
    _refreshSuggestions();
  }

  void _clearField() {
    _controller.clear();
    _focus.requestFocus();
  }

  void _openPhrases() {
    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      builder: (ctx) => _SavedPhrasesSheet(
        onSelect: (phrase) {
          _fillField(phrase);
          Navigator.of(context).pop();
        },
      ),
    ).then((_) {
      if (mounted) _focus.requestFocus();
    });
  }

  void _openHistory() {
    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      builder: (ctx) => _TypeHistorySheet(
        onSelect: (text) {
          _fillField(text);
          Navigator.of(context).pop();
        },
      ),
    ).then((_) {
      if (mounted) _focus.requestFocus();
    });
  }

  void _fillField(String text) {
    _controller.value = TextEditingValue(
      text: text,
      selection: TextSelection.collapsed(offset: text.length),
    );
  }

  @override
  void dispose() {
    _controller.dispose();
    _focus.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final scale = context.select<SessionState, double>((s) => s.buttonScale);
    final scheme = Theme.of(context).colorScheme;

    return Scaffold(
      appBar: AppBar(
        title: Text(AppConfig.appDisplayName),
        actions: [
          IconButton(
            tooltip: 'Caregiver',
            icon: const Icon(Icons.family_restroom),
            onPressed: () => Navigator.of(
              context,
            ).push(MaterialPageRoute(builder: (_) => const CaregiverScreen())),
          ),
          IconButton(
            tooltip: 'Settings',
            icon: const Icon(Icons.settings),
            onPressed: () => Navigator.of(
              context,
            ).push(MaterialPageRoute(builder: (_) => const SettingsScreen())),
          ),
        ],
      ),
      body: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          const TtsBanner(),
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 12, 16, 0),
            child: Semantics(
              label: 'Type your message',
              textField: true,
              child: TextField(
                key: const ValueKey('type-field'),
                controller: _controller,
                focusNode: _focus,
                autofocus: true,
                minLines: 2,
                maxLines: 4,
                textCapitalization: TextCapitalization.sentences,
                style: TextStyle(fontSize: 20 * scale),
                decoration: InputDecoration(
                  labelText: 'Type your message',
                  hintText: 'Type here, then press Speak',
                  border: const OutlineInputBorder(),
                  contentPadding: EdgeInsets.all(16 * scale),
                  suffixIcon: _canSpeak
                      ? IconButton(
                          key: const ValueKey('type-clear'),
                          tooltip: 'Clear text',
                          icon: const Icon(Icons.clear),
                          onPressed: _clearField,
                        )
                      : null,
                ),
              ),
            ),
          ),
          // Prediction row: learned-first, vocab-fallback suggestions.
          // Tapping a chip edits the field — it never speaks.
          if (_suggestions.isNotEmpty)
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 8, 16, 0),
              child: Semantics(
                label: 'Word predictions',
                child: Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  children: [
                    for (final word in _suggestions)
                      ActionChip(
                        key: ValueKey('type-predict-$word'),
                        label: Padding(
                          padding: EdgeInsets.symmetric(
                            vertical: 8 * scale,
                            horizontal: 4 * scale,
                          ),
                          child: Text(
                            word,
                            style: TextStyle(fontSize: 17 * scale),
                          ),
                        ),
                        onPressed: () => _applySuggestion(word),
                      ),
                  ],
                ),
              ),
            ),
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 12, 16, 0),
            child: FilledButton.icon(
              key: const ValueKey('type-speak'),
              onPressed: _canSpeak ? _speak : null,
              icon: const Icon(Icons.volume_up),
              label: Padding(
                padding: EdgeInsets.symmetric(vertical: 12 * scale),
                child: Text(
                  'Speak',
                  style: TextStyle(fontSize: 22 * scale),
                ),
              ),
              style: FilledButton.styleFrom(
                minimumSize: Size(double.infinity, 60 * scale),
              ),
            ),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 8, 16, 0),
            child: Row(
              children: [
                Expanded(
                  child: OutlinedButton.icon(
                    key: const ValueKey('type-phrases-button'),
                    onPressed: _openPhrases,
                    icon: const Icon(Icons.bookmark_outline),
                    label: Padding(
                      padding: EdgeInsets.symmetric(vertical: 10 * scale),
                      child: Text(
                        'Saved phrases',
                        style: TextStyle(fontSize: 16 * scale),
                      ),
                    ),
                    style: OutlinedButton.styleFrom(
                      minimumSize: Size(0, 52 * scale),
                    ),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: OutlinedButton.icon(
                    key: const ValueKey('type-history-button'),
                    onPressed: _openHistory,
                    icon: const Icon(Icons.history),
                    label: Padding(
                      padding: EdgeInsets.symmetric(vertical: 10 * scale),
                      child: Text(
                        'History',
                        style: TextStyle(fontSize: 16 * scale),
                      ),
                    ),
                    style: OutlinedButton.styleFrom(
                      minimumSize: Size(0, 52 * scale),
                    ),
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 8),
          Expanded(
            child: SingleChildScrollView(
              padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
              child: Text(
                'Predictions learn from messages spoken in this profile '
                'and stay on this device. Nothing is spoken until you '
                'press Speak.',
                style: TextStyle(
                  fontSize: 13 * scale,
                  color: scheme.onSurfaceVariant,
                ),
                textAlign: TextAlign.center,
              ),
            ),
          ),
        ],
      ),
    );
  }

}

/// Saved-phrases picker: every phrase-type [BoardItem] in the pack.
///
/// DOCUMENTED CHOICE — tapping a phrase FILLS the text field; it does
/// not speak. The communicator edits (or not) and presses Speak.
class _SavedPhrasesSheet extends StatelessWidget {
  const _SavedPhrasesSheet({required this.onSelect});

  final ValueChanged<String> onSelect;

  @override
  Widget build(BuildContext context) {
    final session = context.read<SessionState>();
    final phrases = session.pack.phrases;
    return SafeArea(
      child: DraggableScrollableSheet(
        expand: false,
        initialChildSize: 0.7,
        minChildSize: 0.4,
        maxChildSize: 0.95,
        builder: (ctx, scrollController) => Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const SizedBox(height: 8),
            Center(
              child: Container(
                width: 40,
                height: 4,
                decoration: BoxDecoration(
                  color: Theme.of(context).dividerColor,
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
            ),
            const Padding(
              padding: EdgeInsets.fromLTRB(16, 12, 16, 4),
              child: Text(
                'Saved phrases',
                style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
              ),
            ),
            const Padding(
              padding: EdgeInsets.fromLTRB(16, 0, 16, 8),
              child: Text(
                'Tap a phrase to put it in the text field. Nothing speaks '
                'until you press Speak.',
                style: TextStyle(fontSize: 13),
              ),
            ),
            Expanded(
              child: phrases.isEmpty
                  ? const Center(
                      child: Padding(
                        padding: EdgeInsets.all(24),
                        child: Text('No saved phrases in this language yet.'),
                      ),
                    )
                  : ListView.separated(
                      controller: scrollController,
                      itemCount: phrases.length,
                      separatorBuilder: (_, _) => const Divider(height: 1),
                      itemBuilder: (ctx2, i) {
                        final phrase = phrases[i];
                        return ListTile(
                          key: ValueKey('type-phrase-$i'),
                          leading: const Icon(Icons.bookmark_outline),
                          title: Text(phrase.label),
                          onTap: () => onSelect(phrase.label),
                        );
                      },
                    ),
            ),
          ],
        ),
      ),
    );
  }
}

/// Message-history picker for the ACTIVE profile only.
///
/// DOCUMENTED CHOICE — tapping an entry REFILLS the text field; it does
/// not speak. Refill + Speak replays a message with speech behind exactly
/// one intentional action.
class _TypeHistorySheet extends StatelessWidget {
  const _TypeHistorySheet({required this.onSelect});

  final ValueChanged<String> onSelect;

  @override
  Widget build(BuildContext context) {
    final session = context.read<SessionState>();
    final List<HistoryEntry> entries = session.history.entries;
    return SafeArea(
      child: DraggableScrollableSheet(
        expand: false,
        initialChildSize: 0.7,
        minChildSize: 0.4,
        maxChildSize: 0.95,
        builder: (ctx, scrollController) => Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const SizedBox(height: 8),
            Center(
              child: Container(
                width: 40,
                height: 4,
                decoration: BoxDecoration(
                  color: Theme.of(context).dividerColor,
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
            ),
            const Padding(
              padding: EdgeInsets.fromLTRB(16, 12, 16, 4),
              child: Text(
                'Message history',
                style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
              ),
            ),
            const Padding(
              padding: EdgeInsets.fromLTRB(16, 0, 16, 8),
              child: Text(
                'Tap a message to put it back in the text field. Nothing '
                'speaks until you press Speak.',
                style: TextStyle(fontSize: 13),
              ),
            ),
            Expanded(
              child: entries.isEmpty
                  ? const Center(
                      child: Padding(
                        padding: EdgeInsets.all(24),
                        child: Text(
                          'Nothing spoken yet. Messages you speak with the '
                          'Speak button will appear here.',
                        ),
                      ),
                    )
                  : ListView.separated(
                      controller: scrollController,
                      itemCount: entries.length,
                      separatorBuilder: (_, _) => const Divider(height: 1),
                      itemBuilder: (ctx2, i) {
                        final entry = entries[i];
                        return ListTile(
                          key: ValueKey('type-history-entry-$i'),
                          leading: const Icon(Icons.history),
                          title: Text(
                            entry.text,
                            maxLines: 2,
                            overflow: TextOverflow.ellipsis,
                          ),
                          subtitle: Text(
                            _relativeTime(entry.spokenAt),
                            style: Theme.of(context).textTheme.bodySmall,
                          ),
                          onTap: () => onSelect(entry.text),
                        );
                      },
                    ),
            ),
          ],
        ),
      ),
    );
  }
}

String _relativeTime(DateTime when) {
  final diff = DateTime.now().difference(when);
  if (diff.inMinutes < 1) return 'just now';
  if (diff.inHours < 1) return '${diff.inMinutes}m ago';
  if (diff.inDays < 1) return '${diff.inHours}h ago';
  if (diff.inDays < 7) return '${diff.inDays}d ago';
  final d = when.toLocal();
  return '${d.month}/${d.day}/${d.year}';
}
