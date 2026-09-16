import 'package:flutter/material.dart';
import 'package:latlong2/latlong.dart';
import 'package:provider/provider.dart';

import '../../models/safe_zone.dart';
import '../../state/session_state.dart';
import '../../widgets/location_section.dart';
import '../../widgets/safe_zones_card.dart';
import '../calling_safety_hub_screen.dart';
import '../safe_zone_editor_screen.dart';
import 'portal_section.dart';

/// Portal "Safety" tab: Calling & Safety (contacts, phrase bank,
/// emergency details), Location sharing, and Safe Zones.
///
/// The safe-zone wiring moved here from the old standalone Safe Zones
/// tab; the list card and editor are the same constructor-injected,
/// portal-ready widgets from the P1 build.
class PortalSafetyTab extends StatelessWidget {
  const PortalSafetyTab({super.key});

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

  Future<void> _openZoneEditor(
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
    final profile = session.profiles.active;
    final contactCount = profile?.contacts.length ?? 0;
    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        PortalSection(
          title: 'Calling & Safety',
          icon: Icons.call_outlined,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Padding(
                padding: EdgeInsets.fromLTRB(4, 0, 4, 8),
                child: Text(
                  'Who they can call, what they can say on a call, and the '
                  'emergency details that fill in their phrases.',
                  style: TextStyle(fontSize: 13),
                ),
              ),
              if (profile != null)
                Padding(
                  padding: const EdgeInsets.fromLTRB(4, 0, 4, 8),
                  child: Text(
                    contactCount == 0
                        ? 'No contacts yet for ${profile.name}'
                        : '$contactCount contact${contactCount == 1 ? '' : 's'} for ${profile.name}',
                    style: TextStyle(
                      fontSize: 13,
                      color: Theme.of(context).colorScheme.onSurfaceVariant,
                    ),
                  ),
                ),
              FilledButton.icon(
                icon: const Icon(Icons.call_outlined),
                label: const Text('Open Calling & Safety'),
                onPressed: () {
                  Navigator.of(context).push(
                    MaterialPageRoute(
                      builder: (_) => const CallingSafetyHubScreen(),
                    ),
                  );
                },
              ),
            ],
          ),
        ),
        PortalSection(
          title: 'Location',
          icon: Icons.location_on_outlined,
          child: const LocationSection(),
        ),
        PortalSection(
          title: 'Safe zones',
          icon: Icons.place_outlined,
          child: SafeZonesCard(
            zones: session.dashboardSync.safeZones,
            onAdd: () => _openZoneEditor(context, session),
            onEdit: (zone) =>
                _openZoneEditor(context, session, existing: zone),
            onToggle: (zone, enabled) async {
              await session.dashboardSync.upsertSafeZone(
                zone.copyWith(enabled: enabled),
              );
              try {
                await session.dashboardSync.pushNow();
              } catch (_) {}
            },
          ),
        ),
      ],
    );
  }
}
