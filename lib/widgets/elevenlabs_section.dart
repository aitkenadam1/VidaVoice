import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../services/elevenlabs_service.dart';
import '../services/proxy_client.dart';
import '../services/tts_service.dart';
import '../services/voice_sample_recorder.dart';
import '../state/session_state.dart';
import 'proxy_account_form.dart';

/// AI cloud voices.
///
/// The primary path is the managed ("included") cloud voices: a VidaVoice
/// account adds AI voices on up to 3 devices, billed through the family's
/// shared monthly quota — no API key needed.
///
/// Below that, collapsed under "Advanced", is the original
/// bring-your-own-key ElevenLabs UI, verbatim: the caregiver pastes their
/// own ElevenLabs API key (stored in the platform keychain, never in
/// backups or logs), then clones a voice from microphone recordings or
/// picks one from their ElevenLabs library. Usage is billed to their
/// ElevenLabs account and needs internet. Any cloud failure falls back to
/// on-device voices — the board never goes silent.
class ElevenLabsSection extends StatefulWidget {
  const ElevenLabsSection({super.key, required this.onVoicesChanged});

  /// Called after the saved-voice list changes so the voice picker reloads.
  final VoidCallback onVoicesChanged;

  @override
  State<ElevenLabsSection> createState() => _ElevenLabsSectionState();
}

class _ElevenLabsSectionState extends State<ElevenLabsSection> {
  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _ProxyVoiceCard(onVoicesChanged: widget.onVoicesChanged),
        const SizedBox(height: 8),
        Card(
          child: ExpansionTile(
            leading: const Icon(Icons.key_outlined),
            title: const Text('Advanced: use my own ElevenLabs key'),
            subtitle: const Text(
              'Clone a voice with your own ElevenLabs account',
              style: TextStyle(fontSize: 12),
            ),
            children: [
              _ByoElevenLabsContent(onVoicesChanged: widget.onVoicesChanged),
            ],
          ),
        ),
      ],
    );
  }
}

/// The managed ("included") cloud voices card: sign-in when signed out,
/// the family's entitlement voices with quota when signed in.
class _ProxyVoiceCard extends StatefulWidget {
  const _ProxyVoiceCard({required this.onVoicesChanged});

  /// Called after the voice choice changes so the voice picker reloads.
  final VoidCallback onVoicesChanged;

  @override
  State<_ProxyVoiceCard> createState() => _ProxyVoiceCardState();
}

class _ProxyVoiceCardState extends State<_ProxyVoiceCard> {
  bool _loading = false;
  bool _loadedSignedIn = false;
  String? _error;
  List<ProxyVoice> _voices = const [];
  String? _quotaLine;

  @override
  void initState() {
    super.initState();
    _loadedSignedIn = context.read<SessionState>().proxySignedIn;
    if (_loadedSignedIn) {
      WidgetsBinding.instance.addPostFrameCallback((_) => _load());
    }
  }

  Future<void> _load({bool force = false}) async {
    final session = context.read<SessionState>();
    if (!session.proxySignedIn) return;
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final voices = await session.proxyEntitlement(force: force);
      final usage = await session.proxyUsage();
      if (!mounted) return;
      setState(() {
        _loading = false;
        _voices = voices;
        _quotaLine = usage == null
            ? null
            : '${usage.used} of ${usage.monthlyCap} characters used this month';
      });
    } on ProxyException catch (e) {
      if (!mounted) return;
      setState(() {
        _loading = false;
        _error = e.code == 'unreachable'
            ? 'Couldn\u2019t reach the VidaVoice service. Your board works '
                  'fully offline \u2014 cloud voices need an account and '
                  'internet.'
            : e.message;
      });
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _loading = false;
        _error = 'Something went wrong. Please try again.';
      });
    }
  }

  Future<void> _useVoice(ProxyVoice voice) async {
    final session = context.read<SessionState>();
    await session.setVoice(
      TtsVoice(name: voice.name, locale: voice.locale, proxyVoiceId: voice.id),
    );
    await session.speakText(_previewFor(session.currentLocale));
    widget.onVoicesChanged();
  }

  Future<void> _signOut() async {
    await context.read<SessionState>().signOut();
    widget.onVoicesChanged();
  }

  @override
  Widget build(BuildContext context) {
    final session = context.watch<SessionState>();
    // Reload when the sign-in state flips under us (e.g. signed in from
    // the inline form below, or signed out from the caregiver hub).
    if (session.proxySignedIn != _loadedSignedIn) {
      _loadedSignedIn = session.proxySignedIn;
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) {
          if (_loadedSignedIn) {
            _load();
          } else {
            setState(() {
              _voices = const [];
              _quotaLine = null;
              _error = null;
            });
          }
        }
      });
    }

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                const Icon(Icons.cloud_outlined),
                const SizedBox(width: 8),
                const Expanded(
                  child: Text(
                    'AI cloud voices (included)',
                    style: TextStyle(fontSize: 15, fontWeight: FontWeight.w600),
                  ),
                ),
                if (session.proxySignedIn)
                  IconButton(
                    tooltip: 'Refresh',
                    icon: const Icon(Icons.refresh, size: 20),
                    onPressed: _loading ? null : () => _load(force: true),
                  ),
              ],
            ),
            const SizedBox(height: 8),
            if (!session.proxySignedIn) ...[
              const Text(
                'A VidaVoice account adds AI cloud voices on up to 3 '
                'devices, with a shared monthly quota \u2014 no API key '
                'needed. Sign up below, or keep using on-device voices: '
                'nothing changes.',
                style: TextStyle(fontSize: 12),
              ),
              const SizedBox(height: 12),
              const ProxyAccountForm(),
            ] else ...[
              if (session.deviceLimitNotice != null) ...[
                Card(
                  color: Theme.of(context).colorScheme.errorContainer,
                  child: Padding(
                    padding: const EdgeInsets.all(12),
                    child: Row(
                      children: [
                        const Icon(Icons.warning_amber_outlined),
                        const SizedBox(width: 8),
                        Expanded(
                          child: Text(
                            session.deviceLimitNotice!,
                            style: const TextStyle(fontSize: 12),
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
                const SizedBox(height: 8),
              ],
              if (_loading && _voices.isEmpty)
                const Center(child: CircularProgressIndicator())
              else if (_error != null && _voices.isEmpty)
                Text(
                  _error!,
                  style: TextStyle(
                    fontSize: 12,
                    color: Theme.of(context).colorScheme.error,
                  ),
                )
              else ...[
                if (_voices.isEmpty)
                  const Text(
                    'No cloud voices on your account yet.',
                    style: TextStyle(fontSize: 12),
                  ),
                for (final v in _voices)
                  ListTile(
                    dense: true,
                    contentPadding: EdgeInsets.zero,
                    leading: const Icon(Icons.cloud_done_outlined, size: 20),
                    title: Text(v.name, style: const TextStyle(fontSize: 13)),
                    subtitle: v.locale.isEmpty
                        ? null
                        : Text(v.locale, style: const TextStyle(fontSize: 11)),
                    trailing: session.currentVoice?.proxyVoiceId == v.id
                        ? const Icon(Icons.check, color: Colors.green, size: 20)
                        : TextButton(
                            onPressed: () => _useVoice(v),
                            child: const Text('Use'),
                          ),
                  ),
                if (_quotaLine != null) ...[
                  const SizedBox(height: 4),
                  Text(
                    _quotaLine!,
                    style: TextStyle(
                      fontSize: 12,
                      color: Theme.of(context).colorScheme.onSurfaceVariant,
                    ),
                  ),
                ],
                Align(
                  alignment: Alignment.centerRight,
                  child: TextButton(
                    onPressed: _signOut,
                    child: const Text('Sign out'),
                  ),
                ),
              ],
            ],
          ],
        ),
      ),
    );
  }
}

/// The bring-your-own-key ElevenLabs UI, unchanged: key field, account
/// voices, clone dialog, saved voices, consent, purge, and createdByApp
/// deletion. Lives collapsed under "Advanced" — the managed cloud voices
/// above are the primary path now.
class _ByoElevenLabsContent extends StatefulWidget {
  const _ByoElevenLabsContent({required this.onVoicesChanged});

  /// Called after the saved-voice list changes so the voice picker reloads.
  final VoidCallback onVoicesChanged;

  @override
  State<_ByoElevenLabsContent> createState() => _ByoElevenLabsContentState();
}

class _ByoElevenLabsContentState extends State<_ByoElevenLabsContent> {
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
    // Voices this app cloned can also be deleted from the ElevenLabs
    // account (after confirmation). Account/library voices are only ever
    // removed locally — the app must never delete those from the cloud.
    final svc = _session.tts.elevenLabs;
    if (voice.createdByApp && svc != null) {
      final choice = await _confirmRemove(context, voice);
      if (choice == null || !mounted) return; // cancelled
      if (choice) {
        try {
          await svc.deleteVoice(voice.id);
        } on ElevenLabsException catch (e) {
          if (mounted) {
            setState(
              () => _error =
                  'Removed here, but could not delete it from ElevenLabs: ${e.message}',
            );
          }
        }
      }
    }
    await _session.elevenLabsVoices.remove(id, voice.id);
    if (_session.currentVoice?.elevenLabsVoiceId == voice.id) {
      await _session.clearVoice();
    }
    await _loadSaved();
    widget.onVoicesChanged();
  }

  /// For app-created clones: null = cancelled, false = remove locally only,
  /// true = also delete the clone from the ElevenLabs account.
  Future<bool?> _confirmRemove(
    BuildContext context,
    SavedElevenLabsVoice voice,
  ) {
    return showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text('Remove "${voice.name}"?'),
        content: const Text(
          'Remove this voice from the profile? You can also delete the '
          'clone from your ElevenLabs account so it no longer exists in '
          'the cloud.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(),
            child: const Text('Cancel'),
          ),
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(false),
            child: const Text('Remove here only'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(ctx).pop(true),
            child: const Text('Delete everywhere'),
          ),
        ],
      ),
    );
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
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Row(
            children: [
              Icon(Icons.cloud_outlined),
              SizedBox(width: 8),
              Text(
                'AI cloud voices (ElevenLabs) · advanced',
                style: TextStyle(fontSize: 15, fontWeight: FontWeight.w600),
              ),
            ],
          ),
          const SizedBox(height: 8),
          const Text(
            'Optional, advanced. Clone a custom voice — for example the '
            "communicator's own voice — with your own ElevenLabs account "
            'and API key. ElevenLabs bills per character spoken and needs '
            'internet; repeated taps of the same button are cached so '
            'they are not billed twice. Everything else in the app keeps '
            'working offline.',
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
                      : Text(v.category, style: const TextStyle(fontSize: 11)),
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
                subtitle: Text(
                  v.createdByApp
                      ? 'ElevenLabs · cloned in this app'
                      : 'ElevenLabs · cloud voice',
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
  // Test seam lives in VoiceSampleRecorder.createForDialog: widget tests
  // inject a fake recorder so the dialog works without a microphone.
  final _recorder = VoiceSampleRecorder.createForDialog();
  final _samples = <VoiceSample>[];
  bool _recording = false;
  bool _busy = false;
  String? _error;

  @override
  void dispose() {
    _nameController.dispose();
    _recorder.cancelSample();
    // The dialog is going away without a successful clone: purge any
    // recordings already made so temp files never linger on the device.
    unawaited(_purgeSampleFiles(_samples));
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
    // Deleting a sample must also remove its recording from the device —
    // removing the list entry alone would orphan the temp file.
    unawaited(_purgeSampleFiles([sample]));
  }

  /// Best-effort deletion of sample files. Used when a sample is removed
  /// individually, when the dialog is dismissed without cloning, and after
  /// a successful upload.
  static Future<void> _purgeSampleFiles(Iterable<VoiceSample> samples) async {
    final debugDelete = VoiceSampleRecorder.debugDeleterForDialog();
    for (final s in samples) {
      try {
        if (debugDelete != null) {
          await debugDelete(s.path);
        } else {
          await File(s.path).delete();
        }
      } catch (_) {
        // Best effort — a leftover temp file is harmless.
      }
    }
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
    // Consent gate: a child's voice leaves the device here. Say exactly
    // what is uploaded, to whom, and how to undo it.
    final consented = await _confirmUpload(context, _samples.length, _total);
    if (consented != true || !mounted) return;
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
        createdByApp: true,
      );
      await session.elevenLabsVoices.add(profileId, saved);
      // The recordings served their purpose — delete them from the device.
      await _deleteLocalSamples();
      if (!mounted) return;
      Navigator.of(context).pop(saved);
    } on ElevenLabsException catch (e) {
      if (!mounted) return;
      setState(() => _error = e.message);
    } catch (_) {
      // cloneVoice only throws ElevenLabsException today; this is a
      // backstop so an unexpected error can never freeze the dialog.
      if (!mounted) return;
      setState(() => _error = 'Something went wrong. Please try again.');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  /// Deletes the local sample files after a successful upload.
  Future<void> _deleteLocalSamples() async {
    await _purgeSampleFiles(_samples);
    _samples.clear();
  }

  /// Consent screen shown before any audio leaves the device. Returns true
  /// when the caregiver explicitly taps "Upload & create".
  Future<bool?> _confirmUpload(
    BuildContext context,
    int sampleCount,
    Duration total,
  ) {
    return showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Upload recordings to ElevenLabs?'),
        content: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'The $sampleCount recording(s) (about ${_formatDuration(total)} '
                'total) will be uploaded to ElevenLabs (elevenlabs.io) to '
                'create a voice clone on YOUR ElevenLabs account.',
                style: const TextStyle(fontSize: 13),
              ),
              const SizedBox(height: 8),
              const Text(
                '• The clone is stored on ElevenLabs\u2019 servers under your '
                'account and counts toward your plan\u2019s voice limit.\n'
                '• Speech with this voice is billed per character by '
                'ElevenLabs.\n'
                '• The recordings are deleted from this device after upload.\n'
                '• You can delete the cloned voice from ElevenLabs at any '
                'time from this screen.',
                style: TextStyle(fontSize: 13),
              ),
              const SizedBox(height: 8),
              const Text(
                'Only clone a voice you have the right to use (your child\u2019s '
                'or your own).',
                style: TextStyle(fontSize: 13, fontWeight: FontWeight.w600),
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
            onPressed: () => Navigator.of(ctx).pop(true),
            child: const Text('Upload & create'),
          ),
        ],
      ),
    );
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
              'ElevenLabs needs at least 30 seconds total across 1–3 clips '
              '(a minute or more is better). The audio is uploaded to '
              'ElevenLabs only after you review and confirm on the next '
              'screen.',
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
                Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Total: ${_formatDuration(_total)}',
                      style: const TextStyle(fontSize: 12),
                    ),
                    if (_samples.isNotEmpty &&
                        _total < const Duration(seconds: 30))
                      const Text(
                        'Under 30s — the clone may fail or sound poor.',
                        style: TextStyle(fontSize: 11, color: Colors.orange),
                      ),
                  ],
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
