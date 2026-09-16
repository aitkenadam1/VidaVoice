import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../app_config.dart';
import '../services/device_role_service.dart';
import '../state/session_state.dart';
import '../theme/onevoz_theme.dart';

/// First-launch device-role question, shown once per device after sign-in
/// (before anything else). The choice is per-device and persisted in
/// secure storage:
///
/// * Communicator — this device is the AAC voice (e.g. the child's iPad).
///   Boards only; the Caregiver Portal does not exist there.
/// * Caregiver — this device manages the family: profiles, devices, safe
///   zones, alerts, controls.
///
/// A caregiver can switch a device between roles later by verifying the
/// OneVoz account password — see [ModeSwitchGate].
class DeviceRoleScreen extends StatefulWidget {
  const DeviceRoleScreen({super.key});

  @override
  State<DeviceRoleScreen> createState() => _DeviceRoleScreenState();
}

class _DeviceRoleScreenState extends State<DeviceRoleScreen> {
  bool _busy = false;

  Future<void> _choose(DeviceRole role) async {
    if (_busy) return;
    setState(() => _busy = true);
    try {
      await context.read<SessionState>().setDeviceRole(role);
    } finally {
      // The router rebuilds on notify; if it didn't (storage hiccup),
      // release the buttons rather than stranding the caregiver here.
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Theme(
      data: OneVozTheme.childTheme(),
      child: Scaffold(
        body: SafeArea(
          child: Center(
            child: SingleChildScrollView(
              padding: const EdgeInsets.symmetric(
                horizontal: 24,
                vertical: 48,
              ),
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 560),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    const WaveformMotif(
                      barCount: 7,
                      height: 44,
                      barWidth: 7,
                      gap: 6,
                      color: OneVozColors.tealDeep,
                    ),
                    const SizedBox(height: 16),
                    Text(
                      'Who is this device for?',
                      style: const TextStyle(
                        fontSize: 26,
                        fontWeight: FontWeight.w800,
                      ),
                      textAlign: TextAlign.center,
                    ),
                    const SizedBox(height: 8),
                    Text(
                      'This sets up ${AppConfig.appDisplayName} on this '
                      'device. You can switch later with your account '
                      'password.',
                      style: TextStyle(
                        fontSize: 15,
                        color: scheme.onSurfaceVariant,
                      ),
                      textAlign: TextAlign.center,
                    ),
                    const SizedBox(height: 28),
                    _roleCard(
                      context,
                      icon: Icons.record_voice_over,
                      title: 'Communicator',
                      body:
                          'This device is the voice — for the person using '
                          'the communication boards. Boards only; no '
                          'caregiver screens appear here at all.',
                      onTap: _busy ? null : () => _choose(DeviceRole.communicator),
                    ),
                    const SizedBox(height: 16),
                    _roleCard(
                      context,
                      icon: Icons.family_restroom,
                      title: 'Caregiver',
                      body:
                          'This device manages the family — profiles, '
                          'devices, safe zones, alerts, and controls in '
                          'the Caregiver Portal.',
                      onTap: _busy ? null : () => _choose(DeviceRole.caregiver),
                    ),
                    if (_busy) ...[
                      const SizedBox(height: 24),
                      const Center(child: CircularProgressIndicator()),
                    ],
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _roleCard(
    BuildContext context, {
    required IconData icon,
    required String title,
    required String body,
    required VoidCallback? onTap,
  }) {
    final scheme = Theme.of(context).colorScheme;
    return Material(
      color: scheme.surface,
      borderRadius: BorderRadius.circular(20),
      elevation: 2,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(20),
        child: Padding(
          padding: const EdgeInsets.all(20),
          child: Row(
            children: [
              Container(
                width: 64,
                height: 64,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: scheme.primaryContainer,
                ),
                child: Icon(icon, size: 34, color: scheme.primary),
              ),
              const SizedBox(width: 16),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      title,
                      style: const TextStyle(
                        fontSize: 20,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      body,
                      style: TextStyle(
                        fontSize: 14,
                        color: scheme.onSurfaceVariant,
                      ),
                    ),
                  ],
                ),
              ),
              Icon(
                Icons.arrow_forward_ios,
                color: scheme.onSurfaceVariant,
              ),
            ],
          ),
        ),
      ),
    );
  }
}
