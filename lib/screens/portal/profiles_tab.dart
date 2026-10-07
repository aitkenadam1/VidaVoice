import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../state/session_state.dart';
import '../../widgets/communication_mode_widgets.dart';
import '../../widgets/mode_nudge_card.dart';
import 'portal_section.dart';

/// Portal "Profiles" tab: full communicator-profile management —
/// list, create, switch active, remove, and per-profile communication
/// mode, Build length, prediction privacy, and mode-nudge settings.
///
/// Migrated from the old caregiver hub's profiles section; the editors
/// are the same tested widgets, keyed the same way so external changes
/// (e.g. backup import) reset local drafts.
class PortalProfilesTab extends StatefulWidget {
  const PortalProfilesTab({super.key});

  @override
  State<PortalProfilesTab> createState() => _PortalProfilesTabState();
}

class _PortalProfilesTabState extends State<PortalProfilesTab> {
  void _refresh() {
    if (mounted) setState(() {});
  }

  @override
  Widget build(BuildContext context) {
    final session = context.watch<SessionState>();
    final profiles = session.profiles;
    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        PortalSection(
          title: 'Communicator profiles',
          icon: Icons.people_outline,
          child: Column(
            children: [
              for (final p in profiles.profiles)
                Card(
                  margin: const EdgeInsets.only(bottom: 8),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      ListTile(
                        leading: const Icon(Icons.person_outline),
                        title: Text(p.name),
                        trailing: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            if (p.id == profiles.active?.id)
                              const Icon(Icons.check, color: Colors.green)
                            else
                              TextButton(
                                onPressed: () async {
                                  await session.switchProfile(p.id);
                                  _refresh();
                                },
                                child: const Text('Switch'),
                              ),
                            if (profiles.profiles.length > 1)
                              IconButton(
                                tooltip: 'Remove profile',
                                icon: const Icon(Icons.delete_outline),
                                onPressed: () async {
                                  // Destructive and irreversible (custom
                                  // words, voices, history) — confirm first,
                                  // like every other destructive action.
                                  final confirm = await showDialog<bool>(
                                    context: context,
                                    builder: (ctx) => AlertDialog(
                                      title: Text('Remove "${p.name}"?'),
                                      content: const Text(
                                        'This deletes the profile and its '
                                        'custom words, saved voices, and '
                                        'history on this device. '
                                        "This can't be undone.",
                                      ),
                                      actions: [
                                        TextButton(
                                          onPressed: () =>
                                              Navigator.of(ctx).pop(false),
                                          child: const Text('Cancel'),
                                        ),
                                        FilledButton(
                                          onPressed: () =>
                                              Navigator.of(ctx).pop(true),
                                          child: const Text('Remove profile'),
                                        ),
                                      ],
                                    ),
                                  );
                                  if (confirm != true || !context.mounted) {
                                    return;
                                  }
                                  await session.removeProfile(p.id);
                                  _refresh();
                                },
                              ),
                          ],
                        ),
                      ),
                      const Divider(height: 1),
                      // Per-profile communication-mode picker. Keyed on
                      // the saved mode so an external change resets the
                      // local selection to what is actually stored.
                      ProfileModeEditor(
                        key: ValueKey(
                          'mode-editor-${p.id}-${p.communicationMode.name}',
                        ),
                        profileId: p.id,
                      ),
                      // Per-profile Build length limit. Keyed on the
                      // saved value for the same reason.
                      BuildLengthEditor(
                        key: ValueKey(
                          'build-length-${p.id}-${p.buildMaxSymbols}',
                        ),
                        profileId: p.id,
                      ),
                      // Per-profile Type prediction privacy controls.
                      // Keyed on the saved toggle for the same reason.
                      PredictionPrivacyEditor(
                        key: ValueKey(
                          'prediction-${p.id}-${p.predictionEnabled}',
                        ),
                        profileId: p.id,
                      ),
                      // The ONE caregiver-facing mode-progression
                      // suggestion. Renders only when eligible; never on
                      // the communicator's board, never interrupts, never
                      // changes the saved mode.
                      ModeNudgeCard(profileId: p.id, onChanged: _refresh),
                      // Durable progression-suggestion preference
                      // (On / Paused / Off). Explicit save; keyed on the
                      // saved value.
                      NudgePreferenceEditor(
                        key: ValueKey(
                          'nudge-pref-${p.id}-${p.modeNudgePreference.name}',
                        ),
                        profileId: p.id,
                      ),
                    ],
                  ),
                ),
              if (profiles.profiles.isEmpty)
                const Padding(
                  padding: EdgeInsets.symmetric(vertical: 8),
                  child: Text('No communicator profiles yet.'),
                ),
              Align(
                alignment: Alignment.centerLeft,
                child: Padding(
                  padding: const EdgeInsets.all(8),
                  child: OutlinedButton.icon(
                    icon: const Icon(Icons.add),
                    label: const Text('Add profile'),
                    onPressed: () =>
                        _addProfileDialog(context, session, _refresh),
                  ),
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }

  Future<void> _addProfileDialog(
    BuildContext context,
    SessionState session,
    VoidCallback refresh,
  ) async {
    final controller = TextEditingController();
    final name = await showDialog<String>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('New profile'),
        content: TextField(
          controller: controller,
          autofocus: true,
          textCapitalization: TextCapitalization.words,
          decoration: const InputDecoration(
            labelText: 'First name',
            border: OutlineInputBorder(),
          ),
          onSubmitted: (_) => Navigator.of(ctx).pop(controller.text),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(ctx).pop(controller.text),
            child: const Text('Add'),
          ),
        ],
      ),
    );
    if (name != null && name.trim().isNotEmpty) {
      await session.profiles.addProfile(name.trim());
      refresh();
    }
  }
}
