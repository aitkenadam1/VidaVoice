import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:latlong2/latlong.dart';

import '../models/safe_zone.dart';
import '../services/proxy_client.dart';

/// MapTiler API key, injected at build time:
/// `flutter build web --dart-define=MAPTILER_KEY=...`
/// Never hardcoded, never in the repo. When absent the editor shows an
/// honest placeholder and manual coordinate fields — creating a zone
/// never depends on the map tiles.
const _mapTilerKey = String.fromEnvironment('MAPTILER_KEY');

/// Standalone safe-zone editor (Phase 2B, P1).
///
/// Fully portable: it takes the zone being edited plus callbacks as
/// constructor params and knows nothing about the caregiver hub, the
/// sync engine, or any app state. The host wires [onSave]/[onDelete] to
/// its own persistence + sync, and [getCurrentLocation] to its own
/// location service.
///
/// Create or edit one zone: name, center (tap the map, use the current
/// GPS fix, or type coordinates), radius slider (50 m – 2 km), enter/exit
/// notification toggles, enabled switch. Validation errors are shown
/// inline; sync failures thrown by [onSave]/[onDelete] surface as an
/// honest toast (the zone is still kept locally by the host).
///
/// P1 honesty: zones are saved and synced, but no device watches them
/// yet — automatic enter/exit alerts arrive in the next update. The
/// editor says so instead of implying live monitoring.
class SafeZoneEditorScreen extends StatefulWidget {
  const SafeZoneEditorScreen({
    super.key,
    this.existing,
    required this.onSave,
    this.onDelete,
    required this.getCurrentLocation,
  });

  /// Null = create a new zone.
  final SafeZone? existing;

  /// Persists the zone (and syncs it, if the host does that). May throw
  /// [ProxyException] — the editor keeps the zone and says sync failed.
  final Future<void> Function(SafeZone zone) onSave;

  /// Deletes the zone. Null hides the delete action (create mode).
  final Future<void> Function(SafeZone zone)? onDelete;

  /// This device's current GPS fix, or null when unavailable. Never
  /// throws — the editor explains when there is no fix.
  final Future<LatLng?> Function() getCurrentLocation;

  @override
  State<SafeZoneEditorScreen> createState() => _SafeZoneEditorScreenState();
}

class _SafeZoneEditorScreenState extends State<SafeZoneEditorScreen> {
  late final TextEditingController _name;
  late final TextEditingController _lat;
  late final TextEditingController _lng;
  double? _centerLat;
  double? _centerLng;
  late double _radiusM;
  late bool _enabled;
  late bool _notifyEnter;
  late bool _notifyExit;

  bool _saving = false;
  List<String> _errors = [];
  final MapController _mapController = MapController();

  @override
  void initState() {
    super.initState();
    final e = widget.existing;
    _name = TextEditingController(text: e?.name ?? '');
    _centerLat = e?.lat;
    _centerLng = e?.lng;
    _lat = TextEditingController(
      text: e == null ? '' : e.lat.toStringAsFixed(5),
    );
    _lng = TextEditingController(
      text: e == null ? '' : e.lng.toStringAsFixed(5),
    );
    _radiusM = e?.radiusM ?? SafeZone.defaultRadiusM;
    _enabled = e?.enabled ?? true;
    _notifyEnter = e?.notifyEnter ?? true;
    _notifyExit = e?.notifyExit ?? true;
  }

  @override
  void dispose() {
    _name.dispose();
    _lat.dispose();
    _lng.dispose();
    _mapController.dispose();
    super.dispose();
  }

  bool get _isNew => widget.existing == null;

  void _setCenter(double lat, double lng) {
    setState(() {
      _centerLat = lat;
      _centerLng = lng;
      _lat.text = lat.toStringAsFixed(5);
      _lng.text = lng.toStringAsFixed(5);
      _errors = [];
    });
  }

  Future<void> _useMyLocation() async {
    final messenger = ScaffoldMessenger.of(context);
    final fix = await widget.getCurrentLocation();
    if (!mounted) return;
    if (fix == null) {
      messenger.showSnackBar(
        const SnackBar(
          content: Text(
            'OneVoz can\u2019t get your location right now. Check that '
            'location is turned on and allowed for OneVoz, or tap the map '
            'to place the center by hand.',
          ),
          duration: Duration(seconds: 5),
        ),
      );
      return;
    }
    _setCenter(fix.latitude, fix.longitude);
    // The controller is only attached when the real map is built (a
    // MapTiler key is configured); moving an unattached controller
    // throws, so skip it in key-less builds.
    if (_mapTilerKey.isNotEmpty) {
      _mapController.move(fix, 14);
    }
  }

  /// Parses the manual coordinate fields into the map center, if both
  /// are valid. Called on save and on field submit.
  void _applyManualCoords() {
    final lat = double.tryParse(_lat.text.trim());
    final lng = double.tryParse(_lng.text.trim());
    if (lat != null && lng != null) {
      _centerLat = lat;
      _centerLng = lng;
    }
  }

  List<String> _validateDraft() {
    _applyManualCoords();
    final draft = SafeZone(
      id: widget.existing?.id ?? SafeZone.newId(),
      name: _name.text,
      lat: _centerLat ?? double.nan,
      lng: _centerLng ?? double.nan,
      radiusM: _radiusM,
      enabled: _enabled,
      notifyEnter: _notifyEnter,
      notifyExit: _notifyExit,
      updatedTs: DateTime.now(),
    );
    final problems = draft.validate().toList();
    if (_centerLat == null || _centerLng == null) {
      problems.insert(
        0,
        'Place the zone center: tap the map, use your current location, '
        'or type coordinates below.',
      );
    }
    return problems;
  }

  Future<void> _save() async {
    final messenger = ScaffoldMessenger.of(context);
    final problems = _validateDraft();
    if (problems.isNotEmpty) {
      setState(() => _errors = problems);
      return;
    }
    setState(() {
      _errors = [];
      _saving = true;
    });
    final zone = SafeZone(
      id: widget.existing?.id ?? SafeZone.newId(),
      name: _name.text.trim(),
      lat: _centerLat!,
      lng: _centerLng!,
      radiusM: _radiusM,
      enabled: _enabled,
      notifyEnter: _notifyEnter,
      notifyExit: _notifyExit,
      updatedTs: DateTime.now(),
    );
    try {
      await widget.onSave(zone);
      if (!mounted) return;
      Navigator.of(context).pop(true);
    } on ProxyException catch (e) {
      if (!mounted) return;
      setState(() => _saving = false);
      messenger.showSnackBar(
        SnackBar(
          content: Text(
            e.code == 'unreachable'
                ? 'Zone saved on this device, but it couldn\u2019t sync. '
                    'Check your connection — it will sync on the next '
                    'successful sync.'
                : 'Zone saved on this device, but syncing failed: '
                    '${e.message}',
          ),
          duration: const Duration(seconds: 6),
        ),
      );
    } catch (_) {
      if (!mounted) return;
      setState(() => _saving = false);
      messenger.showSnackBar(
        const SnackBar(
          content: Text(
            'Zone saved on this device, but something went wrong syncing '
            'it. It will sync on the next successful sync.',
          ),
        ),
      );
    }
  }

  Future<void> _delete() async {
    final existing = widget.existing;
    final onDelete = widget.onDelete;
    if (existing == null || onDelete == null) return;
    final messenger = ScaffoldMessenger.of(context);
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text('Delete \u201c${existing.name}\u201d?'),
        content: const Text(
          'This removes the safe zone from the family\u2019s synced zones. '
          'This can\u2019t be undone.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(false),
            child: const Text('Keep it'),
          ),
          FilledButton(
            style: FilledButton.styleFrom(
              backgroundColor: Theme.of(context).colorScheme.error,
            ),
            onPressed: () => Navigator.of(ctx).pop(true),
            child: const Text('Delete'),
          ),
        ],
      ),
    );
    if (confirmed != true || !mounted) return;
    setState(() => _saving = true);
    try {
      await onDelete(existing);
      if (!mounted) return;
      Navigator.of(context).pop(true);
    } on ProxyException catch (e) {
      if (!mounted) return;
      setState(() => _saving = false);
      messenger.showSnackBar(
        SnackBar(
          content: Text(
            e.code == 'unreachable'
                ? 'Couldn\u2019t reach the OneVoz service. The zone is '
                    'still on this device\u2019s list.'
                : 'Delete failed: ${e.message}',
          ),
        ),
      );
    }
  }

  String _radiusLabel(double m) =>
      m >= 1000 ? '${(m / 1000).toStringAsFixed(1)} km' : '${m.round()} m';

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text(_isNew ? 'New safe zone' : 'Edit safe zone'),
        actions: [
          if (!_isNew && widget.onDelete != null)
            IconButton(
              tooltip: 'Delete zone',
              icon: const Icon(Icons.delete_outline),
              onPressed: _saving ? null : _delete,
            ),
        ],
      ),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          if (_errors.isNotEmpty) _errorBox(context),
          TextField(
            key: const Key('zone_name_field'),
            controller: _name,
            enabled: !_saving,
            maxLength: SafeZone.maxNameLength,
            textCapitalization: TextCapitalization.words,
            decoration: const InputDecoration(
              labelText: 'Zone name',
              hintText: 'Home, School, Grandma\u2019s\u2026',
              border: OutlineInputBorder(),
            ),
            onChanged: (_) {
              if (_errors.isNotEmpty) setState(() => _errors = []);
            },
          ),
          const SizedBox(height: 12),
          _mapArea(context),
          const SizedBox(height: 8),
          Row(
            children: [
              Expanded(
                child: TextField(
                  key: const Key('zone_lat_field'),
                  controller: _lat,
                  enabled: !_saving,
                  keyboardType: const TextInputType.numberWithOptions(
                    signed: true,
                    decimal: true,
                  ),
                  decoration: const InputDecoration(
                    labelText: 'Latitude',
                    border: OutlineInputBorder(),
                    isDense: true,
                  ),
                  onSubmitted: (_) => setState(_applyManualCoords),
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: TextField(
                  key: const Key('zone_lng_field'),
                  controller: _lng,
                  enabled: !_saving,
                  keyboardType: const TextInputType.numberWithOptions(
                    signed: true,
                    decimal: true,
                  ),
                  decoration: const InputDecoration(
                    labelText: 'Longitude',
                    border: OutlineInputBorder(),
                    isDense: true,
                  ),
                  onSubmitted: (_) => setState(_applyManualCoords),
                ),
              ),
              const SizedBox(width: 8),
              FilledButton.tonalIcon(
                icon: const Icon(Icons.my_location),
                label: const Text('Use mine'),
                onPressed: _saving ? null : _useMyLocation,
              ),
            ],
          ),
          const SizedBox(height: 4),
          Text(
            'Tap the map to move the center, or type coordinates. '
            '\u201cUse mine\u201d centers it on this device\u2019s current '
            'GPS fix.',
            style: Theme.of(context).textTheme.bodySmall,
          ),
          const SizedBox(height: 12),
          Row(
            children: [
              const Text(
                'Radius',
                style: TextStyle(fontSize: 16, fontWeight: FontWeight.w600),
              ),
              const Spacer(),
              Text(
                _radiusLabel(_radiusM),
                style: const TextStyle(
                  fontSize: 16,
                  fontWeight: FontWeight.w700,
                ),
              ),
            ],
          ),
          Slider(
            value: _radiusM,
            min: SafeZone.minRadiusM,
            max: SafeZone.maxRadiusM,
            divisions: 39,
            label: _radiusLabel(_radiusM),
            onChanged: _saving ? null : (v) => setState(() => _radiusM = v),
          ),
          SwitchListTile(
            contentPadding: EdgeInsets.zero,
            title: const Text('Zone is active'),
            subtitle: const Text(
              'Turned-off zones are kept but never trigger alerts.',
            ),
            value: _enabled,
            onChanged: _saving ? null : (v) => setState(() => _enabled = v),
          ),
          SwitchListTile(
            contentPadding: EdgeInsets.zero,
            title: const Text('Notify on arrival'),
            value: _notifyEnter,
            onChanged: _saving
                ? null
                : (v) => setState(() => _notifyEnter = v),
          ),
          SwitchListTile(
            contentPadding: EdgeInsets.zero,
            title: const Text('Notify on leaving'),
            value: _notifyExit,
            onChanged: _saving
                ? null
                : (v) => setState(() => _notifyExit = v),
          ),
          const SizedBox(height: 4),
          Text(
            'Zones are saved and synced to every family device. Automatic '
            'enter/leave alerts arrive in the next OneVoz update — for '
            'now, nothing watches these zones yet.',
            style: Theme.of(context).textTheme.bodySmall,
          ),
          const SizedBox(height: 16),
          FilledButton.icon(
            key: const Key('zone_save_button'),
            icon: _saving
                ? const SizedBox(
                    width: 18,
                    height: 18,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                : const Icon(Icons.save_outlined),
            label: Text(_saving ? 'Syncing zones\u2026' : 'Save zone'),
            onPressed: _saving ? null : _save,
          ),
          const SizedBox(height: 24),
        ],
      ),
    );
  }

  Widget _errorBox(BuildContext context) {
    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: Theme.of(context).colorScheme.errorContainer,
        borderRadius: BorderRadius.circular(12),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          for (final e in _errors)
            Padding(
              padding: const EdgeInsets.only(bottom: 4),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text('\u2022 '),
                  Expanded(child: Text(e)),
                ],
              ),
            ),
        ],
      ),
    );
  }

  Widget _mapArea(BuildContext context) {
    if (_mapTilerKey.isEmpty) {
      return Container(
        height: 160,
        decoration: BoxDecoration(
          color: Theme.of(context).colorScheme.surfaceContainerLow,
          borderRadius: BorderRadius.circular(12),
        ),
        padding: const EdgeInsets.all(16),
        child: Center(
          child: Text(
            _centerLat == null
                ? 'The map needs a MapTiler key (build with '
                    '--dart-define=MAPTILER_KEY=your_key). Until then, '
                    'type the coordinates or use \u201cUse mine\u201d.'
                : 'Center: ${_centerLat!.toStringAsFixed(5)}, '
                    '${_centerLng!.toStringAsFixed(5)} \u00b7 '
                    '${_radiusLabel(_radiusM)} radius',
            textAlign: TextAlign.center,
          ),
        ),
      );
    }
    final center = _centerLat == null
        ? const LatLng(39.5, -98.35)
        : LatLng(_centerLat!, _centerLng!);
    return SizedBox(
      height: 260,
      child: ClipRRect(
        borderRadius: BorderRadius.circular(12),
        child: Stack(
          children: [
            FlutterMap(
              mapController: _mapController,
              options: MapOptions(
                initialCenter: center,
                initialZoom: _centerLat == null ? 3 : 14,
                onTap: (_, point) =>
                    _setCenter(point.latitude, point.longitude),
              ),
              children: [
                TileLayer(
                  urlTemplate:
                      'https://api.maptiler.com/maps/streets-v2/256/{z}/{x}/{y}.png?key=$_mapTilerKey',
                  userAgentPackageName: 'me.onevoz.app',
                ),
                if (_centerLat != null) ...[
                  CircleLayer(
                    circles: [
                      CircleMarker(
                        point: LatLng(_centerLat!, _centerLng!),
                        radius: _radiusM,
                        useRadiusInMeter: true,
                        color: Colors.blue.withValues(alpha: 0.15),
                        borderColor: Colors.blue.withValues(alpha: 0.6),
                        borderStrokeWidth: 2,
                      ),
                    ],
                  ),
                  MarkerLayer(
                    markers: [
                      Marker(
                        point: LatLng(_centerLat!, _centerLng!),
                        width: 40,
                        height: 40,
                        child: const Icon(
                          Icons.location_on,
                          color: Colors.blue,
                          size: 36,
                        ),
                      ),
                    ],
                  ),
                ],
              ],
            ),
            Positioned(
              right: 8,
              top: 8,
              child: FloatingActionButton.small(
                heroTag: 'safezone_locate_me',
                tooltip: 'Center on my location',
                onPressed: _saving ? null : _useMyLocation,
                child: const Icon(Icons.my_location),
              ),
            ),
            Positioned(
              left: 8,
              top: 8,
              child: Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: 10,
                  vertical: 6,
                ),
                decoration: BoxDecoration(
                  color: Colors.black54,
                  borderRadius: BorderRadius.circular(16),
                ),
                child: const Text(
                  'Tap the map to place the center',
                  style: TextStyle(color: Colors.white, fontSize: 12),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
