import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../models/calling_safety.dart';
import '../screens/call_confirm_screen.dart';
import '../state/session_state.dart';
import 'safety_contact_avatar.dart';

/// Phone shortcut for the child board AppBars: one tap reaches the child's
/// call contacts without scrolling to the call buttons below the board.
///
/// - Hidden when the active profile has no call contacts.
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
    if (contacts.isEmpty) return const SizedBox.shrink();
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
}
