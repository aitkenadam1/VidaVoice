import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../services/device_role_service.dart';
import '../services/proxy_client.dart';
import '../state/session_state.dart';

/// Opens the discreet caregiver entry point: a bottom sheet with the
/// password gate for switching this device to caregiver mode.
///
/// There is deliberately NO visible affordance for this on communicator
/// boards — no icon, no label. The caregiver long-presses the app title
/// in the board's top bar. A child tapping around finds nothing; the
/// device is never stranded because the caregiver knows the gesture and
/// the account password. The password is verified live (internet
/// required); on success the caregiver chooses between opening the
/// Caregiver Portal and signing this device out — both stay behind the
/// same password gate, so a child can never reach a tappable sign-out.
Future<void> showCaregiverEntrySheet(BuildContext context) {
  return showModalBottomSheet(
    context: context,
    isScrollControlled: true,
    builder: (_) => ModeSwitchGate(
      targetRole: DeviceRole.caregiver,
      offerSignOut: true,
      onVerified: () => Navigator.of(context).pop(),
    ),
  );
}

/// Password gate for switching a device between communicator and
/// caregiver roles.
///
/// The caregiver proves who they are with the OneVoz account password,
/// verified live against the proxy. The returned auth result is
/// discarded — this is a credential check, not a session change (same
/// pattern as the forgotten-PIN reset). The active auth session, sync
/// key, and device registration are never altered.
///
/// Needs an internet connection: without one the password cannot be
/// verified, and the switch is refused honestly instead of guessing.
class ModeSwitchGate extends StatefulWidget {
  const ModeSwitchGate({
    super.key,
    required this.targetRole,
    required this.onVerified,
    this.offerSignOut = false,
  });

  /// The role the device switches to once the password verifies.
  final DeviceRole targetRole;

  /// Called after the password verifies and the role is persisted. The
  /// host pops/navigates from here.
  final VoidCallback onVerified;

  /// When true, a verified password does NOT switch roles immediately:
  /// the caregiver is offered a choice between opening the portal (the
  /// existing behavior) and signing this device out (confirm dialog
  /// first; clears the session AND the device role, so the next launch
  /// asks the role question again). Used only by the discreet
  /// communicator-side entry point, so a child never sees it.
  final bool offerSignOut;

  @override
  State<ModeSwitchGate> createState() => _ModeSwitchGateState();
}

class _ModeSwitchGateState extends State<ModeSwitchGate> {
  final _identifierCtrl = TextEditingController();
  final _passwordCtrl = TextEditingController();
  bool _busy = false;
  String? _error;
  bool _obscured = true;
  bool _choiceShown = false;

  @override
  void dispose() {
    _identifierCtrl.dispose();
    _passwordCtrl.dispose();
    super.dispose();
  }

  Future<void> _verify() async {
    final session = context.read<SessionState>();
    final identifier = _identifierCtrl.text.trim();
    final password = _passwordCtrl.text;
    if (identifier.isEmpty || password.isEmpty) {
      setState(() => _error = 'Enter your email/username and password.');
      return;
    }
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      // Verification login only: the returned token is discarded. This
      // must never call session.signIn — that would re-register the
      // device and re-derive the sync key mid-session.
      await session.proxy.login(identifier: identifier, password: password);
      if (!mounted) return;
      if (widget.offerSignOut) {
        // Communicator-side entry: don't switch yet. The caregiver
        // picks between the portal and signing this device out.
        setState(() {
          _busy = false;
          _choiceShown = true;
        });
        return;
      }
      await session.setDeviceRole(widget.targetRole);
      if (!mounted) return;
      // Release the spinner before handing off: the host usually pops
      // this sheet, but if it doesn't the button must not stay stuck.
      setState(() => _busy = false);
      widget.onVerified();
    } on ProxyException catch (e) {
      if (!mounted) return;
      setState(() {
        _busy = false;
        _error = e.code == 'unreachable'
            ? 'Connect to the internet to switch modes, then try again.'
            : e.message;
      });
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _busy = false;
        _error = 'Something went wrong. Try again.';
      });
    }
  }

  /// Post-verification choice (communicator-side entry only): open the
  /// Caregiver Portal — the previous immediate behavior.
  Future<void> _openPortal() async {
    final session = context.read<SessionState>();
    setState(() => _busy = true);
    try {
      await session.setDeviceRole(widget.targetRole);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
    if (!mounted) return;
    widget.onVerified();
  }

  /// Post-verification choice (communicator-side entry only): sign this
  /// device out. Confirmed first — signOut clears the session AND the
  /// device role, so the next launch asks the role question again.
  Future<void> _signOutDevice() async {
    final confirm = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Sign out this device?'),
        content: const Text(
          'This device will be signed out of the family account. '
          'The next launch asks who the device is for again. '
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
    if (confirm != true || !mounted) return;
    setState(() => _busy = true);
    try {
      await context.read<SessionState>().signOut();
    } finally {
      if (mounted) setState(() => _busy = false);
    }
    // The router now lands on the device-role question (role was
    // cleared); dismiss this sheet so it shows.
    if (mounted) Navigator.of(context).pop();
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final target = widget.targetRole == DeviceRole.caregiver
        ? 'caregiver mode'
        : 'communicator mode';
    if (_choiceShown) return _buildChoice(context, scheme);
    return SingleChildScrollView(
      padding: EdgeInsets.only(
        left: 24,
        right: 24,
        top: 24,
        bottom: 24 + MediaQuery.of(context).viewInsets.bottom,
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Icon(Icons.lock_outline, size: 48, color: scheme.primary),
          const SizedBox(height: 12),
          Text(
            'Switch to $target?',
            style: const TextStyle(fontSize: 20, fontWeight: FontWeight.bold),
            textAlign: TextAlign.center,
          ),
          const SizedBox(height: 8),
          Text(
            'Enter your OneVoz account password to confirm. '
            'This only switches this device — nothing else changes.',
            style: TextStyle(fontSize: 14, color: scheme.onSurfaceVariant),
            textAlign: TextAlign.center,
          ),
          const SizedBox(height: 20),
          TextField(
            controller: _identifierCtrl,
            decoration: const InputDecoration(
              labelText: 'Email or username',
              border: OutlineInputBorder(),
            ),
            keyboardType: TextInputType.emailAddress,
            autocorrect: false,
            textInputAction: TextInputAction.next,
            enabled: !_busy,
          ),
          const SizedBox(height: 12),
          TextField(
            controller: _passwordCtrl,
            decoration: InputDecoration(
              labelText: 'Account password',
              border: const OutlineInputBorder(),
              suffixIcon: IconButton(
                tooltip: _obscured ? 'Show password' : 'Hide password',
                icon: Icon(
                  _obscured ? Icons.visibility : Icons.visibility_off,
                ),
                onPressed: () =>
                    setState(() => _obscured = !_obscured),
              ),
            ),
            obscureText: _obscured,
            textInputAction: TextInputAction.done,
            onSubmitted: (_) => _busy ? null : _verify(),
            enabled: !_busy,
          ),
          if (_error != null) ...[
            const SizedBox(height: 12),
            Text(
              _error!,
              style: TextStyle(color: scheme.error, fontSize: 14),
              textAlign: TextAlign.center,
            ),
          ],
          const SizedBox(height: 20),
          FilledButton(
            onPressed: _busy ? null : _verify,
            style: FilledButton.styleFrom(
              minimumSize: const Size.fromHeight(56),
            ),
            child: _busy
                ? const SizedBox(
                    width: 22,
                    height: 22,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                : Text(
                    'Switch to $target',
                    style: const TextStyle(fontSize: 17),
                  ),
          ),
        ],
      ),
    );
  }
  /// What the caregiver sees after the password verifies on the
  /// communicator-side entry: portal or sign-out. Both stay behind the
  /// password gate — no new visible affordance on the boards.
  Widget _buildChoice(BuildContext context, ColorScheme scheme) {
    return SingleChildScrollView(
      padding: const EdgeInsets.fromLTRB(24, 24, 24, 24),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Icon(Icons.verified_user_outlined, size: 48, color: scheme.primary),
          const SizedBox(height: 12),
          const Text(
            'Password confirmed',
            style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold),
            textAlign: TextAlign.center,
          ),
          const SizedBox(height: 8),
          Text(
            'What would you like to do with this device?',
            style: TextStyle(fontSize: 14, color: scheme.onSurfaceVariant),
            textAlign: TextAlign.center,
          ),
          const SizedBox(height: 20),
          FilledButton.icon(
            onPressed: _busy ? null : _openPortal,
            icon: const Icon(Icons.family_restroom),
            label: const Text('Open Caregiver Portal'),
            style: FilledButton.styleFrom(
              minimumSize: const Size.fromHeight(56),
            ),
          ),
          const SizedBox(height: 12),
          OutlinedButton.icon(
            onPressed: _busy ? null : _signOutDevice,
            icon: const Icon(Icons.logout),
            label: const Text('Sign out this device'),
            style: OutlinedButton.styleFrom(
              minimumSize: const Size.fromHeight(56),
              foregroundColor: scheme.error,
            ),
          ),
          const SizedBox(height: 4),
          TextButton(
            onPressed: _busy ? null : () => Navigator.of(context).pop(),
            child: const Text('Not now'),
          ),
          if (_busy) ...[
            const SizedBox(height: 12),
            const Center(child: CircularProgressIndicator()),
          ],
        ],
      ),
    );
  }
}
