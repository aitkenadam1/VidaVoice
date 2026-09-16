import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../services/proxy_client.dart';
import '../state/session_state.dart';

/// The gate in front of the caregiver hub.
///
/// The hub holds every parental control — location sharing, calling &
/// safety, devices, dashboard editing — so it must not open from a tap a
/// child can make. This gate asks for the device-local caregiver PIN
/// (created on first entry). It is a fast local check, not the account
/// password; the account password remains the root credential and is
/// what resets a forgotten PIN.
///
/// States: checking → create → confirm → (unlocked), or
/// checking → verify → (unlocked), with a forgot-password escape hatch
/// from verify.
class CaregiverPinGate extends StatefulWidget {
  const CaregiverPinGate({super.key, required this.onUnlocked});

  final VoidCallback onUnlocked;

  @override
  State<CaregiverPinGate> createState() => _CaregiverPinGateState();
}

enum _GateMode { checking, create, confirm, verify, forgot }

class _CaregiverPinGateState extends State<CaregiverPinGate> {
  _GateMode _mode = _GateMode.checking;
  String _entry = '';
  String _firstEntry = '';
  String? _error;
  bool _busy = false;

  final _identifierCtrl = TextEditingController();
  final _passwordCtrl = TextEditingController();

  @override
  void initState() {
    super.initState();
    _checkExisting();
  }

  @override
  void dispose() {
    _identifierCtrl.dispose();
    _passwordCtrl.dispose();
    super.dispose();
  }

  Future<void> _checkExisting() async {
    final has =
        await context.read<SessionState>().caregiverPin.hasPin();
    if (!mounted) return;
    setState(() {
      _mode = has ? _GateMode.verify : _GateMode.create;
    });
  }

  void _onDigit(String d) {
    if (_busy || _entry.length >= 4) return;
    setState(() {
      _error = null;
      _entry += d;
    });
    if (_entry.length == 4) {
      // Let the fourth dot paint before acting.
      Future.delayed(const Duration(milliseconds: 120), _submitEntry);
    }
  }

  void _onBackspace() {
    if (_busy || _entry.isEmpty) return;
    setState(() {
      _error = null;
      _entry = _entry.substring(0, _entry.length - 1);
    });
  }

  Future<void> _submitEntry() async {
    if (!mounted) return;
    final session = context.read<SessionState>();
    final entry = _entry;
    switch (_mode) {
      case _GateMode.create:
        setState(() {
          _firstEntry = entry;
          _entry = '';
          _mode = _GateMode.confirm;
        });
      case _GateMode.confirm:
        if (entry == _firstEntry) {
          setState(() => _busy = true);
          try {
            await session.caregiverPin.setPin(entry);
          } finally {
            if (mounted) setState(() => _busy = false);
          }
          widget.onUnlocked();
        } else {
          setState(() {
            _error = 'Those didn\u2019t match. Try again.';
            _entry = '';
            _firstEntry = '';
            _mode = _GateMode.create;
          });
        }
      case _GateMode.verify:
        setState(() => _busy = true);
        bool ok = false;
        try {
          ok = await session.caregiverPin.verify(entry);
        } finally {
          if (mounted) setState(() => _busy = false);
        }
        if (ok) {
          widget.onUnlocked();
        } else if (mounted) {
          setState(() {
            _error = 'Wrong PIN — try again.';
            _entry = '';
          });
        }
      case _GateMode.checking:
      case _GateMode.forgot:
        break;
    }
  }

  /// Forgotten PIN: the caregiver proves who they are with the account
  /// password (verified live against the proxy), which clears the PIN so
  /// a new one can be created. The returned token is discarded — this is
  /// a credential check, not a session change.
  Future<void> _resetWithPassword() async {
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
      await session.proxy.login(identifier: identifier, password: password);
      await session.caregiverPin.clearPin();
      if (!mounted) return;
      setState(() {
        _mode = _GateMode.create;
        _entry = '';
        _firstEntry = '';
        _busy = false;
        _error = null;
      });
    } on ProxyException catch (e) {
      if (!mounted) return;
      setState(() {
        _busy = false;
        _error = e.code == 'unreachable'
            ? 'Connect to the internet to reset your PIN, then try again.'
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
    switch (_mode) {
      case _GateMode.checking:
        return const Center(child: CircularProgressIndicator());
      case _GateMode.forgot:
        return _forgotBody(context);
      case _GateMode.create:
      case _GateMode.confirm:
      case _GateMode.verify:
        return _pinBody(context);
    }
  }

  String get _title => switch (_mode) {
    _GateMode.create => 'Create a caregiver PIN',
    _GateMode.confirm => 'Confirm your PIN',
    _GateMode.verify => 'Caregiver access',
    _GateMode.checking => '',
    _GateMode.forgot => '',
  };

  String get _subtitle => switch (_mode) {
    _GateMode.create =>
      'This 4-digit PIN opens caregiver controls on this device — '
      'location, calling & safety, devices. Only share it with other '
      'caregivers.',
    _GateMode.confirm => 'Enter it once more to make sure it\u2019s right.',
    _GateMode.verify => 'Enter your 4-digit caregiver PIN.',
    _GateMode.checking => '',
    _GateMode.forgot => '',
  };

  Widget _pinBody(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return SingleChildScrollView(
      padding: const EdgeInsets.all(24),
      child: Column(
        children: [
          const SizedBox(height: 16),
          Icon(
            Icons.family_restroom,
            size: 56,
            color: scheme.primary,
          ),
          const SizedBox(height: 16),
          Text(
            _title,
            style: const TextStyle(
              fontSize: 22,
              fontWeight: FontWeight.bold,
            ),
          ),
          const SizedBox(height: 8),
          Text(
            _subtitle,
            textAlign: TextAlign.center,
            style: TextStyle(fontSize: 14, color: Colors.grey.shade700),
          ),
          const SizedBox(height: 24),
          Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              for (var i = 0; i < 4; i++)
                Container(
                  width: 22,
                  height: 22,
                  margin: const EdgeInsets.symmetric(horizontal: 8),
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    color: i < _entry.length
                        ? scheme.primary
                        : Colors.grey.shade300,
                  ),
                ),
            ],
          ),
          if (_error != null) ...[
            const SizedBox(height: 12),
            Text(
              _error!,
              style: TextStyle(color: scheme.error, fontSize: 14),
              textAlign: TextAlign.center,
            ),
          ],
          const SizedBox(height: 16),
          _pinPad(context),
          if (_mode == _GateMode.verify) ...[
            const SizedBox(height: 8),
            TextButton(
              onPressed: _busy
                  ? null
                  : () => setState(() {
                      _mode = _GateMode.forgot;
                      _error = null;
                    }),
              child: const Text('Forgot PIN?'),
            ),
          ],
        ],
      ),
    );
  }

  Widget _pinPad(BuildContext context) {
    Widget key(String label, {VoidCallback? onTap, bool subtle = false}) {
      return SizedBox(
        width: 76,
        height: 64,
        child: TextButton(
          onPressed: _busy ? null : onTap,
          child: label.isEmpty
              ? const SizedBox.shrink()
              : Text(
                  label,
                  style: TextStyle(
                    fontSize: 26,
                    color: subtle
                        ? Colors.grey.shade600
                        : Theme.of(context).colorScheme.onSurface,
                  ),
                ),
        ),
      );
    }

    return Column(
      children: [
        for (final row in const [
          ['1', '2', '3'],
          ['4', '5', '6'],
          ['7', '8', '9'],
        ])
          Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [for (final d in row) key(d, onTap: () => _onDigit(d))],
          ),
        Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            key(''),
            key('0', onTap: () => _onDigit('0')),
            key(
              '⌫',
              subtle: true,
              onTap: _onBackspace,
            ),
          ],
        ),
      ],
    );
  }

  Widget _forgotBody(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return SingleChildScrollView(
      padding: const EdgeInsets.all(24),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          const SizedBox(height: 16),
          const Text(
            'Reset your PIN',
            style: TextStyle(fontSize: 22, fontWeight: FontWeight.bold),
            textAlign: TextAlign.center,
          ),
          const SizedBox(height: 8),
          Text(
            'Enter your OneVoz caregiver account email/username and '
            'password. This needs an internet connection — the password '
            'is checked against your account, and nothing is stored.',
            textAlign: TextAlign.center,
            style: TextStyle(fontSize: 14, color: Colors.grey.shade700),
          ),
          const SizedBox(height: 24),
          TextField(
            controller: _identifierCtrl,
            enabled: !_busy,
            textInputAction: TextInputAction.next,
            decoration: const InputDecoration(
              labelText: 'Email or username',
              border: OutlineInputBorder(),
            ),
          ),
          const SizedBox(height: 12),
          TextField(
            controller: _passwordCtrl,
            enabled: !_busy,
            obscureText: true,
            textInputAction: TextInputAction.done,
            onSubmitted: (_) => _resetWithPassword(),
            decoration: const InputDecoration(
              labelText: 'Account password',
              border: OutlineInputBorder(),
            ),
          ),
          if (_error != null) ...[
            const SizedBox(height: 12),
            Text(
              _error!,
              style: TextStyle(color: scheme.error, fontSize: 14),
              textAlign: TextAlign.center,
            ),
          ],
          const SizedBox(height: 16),
          FilledButton(
            onPressed: _busy ? null : _resetWithPassword,
            child: _busy
                ? const SizedBox(
                    width: 20,
                    height: 20,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                : const Text('Reset PIN'),
          ),
          TextButton(
            onPressed: _busy
                ? null
                : () => setState(() {
                    _mode = _GateMode.verify;
                    _error = null;
                  }),
            child: const Text('Back to PIN entry'),
          ),
        ],
      ),
    );
  }
}
