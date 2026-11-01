import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../models/calling_safety.dart';
import '../state/session_state.dart';
import 'calling_coming_soon.dart';

/// Phone shortcut for the child board AppBars.
///
/// Always visible while a profile is active — the calling feature must
/// show on the blue banner even before any contacts exist. Calling
/// isn't live yet: a tap opens the calling coming-soon sheet
/// ([showCallingComingSoon]) and never dials, whatever contacts exist.
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
    final profile = context.watch<SessionState>().profiles.active;
    if (profile == null) return const SizedBox.shrink();
    return IconButton(
      tooltip: 'Call',
      icon: const Icon(Icons.call),
      onPressed: () => showCallingComingSoon(context),
    );
  }
}
