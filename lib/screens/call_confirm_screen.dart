import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';

import '../models/calling_safety.dart';
import '../theme/onevoz_theme.dart';
import '../widgets/safety_contact_avatar.dart';

/// "Call Mom?" — the second tap of the 2-tap calling rule.
///
/// Board (tap 1: the photo button, which also speaks the contact's name for
/// zero-reading confirmation) -> this screen (tap 2: Call) -> the OS dialer.
/// Nothing here dials silently: the child sees the photo and name and makes
/// a deliberate second choice, and Cancel is just as big as Call.
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

  @override
  Widget build(BuildContext context) {
    final name = contact.name.isNotEmpty ? contact.name : 'this contact';
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
              Expanded(
                child: Padding(
                  padding: const EdgeInsets.all(24),
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      OneVozGradientButton(
                        onPressed: () => _dial(context),
                        label: 'Call',
                        icon: Icons.call,
                        minHeight: 96,
                        gradient: OneVozColors.brandGradient,
                      ),
                      const SizedBox(height: 16),
                      OutlinedButton(
                        onPressed: () => Navigator.of(context).pop(),
                        style: OutlinedButton.styleFrom(
                          minimumSize: const Size.fromHeight(96),
                          side: BorderSide(
                            color: Theme.of(context).colorScheme.outline,
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
            ],
          ),
        ),
      ),
    );
  }
}
