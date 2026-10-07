import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../models/calling_safety.dart';
import '../screens/call_confirm_screen.dart';
import '../screens/caregiver_portal_screen.dart';
import '../state/session_state.dart';
import 'mode_switch_gate.dart';
import 'safety_contact_avatar.dart';

/// Phone shortcut for the child board AppBars: one tap reaches the child's
/// call contacts without scrolling to the call buttons below the board.
///
/// Always visible while a profile is active — the calling feature must show
/// on the blue banner even before any contacts exist:
/// - No call contacts yet: a sheet explains that, with a button opening the
///   password gate (contacts are a caregiver action in the Caregiver Portal).
///   Never a dead button, and never caregiver UI without verification.
/// - One contact: goes straight to call confirmation.
/// - Otherwise: a bottom sheet listing every Mom/Dad-kind contact.
/// Emergency has its own top-bar button ([EmergencyShortcutButton]).
class CallShortcutButton extends StatelessWidget {
  const CallShortcutButton({super.key});

  /// Every contact the child can call from the board: all Mom-kind and
  /// all Dad-kind contacts, in profile order. Mirrors the board's call
  /// action area — keep the two in sync.
  static List<SafetyContact> callContacts(List<SafetyContact> contacts) {
    return [
      for (final c in contacts)
        if (c.kind == 'mom' || c.kind == 'dad') c,
    ];
  }

  @override
  Widget build(BuildContext context) {
    final session = context.watch<SessionState>();
    final profile = session.profiles.active;
    if (profile == null) return const SizedBox.shrink();
    final contacts = callContacts(profile.contacts);
    return IconButton(
      tooltip: 'Call',
      icon: const Icon(Icons.call),
      onPressed: () => _open(context, session, contacts),
    );
  }

  void _open(
    BuildContext context,
    SessionState session,
    List<SafetyContact> contacts,
  ) {
    if (contacts.isEmpty) {
      _noContactsSheet(context);
      return;
    }
    if (contacts.length == 1) {
      _callContact(context, session, contacts.first);
      return;
    }
    showModalBottomSheet<void>(
      context: context,
      builder: (sheetContext) => SafeArea(
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              const Padding(
                padding: EdgeInsets.fromLTRB(16, 16, 16, 8),
                child: Text(
                  'Who do you want to call?',
                  style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
                  textAlign: TextAlign.center,
                ),
              ),
              for (final c in contacts)
                ListTile(
                  leading: SafetyContactAvatar(contact: c, radius: 24),
                  title: Text(
                    c.name.isNotEmpty ? c.name : 'Call',
                    style: const TextStyle(
                      fontSize: 17,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                  // The number rides on the sheet itself (not only on the
                  // confirm screen one tap later) so a caregiver can see
                  // exactly which number each name will dial.
                  subtitle: c.phone.isNotEmpty
                      ? Text(
                          c.phone,
                          style: const TextStyle(fontSize: 15),
                        )
                      : null,
                  trailing: const Icon(Icons.call),
                  onTap: () {
                    Navigator.of(sheetContext).pop();
                    _callContact(context, session, c);
                  },
                ),
              const SizedBox(height: 12),
            ],
          ),
        ),
      ),
    );
  }

  void _callContact(
    BuildContext context,
    SessionState session,
    SafetyContact contact,
  ) {
    session.tts.speak(contact.name);
    Navigator.of(
      context,
    ).push(MaterialPageRoute(builder: (_) => CallConfirmScreen(contact: contact)));
  }

  /// Shown when the profile has no Mom/Dad contacts yet: explains why
  /// there is nobody to call. Adding contacts is a caregiver action, so
  /// the button opens the password gate — caregiver UI never appears on
  /// a communicator device without verification.
  void _noContactsSheet(BuildContext context) {
    showModalBottomSheet<void>(
      context: context,
      builder: (sheetContext) => SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(24, 20, 24, 24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              const Icon(Icons.call, size: 40),
              const SizedBox(height: 12),
              const Text(
                'No one to call yet',
                style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 8),
              const Text(
                'A caregiver adds Mom or Dad contacts in the Caregiver '
                'Portal and they\u2019ll show up here.',
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 16),
              FilledButton.icon(
                icon: const Icon(Icons.family_restroom),
                label: const Text('Continue as caregiver'),
                onPressed: () {
                  Navigator.of(sheetContext).pop();
                  // Lands on the Safety tab after the password gate, so
                  // the caregiver is one tap from adding contacts. The
                  // gate itself never leaks portal content.
                  showCaregiverEntrySheet(
                    context,
                    initialPortalTab: CaregiverPortalScreen.safetyTab,
                  );
                },
              ),
            ],
          ),
        ),
      ),
    );
  }
}
