import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../state/session_state.dart';

/// Child-facing location-sharing status, shown on the boards.
///
/// Phase 2A: while a share session is active this slim banner reads
/// "Sharing location · 23 min left · Stop" — the child's own visibility
/// into (and off-switch for) sharing. It appears ONLY during an active
/// session; otherwise it renders nothing. An incoming caregiver
/// "Request location" shows a prompt row with Share / Dismiss.
///
/// The child can always stop sharing from here. Stopping is immediate
/// and local — no confirmation needed, because the off-switch must be
/// the easiest control on the screen.
class LocationStatusBanner extends StatelessWidget {
  const LocationStatusBanner({super.key});

  @override
  Widget build(BuildContext context) {
    final session = context.watch<SessionState>();
    final share = session.locationShare;
    final active = share.session;
    final request = share.pendingRequest;

    if (active == null && request == null) {
      return const SizedBox.shrink();
    }

    final scheme = Theme.of(context).colorScheme;
    return Container(
      width: double.infinity,
      margin: const EdgeInsets.fromLTRB(12, 8, 12, 0),
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
      decoration: BoxDecoration(
        color: Colors.blue.shade50,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: Colors.blue.shade200),
      ),
      child: request != null
          ? _requestRow(context, session)
          : _sharingRow(context, session, scheme),
    );
  }

  Widget _sharingRow(
    BuildContext context,
    SessionState session,
    ColorScheme scheme,
  ) {
    final share = session.locationShare;
    final left = share.timeLeft;
    final timeText = left == null
        ? 'until stopped'
        : left.inHours > 0
        ? '${left.inHours}h ${left.inMinutes % 60}m left'
        : '${left.inMinutes}m left';
    return Row(
      children: [
        const Icon(Icons.location_on, color: Colors.blue, size: 22),
        const SizedBox(width: 10),
        Expanded(
          child: Text(
            'Sharing location · $timeText',
            style: const TextStyle(
              fontSize: 15,
              fontWeight: FontWeight.w600,
              color: Colors.black87,
            ),
          ),
        ),
        TextButton(
          onPressed: () => share.stopSession(),
          style: TextButton.styleFrom(
            foregroundColor: scheme.error,
            visualDensity: VisualDensity.compact,
          ),
          child: const Text('Stop'),
        ),
      ],
    );
  }

  Widget _requestRow(BuildContext context, SessionState session) {
    final share = session.locationShare;
    return Column(
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
              onPressed: share.dismissRequest,
              child: const Text('Dismiss'),
            ),
            const SizedBox(width: 8),
            FilledButton(
              onPressed: () => share.acceptRequest(),
              child: const Text('Share for 15 min'),
            ),
          ],
        ),
      ],
    );
  }
}
