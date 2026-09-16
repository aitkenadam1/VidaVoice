import 'dart:convert';

import 'package:flutter/material.dart';

import '../models/calling_safety.dart';

/// Photo avatar for a [SafetyContact].
///
/// Shows the caregiver-set photo ([SafetyContact.imageData], base64 — same
/// convention as dashboard cells) or a high-contrast person icon when there
/// is no photo or it fails to decode. Never throws on bad data: a corrupt
/// photo degrades to the icon, never to a crash or a blank hole.
class SafetyContactAvatar extends StatelessWidget {
  const SafetyContactAvatar({
    super.key,
    required this.contact,
    this.radius = 40,
  });

  final SafetyContact contact;
  final double radius;

  ImageProvider? _photo() {
    final data = contact.imageData;
    if (data == null || data.isEmpty) return null;
    try {
      return MemoryImage(base64Decode(data));
    } on FormatException {
      return null;
    }
  }

  @override
  Widget build(BuildContext context) {
    final photo = _photo();
    return CircleAvatar(
      radius: radius,
      backgroundColor: Theme.of(context).colorScheme.primaryContainer,
      backgroundImage: photo,
      child: photo != null
          ? null
          : Icon(
              Icons.person,
              size: radius,
              color: Theme.of(context).colorScheme.onPrimaryContainer,
            ),
    );
  }
}
