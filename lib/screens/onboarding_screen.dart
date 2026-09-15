import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../app_config.dart';
import '../state/session_state.dart';
import '../widgets/dashboard_section.dart';
import '../widgets/obf_import_button.dart';
import '../widgets/proxy_account_form.dart';

/// First-run setup: welcome → account → profile name → import → customize →
/// voice speed → quick tour. Shown once (flag in SharedPreferences);
/// re-runnable from the caregiver hub ("Re-run setup").
///
/// The account, import, and customize steps are all skippable: the board
/// works fully with on-device voices and no account.
class OnboardingScreen extends StatefulWidget {
  const OnboardingScreen({super.key});

  @override
  State<OnboardingScreen> createState() => _OnboardingScreenState();
}

class _OnboardingScreenState extends State<OnboardingScreen> {
  static const _pageCount = 7;
  static const _accountPage = 1;

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
    if (_index < _pageCount - 1) {
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
    // The account page drives itself (sign up / log in / continue without
    // an account), so the global Continue button hides there — the form's
    // own actions are the step's actions.
    final showContinue = _index != _accountPage;
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
                  _accountStep(scheme),
                  _profileStep(scheme),
                  _importStep(scheme),
                  _customizeStep(scheme),
                  _voiceStep(scheme),
                  _tourStep(scheme),
                ],
              ),
            ),
            Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                for (var i = 0; i < _pageCount; i++)
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
            if (showContinue)
              Padding(
                padding: const EdgeInsets.fromLTRB(24, 12, 24, 8),
                child: SizedBox(
                  width: double.infinity,
                  child: FilledButton(
                    onPressed: _next,
                    child: Padding(
                      padding: const EdgeInsets.symmetric(vertical: 12),
                      child: Text(
                        _index == _pageCount - 1
                            ? 'Start communicating'
                            : 'Continue',
                        style: const TextStyle(fontSize: 17),
                      ),
                    ),
                  ),
                ),
              )
            else
              const SizedBox(height: 12),
            TextButton(onPressed: _finish, child: const Text('Skip for now')),
            const SizedBox(height: 8),
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

  Widget _accountStep(ColorScheme scheme) {
    return _page(
      children: [
        Icon(Icons.cloud_outlined, size: 72, color: scheme.primary),
        const SizedBox(height: 16),
        const Text(
          'Your VidaVoice account',
          style: TextStyle(fontSize: 24, fontWeight: FontWeight.bold),
          textAlign: TextAlign.center,
        ),
        const SizedBox(height: 8),
        Text(
          'An account unlocks AI cloud voices, included with VidaVoice, '
          'on up to 3 devices. It\u2019s optional \u2014 the board speaks '
          'fully offline with on-device voices.',
          style: TextStyle(fontSize: 15, color: scheme.onSurfaceVariant),
          textAlign: TextAlign.center,
        ),
        const SizedBox(height: 20),
        ProxyAccountForm(
          showDeferButton: true,
          onSignedIn: _next,
          onDeferred: _next,
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

  Widget _importStep(ColorScheme scheme) {
    return _page(
      children: [
        Icon(Icons.upload_file_outlined, size: 72, color: scheme.primary),
        const SizedBox(height: 16),
        const Text(
          'Bring a board from another app?',
          style: TextStyle(fontSize: 24, fontWeight: FontWeight.bold),
          textAlign: TextAlign.center,
        ),
        const SizedBox(height: 8),
        Text(
          'If you already built a board elsewhere, import it now.\n'
          'Otherwise just continue \u2014 you can import later from the '
          'caregiver hub.',
          style: TextStyle(fontSize: 15, color: scheme.onSurfaceVariant),
          textAlign: TextAlign.center,
        ),
        const SizedBox(height: 24),
        ObfImportButton(onChanged: () => setState(() {})),
      ],
    );
  }

  Widget _customizeStep(ColorScheme scheme) {
    return _page(
      children: [
        Icon(Icons.dashboard_outlined, size: 72, color: scheme.primary),
        const SizedBox(height: 16),
        const Text(
          'Make it theirs',
          style: TextStyle(fontSize: 24, fontWeight: FontWeight.bold),
          textAlign: TextAlign.center,
        ),
        const SizedBox(height: 8),
        Text(
          'Add the words and phrases that matter most, arrange them '
          'freely, or turn on a personal home board.\n'
          'Skip this and the standard board is ready to go.',
          style: TextStyle(fontSize: 15, color: scheme.onSurfaceVariant),
          textAlign: TextAlign.center,
        ),
        const SizedBox(height: 16),
        DashboardSection(refresh: () => setState(() {})),
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
