import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../app_config.dart';
import '../state/session_state.dart';

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
                  leading: Icon(Icons.mic_outlined),
                  title: Text('Voice choice'),
                  subtitle: Text(
                    'Pick from the device\u2019s installed voices per language.',
                  ),
                ),
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

  /// Voice preview sentence in the currently selected language.
  String _voicePreviewFor(String locale) {
    return switch (locale) {
      'es' => '¡Hola! Esta es mi voz.',
      'fr' => 'Bonjour ! C\u2019est ma voix.',
      _ => 'Hello! This is my voice.',
    };
  }

  Widget _sectionTitle(BuildContext context, String title) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Text(
        title,
        style: Theme.of(context).textTheme.titleMedium
            ?.copyWith(fontWeight: FontWeight.bold),
      ),
    );
  }
}
