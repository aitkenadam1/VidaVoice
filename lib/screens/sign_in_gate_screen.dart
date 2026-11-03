import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../app_config.dart';
import '../state/session_state.dart';
import '../widgets/proxy_account_form.dart';

/// Blocking sign-in gate: the app — boards, profiles, settings — is only
/// usable with a caregiver session. Shown when boot restores no session
/// token. Offline, the form surfaces its unreachable error, so the
/// caregiver knows to connect before signing in.
class SignInGateScreen extends StatelessWidget {
  const SignInGateScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Scaffold(
      body: SafeArea(
        child: Center(
          child: SingleChildScrollView(
            padding: const EdgeInsets.symmetric(horizontal: 32, vertical: 48),
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 440),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  if (context.watch<SessionState>().accountDeletedNotice
                      case final notice?) ...[
                    Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 16,
                        vertical: 12,
                      ),
                      decoration: BoxDecoration(
                        color: scheme.primaryContainer,
                        borderRadius: BorderRadius.circular(12),
                      ),
                      child: Row(
                        children: [
                          Icon(
                            Icons.check_circle_outline,
                            color: scheme.onPrimaryContainer,
                          ),
                          const SizedBox(width: 10),
                          Expanded(
                            child: Text(
                              notice,
                              style: TextStyle(
                                color: scheme.onPrimaryContainer,
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(height: 20),
                  ],
                  Icon(Icons.lock_outline, size: 72, color: scheme.primary),
                  const SizedBox(height: 16),
                  Text(
                    'Sign in to ${AppConfig.appDisplayName}',
                    style: const TextStyle(
                      fontSize: 24,
                      fontWeight: FontWeight.bold,
                    ),
                    textAlign: TextAlign.center,
                  ),
                  const SizedBox(height: 8),
                  Text(
                    'Your family\u2019s profiles and boards are protected '
                    'by your caregiver account. Connect to the internet '
                    'to sign in.',
                    style: TextStyle(
                      fontSize: 15,
                      color: scheme.onSurfaceVariant,
                    ),
                    textAlign: TextAlign.center,
                  ),
                  const SizedBox(height: 24),
                  const ProxyAccountForm(),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}
