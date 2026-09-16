import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../screens/emergency_screen.dart';
import '../state/session_state.dart';

/// Emergency shortcut for the child board AppBars: a compact red icon that
/// opens the emergency screen directly.
///
/// This replaces the large hold-to-confirm emergency bar that used to sit
/// below the board: same destination (the emergency screen, where the
/// actual 911 call still needs a 2-second hold), without eating the
/// board's vertical space. It also gives Build and Type mode boards —
/// which never had the bottom bar — emergency access for the first time.
///
/// Hidden when the active profile has emergency disabled or no profile
/// is active.
class EmergencyShortcutButton extends StatelessWidget {
  const EmergencyShortcutButton({super.key});

  @override
  Widget build(BuildContext context) {
    final session = context.watch<SessionState>();
    final profile = session.profiles.active;
    if (profile == null || !profile.emergency.emergencyEnabled) {
      return const SizedBox.shrink();
    }
    return IconButton(
      tooltip: 'Emergency',
      icon: const Icon(Icons.emergency, color: Colors.redAccent),
      onPressed: () => Navigator.of(context).push(
        MaterialPageRoute(
          builder: (_) => EmergencyScreen(
            emergency: profile.emergency,
            contacts: profile.contacts,
          ),
        ),
      ),
    );
  }
}
