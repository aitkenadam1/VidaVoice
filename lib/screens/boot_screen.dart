import 'package:flutter/material.dart';

import '../app_config.dart';

/// Shown while the language pack + TTS boot, or if boot fails.
class LoadingScreen extends StatelessWidget {
  const LoadingScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const CircularProgressIndicator(),
            const SizedBox(height: 16),
            Text('Loading ${AppConfig.appDisplayName}…'),
          ],
        ),
      ),
    );
  }
}

class ErrorScreen extends StatelessWidget {
  const ErrorScreen({super.key, required this.message});

  final String message;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Text(
            "Couldn't start ${AppConfig.appDisplayName}:\n\n$message",
            textAlign: TextAlign.center,
          ),
        ),
      ),
    );
  }
}
