import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';

import '../models/calling_safety.dart';
import '../services/location_service.dart';
import '../theme/onevoz_theme.dart';
import 'call_confirm_screen.dart';
import 'call_screen.dart';

/// The emergency flow, entered only via the 2-second hold on the home board.
///
/// One tap per action from here — the hold was the deliberate gate, so
/// everything on this screen is big, immediate, and honest:
///
/// - Call 911 / Text 911 go straight to the OS dialer / SMS composer.
///   The Text-911 body is pre-composed by [composeEmergencySms]; the GPS
///   line is omitted when no location is available (Phase 1: always).
/// - Call Mom / Call Dad reuse the normal 2-tap confirm flow.
/// - The emergency card is a full-screen, high-contrast info sheet meant
///   to be held up to a bystander.
///
/// Honest copy, stated once and plainly: OneVoz complements the device's
/// Emergency SOS — it never replaces calling 911 directly. Nothing here
/// claims any 911 certification, because there is none to claim.
class EmergencyScreen extends StatefulWidget {
  const EmergencyScreen({
    super.key,
    required this.emergency,
    this.contacts = const [],
    LocationService? locationService,
  }) : locationService = locationService ?? const NoopLocationService();

  final EmergencyProfileData emergency;
  final List<SafetyContact> contacts;
  final LocationService locationService;

  @override
  State<EmergencyScreen> createState() => _EmergencyScreenState();
}

class _EmergencyScreenState extends State<EmergencyScreen> {
  String? _gps;

  @override
  void initState() {
    super.initState();
    widget.locationService.currentCoords().then((coords) {
      if (mounted) setState(() => _gps = coords);
    });
  }

  SafetyContact? _byKind(String kind) {
    for (final c in widget.contacts) {
      if (c.kind == kind) return c;
    }
    return null;
  }

  Future<void> _launch(Uri uri, String failMessage) async {
    // url_launcher can throw (or return false) on devices with no
    // telephony/SMS handler — e.g. a Wi-Fi-only tablet. A dead tap is
    // unacceptable on this screen, so every launch failure surfaces
    // plain-language feedback instead of failing silently.
    try {
      final ok = await launchUrl(uri);
      if (!ok && mounted) _showLaunchError(failMessage);
    } catch (_) {
      if (mounted) _showLaunchError(failMessage);
    }
  }

  void _showLaunchError(String message) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(message), duration: const Duration(seconds: 4)),
    );
  }

  Future<void> _call911() =>
      _launch(telUri('911'), 'Could not open the phone app on this device.');

  Future<void> _text911() {
    // Phase 1 opens the native SMS composer: the OS Send button is the
    // human gate before anything goes out. Nothing sends silently.
    // iOS needs `&body=`, Android needs `?body=` for the prefill to land.
    final uri = smsUri(
      '911',
      composeEmergencySms(widget.emergency, gps: _gps),
      iosStyle: defaultTargetPlatform == TargetPlatform.iOS,
    );
    return _launch(uri, 'Could not open the messaging app on this device.');
  }

  void _callContact(SafetyContact contact) {
    Navigator.of(context).push(
      MaterialPageRoute(builder: (_) => CallConfirmScreen(contact: contact)),
    );
  }

  void _showCard() {
    Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) =>
            EmergencyCardScreen(emergency: widget.emergency, gps: _gps),
      ),
    );
  }

  void _practiceReplies() {
    Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => CallScreen(
          emergencyMode: true,
          phrases: const [],
          emergency: widget.emergency,
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final mom = _byKind('mom');
    final dad = _byKind('dad');
    return Theme(
      data: OneVozTheme.childTheme(),
      child: Scaffold(
        body: SafeArea(
          child: ListView(
            padding: EdgeInsets.zero,
            children: [
              // Red gradient header, matching the approved mockup's
              // `.emergency-head`: back, plain-language title, one clear
              // instruction. Big and calm — the hold on the board was the
              // deliberate gate, so nothing here asks twice.
              Container(
                decoration: const BoxDecoration(
                  gradient: OneVozColors.emergencyGradient,
                  borderRadius: BorderRadius.vertical(
                    bottom: Radius.circular(24),
                  ),
                ),
                padding: const EdgeInsets.fromLTRB(8, 8, 20, 24),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
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
                    const Padding(
                      padding: EdgeInsets.fromLTRB(12, 4, 0, 0),
                      child: Text(
                        'What help do you need?',
                        style: TextStyle(
                          color: Colors.white,
                          fontSize: 30,
                          fontWeight: FontWeight.w800,
                        ),
                      ),
                    ),
                    const Padding(
                      padding: EdgeInsets.fromLTRB(12, 6, 0, 0),
                      child: Text(
                        'Choose one clear next step.',
                        style: TextStyle(color: Colors.white, fontSize: 16),
                      ),
                    ),
                  ],
                ),
              ),
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 16, 16, 16),
                child: Column(
                  children: [
                    _actionRow(
                      context,
                      icon: Icons.call,
                      title: 'Call 911',
                      subtitle: 'Your device will ask to confirm',
                      danger: true,
                      onTap: _call911,
                    ),
                    _actionRow(
                      context,
                      icon: Icons.sms_outlined,
                      title: 'Text 911',
                      subtitle: 'Pre-written message with your details',
                      danger: true,
                      onTap: _text911,
                    ),
                    if (mom != null)
                      _actionRow(
                        context,
                        icon: Icons.person,
                        title: 'Call ${mom.name}',
                        subtitle: 'First emergency contact',
                        onTap: () => _callContact(mom),
                      ),
                    if (dad != null)
                      _actionRow(
                        context,
                        icon: Icons.person,
                        title: 'Call ${dad.name}',
                        subtitle: 'Second emergency contact',
                        onTap: () => _callContact(dad),
                      ),
                    _actionRow(
                      context,
                      icon: Icons.medical_information_outlined,
                      title: 'Show my emergency card',
                      subtitle: 'For a trusted adult or first responder',
                      onTap: _showCard,
                    ),
                    const SizedBox(height: 4),
                    // Honest location strip. Phase 1 has no GPS, so this
                    // never claims "GPS ready" — the saved address fills
                    // phrases and texts instead.
                    Container(
                      width: double.infinity,
                      padding: const EdgeInsets.all(14),
                      decoration: BoxDecoration(
                        color: Theme.of(context)
                            .colorScheme
                            .surfaceContainerLow,
                        borderRadius: BorderRadius.circular(16),
                      ),
                      child: const Text(
                        'Location sharing arrives in a later update — for '
                        'now, phrases and texts use your saved address.',
                        textAlign: TextAlign.center,
                        style: TextStyle(fontSize: 14),
                      ),
                    ),
                    const SizedBox(height: 8),
                    TextButton(
                      onPressed: _practiceReplies,
                      child: const Text('Practice 911 text replies'),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      "OneVoz complements your device's Emergency SOS — "
                      'it never replaces calling 911 directly.',
                      textAlign: TextAlign.center,
                      style: Theme.of(context).textTheme.bodySmall?.copyWith(
                        color: Theme.of(context).colorScheme.onSurfaceVariant,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  /// One big tappable emergency choice: white rounded row with an icon
  /// box, title, subtitle, and chevron — the mockup's `.emergency-choice`.
  /// Danger rows (911) get the red tint treatment.
  Widget _actionRow(
    BuildContext context, {
    required IconData icon,
    required String title,
    required String subtitle,
    required VoidCallback onTap,
    bool danger = false,
  }) {
    final scheme = Theme.of(context).colorScheme;
    final accent = danger ? OneVozColors.emergency : OneVozColors.blue;
    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: Material(
        color: danger
            ? OneVozColors.emergency.withValues(alpha: 0.08)
            : scheme.surface,
        borderRadius: BorderRadius.circular(16),
        elevation: 1,
        child: InkWell(
          onTap: onTap,
          borderRadius: BorderRadius.circular(16),
          child: Container(
            constraints: const BoxConstraints(minHeight: 84),
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(16),
              border: danger
                  ? Border.all(
                      color: OneVozColors.emergency.withValues(alpha: 0.4),
                    )
                  : null,
            ),
            child: Row(
              children: [
                Container(
                  width: 52,
                  height: 52,
                  decoration: BoxDecoration(
                    color: accent.withValues(alpha: 0.12),
                    borderRadius: BorderRadius.circular(14),
                  ),
                  child: Icon(icon, color: accent, size: 28),
                ),
                const SizedBox(width: 14),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(
                        title,
                        style: const TextStyle(
                          fontSize: 22,
                          fontWeight: FontWeight.w800,
                        ),
                      ),
                      const SizedBox(height: 2),
                      Text(
                        subtitle,
                        style: TextStyle(
                          fontSize: 14,
                          color: scheme.onSurfaceVariant,
                        ),
                      ),
                    ],
                  ),
                ),
                Icon(Icons.chevron_right, color: scheme.onSurfaceVariant),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// Full-screen, high-contrast emergency info card.
///
/// Designed to be held up to a bystander: huge type, plain labels, no
/// interaction needed. Shows the child's name and home address, the GPS
/// coordinates or an honest "location unavailable", the parent's name and
/// number, and any medical notes. Read-only — nothing here can be
/// mis-tapped.
class EmergencyCardScreen extends StatelessWidget {
  const EmergencyCardScreen({
    super.key,
    required this.emergency,
    required this.gps,
  });

  final EmergencyProfileData emergency;
  final String? gps;

  @override
  Widget build(BuildContext context) {
    final e = emergency;
    return Theme(
      data: OneVozTheme.childTheme(),
      child: Scaffold(
        backgroundColor: Colors.white,
        appBar: AppBar(
          title: const Text('Emergency card'),
          backgroundColor: Colors.black,
          foregroundColor: Colors.white,
        ),
        body: SafeArea(
          child: ListView(
            padding: const EdgeInsets.all(24),
            children: [
              _line(
                context,
                'CHILD',
                e.childName.isNotEmpty ? e.childName : '—',
                40,
              ),
              _line(
                context,
                'HOME ADDRESS',
                e.homeAddress.isNotEmpty ? e.homeAddress : '—',
                32,
              ),
              _line(
                context,
                'LOCATION',
                (gps != null && gps!.trim().isNotEmpty)
                    ? gps!
                    : 'location unavailable',
                28,
              ),
              _line(
                context,
                'PARENT',
                [
                  e.parentName,
                  e.parentPhone,
                ].where((s) => s.trim().isNotEmpty).join(' · ').ifEmpty('—'),
                32,
              ),
              if (e.medicalNotes.trim().isNotEmpty)
                _line(context, 'MEDICAL NOTES', e.medicalNotes, 28),
              const SizedBox(height: 32),
              const Text(
                'This child is nonverbal. Please communicate by text or show '
                'written words.',
                textAlign: TextAlign.center,
                style: TextStyle(fontSize: 22, fontWeight: FontWeight.bold),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _line(BuildContext context, String label, String value, double size) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 24),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            label,
            style: const TextStyle(
              fontSize: 16,
              fontWeight: FontWeight.bold,
              letterSpacing: 1.5,
              color: Colors.black54,
            ),
          ),
          const SizedBox(height: 4),
          SelectableText(
            value,
            style: TextStyle(
              fontSize: size,
              fontWeight: FontWeight.bold,
              color: Colors.black,
            ),
          ),
          const Divider(thickness: 2),
        ],
      ),
    );
  }
}

extension on String {
  /// Returns [fallback] when this string is empty.
  String ifEmpty(String fallback) => isEmpty ? fallback : this;
}
