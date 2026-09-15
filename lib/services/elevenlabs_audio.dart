import 'dart:typed_data';

import 'package:audioplayers/audioplayers.dart';

/// Plays ElevenLabs-synthesized audio bytes.
///
/// A separate seam (rather than using AudioPlayer directly in TtsService)
/// so tests can substitute a fake and assert routing without touching
/// platform channels.
class ElevenLabsAudioPlayer {
  AudioPlayer? _player;

  Future<void> playBytes(Uint8List bytes) async {
    final player = _player ??= AudioPlayer();
    await player.play(BytesSource(bytes));
  }

  Future<void> stop() async {
    try {
      await _player?.stop();
    } catch (_) {}
  }
}
