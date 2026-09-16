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
/// required); on success the router rebuilds into the Caregiver Portal.
Future<void> showCaregiverEntrySheet(BuildContext context) {
  return showModalBottomSheet(
    context: context,
    isScrollControlled: true,
    builder: (_) => ModeSwitchGate(
      targetRole: DeviceRole.caregiver,
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
  });

  /// The role the device switches to once the password verifies.
  final DeviceRole targetRole;

  /// Called after the password verifies and the role is persisted. The
  /// host pops/navigates from here.
  final VoidCallback onVerified;

  @override
  State<ModeSwitchGate> createState() => _ModeSwitchGateState();
}

class _ModeSwitchGateState extends State<ModeSwitchGate> {
  final _identifierCtrl = TextEditingController();
  final _passwordCtrl = TextEditingController();
  bool _busy = false;
  String? _error;
  bool _obscured = true;

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

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final target = widget.targetRole == DeviceRole.caregiver
        ? 'caregiver mode'
        : 'communicator mode';
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
}
