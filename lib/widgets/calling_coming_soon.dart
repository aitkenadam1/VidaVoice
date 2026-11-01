import 'package:flutter/material.dart';

import 'coming_soon_card.dart';

/// The one coming-soon presentation for calling, shared by every
/// communicator call entry point — the board call button, the board's
/// contact call buttons, and the emergency screen's contact rows —
/// while calling isn't live yet.
///
/// Honest and inert: no dialer opens and no call-confirm screen
/// appears. The emergency screen's 911 rows do NOT come through here —
/// Call 911 and Text 911 stay fully functional.
void showCallingComingSoon(BuildContext context) {
  showModalBottomSheet<void>(
    context: context,
    builder: (_) => const SafeArea(
      child: Padding(
        padding: EdgeInsets.all(16),
        child: ComingSoonCard(
          title: 'Calling',
          body:
              'Calling is coming soon. Soon you\u2019ll be able to call '
              'your people right from OneVoz.',
          icon: Icons.call,
        ),
      ),
    ),
  );
}
