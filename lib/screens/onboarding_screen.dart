import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../app_config.dart';
import '../state/session_state.dart';

/// First-run setup: welcome → profile name → voice speed → quick tour.
/// Shown once (flag in SharedPreferences); re-runnable from Caregiver.
class OnboardingScreen extends StatefulWidget {
  const OnboardingScreen({super.key});

  @override
  State<OnboardingScreen> createState() => _OnboardingScreenState();
}

class _OnboardingScreenState extends State<OnboardingScreen> {
  final PageController _pages = PageController();
  final TextEditingController _name = TextEditingController();
  double _rate = AppConfig.defaultSpeechRate;
  int _index = 0;

  @override
  void dispose() {
    _pages.dispose();
    _name.dispose();
    super.dispose();
  }

  void _next() {
    if (_index < 3) {
      _pages.nextPage(
        duration: const Duration(milliseconds: 300),
        curve: Curves.easeOut,
      );
    } else {
      _finish();
    }
  }

  Future<void> _finish() async {
    await context.read<SessionState>().completeOnboarding(_name.text);
  }

  Future<void> _previewVoice() async {
    final session = context.read<SessionState>();
    await session.setSpeechRate(_rate);
    await session.speakText('Hello! This is my new voice.');
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Scaffold(
      backgroundColor: scheme.surface,
      body: SafeArea(
        child: Column(
          children: [
            Expanded(
              child: PageView(
                controller: _pages,
                onPageChanged: (i) => setState(() => _index = i),
                children: [
                  _welcome(scheme),
                  _profileStep(scheme),
                  _voiceStep(scheme),
                  _tourStep(scheme),
                ],
              ),
            ),
            Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                for (var i = 0; i < 4; i++)
                  Container(
                    margin: const EdgeInsets.symmetric(horizontal: 4),
                    width: 10,
                    height: 10,
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      color: i == _index
                          ? scheme.primary
                          : scheme.surfaceContainerHighest,
                    ),
                  ),
              ],
            ),
            Padding(
              padding: const EdgeInsets.all(24),
              child: SizedBox(
                width: double.infinity,
                child: FilledButton(
                  onPressed: _next,
                  child: Padding(
                    padding: const EdgeInsets.symmetric(vertical: 12),
                    child: Text(
                      _index == 3 ? 'Start communicating' : 'Continue',
                      style: const TextStyle(fontSize: 17),
                    ),
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _welcome(ColorScheme scheme) {
    return _page(
      children: [
        ClipRRect(
          borderRadius: BorderRadius.circular(28),
          child: Image.asset(
            'assets/images/app_icon.png',
            width: 120,
            height: 120,
          ),
        ),
        const SizedBox(height: 24),
        Text(
          'Welcome to ${AppConfig.appDisplayName}',
          style: const TextStyle(fontSize: 26, fontWeight: FontWeight.bold),
          textAlign: TextAlign.center,
        ),
        const SizedBox(height: 8),
        Text(
          AppConfig.appTagline,
          style: TextStyle(fontSize: 18, color: scheme.onSurfaceVariant),
          textAlign: TextAlign.center,
        ),
        const SizedBox(height: 16),
        const Text(
          'A talking picture board that gives every person a voice.\n'
          'Let\u2019s set it up together — it takes about a minute.',
          textAlign: TextAlign.center,
          style: TextStyle(fontSize: 15),
        ),
      ],
    );
  }

  Widget _profileStep(ColorScheme scheme) {
    return _page(
      children: [
        Icon(Icons.person_outline, size: 72, color: scheme.primary),
        const SizedBox(height: 16),
        const Text(
          'Who will use VidaVoice?',
          style: TextStyle(fontSize: 24, fontWeight: FontWeight.bold),
          textAlign: TextAlign.center,
        ),
        const SizedBox(height: 8),
        Text(
          'Their name appears for caregivers.\nYou can add more profiles later.',
          style: TextStyle(fontSize: 15, color: scheme.onSurfaceVariant),
          textAlign: TextAlign.center,
        ),
        const SizedBox(height: 24),
        TextField(
          controller: _name,
          textCapitalization: TextCapitalization.words,
          decoration: const InputDecoration(
            labelText: 'First name',
            border: OutlineInputBorder(),
            prefixIcon: Icon(Icons.badge_outlined),
          ),
          onSubmitted: (_) => _next(),
        ),
      ],
    );
  }

  Widget _voiceStep(ColorScheme scheme) {
    return _page(
      children: [
        Icon(Icons.record_voice_over_outlined, size: 72, color: scheme.primary),
        const SizedBox(height: 16),
        const Text(
          'Choose a voice speed',
          style: TextStyle(fontSize: 24, fontWeight: FontWeight.bold),
          textAlign: TextAlign.center,
        ),
        const SizedBox(height: 8),
        Text(
          'Drag the slider, then press play to hear it.\n'
          'You can fine-tune speed and pitch later in Settings.',
          style: TextStyle(fontSize: 15, color: scheme.onSurfaceVariant),
          textAlign: TextAlign.center,
        ),
        const SizedBox(height: 24),
        Row(
          children: [
            const Icon(Icons.speed_outlined),
            Expanded(
              child: Slider(
                value: _rate,
                min: 0.3,
                max: 1.0,
                divisions: 14,
                label: _rate.toStringAsFixed(2),
                onChanged: (v) => setState(() => _rate = v),
              ),
            ),
            IconButton.filled(
              tooltip: 'Hear it',
              icon: const Icon(Icons.play_arrow),
              onPressed: _previewVoice,
            ),
          ],
        ),
      ],
    );
  }

  Widget _tourStep(ColorScheme scheme) {
    const tips = [
      ('👆', 'Tap any word to hear it', 'It speaks out loud right away.'),
      (
        '📁',
        'Open folders for more words',
        'Food, Feelings, People and Play live one tap away.',
      ),
      (
        '💬',
        'Build sentences in the message bar',
        'Then press Speak to say the whole sentence.',
      ),
    ];
    return _page(
      children: [
        const Text(
          'How it works',
          style: TextStyle(fontSize: 24, fontWeight: FontWeight.bold),
          textAlign: TextAlign.center,
        ),
        const SizedBox(height: 16),
        for (final (emoji, title, body) in tips)
          Card(
            margin: const EdgeInsets.symmetric(vertical: 6),
            child: ListTile(
              leading: Text(emoji, style: const TextStyle(fontSize: 30)),
              title: Text(
                title,
                style: const TextStyle(fontWeight: FontWeight.bold),
              ),
              subtitle: Text(body),
            ),
          ),
      ],
    );
  }

  Widget _page({required List<Widget> children}) {
    return SingleChildScrollView(
      padding: const EdgeInsets.symmetric(horizontal: 32, vertical: 48),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: children,
      ),
    );
  }
}
