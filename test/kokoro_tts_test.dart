import 'dart:io';
import 'dart:typed_data';

import 'package:archive/archive.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;
import 'package:vidavoice/services/kokoro_tts_service.dart';
import 'package:vidavoice/services/tts_service.dart';

void main() {
  group('kokoro voice table', () {
    test('covers en, es, and fr with the verified pack sids', () {
      // sids verified against k2-fsa/sherpa-onnx
      // scripts/kokoro/v1.0/generate_voices_bin.py (id2speaker table).
      final byId = {for (final v in kokoroVoices) v.id: v};
      expect(byId['af_bella']!.sid, 2);
      expect(byId['af_heart']!.sid, 3);
      expect(byId['ef_dora']!.sid, 28);
      expect(byId['em_alex']!.sid, 29);
      expect(byId['ff_siwis']!.sid, 30);

      expect(
        kokoroVoices.where((v) => v.locale == 'en').length,
        greaterThanOrEqualTo(1),
      );
      expect(
        kokoroVoices.where((v) => v.locale == 'es').length,
        greaterThanOrEqualTo(1),
      );
      expect(
        kokoroVoices.where((v) => v.locale == 'fr').length,
        greaterThanOrEqualTo(1),
      );
    });

    test('espeak language codes match the voice language', () {
      for (final v in kokoroVoices) {
        expect(v.espeakLang, isNotEmpty);
      }
      expect(
        kokoroVoices
            .where((v) => v.locale == 'es')
            .every((v) => v.espeakLang == 'es'),
        isTrue,
      );
      expect(
        kokoroVoices
            .where((v) => v.locale == 'fr')
            .every((v) => v.espeakLang == 'fr'),
        isTrue,
      );
      expect(
        kokoroVoices
            .where((v) => v.locale == 'en')
            .every((v) => v.espeakLang == 'en-us'),
        isTrue,
      );
    });

    test('kokoroVoiceById round-trips the table', () {
      for (final v in kokoroVoices) {
        expect(kokoroVoiceById(v.id), same(v));
      }
      expect(kokoroVoiceById('nope'), isNull);
    });

    test('sids are unique', () {
      final sids = kokoroVoices.map((v) => v.sid).toList();
      expect(sids.toSet().length, sids.length);
    });
  });

  group('rateToSpeed', () {
    test('maps the app rate slider to a Kokoro speed multiplier', () {
      // App slider: 0.3 - 1.0, default 0.5. Kokoro: 1.0 = normal speed.
      expect(KokoroTtsService.rateToSpeed(0.5), 1.0);
      expect(KokoroTtsService.rateToSpeed(0.3), closeTo(0.6, 1e-9));
      expect(KokoroTtsService.rateToSpeed(1.0), 2.0);
    });
  });

  group('encodeWav', () {
    test('writes a valid 16-bit PCM WAV header', () {
      final samples = Float32List.fromList([0.0, 0.5, -0.5, 1.0, -1.0]);
      final wav = encodeWav(samples, 24000);
      expect(wav.length, 44 + samples.length * 2);
      final header = String.fromCharCodes(wav.sublist(0, 4));
      expect(header, 'RIFF');
      expect(String.fromCharCodes(wav.sublist(8, 12)), 'WAVE');
      expect(String.fromCharCodes(wav.sublist(12, 16)), 'fmt ');
      final data = ByteData.sublistView(wav);
      expect(data.getUint32(24, Endian.little), 24000); // sample rate
      expect(data.getUint16(22, Endian.little), 1); // mono
      expect(data.getUint16(34, Endian.little), 16); // bits per sample
      expect(data.getUint32(40, Endian.little), samples.length * 2);
      // Sample values: 0.5 -> ~16384, clamped extremes.
      expect(data.getInt16(44 + 1 * 2, Endian.little), closeTo(16384, 1));
      expect(data.getInt16(44 + 3 * 2, Endian.little), 32767);
      expect(data.getInt16(44 + 4 * 2, Endian.little), -32767);
    });

    test('clamps out-of-range samples', () {
      final samples = Float32List.fromList([2.0, -3.0]);
      final wav = encodeWav(samples, 24000);
      final data = ByteData.sublistView(wav);
      expect(data.getInt16(44, Endian.little), 32767);
      expect(data.getInt16(46, Endian.little), -32767);
    });
  });

  group('extractModelPack', () {
    Future<Directory> makeTarball(Map<String, List<int>> files) async {
      final archive = Archive();
      for (final e in files.entries) {
        archive.addFile(ArchiveFile(e.key, e.value.length, e.value));
      }
      final bz2 = BZip2Encoder().encodeBytes(TarEncoder().encodeBytes(archive));
      final tmp = await Directory.systemTemp.createTemp('kokoro_test');
      await File(p.join(tmp.path, 'pack.tar.bz2')).writeAsBytes(bz2);
      return tmp;
    }

    test('round-trips files, long names, and nested dirs; skips zip-slip',
        () async {
      final longName = '${'a' * 120}.txt';
      final tmp = await makeTarball({
        'hello.txt': [104, 101, 108, 108, 111],
        'nested/dir/data.bin': [1, 2, 3, 4],
        longName: [7, 8, 9],
        '../evil.txt': [9, 9, 9],
      });
      try {
        final tarball = p.join(tmp.path, 'pack.tar.bz2');
        final staging = Directory(p.join(tmp.path, 'staging'));
        await staging.create();
        await extractModelPack(
          ExtractModelPackArgs(tarballPath: tarball, stagingDir: staging.path),
        );
        expect(
          await File(p.join(staging.path, 'hello.txt')).readAsString(),
          'hello',
        );
        expect(
          await File(
            p.join(staging.path, 'nested', 'dir', 'data.bin'),
          ).readAsBytes(),
          [1, 2, 3, 4],
        );
        expect(
          await File(p.join(staging.path, longName)).readAsBytes(),
          [7, 8, 9],
        );
        // Zip-slip entry must not escape the staging dir.
        expect(await File(p.join(tmp.path, 'evil.txt')).exists(), isFalse);
        // Temp tar is cleaned up.
        expect(await File('$tarball.tar').exists(), isFalse);
      } finally {
        await tmp.delete(recursive: true);
      }
    });

    test('rejects a corrupt tarball', () async {
      final tmp = await Directory.systemTemp.createTemp('kokoro_test');
      try {
        final tarball = p.join(tmp.path, 'pack.tar.bz2');
        await File(tarball).writeAsBytes([1, 2, 3, 4, 5]);
        final staging = Directory(p.join(tmp.path, 'staging'));
        await staging.create();
        await expectLater(
          extractModelPack(
            ExtractModelPackArgs(
              tarballPath: tarball,
              stagingDir: staging.path,
            ),
          ),
          throwsA(isA<ArchiveException>()),
        );
      } finally {
        await tmp.delete(recursive: true);
      }
    });
  });

  group('TtsVoice kokoro support', () {    test('equality and hashCode include kokoroVoiceId', () {
      const a = TtsVoice(name: 'Kokoro Bella', locale: 'en-US');
      const b = TtsVoice(
        name: 'Kokoro Bella',
        locale: 'en-US',
        kokoroVoiceId: 'af_bella',
      );
      const c = TtsVoice(
        name: 'Kokoro Bella',
        locale: 'en-US',
        kokoroVoiceId: 'af_bella',
      );
      expect(a.isKokoro, isFalse);
      expect(b.isKokoro, isTrue);
      expect(a, isNot(equals(b)));
      expect(b, equals(c));
      expect(b.hashCode, c.hashCode);
    });
  });
}
