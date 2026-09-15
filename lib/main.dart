import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import 'app_config.dart';
import 'screens/boot_screen.dart';
import 'screens/build_board_screen.dart';
import 'screens/home_board_screen.dart';
import 'screens/onboarding_screen.dart';
import 'services/profile_service.dart';
import 'state/session_state.dart';

void main() {
  final session = SessionState();
  runApp(OneVozApp(session: session));
  // Async on purpose: the UI reacts to BootStatus changes.
  session.boot();
}

/// Routes the home experience by the active profile's communication mode
/// (Phase 3 of the modes plan): Build gets the phrase-strip surface; Tap
/// (and Type, until Phase 4 ships its own screen) keep the classic board.
Widget homeScreenFor(SessionState session) =>
    session.profiles.active?.communicationMode == CommunicationMode.build
        ? const BuildBoardScreen()
        : const HomeBoardScreen();

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
                if (!s.onboardingComplete) {
                  return const OnboardingScreen();
                }
                return homeScreenFor(s);
            }
          },
        ),
      ),
    );
  }
}
