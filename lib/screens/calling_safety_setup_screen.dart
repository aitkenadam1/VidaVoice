import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../services/profile_service.dart';
import '../state/session_state.dart';
import '../widgets/calling_safety/contact_editor.dart';
import '../widgets/calling_safety/emergency_editor.dart';
import '../widgets/calling_safety/phrase_editor.dart';

/// Guided 2-minute setup flow for Calling & Safety: Contacts → Phrases →
/// Emergency → Done.
///
/// Each step asks for ONE thing with big, clear actions. "Skip for now"
/// is always visible; skipping leaves the safe defaults (the starter
/// phrase bank is pre-seeded). Re-enterable any time from the hub via
/// "Run guided setup again".
class CallingSafetySetupScreen extends StatefulWidget {
  const CallingSafetySetupScreen({super.key});

  @override
  State<CallingSafetySetupScreen> createState() =>
      _CallingSafetySetupScreenState();
}

class _CallingSafetySetupScreenState extends State<CallingSafetySetupScreen> {
  static const _stepTitles = [
    'Who should they be able to call?',
    'What should they be able to say?',
    'Emergency details',
    'You\u2019re all set',
  ];

  int _step = 0;

  void _next() {
    if (_step < _stepTitles.length - 1) setState(() => _step++);
  }

  void _back() {
    if (_step > 0) setState(() => _step--);
  }

  @override
  Widget build(BuildContext context) {
    final session = context.watch<SessionState>();
    final profile = session.profiles.active;
    return Scaffold(
      appBar: AppBar(
        title: const Text('Calling & Safety setup'),
      ),
      body: Column(
        children: [
          _progressDots(),
          Expanded(
            child: profile == null
                ? const Center(
                    child: Padding(
                      padding: EdgeInsets.all(24),
                      child: Text(
                        'Add a communicator profile first — calling and '
                        'safety settings belong to a profile.',
                        textAlign: TextAlign.center,
                      ),
                    ),
                  )
                : _stepBody(context, session, profile),
          ),
          if (profile != null) _bottomBar(),
        ],
      ),
    );
  }

  Widget _progressDots() {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 4),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          for (var i = 0; i < _stepTitles.length; i++)
            Container(
              width: 10,
              height: 10,
              margin: const EdgeInsets.symmetric(horizontal: 5),
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: i == _step
                    ? Theme.of(context).colorScheme.primary
                    : Theme.of(context).colorScheme.surfaceContainerHighest,
              ),
            ),
        ],
      ),
    );
  }

  Widget _stepBody(
    BuildContext context,
    SessionState session,
    UserProfile profile,
  ) {
    final profileId = profile.id;
    switch (_step) {
      case 0:
        return _StepScaffold(
          title: _stepTitles[0],
          subtitle: 'Add the people they should be able to reach. One is '
              'enough to start — family first.',
          child: ContactListEditor(
            key: ValueKey('setup-contacts-$profileId'),
            profileId: profileId,
            onChanged: () => setState(() {}),
          ),
        );
      case 1:
        return _StepScaffold(
          title: _stepTitles[1],
          subtitle: 'A starter set is already here — keep it, change it, or '
              'add your own. Drag to reorder.',
          child: PhraseBankEditor(
            key: ValueKey('setup-phrases-$profileId'),
            profileId: profileId,
            onChanged: () => setState(() {}),
          ),
        );
      case 2:
        return _StepScaffold(
          title: _stepTitles[2],
          subtitle: 'Fills the {child_name} and {home_address} placeholders '
              'in their phrases.',
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              EmergencyDetailsEditor(
                key: ValueKey('setup-emergency-$profileId'),
                profileId: profileId,
                compact: true,
                onChanged: () => setState(() {}),
              ),
              const Padding(
                padding: EdgeInsets.fromLTRB(16, 12, 16, 0),
                child: Text(
                  'OneVoz complements your device\u2019s built-in Emergency '
                  'SOS \u2014 it never replaces calling 911 directly.',
                  style: TextStyle(fontSize: 12),
                ),
              ),
            ],
          ),
        );
      default:
        return _doneStep(session, profile);
    }
  }

  /// Bottom bar: Skip is always visible, Back goes to the previous step,
  /// Continue advances (Done on the last step pops back to the hub).
  Widget _bottomBar() {
    final isDone = _step == _stepTitles.length - 1;
    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 8, 16, 16),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Row(
              children: [
                if (_step > 0)
                  Expanded(
                    child: OutlinedButton(
                      onPressed: _back,
                      child: const Text('Back'),
                    ),
                  ),
                if (_step > 0) const SizedBox(width: 12),
                Expanded(
                  flex: 2,
                  child: FilledButton(
                    onPressed: isDone
                        ? () => Navigator.of(context).pop()
                        : _next,
                    child: Text(isDone ? 'Back to hub' : 'Continue'),
                  ),
                ),
              ],
            ),
            if (!isDone)
              TextButton(
                onPressed: _next,
                child: const Text('Skip for now'),
              ),
          ],
        ),
      ),
    );
  }

  Widget _doneStep(SessionState session, UserProfile profile) {
    final contacts = profile.contacts.length;
    final phrases = profile.callPhrases.length;
    final emergency = profile.emergency;
    final safety = profile.safety;
    final detailsDone = emergency.childName.trim().isNotEmpty ||
        emergency.homeAddress.trim().isNotEmpty;
    return _StepScaffold(
      title: _stepTitles[3],
      subtitle: 'Here\u2019s what\u2019s ready. Anything you skipped can be '
          'finished later from the Calling & Safety hub.',
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 4),
        child: Column(
          children: [
            _summaryRow(
              Icons.contacts_outlined,
              contacts == 0
                  ? 'No contacts yet'
                  : '$contacts contact${contacts == 1 ? '' : 's'} added',
              contacts > 0,
            ),
            _summaryRow(
              Icons.chat_bubble_outline,
              '$phrases phrase${phrases == 1 ? '' : 's'} in the bank',
              phrases > 0,
            ),
            _summaryRow(
              Icons.medical_information_outlined,
              detailsDone
                  ? 'Emergency details saved'
                  : 'Emergency details skipped',
              detailsDone,
            ),
            if (emergency.emergencyEnabled)
              _summaryRow(
                Icons.emergency_outlined,
                'Emergency button is on',
                true,
              ),
            _summaryRow(
              Icons.shield_outlined,
              'AI suggestions ${safety.aiSuggestions ? 'on' : 'off'} · '
              'my phrases ${safety.preferOwnPhrases ? 'first' : 'mixed in'}',
              true,
            ),
            const SizedBox(height: 8),
            const Text(
              'Text-to-911 works only where your local 911 center accepts '
              'texts. It doesn\u2019t work while roaming, can\u2019t send '
              'photos, and texts can arrive late or out of order.',
              style: TextStyle(fontSize: 12),
            ),
          ],
        ),
      ),
    );
  }

  Widget _summaryRow(IconData icon, String text, bool done) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 6),
      child: Row(
        children: [
          Icon(
            done ? Icons.check_circle_outline : Icons.circle_outlined,
            color: done ? Colors.green : Colors.grey,
          ),
          const SizedBox(width: 12),
          Icon(icon, size: 18),
          const SizedBox(width: 8),
          Expanded(child: Text(text)),
        ],
      ),
    );
  }
}

/// One setup step: a clear title, one plain-language instruction, and the
/// single action for this step.
class _StepScaffold extends StatelessWidget {
  const _StepScaffold({
    required this.title,
    required this.subtitle,
    required this.child,
  });

  final String title;
  final String subtitle;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    return ListView(
      padding: const EdgeInsets.fromLTRB(16, 8, 16, 16),
      children: [
        Text(
          title,
          style: const TextStyle(fontSize: 22, fontWeight: FontWeight.bold),
        ),
        const SizedBox(height: 4),
        Text(subtitle, style: const TextStyle(fontSize: 14)),
        const SizedBox(height: 12),
        child,
      ],
    );
  }
}
