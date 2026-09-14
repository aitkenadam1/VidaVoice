import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import 'app_config.dart';
import 'screens/boot_screen.dart';
import 'screens/home_board_screen.dart';
import 'screens/onboarding_screen.dart';
import 'state/session_state.dart';

void main() {
  final session = SessionState();
  runApp(VidaVoiceApp(session: session));
  // Async on purpose: the UI reacts to BootStatus changes.
  session.boot();
}

class VidaVoiceApp extends StatelessWidget {
  const VidaVoiceApp({super.key, required this.session});

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
                return const HomeBoardScreen();
            }
          },
        ),
      ),
    );
  }
}
