import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../models/calling_safety.dart';
import '../../state/session_state.dart';

/// Emergency details editor for the Calling & Safety hub and guided setup
/// flow.
///
/// These details fill the {child_name}, {home_address}, {parent_name} and
/// {parent_phone} placeholders in call phrases at call time. Writes through
/// [ProfileService.setEmergency]; the session's onChanged wiring schedules
/// the encrypted sync push automatically.
class EmergencyDetailsEditor extends StatefulWidget {
  const EmergencyDetailsEditor({
    super.key,
    required this.profileId,
    this.onChanged,
    this.compact = false,
  });

  final String profileId;
  final VoidCallback? onChanged;

  /// When true (guided setup), the explainer text is shorter.
  final bool compact;

  @override
  State<EmergencyDetailsEditor> createState() => _EmergencyDetailsEditorState();
}

class _EmergencyDetailsEditorState extends State<EmergencyDetailsEditor> {
  late final TextEditingController _childName;
  late final TextEditingController _homeAddress;
  late final TextEditingController _parentName;
  late final TextEditingController _parentPhone;
  late final TextEditingController _medicalNotes;
  late bool _emergencyEnabled;
  bool _saving = false;
  bool _initialized = false;

  EmergencyProfileData _data(SessionState session) {
    for (final p in session.profiles.profiles) {
      if (p.id == widget.profileId) return p.emergency;
    }
    return EmergencyProfileData();
  }

  void _initFrom(EmergencyProfileData data) {
    _childName = TextEditingController(text: data.childName);
    _homeAddress = TextEditingController(text: data.homeAddress);
    _parentName = TextEditingController(text: data.parentName);
    _parentPhone = TextEditingController(text: data.parentPhone);
    _medicalNotes = TextEditingController(text: data.medicalNotes);
    _emergencyEnabled = data.emergencyEnabled;
    _initialized = true;
  }

  @override
  void dispose() {
    if (_initialized) {
      _childName.dispose();
      _homeAddress.dispose();
      _parentName.dispose();
      _parentPhone.dispose();
      _medicalNotes.dispose();
    }
    super.dispose();
  }

  Future<void> _save(SessionState session) async {
    setState(() => _saving = true);
    try {
      await session.profiles.setEmergency(
        widget.profileId,
        EmergencyProfileData(
          childName: _childName.text.trim(),
          homeAddress: _homeAddress.text.trim(),
          parentName: _parentName.text.trim(),
          parentPhone: _parentPhone.text.trim(),
          medicalNotes: _medicalNotes.text.trim(),
          emergencyEnabled: _emergencyEnabled,
        ),
      );
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Emergency details saved.')),
      );
    } finally {
      if (mounted) setState(() => _saving = false);
    }
    widget.onChanged?.call();
  }

  @override
  Widget build(BuildContext context) {
    final session = context.watch<SessionState>();
    if (!_initialized) _initFrom(_data(session));
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        if (!widget.compact)
          const Padding(
            padding: EdgeInsets.fromLTRB(12, 4, 12, 8),
            child: Text(
              'Used to fill the placeholders in call phrases — for '
              'example, {child_name} becomes the name you enter here. '
              'Nothing here is shared anywhere until a phrase that uses '
              'it is spoken or sent.',
              style: TextStyle(fontSize: 13),
            ),
          ),
        SwitchListTile(
          title: const Text(
            'Emergency button',
            style: TextStyle(fontSize: 14, fontWeight: FontWeight.w600),
          ),
          subtitle: const Text(
            'Shows an emergency button on the home board for this profile.',
            style: TextStyle(fontSize: 12),
          ),
          value: _emergencyEnabled,
          onChanged: _saving
              ? null
              : (v) => setState(() => _emergencyEnabled = v),
        ),
        Padding(
          padding: const EdgeInsets.fromLTRB(12, 4, 12, 0),
          child: TextField(
            controller: _childName,
            textCapitalization: TextCapitalization.words,
            decoration: const InputDecoration(
              labelText: 'Child\u2019s name',
              hintText: 'Fills {child_name}',
              border: OutlineInputBorder(),
            ),
          ),
        ),
        Padding(
          padding: const EdgeInsets.fromLTRB(12, 8, 12, 0),
          child: TextField(
            controller: _homeAddress,
            textCapitalization: TextCapitalization.words,
            maxLines: 2,
            minLines: 1,
            decoration: const InputDecoration(
              labelText: 'Home address',
              hintText: 'Fills {home_address}',
              border: OutlineInputBorder(),
            ),
          ),
        ),
        Padding(
          padding: const EdgeInsets.fromLTRB(12, 8, 12, 0),
          child: TextField(
            controller: _parentName,
            textCapitalization: TextCapitalization.words,
            decoration: const InputDecoration(
              labelText: 'Parent or caregiver name',
              hintText: 'Fills {parent_name}',
              border: OutlineInputBorder(),
            ),
          ),
        ),
        Padding(
          padding: const EdgeInsets.fromLTRB(12, 8, 12, 0),
          child: TextField(
            controller: _parentPhone,
            keyboardType: TextInputType.phone,
            decoration: const InputDecoration(
              labelText: 'Parent or caregiver phone',
              hintText: 'Fills {parent_phone}',
              border: OutlineInputBorder(),
            ),
          ),
        ),
        Padding(
          padding: const EdgeInsets.fromLTRB(12, 8, 12, 0),
          child: TextField(
            controller: _medicalNotes,
            maxLines: 3,
            minLines: 2,
            textCapitalization: TextCapitalization.sentences,
            decoration: const InputDecoration(
              labelText: 'Medical notes (optional)',
              hintText: 'Allergies, conditions — only used in an emergency',
              border: OutlineInputBorder(),
            ),
          ),
        ),
        Padding(
          padding: const EdgeInsets.fromLTRB(12, 12, 12, 0),
          child: FilledButton.icon(
            icon: _saving
                ? const SizedBox(
                    width: 16,
                    height: 16,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                : const Icon(Icons.save_outlined, size: 18),
            label: const Text('Save emergency details'),
            onPressed: _saving ? null : () => _save(session),
          ),
        ),
      ],
    );
  }
}

/// The two calling-safety preference toggles. Each toggle saves
/// immediately through [ProfileService.setSafety].
class SafetyTogglesCard extends StatefulWidget {
  const SafetyTogglesCard({
    super.key,
    required this.profileId,
    this.onChanged,
  });

  final String profileId;
  final VoidCallback? onChanged;

  @override
  State<SafetyTogglesCard> createState() => _SafetyTogglesCardState();
}

class _SafetyTogglesCardState extends State<SafetyTogglesCard> {
  bool _saving = false;

  SafetySettings _settings(SessionState session) {
    for (final p in session.profiles.profiles) {
      if (p.id == widget.profileId) return p.safety;
    }
    return SafetySettings();
  }

  Future<void> _set(SessionState session, SafetySettings next) async {
    setState(() => _saving = true);
    try {
      await session.profiles.setSafety(widget.profileId, next);
    } finally {
      if (mounted) setState(() => _saving = false);
    }
    widget.onChanged?.call();
  }

  @override
  Widget build(BuildContext context) {
    final session = context.watch<SessionState>();
    final settings = _settings(session);
    return Column(
      children: [
        SwitchListTile(
          title: const Text(
            'AI phrase suggestions',
            style: TextStyle(fontSize: 14, fontWeight: FontWeight.w600),
          ),
          subtitle: const Text(
            'Suggest helpful phrases during a call based on what\u2019s '
            'happening. Suggestions never replace your own phrase bank.',
            style: TextStyle(fontSize: 12),
          ),
          value: settings.aiSuggestions,
          onChanged: _saving
              ? null
              : (v) => _set(
                  session,
                  SafetySettings(
                    aiSuggestions: v,
                    preferOwnPhrases: settings.preferOwnPhrases,
                  ),
                ),
        ),
        SwitchListTile(
          title: const Text(
            'Prefer my phrases',
            style: TextStyle(fontSize: 14, fontWeight: FontWeight.w600),
          ),
          subtitle: const Text(
            'When on, your phrase bank is always offered first — AI '
            'suggestions only fill the gaps.',
            style: TextStyle(fontSize: 12),
          ),
          value: settings.preferOwnPhrases,
          onChanged: _saving
              ? null
              : (v) => _set(
                  session,
                  SafetySettings(
                    aiSuggestions: settings.aiSuggestions,
                    preferOwnPhrases: v,
                  ),
                ),
        ),
      ],
    );
  }
}
