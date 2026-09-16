import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../state/session_state.dart';

/// Child-facing location-request consent prompt, shown on the boards.
///
/// When the caregiver taps "Request" on this device and auto-share is not
/// pre-authorized for the profile, the child is asked here — "Share for
/// 15 min" or "Dismiss". Nothing renders otherwise.
///
/// This is the ONLY location UI on the child's boards. The sharing status
/// itself ("Sharing location · Stop") used to sit at the top of the
/// dashboard; it now lives in the caregiver hub, where little fingers
/// can't see it or stop a share.
class LocationRequestPrompt extends StatelessWidget {
  const LocationRequestPrompt({super.key});

  @override
  Widget build(BuildContext context) {
    final session = context.watch<SessionState>();
    final request = session.locationShare.pendingRequest;

    if (request == null) {
      return const SizedBox.shrink();
    }

    return Container(
      width: double.infinity,
      margin: const EdgeInsets.fromLTRB(12, 8, 12, 0),
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
      decoration: BoxDecoration(
        color: Colors.blue.shade50,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: Colors.blue.shade200),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Row(
            children: [
              Icon(Icons.location_searching, color: Colors.blue, size: 22),
              SizedBox(width: 10),
              Expanded(
                child: Text(
                  'Your caregiver is asking to see your location.',
                  style: TextStyle(
                    fontSize: 15,
                    fontWeight: FontWeight.w600,
                    color: Colors.black87,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          Row(
            mainAxisAlignment: MainAxisAlignment.end,
            children: [
              TextButton(
                onPressed: session.locationShare.dismissRequest,
                child: const Text('Dismiss'),
              ),
              const SizedBox(width: 8),
              FilledButton(
                onPressed: () => session.locationShare.acceptRequest(),
                child: const Text('Share for 15 min'),
              ),
            ],
          ),
        ],
      ),
    );
  }
}
