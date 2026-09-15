import 'dart:io';

import 'package:path_provider/path_provider.dart';
import 'package:record/record.dart';

import 'elevenlabs_service.dart';

/// Records the short voice samples used for ElevenLabs voice cloning.
///
/// WAV 16 kHz mono: small, lossless, and accepted by the cloning API.
/// A sample shorter than ~2 seconds is rejected client-side — it would
/// only waste an upload. Recording never leaves the device except in the
/// explicit "Create voice" upload step.
class VoiceSampleRecorder {
  VoiceSampleRecorder({AudioRecorder Function()? recorderFactory})
    : _recorderFactory = recorderFactory ?? AudioRecorder.new;

  final AudioRecorder Function() _recorderFactory;
  AudioRecorder? _recorder;
  String? _path;

  /// True while a sample is being recorded.
  bool get isRecording => _recorder != null;

  /// Starts recording a sample. Throws [VoiceSampleException] with a
  /// caregiver-readable message when the microphone is unavailable.
  Future<void> startSample() async {
    if (_recorder != null) return;
    final recorder = _recorderFactory();
    bool permitted = false;
    try {
      permitted = await recorder.hasPermission();
    } catch (_) {
      permitted = false;
    }
    if (!permitted) {
      try {
        await recorder.dispose();
      } catch (_) {}
      throw const VoiceSampleException(
        'Microphone access was denied. Allow the microphone in the device '
        'Settings, then try again.',
      );
    }
    final dir = await getTemporaryDirectory();
    final path =
        '${dir.path}/vv_sample_${DateTime.now().millisecondsSinceEpoch}.wav';
    try {
      await recorder.start(
        const RecordConfig(
          encoder: AudioEncoder.wav,
          sampleRate: 16000,
          numChannels: 1,
        ),
        path: path,
      );
    } catch (_) {
      try {
        await recorder.dispose();
      } catch (_) {}
      throw const VoiceSampleException('Could not start recording. Try again.');
    }
    _recorder = recorder;
    _path = path;
  }

  /// Stops recording and returns the sample. Too-short recordings are
  /// discarded with a caregiver-readable error.
  Future<VoiceSample> stopSample() async {
    final recorder = _recorder;
    final path = _path;
    _recorder = null;
    _path = null;
    if (recorder == null || path == null) {
      throw StateError('No recording in progress.');
    }
    try {
      await recorder.stop();
    } catch (_) {
      // Fall through: validate the file below.
    } finally {
      try {
        await recorder.dispose();
      } catch (_) {}
    }
    final file = File(path);
    if (!await file.exists()) {
      throw const VoiceSampleException('Recording failed. Try again.');
    }
    final bytes = await file.length();
    // 16-bit mono 16 kHz: 32000 bytes/second after the 44-byte WAV header.
    final seconds = (bytes - 44) / 32000;
    if (seconds < 2) {
      try {
        await file.delete();
      } catch (_) {}
      throw VoiceSampleException(
        'That recording was only ${seconds.toStringAsFixed(1)}s — '
        'record at least 2 seconds of clear speech.',
      );
    }
    return VoiceSample(
      path: path,
      duration: Duration(milliseconds: (seconds * 1000).round()),
    );
  }

  /// Aborts an in-progress recording and deletes the partial file.
  Future<void> cancelSample() async {
    final recorder = _recorder;
    final path = _path;
    _recorder = null;
    _path = null;
    if (recorder != null) {
      try {
        await recorder.stop();
      } catch (_) {}
      try {
        await recorder.dispose();
      } catch (_) {}
    }
    if (path != null) {
      try {
        await File(path).delete();
      } catch (_) {}
    }
  }
}

/// Caregiver-readable recording failure.
class VoiceSampleException implements Exception {
  const VoiceSampleException(this.message);
  final String message;
  @override
  String toString() => 'VoiceSampleException: $message';
}
