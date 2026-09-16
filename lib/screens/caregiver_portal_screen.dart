import 'package:flutter/material.dart';
import 'package:latlong2/latlong.dart';
import 'package:provider/provider.dart';

import '../models/safe_zone.dart';
import '../services/device_role_service.dart';
import '../services/profile_service.dart';
import '../services/proxy_client.dart';
import '../state/session_state.dart';
import '../widgets/coming_soon_card.dart';
import '../widgets/mode_switch_gate.dart';
import '../widgets/safe_zones_card.dart';
import 'safe_zone_editor_screen.dart';

/// The Caregiver Portal: the dedicated multi-page management surface for
/// caregiver-role devices. Tabs: Devices, Safe Zones, Alerts, Profiles,
/// Account.
///
/// This screen exists ONLY on caregiver-role devices. Communicator
/// devices render the board shell with zero portal routes — see the root
/// router in main.dart. The old PIN-gated CaregiverScreen is superseded
/// and is not referenced from anywhere in the portal.
class CaregiverPortalScreen extends StatefulWidget {
  const CaregiverPortalScreen({super.key});

  @override
  State<CaregiverPortalScreen> createState() => _CaregiverPortalScreenState();
}

class _CaregiverPortalScreenState extends State<CaregiverPortalScreen> {
  int _tab = 0;

  static const _tabs = [
    (icon: Icons.devices_outlined, label: 'Devices'),
    (icon: Icons.place_outlined, label: 'Safe Zones'),
    (icon: Icons.notifications_outlined, label: 'Alerts'),
    (icon: Icons.people_outline, label: 'Profiles'),
    (icon: Icons.manage_accounts_outlined, label: 'Account'),
  ];

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
            _DevicesTab(),
            _SafeZonesTab(),
            _AlertsTab(),
            _ProfilesTab(),
            _AccountTab(),
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

// ---------------------------------------------------------------- devices

/// Lists every registered family device (name / platform / last seen),
/// assigns communicator devices to profiles, and revokes lost devices.
///
/// Revocation calls the existing device-delete endpoint, which the
/// server fans out: the device row dies (freeing the license slot) AND
/// that install's push-token row dies (cutting off future sync and
/// push). Verified in the worker source — no client reimplementation.
class _DevicesTab extends StatefulWidget {
  const _DevicesTab();

  @override
  State<_DevicesTab> createState() => _DevicesTabState();
}

class _DevicesTabState extends State<_DevicesTab> {
  bool _loading = true;
  bool _busy = false;
  String? _error;
  ProxyDeviceList? _list;
  String? _thisInstallId;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _load());
  }

  Future<void> _load() async {
    final session = context.read<SessionState>();
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final results = await Future.wait([
        session.proxyDevices(),
        session.proxyAuth.installId(),
      ]);
      if (!mounted) return;
      setState(() {
        _loading = false;
        _list = results[0] as ProxyDeviceList;
        _thisInstallId = results[1] as String;
      });
    } on ProxyException catch (e) {
      if (!mounted) return;
      setState(() {
        _loading = false;
        _error = e.code == 'unreachable'
            ? 'Couldn\u2019t reach the OneVoz service. Check your '
                'connection and try again.'
            : e.message;
      });
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _loading = false;
        _error = 'Something went wrong. Please try again.';
      });
    }
  }

  /// Revoke (delete) a device. Frees its license slot and kills its sync
  /// + push access server-side. Revoking THIS device signs out locally
  /// too, so the device doesn't linger in a half-registered state.
  Future<void> _revoke(ProxyDevice device) async {
    final session = context.read<SessionState>();
    final name = _displayName(device);
    final isSelf = device.installId == _thisInstallId;
    final confirm = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text('Revoke "$name"?'),
        content: Text(
          isSelf
              ? 'This device will be signed out of the family account, '
                  'its license slot freed, and its sync and push access '
                  'cut off.'
              : 'This device will be signed out of the family account, '
                  'its license slot freed, and its sync and push access '
                  'cut off. Use this for lost or stolen devices.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(ctx).pop(true),
            child: const Text('Revoke device'),
          ),
        ],
      ),
    );
    if (confirm != true || !mounted) return;
    setState(() => _busy = true);
    try {
      await session.removeProxyDevice(device.installId);
    } on ProxyException catch (e) {
      if (mounted) {
        setState(() {
          _busy = false;
          _error = e.message;
        });
      }
      return;
    } catch (_) {
      if (mounted) {
        setState(() {
          _busy = false;
          _error = 'Could not revoke the device. Please try again.';
        });
      }
      return;
    }
    if (!mounted) return;
    if (isSelf) {
      // This device just lost its registration: sign out fully so the
      // router returns to the sign-in gate instead of a zombie session.
      await context.read<SessionState>().signOut();
      return;
    }
    setState(() => _busy = false);
    await _load();
  }

  Future<void> _assign(ProxyDevice device, String? profileId) async {
    final session = context.read<SessionState>();
    setState(() => _busy = true);
    try {
      await session.dashboardSync.setDeviceAssignment(
        device.installId,
        profileId,
      );
      // Best-effort publish: the assignment is saved locally either way,
      // and converges on the next sync.
      try {
        await session.dashboardSync.pushNow();
      } catch (_) {}
    } catch (_) {
      if (mounted) {
        setState(() {
          _error = 'Could not save the assignment. Please try again.';
        });
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  String _displayName(ProxyDevice device) {
    final name = device.deviceName;
    return (name == null || name.trim().isEmpty) ? 'Unnamed device' : name;
  }

  String _lastSeen(ProxyDevice device) {
    final raw = device.lastSeenAt;
    if (raw == null || raw.isEmpty) return 'last seen unknown';
    final at = DateTime.tryParse(raw);
    if (at == null) return 'last seen unknown';
    final age = DateTime.now().difference(at.toLocal());
    if (age.isNegative || age.inMinutes < 1) return 'last seen just now';
    if (age.inMinutes < 60) return 'last seen ${age.inMinutes}m ago';
    if (age.inHours < 24) return 'last seen ${age.inHours}h ago';
    if (age.inDays < 7) return 'last seen ${age.inDays}d ago';
    final local = at.toLocal();
    return 'last seen ${local.year}-'
        '${local.month.toString().padLeft(2, '0')}-'
        '${local.day.toString().padLeft(2, '0')}';
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final list = _list;
    if (_loading) {
      return const Center(child: CircularProgressIndicator());
    }
    if (_error != null && list == null) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(32),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                _error!,
                style: TextStyle(color: scheme.error, fontSize: 14),
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 12),
              OutlinedButton.icon(
                onPressed: _busy ? null : _load,
                icon: const Icon(Icons.refresh),
                label: const Text('Try again'),
              ),
            ],
          ),
        ),
      );
    }
    final session = context.watch<SessionState>();
    final assignments = session.dashboardSync.deviceAssignments;
    final profiles = session.profiles.profiles;
    return RefreshIndicator(
      onRefresh: _load,
      child: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          if (list != null)
            Padding(
              padding: const EdgeInsets.only(bottom: 12),
              child: Text(
                '${list.devicesUsed} of ${list.deviceSlots} device '
                'licenses in use.',
                style: TextStyle(
                  fontSize: 14,
                  color: scheme.onSurfaceVariant,
                ),
              ),
            ),
          if (_error != null)
            Padding(
              padding: const EdgeInsets.only(bottom: 8),
              child: Text(
                _error!,
                style: TextStyle(fontSize: 13, color: scheme.error),
              ),
            ),
          for (final device in list?.devices ?? const <ProxyDevice>[])
            _deviceCard(
              context,
              device: device,
              isSelf: device.installId == _thisInstallId,
              assignedProfileId: assignments[device.installId],
              profiles: profiles,
            ),
          if ((list?.devices ?? const []).isEmpty)
            const Padding(
              padding: EdgeInsets.symmetric(vertical: 32),
              child: Text(
                'No devices registered yet.',
                textAlign: TextAlign.center,
              ),
            ),
        ],
      ),
    );
  }

  Widget _deviceCard(
    BuildContext context, {
    required ProxyDevice device,
    required bool isSelf,
    required String? assignedProfileId,
    required List<UserProfile> profiles,
  }) {
    final scheme = Theme.of(context).colorScheme;
    final assigned = assignedProfileId == null
        ? null
        : profiles.where((p) => p.id == assignedProfileId).firstOrNull;
    return Card(
      margin: const EdgeInsets.only(bottom: 8),
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                const Icon(Icons.smartphone_outlined),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    _displayName(device),
                    style: const TextStyle(
                      fontSize: 16,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ),
                if (isSelf)
                  Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 10,
                      vertical: 4,
                    ),
                    decoration: BoxDecoration(
                      color: scheme.primaryContainer,
                      borderRadius: BorderRadius.circular(99),
                    ),
                    child: const Text(
                      'This device',
                      style: TextStyle(fontSize: 12),
                    ),
                  ),
              ],
            ),
            const SizedBox(height: 4),
            Text(
              [
                if (device.platform != null &&
                    device.platform!.isNotEmpty)
                  device.platform!,
                _lastSeen(device),
              ].join(' \u00b7 '),
              style: TextStyle(
                fontSize: 13,
                color: scheme.onSurfaceVariant,
              ),
            ),
            const SizedBox(height: 8),
            Row(
              children: [
                Expanded(
                  child: OutlinedButton.icon(
                    onPressed: _busy
                        ? null
                        : () => _pickAssignment(device, profiles),
                    icon: const Icon(Icons.person_outline, size: 18),
                    label: Text(
                      assigned == null
                          ? 'Assign to profile'
                          : 'For ${assigned.name}',
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                ),
                const SizedBox(width: 8),
                TextButton(
                  onPressed: _busy ? null : () => _revoke(device),
                  style: TextButton.styleFrom(
                    foregroundColor: scheme.error,
                  ),
                  child: const Text('Revoke'),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _pickAssignment(
    ProxyDevice device,
    List<UserProfile> profiles,
  ) async {
    final choice = await showDialog<String?>(
      context: context,
      builder: (ctx) => SimpleDialog(
        title: Text('Which communicator uses "${_displayName(device)}"?'),
        children: [
          for (final p in profiles)
            SimpleDialogOption(
              onPressed: () => Navigator.of(ctx).pop(p.id),
              child: Padding(
                padding: const EdgeInsets.symmetric(vertical: 8),
                child: Text(p.name, style: const TextStyle(fontSize: 16)),
              ),
            ),
          SimpleDialogOption(
            onPressed: () => Navigator.of(ctx).pop(''),
            child: const Padding(
              padding: EdgeInsets.symmetric(vertical: 8),
              child: Text(
                'No assignment',
                style: TextStyle(fontSize: 16),
              ),
            ),
          ),
        ],
      ),
    );
    if (choice == null || !mounted) return; // dismissed
    await _assign(device, choice.isEmpty ? null : choice);
  }
}

// --------------------------------------------------------------- safe zones

/// Mounts the P1 standalone safe-zone screens: the list card wired to
/// the encrypted sync engine, and the editor pushed on add/edit. The
/// widgets are constructor-injected and portal-ready — no caregiver-hub
/// imports.
class _SafeZonesTab extends StatelessWidget {
  const _SafeZonesTab();

  /// This device's GPS fix as a latlong2 LatLng, or null when
  /// unavailable. Never throws — the editor explains a missing fix.
  Future<LatLng?> _currentLocation(SessionState session) async {
    try {
      final raw = await session.locationService.currentCoords();
      if (raw == null) return null;
      final parts = raw.split(',');
      if (parts.length != 2) return null;
      final lat = double.tryParse(parts[0].trim());
      final lng = double.tryParse(parts[1].trim());
      if (lat == null || lng == null) return null;
      return LatLng(lat, lng);
    } catch (_) {
      return null;
    }
  }

  Future<void> _openEditor(
    BuildContext context,
    SessionState session, {
    SafeZone? existing,
  }) async {
    await Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => SafeZoneEditorScreen(
          existing: existing,
          getCurrentLocation: () => _currentLocation(session),
          onSave: (zone) async {
            await session.dashboardSync.upsertSafeZone(zone);
            // Best-effort publish: the zone is saved locally either way.
            // pushNow throws ProxyException on transport failure — the
            // editor keeps the zone and reports the sync failure itself.
            await session.dashboardSync.pushNow();
          },
          onDelete: existing == null
              ? null
              : (zone) async {
                  await session.dashboardSync.removeSafeZone(zone.id);
                  try {
                    await session.dashboardSync.pushNow();
                  } catch (_) {}
                },
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final session = context.watch<SessionState>();
    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        SafeZonesCard(
          zones: session.dashboardSync.safeZones,
          onAdd: () => _openEditor(context, session),
          onEdit: (zone) => _openEditor(context, session, existing: zone),
          onToggle: (zone, enabled) async {
            await session.dashboardSync.upsertSafeZone(
              zone.copyWith(enabled: enabled),
            );
            try {
              await session.dashboardSync.pushNow();
            } catch (_) {}
          },
        ),
      ],
    );
  }
}

// ------------------------------------------------------------------- alerts

class _AlertsTab extends StatelessWidget {
  const _AlertsTab();

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

// ------------------------------------------------------------------ profiles

/// Read-only profile roster for now: names, communication modes, and
/// Build-mode limits. Full profile management (create/edit/delete,
/// dashboard editing) arrives in a later portal update.
class _ProfilesTab extends StatelessWidget {
  const _ProfilesTab();

  String _modeLabel(CommunicationMode mode) => switch (mode) {
    CommunicationMode.tap => 'Tap to speak',
    CommunicationMode.build => 'Build a phrase',
    CommunicationMode.type => 'Type to speak',
  };

  @override
  Widget build(BuildContext context) {
    final session = context.watch<SessionState>();
    final scheme = Theme.of(context).colorScheme;
    final profiles = session.profiles.profiles;
    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        for (final p in profiles)
          Card(
            margin: const EdgeInsets.only(bottom: 8),
            child: ListTile(
              leading: const Icon(Icons.person_outline),
              title: Text(p.name),
              subtitle: Text(
                '${_modeLabel(p.communicationMode)}'
                '${p.communicationMode == CommunicationMode.build ? ' \u00b7 up to ${p.buildMaxSymbols} symbols' : ''}',
              ),
            ),
          ),
        if (profiles.isEmpty)
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 16),
            child: Text(
              'No communicator profiles yet.',
              textAlign: TextAlign.center,
              style: TextStyle(color: scheme.onSurfaceVariant),
            ),
          ),
        const SizedBox(height: 8),
        const ComingSoonCard(
          title: 'Profile management',
          body:
              'Creating and editing communicator profiles — names, '
              'communication modes, dashboards — is coming to this tab.',
          icon: Icons.people_outline,
        ),
      ],
    );
  }
}

// ------------------------------------------------------------------- account

class _AccountTab extends StatelessWidget {
  const _AccountTab();

  void _switchMode(BuildContext context) {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      builder: (_) => ModeSwitchGate(
        targetRole: DeviceRole.communicator,
        onVerified: () {
          Navigator.of(context).pop();
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text(
                'Switched to communicator mode — boards only.',
              ),
              duration: Duration(seconds: 3),
            ),
          );
        },
      ),
    );
  }

  Future<void> _signOut(BuildContext context) async {
    final confirm = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Sign out?'),
        content: const Text(
          'This device will be signed out of the family account. '
          'Boards already on this device keep working offline.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(ctx).pop(true),
            child: const Text('Sign out'),
          ),
        ],
      ),
    );
    if (confirm != true || !context.mounted) return;
    await context.read<SessionState>().signOut();
  }

  @override
  Widget build(BuildContext context) {
    final session = context.watch<SessionState>();
    final scheme = Theme.of(context).colorScheme;
    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        Card(
          margin: EdgeInsets.zero,
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text(
                  'Family account',
                  style: TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.bold,
                  ),
                ),
                const SizedBox(height: 8),
                Text(
                  'This device is set up as a caregiver device.',
                  style: TextStyle(
                    fontSize: 14,
                    color: scheme.onSurfaceVariant,
                  ),
                ),
                if (session.proxyFamilyId != null) ...[
                  const SizedBox(height: 4),
                  Text(
                    'Family ID: ${session.proxyFamilyId}',
                    style: TextStyle(
                      fontSize: 12,
                      color: scheme.onSurfaceVariant,
                    ),
                  ),
                ],
              ],
            ),
          ),
        ),
        const SizedBox(height: 12),
        Card(
          margin: EdgeInsets.zero,
          child: Column(
            children: [
              ListTile(
                leading: const Icon(Icons.swap_horiz),
                title: const Text('Switch to communicator mode'),
                subtitle: const Text(
                  'Make this device the AAC voice. Requires your account password.',
                ),
                trailing: const Icon(Icons.arrow_forward_ios, size: 16),
                onTap: () => _switchMode(context),
              ),
              const Divider(height: 1),
              ListTile(
                leading: Icon(Icons.logout, color: scheme.error),
                title: Text(
                  'Sign out',
                  style: TextStyle(color: scheme.error),
                ),
                onTap: () => _signOut(context),
              ),
            ],
          ),
        ),
        const SizedBox(height: 12),
        const ComingSoonCard(
          title: 'Voice quota & subscription',
          body:
              'Cloud-voice usage, device licenses, and subscription '
              'management are coming to this tab.',
          icon: Icons.manage_accounts_outlined,
        ),
      ],
    );
  }
}
