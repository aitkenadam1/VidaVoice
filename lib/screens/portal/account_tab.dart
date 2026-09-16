import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../services/device_role_service.dart';
import '../../state/session_state.dart';
import '../../widgets/coming_soon_card.dart';
import '../../widgets/mode_switch_gate.dart';

/// Portal "Account" tab: family account info, mode switch, sign out.

// ------------------------------------------------------------------- account

class PortalAccountTab extends StatelessWidget {
  const PortalAccountTab({super.key});

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
        const ComingSoonCard(
          title: 'Voice quota & subscription',
          body:
              'Cloud-voice usage, device licenses, and subscription '
              'management are coming to this tab.',
          icon: Icons.manage_accounts_outlined,
        ),
      ],
    );
  }
}
