import 'package:flutter/material.dart';

import '../models/safe_zone.dart';

/// Standalone safe-zones list card (Phase 2B, P1).
///
/// Fully presentational and portable: it takes the zone list plus
/// callbacks as constructor params and knows nothing about the
/// caregiver hub, the sync engine, or any app state. A future caregiver
/// portal (or any other host) can drop this in by wiring the callbacks
/// to its own services.
///
/// P1 honesty: zones are stored and synced, but no device watches them
/// yet — automatic enter/leave alerts arrive in the next OneVoz update,
/// and the card says so. Never shown on child boards.
class SafeZonesCard extends StatelessWidget {
  const SafeZonesCard({
    super.key,
    required this.zones,
    required this.onAdd,
    required this.onEdit,
    required this.onToggle,
    this.syncingIds = const {},
    this.syncMessage,
  });

  /// The family's zones, in display order.
  final List<SafeZone> zones;

  /// Called when "Add safe zone" is tapped. The host opens the editor.
  final VoidCallback onAdd;

  /// Called when a zone row is tapped. The host opens the editor.
  final ValueChanged<SafeZone> onEdit;

  /// Called when a zone's enabled switch flips. May throw — the host
  /// surfaces sync failures; the card only spins the affected row while
  /// its id is in [syncingIds].
  final Future<void> Function(SafeZone zone, bool enabled) onToggle;

  /// Zone ids currently syncing (spinner instead of switch).
  final Set<String> syncingIds;

  /// Optional last-sync status line, e.g. "Dashboards synced."
  final String? syncMessage;

  String _radiusLabel(double m) =>
      m >= 1000 ? '${(m / 1000).toStringAsFixed(1)} km' : '${m.round()} m';

  @override
  Widget build(BuildContext context) {
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
                  'Safe zones',
                  style: TextStyle(fontSize: 16, fontWeight: FontWeight.w700),
                ),
                const Spacer(),
                TextButton.icon(
                  icon: const Icon(Icons.add),
                  label: const Text('Add safe zone'),
                  onPressed: onAdd,
                ),
              ],
            ),
            Text(
              'Places that matter — Home, School. Zones sync to every '
              'family device, encrypted. Automatic enter/leave alerts '
              'arrive in the next OneVoz update; for now, nothing '
              'watches these zones yet.',
              style: Theme.of(context).textTheme.bodySmall,
            ),
            const SizedBox(height: 8),
            if (zones.isEmpty)
              const Text(
                'No safe zones yet. Add one to mark a place that matters.',
              )
            else
              for (final z in zones) _zoneRow(context, z),
            const SizedBox(height: 4),
            if (syncMessage != null && zones.isNotEmpty)
              Text(
                syncMessage!,
                style: Theme.of(context).textTheme.bodySmall,
              ),
          ],
        ),
      ),
    );
  }

  Widget _zoneRow(BuildContext context, SafeZone z) {
    final busy = syncingIds.contains(z.id);
    final notifyBits = [
      if (z.notifyEnter) 'arrival',
      if (z.notifyExit) 'leaving',
    ].join(' + ');
    return ListTile(
      contentPadding: EdgeInsets.zero,
      dense: true,
      leading: Icon(
        Icons.location_on,
        color: z.enabled ? Colors.blue : Colors.grey,
      ),
      title: Text(
        z.name,
        style: TextStyle(
          color: z.enabled ? null : Colors.grey,
          decoration: z.enabled ? null : TextDecoration.lineThrough,
        ),
      ),
      subtitle: Text(
        '${_radiusLabel(z.radiusM)} radius'
        '${notifyBits.isEmpty ? '' : ' · notifies on $notifyBits'}',
      ),
      trailing: busy
          ? const SizedBox(
              width: 24,
              height: 24,
              child: CircularProgressIndicator(strokeWidth: 2),
            )
          : Switch(
              value: z.enabled,
              onChanged: (v) => onToggle(z, v),
            ),
      onTap: busy ? null : () => onEdit(z),
    );
  }
}
