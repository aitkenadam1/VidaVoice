import 'dart:async';
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:latlong2/latlong.dart';
import 'package:provider/provider.dart';

import '../services/dashboard_sync_service.dart';
import '../services/location_share_service.dart';
import '../services/profile_service.dart';
import '../services/proxy_client.dart';
import '../state/session_state.dart';

/// MapTiler API key, injected at build time:
/// `flutter build web --dart-define=MAPTILER_KEY=...`
/// Never hardcoded, never in the repo. When absent the map area shows an
/// honest "not configured" state instead of a broken map.
const _mapTilerKey = String.fromEnvironment('MAPTILER_KEY');

/// Caregiver-hub card for Phase 2A location sharing.
///
/// Hidden entirely when not signed in. Contains:
/// - per-profile opt-in (OFF by default) with the consent disclosure,
///   consent timestamp, and the auto-share pre-authorization toggle;
/// - start/stop for on-demand share sessions on this device;
/// - the live caregiver map (flutter_map + MapTiler), with accuracy
///   circles and stale labels, decrypted client-side;
/// - history trails per device and time window;
/// - "Request location" per device (picked up by the child's app on its
///   next alert poll — Phase 2A has no push);
/// - the alert history (SOS / share start / share stop), decrypted
///   client-side.
///
/// Coordinates never leave the device except inside AES-GCM ciphertext.
/// When the map key is missing or permission is denied, the UI explains —
/// no dead buttons, no dead map.
class LocationSection extends StatefulWidget {
  const LocationSection({super.key});

  @override
  State<LocationSection> createState() => _LocationSectionState();
}

class _LiveDevice {
  _LiveDevice({
    required this.installId,
    required this.name,
    required this.lat,
    required this.lon,
    required this.accuracyMeters,
    required this.updatedAt,
  });

  final String installId;
  final String name;
  final double lat;
  final double lon;
  final double accuracyMeters;
  final DateTime updatedAt;

  bool get isStale =>
      DateTime.now().difference(updatedAt) > const Duration(hours: 24);
}

class _LocationSectionState extends State<LocationSection> {
  bool _loadingDevices = false;
  String? _devicesError;
  List<ProxyDevice> _devices = [];
  List<_LiveDevice> _live = [];
  String? _mapError;

  String? _historyDeviceId;
  int _historyWindowHours = 6;
  List<LatLng> _trail = [];
  bool _loadingTrail = false;

  List<Map<String, dynamic>> _alerts = [];
  bool _loadingAlerts = false;

  String? _myInstallId;

  @override
  void initState() {
    super.initState();
    final session = context.read<SessionState>();
    if (session.proxySignedIn) {
      WidgetsBinding.instance.addPostFrameCallback((_) => _reload());
    }
  }

  Future<void> _reload() => _loadDevices();

  Future<Map<String, dynamic>?> _decrypt(
    SessionState session,
    String? ciphertext,
    String? nonce,
  ) async {
    final key = session.dashboardSync.keyBytes;
    if (key == null || ciphertext == null || nonce == null) return null;
    try {
      final clear = await DashboardSyncService.decrypt(
        key,
        ciphertext,
        nonce,
      );
      final decoded = json.decode(clear);
      return decoded is Map ? Map<String, dynamic>.from(decoded) : null;
    } catch (_) {
      return null;
    }
  }

  Future<void> _loadDevices() async {
    final session = context.read<SessionState>();
    if (!session.proxySignedIn) return;
    setState(() {
      _loadingDevices = true;
      _devicesError = null;
      _mapError = null;
    });
    try {
      _myInstallId = await session.proxyAuth.installId();
      final list = await session.proxyDevices();
      final devices = list.devices;
      final live = <_LiveDevice>[];
      String? mapError;
      for (final d in devices) {
        final blob = await session.proxy.getLocationLatest(d.installId);
        if (blob == null) continue;
        final payload = await _decrypt(
          session,
          blob['ciphertext']?.toString(),
          blob['nonce']?.toString(),
        );
        if (payload == null) continue;
        final lat = (payload['lat'] as num?)?.toDouble();
        final lon = (payload['lon'] as num?)?.toDouble();
        final ts = (payload['ts'] as num?)?.toInt();
        if (lat == null || lon == null || ts == null) continue;
        live.add(
          _LiveDevice(
            installId: d.installId,
            name: d.deviceName?.trim().isNotEmpty == true
                ? d.deviceName!.trim()
                : 'Device',
            lat: lat,
            lon: lon,
            accuracyMeters:
                (payload['acc'] as num?)?.toDouble() ?? 100,
            updatedAt: DateTime.fromMillisecondsSinceEpoch(ts),
          ),
        );
      }
      if (!mounted) return;
      setState(() {
        _loadingDevices = false;
        _devices = devices;
        _live = live;
        _mapError = mapError;
      });
      unawaited(_loadTrail());
      unawaited(_loadAlerts());
    } on ProxyException catch (e) {
      if (!mounted) return;
      setState(() {
        _loadingDevices = false;
        _devicesError = e.code == 'unreachable'
            ? 'Couldn\u2019t reach the OneVoz service. Check your '
                'connection and try again.'
            : e.message;
      });
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _loadingDevices = false;
        _devicesError = 'Something went wrong. Please try again.';
      });
    }
  }

  Future<void> _loadTrail() async {
    final session = context.read<SessionState>();
    final deviceId = _historyDeviceId ?? _live.firstOrNull?.installId;
    if (deviceId == null || !session.proxySignedIn) {
      if (mounted) setState(() => _trail = []);
      return;
    }
    setState(() {
      _loadingTrail = true;
      _historyDeviceId = deviceId;
    });
    try {
      final now = DateTime.now().millisecondsSinceEpoch;
      final since = now - _historyWindowHours * 3600 * 1000;
      final res = await session.proxy.getLocationPoints(
        installId: deviceId,
        since: since,
        until: now,
      );
      final raw = res['points'];
      final trail = <LatLng>[];
      if (raw is List) {
        for (final entry in raw) {
          if (entry is! Map) continue;
          final payload = await _decrypt(
            session,
            entry['ciphertext']?.toString(),
            entry['nonce']?.toString(),
          );
          final lat = (payload?['lat'] as num?)?.toDouble();
          final lon = (payload?['lon'] as num?)?.toDouble();
          if (lat != null && lon != null) trail.add(LatLng(lat, lon));
        }
      }
      if (!mounted) return;
      setState(() {
        _trail = trail;
        _loadingTrail = false;
      });
    } catch (_) {
      if (!mounted) return;
      setState(() => _loadingTrail = false);
    }
  }

  Future<void> _loadAlerts() async {
    final session = context.read<SessionState>();
    if (!session.proxySignedIn) return;
    setState(() => _loadingAlerts = true);
    try {
      final since =
          DateTime.now().millisecondsSinceEpoch - 90 * 24 * 3600 * 1000;
      final alerts = await session.proxy.getAlerts(sinceMs: since);
      final items = <Map<String, dynamic>>[];
      for (final a in alerts.reversed) {
        final payload = await _decrypt(
          session,
          a['ciphertext']?.toString(),
          a['nonce']?.toString(),
        );
        items.add({...a, 'payload': payload});
      }
      if (!mounted) return;
      setState(() {
        _alerts = items;
        _loadingAlerts = false;
      });
    } catch (_) {
      if (!mounted) return;
      setState(() => _loadingAlerts = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final session = context.watch<SessionState>();
    if (!session.proxySignedIn) {
      return const Text(
        'Sign in to use location sharing. The family\u2019s boards keep '
        'working offline.',
      );
    }
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _optInCard(context, session),
        const SizedBox(height: 12),
        _mapCard(context, session),
        const SizedBox(height: 12),
        _historyCard(context, session),
        const SizedBox(height: 12),
        _alertsCard(context),
      ],
    );
  }

  // ---- per-profile opt-in + session controls ----

  Widget _optInCard(BuildContext context, SessionState session) {
    final profiles = session.profiles.profiles;
    if (profiles.isEmpty) {
      return const Text('Add a profile first, then turn on location sharing.');
    }
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        for (final p in profiles) ...[
          _profileOptIn(context, session, p),
          const SizedBox(height: 8),
        ],
        Text(
          'Sharing uploads an encrypted position about once a minute while '
          'it\u2019s on, and only while this app is open. Nothing is recorded '
          'when sharing is off. An SOS from the emergency screen always '
          'sends one location update, even when sharing is off.',
          style: Theme.of(context).textTheme.bodySmall,
        ),
      ],
    );
  }

  Widget _profileOptIn(
    BuildContext context,
    SessionState session,
    UserProfile p,
  ) {
    final share = session.locationShare;
    final mySession =
        share.session != null && share.session!.profileId == p.id;
    final consent = p.locationSharingConsentAt;
    return Card(
      margin: EdgeInsets.zero,
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Expanded(
                  child: Text(
                    p.name,
                    style: const TextStyle(
                      fontSize: 16,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ),
                Switch(
                  value: p.locationSharingEnabled,
                  onChanged: (v) => _toggleOptIn(context, session, p, v),
                ),
              ],
            ),
            if (consent != null)
              Text(
                'Sharing allowed since ${_fmtDate(consent)}',
                style: Theme.of(context).textTheme.bodySmall,
              ),
            if (p.locationSharingEnabled) ...[
              const SizedBox(height: 8),
              Row(
                children: [
                  Expanded(
                    child: Text(
                      'Auto-start when I request location',
                      style: Theme.of(context).textTheme.bodyMedium,
                    ),
                  ),
                  Switch(
                    value: p.locationAutoShare,
                    onChanged: (v) async {
                      await session.profiles.setLocationAutoShare(p.id, v);
                      session.dashboardSync.schedulePush();
                      setState(() {});
                    },
                  ),
                ],
              ),
              Text(
                'When on, a \u201cRequest location\u201d alert starts a '
                '15-minute share on this device without asking first.',
                style: Theme.of(context).textTheme.bodySmall,
              ),
              const SizedBox(height: 8),
              if (mySession)
                _stopRow(context, share)
              else
                _startRow(context, session, p),
              if (share.lastError != null && mySession)
                Padding(
                  padding: const EdgeInsets.only(top: 6),
                  child: Text(
                    share.lastError!,
                    style: TextStyle(
                      color: Theme.of(context).colorScheme.error,
                      fontSize: 13,
                    ),
                  ),
                ),
            ],
          ],
        ),
      ),
    );
  }

  Future<void> _toggleOptIn(
    BuildContext context,
    SessionState session,
    UserProfile p,
    bool enable,
  ) async {
    if (!enable) {
      await session.profiles.setLocationSharingEnabled(p.id, false);
      if (session.locationShare.session?.profileId == p.id) {
        await session.locationShare.stopSession();
      }
      session.dashboardSync.schedulePush();
      setState(() {});
      return;
    }
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text('Share ${p.name}\u2019s location?'),
        content: const Text(
          'OneVoz will record this device\u2019s location while sharing is '
          'on and upload it encrypted, so your family\u2019s caregiver '
          'devices can see it on the map. Only this device\u2019s position '
          'is shared, about once a minute, and only while the app is open. '
          'You or your child can stop sharing at any time from the board '
          'or here.\n\n'
          'An SOS from the emergency screen always sends one location '
          'update, even when sharing is off.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(false),
            child: const Text('Not now'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(ctx).pop(true),
            child: const Text('Allow sharing'),
          ),
        ],
      ),
    );
    if (ok == true) {
      await session.profiles.setLocationSharingEnabled(p.id, true);
      session.dashboardSync.schedulePush();
      setState(() {});
    }
  }

  Widget _startRow(
    BuildContext context,
    SessionState session,
    UserProfile p,
  ) {
    Duration? choice = const Duration(minutes: 30);
    return StatefulBuilder(
      builder: (ctx, setRow) => Row(
        children: [
          Expanded(
            child: DropdownButtonFormField<Duration?>(
              initialValue: choice,
              decoration: const InputDecoration(
                labelText: 'Share for',
                border: OutlineInputBorder(),
                isDense: true,
              ),
              items: const [
                DropdownMenuItem(
                  value: Duration(minutes: 15),
                  child: Text('15 minutes'),
                ),
                DropdownMenuItem(
                  value: Duration(minutes: 30),
                  child: Text('30 minutes'),
                ),
                DropdownMenuItem(
                  value: Duration(hours: 1),
                  child: Text('1 hour'),
                ),
                DropdownMenuItem(value: null, child: Text('Until stopped')),
              ],
              onChanged: (v) => setRow(() => choice = v),
            ),
          ),
          const SizedBox(width: 8),
          FilledButton.icon(
            icon: const Icon(Icons.location_on),
            label: const Text('Share now'),
            onPressed: () => _startSharing(context, session, p, choice),
          ),
        ],
      ),
    );
  }

  Future<void> _startSharing(
    BuildContext context,
    SessionState session,
    UserProfile p,
    Duration? duration,
  ) async {
    // Capture the messenger before any await: context must not cross the
    // async gap.
    final messenger = ScaffoldMessenger.of(context);
    // Honest pre-check: when the OS won't give us a fix, say so instead
    // of starting a session that uploads nothing.
    final fix = await session.locationService.currentFix();
    if (fix == null) {
      if (!mounted) return;
      messenger.showSnackBar(
        const SnackBar(
          content: Text(
            'OneVoz can\u2019t get your location right now. Check that '
            'location is turned on and allowed for OneVoz, then try again.',
          ),
          duration: Duration(seconds: 5),
        ),
      );
      return;
    }
    try {
      await session.locationShare.startSession(
        profileId: p.id,
        duration: duration,
      );
    } on LocationShareException catch (e) {
      if (!mounted) return;
      messenger.showSnackBar(SnackBar(content: Text(e.message)));
    }
    if (mounted) setState(() {});
  }

  Widget _stopRow(BuildContext context, LocationShareService share) {
    final left = share.timeLeft;
    final label = left == null
        ? 'Sharing now · until stopped'
        : 'Sharing now · ${_fmtDuration(left)} left';
    return Row(
      children: [
        const Icon(Icons.location_on, color: Colors.blue),
        const SizedBox(width: 8),
        Expanded(child: Text(label)),
        OutlinedButton(
          onPressed: () async {
            await share.stopSession();
            setState(() {});
          },
          child: const Text('Stop'),
        ),
      ],
    );
  }

  // ---- live map ----

  Widget _mapCard(BuildContext context, SessionState session) {
    return Card(
      margin: EdgeInsets.zero,
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                const Text(
                  'Live map',
                  style: TextStyle(fontSize: 16, fontWeight: FontWeight.w700),
                ),
                const Spacer(),
                IconButton(
                  tooltip: 'Refresh',
                  icon: const Icon(Icons.refresh),
                  onPressed: _loadingDevices ? null : _loadDevices,
                ),
              ],
            ),
            const SizedBox(height: 8),
            if (_mapTilerKey.isEmpty)
              _mapKeyMissing(context)
            else if (_loadingDevices)
              const SizedBox(
                height: 220,
                child: Center(child: CircularProgressIndicator()),
              )
            else if (_devicesError != null)
              SizedBox(
                height: 120,
                child: Center(child: Text(_devicesError!)),
              )
            else
              _map(context, session),
            if (_mapError != null)
              Padding(
                padding: const EdgeInsets.only(top: 6),
                child: Text(
                  _mapError!,
                  style: TextStyle(
                    color: Theme.of(context).colorScheme.error,
                    fontSize: 13,
                  ),
                ),
              ),
            const SizedBox(height: 8),
            _deviceRows(context, session),
          ],
        ),
      ),
    );
  }

  Widget _mapKeyMissing(BuildContext context) {
    return Container(
      height: 160,
      decoration: BoxDecoration(
        color: Theme.of(context).colorScheme.surfaceContainerLow,
        borderRadius: BorderRadius.circular(12),
      ),
      padding: const EdgeInsets.all(16),
      child: const Center(
        child: Text(
          'The map needs a MapTiler key. Build the app with '
          '--dart-define=MAPTILER_KEY=your_key (free at maptiler.com) to '
          'enable the live map. Location sharing still works without it.',
          textAlign: TextAlign.center,
        ),
      ),
    );
  }

  Widget _map(BuildContext context, SessionState session) {
    final center = _live.isNotEmpty
        ? LatLng(_live.first.lat, _live.first.lon)
        : const LatLng(39.5, -98.35);
    return SizedBox(
      height: 260,
      child: ClipRRect(
        borderRadius: BorderRadius.circular(12),
        child: Stack(
          children: [
            FlutterMap(
              options: MapOptions(
                initialCenter: center,
                initialZoom: _live.isNotEmpty ? 13 : 3,
                interactionOptions: const InteractionOptions(
                  flags: InteractiveFlag.all,
                ),
              ),
              children: [
                TileLayer(
                  urlTemplate:
                      'https://api.maptiler.com/maps/streets-v2/{z}/{x}/{y}.png?key=$_mapTilerKey',
                  userAgentPackageName: 'me.onevoz.app',
                ),
                if (_live.isNotEmpty)
                  CircleLayer(
                    circles: [
                      for (final d in _live)
                        CircleMarker(
                          point: LatLng(d.lat, d.lon),
                          radius: d.accuracyMeters,
                          useRadiusInMeter: true,
                          color: Colors.blue.withValues(alpha: 0.15),
                          borderColor: Colors.blue.withValues(alpha: 0.5),
                          borderStrokeWidth: 2,
                        ),
                    ],
                  ),
                if (_trail.isNotEmpty)
                  PolylineLayer(
                    polylines: [
                      Polyline(
                        points: _trail,
                        color: Colors.blue,
                        strokeWidth: 4,
                      ),
                    ],
                  ),
                if (_live.isNotEmpty)
                  MarkerLayer(
                    markers: [
                      for (final d in _live)
                        Marker(
                          point: LatLng(d.lat, d.lon),
                          width: 120,
                          height: 44,
                          alignment: Alignment.topCenter,
                          child: Column(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Container(
                                padding: const EdgeInsets.symmetric(
                                  horizontal: 8,
                                  vertical: 3,
                                ),
                                decoration: BoxDecoration(
                                  color: d.isStale
                                      ? Colors.grey.shade700
                                      : Colors.blue.shade700,
                                  borderRadius: BorderRadius.circular(10),
                                ),
                                child: Text(
                                  d.name,
                                  style: const TextStyle(
                                    color: Colors.white,
                                    fontSize: 12,
                                    fontWeight: FontWeight.w600,
                                  ),
                                  overflow: TextOverflow.ellipsis,
                                ),
                              ),
                              Icon(
                                Icons.location_on,
                                color: d.isStale
                                    ? Colors.grey.shade700
                                    : Colors.blue.shade700,
                                size: 26,
                              ),
                            ],
                          ),
                        ),
                    ],
                  ),
              ],
            ),
            Positioned(
              right: 8,
              bottom: 8,
              child: Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: 6,
                  vertical: 2,
                ),
                color: Colors.white70,
                child: const Text(
                  '\u00a9 MapTiler \u00a9 OpenStreetMap contributors',
                  style: TextStyle(fontSize: 10),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _deviceRows(BuildContext context, SessionState session) {
    if (_devices.isEmpty) {
      return const Text('No devices registered yet.');
    }
    return Column(
      children: [
        for (final d in _devices)
          _deviceRow(context, session, d),
      ],
    );
  }

  Widget _deviceRow(
    BuildContext context,
    SessionState session,
    ProxyDevice d,
  ) {
    final live = _live
        .where((l) => l.installId == d.installId)
        .firstOrNull;
    final name = d.deviceName?.trim().isNotEmpty == true
        ? d.deviceName!.trim()
        : 'Device';
    final isMine = d.installId == _myInstallId;
    return ListTile(
      contentPadding: EdgeInsets.zero,
      dense: true,
      leading: Icon(
        Icons.smartphone,
        color: live != null && !live.isStale ? Colors.green : Colors.grey,
      ),
      title: Text(name + (isMine ? ' (this device)' : '')),
      subtitle: live == null
          ? const Text('Not sharing right now')
          : Text(
              live.isStale
                  ? 'Last seen ${_fmtAgo(live.updatedAt)} (stale)'
                  : 'Updated ${_fmtAgo(live.updatedAt)} · '
                      'accurate to about ${live.accuracyMeters.round()}m',
            ),
      trailing: isMine
          ? null
          : TextButton(
              onPressed: () => _requestLocation(context, session, d),
              child: const Text('Request'),
            ),
    );
  }

  Future<void> _requestLocation(
    BuildContext context,
    SessionState session,
    ProxyDevice d,
  ) async {
    // Capture the messenger before any await: context must not cross the
    // async gap.
    final messenger = ScaffoldMessenger.of(context);
    try {
      await session.locationShare.requestLocation(d.installId);
      if (!mounted) return;
      messenger.showSnackBar(
        const SnackBar(
          content: Text(
            'Request sent. That device will start sharing when its app '
            'checks in (or right away if auto-share is on).',
          ),
        ),
      );
    } on LocationShareException catch (e) {
      if (!mounted) return;
      messenger.showSnackBar(SnackBar(content: Text(e.message)));
    }
  }

  // ---- history trail ----

  Widget _historyCard(BuildContext context, SessionState session) {
    return Card(
      margin: EdgeInsets.zero,
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              'History trail',
              style: TextStyle(fontSize: 16, fontWeight: FontWeight.w700),
            ),
            const SizedBox(height: 4),
            Text(
              'Where a device has been. Trail points are stored at reduced '
              'accuracy (about 100m).',
              style: Theme.of(context).textTheme.bodySmall,
            ),
            const SizedBox(height: 8),
            Row(
              children: [
                Expanded(
                  child: DropdownButtonFormField<String?>(
                    initialValue: _historyDeviceId,
                    decoration: const InputDecoration(
                      labelText: 'Device',
                      border: OutlineInputBorder(),
                      isDense: true,
                    ),
                    items: [
                      for (final d in _devices)
                        DropdownMenuItem(
                          value: d.installId,
                          child: Text(
                            d.deviceName?.trim().isNotEmpty == true
                                ? d.deviceName!.trim()
                                : 'Device',
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                    ],
                    onChanged: (v) {
                      setState(() => _historyDeviceId = v);
                      _loadTrail();
                    },
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: DropdownButtonFormField<int>(
                    initialValue: _historyWindowHours,
                    decoration: const InputDecoration(
                      labelText: 'Window',
                      border: OutlineInputBorder(),
                      isDense: true,
                    ),
                    items: const [
                      DropdownMenuItem(value: 1, child: Text('Last hour')),
                      DropdownMenuItem(value: 6, child: Text('Last 6 hours')),
                      DropdownMenuItem(value: 24, child: Text('Last 24 hours')),
                      DropdownMenuItem(value: 168, child: Text('Last 7 days')),
                    ],
                    onChanged: (v) {
                      if (v == null) return;
                      setState(() => _historyWindowHours = v);
                      _loadTrail();
                    },
                  ),
                ),
              ],
            ),
            const SizedBox(height: 8),
            if (_loadingTrail)
              const Center(child: CircularProgressIndicator())
            else if (_trail.isEmpty)
              const Text('No trail points in this window.')
            else
              Text(
                '${_trail.length} points in the last '
                '${_historyWindowHours >= 24 ? '${_historyWindowHours ~/ 24}d' : '${_historyWindowHours}h'} '
                '(shown on the map above).',
              ),
          ],
        ),
      ),
    );
  }

  // ---- alert history ----

  Widget _alertsCard(BuildContext context) {
    return Card(
      margin: EdgeInsets.zero,
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                const Text(
                  'Alert history',
                  style: TextStyle(fontSize: 16, fontWeight: FontWeight.w700),
                ),
                const Spacer(),
                IconButton(
                  tooltip: 'Refresh',
                  icon: const Icon(Icons.refresh),
                  onPressed: _loadingAlerts ? null : _loadAlerts,
                ),
              ],
            ),
            if (_loadingAlerts)
              const Center(child: CircularProgressIndicator())
            else if (_alerts.isEmpty)
              const Text('No alerts in the last 90 days.')
            else
              for (final a in _alerts.take(30)) _alertRow(context, a),
          ],
        ),
      ),
    );
  }

  Widget _alertRow(BuildContext context, Map<String, dynamic> a) {
    final kind = a['kind']?.toString() ?? 'unknown';
    final ts = (a['ts'] as num?)?.toInt() ?? 0;
    final payload = a['payload'] as Map<String, dynamic>?;
    final label = switch (kind) {
      'sos' => 'SOS',
      'location_request' => 'Location requested',
      'share_started' => 'Sharing started',
      'share_stopped' => 'Sharing stopped',
      _ => kind,
    };
    String detail = '';
    if (payload != null) {
      final lat = (payload['lat'] as num?)?.toDouble();
      final lon = (payload['lon'] as num?)?.toDouble();
      final profileName = payload['profileName']?.toString();
      if (lat != null && lon != null) {
        detail = '${lat.toStringAsFixed(5)}, ${lon.toStringAsFixed(5)}';
      } else if (profileName != null && profileName.isNotEmpty) {
        detail = profileName;
      }
    }
    return ListTile(
      contentPadding: EdgeInsets.zero,
      dense: true,
      leading: Icon(
        kind == 'sos' ? Icons.sos : Icons.notifications_outlined,
        color: kind == 'sos' ? Colors.red : null,
      ),
      title: Text(label),
      subtitle: Text(
        [
          if (detail.isNotEmpty) detail,
          _fmtDateTime(DateTime.fromMillisecondsSinceEpoch(ts)),
        ].join(' · '),
      ),
    );
  }

  // ---- formatting helpers (no coordinates ever logged) ----

  String _fmtDuration(Duration d) {
    if (d.inHours > 0) return '${d.inHours}h ${d.inMinutes % 60}m';
    if (d.inMinutes > 0) return '${d.inMinutes}m';
    return '${d.inSeconds}s';
  }

  String _fmtAgo(DateTime t) {
    final d = DateTime.now().difference(t);
    if (d.inMinutes < 1) return 'just now';
    if (d.inMinutes < 60) return '${d.inMinutes}m ago';
    if (d.inHours < 24) return '${d.inHours}h ago';
    return '${d.inDays}d ago';
  }

  String _fmtDate(DateTime t) =>
      '${t.month}/${t.day}/${t.year}';

  String _fmtDateTime(DateTime t) =>
      '${_fmtDate(t)} ${_fmtTime(t)}';

  String _fmtTime(DateTime t) {
    final h = t.hour % 12 == 0 ? 12 : t.hour % 12;
    final m = t.minute.toString().padLeft(2, '0');
    final ap = t.hour < 12 ? 'AM' : 'PM';
    return '$h:$m $ap';
  }
}
