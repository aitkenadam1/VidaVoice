import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../models/calling_safety.dart';
import '../models/dashboard.dart';
import '../models/word.dart';
import '../services/profile_service.dart';
import '../state/session_state.dart';
import '../theme/onevoz_theme.dart';
import '../widgets/dashboard_tile.dart';
import '../widgets/safety_contact_avatar.dart';
import '../widgets/word_button.dart';

/// Caregiver-side live preview of the communicator's board.
///
/// Renders the ACTIVE profile's home board exactly as the communicator
/// side shows it — personal dashboard when one is enabled, the full word
/// grid otherwise, folder pages, Mom/Dad call buttons, and the sentence
/// strip — so a caregiver customizing the dashboard, words, or phrases
/// can see the result without switching modes back and forth.
///
/// Preview rules (pinned by tests):
/// * Taps behave like the real board, including speaking with the
///   profile's voice, so the caregiver hears what the child produces.
/// * NOTHING here mutates the session: no sentence history, no usage
///   counts, no activity log, no prediction learning. The composed
///   sentence lives only in this screen and dies with it.
/// * Call buttons never place a call — they speak the contact's name
///   and say so.
class BoardPreviewScreen extends StatefulWidget {
  const BoardPreviewScreen({super.key});

  @override
  State<BoardPreviewScreen> createState() => _BoardPreviewScreenState();
}

class _BoardPreviewScreenState extends State<BoardPreviewScreen> {
  /// Local sentence strip (labels/text in tap order). Preview-only state.
  final List<String> _strip = [];

  /// Whether the preview currently shows the personal dashboard (vs the
  /// full grid). Mirrors the real board's session-only toggle.
  bool? _showDashboard;

  bool _dashboardAvailable(SessionState session) {
    final id = session.profiles.active?.id;
    if (id == null) return false;
    final dashboard = session.dashboards.forProfile(id);
    return dashboard != null && dashboard.enabled && dashboard.cells.isNotEmpty;
  }

  bool get _isBuild =>
      context.read<SessionState>().profiles.active?.communicationMode ==
      CommunicationMode.build;

  void _speak(String text) {
    if (text.isEmpty) return;
    context.read<SessionState>().tts.speak(text);
  }

  /// Mirror of the real board's tap behavior, minus every side effect
  /// beyond speech itself.
  void _tapWordItem(BoardItem item) {
    if (item.type == BoardItemType.folder) return;
    if (item.type == BoardItemType.phrase) {
      // Phrases are atomic: in Build mode they join the strip as one
      // unit; in Tap mode they speak whole immediately.
      if (_isBuild) {
        _addToStrip(item.label);
      } else {
        _speak(item.label);
      }
      return;
    }
    if (_isBuild) {
      _addToStrip(item.label);
    } else {
      _speak(item.label);
      setState(() => _strip.add(item.label));
    }
  }

  void _addToStrip(String text) {
    final session = context.read<SessionState>();
    if (_strip.length >= session.buildMax) return;
    setState(() => _strip.add(text));
  }

  void _tapDashboardCell(SessionState session, DashboardCell cell) {
    final wordId = cell.wordId;
    if (wordId != null) {
      try {
        _tapWordItem(session.pack.wordById(wordId));
        return;
      } on Object {
        // Word vanished from the pack — fall through to stored text.
      }
    }
    final text = cell.customText;
    if (text.isEmpty) return;
    if (_isBuild) {
      _addToStrip(text);
    } else {
      _speak(text);
    }
  }

  void _speakStrip() {
    if (_strip.isEmpty) return;
    _speak(_strip.join(' '));
  }

  @override
  Widget build(BuildContext context) {
    final session = context.watch<SessionState>();
    final profile = session.profiles.active;
    return Theme(
      data: OneVozTheme.childTheme(),
      child: Scaffold(
        appBar: AppBar(
          title: Text(
            profile == null ? 'Preview' : 'Preview — ${profile.name}',
          ),
          actions: [
            IconButton(
              icon: const Icon(Icons.close),
              tooltip: 'Close preview',
              onPressed: () => Navigator.of(context).pop(),
            ),
          ],
        ),
        body: profile == null
            ? const Center(
                child: Padding(
                  padding: EdgeInsets.all(24),
                  child: Text(
                    'Add a communicator profile first — the preview '
                    'belongs to a profile.',
                    textAlign: TextAlign.center,
                  ),
                ),
              )
            : _body(session),
      ),
    );
  }

  Widget _body(SessionState session) {
    final profile = session.profiles.active!;
    final dashboardAvailable = _dashboardAvailable(session);
    final showDashboard = _showDashboard ?? dashboardAvailable;
    return Column(
      children: [
        Container(
          width: double.infinity,
          color: Theme.of(context).colorScheme.primaryContainer,
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
          child: Text(
            profile.communicationMode == CommunicationMode.type
                ? 'Type mode: ${profile.name} starts on a keyboard. This '
                      'previews their word board and dashboard. Taps speak '
                      'here — nothing is saved or changed.'
                : 'This is what ${profile.name} sees. Taps speak here — '
                      'nothing is saved or changed.',
            style: const TextStyle(fontSize: 13),
          ),
        ),
        Expanded(
          child: showDashboard ? _dashboardGrid(session) : _fullGrid(session),
        ),
        if (dashboardAvailable && showDashboard)
          TextButton.icon(
            onPressed: () => setState(() => _showDashboard = false),
            icon: const Icon(Icons.grid_view),
            label: const Text('Show all words'),
          )
        else if (dashboardAvailable)
          TextButton.icon(
            onPressed: () => setState(() => _showDashboard = true),
            icon: const Icon(Icons.dashboard),
            label: const Text('Back to my board'),
          ),
        _callArea(session),
        _stripBar(session),
      ],
    );
  }

  Widget _fullGrid(SessionState session) {
    final pack = session.pack;
    return GridView.count(
      crossAxisCount: pack.gridColumns,
      padding: const EdgeInsets.all(8),
      childAspectRatio: 0.92,
      children: [
        for (var r = 0; r < pack.gridRows; r++)
          for (var c = 0; c < pack.gridColumns; c++) _cell(session, r, c),
      ],
    );
  }

  Widget _cell(SessionState session, int row, int col) {
    final pack = session.pack;
    final item = pack.itemAt(row, col, unlockedLevel: session.unlockedLevel);
    if (item == null) return const SizedBox.shrink();
    return WordButton(
      item: item,
      scale: session.buttonScale,
      hasSymbol: session.symbols.hasSymbol(item.id),
      imageOverride: session.symbolOverrideFor(item.id),
      onTap: () {
        if (item.isFolder) {
          Navigator.of(context).push(
            MaterialPageRoute(
              builder: (_) => _PreviewCategoryScreen(
                folderId: item.id,
                strip: _strip,
                onWordTap: _tapWordItem,
                onStripChanged: () => setState(() {}),
              ),
            ),
          );
        } else {
          _tapWordItem(item);
        }
      },
    );
  }

  Widget _dashboardGrid(SessionState session) {
    final profileId = session.profiles.active?.id;
    final dashboard = profileId == null
        ? null
        : session.dashboards.forProfile(profileId);
    if (dashboard == null || dashboard.cells.isEmpty) {
      return const Center(child: Text('This dashboard is empty.'));
    }
    final pack = session.pack;
    return GridView.count(
      crossAxisCount: pack.gridColumns,
      padding: const EdgeInsets.all(8),
      childAspectRatio: 0.92,
      children: [
        for (final cell in dashboard.cells) _dashboardCell(session, cell),
      ],
    );
  }

  Widget _dashboardCell(SessionState session, DashboardCell cell) {
    final wordId = cell.wordId;
    if (wordId != null) {
      try {
        final item = session.pack.wordById(wordId);
        return WordButton(
          item: item,
          scale: session.buttonScale,
          hasSymbol: session.symbols.hasSymbol(item.id),
          imageOverride: session.symbolOverrideFor(item.id),
          onTap: () => _tapDashboardCell(session, cell),
        );
      } on Object {
        // Word vanished from a newer pack — render the stored text below.
      }
    }
    return DashboardTile(
      label: cell.label.isNotEmpty ? cell.label : cell.speakText,
      emoji: cell.emoji,
      imageData: cell.imageData,
      color: cell.color,
      scale: session.buttonScale,
      onTap: () => _tapDashboardCell(session, cell),
    );
  }

  /// Mom/Dad call buttons as the child sees them. Tapping speaks the
  /// name (the real board's first step) and announces that the preview
  /// places no call.
  Widget _callArea(SessionState session) {
    final profile = session.profiles.active;
    if (profile == null) return const SizedBox.shrink();
    final contacts = [
      for (final c in profile.contacts)
        if (c.kind == 'mom' || c.kind == 'dad') c,
    ];
    if (contacts.isEmpty) return const SizedBox.shrink();
    return Padding(
      padding: const EdgeInsets.fromLTRB(12, 4, 12, 8),
      child: Wrap(
        spacing: 8,
        runSpacing: 8,
        alignment: WrapAlignment.center,
        children: [for (final c in contacts) _callButton(session, c)],
      ),
    );
  }

  Widget _callButton(SessionState session, SafetyContact contact) {
    final label = contact.name.isNotEmpty ? contact.name : 'Call';
    return InkWell(
      onTap: () {
        _speak(contact.name);
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Preview only — no call is placed.'),
            duration: Duration(seconds: 2),
          ),
        );
      },
      borderRadius: BorderRadius.circular(20),
      child: Container(
        constraints: const BoxConstraints(minHeight: 96),
        decoration: BoxDecoration(
          color: Theme.of(context).colorScheme.primaryContainer,
          borderRadius: BorderRadius.circular(20),
        ),
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 10),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          mainAxisSize: MainAxisSize.min,
          children: [
            SafetyContactAvatar(contact: contact, radius: 28),
            const SizedBox(height: 4),
            Text(
              label,
              style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
          ],
        ),
      ),
    );
  }

  /// The sentence strip: local, functional (compose / backspace /
  /// clear / speak), and discarded when the preview closes.
  Widget _stripBar(SessionState session) {
    final isBuild = _isBuild;
    return Container(
      color: Theme.of(context).colorScheme.surfaceContainerHighest,
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      child: Row(
        children: [
          Expanded(
            child: Text(
              _strip.isEmpty
                  ? (isBuild
                        ? '${session.buildMax} words max — tap words to '
                              'build a sentence…'
                        : 'Tap words to build a sentence…')
                  : _strip.join(' '),
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(fontSize: 16),
            ),
          ),
          IconButton(
            icon: const Icon(Icons.backspace_outlined),
            tooltip: 'Delete last word',
            onPressed: _strip.isEmpty
                ? null
                : () => setState(() => _strip.removeLast()),
          ),
          TextButton(
            onPressed: _strip.isEmpty
                ? null
                : () => setState(() => _strip.clear()),
            child: const Text('Clear'),
          ),
          FilledButton.icon(
            onPressed: _strip.isEmpty ? null : _speakStrip,
            icon: const Icon(Icons.volume_up),
            label: const Text('Speak'),
          ),
        ],
      ),
    );
  }
}

/// A folder page inside the preview: same tiles, same tap behavior,
/// writing into the preview's shared local strip.
class _PreviewCategoryScreen extends StatelessWidget {
  const _PreviewCategoryScreen({
    required this.folderId,
    required this.strip,
    required this.onWordTap,
    required this.onStripChanged,
  });

  final String folderId;
  final List<String> strip;
  final void Function(BoardItem) onWordTap;
  final VoidCallback onStripChanged;

  @override
  Widget build(BuildContext context) {
    final session = context.watch<SessionState>();
    final pack = session.pack;
    final folder = pack.folders[folderId];
    if (folder == null) {
      return Scaffold(
        appBar: AppBar(),
        body: const Center(child: Text('Unknown folder')),
      );
    }
    return Theme(
      data: OneVozTheme.childTheme(),
      child: Scaffold(
        appBar: AppBar(title: Text('${folder.emoji} ${folder.label}')),
        body: Column(
          children: [
            Expanded(
              child: GridView.count(
                crossAxisCount: 4,
                padding: const EdgeInsets.all(8),
                childAspectRatio: 0.92,
                children: [
                  for (final word in folder.words)
                    if (!word.visibleAt(session.unlockedLevel))
                      const SizedBox.shrink()
                    else
                      WordButton(
                        item: word,
                        scale: session.buttonScale,
                        hasSymbol: session.symbols.hasSymbol(word.id),
                        imageOverride: session.symbolOverrideFor(word.id),
                        onTap: () {
                          onWordTap(word);
                          onStripChanged();
                        },
                      ),
                ],
              ),
            ),
            Container(
              width: double.infinity,
              color: Theme.of(context).colorScheme.surfaceContainerHighest,
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
              child: Text(
                strip.isEmpty
                    ? 'Tap words to build a sentence…'
                    : strip.join(' '),
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(fontSize: 16),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
