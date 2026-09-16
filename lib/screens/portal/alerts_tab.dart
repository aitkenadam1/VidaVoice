import 'package:flutter/material.dart';

import '../../widgets/coming_soon_card.dart';

/// Portal "Alerts" tab: honest non-tappable placeholder. Push alerts
/// genuinely aren't built yet — the card says so and goes nowhere.

// ------------------------------------------------------------------- alerts

class PortalAlertsTab extends StatelessWidget {
  const PortalAlertsTab({super.key});

  @override
  Widget build(BuildContext context) {
    return const SingleChildScrollView(
      padding: EdgeInsets.all(16),
      child: ComingSoonCard(
        title: 'Alert history',
        body:
            'Safe-zone enter/leave alerts and the alert history feed will '
            'live here. Alerts already reach this device as push '
            'notifications once automatic zone watching ships.',
        icon: Icons.notifications_outlined,
      ),
    );
  }
}
