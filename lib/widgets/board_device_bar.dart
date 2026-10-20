import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../state/session_state.dart';
import 'mode_switch_gate.dart';

/// Device chrome for communicator boards: a slim row UNDER the
/// communication surface (below the message bar / phrase strip) with
/// the two device actions a communicator device needs, as labeled
/// buttons (Adam, 2026-10-20):
///
/// * "Caregiver Portal" — opens the account gate
///   ([showCaregiverPortalGate]): email/username + password, verified
///   live, and the account must belong to this device's family before
///   the device switches to caregiver mode. Same gate as the discreet
///   long-press on the app title, which still works.
/// * "Log out" — confirmation first, then the existing session
///   sign-out. Sign-out also clears the device role, so the next
///   launch asks who the device is for and then shows the sign-in
///   gate.
///
/// The board grid itself is untouched (fixed positions are sacred),
/// and no settings live here: account, voices, and keys stay in the
/// Caregiver Portal only.
class BoardDeviceBar extends StatelessWidget {
  const BoardDeviceBar({super.key});

  Future<void> _confirmLogOut(BuildContext context) async {
    final confirm = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Log out?'),
        content: const Text(
          'This signs this device out of the family account. '
          "You'll need to sign in again to use OneVoz on this device.",
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(ctx).pop(true),
            child: const Text('Log out'),
          ),
        ],
      ),
    );
    if (confirm != true || !context.mounted) return;
    await context.read<SessionState>().signOut();
  }

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(8, 2, 8, 6),
      child: Row(
        children: [
          TextButton.icon(
            onPressed: () => showCaregiverPortalGate(context),
            icon: const Icon(Icons.family_restroom),
            label: const Text('Caregiver Portal'),
          ),
          const Spacer(),
          TextButton.icon(
            onPressed: () => _confirmLogOut(context),
            icon: const Icon(Icons.logout),
            label: const Text('Log out'),
          ),
        ],
      ),
    );
  }
}
