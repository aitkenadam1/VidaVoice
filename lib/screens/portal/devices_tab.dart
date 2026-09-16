import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../services/profile_service.dart';
import '../../services/proxy_client.dart';
import '../../state/session_state.dart';

/// Portal "Devices" tab: lists every registered family device
/// (name / platform / last seen), assigns communicator devices
/// to profiles, and revokes lost devices.
///
/// Revocation calls the existing device-delete endpoint, which the
/// server fans out: the device row dies (freeing the license slot) AND
/// that install's push-token row dies (cutting off future sync and
/// push). Verified in the worker source — no client reimplementation.

// ---------------------------------------------------------------- devices

/// Lists every registered family device (name / platform / last seen),
/// assigns communicator devices to profiles, and revokes lost devices.
///
/// Revocation calls the existing device-delete endpoint, which the
/// server fans out: the device row dies (freeing the license slot) AND
/// that install's push-token row dies (cutting off future sync and
/// push). Verified in the worker source — no client reimplementation.
class PortalDevicesTab extends StatefulWidget {
  const PortalDevicesTab({super.key});

  @override
  State<PortalDevicesTab> createState() => _PortalDevicesTabState();
}

class _PortalDevicesTabState extends State<PortalDevicesTab> {
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
