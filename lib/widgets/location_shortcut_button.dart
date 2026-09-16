import 'package:flutter/material.dart';

import '../screens/location_screen.dart';

/// Location shortcut for the board AppBars: a pin icon next to the call
/// shortcut that opens the standalone Location page.
///
/// Always visible — the page itself holds the per-profile opt-in toggle,
/// so hiding it when sharing is off would strand the way to turn sharing
/// on. Mirrors the existing top-bar shortcuts: compact, one tap, no dead
/// state.
class LocationShortcutButton extends StatelessWidget {
  const LocationShortcutButton({super.key});

  @override
  Widget build(BuildContext context) {
    return IconButton(
      tooltip: 'Location',
      icon: const Icon(Icons.location_on),
      onPressed: () => Navigator.of(context).push(
        MaterialPageRoute(builder: (_) => const LocationScreen()),
      ),
    );
  }
}
