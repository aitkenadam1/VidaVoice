import 'dart:async';

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../app_config.dart';
import '../services/kokoro_tts_service.dart';
import '../services/personal_voice_service.dart';
import '../services/tts_service.dart';
import '../state/session_state.dart';
import '../widgets/elevenlabs_section.dart';

/// Settings: language, voice (rate + pitch), and button size.
///
/// Deliberately NOT here: grid column count. Word positions are fixed in
/// the language pack for motor planning — changing the column count would
/// move every word on screen, so the layout is locked by design.
class SettingsScreen extends StatefulWidget {
  const SettingsScreen({super.key});

  @override
  State<SettingsScreen> createState() => _SettingsScreenState();
}

class _SettingsScreenState extends State<SettingsScreen> {
  late double _rate;
  late double _pitch;
  bool _loaded = false;
  // Bumped when the Kokoro model becomes ready so the voice picker reloads
  // (the picker only loads its list in initState).
  int _voiceListVersion = 0;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (!_loaded) {
      final tts = context.read<SessionState>().tts;
      _rate = tts.rate;
      _pitch = tts.pitch;
      _loaded = true;
    }
  }

  @override
  Widget build(BuildContext context) {
    final session = context.watch<SessionState>();
    return Scaffold(
      appBar: AppBar(title: const Text('Settings')),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          _sectionTitle(context, 'Language'),
          Card(
            child: RadioGroup<String>(
              groupValue: session.currentLocale,
              onChanged: (v) {
                if (v != null) session.setLocale(v);
              },
              child: Column(
                children: [
                  for (final locale in AppConfig.supportedLocales)
                    RadioListTile<String>(
                      title: Text(AppConfig.localeNames[locale] ?? locale),
                      subtitle: switch (locale) {
                        'es' => const Text(
                          'Traducción preliminar — pendiente de revisión por un especialista.',
                        ),
                        'fr' => const Text(
                          'Traduction préliminaire — en attente de révision par un spécialiste.',
                        ),
                        _ => null,
                      },
                      value: locale,
                    ),
                ],
              ),
            ),
          ),
          const Padding(
            padding: EdgeInsets.only(top: 4, left: 4),
            child: Text(
              'Switching language changes every word label and the speaking '
              'voice, but never moves a word — positions are identical in '
              'every language. The message bar clears on switch.',
              style: TextStyle(fontSize: 12),
            ),
          ),
          const SizedBox(height: 16),
          _sectionTitle(context, 'Voice'),
          Card(
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                children: [
                  Row(
                    children: [
                      const Icon(Icons.speed_outlined),
                      Expanded(
                        child: Slider(
                          value: _rate,
                          min: 0.3,
                          max: 1.0,
                          divisions: 14,
                          label: 'Speed ${_rate.toStringAsFixed(2)}',
                          onChanged: (v) => setState(() => _rate = v),
                          onChangeEnd: (v) => session.setSpeechRate(v),
                        ),
                      ),
                    ],
                  ),
                  Row(
                    children: [
                      const Icon(Icons.tune_outlined),
                      Expanded(
                        child: Slider(
                          value: _pitch,
                          min: 0.5,
                          max: 1.5,
                          divisions: 20,
                          label: 'Pitch ${_pitch.toStringAsFixed(2)}',
                          onChanged: (v) => setState(() => _pitch = v),
                          onChangeEnd: (v) => session.setSpeechPitch(v),
                        ),
                      ),
                    ],
                  ),
                  Align(
                    alignment: Alignment.centerRight,
                    child: TextButton.icon(
                      icon: const Icon(Icons.play_arrow),
                      label: const Text('Hear it'),
                      onPressed: () => session.speakText(
                        _voicePreviewFor(session.currentLocale),
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 16),
          _sectionTitle(context, 'Voice choice'),
          _VoiceChoiceSection(
            key: ValueKey('${session.currentLocale}-v$_voiceListVersion'),
          ),
          const SizedBox(height: 16),
          _sectionTitle(context, 'Neural voices (optional)'),
          _KokoroSection(
            key: ValueKey('kokoro-${session.currentLocale}'),
            onVoicesChanged: () => setState(() => _voiceListVersion++),
          ),
          const SizedBox(height: 16),
          _sectionTitle(context, 'My own voice (iPhone)'),
          _PersonalVoiceSection(
            onVoicesChanged: () => setState(() => _voiceListVersion++),
          ),
          const SizedBox(height: 16),
          _sectionTitle(context, 'AI cloud voices (optional)'),
          ElevenLabsSection(
            onVoicesChanged: () => setState(() => _voiceListVersion++),
          ),
          const SizedBox(height: 16),
          _sectionTitle(context, 'Buttons'),
          Card(
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text('Button size'),
                  const SizedBox(height: 8),
                  SegmentedButton<double>(
                    segments: [
                      for (var i = 0; i < AppConfig.buttonScales.length; i++)
                        ButtonSegment(
                          value: AppConfig.buttonScales[i],
                          label: Text(AppConfig.buttonScaleNames[i]),
                        ),
                    ],
                    selected: {session.buttonScale},
                    onSelectionChanged: (s) => session.setButtonScale(s.first),
                  ),
                  const SizedBox(height: 8),
                  const Text(
                    'Size changes how big each button looks. The grid itself '
                    'never changes — every word stays exactly where motor '
                    'memory expects it.',
                    style: TextStyle(fontSize: 12),
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 16),
          _sectionTitle(context, 'About'),
          Card(
            child: ListTile(
              leading: ClipRRect(
                borderRadius: BorderRadius.circular(8),
                child: Image.asset(
                  'assets/images/app_icon.png',
                  width: 40,
                  height: 40,
                ),
              ),
              title: Text(AppConfig.appDisplayName),
              subtitle: const Text(
                'Starter build.\n'
                'Word symbols: ARASAAC (CC BY-NC-SA), https://arasaac.org',
              ),
              isThreeLine: true,
            ),
          ),
          const SizedBox(height: 16),
          _sectionTitle(context, 'Coming soon'),
          const Card(
            child: Column(
              children: [
                ListTile(
                  leading: Icon(Icons.grid_on_outlined),
                  title: Text('Vocabulary levels'),
                  subtitle: Text(
                    'Progressive reveal for new communicators — positions stay fixed.',
                  ),
                ),
                ListTile(
                  leading: Icon(Icons.cloud_outlined),
                  title: Text('Backup & sync'),
                  subtitle: Text('Profiles and custom words across devices.'),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _sectionTitle(BuildContext context, String title) {
    return Padding(
      padding: EdgeInsets.only(bottom: 8),
      child: Text(
        title,
        style: Theme.of(context).textTheme.titleMedium
            ?.copyWith(fontWeight: FontWeight.bold),
      ),
    );
  }
}

/// Voice preview sentence in the currently selected language.
String _voicePreviewFor(String locale) {
  return switch (locale) {
    'es' => '¡Hola! Esta es mi voz.',
    'fr' => 'Bonjour ! C\u2019est ma voix.',
    _ => 'Hello! This is my voice.',
  };
}

/// Voice picker: lists the engine's voices for the current language and
/// persists the choice per language. Keyed by locale in the parent so a
/// language switch reloads the list.
class _VoiceChoiceSection extends StatefulWidget {
  const _VoiceChoiceSection({super.key});

  @override
  State<_VoiceChoiceSection> createState() => _VoiceChoiceSectionState();
}

class _VoiceChoiceSectionState extends State<_VoiceChoiceSection> {
  List<TtsVoice>? _voices;
  bool _applying = false;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final session = context.read<SessionState>();
    final voices = await session.loadVoices();
    if (mounted) setState(() => _voices = voices);
  }

  Future<void> _select(TtsVoice? voice) async {
    if (_applying) return;
    setState(() => _applying = true);
    final session = context.read<SessionState>();
    if (voice == null) {
      await session.clearVoice();
    } else {
      await session.setVoice(voice);
      // Preview the newly selected voice immediately.
      await session.speakText(_voicePreviewFor(session.currentLocale));
    }
    if (mounted) setState(() => _applying = false);
  }

  @override
  Widget build(BuildContext context) {
    final session = context.watch<SessionState>();
    final voices = _voices;
    return Card(
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 8),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            if (voices == null)
              const Padding(
                padding: EdgeInsets.all(16),
                child: Center(child: CircularProgressIndicator()),
              )
            else if (voices.isEmpty)
              const Padding(
                padding: EdgeInsets.all(16),
                child: Text(
                  'No voices found for this language on this device.',
                  style: TextStyle(fontSize: 13),
                ),
              )
            else
              RadioGroup<TtsVoice?>(
                groupValue: session.currentVoice,
                onChanged: (v) => _select(v),
                child: Column(
                  children: [
                    RadioListTile<TtsVoice?>(
                      title: const Text('System default'),
                      subtitle: const Text(
                        'Let the device pick the voice.',
                        style: TextStyle(fontSize: 12),
                      ),
                      value: null,
                      enabled: !_applying,
                    ),
                    const Divider(height: 1),
                    for (final voice in voices)
                      RadioListTile<TtsVoice?>(
                        title: Text(
                          voice.name,
                          style: const TextStyle(fontSize: 14),
                        ),
                        subtitle: Text(
                          voice.isKokoro
                              ? 'Kokoro · on-device neural voice'
                              : voice.isElevenLabs
                              ? 'ElevenLabs · cloud voice'
                              : voice.locale,
                          style: const TextStyle(fontSize: 12),
                        ),
                        value: voice,
                        enabled: !_applying,
                      ),
                  ],
                ),
              ),
            const Padding(
              padding: EdgeInsets.fromLTRB(16, 4, 16, 8),
              child: Text(
                'The choice is saved separately for each language.',
                style: TextStyle(fontSize: 12),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// Kokoro on-device neural voices: one-time ~126 MB download, then fully
/// offline. Not shown on web (Kokoro runs natively only).
class _KokoroSection extends StatefulWidget {
  const _KokoroSection({super.key, required this.onVoicesChanged});

  /// Called after the model becomes ready so the voice picker reloads.
  final VoidCallback onVoicesChanged;

  @override
  State<_KokoroSection> createState() => _KokoroSectionState();
}

class _KokoroSectionState extends State<_KokoroSection> {
  bool? _ready;
  String? _error;

  KokoroTtsService get _kokoro => context.read<SessionState>().kokoro;

  @override
  void initState() {
    super.initState();
    _check();
  }

  Future<void> _check() async {
    if (!KokoroTtsService.isSupported) {
      if (mounted) setState(() => _ready = null);
      return;
    }
    final ready = await _kokoro.isModelReady();
    if (mounted) setState(() => _ready = ready);
  }

  Future<void> _download() async {
    final kokoro = _kokoro;
    if (kokoro.isDownloading.value) return;
    setState(() => _error = null);
    try {
      // Progress is broadcast by the service itself (see
      // KokoroTtsService.downloadProgress): the UI below subscribes to it,
      // so navigating away and back mid-download still shows a live bar.
      await kokoro.downloadModel();
      if (mounted) setState(() => _ready = true);
      widget.onVoicesChanged();
      // Pre-load the engine so the first utterance isn't slow.
      unawaited(kokoro.warmup());
    } catch (e) {
      if (mounted) {
        setState(() {
          _error = 'Download failed. Check your connection and try again.';
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    if (!KokoroTtsService.isSupported) return const SizedBox.shrink();
    // Rebuilds whenever the service's download state changes — even when
    // this widget was created mid-download.
    return ValueListenableBuilder<bool>(
      valueListenable: _kokoro.isDownloading,
      builder: (context, downloading, _) => _buildCard(downloading),
    );
  }

  Widget _buildCard(bool downloading) {
    final ready = _ready;
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Row(
              children: [
                Icon(Icons.psychology_outlined),
                SizedBox(width: 8),
                Text(
                  'Kokoro neural voices',
                  style: TextStyle(fontSize: 15, fontWeight: FontWeight.w600),
                ),
              ],
            ),
            const SizedBox(height: 8),
            const Text(
              'Free, human-sounding voices for English, Spanish, and French. '
              'One download of about 126 MB, then everything works offline — '
              'no account, no subscription, nothing leaves the device.',
              style: TextStyle(fontSize: 12),
            ),
            const SizedBox(height: 12),
            if (ready == null)
              const Center(
                child: Padding(
                  padding: EdgeInsets.all(8),
                  child: CircularProgressIndicator(),
                ),
              )
            else if (downloading)
              ValueListenableBuilder<double?>(
                valueListenable: _kokoro.downloadProgress,
                builder: (context, progress, _) {
                  final p = progress ?? 0;
                  return Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      if (p < 1) ...[
                        LinearProgressIndicator(value: p),
                        const SizedBox(height: 8),
                        Text(
                          'Downloading… ${(p * 100).toStringAsFixed(0)}% '
                          '(${(p * 126).toStringAsFixed(0)} of ~126 MB)',
                          style: const TextStyle(fontSize: 12),
                        ),
                      ] else ...[
                        const LinearProgressIndicator(),
                        const SizedBox(height: 8),
                        const Text(
                          'Extracting voices… this takes a minute on older tablets.',
                          style: TextStyle(fontSize: 12),
                        ),
                      ],
                      const SizedBox(height: 4),
                      const Text(
                        'Keep the app open until it finishes.',
                        style: TextStyle(
                          fontSize: 12,
                          fontStyle: FontStyle.italic,
                        ),
                      ),
                    ],
                  );
                },
              )
            else if (ready) ...[
              const Row(
                children: [
                  Icon(Icons.check_circle, color: Colors.green, size: 18),
                  SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      'Downloaded. Kokoro voices now appear in Voice choice above.',
                      style: TextStyle(fontSize: 12),
                    ),
                  ),
                ],
              ),
            ] else ...[
              if (_error != null) ...[
                Text(
                  _error!,
                  style: const TextStyle(fontSize: 12, color: Colors.red),
                ),
                const SizedBox(height: 8),
              ],
              FilledButton.icon(
                onPressed: _download,
                icon: const Icon(Icons.download),
                label: const Text('Download voices (~126 MB)'),
              ),
            ],
          ],
        ),
      ),
    );
  }
}

/// Apple's Personal Voice (iPhone/iPad, iOS 17+): a voice the family
/// creates on-device in Settings → Accessibility → Personal Voice. Free,
/// private, works offline — ideal for a communicator who wants their own
/// (or a parent's) voice. iOS hides it from apps until the app explicitly
/// asks, so this section requests access; once granted, the Personal Voice
/// appears in Voice choice above like any other system voice.
class _PersonalVoiceSection extends StatefulWidget {
  const _PersonalVoiceSection({required this.onVoicesChanged});

  /// Called after access is granted so the voice picker reloads.
  final VoidCallback onVoicesChanged;

  @override
  State<_PersonalVoiceSection> createState() => _PersonalVoiceSectionState();
}

class _PersonalVoiceSectionState extends State<_PersonalVoiceSection> {
  final _service = PersonalVoiceService();
  bool _busy = false;
  PersonalVoiceStatus? _status;

  Future<void> _enable() async {
    if (_busy) return;
    setState(() => _busy = true);
    final status = await _service.requestAuthorization();
    if (!mounted) return;
    setState(() {
      _busy = false;
      _status = status;
    });
    if (status == PersonalVoiceStatus.authorized) widget.onVoicesChanged();
  }

  @override
  Widget build(BuildContext context) {
    // Android, web, and desktop have no Personal Voice.
    if (!PersonalVoiceService.isPlatformSupported) {
      return const SizedBox.shrink();
    }
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Row(
              children: [
                Icon(Icons.record_voice_over_outlined),
                SizedBox(width: 8),
                Text(
                  'Personal Voice',
                  style: TextStyle(fontSize: 15, fontWeight: FontWeight.w600),
                ),
              ],
            ),
            const SizedBox(height: 8),
            const Text(
              'Use a voice created on this iPhone — for example the '
              'communicator\'s own voice, or a parent\'s. It is created '
              'entirely on the device: free, private, and it works offline.',
              style: TextStyle(fontSize: 12),
            ),
            const SizedBox(height: 8),
            const Text(
              'No Personal Voice yet? Create one in the iPhone Settings app '
              '→ Accessibility → Personal Voice (a few minutes of reading '
              'aloud). Then enable access below.',
              style: TextStyle(fontSize: 12),
            ),
            const SizedBox(height: 12),
            _buildStatus(),
          ],
        ),
      ),
    );
  }

  Widget _buildStatus() {
    final status = _status;
    if (_busy) {
      return const Center(
        child: Padding(
          padding: EdgeInsets.all(8),
          child: CircularProgressIndicator(),
        ),
      );
    }
    switch (status) {
      case null:
      case PersonalVoiceStatus.notDetermined:
        return FilledButton.icon(
          onPressed: _enable,
          icon: const Icon(Icons.voice_over_off_outlined),
          label: const Text('Enable Personal Voice access'),
        );
      case PersonalVoiceStatus.authorized:
        return const Row(
          children: [
            Icon(Icons.check_circle, color: Colors.green, size: 18),
            SizedBox(width: 8),
            Expanded(
              child: Text(
                'Enabled. Your Personal Voice now appears in Voice choice '
                'above — pick it like any other voice.',
                style: TextStyle(fontSize: 12),
              ),
            ),
          ],
        );
      case PersonalVoiceStatus.denied:
        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              'Access was denied. To allow it: iPhone Settings → '
              'Accessibility → Personal Voice → turn on “Allow Apps to '
              'Request to Use”, then try again.',
              style: TextStyle(fontSize: 12),
            ),
            const SizedBox(height: 8),
            OutlinedButton.icon(
              onPressed: _enable,
              icon: const Icon(Icons.refresh),
              label: const Text('Try again'),
            ),
          ],
        );
      case PersonalVoiceStatus.unsupported:
        return const Text(
          'Personal Voice needs iOS 17 or later on this device.',
          style: TextStyle(fontSize: 12),
        );
      case PersonalVoiceStatus.unknown:
        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              'Something went wrong asking iOS for access.',
              style: TextStyle(fontSize: 12),
            ),
            const SizedBox(height: 8),
            OutlinedButton.icon(
              onPressed: _enable,
              icon: const Icon(Icons.refresh),
              label: const Text('Try again'),
            ),
          ],
        );
    }
  }
}
