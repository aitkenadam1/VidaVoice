import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../services/proxy_client.dart';
import '../state/session_state.dart';

/// Caregiver-readable text for the proxy's machine-readable error codes.
String proxyErrorMessage(ProxyException e) {
  switch (e.code) {
    case 'unreachable':
      return 'Couldn\u2019t reach the VoiceSimple service. Check your '
          'connection and try again.';
    case 'invalid_email':
      return 'That email doesn\u2019t look right \u2014 check it and try again.';
    case 'invalid_username':
      return 'Usernames are 3\u201332 characters: lowercase letters, numbers, '
          'dots, underscores, and dashes.';
    case 'weak_password':
      return 'That password is too weak \u2014 use at least 10 characters.';
    case 'email_taken':
      return 'That email is already registered \u2014 try logging in.';
    case 'username_taken':
      return 'That username is taken \u2014 try another one.';
    case 'already_registered':
      return 'An account is already registered here \u2014 try logging in.';
    case 'invalid_request':
      return 'Something\u2019s missing \u2014 check the form and try again.';
    case 'invalid_credentials':
    case 'unauthorized':
      return 'That email/username and password didn\u2019t match. Try again.';
    case 'rate_limited':
      return 'Too many attempts \u2014 wait a bit and try again.';
    case 'DEVICE_LIMIT_REACHED':
      return e.message;
    default:
      return e.message.isNotEmpty
          ? e.message
          : 'Something went wrong. Please try again.';
  }
}

/// Mirrors the server's account rules so bad input is caught before a
/// network call: email format, username 3-32 chars of [a-z0-9._-],
/// password 10-128 chars.
bool isValidProxyEmail(String v) =>
    RegExp(r'^[^@\s]+@[^@\s]+\.[^@\s]+$').hasMatch(v.trim());

bool isValidProxyUsername(String v) =>
    RegExp(r'^[a-z0-9._-]{3,32}$').hasMatch(v.trim());

bool isValidProxyPassword(String v) => v.length >= 10 && v.length <= 128;

/// The caregiver account form, shared by onboarding and the voice
/// settings card. Signup and login in one place: the toggle switches
/// modes, server error codes are translated to plain language, and an
/// unreachable proxy offers the offline path instead of a dead end.
///
/// When the session is already signed in, shows a compact "signed in"
/// state instead of the form.
class ProxyAccountForm extends StatefulWidget {
  const ProxyAccountForm({
    super.key,
    this.showDeferButton = false,
    this.onSignedIn,
    this.onDeferred,
  });

  /// Show the prominent "Continue with on-device voices for now" button
  /// (onboarding). When false (voice settings), an unreachable service is
  /// just an error message — the board keeps working either way.
  final bool showDeferButton;

  /// Called after a successful sign-up or sign-in.
  final VoidCallback? onSignedIn;

  /// Called when the caregiver chooses to continue without an account.
  final VoidCallback? onDeferred;

  @override
  State<ProxyAccountForm> createState() => _ProxyAccountFormState();
}

class _ProxyAccountFormState extends State<ProxyAccountForm> {
  bool _loginMode = false;
  final _email = TextEditingController();
  final _username = TextEditingController();
  final _identifier = TextEditingController();
  final _password = TextEditingController();
  bool _obscure = true;
  bool _busy = false;
  String? _error;
  bool _unreachable = false;

  @override
  void dispose() {
    _email.dispose();
    _username.dispose();
    _identifier.dispose();
    _password.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    final session = context.read<SessionState>();
    final email = _email.text.trim();
    final username = _username.text.trim();
    final identifier = _identifier.text.trim();
    final password = _password.text;

    String? localError;
    if (_loginMode) {
      if (identifier.isEmpty) {
        localError = 'Enter your email or username.';
      } else if (!isValidProxyPassword(password)) {
        localError = 'Passwords are at least 10 characters.';
      }
    } else {
      if (!isValidProxyEmail(email)) {
        localError = 'Enter a valid email address.';
      } else if (!isValidProxyUsername(username)) {
        localError =
            'Usernames are 3\u201332 characters: lowercase letters, numbers, '
            'dots, underscores, and dashes.';
      } else if (!isValidProxyPassword(password)) {
        localError = 'Use a password of at least 10 characters.';
      }
    }
    if (localError != null) {
      setState(() {
        _error = localError;
        _unreachable = false;
      });
      return;
    }

    setState(() {
      _busy = true;
      _error = null;
      _unreachable = false;
    });
    try {
      if (_loginMode) {
        await session.signIn(identifier: identifier, password: password);
      } else {
        await session.signUp(
          email: email,
          username: username,
          password: password,
        );
      }
    } on ProxyException catch (e) {
      if (!mounted) return;
      setState(() {
        _busy = false;
        _error = proxyErrorMessage(e);
        _unreachable = e.code == 'unreachable';
      });
      return;
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _busy = false;
        _error = 'Something went wrong. Please try again.';
        _unreachable = false;
      });
      return;
    }
    if (!mounted) return;
    setState(() => _busy = false);
    widget.onSignedIn?.call();
  }

  Future<void> _defer() async {
    final session = context.read<SessionState>();
    await session.deferAccount();
    widget.onDeferred?.call();
  }

  Future<void> _signOut() async {
    await context.read<SessionState>().signOut();
  }

  @override
  Widget build(BuildContext context) {
    final session = context.watch<SessionState>();
    if (session.proxySignedIn) {
      return Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          const Row(
            children: [
              Icon(Icons.check_circle, color: Colors.green, size: 20),
              SizedBox(width: 8),
              Expanded(
                child: Text(
                  'Signed in \u2014 cloud voices are ready.',
                  style: TextStyle(fontSize: 14, fontWeight: FontWeight.w600),
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          Row(
            children: [
              if (widget.onSignedIn != null)
                Expanded(
                  child: FilledButton(
                    onPressed: widget.onSignedIn,
                    child: const Text('Continue'),
                  ),
                ),
              if (widget.onSignedIn != null) const SizedBox(width: 8),
              Expanded(
                child: OutlinedButton(
                  onPressed: _signOut,
                  child: const Text('Sign out'),
                ),
              ),
            ],
          ),
        ],
      );
    }

    final scheme = Theme.of(context).colorScheme;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        SegmentedButton<bool>(
          segments: const [
            ButtonSegment(value: false, label: Text('Sign up')),
            ButtonSegment(value: true, label: Text('Log in')),
          ],
          selected: {_loginMode},
          onSelectionChanged: _busy
              ? null
              : (s) => setState(() {
                  _loginMode = s.first;
                  _error = null;
                  _unreachable = false;
                }),
        ),
        const SizedBox(height: 12),
        if (_loginMode)
          TextField(
            controller: _identifier,
            keyboardType: TextInputType.emailAddress,
            autocorrect: false,
            enableSuggestions: false,
            decoration: const InputDecoration(
              labelText: 'Email or username',
              border: OutlineInputBorder(),
              prefixIcon: Icon(Icons.person_outline),
            ),
            onSubmitted: (_) => _submit(),
          )
        else ...[
          TextField(
            controller: _email,
            keyboardType: TextInputType.emailAddress,
            autocorrect: false,
            enableSuggestions: false,
            decoration: const InputDecoration(
              labelText: 'Email',
              border: OutlineInputBorder(),
              prefixIcon: Icon(Icons.email_outlined),
            ),
            onSubmitted: (_) => _submit(),
          ),
          const SizedBox(height: 12),
          TextField(
            controller: _username,
            autocorrect: false,
            enableSuggestions: false,
            decoration: const InputDecoration(
              labelText: 'Username',
              helperText: '3\u201332 characters: a\u2013z, 0\u20139, . _ -',
              border: OutlineInputBorder(),
              prefixIcon: Icon(Icons.badge_outlined),
            ),
            onSubmitted: (_) => _submit(),
          ),
        ],
        const SizedBox(height: 12),
        TextField(
          controller: _password,
          obscureText: _obscure,
          enableSuggestions: false,
          autocorrect: false,
          decoration: InputDecoration(
            labelText: 'Password',
            helperText: _loginMode ? null : 'At least 10 characters',
            border: const OutlineInputBorder(),
            prefixIcon: const Icon(Icons.lock_outline),
            suffixIcon: IconButton(
              tooltip: _obscure ? 'Show password' : 'Hide password',
              icon: Icon(
                _obscure
                    ? Icons.visibility_outlined
                    : Icons.visibility_off_outlined,
              ),
              onPressed: () => setState(() => _obscure = !_obscure),
            ),
          ),
          onSubmitted: (_) => _submit(),
        ),
        if (_error != null) ...[
          const SizedBox(height: 8),
          Text(_error!, style: TextStyle(fontSize: 13, color: scheme.error)),
        ],
        const SizedBox(height: 12),
        FilledButton(
          onPressed: _busy ? null : _submit,
          child: Padding(
            padding: const EdgeInsets.symmetric(vertical: 10),
            child: _busy
                ? const SizedBox(
                    width: 20,
                    height: 20,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                : Text(
                    _loginMode ? 'Log in' : 'Create account',
                    style: const TextStyle(fontSize: 16),
                  ),
          ),
        ),
        if (widget.showDeferButton) ...[
          const SizedBox(height: 8),
          OutlinedButton(
            onPressed: _busy ? null : _defer,
            child: const Padding(
              padding: EdgeInsets.symmetric(vertical: 10),
              child: Text(
                'Continue with on-device voices for now',
                style: TextStyle(fontSize: 15),
              ),
            ),
          ),
          if (_unreachable)
            const Padding(
              padding: EdgeInsets.only(top: 8),
              child: Text(
                'You can set up your account later from the caregiver hub. '
                'Everything on the board works offline.',
                style: TextStyle(fontSize: 12),
                textAlign: TextAlign.center,
              ),
            ),
        ],
      ],
    );
  }
}
