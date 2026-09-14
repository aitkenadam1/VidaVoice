import 'dart:async';
import 'dart:io';
import 'dart:isolate';
import 'dart:typed_data';

import 'package:archive/archive.dart';
import 'package:audioplayers/audioplayers.dart';
import 'package:crypto/crypto.dart';
import 'package:flutter/foundation.dart' show ValueNotifier, kIsWeb;
import 'package:http/http.dart' as http;
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:sherpa_onnx/sherpa_onnx.dart' as sherpa;

/// A single Kokoro voice.
///
/// [sid] is the speaker index into the voices.bin of the
/// kokoro-int8-multi-lang-v1_0 pack. The ordering below is the pack's
/// canonical order (see k2-fsa/sherpa-onnx
/// scripts/kokoro/v1.0/generate_voices_bin.py):
///   0-10  af_*  American English female
///   11-19 am_*  American English male
///   20-23 bf_*  British English female
///   24-27 bm_*  British English male
///   28    ef_dora   Spanish female
///   29    em_alex   Spanish male
///   30    ff_siwis  French female
///   53    em_santa  Spanish male
class KokoroVoice {
  const KokoroVoice({
    required this.id,
    required this.displayName,
    required this.sid,
    required this.locale,
    required this.espeakLang,
  });

  /// Voice id, e.g. 'af_bella'. Persisted in preferences.
  final String id;

  /// Short display name, e.g. 'Bella'.
  final String displayName;

  /// Speaker index into the pack's voices.bin.
  final int sid;

  /// App locale this voice speaks: 'en', 'es', or 'fr'.
  final String locale;

  /// espeak-ng voice code used for phonemization of this voice's language.
  final String espeakLang;
}

/// Curated Kokoro voices: two per language (one for French for now), all
/// from the single multi-language int8 pack so one ~126 MB download covers
/// every language.
const List<KokoroVoice> kokoroVoices = [
  KokoroVoice(
    id: 'af_bella',
    displayName: 'Bella',
    sid: 2,
    locale: 'en',
    espeakLang: 'en-us',
  ),
  KokoroVoice(
    id: 'af_heart',
    displayName: 'Heart',
    sid: 3,
    locale: 'en',
    espeakLang: 'en-us',
  ),
  KokoroVoice(
    id: 'ef_dora',
    displayName: 'Dora',
    sid: 28,
    locale: 'es',
    espeakLang: 'es',
  ),
  KokoroVoice(
    id: 'em_alex',
    displayName: 'Alex',
    sid: 29,
    locale: 'es',
    espeakLang: 'es',
  ),
  KokoroVoice(
    id: 'ff_siwis',
    displayName: 'Siwis',
    sid: 30,
    locale: 'fr',
    espeakLang: 'fr',
  ),
];

/// Look up a curated voice by its persisted id. Null when unknown.
KokoroVoice? kokoroVoiceById(String id) {
  for (final v in kokoroVoices) {
    if (v.id == id) return v;
  }
  return null;
}

/// BCP-47 tag used for a Kokoro voice's locale in the voice picker.
String kokoroLocaleTag(String locale) => switch (locale) {
  'es' => 'es-ES',
  'fr' => 'fr-FR',
  _ => 'en-US',
};

/// Encode mono float samples as 16-bit PCM WAV bytes. Pure function —
/// unit-testable without the native engine.
Uint8List encodeWav(Float32List samples, int sampleRate) {
  final dataSize = samples.length * 2;
  final buffer = ByteData(44 + dataSize);
  void writeString(int offset, String s) {
    for (var i = 0; i < s.length; i++) {
      buffer.setUint8(offset + i, s.codeUnitAt(i));
    }
  }

  writeString(0, 'RIFF');
  buffer.setUint32(4, 36 + dataSize, Endian.little);
  writeString(8, 'WAVE');
  writeString(12, 'fmt ');
  buffer.setUint32(16, 16, Endian.little); // PCM chunk size
  buffer.setUint16(20, 1, Endian.little); // PCM format
  buffer.setUint16(22, 1, Endian.little); // mono
  buffer.setUint32(24, sampleRate, Endian.little);
  buffer.setUint32(28, sampleRate * 2, Endian.little); // byte rate
  buffer.setUint16(32, 2, Endian.little); // block align
  buffer.setUint16(34, 16, Endian.little); // bits per sample
  writeString(36, 'data');
  buffer.setUint32(40, dataSize, Endian.little);
  for (var i = 0; i < samples.length; i++) {
    final v = (samples[i].clamp(-1.0, 1.0) * 32767).round();
    buffer.setInt16(44 + i * 2, v, Endian.little);
  }
  return buffer.buffer.asUint8List();
}

/// On-device neural TTS via Kokoro-82M (Apache 2.0, free, offline).
///
/// The model pack (~126 MB) is downloaded once on demand from the
/// sherpa-onnx release and extracted with streaming I/O so peak memory stays
/// flat on low-end devices. Synthesis runs in a dedicated worker isolate
/// (FFI blocks the calling isolate), and playback goes through audioplayers.
///
/// Constructing this class touches no platform channels: everything
/// (paths, HTTP, player, isolate) is resolved lazily inside async methods.
class KokoroTtsService {
  static const String _modelDirName = 'kokoro-int8-multi-lang-v1_0';
  static const String _modelUrl =
      'https://github.com/k2-fsa/sherpa-onnx/releases/download/'
      'tts-models/$_modelDirName.tar.bz2';

  /// Download size in bytes of the pinned pack release. Shown in Settings
  /// and used as the progress-bar fallback when the server omits the
  /// content length.
  static const int modelDownloadBytes = 132303094;

  /// SHA-256 of the pinned model pack release. Verified after download,
  /// before extraction — a 126 MB artifact that gets executed as ONNX must
  /// not be trusted on HTTPS alone.
  static const String modelSha256 =
      '4c3052abaa60943a341f193888cf6abd68787dae6ab8ae5c925a706caa247e4e';

  /// Kokoro only runs natively. Web keeps the device voices (flutter_tts).
  static bool get isSupported => !kIsWeb;

  /// The app's speech-rate slider (0.3-1.0, default 0.5) maps to Kokoro's
  /// speed multiplier (1.0 = normal): rate 0.5 -> speed 1.0.
  static double rateToSpeed(double rate) => (rate / 0.5).clamp(0.5, 2.0);

  AudioPlayer? _player;
  AudioPlayer get _audio => _player ??= AudioPlayer();

  http.Client? _http;
  http.Client get _client => _http ??= http.Client();

  Future<Directory>? _modelDirFuture;

  /// Final home of the extracted model: `<support>/kokoro/<pack>/`
  /// (mirrors the tarball's own subdirectory layout).
  Future<Directory> _modelDir() => _modelDirFuture ??= () async {
    final support = await getApplicationSupportDirectory();
    final dir = Directory(p.join(support.path, 'kokoro', _modelDirName));
    return dir;
  }();

  /// True once the model pack is downloaded and extracted. Never throws.
  Future<bool> isModelReady() async {
    if (!isSupported) return false;
    try {
      final home = await _modelDir();
      final ready = File(p.join(home.path, '.ready'));
      if (!await ready.exists()) return false;
      // Belt and suspenders: the engine needs these exact files.
      for (final name in const [
        'model.int8.onnx',
        'voices.bin',
        'tokens.txt',
      ]) {
        if (!await File(p.join(home.path, name)).exists()) return false;
      }
      return await Directory(p.join(home.path, 'espeak-ng-data')).exists();
    } catch (_) {
      return false;
    }
  }

  Future<void>? _downloadFuture;

  /// Broadcast download progress (0.0-1.0) and in-flight state. The service
  /// — not the first caller — owns progress now: UI that subscribes
  /// mid-download (e.g. after navigating away and back, or switching
  /// language) still sees a live bar instead of one frozen at 0. Progress
  /// is null and [isDownloading] false when idle.
  final ValueNotifier<double?> downloadProgress = ValueNotifier<double?>(null);
  final ValueNotifier<bool> isDownloading = ValueNotifier<bool>(false);

  /// Download + extract the model pack (single-flight). Reports 0.0-1.0
  /// progress. Throws on network or extraction failure.
  Future<void> downloadModel({void Function(double progress)? onProgress}) {
    return _downloadFuture ??= _downloadImpl(onProgress: onProgress).whenComplete(
      () => _downloadFuture = null,
    );
  }

  Future<void> _downloadImpl({
    void Function(double progress)? onProgress,
  }) async {
    isDownloading.value = true;
    downloadProgress.value = 0;
    try {
      await _downloadImplInner(onProgress: onProgress);
    } finally {
      isDownloading.value = false;
      downloadProgress.value = null;
    }
  }

  Future<void> _downloadImplInner({
    void Function(double progress)? onProgress,
  }) async {
    final support = await getApplicationSupportDirectory();
    final kokoroRoot = Directory(p.join(support.path, 'kokoro'));
    await kokoroRoot.create(recursive: true);
    final tarball = File(p.join(kokoroRoot.path, '$_modelDirName.tar.bz2'));

    final request = http.Request('GET', Uri.parse(_modelUrl));
    final response = await _client.send(request);
    if (response.statusCode != 200) {
      throw StateError(
        'Kokoro model download failed: HTTP ${response.statusCode}',
      );
    }
    final total = response.contentLength ?? -1;
    // Some servers omit the length; fall back to the pack-time size so the
    // progress bar still moves.
    final expected = total > 0 ? total : modelDownloadBytes;
    var received = 0;
    final sink = tarball.openWrite();
    try {
      await for (final chunk in response.stream) {
        received += chunk.length;
        sink.add(chunk);
        final progress = (received / expected).clamp(0.0, 1.0);
        onProgress?.call(progress);
        downloadProgress.value = progress;
      }
    } finally {
      await sink.close();
    }

    await _verifyDownloadSha256(tarball);

    // Streaming extraction with flat memory (see extractModelPack):
    // bzip2 decodes to a temp tar, then tar entries stream entry-by-entry
    // straight to a staging dir. Runs in a worker isolate, off the UI.
    final root = Directory(p.join(support.path, 'kokoro'));
    final staging = Directory(p.join(root.path, '.staging'));
    if (await staging.exists()) await staging.delete(recursive: true);
    await staging.create(recursive: true);
    try {
      await _extractInIsolate(
        ExtractModelPackArgs(
          tarballPath: tarball.path,
          stagingDir: staging.path,
        ),
      );
      final home = await _modelDir();
      await _verifyStagedPack(staging.path);
      // Atomic promotion: staging -> final home on the same filesystem.
      if (await home.exists()) await home.delete(recursive: true);
      await Directory(
        p.join(staging.path, _modelDirName),
      ).rename(home.path);
    } finally {
      if (await staging.exists()) await staging.delete(recursive: true);
      if (await tarball.exists()) await tarball.delete();
    }

    final home = await _modelDir();
    // The sentinel must be written BEFORE isModelReady() runs: that check
    // requires `.ready` to exist, so verifying first could never succeed.
    await File(p.join(home.path, '.ready')).writeAsString(_modelDirName);
    if (!await isModelReady()) {
      throw StateError('Kokoro model extraction incomplete.');
    }
  }

  /// SHA-256 check of the downloaded pack against the pinned release hash.
  /// Deletes the tarball and throws on mismatch — never extract (let alone
  /// execute) bytes we didn't expect.
  Future<void> _verifyDownloadSha256(File tarball) async {
    final digest = await sha256.bind(tarball.openRead()).first;
    if (digest.toString() != modelSha256) {
      try {
        await tarball.delete();
      } catch (_) {}
      throw StateError(
        'Kokoro model download failed its integrity check. '
        'Please try again.',
      );
    }
  }

  /// The engine needs these files; throw when the staged pack lacks any.
  Future<void> _verifyStagedPack(String stagingPath) async {
    final pack = p.join(stagingPath, _modelDirName);
    for (final name in const [
      'model.int8.onnx',
      'voices.bin',
      'tokens.txt',
    ]) {
      if (!await File(p.join(pack, name)).exists()) {
        throw StateError('Kokoro pack is missing $name.');
      }
    }
    if (!await Directory(p.join(pack, 'espeak-ng-data')).exists()) {
      throw StateError('Kokoro pack is missing espeak-ng-data.');
    }
  }

  // ---- worker isolate ----

  Isolate? _isolate;
  SendPort? _workerPort;
  Future<SendPort>? _workerFuture;

  Future<SendPort> _worker() {
    final pending = _workerFuture;
    if (pending != null) return pending;
    final future = _spawnWorker();
    _workerFuture = future;
    // A failed spawn must not poison later attempts (e.g. transient
    // resource pressure); the next speak() retries the spawn.
    future.then((_) {}, onError: (_) => _workerFuture = null);
    return future;
  }

  Future<SendPort> _spawnWorker() async {
    final home = await _modelDir();
    final mainPort = ReceivePort();
    final errorPort = ReceivePort();
    final isolate = await Isolate.spawn(
      _kokoroWorkerEntry,
      _KokoroWorkerArgs(modelDir: home.path, mainPort: mainPort.sendPort),
      debugName: 'kokoro-tts',
      onError: errorPort.sendPort,
    );
    _isolate = isolate;
    try {
      // The native engine loads inside the worker; on a Fire tablet that
      // takes a while, but it must not hang forever — a dead worker would
      // otherwise leave speak() waiting on a port that never fires, which
      // on a communication device is a permanently dead button.
      final workerSendPort = await Future.any([
        mainPort.first.then((v) => v as SendPort),
        errorPort.first.then((pair) {
          final p = pair as List;
          throw StateError('Kokoro worker failed to start: ${p.first}');
        }),
      ]).timeout(const Duration(seconds: 90));
      _workerPort = workerSendPort;
      return workerSendPort;
    } catch (_) {
      // Don't leave a half-started isolate behind, and don't poison later
      // attempts: the next speak() respawns.
      try {
        isolate.kill(priority: Isolate.immediate);
      } catch (_) {}
      if (identical(_isolate, isolate)) _isolate = null;
      rethrow;
    } finally {
      mainPort.close();
      errorPort.close();
    }
  }

  /// Drop the synthesis worker after a failure or timeout so the next
  /// speak() respawns a fresh one instead of talking to a dead port.
  void _dropWorker() {
    _workerFuture = null;
    _workerPort = null;
    try {
      _isolate?.kill(priority: Isolate.immediate);
    } catch (_) {}
    _isolate = null;
  }

  /// Pre-load the engine in the background (e.g. right after the caregiver
  /// picks a Kokoro voice) so the first real utterance isn't slow.
  /// Never throws.
  Future<void> warmup() async {
    if (!isSupported) return;
    try {
      if (await isModelReady()) await _worker();
    } catch (_) {}
  }

  /// Synthesize [text] with [voice] and play it. Returns false (never
  /// throws) when the model isn't ready or synthesis/playback fails — the
  /// caller falls back to the system voice.
  ///
  /// Each utterance gets its own WAV file: rapid AAC taps must never make
  /// two playbacks share (or race on) one file. A generation counter drops
  /// stale results: when taps overlap, only the latest utterance plays and
  /// superseded audio is deleted, never spoken.
  Future<bool> speak(
    String text, {
    required KokoroVoice voice,
    required double speed,
  }) async {
    if (!isSupported || text.trim().isEmpty) return false;
    if (!await isModelReady()) return false;
    final generation = ++_speakGeneration;
    final replyPort = ReceivePort();
    _KokoroSpeakResult result;
    try {
      final worker = await _worker();
      final temp = await getTemporaryDirectory();
      final wavPath = p.join(temp.path, 'kokoro_${_speakSeq++}.wav');
      worker.send(
        _KokoroSpeakRequest(
          text: text,
          sid: voice.sid,
          espeakLang: voice.espeakLang,
          speed: speed,
          wavPath: wavPath,
          replyPort: replyPort.sendPort,
        ),
      );
      // A wedged worker (native crash, OOM on a Fire tablet) must not hang
      // the button forever: time out and let the caller fall back to the
      // system voice.
      result = await replyPort.first.timeout(
        const Duration(seconds: 30),
        onTimeout: () => _KokoroSpeakResult(error: 'Kokoro timed out.'),
      );
    } catch (_) {
      // Port/isolate trouble: drop the worker so the next speak() respawns
      // it instead of talking to a dead port forever.
      _dropWorker();
      return false;
    } finally {
      replyPort.close();
    }
    final path = result.wavPath;
    if (result.error != null || path == null) {
      // The worker is wedged or the engine failed: drop it so the next
      // speak() starts fresh; this utterance falls back to system voice.
      // (A timed-out worker may still deliver late; the generation check
      // below keeps that stale audio from ever playing.)
      _dropWorker();
      return false;
    }
    if (generation != _speakGeneration) {
      // A newer tap superseded this one — delete the stale audio, don't
      // play it.
      try {
        await File(path).delete();
      } catch (_) {}
      return false;
    }
    // Track the new file BEFORE playing so a playback throw can't leak it.
    final prev = _lastWavPath;
    _lastWavPath = path;
    try {
      await _audio.stop();
      await _audio.play(DeviceFileSource(path));
    } catch (_) {
      try {
        await File(path).delete();
      } catch (_) {}
      _lastWavPath = prev;
      return false;
    }
    // The previous utterance is stopped; its file can go.
    if (prev != null && prev != path) {
      try {
        await File(prev).delete();
      } catch (_) {}
    }
    return true;
  }

  int _speakSeq = 0;

  /// Monotonic tap generation: bumped on every speak() and stop() so
  /// overlapping or superseded synthesis results are dropped, never played.
  int _speakGeneration = 0;
  String? _lastWavPath;

  /// Stop Kokoro playback. Never throws.
  Future<void> stop() async {
    // Invalidate any in-flight synthesis so a queued result never plays
    // after the user asked for silence.
    _speakGeneration++;
    try {
      await _player?.stop();
    } catch (_) {}
  }

  /// Shut down the worker and release resources. Never throws.
  Future<void> dispose() async {
    try {
      _workerPort?.send('quit');
    } catch (_) {}
    _workerFuture = null;
    _workerPort = null;
    try {
      _isolate?.kill(priority: Isolate.immediate);
    } catch (_) {}
    _isolate = null;
    try {
      await _player?.dispose();
    } catch (_) {}
    _player = null;
    try {
      _http?.close();
    } catch (_) {}
    _http = null;
  }
}

/// Spawn args for the worker isolate. Plain data only (isolate-safe).
class _KokoroWorkerArgs {
  _KokoroWorkerArgs({required this.modelDir, required this.mainPort});

  final String modelDir;
  final SendPort mainPort;
}

/// Main -> worker synthesis request. Plain data only (isolate-safe).
class _KokoroSpeakRequest {
  _KokoroSpeakRequest({
    required this.text,
    required this.sid,
    required this.espeakLang,
    required this.speed,
    required this.wavPath,
    required this.replyPort,
  });

  final String text;
  final int sid;
  final String espeakLang;
  final double speed;
  final String wavPath;
  final SendPort replyPort;
}

/// Worker -> main synthesis result. Plain data only (isolate-safe).
class _KokoroSpeakResult {
  _KokoroSpeakResult({this.wavPath, this.error});

  final String? wavPath;
  final String? error;
}

/// Worker isolate entry point: owns the sherpa-onnx engine for the app's
/// lifetime. Each isolate needs its own FFI bindings (initBindings).
///
/// The engine is created once with config-level lang 'en-us' (required at
/// startup or the native layer aborts); every request overrides the
/// phonemization language per-utterance via extra['lang'], so one engine
/// serves all three app languages.
Future<void> _kokoroWorkerEntry(_KokoroWorkerArgs args) async {
  final inbox = ReceivePort();
  args.mainPort.send(inbox.sendPort);

  sherpa.initBindings();
  late final sherpa.OfflineTts tts;
  try {
    tts = sherpa.OfflineTts(
      sherpa.OfflineTtsConfig(
        model: sherpa.OfflineTtsModelConfig(
          kokoro: sherpa.OfflineTtsKokoroModelConfig(
            model: p.join(args.modelDir, 'model.int8.onnx'),
            voices: p.join(args.modelDir, 'voices.bin'),
            tokens: p.join(args.modelDir, 'tokens.txt'),
            dataDir: p.join(args.modelDir, 'espeak-ng-data'),
            // Startup default only; requests pass their own lang.
            lang: 'en-us',
          ),
          numThreads: 2,
          debug: false,
          provider: 'cpu',
        ),
        maxNumSenetences: 1,
      ),
    );
  } catch (e) {
    // Engine failed to load: answer every request with the error.
    await for (final msg in inbox) {
      if (msg is _KokoroSpeakRequest) {
        msg.replyPort.send(_KokoroSpeakResult(error: e.toString()));
      } else if (msg == 'quit') {
        break;
      }
    }
    inbox.close();
    return;
  }

  await for (final msg in inbox) {
    if (msg is _KokoroSpeakRequest) {
      try {
        final audio = tts.generateWithConfig(
          text: msg.text,
          config: sherpa.OfflineTtsGenerationConfig(
            sid: msg.sid,
            speed: msg.speed,
            extra: {'lang': msg.espeakLang},
          ),
        );
        if (audio.samples.isEmpty) {
          msg.replyPort.send(
            _KokoroSpeakResult(error: 'Kokoro produced no audio.'),
          );
        } else {
          final wav = encodeWav(audio.samples, audio.sampleRate);
          await File(msg.wavPath).writeAsBytes(wav, flush: true);
          msg.replyPort.send(_KokoroSpeakResult(wavPath: msg.wavPath));
        }
      } catch (e) {
        msg.replyPort.send(_KokoroSpeakResult(error: e.toString()));
      }
    } else if (msg == 'quit') {
      break;
    }
  }
  tts.free();
  inbox.close();
}

/// Isolate-safe args for [extractModelPack].
class ExtractModelPackArgs {
  const ExtractModelPackArgs({
    required this.tarballPath,
    required this.stagingDir,
  });

  final String tarballPath;
  final String stagingDir;
}

/// Stream-extract a .tar.bz2 model pack to [stagingDir] with flat memory.
///
/// bzip2 decodes block-by-block to a temp tar, then tar entries stream
/// entry-by-entry straight to disk — the ~340 MB the pack expands to is
/// never held in memory, which matters on 2 GB Fire tablets. Each tar
/// header checksum is verified; throws [ArchiveException] on corruption.
///
/// Public so it can be unit-tested; app code calls it in an isolate via
/// [KokoroTtsService.downloadModel].
Future<void> extractModelPack(ExtractModelPackArgs args) async {
  final tarPath = '${args.tarballPath}.tar';
  final input = InputFileStream(args.tarballPath);
  final output = OutputFileStream(tarPath);
  try {
    if (!BZip2Decoder().decodeStream(input, output)) {
      throw ArchiveException('Invalid bzip2 data in Kokoro model pack.');
    }
  } finally {
    await input.close();
    await output.close();
  }
  try {
    await _untarToDisk(tarPath, args.stagingDir);
  } finally {
    await File(tarPath).delete();
  }
}

/// Message for the extraction isolate: plain data + a reply port.
class _ExtractMessage {
  _ExtractMessage(this.args, this.done);

  final ExtractModelPackArgs args;
  final SendPort done;
}

/// Top-level entry point for the extraction isolate. [Isolate.run] and
/// [Isolate.spawn] reject closures, so this cannot be an inline closure.
Future<void> _extractEntryPoint(_ExtractMessage message) async {
  await extractModelPack(message.args);
  message.done.send(null);
}

/// Run [extractModelPack] in a worker isolate and rethrow failures here.
Future<void> _extractInIsolate(ExtractModelPackArgs args) async {
  final done = ReceivePort();
  final failures = ReceivePort();
  final isolate = await Isolate.spawn(
    _extractEntryPoint,
    _ExtractMessage(args, done.sendPort),
    errorsAreFatal: true,
    onError: failures.sendPort,
    debugName: 'kokoro-extract',
  );
  try {
    await Future.any([
      done.first,
      failures.first.then((pair) {
        final p = pair as List;
        throw StateError('Kokoro model extraction failed: ${p.first}');
      }),
    ]);
  } finally {
    done.close();
    failures.close();
    isolate.kill(priority: Isolate.immediate);
  }
}

const int _tarBlockSize = 512;

/// Minimal streaming tar reader: regular files, directories, and GNU long
/// names only — everything the Kokoro pack contains. Symlinks, devices,
/// and other special entries are skipped. Entries that would escape
/// [destDir] (zip-slip) are skipped.
Future<void> _untarToDisk(String tarPath, String destDir) async {
  final dest = p.normalize(p.absolute(destDir));
  final input = InputFileStream(tarPath);
  try {
    String? longName;
    while (!input.isEOS) {
      final header = await _readFully(input, _tarBlockSize);
      if (header.length < _tarBlockSize) break;
      if (_isZeroBlock(header)) break; // end-of-archive marker
      _verifyTarChecksum(header);

      final name = longName ?? _tarString(header, 0, 100);
      longName = null;
      final size = _tarOctal(header, 124, 12);
      final typeFlag = header[156];
      final outPath = p.normalize(p.join(dest, name));

      if (!_isWithinDir(dest, outPath)) {
        // Skipped entries still occupy data blocks plus padding; both must
        // be consumed or the next header read desyncs.
        await _skipFully(input, size);
        await _skipPadding(input, size);
        continue;
      }
      switch (typeFlag) {
        case 0x4c: // 'L': GNU long name for the next entry
          final nameBytes = await _readFully(input, size);
          longName = _cString(nameBytes);
          await _skipPadding(input, size);
        case 0x35: // '5': directory
          await Directory(outPath).create(recursive: true);
        case 0x30: // '0': regular file
        case 0x00: // '\0': regular file (pre-POSIX tars)
          final file = File(outPath);
          await file.parent.create(recursive: true);
          final sink = file.openWrite();
          try {
            var remaining = size;
            while (remaining > 0) {
              final n = remaining > 65536 ? 65536 : remaining;
              sink.add(await _readFully(input, n));
              remaining -= n;
            }
          } finally {
            await sink.close();
          }
          await _skipPadding(input, size);
        default: // symlinks, pax headers, devices: skip the data AND its
          // block padding, or the next header read desyncs.
          await _skipFully(input, size);
          await _skipPadding(input, size);
      }
    }
  } finally {
    await input.close();
  }
}

/// Read exactly [n] bytes (or throw on a truncated archive).
Future<Uint8List> _readFully(InputStream input, int n) async {
  final out = BytesBuilder();
  var remaining = n;
  while (remaining > 0 && !input.isEOS) {
    final chunk = input.readBytes(remaining);
    if (chunk.length == 0) break;
    out.add(chunk.toUint8List());
    remaining -= chunk.length;
  }
  final bytes = out.toBytes();
  if (bytes.length != n) {
    throw ArchiveException('Truncated tar archive.');
  }
  return bytes;
}

Future<void> _skipFully(InputStream input, int n) async {
  var remaining = n;
  while (remaining > 0 && !input.isEOS) {
    final chunk = input.readBytes(remaining);
    if (chunk.length == 0) break;
    remaining -= chunk.length;
  }
  if (remaining != 0) throw ArchiveException('Truncated tar archive.');
}

Future<void> _skipPadding(InputStream input, int size) async {
  final pad = (_tarBlockSize - (size % _tarBlockSize)) % _tarBlockSize;
  if (pad > 0) await _skipFully(input, pad);
}

bool _isZeroBlock(Uint8List block) {
  for (final b in block) {
    if (b != 0) return false;
  }
  return true;
}

/// Standard tar header checksum: the stored octal value must equal the sum
/// of the 512 header bytes with the checksum field itself read as spaces.
void _verifyTarChecksum(Uint8List header) {
  var sum = 0;
  for (var i = 0; i < _tarBlockSize; i++) {
    sum += (i >= 148 && i < 156) ? 0x20 : header[i];
  }
  if (sum != _tarOctal(header, 148, 8)) {
    throw ArchiveException('Invalid tar header checksum.');
  }
}

/// NUL-terminated ASCII string from a header field.
String _tarString(Uint8List header, int offset, int length) =>
    _cString(header.sublist(offset, offset + length));

String _cString(Uint8List bytes) {
  var end = bytes.length;
  for (var i = 0; i < bytes.length; i++) {
    if (bytes[i] == 0) {
      end = i;
      break;
    }
  }
  return String.fromCharCodes(bytes, 0, end);
}

/// Octal ASCII number from a header field (tolerates NUL/space padding).
int _tarOctal(Uint8List header, int offset, int length) {
  final s = _tarString(header, offset, length).trim();
  if (s.isEmpty) return 0;
  final v = int.tryParse(s, radix: 8);
  if (v == null) throw ArchiveException('Invalid tar header number.');
  return v;
}

bool _isWithinDir(String dir, String path) {
  if (path == dir) return true;
  return p.isWithin(dir, path);
}
