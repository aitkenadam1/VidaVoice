import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';

import 'package:http/http.dart' as http;

/// One voice on the ElevenLabs account: a voice the family cloned, or any
/// voice in their ElevenLabs library.
class ElevenLabsVoice {
  const ElevenLabsVoice({
    required this.id,
    required this.name,
    required this.category,
  });

  final String id;
  final String name;

  /// 'cloned', 'generated', 'premade', 'professional', ...
  final String category;
}

/// A voice recording used as cloning input.
class VoiceSample {
  const VoiceSample({required this.path, required this.duration});

  /// Local file path of the recorded WAV.
  final String path;
  final Duration duration;
}

/// A voice reference saved to a communicator profile.
class SavedElevenLabsVoice {
  const SavedElevenLabsVoice({
    required this.id,
    required this.name,
    required this.locale,
    this.createdByApp = false,
  });

  final String id;
  final String name;

  /// BCP-47 tag captured when the voice was cloned/saved (the language
  /// that was spoken), used to filter the voice picker per language.
  final String locale;

  /// True when this voice was created by VoiceSimple's clone flow (so "remove"
  /// may also delete it from the ElevenLabs account). Account/library voices
  /// are never deleted from ElevenLabs by the app.
  final bool createdByApp;

  Map<String, dynamic> toJson() => {
    'id': id,
    'name': name,
    'locale': locale,
    'createdByApp': createdByApp,
  };

  factory SavedElevenLabsVoice.fromJson(Map<String, dynamic> json) {
    final id = json['id'];
    final name = json['name'];
    final locale = json['locale'];
    if (id is! String || id.isEmpty || name is! String || name.isEmpty) {
      throw const ElevenLabsException('Saved voice entry is malformed.');
    }
    return SavedElevenLabsVoice(
      id: id,
      name: name,
      locale: locale is String && locale.isNotEmpty ? locale : 'en',
      createdByApp: json['createdByApp'] == true,
    );
  }
}

/// Caregiver-readable ElevenLabs failure. Never carries the API key.
class ElevenLabsException implements Exception {
  const ElevenLabsException(this.message);
  final String message;
  @override
  String toString() => 'ElevenLabsException: $message';
}

/// Thin client for the ElevenLabs cloud voice API (bring-your-own-key).
///
/// Used for two things: listing the voices on the caregiver's ElevenLabs
/// account, and synthesizing speech / cloning voices. Every method throws
/// [ElevenLabsException] with a caregiver-readable message — callers treat
/// any failure as "cloud voice unavailable" and fall back to on-device
/// voices, never silence.
class ElevenLabsService {
  // The API key stays a private field on purpose: it is the credential this
  // service needs to sign requests, and it must not be readable from
  // callers, logs, or backups.
  ElevenLabsService({required String apiKey, http.Client? httpClient})
    // ignore: prefer_initializing_formals
    : _apiKey = apiKey,
      _client = httpClient ?? http.Client();

  static const _base = 'https://api.elevenlabs.io';

  /// Bounds every network call: a stalled connection must surface as an
  /// error (so the on-device fallback runs) rather than hang a button
  /// forever. Cloning uploads audio and waits on server-side processing,
  /// so it gets a longer budget.
  static const _listTimeout = Duration(seconds: 10);
  static const _synthesizeTimeout = Duration(seconds: 5);
  static const _cloneTimeout = Duration(seconds: 90);
  static const _deleteTimeout = Duration(seconds: 10);

  final String _apiKey;
  final http.Client _client;

  Map<String, String> get _headers => {
    'xi-api-key': _apiKey,
    'Content-Type': 'application/json',
  };

  /// Voices on the ElevenLabs account (cloned + library).
  Future<List<ElevenLabsVoice>> listVoices() async {
    final res = await _guard(
      () => _client.get(Uri.parse('$_base/v1/voices'), headers: _headers),
      timeout: _listTimeout,
    );
    _check(res.statusCode, res.body);
    final decoded = json.decode(res.body);
    final voices = decoded is Map ? decoded['voices'] : null;
    if (voices is! List) {
      throw const ElevenLabsException(
        'ElevenLabs returned an unexpected voice list.',
      );
    }
    return [
      for (final v in voices)
        if (v is Map)
          ElevenLabsVoice(
            id: v['voice_id']?.toString() ?? '',
            name: v['name']?.toString() ?? 'Voice',
            category: v['category']?.toString() ?? '',
          ),
    ].where((v) => v.id.isNotEmpty).toList();
  }

  /// Synthesizes [text] as MP3 audio bytes. Keep utterances short (board
  /// phrases are) — long text costs more and is slower.
  Future<Uint8List> synthesize({
    required String text,
    required String voiceId,
  }) async {
    final trimmed = text.trim();
    if (trimmed.isEmpty) {
      throw const ElevenLabsException('Nothing to speak.');
    }
    final res = await _guard(
      () => _client.post(
        Uri.parse(
          '$_base/v1/text-to-speech/$voiceId?output_format=mp3_44100_64',
        ),
        headers: _headers,
        body: json.encode({
          'text': trimmed,
          'model_id': 'eleven_multilingual_v2',
        }),
      ),
      timeout: _synthesizeTimeout,
    );
    _check(res.statusCode, res.body);
    return res.bodyBytes;
  }

  /// Creates an instant-cloned voice from recorded samples and returns its
  /// id. The audio files are uploaded to ElevenLabs — call only after the
  /// caregiver explicitly consents ("Create voice"). Everything that can
  /// throw here — building the multipart body, reading sample files,
  /// sending, reading the response — runs inside [_guard] so callers only
  /// ever see [ElevenLabsException].
  Future<String> cloneVoice({
    required String name,
    required List<VoiceSample> samples,
  }) async {
    final trimmed = name.trim();
    if (trimmed.isEmpty) {
      throw const ElevenLabsException('Give the voice a name first.');
    }
    if (samples.isEmpty) {
      throw const ElevenLabsException(
        'Record at least one voice sample first.',
      );
    }
    final body = await _guard(() async {
      final request = http.MultipartRequest(
        'POST',
        Uri.parse('$_base/v1/voices/add'),
      );
      request.headers['xi-api-key'] = _apiKey;
      request.fields['name'] = trimmed;
      for (var i = 0; i < samples.length; i++) {
        request.files.add(
          await http.MultipartFile.fromPath(
            'files',
            samples[i].path,
            filename: 'sample_${i + 1}.wav',
          ),
        );
      }
      final streamed = await _client.send(request);
      final text = await streamed.stream.bytesToString();
      _check(streamed.statusCode, text);
      return text;
    }, timeout: _cloneTimeout);
    final decoded = json.decode(body);
    final voiceId = decoded is Map ? decoded['voice_id']?.toString() : null;
    if (voiceId == null || voiceId.isEmpty) {
      throw const ElevenLabsException('ElevenLabs did not return a voice id.');
    }
    return voiceId;
  }

  /// Deletes a voice from the ElevenLabs account. Only call for voices this
  /// app created ([SavedElevenLabsVoice.createdByApp]) after the caregiver
  /// confirms — account/library voices must never be deleted by the app.
  Future<void> deleteVoice(String voiceId) async {
    final res = await _guard(
      () => _client.delete(
        Uri.parse('$_base/v1/voices/$voiceId'),
        headers: _headers,
      ),
      timeout: _deleteTimeout,
    );
    _check(res.statusCode, res.body);
  }

  /// Maps transport failures to caregiver-readable errors. The [timeout]
  /// bounds the whole call: a stalled connection becomes an
  /// [ElevenLabsException] so the on-device speech fallback runs instead of
  /// hanging the button.
  Future<T> _guard<T>(
    Future<T> Function() call, {
    required Duration timeout,
  }) async {
    try {
      return await call().timeout(timeout);
    } on TimeoutException {
      throw const ElevenLabsException(
        'ElevenLabs took too long to respond. Check the connection and try again.',
      );
    } on ElevenLabsException {
      rethrow;
    } catch (_) {
      throw const ElevenLabsException(
        "Couldn't reach ElevenLabs. Check the internet connection and try again.",
      );
    }
  }

  /// Maps HTTP failures to caregiver-readable errors.
  void _check(int status, String body) {
    if (status >= 200 && status < 300) return;
    if (status == 401 || status == 403) {
      throw const ElevenLabsException(
        'ElevenLabs rejected the API key. Double-check the key and try again.',
      );
    }
    if (status == 429) {
      throw const ElevenLabsException(
        'ElevenLabs rate limit or quota reached. Try again later or check the ElevenLabs account.',
      );
    }
    if (status == 400 || status == 422) {
      final detail = _detail(body);
      throw ElevenLabsException(
        detail.isNotEmpty ? detail : 'ElevenLabs rejected the request.',
      );
    }
    throw ElevenLabsException(
      'ElevenLabs request failed (status $status). Try again.',
    );
  }

  String _detail(String body) {
    try {
      final decoded = json.decode(body);
      if (decoded is Map) {
        final detail = decoded['detail'];
        if (detail is Map && detail['message'] is String) {
          return detail['message'] as String;
        }
        if (detail is String) return detail;
        if (decoded['message'] is String) return decoded['message'] as String;
      }
    } catch (_) {}
    return '';
  }
}
