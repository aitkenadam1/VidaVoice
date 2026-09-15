import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:onevoz/services/elevenlabs_service.dart';

void main() {
  /// Fake HTTP client that can return streamed responses (needed for the
  /// multipart cloneVoice upload). MockClient only supports plain
  /// responses, so it is used for the other endpoints.
  ElevenLabsService streamedService(
    Future<http.StreamedResponse> Function(http.BaseRequest) handler,
  ) => ElevenLabsService(
    apiKey: 'test-key',
    httpClient: _FakeStreamingClient(handler),
  );

  ElevenLabsService service(
    Future<http.Response> Function(http.Request) handler,
  ) => ElevenLabsService(apiKey: 'test-key', httpClient: MockClient(handler));

  group('listVoices', () {
    test('parses the account voice list', () async {
      final svc = service(
        (_) async => http.Response(
          json.encode({
            'voices': [
              {'voice_id': 'v1', 'name': 'Maya', 'category': 'cloned'},
              {'voice_id': 'v2', 'name': 'Narrator', 'category': 'premade'},
            ],
          }),
          200,
        ),
      );
      final voices = await svc.listVoices();
      expect(voices.map((v) => v.id), ['v1', 'v2']);
      expect(voices.first.name, 'Maya');
      expect(voices.first.category, 'cloned');
    });

    test('rejects the API key with a caregiver-readable message', () async {
      final svc = service((_) async => http.Response('{"detail":"x"}', 401));
      expect(
        svc.listVoices(),
        throwsA(
          isA<ElevenLabsException>().having(
            (e) => e.message,
            'message',
            contains('API key'),
          ),
        ),
      );
    });

    test('maps quota errors without leaking the key', () async {
      final svc = service((_) async => http.Response('', 429));
      try {
        await svc.listVoices();
        fail('expected throw');
      } on ElevenLabsException catch (e) {
        expect(e.message, contains('quota'));
        expect(e.message, isNot(contains('test-key')));
      }
    });

    test('skips entries without an id', () async {
      final svc = service(
        (_) async => http.Response(
          json.encode({
            'voices': [
              {'name': 'Nameless'},
              {'voice_id': 'v9', 'name': 'Ok'},
            ],
          }),
          200,
        ),
      );
      final voices = await svc.listVoices();
      expect(voices.map((v) => v.id), ['v9']);
    });
  });

  group('synthesize', () {
    test('returns the audio bytes', () async {
      final bytes = Uint8List.fromList([1, 2, 3, 4]);
      http.BaseRequest? seen;
      final svc = service((req) async {
        seen = req;
        return http.Response.bytes(bytes, 200);
      });
      final out = await svc.synthesize(text: 'Hello', voiceId: 'v1');
      expect(out, bytes);
      expect(seen!.url.path, contains('v1'));
      expect(seen!.url.query, contains('output_format=mp3_44100_64'));
    });

    test('network failure becomes a caregiver-readable error', () async {
      final svc = service((_) => throw http.ClientException('down'));
      expect(
        svc.synthesize(text: 'Hello', voiceId: 'v1'),
        throwsA(
          isA<ElevenLabsException>().having(
            (e) => e.message,
            'message',
            contains("Couldn't reach ElevenLabs"),
          ),
        ),
      );
    });

    test('empty text is rejected before any network call', () async {
      var called = false;
      final svc = service((_) async {
        called = true;
        return http.Response('', 200);
      });
      expect(
        svc.synthesize(text: '  ', voiceId: 'v1'),
        throwsA(isA<ElevenLabsException>()),
      );
      expect(called, isFalse);
    });
  });

  group('cloneVoice', () {
    /// Real temp files: MultipartFile.fromPath reads from disk.
    Future<List<VoiceSample>> tempSamples() async {
      final dir = await Directory.systemTemp.createTemp('vv_test_');
      final paths = <String>[];
      for (var i = 0; i < 2; i++) {
        final file = File('${dir.path}/sample_$i.wav');
        await file.writeAsBytes(List.filled(32000 * 5, 0));
        paths.add(file.path);
      }
      return [
        for (final p in paths)
          VoiceSample(path: p, duration: const Duration(seconds: 5)),
      ];
    }

    test('uploads samples and returns the new voice id', () async {
      http.BaseRequest? seen;
      final svc = streamedService((req) async {
        seen = req;
        return http.StreamedResponse(
          Stream.value(utf8.encode('{"voice_id":"cv-1"}')),
          200,
        );
      });
      final id = await svc.cloneVoice(
        name: 'Maya',
        samples: await tempSamples(),
      );
      expect(id, 'cv-1');
      final multipart = seen as http.MultipartRequest;
      expect(multipart.fields['name'], 'Maya');
      expect(multipart.files.length, 2);
      expect(multipart.headers['xi-api-key'], 'test-key');
    });

    test('requires a name and at least one sample', () async {
      final svc = service((_) async => http.Response('', 200));
      expect(
        svc.cloneVoice(name: '  ', samples: const []),
        throwsA(isA<ElevenLabsException>()),
      );
      expect(
        svc.cloneVoice(name: 'Maya', samples: const []),
        throwsA(isA<ElevenLabsException>()),
      );
    });

    test('missing voice id in the response is an error', () async {
      final svc = streamedService(
        (_) async =>
            http.StreamedResponse(Stream.value(utf8.encode('{}')), 200),
      );
      expect(
        svc.cloneVoice(name: 'Maya', samples: await tempSamples()),
        throwsA(isA<ElevenLabsException>()),
      );
    });
  });

  group('SavedElevenLabsVoice', () {
    test('round-trips through JSON', () {
      const v = SavedElevenLabsVoice(id: 'cv-1', name: 'Maya', locale: 'en');
      final back = SavedElevenLabsVoice.fromJson(v.toJson());
      expect(back.id, 'cv-1');
      expect(back.name, 'Maya');
      expect(back.locale, 'en');
    });

    test('malformed entries are rejected', () {
      expect(
        () => SavedElevenLabsVoice.fromJson({'id': '', 'name': 'x'}),
        throwsA(isA<ElevenLabsException>()),
      );
      expect(
        () => SavedElevenLabsVoice.fromJson({'name': 'x'}),
        throwsA(isA<ElevenLabsException>()),
      );
    });
  });
}

/// Minimal [http.BaseClient] that answers with canned streamed responses.
/// Used for the multipart upload path, which MockClient cannot serve.
class _FakeStreamingClient extends http.BaseClient {
  _FakeStreamingClient(this._handler);

  final Future<http.StreamedResponse> Function(http.BaseRequest) _handler;

  @override
  Future<http.StreamedResponse> send(http.BaseRequest request) =>
      _handler(request);
}
