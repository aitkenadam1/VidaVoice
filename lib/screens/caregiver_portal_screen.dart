import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../state/session_state.dart';
import 'portal/account_tab.dart';
import 'portal/alerts_tab.dart';
import 'portal/content_tab.dart';
import 'portal/devices_tab.dart';
import 'portal/profiles_tab.dart';
import 'portal/safety_tab.dart';
import 'portal/settings_tab.dart';

/// The Caregiver Portal: the dedicated multi-page management surface for
/// caregiver-role devices. Tabs: Content, Profiles, Safety, Devices,
/// Alerts, Settings, Account.
///
/// This screen exists ONLY on caregiver-role devices. Communicator
/// devices render the board shell with zero portal routes — see the root
/// router in main.dart. The old PIN-gated CaregiverScreen is superseded
/// and is not referenced from anywhere in the app (it survives only as
/// legacy test surface).
class CaregiverPortalScreen extends StatefulWidget {
  const CaregiverPortalScreen({super.key});

  /// Index of the Safety tab — the communicator-side "Continue as
  /// caregiver" entry from the no-contacts sheet lands here via
  /// [SessionState.pendingPortalTab].
  static const int safetyTab = 2;

  @override
  State<CaregiverPortalScreen> createState() => _CaregiverPortalScreenState();
}

class _CaregiverPortalScreenState extends State<CaregiverPortalScreen> {
  int _tab = 0;

  static const _tabs = [
    (icon: Icons.dashboard_outlined, label: 'Content'),
    (icon: Icons.people_outline, label: 'Profiles'),
    (icon: Icons.shield_outlined, label: 'Safety'),
    (icon: Icons.devices_outlined, label: 'Devices'),
    (icon: Icons.notifications_outlined, label: 'Alerts'),
    (icon: Icons.settings_outlined, label: 'Settings'),
    (icon: Icons.manage_accounts_outlined, label: 'Account'),
  ];

  @override
  void initState() {
    super.initState();
    // One-shot deep link: the discreet communicator-side entry can ask
    // for a specific tab (e.g. Safety for "Continue as caregiver" from
    // the no-contacts sheet). Consumed here so later rebuilds don't
    // yank the caregiver back.
    final session = context.read<SessionState>();
    final requested = session.pendingPortalTab;
    if (requested != null) {
      session.pendingPortalTab = null;
      if (requested >= 0 && requested < _tabs.length) {
        _tab = requested;
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Caregiver Portal'),
      ),
      body: SafeArea(
        child: IndexedStack(
          index: _tab,
          children: const [
            PortalContentTab(),
            PortalProfilesTab(),
            PortalSafetyTab(),
            PortalDevicesTab(),
            PortalAlertsTab(),
            PortalSettingsTab(),
            PortalAccountTab(),
          ],
        ),
      ),
      bottomNavigationBar: BottomNavigationBar(
        currentIndex: _tab,
        type: BottomNavigationBarType.fixed,
        onTap: (i) => setState(() => _tab = i),
        items: [
          for (final t in _tabs)
            BottomNavigationBarItem(icon: Icon(t.icon), label: t.label),
        ],
      ),
    );
  }
}
