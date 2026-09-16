import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../services/proxy_client.dart';
import '../state/session_state.dart';

/// Caregiver-hub card for the end-to-end encrypted dashboard sync.
///
/// Hidden entirely when not signed in. Shows the "same profile on all
/// devices" mirror toggle (synced to the family, so every device agrees)
/// and a manual "Sync now" button with the last-sync time and outcome.
/// The sync payload is encrypted on-device before upload — the server
/// only ever stores opaque bytes (see DashboardSyncService).
class DeviceSyncSection extends StatefulWidget {
  const DeviceSyncSection({super.key});

  @override
  State<DeviceSyncSection> createState() => _DeviceSyncSectionState();
}

class _DeviceSyncSectionState extends State<DeviceSyncSection> {
  bool _busy = false;
  String? _message;

  Future<void> _toggleMirror(bool value) async {
    final session = context.read<SessionState>();
    setState(() {
      _busy = true;
      _message = null;
    });
    try {
      await session.dashboardSync.setMirror(value);
      if (!mounted) return;
      setState(() {
        _busy = false;
        _message = session.dashboardSync.lastMessage;
      });
    } on ProxyException catch (e) {
      if (!mounted) return;
      setState(() {
        _busy = false;
        _message = e.code == 'unreachable'
            ? 'Couldn\u2019t reach the OneVoz service. Check your '
                  'connection and try again.'
            : e.message;
      });
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _busy = false;
        _message = 'Something went wrong. Please try again.';
      });
    }

  }

  Future<void> _syncNow() async {
    final session = context.read<SessionState>();
    setState(() {
      _busy = true;
      _message = null;
    });
    try {
      final result = await session.dashboardSync.syncNow();
      // An explicit sync counts as the first pull: local edits may
      // auto-push from here on.
      session.dashboardSync.autoPushEnabled = true;
      if (result.changed) {
        await session.dashboards.backfillLabels(session.pack);
        await session.reloadProfileData();
      }
      if (!mounted) return;
      setState(() {
        _busy = false;
        _message = result.changed
            ? 'Dashboards synced.'
            : (session.dashboardSync.lastMessage ?? 'Already up to date.');
      });
    } on ProxyException catch (e) {
      if (!mounted) return;
      setState(() {
        _busy = false;
        _message = e.code == 'unreachable'
            ? 'Couldn\u2019t reach the OneVoz service. Check your '
                  'connection and try again.'
            : e.message;
      });
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _busy = false;
        _message = 'Something went wrong. Please try again.';
      });
    }

  }

  String _lastSyncedText(DateTime? at) {
    if (at == null) return 'Never synced yet';
    final age = DateTime.now().difference(at);
    if (age.isNegative || age.inMinutes < 1) return 'Last synced just now';
    if (age.inMinutes < 60) return 'Last synced ${age.inMinutes}m ago';
    if (age.inHours < 24) return 'Last synced ${age.inHours}h ago';
    return 'Last synced ${age.inDays}d ago';
  }

  @override
  Widget build(BuildContext context) {
    final session = context.watch<SessionState>();
    // Hidden entirely when not signed in.
    if (!session.proxySignedIn) return const SizedBox.shrink();

    final sync = session.dashboardSync;
    final scheme = Theme.of(context).colorScheme;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        SwitchListTile(
          title: const Text(
            'Same profile on all devices',
            style: TextStyle(fontSize: 14, fontWeight: FontWeight.w600),
          ),
          subtitle: const Text(
            'When on, switching profiles on one device switches them '
            'everywhere. When off, each device keeps its own profile \u2014 '
            'dashboard content still stays identical.',
            style: TextStyle(fontSize: 12),
          ),
          value: sync.mirrorActiveProfile,
          onChanged: _busy ? null : _toggleMirror,
        ),
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 4, 16, 0),
          child: Row(
            children: [
              Expanded(
                child: FilledButton.icon(
                  onPressed: _busy ? null : _syncNow,
                  icon: _busy
                      ? const SizedBox(
                          width: 16,
                          height: 16,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        )
                      : const Icon(Icons.sync, size: 18),
                  label: const Text('Sync now'),
                ),
              ),
            ],
          ),
        ),
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 8, 16, 0),
          child: Text(
            _lastSyncedText(sync.lastSyncedAt),
            style: TextStyle(fontSize: 12, color: scheme.onSurfaceVariant),
          ),
        ),
        if (_message != null)
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 4, 16, 0),
            child: Text(_message!, style: const TextStyle(fontSize: 13)),
          ),
        const Padding(
          padding: EdgeInsets.fromLTRB(16, 8, 16, 0),
          child: Text(
            'Dashboards are encrypted on this device before syncing \u2014 '
            'the OneVoz service only stores scrambled data it cannot read.',
            style: TextStyle(fontSize: 12),
          ),
        ),
      ],
    );
  }
}
