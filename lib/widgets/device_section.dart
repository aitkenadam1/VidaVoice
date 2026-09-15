import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../services/proxy_client.dart';
import '../state/session_state.dart';

/// Caregiver-hub card for the family's registered devices.
///
/// Hidden entirely when not signed in. Shows "X of N devices used" (N is
/// 3 on the base tier, 4 on Plus), each device with its last-seen time,
/// and per-row removal with confirmation. Also surfaces the server's
/// caregiver-readable message when registration hit the device cap at
/// sign-in.
class DeviceSection extends StatefulWidget {
  const DeviceSection({super.key});

  @override
  State<DeviceSection> createState() => _DeviceSectionState();
}

class _DeviceSectionState extends State<DeviceSection> {
  bool _loading = false;
  bool _loadedSignedIn = false;
  String? _error;
  ProxyDeviceList? _list;

  @override
  void initState() {
    super.initState();
    _loadedSignedIn = context.read<SessionState>().proxySignedIn;
    if (_loadedSignedIn) {
      WidgetsBinding.instance.addPostFrameCallback((_) => _load());
    }
  }

  Future<void> _load() async {
    final session = context.read<SessionState>();
    if (!session.proxySignedIn) return;
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final list = await session.proxyDevices();
      if (!mounted) return;
      setState(() {
        _loading = false;
        _list = list;
      });
    } on ProxyException catch (e) {
      if (!mounted) return;
      setState(() {
        _loading = false;
        _error = e.code == 'unreachable'
            ? 'Couldn\u2019t reach the VoiceSimple service. Check your '
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

  Future<void> _remove(ProxyDevice device) async {
    final name = _displayName(device);
    final confirm = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text('Remove "$name"?'),
        content: const Text(
          'This device will be signed out of the family account and its '
          'slot freed. The app on that device keeps working with '
          'on-device voices.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(ctx).pop(true),
            child: const Text('Remove'),
          ),
        ],
      ),
    );
    if (confirm != true || !mounted) return;
    try {
      await context.read<SessionState>().removeProxyDevice(device.installId);
    } on ProxyException catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text(e.message)));
      }
      return;
    } catch (_) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Could not remove the device.')),
        );
      }
      return;
    }
    await _load();
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
    return 'last seen ${at.toLocal().year}-'
        '${at.toLocal().month.toString().padLeft(2, '0')}-'
        '${at.toLocal().day.toString().padLeft(2, '0')}';
  }

  @override
  Widget build(BuildContext context) {
    final session = context.watch<SessionState>();
    // Hidden entirely when not signed in.
    if (!session.proxySignedIn) return const SizedBox.shrink();

    // Reload when the sign-in state flips under us (e.g. signed in from
    // the voice card, or signed out elsewhere).
    if (session.proxySignedIn != _loadedSignedIn) {
      _loadedSignedIn = session.proxySignedIn;
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) {
          if (_loadedSignedIn) {
            _load();
          } else {
            setState(() => _list = null);
          }
        }
      });
    }

    final limitNotice = session.deviceLimitNotice;
    final list = _list;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        if (limitNotice != null) ...[
          Card(
            color: Theme.of(context).colorScheme.errorContainer,
            child: Padding(
              padding: const EdgeInsets.all(12),
              child: Row(
                children: [
                  const Icon(Icons.warning_amber_outlined),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      limitNotice,
                      style: const TextStyle(fontSize: 13),
                    ),
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 8),
        ],
        Row(
          children: [
            Expanded(
              child: Padding(
                padding: const EdgeInsets.only(left: 12),
                child: Text(
                  list == null
                      ? 'Devices'
                      : '${list.devicesUsed} of ${list.deviceSlots} devices used',
                  style: const TextStyle(
                    fontSize: 14,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
            ),
            IconButton(
              tooltip: 'Refresh',
              icon: const Icon(Icons.refresh, size: 20),
              onPressed: _loading ? null : _load,
            ),
          ],
        ),
        if (list != null && list.subscriptionTier == 'plus')
          const Padding(
            padding: EdgeInsets.only(left: 12, bottom: 4),
            child: Text(
              'Plus plan \u2014 includes an extra device slot.',
              style: TextStyle(fontSize: 12),
            ),
          ),
        if (_loading && list == null)
          const Center(child: CircularProgressIndicator())
        else if (_error != null && list == null)
          Padding(
            padding: const EdgeInsets.all(12),
            child: Text(
              _error!,
              style: TextStyle(
                fontSize: 13,
                color: Theme.of(context).colorScheme.error,
              ),
            ),
          )
        else if (list != null && list.devices.isEmpty)
          const Padding(
            padding: EdgeInsets.all(12),
            child: Text(
              'No devices registered yet.',
              style: TextStyle(fontSize: 13),
            ),
          )
        else if (list != null)
          for (final device in list.devices)
            ListTile(
              dense: true,
              contentPadding: const EdgeInsets.symmetric(horizontal: 12),
              leading: const Icon(Icons.smartphone_outlined, size: 20),
              title: Text(
                _displayName(device),
                style: const TextStyle(fontSize: 13),
              ),
              subtitle: Text(
                [
                  if (device.platform != null && device.platform!.isNotEmpty)
                    device.platform!,
                  _lastSeen(device),
                ].join(' \u00b7 '),
                style: const TextStyle(fontSize: 11),
              ),
              trailing: IconButton(
                tooltip: 'Remove device',
                icon: const Icon(Icons.delete_outline, size: 20),
                onPressed: () => _remove(device),
              ),
            ),
        const Padding(
          padding: EdgeInsets.fromLTRB(12, 8, 12, 0),
          child: Text(
            'Removing a device signs it out and frees its slot. Need more '
            'slots? Plus adds one extra device.',
            style: TextStyle(fontSize: 12),
          ),
        ),
      ],
    );
  }
}
