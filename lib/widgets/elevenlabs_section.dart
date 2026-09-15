import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../services/elevenlabs_service.dart';
import '../services/tts_service.dart';
import '../services/voice_sample_recorder.dart';
import '../state/session_state.dart';

/// ElevenLabs cloud voices (bring-your-own-key).
///
/// Optional and off by default: the caregiver pastes their own ElevenLabs
/// API key (stored in the platform keychain, never in backups or logs),
/// then clones a voice from microphone recordings or picks one from their
/// ElevenLabs library. Usage is billed to their ElevenLabs account and
/// needs internet. Any cloud failure falls back to on-device voices —
/// the board never goes silent.
class ElevenLabsSection extends StatefulWidget {
  const ElevenLabsSection({super.key, required this.onVoicesChanged});

  /// Called after the saved-voice list changes so the voice picker reloads.
  final VoidCallback onVoicesChanged;

  @override
  State<ElevenLabsSection> createState() => _ElevenLabsSectionState();
}

class _ElevenLabsSectionState extends State<ElevenLabsSection> {
  final _keyController = TextEditingController();
  bool? _keySet;
  bool _busy = false;
  String? _error;
  List<ElevenLabsVoice>? _accountVoices;
  List<SavedElevenLabsVoice> _savedVoices = const [];

  SessionState get _session => context.read<SessionState>();

  @override
  void initState() {
    super.initState();
    _checkKey();
  }

  @override
  void dispose() {
    _keyController.dispose();
    super.dispose();
  }

  Future<void> _checkKey() async {
    final key = await _session.elevenLabsKeys.readKey();
    if (!mounted) return;
    setState(() => _keySet = key != null);
    if (key != null) _loadSaved();
  }

  Future<void> _loadSaved() async {
    final id = _session.profiles.active?.id;
    if (id == null) return;
    final voices = await _session.elevenLabsVoices.load(id);
    if (mounted) setState(() => _savedVoices = voices);
  }

  Future<void> _saveKey() async {
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      await _session.elevenLabsKeys.saveKey(_keyController.text);
      await _session.refreshElevenLabs();
      _keyController.clear();
      if (!mounted) return;
      setState(() {
        _keySet = true;
        _busy = false;
      });
      await _loadSaved();
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _busy = false;
        _error = 'Could not save the key. Try again.';
      });
    }
  }

  Future<void> _clearKey() async {
    setState(() {
      _busy = true;
      _error = null;
    });
    await _session.elevenLabsKeys.clearKey();
    await _session.refreshElevenLabs();
    // A cloud voice choice is meaningless without a key.
    if (_session.currentVoice?.isElevenLabs ?? false) {
      await _session.clearVoice();
    }
    if (!mounted) return;
    setState(() {
      _busy = false;
      _keySet = false;
      _accountVoices = null;
    });
    widget.onVoicesChanged();
  }

  Future<void> _refreshAccountVoices() async {
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      final svc = _session.tts.elevenLabs;
      if (svc == null) {
        throw const ElevenLabsException('Enter an API key first.');
      }
      final voices = await svc.listVoices();
      if (!mounted) return;
      setState(() {
        _busy = false;
        _accountVoices = voices;
      });
    } on ElevenLabsException catch (e) {
      if (!mounted) return;
      setState(() {
        _busy = false;
        _error = e.message;
      });
    }
  }

  Future<void> _saveToProfile(ElevenLabsVoice voice) async {
    final id = _session.profiles.active?.id;
    if (id == null) return;
    await _session.elevenLabsVoices.add(
      id,
      SavedElevenLabsVoice(
        id: voice.id,
        name: voice.name,
        locale: _session.currentLocale,
      ),
    );
    await _loadSaved();
    widget.onVoicesChanged();
  }

  Future<void> _removeSaved(SavedElevenLabsVoice voice) async {
    final id = _session.profiles.active?.id;
    if (id == null) return;
    await _session.elevenLabsVoices.remove(id, voice.id);
    if (_session.currentVoice?.elevenLabsVoiceId == voice.id) {
      await _session.clearVoice();
    }
    await _loadSaved();
    widget.onVoicesChanged();
  }

  Future<void> _useVoice(SavedElevenLabsVoice voice) async {
    await _session.setVoice(
      TtsVoice(
        name: voice.name,
        locale: voice.locale,
        elevenLabsVoiceId: voice.id,
      ),
    );
    await _session.speakText(_previewFor(_session.currentLocale));
    widget.onVoicesChanged();
  }

  Future<void> _clone() async {
    final created = await showDialog<SavedElevenLabsVoice>(
      context: context,
      builder: (_) => const _CloneVoiceDialog(),
    );
    if (created != null && mounted) {
      await _loadSaved();
      widget.onVoicesChanged();
      await _useVoice(created);
    }
  }

  @override
  Widget build(BuildContext context) {
    final keySet = _keySet;
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Row(
              children: [
                Icon(Icons.cloud_outlined),
                SizedBox(width: 8),
                Text(
                  'AI cloud voices (ElevenLabs)',
                  style: TextStyle(fontSize: 15, fontWeight: FontWeight.w600),
                ),
              ],
            ),
            const SizedBox(height: 8),
            const Text(
              'Optional. Clone a custom voice — for example the '
              "communicator's own voice — with your own ElevenLabs account. "
              'Usage is billed by ElevenLabs and needs internet; everything '
              'else in the app keeps working offline.',
              style: TextStyle(fontSize: 12),
            ),
            const SizedBox(height: 12),
            if (keySet == null)
              const Center(child: CircularProgressIndicator())
            else if (!keySet) ...[
              const Text(
                'Paste an ElevenLabs API key to begin. The key is stored in '
                'this device\u2019s secure storage — never in backups.',
                style: TextStyle(fontSize: 12),
              ),
              const SizedBox(height: 8),
              Row(
                children: [
                  Expanded(
                    child: TextField(
                      controller: _keyController,
                      obscureText: true,
                      enableSuggestions: false,
                      autocorrect: false,
                      decoration: const InputDecoration(
                        labelText: 'ElevenLabs API key',
                        border: OutlineInputBorder(),
                        isDense: true,
                      ),
                      onSubmitted: (_) => _saveKey(),
                    ),
                  ),
                  const SizedBox(width: 8),
                  FilledButton(
                    onPressed: _busy ? null : _saveKey,
                    child: const Text('Save'),
                  ),
                ],
              ),
            ] else ...[
              Row(
                children: [
                  const Icon(Icons.check_circle, color: Colors.green, size: 18),
                  const SizedBox(width: 8),
                  const Expanded(
                    child: Text(
                      'API key saved on this device.',
                      style: TextStyle(fontSize: 12),
                    ),
                  ),
                  TextButton(
                    onPressed: _busy ? null : _clearKey,
                    child: const Text('Remove key'),
                  ),
                ],
              ),
              const SizedBox(height: 8),
              Wrap(
                spacing: 8,
                children: [
                  OutlinedButton.icon(
                    onPressed: _busy ? null : _refreshAccountVoices,
                    icon: const Icon(Icons.refresh, size: 18),
                    label: const Text('My ElevenLabs voices'),
                  ),
                  FilledButton.icon(
                    onPressed: _busy ? null : _clone,
                    icon: const Icon(Icons.mic_outlined, size: 18),
                    label: const Text('Clone a new voice'),
                  ),
                ],
              ),
              if (_busy) ...[
                const SizedBox(height: 12),
                const Center(child: CircularProgressIndicator()),
              ],
              if (_accountVoices != null) ...[
                const SizedBox(height: 12),
                const Text(
                  'Voices on your ElevenLabs account:',
                  style: TextStyle(fontSize: 13, fontWeight: FontWeight.w600),
                ),
                if (_accountVoices!.isEmpty)
                  const Padding(
                    padding: EdgeInsets.only(top: 4),
                    child: Text(
                      'No voices found. Clone one above to get started.',
                      style: TextStyle(fontSize: 12),
                    ),
                  ),
                for (final v in _accountVoices!)
                  ListTile(
                    dense: true,
                    contentPadding: EdgeInsets.zero,
                    title: Text(v.name, style: const TextStyle(fontSize: 13)),
                    subtitle: v.category.isEmpty
                        ? null
                        : Text(
                            v.category,
                            style: const TextStyle(fontSize: 11),
                          ),
                    trailing: TextButton(
                      onPressed: () => _saveToProfile(v),
                      child: const Text('Add'),
                    ),
                  ),
              ],
              const SizedBox(height: 12),
              const Text(
                'Saved for this profile:',
                style: TextStyle(fontSize: 13, fontWeight: FontWeight.w600),
              ),
              if (_savedVoices.isEmpty)
                const Padding(
                  padding: EdgeInsets.only(top: 4),
                  child: Text(
                    'None yet. Cloned voices appear here and in Voice choice above.',
                    style: TextStyle(fontSize: 12),
                  ),
                ),
              for (final v in _savedVoices)
                ListTile(
                  dense: true,
                  contentPadding: EdgeInsets.zero,
                  leading: const Icon(Icons.cloud_done_outlined, size: 20),
                  title: Text(v.name, style: const TextStyle(fontSize: 13)),
                  subtitle: const Text(
                    'ElevenLabs · cloud voice',
                    style: TextStyle(fontSize: 11),
                  ),
                  trailing: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      TextButton(
                        onPressed: () => _useVoice(v),
                        child: const Text('Use'),
                      ),
                      IconButton(
                        icon: const Icon(Icons.delete_outline, size: 20),
                        tooltip: 'Remove from profile',
                        onPressed: () => _removeSaved(v),
                      ),
                    ],
                  ),
                ),
            ],
            if (_error != null) ...[
              const SizedBox(height: 8),
              Text(
                _error!,
                style: const TextStyle(fontSize: 12, color: Colors.red),
              ),
            ],
          ],
        ),
      ),
    );
  }
}

/// Preview sentence reused from the voice picker.
String _previewFor(String locale) {
  switch (locale) {
    case 'es':
      return 'Hola, esta es mi voz.';
    case 'fr':
      return 'Bonjour, c\u2019est ma voix.';
    default:
      return 'Hello, this is my voice.';
  }
}

/// Dialog that records voice samples and creates an ElevenLabs clone.
///
/// Nothing is uploaded until the caregiver taps "Create voice".
class _CloneVoiceDialog extends StatefulWidget {
  const _CloneVoiceDialog();

  @override
  State<_CloneVoiceDialog> createState() => _CloneVoiceDialogState();
}

class _CloneVoiceDialogState extends State<_CloneVoiceDialog> {
  final _nameController = TextEditingController();
  final _recorder = VoiceSampleRecorder();
  final _samples = <VoiceSample>[];
  bool _recording = false;
  bool _busy = false;
  String? _error;

  @override
  void dispose() {
    _nameController.dispose();
    _recorder.cancelSample();
    super.dispose();
  }

  Duration get _total =>
      _samples.fold(Duration.zero, (sum, s) => sum + s.duration);

  Future<void> _toggleRecording() async {
    if (_busy) return;
    if (_recording) {
      setState(() => _busy = true);
      try {
        final sample = await _recorder.stopSample();
        if (!mounted) return;
        setState(() {
          _samples.add(sample);
          _recording = false;
          _busy = false;
          _error = null;
        });
      } on VoiceSampleException catch (e) {
        if (!mounted) return;
        setState(() {
          _recording = false;
          _busy = false;
          _error = e.message;
        });
      }
      return;
    }
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      await _recorder.startSample();
      if (!mounted) return;
      setState(() {
        _recording = true;
        _busy = false;
      });
    } on VoiceSampleException catch (e) {
      if (!mounted) return;
      setState(() {
        _busy = false;
        _error = e.message;
      });
    }
  }

  void _deleteSample(VoiceSample sample) {
    setState(() => _samples.remove(sample));
  }

  Future<void> _create() async {
    final session = context.read<SessionState>();
    final profileId = session.profiles.active?.id;
    final svc = session.tts.elevenLabs;
    if (profileId == null) {
      setState(() => _error = 'No active profile.');
      return;
    }
    if (svc == null) {
      setState(() => _error = 'Enter an API key first.');
      return;
    }
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      final voiceId = await svc.cloneVoice(
        name: _nameController.text,
        samples: _samples,
      );
      final saved = SavedElevenLabsVoice(
        id: voiceId,
        name: _nameController.text.trim(),
        locale: session.currentLocale,
      );
      await session.elevenLabsVoices.add(profileId, saved);
      if (!mounted) return;
      Navigator.of(context).pop(saved);
    } on ElevenLabsException catch (e) {
      if (!mounted) return;
      setState(() {
        _busy = false;
        _error = e.message;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final canCreate =
        !_busy &&
        !_recording &&
        _nameController.text.trim().isNotEmpty &&
        _samples.isNotEmpty;
    return AlertDialog(
      title: const Text('Clone a voice'),
      content: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              'Record clear speech — reading the phrases below works well. '
              'Aim for at least a minute total across 1–3 clips; more is '
              'better. The audio is uploaded to ElevenLabs only when you '
              'tap \u201cCreate voice\u201d.',
              style: TextStyle(fontSize: 12),
            ),
            const SizedBox(height: 8),
            const Text(
              '\u201cI want juice, please.\u201d \u00b7 \u201cI am happy today.\u201d \u00b7 \u201cLet\u2019s go outside and play.\u201d',
              style: TextStyle(fontSize: 12, fontStyle: FontStyle.italic),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: _nameController,
              decoration: const InputDecoration(
                labelText: 'Voice name (e.g. \u201cMaya\u2019s voice\u201d)',
                border: OutlineInputBorder(),
                isDense: true,
              ),
              onChanged: (_) => setState(() {}),
            ),
            const SizedBox(height: 12),
            for (final s in _samples)
              ListTile(
                dense: true,
                contentPadding: EdgeInsets.zero,
                leading: const Icon(Icons.audio_file_outlined, size: 20),
                title: Text(
                  'Sample ${_samples.indexOf(s) + 1} · ${_formatDuration(s.duration)}',
                  style: const TextStyle(fontSize: 13),
                ),
                trailing: IconButton(
                  icon: const Icon(Icons.delete_outline, size: 20),
                  onPressed: _busy ? null : () => _deleteSample(s),
                ),
              ),
            Row(
              children: [
                FilledButton.icon(
                  onPressed: _busy ? null : _toggleRecording,
                  icon: Icon(_recording ? Icons.stop : Icons.mic, size: 18),
                  label: Text(_recording ? 'Stop' : 'Record a sample'),
                  style: _recording
                      ? FilledButton.styleFrom(backgroundColor: Colors.red)
                      : null,
                ),
                const SizedBox(width: 12),
                Text(
                  'Total: ${_formatDuration(_total)}',
                  style: const TextStyle(fontSize: 12),
                ),
              ],
            ),
            if (_recording)
              const Padding(
                padding: EdgeInsets.only(top: 8),
                child: Text(
                  'Recording\u2026 speak clearly into the microphone.',
                  style: TextStyle(fontSize: 12, color: Colors.red),
                ),
              ),
            if (_error != null) ...[
              const SizedBox(height: 8),
              Text(
                _error!,
                style: const TextStyle(fontSize: 12, color: Colors.red),
              ),
            ],
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: _busy ? null : () => Navigator.of(context).pop(),
          child: const Text('Cancel'),
        ),
        FilledButton(
          onPressed: canCreate ? _create : null,
          child: _busy && !_recording
              ? const SizedBox(
                  width: 18,
                  height: 18,
                  child: CircularProgressIndicator(strokeWidth: 2),
                )
              : const Text('Create voice'),
        ),
      ],
    );
  }
}

String _formatDuration(Duration d) {
  final m = d.inMinutes;
  final s = d.inSeconds % 60;
  return '${m}m ${s.toString().padLeft(2, '0')}s';
}
