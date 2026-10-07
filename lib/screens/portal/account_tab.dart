import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../services/device_role_service.dart';
import '../../state/session_state.dart';
import '../../widgets/mode_switch_gate.dart';

/// Portal "Account" tab: family account info, support/donate, mode switch,
/// sign out.

// ------------------------------------------------------------------- account

class PortalAccountTab extends StatelessWidget {
  const PortalAccountTab({super.key, this.donateLauncher});

  /// Opens the VidaCare donation page. Injectable for tests; defaults to
  /// the system browser / new tab.
  final Future<bool> Function(Uri uri)? donateLauncher;

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

  static final Uri _donateUri = Uri.parse(
    'https://vidacarefoundation.org/donate/money',
  );

  static Future<bool> _launchDonatePage(Uri uri) =>
      launchUrl(uri, mode: LaunchMode.externalApplication);

  Future<void> _openDonationPage(BuildContext context) async {
    var ok = false;
    try {
      ok = await (donateLauncher ?? _launchDonatePage)(_donateUri);
    } catch (_) {
      ok = false;
    }
    if (!ok && context.mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text(
            'Couldn\u2019t open the donation page. You can give at '
            'vidacarefoundation.org/donate/money',
          ),
          duration: Duration(seconds: 5),
        ),
      );
    }
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
        Card(
          margin: EdgeInsets.zero,
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Row(
                  children: [
                    Icon(Icons.favorite_outline, size: 20),
                    SizedBox(width: 8),
                    Text(
                      'Support OneVoz',
                      style: TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 8),
                Text(
                  'OneVoz is free for every family, from VidaCare, a '
                  'nonprofit. If it helps your family, give what you can '
                  '(\$5 minimum if you\u2019re able, more if you can). '
                  'Every gift keeps it free for the next family.',
                  style: TextStyle(
                    fontSize: 14,
                    color: scheme.onSurfaceVariant,
                  ),
                ),
                const SizedBox(height: 12),
                FilledButton.icon(
                  icon: const Icon(Icons.volunteer_activism_outlined),
                  label: const Text('Donate'),
                  onPressed: () => _openDonationPage(context),
                ),
              ],
            ),
          ),
        ),
      ],
    );
  }
}
