import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../services/profile_service.dart';
import '../state/session_state.dart';

/// Phase 2 (communication modes): mode selection UI shared by onboarding
/// and the caregiver hub.
///
/// The ONLY sanctioned persistence path for a profile's communication mode
/// is [ProfileService.setCommunicationMode]; UI code calls it through the
/// [SessionState.setCommunicationMode] wrapper (same persistence plus a
/// listener notification so the home screen switches surfaces). Both save
/// actions below are explicit caregiver "Save mode" presses. Nothing in
/// this file derives the mode from mobility answers, grid size, or any
/// other signal, and the sandbox previews below never touch the TTS layer
/// at all — they are pure local-state mocks, so "try before saving" cannot
/// speak by construction.
///
/// Copy source: the OneVoz Communication Modes plan (onboarding + profile
/// settings sections).

/// Static copy per mode: title, one-line description, and icon.
({String title, String description, IconData icon}) _modeInfo(
  CommunicationMode mode,
) => switch (mode) {
  CommunicationMode.tap => (
    title: 'Tap',
    description: 'Speak with one large symbol at a time.',
    icon: Icons.touch_app_outlined,
  ),
  CommunicationMode.build => (
    title: 'Build',
    description: 'Put symbols together, then speak the message.',
    icon: Icons.view_column_outlined,
  ),
  CommunicationMode.type => (
    title: 'Type',
    description: 'Type with predictions and saved phrases.',
    icon: Icons.keyboard_outlined,
  ),
};

/// Three radio-style mode choices, each with a short static visual preview
/// card. Reports selection via [onSelectionChanged] but writes nothing —
/// the caller owns the explicit save.
class CommunicationModePicker extends StatefulWidget {
  const CommunicationModePicker({
    super.key,
    required this.initialMode,
    required this.onSelectionChanged,
  });

  final CommunicationMode initialMode;
  final ValueChanged<CommunicationMode> onSelectionChanged;

  @override
  State<CommunicationModePicker> createState() =>
      _CommunicationModePickerState();
}

class _CommunicationModePickerState extends State<CommunicationModePicker> {
  late CommunicationMode _selected = widget.initialMode;

  void _select(CommunicationMode mode) {
    if (mode == _selected) return;
    setState(() => _selected = mode);
    widget.onSelectionChanged(mode);
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      mainAxisSize: MainAxisSize.min,
      children: [
        RadioGroup<CommunicationMode>(
          groupValue: _selected,
          onChanged: (v) {
            if (v != null) _select(v);
          },
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              for (final mode in CommunicationMode.values)
                _ModeOptionCard(
                  mode: mode,
                  selected: _selected == mode,
                  onSelect: _select,
                ),
            ],
          ),
        ),
        const SizedBox(height: 4),
        Align(
          alignment: Alignment.centerLeft,
          child: OutlinedButton.icon(
            icon: const Icon(Icons.visibility_outlined, size: 18),
            label: const Text('Try before saving'),
            onPressed: () => showModePreviewDialog(context, _selected),
          ),
        ),
      ],
    );
  }
}

class _ModeOptionCard extends StatelessWidget {
  const _ModeOptionCard({
    required this.mode,
    required this.selected,
    required this.onSelect,
  });

  final CommunicationMode mode;
  final bool selected;
  final ValueChanged<CommunicationMode> onSelect;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final info = _modeInfo(mode);
    return Card(
      margin: const EdgeInsets.symmetric(vertical: 6),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(16),
        side: BorderSide(
          color: selected ? scheme.primary : scheme.outlineVariant,
          width: selected ? 2 : 1,
        ),
      ),
      child: InkWell(
        key: ValueKey('mode-option-${mode.name}'),
        borderRadius: BorderRadius.circular(16),
        onTap: () => onSelect(mode),
        child: Padding(
          padding: const EdgeInsets.all(12),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // groupValue/onChanged come from the RadioGroup ancestor.
              Radio<CommunicationMode>(value: mode),
              const SizedBox(width: 4),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Icon(info.icon, size: 20, color: scheme.primary),
                        const SizedBox(width: 8),
                        Text(
                          info.title,
                          style: const TextStyle(
                            fontSize: 17,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 4),
                    Text(info.description, style: const TextStyle(fontSize: 14)),
                    const SizedBox(height: 8),
                    _MiniPreview(mode: mode),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// Tiny static illustration of what each mode's screen does. Pure
/// decoration — no interaction, no state, no speech.
class _MiniPreview extends StatelessWidget {
  const _MiniPreview({required this.mode});

  final CommunicationMode mode;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    switch (mode) {
      case CommunicationMode.tap:
        // One large symbol tile.
        return Container(
          height: 52,
          decoration: BoxDecoration(
            color: scheme.primaryContainer,
            borderRadius: BorderRadius.circular(12),
          ),
          child: const Center(child: Icon(Icons.image_outlined, size: 28)),
        );
      case CommunicationMode.build:
        // Small tiles flowing into a phrase strip.
        return SizedBox(
          height: 52,
          child: Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              for (var i = 0; i < 3; i++)
                Container(
                  width: 30,
                  height: 30,
                  margin: const EdgeInsets.symmetric(horizontal: 2),
                  decoration: BoxDecoration(
                    color: scheme.secondaryContainer,
                    borderRadius: BorderRadius.circular(6),
                  ),
                  child: const Icon(Icons.image_outlined, size: 15),
                ),
              const Padding(
                padding: EdgeInsets.symmetric(horizontal: 4),
                child: Icon(Icons.arrow_forward, size: 15),
              ),
              Container(
                width: 62,
                height: 30,
                decoration: BoxDecoration(
                  color: scheme.primaryContainer,
                  borderRadius: BorderRadius.circular(15),
                ),
                child: const Icon(Icons.graphic_eq, size: 15),
              ),
            ],
          ),
        );
      case CommunicationMode.type:
        // Text bar with a prediction row.
        return SizedBox(
          height: 52,
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Container(
                height: 20,
                decoration: BoxDecoration(
                  color: scheme.surfaceContainerHighest,
                  borderRadius: BorderRadius.circular(10),
                ),
                child: const Row(
                  children: [
                    SizedBox(width: 8),
                    Icon(Icons.keyboard_outlined, size: 13),
                  ],
                ),
              ),
              const SizedBox(height: 5),
              Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  for (final w in const ['I', 'want', 'more'])
                    Container(
                      margin: const EdgeInsets.symmetric(horizontal: 2),
                      padding: const EdgeInsets.symmetric(
                        horizontal: 8,
                        vertical: 2,
                      ),
                      decoration: BoxDecoration(
                        color: scheme.secondaryContainer,
                        borderRadius: BorderRadius.circular(9),
                      ),
                      child: Text(w, style: const TextStyle(fontSize: 11)),
                    ),
                ],
              ),
            ],
          ),
        );
    }
  }
}

/// The onboarding mode-choice step (placed right after the profile-name
/// step). Skippable like every other step: leaving without pressing
/// "Save mode" writes nothing and the profile stays in Tap.
class ModeChoiceStep extends StatefulWidget {
  const ModeChoiceStep({super.key});

  @override
  State<ModeChoiceStep> createState() => _ModeChoiceStepState();
}

class _ModeChoiceStepState extends State<ModeChoiceStep> {
  late CommunicationMode _selected;
  CommunicationMode? _saved;

  @override
  void initState() {
    super.initState();
    _selected =
        context.read<SessionState>().profiles.active?.communicationMode ??
        CommunicationMode.tap;
  }

  Future<void> _save() async {
    final session = context.read<SessionState>();
    final profile = session.profiles.active;
    if (profile == null) return;
    // The UI-level save: persists the mode through the single sanctioned
    // ProfileService path and notifies so the home screen switches.
    await session.setCommunicationMode(profile.id, _selected);
    if (!mounted) return;
    setState(() => _saved = _selected);
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text('Saved: ${_modeInfo(_selected).title} mode')),
    );
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        const Text(
          'How does this person communicate best right now?',
          style: TextStyle(fontSize: 24, fontWeight: FontWeight.bold),
          textAlign: TextAlign.center,
        ),
        const SizedBox(height: 8),
        Text(
          'Choose a starting mode. You can change it later without losing '
          'words, boards, phrases, or history.',
          style: TextStyle(fontSize: 15, color: scheme.onSurfaceVariant),
          textAlign: TextAlign.center,
        ),
        const SizedBox(height: 16),
        CommunicationModePicker(
          initialMode: _selected,
          onSelectionChanged: (m) => setState(() {
            _selected = m;
            _saved = null;
          }),
        ),
        const SizedBox(height: 8),
        FilledButton(
          onPressed: _save,
          child: const Padding(
            padding: EdgeInsets.symmetric(vertical: 12),
            child: Text('Save mode', style: TextStyle(fontSize: 17)),
          ),
        ),
        if (_saved != null) ...[
          const SizedBox(height: 8),
          Text(
            'Saved: ${_modeInfo(_saved!).title} mode \u2014 you can change it '
            'any time from the caregiver hub.',
            textAlign: TextAlign.center,
            style: TextStyle(fontSize: 13, color: scheme.onSurfaceVariant),
          ),
        ],
      ],
    );
  }
}

/// Per-profile "Communication mode" editor for the caregiver hub's
/// Communicator profiles section. Shows the profile's current mode and
/// saves only through [SessionState.setCommunicationMode] (which persists
/// via the single sanctioned [ProfileService] path and notifies so the
/// home screen switches), which touches
/// the mode field and nothing else — dashboards, symbols, phrases, voice,
/// and history are stored separately and are never rewritten here.
class ProfileModeEditor extends StatefulWidget {
  const ProfileModeEditor({super.key, required this.profileId});

  final String profileId;

  @override
  State<ProfileModeEditor> createState() => _ProfileModeEditorState();
}

class _ProfileModeEditorState extends State<ProfileModeEditor> {
  late CommunicationMode _selected;

  @override
  void initState() {
    super.initState();
    _selected = _currentMode() ?? CommunicationMode.tap;
  }

  CommunicationMode? _currentMode() {
    final profiles = context.read<SessionState>().profiles.profiles;
    for (final p in profiles) {
      if (p.id == widget.profileId) return p.communicationMode;
    }
    return null;
  }

  Future<void> _save() async {
    final session = context.read<SessionState>();
    // The UI-level save: persists through the single sanctioned
    // ProfileService path and notifies so the home screen switches to
    // the new mode surface immediately.
    await session.setCommunicationMode(widget.profileId, _selected);
    if (!mounted) return;
    setState(() {}); // refresh the "Current" line below
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(
          'Communication mode saved: ${_modeInfo(_selected).title}',
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final session = context.watch<SessionState>();
    UserProfile? profile;
    for (final p in session.profiles.profiles) {
      if (p.id == widget.profileId) profile = p;
    }
    if (profile == null) return const SizedBox.shrink();
    final scheme = Theme.of(context).colorScheme;
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 4, 16, 16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          const Text(
            'Communication mode',
            style: TextStyle(fontWeight: FontWeight.bold, fontSize: 15),
          ),
          const SizedBox(height: 4),
          Text(
            'Changes this profile\u2019s main communication screen. It does '
            'not remove any saved content.',
            style: TextStyle(fontSize: 13, color: scheme.onSurfaceVariant),
          ),
          const SizedBox(height: 4),
          Text(
            'Current: ${_modeInfo(profile.communicationMode).title}',
            style: TextStyle(fontSize: 13, color: scheme.onSurfaceVariant),
          ),
          const SizedBox(height: 8),
          CommunicationModePicker(
            initialMode: _selected,
            onSelectionChanged: (m) => setState(() => _selected = m),
          ),
          const SizedBox(height: 4),
          FilledButton(onPressed: _save, child: const Text('Save mode')),
        ],
      ),
    );
  }
}

/// Per-profile "Maximum phrase length" (Build mode) editor for the
/// caregiver hub's Communicator profiles section. The slider drafts
/// locally; nothing is written until the explicit Save, which goes only
/// through [ProfileService.setBuildMaxSymbols] — the same explicit-save
/// contract as the mode picker. The value clamps to
/// [ProfileService.minBuildMaxSymbols]..[ProfileService.maxBuildMaxSymbols]
/// (2..12) on both ends.
class BuildLengthEditor extends StatefulWidget {
  const BuildLengthEditor({super.key, required this.profileId});

  final String profileId;

  @override
  State<BuildLengthEditor> createState() => _BuildLengthEditorState();
}

class _BuildLengthEditorState extends State<BuildLengthEditor> {
  late double _draft;
  bool _saved = false;

  @override
  void initState() {
    super.initState();
    _draft =
        (_currentValue() ?? ProfileService.defaultBuildMaxSymbols).toDouble();
  }

  int? _currentValue() {
    final profiles = context.read<SessionState>().profiles.profiles;
    for (final p in profiles) {
      if (p.id == widget.profileId) return p.buildMaxSymbols;
    }
    return null;
  }

  Future<void> _save() async {
    final session = context.read<SessionState>();
    // The UI-level save: persists through ProfileService and notifies so
    // the phrase strip re-reads the limit immediately.
    await session.setBuildMaxSymbols(
      widget.profileId,
      _draft.round(),
    );
    if (!mounted) return;
    setState(() => _saved = true);
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(
          'Maximum phrase length saved: ${_draft.round()} symbols',
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final session = context.watch<SessionState>();
    UserProfile? profile;
    for (final p in session.profiles.profiles) {
      if (p.id == widget.profileId) profile = p;
    }
    if (profile == null) return const SizedBox.shrink();
    final scheme = Theme.of(context).colorScheme;
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          const Text(
            'Maximum phrase length',
            style: TextStyle(fontWeight: FontWeight.bold, fontSize: 15),
          ),
          const SizedBox(height: 4),
          Text(
            'How many symbols fit in this profile\u2019s Build-mode phrase '
            'strip. Applies to Build mode only.',
            style: TextStyle(fontSize: 13, color: scheme.onSurfaceVariant),
          ),
          const SizedBox(height: 4),
          Text(
            'Current: ${profile.buildMaxSymbols} symbols',
            style: TextStyle(fontSize: 13, color: scheme.onSurfaceVariant),
          ),
          Semantics(
            label: 'Maximum phrase length, ${_draft.round()} symbols',
            child: Slider(
              value: _draft,
              min: ProfileService.minBuildMaxSymbols.toDouble(),
              max: ProfileService.maxBuildMaxSymbols.toDouble(),
              divisions:
                  ProfileService.maxBuildMaxSymbols -
                  ProfileService.minBuildMaxSymbols,
              label: '${_draft.round()} symbols',
              onChanged: (v) => setState(() {
                _draft = v;
                _saved = false;
              }),
            ),
          ),
          FilledButton(
            onPressed: _save,
            child: const Text('Save maximum'),
          ),
          if (_saved)
            Padding(
              padding: const EdgeInsets.only(top: 4),
              child: Text(
                'Saved: ${_draft.round()} symbols',
                textAlign: TextAlign.center,
                style: TextStyle(fontSize: 13, color: scheme.onSurfaceVariant),
              ),
            ),
        ],
      ),
    );
  }
}

/// Per-profile Type-mode prediction controls for the caregiver hub's
/// Communicator profiles section (Phase 4 of the modes plan).
///
/// Three INDEPENDENT actions:
/// * the "Learn from spoken messages" toggle — OFF disables learning and
///   clears the profile's already-learned ranks (a disabled profile must
///   not keep a personal language model);
/// * "Clear message history" — wipes the spoken-history store only;
/// * "Reset learned predictions" — wipes the learned-ranks store only.
///
/// Copy source: the OneVoz Communication Modes plan (prediction data
/// boundaries + transparent controls sections).
class PredictionPrivacyEditor extends StatefulWidget {
  const PredictionPrivacyEditor({super.key, required this.profileId});

  final String profileId;

  @override
  State<PredictionPrivacyEditor> createState() => _PredictionPrivacyEditorState();
}

class _PredictionPrivacyEditorState extends State<PredictionPrivacyEditor> {
  bool _busy = false;

  UserProfile? _profile(SessionState session) {
    for (final p in session.profiles.profiles) {
      if (p.id == widget.profileId) return p;
    }
    return null;
  }

  Future<void> _toggle(bool enabled) async {
    if (_busy) return;
    setState(() => _busy = true);
    try {
      await context.read<SessionState>().setPredictionEnabled(
        widget.profileId,
        enabled,
      );
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              enabled
                  ? 'Prediction learning on — new spoken messages will '
                      'improve suggestions.'
                  : 'Prediction learning off — learned predictions cleared.',
            ),
          ),
        );
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _confirmAndRun({
    required String title,
    required String body,
    required String actionLabel,
    required Future<void> Function(SessionState session) run,
    required String doneMessage,
  }) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(title),
        content: Text(body),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(ctx).pop(true),
            child: Text(actionLabel),
          ),
        ],
      ),
    );
    if (confirmed != true || !mounted) return;
    setState(() => _busy = true);
    try {
      await run(context.read<SessionState>());
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text(doneMessage)));
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final session = context.watch<SessionState>();
    final profile = _profile(session);
    if (profile == null) return const SizedBox.shrink();
    final scheme = Theme.of(context).colorScheme;
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          const Text(
            'Prediction privacy',
            style: TextStyle(fontWeight: FontWeight.bold, fontSize: 15),
          ),
          const SizedBox(height: 4),
          Text(
            'Predictions learn from messages spoken in this profile and '
            'stay on this device. Clearing history and resetting learning '
            'are separate — neither touches the other.',
            style: TextStyle(fontSize: 13, color: scheme.onSurfaceVariant),
          ),
          SwitchListTile(
            key: ValueKey('prediction-toggle-${widget.profileId}'),
            contentPadding: EdgeInsets.zero,
            title: const Text('Learn from spoken messages'),
            subtitle: Text(
              profile.predictionEnabled
                  ? 'On — spoken messages improve suggestions'
                  : 'Off — no learning; existing learned predictions '
                      'were cleared',
              style: TextStyle(fontSize: 13, color: scheme.onSurfaceVariant),
            ),
            value: profile.predictionEnabled,
            onChanged: _busy ? null : _toggle,
          ),
          Row(
            children: [
              Expanded(
                child: OutlinedButton.icon(
                  key: ValueKey(
                    'prediction-clear-history-${widget.profileId}',
                  ),
                  onPressed: _busy
                      ? null
                      : () => _confirmAndRun(
                          title: 'Clear message history?',
                          body:
                              'This deletes every spoken message recorded for '
                              '${profile.name}. Learned predictions are kept — '
                              'use “Reset learned predictions” to clear those '
                              'too.',
                          actionLabel: 'Clear history',
                          run: (s) => s.clearHistoryFor(widget.profileId),
                          doneMessage:
                              'Message history cleared for ${profile.name}.',
                        ),
                  icon: const Icon(Icons.delete_outline, size: 18),
                  label: const Text('Clear message history'),
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: OutlinedButton.icon(
                  key: ValueKey('prediction-reset-${widget.profileId}'),
                  onPressed: _busy
                      ? null
                      : () => _confirmAndRun(
                          title: 'Reset learned predictions?',
                          body:
                              'This forgets everything prediction learned from '
                              '${profile.name}\u2019s spoken messages. The '
                              'message history itself is kept.',
                          actionLabel: 'Reset learning',
                          run: (s) => s.resetLearningFor(widget.profileId),
                          doneMessage:
                              'Learned predictions reset for ${profile.name}.',
                        ),
                  icon: const Icon(Icons.psychology_outlined, size: 18),
                  label: const Text('Reset learned predictions'),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

/// Opens the safe sandbox preview for [mode]. The preview is a static,
/// local-state-only mock of the mode's main screen: tiles and chips react
/// visually, the Speak action is disabled, and the dialog never references
/// [SessionState] or the TTS layer — "try before saving" cannot speak, by
/// construction.
Future<void> showModePreviewDialog(
  BuildContext context,
  CommunicationMode mode,
) {
  return showDialog<void>(
    context: context,
    builder: (ctx) => AlertDialog(
      title: Text('${_modeInfo(mode).title} mode \u2014 preview'),
      content: SingleChildScrollView(
        child: _ModeSandboxPreview(mode: mode),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(ctx).pop(),
          child: const Text('Close'),
        ),
      ],
    ),
  );
}

class _ModeSandboxPreview extends StatelessWidget {
  const _ModeSandboxPreview({required this.mode});

  final CommunicationMode mode;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Container(
          padding: const EdgeInsets.all(10),
          decoration: BoxDecoration(
            color: scheme.surfaceContainerHighest,
            borderRadius: BorderRadius.circular(12),
          ),
          child: const Row(
            children: [
              Icon(Icons.volume_off_outlined, size: 18),
              SizedBox(width: 8),
              Expanded(
                child: Text(
                  'Preview only \u2014 nothing will speak here.',
                  style: TextStyle(fontSize: 13),
                ),
              ),
            ],
          ),
        ),
        const SizedBox(height: 12),
        switch (mode) {
          CommunicationMode.tap => const _TapSandbox(),
          CommunicationMode.build => const _BuildSandbox(),
          CommunicationMode.type => const _TypeSandbox(),
        },
      ],
    );
  }
}

/// Mock of the Tap home board: large tiles react with a highlight and a
/// caption, never with speech.
class _TapSandbox extends StatefulWidget {
  const _TapSandbox();

  @override
  State<_TapSandbox> createState() => _TapSandboxState();
}

class _TapSandboxState extends State<_TapSandbox> {
  String? _pressed;

  static const _tiles = [
    ('water', Icons.water_drop_outlined),
    ('more', Icons.add_circle_outline),
    ('help', Icons.help_outline),
    ('go', Icons.play_circle_outline),
  ];

  Widget _tile(String label, IconData icon, ColorScheme scheme) {
    return SizedBox(
      height: 76,
      child: Card(
        key: ValueKey('sandbox-tile-$label'),
        margin: EdgeInsets.zero,
        color: _pressed == label ? scheme.primaryContainer : null,
        child: InkWell(
          borderRadius: BorderRadius.circular(12),
          onTap: () => setState(() => _pressed = label),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(icon, size: 30),
              const SizedBox(height: 4),
              Text(label, style: const TextStyle(fontSize: 14)),
            ],
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text(
          'One large symbol fills the screen. One tap speaks it.',
          style: TextStyle(fontSize: 13, color: scheme.onSurfaceVariant),
        ),
        const SizedBox(height: 8),
        // Plain rows, not a GridView: a shrink-wrapping viewport inside an
        // AlertDialog cannot compute intrinsic dimensions.
        for (var row = 0; row < 2; row++) ...[
          if (row > 0) const SizedBox(height: 8),
          Row(
            children: [
              Expanded(
                child: _tile(
                  _tiles[row * 2].$1,
                  _tiles[row * 2].$2,
                  scheme,
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: _tile(
                  _tiles[row * 2 + 1].$1,
                  _tiles[row * 2 + 1].$2,
                  scheme,
                ),
              ),
            ],
          ),
        ],
        const SizedBox(height: 8),
        Text(
          _pressed == null
              ? 'Tap a symbol to see what would happen.'
              : 'In the real board, tapping \u201c$_pressed\u201d would speak '
                  'it. Here, nothing speaks.',
          style: TextStyle(fontSize: 13, color: scheme.onSurfaceVariant),
          textAlign: TextAlign.center,
        ),
      ],
    );
  }
}

/// Mock of the Build phrase strip: symbols collect locally, can be
/// removed, and the Speak action stays disabled.
class _BuildSandbox extends StatefulWidget {
  const _BuildSandbox();

  @override
  State<_BuildSandbox> createState() => _BuildSandboxState();
}

class _BuildSandboxState extends State<_BuildSandbox> {
  final List<String> _strip = ['I', 'want'];

  static const _candidates = ['more', 'juice', 'go'];

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final full = _strip.length >= ProfileService.defaultBuildMaxSymbols;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text(
          'Symbols collect in the phrase strip. Nothing speaks until the '
          'communicator presses Speak.',
          style: TextStyle(fontSize: 13, color: scheme.onSurfaceVariant),
        ),
        const SizedBox(height: 8),
        Container(
          padding: const EdgeInsets.all(8),
          decoration: BoxDecoration(
            border: Border.all(color: scheme.outlineVariant),
            borderRadius: BorderRadius.circular(12),
          ),
          child: _strip.isEmpty
              ? Text(
                  'Empty strip \u2014 tap a symbol below to add it.',
                  style: TextStyle(
                    fontSize: 13,
                    color: scheme.onSurfaceVariant,
                  ),
                )
              : Wrap(
                  spacing: 6,
                  children: [
                    for (var i = 0; i < _strip.length; i++)
                      InputChip(
                        key: ValueKey('sandbox-strip-$i'),
                        label: Text(_strip[i]),
                        deleteIcon: const Icon(Icons.close, size: 16),
                        onDeleted: () => setState(() => _strip.removeAt(i)),
                      ),
                  ],
                ),
        ),
        const SizedBox(height: 8),
        Wrap(
          spacing: 6,
          children: [
            for (final w in _candidates)
              ActionChip(
                key: ValueKey('sandbox-add-$w'),
                label: Text(w),
                onPressed: full ? null : () => setState(() => _strip.add(w)),
              ),
          ],
        ),
        const SizedBox(height: 12),
        FilledButton(onPressed: null, child: const Text('Speak')),
        const SizedBox(height: 4),
        Text(
          'Speak is disabled in previews.',
          style: TextStyle(fontSize: 12, color: scheme.onSurfaceVariant),
          textAlign: TextAlign.center,
        ),
      ],
    );
  }
}

/// Mock of the Type screen: a fake text field, prediction chips that fill
/// it locally, and a disabled Speak action.
class _TypeSandbox extends StatefulWidget {
  const _TypeSandbox();

  @override
  State<_TypeSandbox> createState() => _TypeSandboxState();
}

class _TypeSandboxState extends State<_TypeSandbox> {
  String _text = '';

  static const _predictions = ['I', 'want', 'more'];

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text(
          'A keyboard, predictions, and saved phrases. Nothing speaks until '
          'the communicator presses Speak.',
          style: TextStyle(fontSize: 13, color: scheme.onSurfaceVariant),
        ),
        const SizedBox(height: 8),
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 14),
          decoration: BoxDecoration(
            color: scheme.surfaceContainerHighest,
            borderRadius: BorderRadius.circular(12),
          ),
          child: Text(
            _text.isEmpty ? 'Type here\u2026' : _text,
            style: TextStyle(
              fontSize: 15,
              color: _text.isEmpty ? scheme.onSurfaceVariant : null,
            ),
          ),
        ),
        const SizedBox(height: 8),
        Wrap(
          spacing: 6,
          children: [
            for (final w in _predictions)
              ActionChip(
                key: ValueKey('sandbox-predict-$w'),
                label: Text(w),
                onPressed: () =>
                    setState(() => _text = _text.isEmpty ? w : '$_text $w'),
              ),
          ],
        ),
        const SizedBox(height: 12),
        FilledButton(onPressed: null, child: const Text('Speak')),
        const SizedBox(height: 4),
        Text(
          'Speak is disabled in previews.',
          style: TextStyle(fontSize: 12, color: scheme.onSurfaceVariant),
          textAlign: TextAlign.center,
        ),
      ],
    );
  }
}

/// Per-profile "progression suggestions" preference (Phase 5).
///
/// The durable counterpart to the ModeNudgeCard's one-way "Don't suggest
/// again": a caregiver who declined suggestions can re-enable them here,
/// or pause them without erasing eligibility state. Uses a local draft +
/// explicit Save, consistent with the other profile editors in this file.
class NudgePreferenceEditor extends StatefulWidget {
  const NudgePreferenceEditor({super.key, required this.profileId});

  final String profileId;

  @override
  State<NudgePreferenceEditor> createState() => _NudgePreferenceEditorState();
}

class _NudgePreferenceEditorState extends State<NudgePreferenceEditor> {
  late ModeNudgePreference _draft;
  bool _initialized = false;
  bool _busy = false;

  static String _label(ModeNudgePreference p) => switch (p) {
        ModeNudgePreference.allowed => 'On',
        ModeNudgePreference.paused => 'Paused',
        ModeNudgePreference.off => 'Off',
      };

  static String _description(ModeNudgePreference p) => switch (p) {
        ModeNudgePreference.allowed =>
          'Suggestions are shown in this hub when this profile is ready.',
        ModeNudgePreference.paused =>
          'Suggestions are hidden for now. Progress is kept, so they can '
          'return later.',
        ModeNudgePreference.off =>
          'Never suggest a new mode for this profile. Nothing is counted.',
      };

  @override
  Widget build(BuildContext context) {
    final session = context.watch<SessionState>();
    UserProfile? profile;
    for (final p in session.profiles.profiles) {
      if (p.id == widget.profileId) profile = p;
    }
    final saved = profile?.modeNudgePreference ?? ModeNudgePreference.allowed;
    if (!_initialized) {
      _draft = saved;
      _initialized = true;
    }
    final scheme = Theme.of(context).colorScheme;
    final dirty = _draft != saved;
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 4, 16, 8),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'Progression suggestions',
            style: Theme.of(context)
                .textTheme
                .titleSmall
                ?.copyWith(fontWeight: FontWeight.w600),
          ),
          const SizedBox(height: 2),
          Text(
            'Gentle prompts to try the next mode up, shown only here. '
            'Nothing ever changes the mode automatically.',
            style: TextStyle(fontSize: 13, color: scheme.onSurfaceVariant),
          ),
          const SizedBox(height: 8),
          SegmentedButton<ModeNudgePreference>(
            segments: [
              for (final p in ModeNudgePreference.values)
                ButtonSegment(value: p, label: Text(_label(p))),
            ],
            selected: {_draft},
            onSelectionChanged: (s) => setState(() => _draft = s.single),
            style: ButtonStyle(
              visualDensity:
                  const VisualDensity(horizontal: -1, vertical: -2),
            ),
          ),
          const SizedBox(height: 4),
          Text(
            _description(_draft),
            style: TextStyle(fontSize: 13, color: scheme.onSurfaceVariant),
          ),
          Align(
            alignment: Alignment.centerRight,
            child: FilledButton(
              onPressed: (_busy || !dirty)
                  ? null
                  : () async {
                      setState(() => _busy = true);
                      try {
                        await session.profiles
                            .setNudgePreference(widget.profileId, _draft);
                        if (context.mounted) {
                          ScaffoldMessenger.of(context).showSnackBar(
                            SnackBar(
                              content: Text(
                                'Progression suggestions: ${_label(_draft)} '
                                'for ${profile?.name ?? 'this profile'}.',
                              ),
                            ),
                          );
                        }
                      } finally {
                        if (mounted) setState(() => _busy = false);
                      }
                    },
              child: const Text('Save'),
            ),
          ),
        ],
      ),
    );
  }
}
