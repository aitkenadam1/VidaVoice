import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:url_launcher/url_launcher.dart';

import '../models/calling_safety.dart';
import '../state/session_state.dart';
import '../theme/onevoz_theme.dart';
import '../widgets/safety_contact_avatar.dart';
import 'call_screen.dart';

/// "Call Mom?" — the second tap of the 2-tap calling rule.
///
/// Board (tap 1: the photo button, which also speaks the contact's name for
/// zero-reading confirmation) -> this screen (tap 2: Call) -> the OS dialer.
/// Nothing here dials silently: the child sees the photo and name and makes
/// a deliberate second choice, and Cancel is just as big as Call.
///
/// "What to say" opens the phrase/quick-answer cards for this contact so
/// the child has something to say once the call connects on speakerphone.
/// Nothing about the 2-tap path changes: it sits between Call and Cancel
/// as a parallel, clearly-labeled option.
///
/// Platform note: on iOS, `tel:` links show the system's own call
/// confirmation sheet before dialing — that sheet sits outside our 2-tap
/// budget, and that's iOS, not us. On Android the dialer opens directly.
class CallConfirmScreen extends StatelessWidget {
  const CallConfirmScreen({super.key, required this.contact});

  final SafetyContact contact;

  Future<void> _dial(BuildContext context) async {
    // The phone number comes from the caregiver-configured contact only.
    // Sanitized to a dialable form ("+1 555 010 2030" -> "+15550102030").
    // A device with no phone handler (Wi-Fi-only tablet) gets
    // plain-language feedback instead of a dead tap.
    try {
      final ok = await launchUrl(telUri(contact.phone));
      if (!ok && context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Could not open the phone app on this device.'),
            duration: Duration(seconds: 4),
          ),
        );
      }
    } catch (_) {
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Could not open the phone app on this device.'),
            duration: Duration(seconds: 4),
          ),
        );
      }
    }
  }

  /// Opens the phrase cards for this contact, so the child has something to
  /// say once the call connects (speakerphone). Speaks the button label
  /// first for zero-reading confirmation, matching the board's pattern.
  void _openWhatToSay(BuildContext context) {
    final session = context.read<SessionState>();
    final profile = session.profiles.active;
    session.tts.speak('What to say');
    Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => CallScreen(
          contact: contact,
          phrases: profile?.callPhrases ?? const [],
          emergency: profile?.emergency,
          safety: profile?.safety ?? const SafetySettings(),
          locationService: session.locationService,
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final name = contact.name.isNotEmpty ? contact.name : 'this contact';
    // A contact saved before phone validation (or with a blank number)
    // must never produce a Call button dialing `tel:` with an empty path:
    // the button is disabled and the caregiver gets a plain-language note.
    final hasPhone = contact.phone.trim().isNotEmpty;
    return Theme(
      data: OneVozTheme.childTheme(),
      child: Scaffold(
        body: SafeArea(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              // Navy gradient hero, matching the mockup's `.call-hero`:
              // photo/initial, name, and number — the child sees exactly
              // who they're about to call before the second tap.
              Container(
                decoration: const BoxDecoration(
                  gradient: OneVozColors.heroGradient,
                  borderRadius: BorderRadius.vertical(
                    bottom: Radius.circular(24),
                  ),
                ),
                padding: const EdgeInsets.fromLTRB(8, 8, 20, 32),
                child: Column(
                  children: [
                    Row(
                      children: [
                        IconButton(
                          tooltip: 'Back to board',
                          icon: const Icon(
                            Icons.arrow_back,
                            color: Colors.white,
                          ),
                          onPressed: () => Navigator.of(context).pop(),
                        ),
                        const WaveformMotif(
                          barCount: 5,
                          height: 26,
                          barWidth: 5,
                          gap: 4,
                          color: Colors.white,
                        ),
                      ],
                    ),
                    const SizedBox(height: 8),
                    SafetyContactAvatar(contact: contact, radius: 64),
                    const SizedBox(height: 16),
                    Text(
                      'Call $name?',
                      textAlign: TextAlign.center,
                      style: const TextStyle(
                        color: Colors.white,
                        fontSize: 34,
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                    if (contact.phone.isNotEmpty) ...[
                      const SizedBox(height: 6),
                      Text(
                        contact.phone,
                        textAlign: TextAlign.center,
                        style: const TextStyle(
                          color: Colors.white,
                          fontSize: 18,
                        ),
                      ),
                    ],
                  ],
                ),
              ),
              // Scrollable when the screen is short (small phones, test
              // viewports): three 96px buttons plus the hero must never
              // overflow. Centers the buttons when they fit.
              Expanded(
                child: LayoutBuilder(
                  builder: (context, constraints) => SingleChildScrollView(
                    child: ConstrainedBox(
                      constraints: BoxConstraints(
                        minHeight: constraints.maxHeight,
                      ),
                      child: Padding(
                        padding: const EdgeInsets.all(24),
                        child: Column(
                          mainAxisAlignment: MainAxisAlignment.center,
                          crossAxisAlignment: CrossAxisAlignment.stretch,
                          children: [
                            OneVozGradientButton(
                              onPressed: hasPhone
                                  ? () => _dial(context)
                                  : null,
                              label: 'Call',
                              icon: Icons.call,
                              minHeight: 96,
                              gradient: OneVozColors.brandGradient,
                            ),
                            if (!hasPhone) ...[
                              const SizedBox(height: 8),
                              const Text(
                                'No phone number saved for this contact. '
                                'Ask a caregiver to add one.',
                                textAlign: TextAlign.center,
                                style: TextStyle(fontSize: 15),
                              ),
                            ],
                            const SizedBox(height: 16),
                            // Parallel path to the phrase cards: what to say
                            // once the call connects. Big, icon-led, spoken
                            // on tap — no reading required.
                            FilledButton.tonalIcon(
                              onPressed: () => _openWhatToSay(context),
                              icon: const Icon(
                                Icons.record_voice_over,
                                size: 30,
                              ),
                              label: const Text(
                                'What to say',
                                style: TextStyle(
                                  fontSize: 24,
                                  fontWeight: FontWeight.bold,
                                ),
                              ),
                              style: FilledButton.styleFrom(
                                minimumSize: const Size.fromHeight(96),
                                shape: RoundedRectangleBorder(
                                  borderRadius: BorderRadius.circular(1000),
                                ),
                              ),
                            ),
                            const SizedBox(height: 16),
                            OutlinedButton(
                              onPressed: () => Navigator.of(context).pop(),
                              style: OutlinedButton.styleFrom(
                                minimumSize: const Size.fromHeight(96),
                                side: BorderSide(
                                  color: Theme.of(
                                    context,
                                  ).colorScheme.outline,
                                  width: 2,
                                ),
                                shape: RoundedRectangleBorder(
                                  borderRadius: BorderRadius.circular(1000),
                                ),
                              ),
                              child: const Text(
                                'Cancel',
                                style: TextStyle(
                                  fontSize: 24,
                                  fontWeight: FontWeight.bold,
                                ),
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
