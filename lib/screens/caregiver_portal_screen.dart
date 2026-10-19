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
/// Tabs and sections appear progressively by [PortalTier] (Basic /
/// Moderate / Advanced — see the switcher under the app bar): a new
/// caregiver meets four calm tabs and the essential sections; the full
/// surface is one tap away and nothing is ever removed, only folded.
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
  /// [SessionState.pendingPortalTab]. Indexes are into the FULL tab
  /// list (tier-independent); Safety is visible at every tier.
  static const int safetyTab = 2;

  @override
  State<CaregiverPortalScreen> createState() => _CaregiverPortalScreenState();
}

/// One portal tab in the full (Advanced) ordering.
class _TabSpec {
  const _TabSpec(this.icon, this.label, this.minTier, this.child);

  final IconData icon;
  final String label;
  final PortalTier minTier;
  final Widget child;
}

class _CaregiverPortalScreenState extends State<CaregiverPortalScreen> {
  /// The selected tab as an index into the FULL tab list, so tier
  /// changes never silently re-point the selection at another tab.
  int _tab = 0;

  static const _tabs = <_TabSpec>[
    _TabSpec(
      Icons.dashboard_outlined,
      'Content',
      PortalTier.basic,
      PortalContentTab(),
    ),
    _TabSpec(
      Icons.people_outline,
      'Profiles',
      PortalTier.basic,
      PortalProfilesTab(),
    ),
    _TabSpec(
      Icons.shield_outlined,
      'Safety',
      PortalTier.basic,
      PortalSafetyTab(),
    ),
    _TabSpec(
      Icons.devices_outlined,
      'Devices',
      PortalTier.moderate,
      PortalDevicesTab(),
    ),
    _TabSpec(
      Icons.notifications_outlined,
      'Alerts',
      PortalTier.advanced,
      PortalAlertsTab(),
    ),
    _TabSpec(
      Icons.settings_outlined,
      'Settings',
      PortalTier.moderate,
      PortalSettingsTab(),
    ),
    _TabSpec(
      Icons.manage_accounts_outlined,
      'Account',
      PortalTier.basic,
      PortalAccountTab(),
    ),
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
    final session = context.watch<SessionState>();
    final tier = session.portalTier;
    final visible = [
      for (var i = 0; i < _tabs.length; i++)
        if (tier.includes(_tabs[i].minTier)) i,
    ];
    // The selected tab can be folded away by lowering the tier; land on
    // the first visible tab rather than pointing at the wrong page.
    final selectedFull = visible.contains(_tab) ? _tab : visible.first;
    final selectedVisible = visible.indexOf(selectedFull);
    return Scaffold(
      appBar: AppBar(title: const Text('Caregiver Portal')),
      body: SafeArea(
        child: Column(
          children: [
            _TierBar(tier: tier, session: session),
            Expanded(
              child: IndexedStack(
                index: selectedVisible,
                children: [for (final i in visible) _tabs[i].child],
              ),
            ),
          ],
        ),
      ),
      bottomNavigationBar: BottomNavigationBar(
        currentIndex: selectedVisible,
        type: BottomNavigationBarType.fixed,
        onTap: (visibleIndex) =>
            setState(() => _tab = visible[visibleIndex]),
        items: [
          for (final i in visible)
            BottomNavigationBarItem(
              icon: Icon(_tabs[i].icon),
              label: _tabs[i].label,
            ),
        ],
      ),
    );
  }
}

/// The Basic / Moderate / Advanced switcher, pinned under the app bar on
/// every tab so the current view is always explainable and one tap from
/// changing. In Basic it carries a one-line reassurance that more is
/// available — hidden is never a dead end.
class _TierBar extends StatelessWidget {
  const _TierBar({required this.tier, required this.session});

  final PortalTier tier;
  final SessionState session;

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    return Container(
      width: double.infinity,
      color: colors.surfaceContainerHighest.withValues(alpha: 0.55),
      padding: const EdgeInsets.fromLTRB(16, 8, 16, 10),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(Icons.tune, size: 18, color: colors.onSurfaceVariant),
              const SizedBox(width: 8),
              const Text(
                'Portal view',
                style: TextStyle(fontSize: 13, fontWeight: FontWeight.w600),
              ),
              const Spacer(),
              SegmentedButton<PortalTier>(
                segments: const [
                  ButtonSegment(
                    value: PortalTier.basic,
                    label: Text('Basic'),
                  ),
                  ButtonSegment(
                    value: PortalTier.moderate,
                    label: Text('Moderate'),
                  ),
                  ButtonSegment(
                    value: PortalTier.advanced,
                    label: Text('Advanced'),
                  ),
                ],
                selected: {tier},
                onSelectionChanged: (selection) =>
                    session.setPortalTier(selection.first),
                showSelectedIcon: false,
                style: const ButtonStyle(
                  visualDensity: VisualDensity.compact,
                  textStyle: WidgetStatePropertyAll(TextStyle(fontSize: 12)),
                ),
              ),
            ],
          ),
          if (tier == PortalTier.basic)
            const Padding(
              padding: EdgeInsets.only(top: 4),
              child: Text(
                'Showing the essentials. Switch to Moderate or Advanced '
                'any time you want more settings.',
                style: TextStyle(fontSize: 12),
              ),
            ),
        ],
      ),
    );
  }
}
