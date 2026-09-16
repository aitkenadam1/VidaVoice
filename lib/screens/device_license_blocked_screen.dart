import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../services/proxy_client.dart';
import '../state/session_state.dart';

/// Blocking screen shown right after sign-in when device registration hit
/// the family's device cap. The session stays signed in — the token is
/// needed to list and remove devices — and the caregiver frees a slot by
/// removing a device they no longer use. Registration is retried
/// automatically; on success the app proceeds to the home board.
class DeviceLicenseBlockedScreen extends StatefulWidget {
  const DeviceLicenseBlockedScreen({super.key});

  @override
  State<DeviceLicenseBlockedScreen> createState() =>
      _DeviceLicenseBlockedScreenState();
}

class _DeviceLicenseBlockedScreenState
    extends State<DeviceLicenseBlockedScreen> {
  bool _loading = true;
  bool _busy = false;
  String? _error;
  ProxyDeviceList? _list;

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

  Future<void> _remove(ProxyDevice device) async {
    final session = context.read<SessionState>();
    final name = _displayName(device);
    final confirm = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text('Remove "$name"?'),
        content: const Text(
          'This device will be signed out of the family account and its '
          'slot freed. This device will then sign in automatically.',
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
    setState(() => _busy = true);
    try {
      await session.removeProxyDevice(device.installId);
      await session.retryDeviceRegistration();
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
          _error = 'Could not remove the device. Please try again.';
        });
      }
      return;
    }
    // On success deviceLicenseBlocked clears and the app routes home via
    // the session listener. Otherwise refresh the list.
    if (mounted && context.read<SessionState>().deviceLicenseBlocked) {
      setState(() => _busy = false);
      await _load();
    }
  }

  Future<void> _retry() async {
    setState(() => _busy = true);
    await context.read<SessionState>().retryDeviceRegistration();
    if (mounted) setState(() => _busy = false);
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
    return Scaffold(
      body: SafeArea(
        child: Center(
          child: SingleChildScrollView(
            padding: const EdgeInsets.symmetric(horizontal: 32, vertical: 48),
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 520),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Icon(
                    Icons.devices_outlined,
                    size: 72,
                    color: scheme.primary,
                  ),
                  const SizedBox(height: 16),
                  const Text(
                    'All device licenses are in use',
                    style: TextStyle(
                      fontSize: 24,
                      fontWeight: FontWeight.bold,
                    ),
                    textAlign: TextAlign.center,
                  ),
                  const SizedBox(height: 8),
                  Text(
                    list == null
                        ? 'Your family plan includes a limited number of devices.'
                        : 'Your family plan includes ${list.deviceSlots} '
                              'devices, and all ${list.devicesUsed} are '
                              'registered. Remove a device you no longer '
                              'use to free its slot.',
                    style: TextStyle(
                      fontSize: 15,
                      color: scheme.onSurfaceVariant,
                    ),
                    textAlign: TextAlign.center,
                  ),
                  const SizedBox(height: 24),
                  if (_loading)
                    const Center(child: CircularProgressIndicator())
                  else if (_error != null && list == null)
                    Column(
                      children: [
                        Text(
                          _error!,
                          style: TextStyle(
                            fontSize: 14,
                            color: scheme.error,
                          ),
                          textAlign: TextAlign.center,
                        ),
                        const SizedBox(height: 12),
                        OutlinedButton.icon(
                          onPressed: _busy ? null : _load,
                          icon: const Icon(Icons.refresh),
                          label: const Text('Try again'),
                        ),
                      ],
                    )
                  else if (list != null) ...[
                    for (final device in list.devices)
                      Card(
                        margin: const EdgeInsets.symmetric(vertical: 4),
                        child: ListTile(
                          leading: const Icon(Icons.smartphone_outlined),
                          title: Text(_displayName(device)),
                          subtitle: Text(
                            [
                              if (device.platform != null &&
                                  device.platform!.isNotEmpty)
                                device.platform!,
                              _lastSeen(device),
                            ].join(' \u00b7 '),
                          ),
                          trailing: _busy
                              ? const SizedBox(
                                  width: 20,
                                  height: 20,
                                  child: CircularProgressIndicator(
                                    strokeWidth: 2,
                                  ),
                                )
                              : TextButton(
                                  onPressed: () => _remove(device),
                                  child: const Text('Remove'),
                                ),
                        ),
                      ),
                    const SizedBox(height: 16),
                    if (_error != null)
                      Padding(
                        padding: const EdgeInsets.only(bottom: 8),
                        child: Text(
                          _error!,
                          style: TextStyle(
                            fontSize: 13,
                            color: scheme.error,
                          ),
                          textAlign: TextAlign.center,
                        ),
                      ),
                    OutlinedButton.icon(
                      onPressed: _busy ? null : _retry,
                      icon: const Icon(Icons.refresh),
                      label: const Padding(
                        padding: EdgeInsets.symmetric(vertical: 10),
                        child: Text(
                          'I freed a slot on another device \u2014 try again',
                          style: TextStyle(fontSize: 15),
                        ),
                      ),
                    ),
                  ],
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}
