import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../services/device_role_service.dart';
import '../../services/proxy_client.dart';
import '../../state/session_state.dart';
import '../../widgets/mode_switch_gate.dart';
import 'team_section.dart';

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
              content: Text('Switched to communicator mode — boards only.'),
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

  /// Account deletion: the confirm dialog verifies the password with
  /// the server and performs the deletion; only when it reports success
  /// do we tear the local session down (finishAccountDeletion), which
  /// signs this device out and lands on the role question / sign-in
  /// gate with a one-shot "account deleted" banner.
  Future<void> _deleteAccount(BuildContext context) async {
    final session = context.read<SessionState>();
    final deleted = await showDialog<bool>(
      context: context,
      barrierDismissible: false,
      builder: (_) => DeleteAccountDialog(session: session),
    );
    if (deleted == true) {
      await session.finishAccountDeletion();
    }
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
                  style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
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
                if (session.inJoinedFamily) ...[
                  const SizedBox(height: 4),
                  const Text(
                    'You are currently in a family you joined as a team '
                    'member. Switch back to your own family below.',
                    style: TextStyle(fontSize: 12),
                  ),
                ],
              ],
            ),
          ),
        ),
        const SizedBox(height: 12),
        const FamiliesCard(),
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
                title: Text('Sign out', style: TextStyle(color: scheme.error)),
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
                  'nonprofit. Every dollar helps advance our mission. '
                  'Give what you can — every gift keeps it free for the '
                  'next family.',
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
        const SizedBox(height: 12),
        Card(
          margin: EdgeInsets.zero,
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Icon(
                      Icons.warning_amber_outlined,
                      size: 20,
                      color: scheme.error,
                    ),
                    const SizedBox(width: 8),
                    Text(
                      'Delete account',
                      style: TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.bold,
                        color: scheme.error,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 8),
                Text(
                  session.inJoinedFamily
                      ? 'Deleting your account permanently removes you '
                            'from OneVoz: your sign-in, your access to '
                            'every family you joined, and your own '
                            'family\u2019s data are deleted. This '
                            'family\u2019s data belongs to its owner and '
                            'is not deleted. This cannot be undone.'
                      : 'Deleting your account permanently deletes your '
                            'family\u2019s OneVoz data for everyone in '
                            'the family \u2014 boards, profiles, goals, '
                            'safe zones, and team access \u2014 and '
                            'removes your account. This cannot be undone.',
                  style: TextStyle(
                    fontSize: 14,
                    color: scheme.onSurfaceVariant,
                  ),
                ),
                const SizedBox(height: 12),
                OutlinedButton.icon(
                  icon: const Icon(Icons.delete_forever_outlined),
                  label: const Text('Delete account'),
                  style: OutlinedButton.styleFrom(
                    foregroundColor: scheme.error,
                    side: BorderSide(color: scheme.error),
                  ),
                  onPressed: () => _deleteAccount(context),
                ),
              ],
            ),
          ),
        ),
      ],
    );
  }
}

/// The irreversible-action gate for account deletion: the caregiver
/// must re-enter the account password (verified server-side — a wrong
/// password deletes nothing and says so) AND type DELETE before the
/// destructive button arms. Once the server confirms, the dialog
/// cannot be backed out of; its Done button hands back to the Account
/// tab, which tears the local session down.
class DeleteAccountDialog extends StatefulWidget {
  const DeleteAccountDialog({super.key, required this.session});

  final SessionState session;

  @override
  State<DeleteAccountDialog> createState() => _DeleteAccountDialogState();
}

class _DeleteAccountDialogState extends State<DeleteAccountDialog> {
  final _passwordCtrl = TextEditingController();
  final _confirmCtrl = TextEditingController();
  bool _busy = false;
  bool _deleted = false;
  bool _obscured = true;
  String? _error;

  @override
  void dispose() {
    _passwordCtrl.dispose();
    _confirmCtrl.dispose();
    super.dispose();
  }

  bool get _armed =>
      !_busy &&
      !_deleted &&
      _passwordCtrl.text.isNotEmpty &&
      _confirmCtrl.text.trim() == 'DELETE';

  String _friendlyError(ProxyException e) {
    switch (e.code) {
      case 'invalid_password':
        return 'That password is incorrect. Nothing was deleted.';
      case 'rate_limited':
        return 'Too many incorrect attempts. Please wait a while and '
            'try again. Nothing was deleted.';
      case 'unreachable':
        return 'Couldn\u2019t reach OneVoz. Deleting your account needs '
            'an internet connection. Nothing was deleted.';
      default:
        return '${e.message} Nothing was deleted.';
    }
  }

  Future<void> _submit() async {
    if (!_armed) return;
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      await widget.session.deleteAccount(credential: _passwordCtrl.text);
      if (mounted) {
        setState(() {
          _busy = false;
          _deleted = true;
        });
      }
    } on ProxyException catch (e) {
      // A 404 means a previous attempt already erased the account
      // (e.g. its response was lost) — that IS the desired end state.
      if (e.code == 'account_not_found' || e.statusCode == 404) {
        if (mounted) {
          setState(() {
            _busy = false;
            _deleted = true;
          });
        }
        return;
      }
      if (mounted) {
        setState(() {
          _busy = false;
          _error = _friendlyError(e);
          _passwordCtrl.clear();
        });
      }
    } catch (_) {
      if (mounted) {
        setState(() {
          _busy = false;
          _error = 'Something went wrong. Nothing was deleted.';
          _passwordCtrl.clear();
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final joined = widget.session.inJoinedFamily;
    return PopScope(
      canPop: !_deleted,
      child: AlertDialog(
        title: Text(_deleted ? 'Account deleted' : 'Delete your account?'),
        content: _deleted
            ? const Text(
                'Your account has been deleted. This device is being '
                'signed out \u2014 the sign-in screen is next.',
              )
            : SingleChildScrollView(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      joined
                          ? 'This permanently removes your account, your '
                                'access to every family you joined, and '
                                'your own family\u2019s OneVoz data. This '
                                'family\u2019s data is not deleted. This '
                                'cannot be undone.'
                          : 'This permanently deletes your account and '
                                'your family\u2019s OneVoz data for '
                                'everyone in the family. This cannot be '
                                'undone.',
                    ),
                    const SizedBox(height: 16),
                    TextField(
                      controller: _passwordCtrl,
                      obscureText: _obscured,
                      autocorrect: false,
                      enableSuggestions: false,
                      onChanged: (_) => setState(() {}),
                      decoration: InputDecoration(
                        labelText: 'Your account password',
                        border: const OutlineInputBorder(),
                        suffixIcon: IconButton(
                          icon: Icon(
                            _obscured
                                ? Icons.visibility_outlined
                                : Icons.visibility_off_outlined,
                          ),
                          onPressed: () =>
                              setState(() => _obscured = !_obscured),
                        ),
                      ),
                    ),
                    const SizedBox(height: 12),
                    TextField(
                      controller: _confirmCtrl,
                      autocorrect: false,
                      enableSuggestions: false,
                      textCapitalization: TextCapitalization.characters,
                      onChanged: (_) => setState(() {}),
                      decoration: const InputDecoration(
                        labelText: 'Type DELETE to confirm',
                        border: OutlineInputBorder(),
                      ),
                    ),
                    if (_error != null) ...[
                      const SizedBox(height: 12),
                      Text(
                        _error!,
                        style: TextStyle(color: scheme.error, fontSize: 13),
                      ),
                    ],
                  ],
                ),
              ),
        actions: _deleted
            ? [
                FilledButton(
                  onPressed: () => Navigator.of(context).pop(true),
                  child: const Text('Done'),
                ),
              ]
            : [
                TextButton(
                  onPressed: _busy
                      ? null
                      : () => Navigator.of(context).pop(false),
                  child: const Text('Cancel'),
                ),
                FilledButton(
                  onPressed: _armed ? _submit : null,
                  style: FilledButton.styleFrom(
                    backgroundColor: scheme.error,
                    foregroundColor: scheme.onError,
                  ),
                  child: Text(_busy ? 'Deleting\u2026' : 'Delete my account'),
                ),
              ],
      ),
    );
  }
}
