import 'dart:convert';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../models/dashboard.dart';
import '../services/obf_import_service.dart';
import '../services/word_finder.dart';
import '../state/session_state.dart';
import 'pick_button_image.dart';
import 'symbol_image.dart';

/// The caregiver's personal-dashboard editor: enable the dashboard as the
/// profile's home board, add/reorder/remove buttons, pull suggestions
/// from the most-used words, and import a board file from another AAC app.
class DashboardSection extends StatefulWidget {
  const DashboardSection({super.key, required this.refresh});

  final VoidCallback refresh;

  @override
  State<DashboardSection> createState() => _DashboardSectionState();
}

class _DashboardSectionState extends State<DashboardSection> {
  bool _busy = false;

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
    final dashboard = session.dashboards.forProfile(profile.id);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        if (_busy) const LinearProgressIndicator(),
        Padding(
          padding: const EdgeInsets.fromLTRB(12, 0, 12, 8),
          child: Text(
            'A personal board for ${profile.name} — you choose the words '
            'and phrases and arrange them freely. It can replace the '
            'standard home board; the standard board itself never changes.',
            style: const TextStyle(fontSize: 13),
          ),
        ),
        SwitchListTile(
          title: const Text('Use as home board'),
          subtitle: Text(
            dashboard != null && dashboard.enabled
                ? 'On — the dashboard replaces the standard board'
                : 'Off — the standard board is showing',
          ),
          value: dashboard?.enabled ?? false,
          onChanged: (v) async {
            final d = session.dashboards.ensureFor(
              profile.id,
              name: profile.name,
            );
            d.enabled = v;
            await session.dashboards.save(d);
            widget.refresh();
          },
        ),
        if (dashboard != null) ...[
          _suggestions(session, dashboard),
          _cellList(session, dashboard),
        ],
        Padding(
          padding: const EdgeInsets.all(8),
          child: Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              OutlinedButton.icon(
                icon: const Icon(Icons.add),
                label: const Text('Add words'),
                onPressed: () => _addWordsDialog(session, profile.id),
              ),
              OutlinedButton.icon(
                icon: const Icon(Icons.edit),
                label: const Text('Add custom'),
                onPressed: () => _addCustomDialog(session, profile.id),
              ),
              OutlinedButton.icon(
                icon: const Icon(Icons.upload_file),
                label: const Text('Import file'),
                onPressed: _busy
                    ? null
                    : () => _importFile(session, profile.id, profile.name),
              ),
              if (dashboard != null)
                TextButton.icon(
                  icon: const Icon(Icons.delete_outline),
                  label: const Text('Delete'),
                  onPressed: () => _deleteDialog(session, profile.id),
                ),
            ],
          ),
        ),
      ],
    );
  }

  // ---------------------------------------------------------- suggestions ---

  /// Most-used words that aren't on the dashboard yet, one tap to add.
  Widget _suggestions(SessionState session, PersonalDashboard dashboard) {
    final onBoard = {for (final c in dashboard.cells) c.wordId}..remove(null);
    final suggestions = <WordMatch>[];
    for (final entry in session.usage.top(10)) {
      if (suggestions.length >= 5) break;
      if (onBoard.contains(entry.key)) continue;
      try {
        final item = session.pack.wordById(entry.key);
        if (item.isFolder) continue;
        suggestions.add(WordMatch(item: item, location: '×${entry.value}'));
      } catch (_) {
        // Word left the pack — not suggestible.
      }
    }
    if (suggestions.isEmpty) return const SizedBox.shrink();
    return Padding(
      padding: const EdgeInsets.fromLTRB(12, 4, 12, 4),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            'Suggested from most-used words',
            style: TextStyle(fontWeight: FontWeight.bold, fontSize: 13),
          ),
          const SizedBox(height: 4),
          Wrap(
            spacing: 8,
            runSpacing: 4,
            children: [
              for (final s in suggestions)
                ActionChip(
                  avatar: const Icon(Icons.add, size: 16),
                  label: Text('${s.item.label} ${s.location}'),
                  onPressed: () async {
                    dashboard.cells.add(
                      DashboardCell(
                        id: session.dashboards.newCellId(dashboard),
                        wordId: s.item.id,
                        // Stored fallback: if the word ever leaves the
                        // pack, the tile still shows and speaks this.
                        label: s.item.label,
                      ),
                    );
                    await session.dashboards.save(dashboard);
                    widget.refresh();
                  },
                ),
            ],
          ),
        ],
      ),
    );
  }

  // ------------------------------------------------------------ cell list ---

  Widget _cellList(SessionState session, PersonalDashboard dashboard) {
    if (dashboard.cells.isEmpty) {
      return const Padding(
        padding: EdgeInsets.fromLTRB(12, 8, 12, 8),
        child: Text(
          'Empty — add words, add a custom button, or import a board file.',
          style: TextStyle(fontSize: 13, fontStyle: FontStyle.italic),
        ),
      );
    }
    return ReorderableListView.builder(
      shrinkWrap: true,
      physics: const NeverScrollableScrollPhysics(),
      itemCount: dashboard.cells.length,
      // onReorderItem (not the deprecated onReorder) already adjusts
      // newIndex for the removed item — no manual correction needed.
      onReorderItem: (oldIndex, newIndex) async {
        final cell = dashboard.cells.removeAt(oldIndex);
        dashboard.cells.insert(newIndex, cell);
        await session.dashboards.save(dashboard);
        widget.refresh();
      },
      itemBuilder: (context, index) {
        final cell = dashboard.cells[index];
        return ListTile(
          key: ValueKey(cell.id),
          dense: true,
          leading: _cellLeading(session, cell),
          title: Text(_cellLabel(session, cell)),
          subtitle: Text(_cellKind(session, cell)),
          trailing: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              if (cell.wordId == null)
                IconButton(
                  tooltip: 'Edit',
                  icon: const Icon(Icons.edit_outlined),
                  onPressed: () => _editCustomDialog(session, dashboard, index),
                ),
              IconButton(
                tooltip: 'Remove',
                icon: const Icon(Icons.remove_circle_outline),
                onPressed: () async {
                  dashboard.cells.removeAt(index);
                  await session.dashboards.save(dashboard);
                  widget.refresh();
                },
              ),
              ReorderableDragStartListener(
                index: index,
                child: const Padding(
                  padding: EdgeInsets.all(8),
                  child: Icon(Icons.drag_handle),
                ),
              ),
            ],
          ),
        );
      },
    );
  }

  String _cellLabel(SessionState session, DashboardCell cell) {
    final wordId = cell.wordId;
    if (wordId != null) {
      try {
        return session.pack.wordById(wordId).label;
      } catch (_) {
        // Fell out of the pack — show what we stored.
      }
    }
    return cell.label.isNotEmpty ? cell.label : cell.speakText;
  }

  String _cellKind(SessionState session, DashboardCell cell) {
    final wordId = cell.wordId;
    if (wordId == null) return 'Custom button — speaks immediately';
    try {
      return session.pack.wordById(wordId).isPhrase ? 'Phrase' : 'Word';
    } catch (_) {
      return 'Word (no longer in vocabulary)';
    }
  }

  Widget _cellLeading(SessionState session, DashboardCell cell) {
    const size = 32.0;
    final wordId = cell.wordId;
    if (wordId != null) {
      try {
        final item = session.pack.wordById(wordId);
        return SymbolImage(
          item: item,
          hasSymbol: session.symbols.hasSymbol(item.id),
          overrideData: session.symbolOverrideFor(item.id),
          size: size,
        );
      } catch (_) {
        // Fall through to emoji.
      }
    }
    final imageData = cell.imageData;
    if (imageData != null) {
      try {
        return Image.memory(
          base64.decode(imageData),
          width: size,
          height: size,
          fit: BoxFit.contain,
          errorBuilder: (_, _, _) => _emojiText(cell.emoji, size),
        );
      } catch (_) {
        // Fall through to emoji.
      }
    }
    return _emojiText(cell.emoji, size);
  }

  Widget _emojiText(String emoji, double size) =>
      Text(emoji, style: TextStyle(fontSize: size * 0.85));

  // ------------------------------------------------------------ add words ---

  Future<void> _addWordsDialog(SessionState session, String profileId) async {
    final query = TextEditingController();
    final added = <String>{};
    await showDialog(
      context: context,
      builder: (ctx) => _DisposeOnUnmount(
        onDispose: query.dispose,
        child: StatefulBuilder(
          builder: (ctx, setDialogState) {
            final hits = findWords(session.pack, query.text).take(30).toList();
            return AlertDialog(
              title: const Text('Add words'),
              content: SizedBox(
                width: double.maxFinite,
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    TextField(
                      controller: query,
                      autofocus: true,
                      decoration: const InputDecoration(
                        labelText: 'Search words',
                        prefixIcon: Icon(Icons.search),
                        border: OutlineInputBorder(),
                      ),
                      onChanged: (_) => setDialogState(() {}),
                    ),
                    const SizedBox(height: 8),
                    Flexible(
                      child: ListView.builder(
                        shrinkWrap: true,
                        itemCount: hits.length,
                        itemBuilder: (ctx, i) {
                          final hit = hits[i];
                          final wasAdded = added.contains(hit.item.id);
                          return ListTile(
                            dense: true,
                            title: Text(hit.item.label),
                            subtitle: Text(hit.location),
                            trailing: wasAdded
                                ? const Icon(Icons.check, color: Colors.green)
                                : const Icon(Icons.add),
                            onTap: wasAdded
                                ? null
                                : () async {
                                    final dashboard = session.dashboards
                                        .ensureFor(profileId);
                                    dashboard.cells.add(
                                      DashboardCell(
                                        id: session.dashboards.newCellId(
                                          dashboard,
                                        ),
                                        wordId: hit.item.id,
                                        // Stored fallback: if the word ever
                                        // leaves the pack, the tile still
                                        // shows and speaks this.
                                        label: hit.item.label,
                                      ),
                                    );
                                    await session.dashboards.save(dashboard);
                                    added.add(hit.item.id);
                                    setDialogState(() {});
                                    widget.refresh();
                                  },
                          );
                        },
                      ),
                    ),
                  ],
                ),
              ),
              actions: [
                TextButton(
                  onPressed: () => Navigator.of(ctx).pop(),
                  child: const Text('Done'),
                ),
              ],
            );
          },
        ),
      ),
    );
  }

  // ----------------------------------------------------------- add custom ---

  /// Lets the caregiver pick a photo for a button. Returns the stored
  /// (downscaled, base64) image, or null when they cancel / it fails.
  Future<String?> _pickButtonImage() async {
    try {
      return await pickButtonImage();
    } on ButtonImageException catch (e) {
      _showError(e.message);
      return null;
    }
  }

  /// Small preview + choose/remove buttons, for the custom-button dialogs.
  Widget _imagePickRow(
    String? imageData,
    void Function(String?) setImage,
    void Function(VoidCallback) setDialogState,
  ) {
    return Row(
      children: [
        Container(
          width: 64,
          height: 64,
          decoration: BoxDecoration(
            border: Border.all(color: Colors.grey.shade400),
            borderRadius: BorderRadius.circular(8),
          ),
          child: imageData != null
              ? ClipRRect(
                  borderRadius: BorderRadius.circular(8),
                  child: Image.memory(
                    base64.decode(imageData),
                    width: 64,
                    height: 64,
                    fit: BoxFit.cover,
                    errorBuilder: (_, _, _) =>
                        const Icon(Icons.broken_image_outlined),
                  ),
                )
              : const Icon(Icons.image_outlined, size: 32),
        ),
        const SizedBox(width: 12),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              OutlinedButton.icon(
                icon: const Icon(Icons.photo_library_outlined),
                label: Text(
                  imageData == null ? 'Choose image' : 'Change image',
                ),
                onPressed: () async {
                  final picked = await _pickButtonImage();
                  if (picked != null) {
                    setDialogState(() => setImage(picked));
                  }
                },
              ),
              if (imageData != null)
                TextButton(
                  onPressed: () => setDialogState(() => setImage(null)),
                  child: const Text('Remove image'),
                ),
            ],
          ),
        ),
      ],
    );
  }

  Future<void> _addCustomDialog(SessionState session, String profileId) async {
    final label = TextEditingController();
    final speak = TextEditingController();
    String? imageData;
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => _DisposeOnUnmount(
        onDispose: () {
          label.dispose();
          speak.dispose();
        },
        child: StatefulBuilder(
          builder: (ctx, setDialogState) => AlertDialog(
            title: const Text('Custom button'),
            content: SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const Text(
                    'A button that speaks immediately when tapped — '
                    'for phrases like "I need a break".',
                    style: TextStyle(fontSize: 13),
                  ),
                  const SizedBox(height: 12),
                  _imagePickRow(
                    imageData,
                    (v) => imageData = v,
                    setDialogState,
                  ),
                  const SizedBox(height: 12),
                  TextField(
                    controller: label,
                    autofocus: true,
                    textCapitalization: TextCapitalization.sentences,
                    decoration: const InputDecoration(
                      labelText: 'Button label',
                      border: OutlineInputBorder(),
                    ),
                  ),
                  const SizedBox(height: 12),
                  TextField(
                    controller: speak,
                    textCapitalization: TextCapitalization.sentences,
                    decoration: const InputDecoration(
                      labelText: 'Says (optional — defaults to the label)',
                      border: OutlineInputBorder(),
                    ),
                  ),
                ],
              ),
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.of(ctx).pop(false),
                child: const Text('Cancel'),
              ),
              FilledButton(
                onPressed: () =>
                    Navigator.of(ctx).pop(label.text.trim().isNotEmpty),
                child: const Text('Add'),
              ),
            ],
          ),
        ),
      ),
    );
    if (ok == true) {
      final dashboard = session.dashboards.ensureFor(profileId);
      dashboard.cells.add(
        DashboardCell(
          id: session.dashboards.newCellId(dashboard),
          label: label.text.trim(),
          speakText: speak.text.trim(),
          emoji: '💬',
          imageData: imageData,
        ),
      );
      await session.dashboards.save(dashboard);
      widget.refresh();
    }
  }

  // ---------------------------------------------------------- edit custom ---

  /// Edit a custom (non-vocabulary) cell: label, spoken text, and image.
  /// Vocabulary cells keep their pack-driven text; their image is set via
  /// the Custom symbols section instead.
  Future<void> _editCustomDialog(
    SessionState session,
    PersonalDashboard dashboard,
    int index,
  ) async {
    final cell = dashboard.cells[index];
    if (cell.wordId != null) return;
    final label = TextEditingController(text: cell.label);
    final speak = TextEditingController(text: cell.speakText);
    String? imageData = cell.imageData;
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => _DisposeOnUnmount(
        onDispose: () {
          label.dispose();
          speak.dispose();
        },
        child: StatefulBuilder(
          builder: (ctx, setDialogState) => AlertDialog(
            title: const Text('Edit button'),
            content: SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  _imagePickRow(
                    imageData,
                    (v) => imageData = v,
                    setDialogState,
                  ),
                  const SizedBox(height: 12),
                  TextField(
                    controller: label,
                    textCapitalization: TextCapitalization.sentences,
                    decoration: const InputDecoration(
                      labelText: 'Button label',
                      border: OutlineInputBorder(),
                    ),
                  ),
                  const SizedBox(height: 12),
                  TextField(
                    controller: speak,
                    textCapitalization: TextCapitalization.sentences,
                    decoration: const InputDecoration(
                      labelText: 'Says (optional — defaults to the label)',
                      border: OutlineInputBorder(),
                    ),
                  ),
                ],
              ),
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.of(ctx).pop(false),
                child: const Text('Cancel'),
              ),
              FilledButton(
                onPressed: () =>
                    Navigator.of(ctx).pop(label.text.trim().isNotEmpty),
                child: const Text('Save'),
              ),
            ],
          ),
        ),
      ),
    );
    if (ok == true) {
      dashboard.cells[index] = DashboardCell(
        id: cell.id,
        label: label.text.trim(),
        speakText: speak.text.trim(),
        emoji: cell.emoji,
        imageData: imageData,
        color: cell.color,
      );
      await session.dashboards.save(dashboard);
      widget.refresh();
    }
  }

  // --------------------------------------------------------------- import ---

  Future<void> _importFile(
    SessionState session,
    String profileId,
    String profileName,
  ) async {
    final List<PlatformFile> files;
    try {
      files = await FilePicker.pickFiles(
        type: FileType.custom,
        allowedExtensions: ['obf', 'obz', 'json'],
      );
    } catch (e) {
      _showError('Could not open the file picker: $e');
      return;
    }
    if (files.isEmpty) return; // user cancelled
    setState(() => _busy = true);
    try {
      final picked = files.single;
      final bytes = await picked.readAsBytes();
      final report = ObfImportService().importBytes(
        bytes,
        profileId: profileId,
        fileName: picked.name,
      );
      if (!mounted) return;
      final existing = session.dashboards.forProfile(profileId);
      final hasExisting = existing != null && existing.cells.isNotEmpty;
      final confirm = await showDialog<bool>(
        context: context,
        builder: (ctx) => AlertDialog(
          title: Text('Import "${report.dashboard.name}"?'),
          content: Text(
            '${report.buttonCount} buttons'
            '${hasExisting ? ' will replace the current dashboard' : ''}.'
            '\n\nImported buttons speak their text immediately when tapped '
            '— they do not build sentences.'
            '${report.warnings.isNotEmpty ? '\n\nNotes:\n${report.warnings.join('\n')}' : ''}',
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(ctx).pop(false),
              child: const Text('Cancel'),
            ),
            FilledButton(
              onPressed: () => Navigator.of(ctx).pop(true),
              child: const Text('Import'),
            ),
          ],
        ),
      );
      if (confirm != true || !mounted) return;
      final dashboard = session.dashboards.ensureFor(
        profileId,
        name: profileName,
      );
      final wasEnabled = dashboard.enabled;
      dashboard.name = report.dashboard.name;
      dashboard.source = report.dashboard.source;
      dashboard.cells
        ..clear()
        ..addAll(report.dashboard.cells);
      dashboard.enabled = wasEnabled;
      await session.dashboards.save(dashboard);
      widget.refresh();
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              'Imported ${report.buttonCount} buttons'
              '${report.imageCount > 0 ? ' (${report.imageCount} with images)' : ''}.',
            ),
          ),
        );
      }
    } on ObfImportError catch (e) {
      _showError(e.message);
    } catch (e) {
      _showError('Import failed: $e');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  // --------------------------------------------------------------- delete ---

  Future<void> _deleteDialog(SessionState session, String profileId) async {
    final confirm = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Delete dashboard?'),
        content: const Text(
          'The personal dashboard for this profile will be removed. '
          'The standard board is unaffected.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(ctx).pop(true),
            child: const Text('Delete'),
          ),
        ],
      ),
    );
    if (confirm == true) {
      await session.dashboards.delete(profileId);
      widget.refresh();
    }
  }

  void _showError(String message) {
    if (!mounted) return;
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Import failed'),
        content: Text(message),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(),
            child: const Text('OK'),
          ),
        ],
      ),
    );
  }
}

/// Runs [onDispose] when unmounted. Dialogs that create their
/// TextEditingControllers outside the dialog widget use this so the
/// controllers are disposed only after the pop transition finishes: the
/// dialog subtree keeps rebuilding (including TextField cursor animations
/// that listen to the controller) until the route is fully removed, so
/// disposing right when [showDialog] returns is a use-after-dispose.
class _DisposeOnUnmount extends StatefulWidget {
  const _DisposeOnUnmount({required this.onDispose, required this.child});

  final VoidCallback onDispose;
  final Widget child;

  @override
  State<_DisposeOnUnmount> createState() => _DisposeOnUnmountState();
}

class _DisposeOnUnmountState extends State<_DisposeOnUnmount> {
  @override
  Widget build(BuildContext context) => widget.child;

  @override
  void dispose() {
    widget.onDispose();
    super.dispose();
  }
}
