import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import 'app_config.dart';
import 'screens/boot_screen.dart';
import 'screens/build_board_screen.dart';
import 'screens/device_license_blocked_screen.dart';
import 'screens/home_board_screen.dart';
import 'screens/onboarding_screen.dart';
import 'screens/sign_in_gate_screen.dart';
import 'screens/type_board_screen.dart';
import 'services/profile_service.dart';
import 'state/session_state.dart';

void main() {
  final session = SessionState();
  runApp(OneVozApp(session: session));
  // Async on purpose: the UI reacts to BootStatus changes.
  session.boot();
}

/// Routes the home experience by the active profile's communication mode
/// (Phase 4 of the modes plan): Build gets the phrase-strip surface, Type
/// gets the keyboard + prediction surface, and Tap (or a missing profile)
/// keeps the classic board.
/// Home screen for the active profile's communication mode.
///
/// Composition state is per profile: never leak an unsent build strip or a
/// typed-but-never-spoken draft into another profile's session. The screens
/// are keyed by the active profile id so a profile switch rebuilds with
/// fresh local state (a reused [TextEditingController] would otherwise keep
/// the previous profile's draft in the field).
Widget homeScreenFor(SessionState session) {
  final profileId = session.profiles.active?.id;
  return switch (session.profiles.active?.communicationMode) {
    CommunicationMode.build => BuildBoardScreen(
      key: ValueKey('build-$profileId'),
    ),
    CommunicationMode.type => TypeBoardScreen(key: ValueKey('type-$profileId')),
    _ => HomeBoardScreen(key: ValueKey('tap-$profileId')),
  };
}

class OneVozApp extends StatelessWidget {
  const OneVozApp({super.key, required this.session});

  final SessionState session;

  @override
  Widget build(BuildContext context) {
    return ChangeNotifierProvider.value(
      value: session,
      child: MaterialApp(
        title: AppConfig.appDisplayName,
        debugShowCheckedModeBanner: false,
        theme: ThemeData(colorSchemeSeed: Colors.teal, useMaterial3: true),
        home: Consumer<SessionState>(
          builder: (context, s, _) {
            switch (s.status) {
              case BootStatus.loading:
                return const LoadingScreen();
              case BootStatus.error:
                return ErrorScreen(
                  message: s.bootError,
                  onRetry: () => s.boot(),
                );
              case BootStatus.ready:
                // Login gates everything: without a caregiver session the
                // app shows the sign-in gate — never the home board. A
                // device that hit the family device cap stops at the
                // device-license screen until a slot is freed.
                if (!s.onboardingComplete) {
                  return const OnboardingScreen();
                }
                if (!s.proxySignedIn) {
                  return const SignInGateScreen();
                }
                if (s.deviceLicenseBlocked) {
                  return const DeviceLicenseBlockedScreen();
                }
                return homeScreenFor(s);
            }
          },
        ),
      ),
    );
  }
}
