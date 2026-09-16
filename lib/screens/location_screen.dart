import 'package:flutter/material.dart';

import '../widgets/location_section.dart';

/// Standalone Location page.
///
/// Opened from the location shortcut in the blue banner on the boards
/// (next to the call shortcut). Hosts the full location content — consent,
/// sharing controls, live map, history, and alerts — as its own page
/// instead of buried inside the caregiver settings. Same widgets, same
/// privacy posture: coordinates only ever appear decrypted on-device.
class LocationScreen extends StatelessWidget {
  const LocationScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Location'),
      ),
      body: const SingleChildScrollView(
        padding: EdgeInsets.all(16),
        child: LocationSection(),
      ),
    );
  }
}
