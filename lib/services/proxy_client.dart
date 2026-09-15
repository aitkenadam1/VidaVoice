import 'dart:async';
import 'dart:convert';
import 'dart:math';
import 'dart:typed_data';

import 'package:http/http.dart' as http;

import 'elevenlabs_key_store.dart';

/// Base URL of the managed VidaVoice voice backend.
///
/// PLACEHOLDER: the proxy is built and verified locally at
/// ~/workspace/vidavoice-voice-proxy but is NOT deployed yet. Until Adam
/// deploys it and updates this URL, every proxy call fails with an
/// "unreachable" ProxyException — which is the normal, expected state.
/// The app treats an unreachable proxy as "offline": onboarding offers to
/// continue with on-device voices, and speech falls back to on-device
/// voices. Nothing in the app may break when this host doesn't resolve.
const kProxyBaseUrl = 'https://voice.vidavoice.org';

/// Error from the managed voice proxy (or from reaching it).
///
/// [code] is the server's machine-readable error code when one was
/// provided (e.g. "email_taken", "quota_exceeded", "DEVICE_LIMIT_REACHED",
/// "unauthorized") or a client-side code ("unreachable", "bad_response").
/// [fallbackAllowed] mirrors the contract: the caller may fall back to
/// on-device voices.
class ProxyException implements Exception {
  ProxyException(
    this.message, {
    this.code,
    this.statusCode,
    this.fallbackAllowed = false,
  });

  final String message;
  final String? code;
  final int? statusCode;
  final bool fallbackAllowed;

  @override
  String toString() => 'ProxyException(${code ?? statusCode}): $message';
}

/// A UUID v4, for request ids and install ids. The http package is the
/// only dependency we need; no uuid package is used in this repo.
String proxyUuid4() {
  final r = Random.secure();
  final bytes = List<int>.generate(16, (_) => r.nextInt(256));
  bytes[6] = (bytes[6] & 0x0f) | 0x40; // version 4
  bytes[8] = (bytes[8] & 0x3f) | 0x80; // variant 10
  String hex(int n) => n.toRadixString(16).padLeft(2, '0');
  final s = bytes.map(hex).join();
  return '${s.substring(0, 8)}-${s.substring(8, 12)}-'
      '${s.substring(12, 16)}-${s.substring(16, 20)}-${s.substring(20)}';
}

/// Result of a successful signup or login.
class ProxyAuthResult {
  ProxyAuthResult({
    required this.token,
    required this.familyId,
    required this.profileIds,
  });

  final String token;
  final String familyId;
  final List<String> profileIds;

  factory ProxyAuthResult.fromJson(Map<String, dynamic> json) {
    final token = json['token']?.toString() ?? '';
    if (token.isEmpty) {
      throw ProxyException(
        'The service returned an unexpected response.',
        code: 'bad_response',
      );
    }
    final rawIds = json['profile_ids'];
    return ProxyAuthResult(
      token: token,
      familyId: json['family_id']?.toString() ?? '',
      profileIds: rawIds is List
          ? rawIds.map((e) => e.toString()).toList()
          : const [],
    );
  }
}

/// One cloud voice from the family's entitlement. Ids are opaque — the app
/// never sees provider ids, only these.
class ProxyVoice {
  ProxyVoice({
    required this.id,
    required this.name,
    required this.locale,
    this.version,
  });

  final String id;
  final String name;
  final String locale;
  final String? version;

  factory ProxyVoice.fromJson(Map<String, dynamic> json) => ProxyVoice(
    id: json['id']?.toString() ?? '',
    name: json['name']?.toString() ?? 'Voice',
    locale: json['locale']?.toString() ?? '',
    version: json['version']?.toString(),
  );
}

/// GET /v1/voice-entitlement response.
class ProxyEntitlement {
  ProxyEntitlement({
    required this.familyId,
    required this.voices,
    required this.monthlyCap,
    required this.used,
    required this.remaining,
    this.perMinuteLimit,
    this.source,
    this.periodStart,
  });

  final String familyId;
  final List<ProxyVoice> voices;
  final int monthlyCap;
  final int used;
  final int remaining;
  final int? perMinuteLimit;
  final String? source;
  final String? periodStart;

  factory ProxyEntitlement.fromJson(Map<String, dynamic> json) {
    final rawVoices = json['voices'];
    final quota = json['quota'];
    final Map<String, dynamic> q = quota is Map<String, dynamic> ? quota : {};
    return ProxyEntitlement(
      familyId: json['family_id']?.toString() ?? '',
      voices: rawVoices is List
          ? rawVoices
                .whereType<Map<String, dynamic>>()
                .map(ProxyVoice.fromJson)
                .toList()
          : const [],
      monthlyCap: (q['monthly_cap'] as num?)?.toInt() ?? 0,
      used: (q['used'] as num?)?.toInt() ?? 0,
      remaining: (q['remaining'] as num?)?.toInt() ?? 0,
      perMinuteLimit: (q['per_minute_limit'] as num?)?.toInt(),
      source: q['source']?.toString(),
      periodStart: q['period_start']?.toString(),
    );
  }
}

/// GET /v1/usage-summary response. Carries counts and quota only — the
/// contract guarantees no utterance text is ever included.
class ProxyUsage {
  ProxyUsage({
    required this.familyId,
    required this.monthlyCap,
    required this.used,
    required this.remaining,
    this.periodStart,
    this.periodEnd,
    this.total,
    this.cacheHits,
    this.providerCalls,
    this.throttled,
    this.errors,
    this.avgLatencyMs,
  });

  final String familyId;
  final int monthlyCap;
  final int used;
  final int remaining;
  final String? periodStart;
  final String? periodEnd;
  final int? total;
  final int? cacheHits;
  final int? providerCalls;
  final int? throttled;
  final int? errors;
  final int? avgLatencyMs;

  factory ProxyUsage.fromJson(Map<String, dynamic> json) {
    final period = json['period'];
    final Map<String, dynamic> p = period is Map<String, dynamic> ? period : {};
    final quota = json['quota'];
    final Map<String, dynamic> q = quota is Map<String, dynamic> ? quota : {};
    final requests = json['requests'];
    final Map<String, dynamic> r = requests is Map<String, dynamic>
        ? requests
        : {};
    int? asInt(Object? v) => (v as num?)?.toInt();
    return ProxyUsage(
      familyId: json['family_id']?.toString() ?? '',
      monthlyCap: asInt(q['monthly_cap']) ?? 0,
      used: asInt(q['used']) ?? 0,
      remaining: asInt(q['remaining']) ?? 0,
      periodStart: p['start']?.toString(),
      periodEnd: p['end']?.toString(),
      total: asInt(r['total']),
      cacheHits: asInt(r['cache_hits']),
      providerCalls: asInt(r['provider_calls']),
      throttled: asInt(r['throttled']),
      errors: asInt(r['errors']),
      avgLatencyMs: asInt(r['avg_latency_ms']),
    );
  }
}

/// One registered device.
class ProxyDevice {
  ProxyDevice({
    required this.installId,
    this.deviceName,
    this.platform,
    this.createdAt,
    this.lastSeenAt,
  });

  final String installId;
  final String? deviceName;
  final String? platform;
  final String? createdAt;
  final String? lastSeenAt;

  factory ProxyDevice.fromJson(Map<String, dynamic> json) => ProxyDevice(
    installId: json['install_id']?.toString() ?? '',
    deviceName: json['device_name']?.toString(),
    platform: json['platform']?.toString(),
    createdAt: json['created_at']?.toString(),
    lastSeenAt: json['last_seen_at']?.toString(),
  );
}

/// POST /v1/devices/register response (201 new, 200 re-register).
class ProxyDeviceRegistration {
  ProxyDeviceRegistration({
    required this.device,
    required this.deviceSlots,
    required this.subscriptionTier,
    required this.devicesUsed,
  });

  final ProxyDevice device;
  final int deviceSlots;
  final String subscriptionTier;
  final int devicesUsed;

  factory ProxyDeviceRegistration.fromJson(Map<String, dynamic> json) {
    final device = json['device'];
    return ProxyDeviceRegistration(
      device: device is Map<String, dynamic>
          ? ProxyDevice.fromJson(device)
          : ProxyDevice(installId: ''),
      deviceSlots: (json['device_slots'] as num?)?.toInt() ?? 3,
      subscriptionTier: json['subscription_tier']?.toString() ?? 'base',
      devicesUsed: (json['devices_used'] as num?)?.toInt() ?? 0,
    );
  }
}

/// GET /v1/devices response.
class ProxyDeviceList {
  ProxyDeviceList({
    required this.deviceSlots,
    required this.subscriptionTier,
    required this.devicesUsed,
    required this.devices,
  });

  final int deviceSlots;
  final String subscriptionTier;
  final int devicesUsed;
  final List<ProxyDevice> devices;

  factory ProxyDeviceList.fromJson(Map<String, dynamic> json) {
    final raw = json['devices'];
    return ProxyDeviceList(
      deviceSlots: (json['device_slots'] as num?)?.toInt() ?? 3,
      subscriptionTier: json['subscription_tier']?.toString() ?? 'base',
      devicesUsed: (json['devices_used'] as num?)?.toInt() ?? 0,
      devices: raw is List
          ? raw
                .whereType<Map<String, dynamic>>()
                .map(ProxyDevice.fromJson)
                .toList()
          : const [],
    );
  }
}

/// HTTP client for the managed VidaVoice voice backend.
///
/// Every call carries `Authorization: Bearer <token>` (once signed in) and
/// a 5-second timeout. The backend is optional infrastructure: when it is
/// unreachable, every method throws a [ProxyException] with code
/// "unreachable", and callers fall back to on-device voices.
class ProxyClient {
  ProxyClient({http.Client? client, String? baseUrl})
    : _client = client ?? http.Client(),
      baseUrl = baseUrl ?? kProxyBaseUrl;

  /// Per-call timeout, per the proxy contract.
  static const _timeout = Duration(seconds: 5);

  final http.Client _client;

  /// Overridable for tests; production uses [kProxyBaseUrl].
  final String baseUrl;

  String? _token;

  /// The current bearer token, if signed in.
  String? get token => _token;

  bool get hasToken => _token != null && _token!.isNotEmpty;

  void setToken(String? token) {
    _token = (token == null || token.isEmpty) ? null : token;
  }

  Map<String, String> _headers({bool jsonBody = true}) {
    final headers = <String, String>{};
    if (jsonBody) headers['Content-Type'] = 'application/json';
    final t = _token;
    if (t != null) headers['Authorization'] = 'Bearer $t';
    return headers;
  }

  void _requireAuth() {
    if (!hasToken) {
      throw ProxyException('Not signed in.', code: 'unauthorized');
    }
  }

  /// POST [path], returning the decoded JSON body. Throws [ProxyException]
  /// on transport failure or any non-2xx status.
  Future<Map<String, dynamic>> _postJson(
    String path,
    Map<String, dynamic> body,
  ) async {
    final uri = Uri.parse('$baseUrl$path');
    late http.Response res;
    try {
      res = await _client
          .post(uri, headers: _headers(), body: json.encode(body))
          .timeout(_timeout);
    } on TimeoutException {
      throw ProxyException(
        'The request timed out.',
        code: 'unreachable',
        fallbackAllowed: true,
      );
    } catch (_) {
      throw ProxyException(
        'Could not reach the VidaVoice service.',
        code: 'unreachable',
        fallbackAllowed: true,
      );
    }
    return _decode(res);
  }

  /// GET [path], returning the decoded JSON body.
  Future<Map<String, dynamic>> _getJson(String path) async {
    final uri = Uri.parse('$baseUrl$path');
    late http.Response res;
    try {
      res = await _client.get(uri, headers: _headers()).timeout(_timeout);
    } on TimeoutException {
      throw ProxyException(
        'The request timed out.',
        code: 'unreachable',
        fallbackAllowed: true,
      );
    } catch (_) {
      throw ProxyException(
        'Could not reach the VidaVoice service.',
        code: 'unreachable',
        fallbackAllowed: true,
      );
    }
    return _decode(res, uri: uri);
  }

  /// DELETE [path], returning the decoded JSON body.
  Future<Map<String, dynamic>> _deleteJson(String path) async {
    final uri = Uri.parse('$baseUrl$path');
    late http.Response res;
    try {
      res = await _client.delete(uri, headers: _headers()).timeout(_timeout);
    } on TimeoutException {
      throw ProxyException(
        'The request timed out.',
        code: 'unreachable',
        fallbackAllowed: true,
      );
    } catch (_) {
      throw ProxyException(
        'Could not reach the VidaVoice service.',
        code: 'unreachable',
        fallbackAllowed: true,
      );
    }
    return _decode(res, uri: uri);
  }

  Map<String, dynamic> _decode(http.Response res, {Uri? uri}) {
    Map<String, dynamic>? body;
    try {
      final decoded = json.decode(res.body);
      if (decoded is Map<String, dynamic>) body = decoded;
    } catch (_) {
      // Non-JSON body — handled below as a generic error.
    }
    if (res.statusCode >= 200 && res.statusCode < 300) {
      return body ?? const {};
    }
    throw _errorFor(res.statusCode, body);
  }

  ProxyException _errorFor(int status, Map<String, dynamic>? body) {
    final err = body?['error'];
    final Map<String, dynamic>? detail = err is Map<String, dynamic>
        ? err
        : null;
    final code = detail?['code']?.toString() ?? _defaultCode(status);
    final message =
        detail?['message']?.toString() ?? _defaultMessage(status, code);
    // The contract puts fallback_allowed at the top level; accept it nested
    // too. 429/502/503 are always fall-back-able per the contract.
    final fallback =
        (body?['fallback_allowed'] as bool?) ??
        (detail?['fallback_allowed'] as bool?) ??
        (status == 429 || status == 502 || status == 503);
    return ProxyException(
      message,
      code: code,
      statusCode: status,
      fallbackAllowed: fallback,
    );
  }

  String _defaultCode(int status) {
    switch (status) {
      case 400:
        return 'bad_request';
      case 401:
        return 'unauthorized';
      case 403:
        return 'forbidden';
      case 404:
        return 'not_found';
      case 409:
        return 'conflict';
      case 429:
        return 'rate_limited';
      case 502:
      case 503:
        return 'provider_unavailable';
      default:
        return 'server_error';
    }
  }

  String _defaultMessage(int status, String code) {
    switch (code) {
      case 'unauthorized':
        return 'Your session expired. Please sign in again.';
      case 'rate_limited':
        return 'Too many requests. Please wait and try again.';
      case 'provider_unavailable':
        return 'The voice service is temporarily unavailable.';
      default:
        return 'The service returned an error ($status).';
    }
  }

  /// Create a caregiver account. 201 on success.
  Future<ProxyAuthResult> signup({
    required String email,
    required String username,
    required String password,
    String? profileName,
  }) async {
    final body = await _postJson('/v1/auth/signup', {
      'email': email,
      'username': username,
      'password': password,
      if (profileName != null && profileName.trim().isNotEmpty)
        'profile_name': profileName.trim(),
    });
    return ProxyAuthResult.fromJson(body);
  }

  /// Sign in with email or username. 200 on success.
  Future<ProxyAuthResult> login({
    required String identifier,
    required String password,
  }) async {
    final body = await _postJson('/v1/auth/login', {
      'identifier': identifier,
      'password': password,
    });
    return ProxyAuthResult.fromJson(body);
  }

  /// Synthesize [text] through the managed backend and return the raw MP3
  /// bytes. The contract's audio URL is signed AND requires the bearer
  /// token to fetch, so it is fetched here with the Authorization header —
  /// the signed URL never leaves this method.
  ///
  /// Throws [ProxyException] on any failure (including 429 quota/rate
  /// limits and 502/503 provider outages). Callers fall back to on-device
  /// voices whenever [ProxyException.fallbackAllowed] is true.
  Future<Uint8List> synthesize({
    required String requestId,
    required String profileId,
    required String voiceId,
    required String text,
  }) async {
    _requireAuth();
    final body = await _postJson('/v1/speech', {
      'request_id': requestId,
      'profile_id': profileId,
      'voice_id': voiceId,
      'text': text,
    });
    final audio = body['audio'];
    final url = audio is Map<String, dynamic> ? audio['url']?.toString() : null;
    if (url == null || url.isEmpty) {
      throw ProxyException(
        'The voice service returned no audio.',
        code: 'bad_response',
        fallbackAllowed: true,
      );
    }
    late http.Response res;
    try {
      res = await _client
          .get(Uri.parse(url), headers: _headers(jsonBody: false))
          .timeout(_timeout);
    } on TimeoutException {
      throw ProxyException(
        'The request timed out.',
        code: 'unreachable',
        fallbackAllowed: true,
      );
    } catch (_) {
      throw ProxyException(
        'Could not download the audio.',
        code: 'unreachable',
        fallbackAllowed: true,
      );
    }
    if (res.statusCode != 200) {
      final e = _errorFor(res.statusCode, null);
      throw ProxyException(
        e.message,
        code: e.code,
        statusCode: e.statusCode,
        fallbackAllowed: true,
      );
    }
    return res.bodyBytes;
  }

  /// The family's cloud voices plus quota. 401 → [ProxyException] with
  /// code "unauthorized" (callers sign out).
  Future<ProxyEntitlement> getEntitlement() async {
    _requireAuth();
    return ProxyEntitlement.fromJson(await _getJson('/v1/voice-entitlement'));
  }

  /// Quota and request counts for the current period. Never includes
  /// utterance text (contract guarantee).
  Future<ProxyUsage> getUsageSummary() async {
    _requireAuth();
    return ProxyUsage.fromJson(await _getJson('/v1/usage-summary'));
  }

  /// Register this install as a family device. 201 on first registration,
  /// 200 when the same install_id re-registers. 403 with code
  /// "DEVICE_LIMIT_REACHED" when the family's slots are full.
  Future<ProxyDeviceRegistration> registerDevice({
    required String installId,
    String? deviceName,
    String? platform,
  }) async {
    _requireAuth();
    final body = await _postJson('/v1/devices/register', {
      'install_id': installId,
      if (deviceName != null && deviceName.isNotEmpty)
        'device_name': deviceName,
      if (platform != null && platform.isNotEmpty) 'platform': platform,
    });
    return ProxyDeviceRegistration.fromJson(body);
  }

  /// List the family's registered devices and slot counts.
  Future<ProxyDeviceList> listDevices() async {
    _requireAuth();
    return ProxyDeviceList.fromJson(await _getJson('/v1/devices'));
  }

  /// Remove a device, freeing its slot. 404 → code "device_not_found".
  Future<void> deleteDevice(String installId) async {
    _requireAuth();
    await _deleteJson('/v1/devices/$installId');
  }
}

/// Secure storage for the proxy auth material: the bearer token, the
/// family id, and the profile ids. Like the ElevenLabs key, the token is a
/// billing credential: it lives in the platform keychain, never in
/// SharedPreferences, never in backups, never in logs.
///
/// The per-install [installId] also lives here (it is an install identity,
/// not an account secret, but the keychain is the right durable home for
/// it and keeps it out of backups). It survives sign-out.
class ProxyAuthStore {
  ProxyAuthStore({SecureValueStore? store})
    : _store = store ?? PlatformSecureValueStore();

  static const _tokenKey = 'vidavoice.proxy.token';
  static const _familyKey = 'vidavoice.proxy.familyId';
  static const _profilesKey = 'vidavoice.proxy.profileIds';
  static const _installKey = 'vidavoice.proxy.installId';

  final SecureValueStore _store;

  Future<String?> readToken() async {
    try {
      final token = await _store.read(_tokenKey);
      return (token == null || token.isEmpty) ? null : token;
    } catch (_) {
      return null;
    }
  }

  Future<String?> readFamilyId() async {
    try {
      return await _store.read(_familyKey);
    } catch (_) {
      return null;
    }
  }

  /// The server-issued profile ids from the last sign-in/sign-up. The
  /// proxy contract meters speech per profile_id, and only ids the server
  /// issued are valid there — local app profile ids are unrelated.
  Future<List<String>> readProfileIds() async {
    try {
      final raw = await _store.read(_profilesKey);
      if (raw == null || raw.isEmpty) return const [];
      final decoded = json.decode(raw);
      if (decoded is! List) return const [];
      return decoded.whereType<String>().toList();
    } catch (_) {
      return const [];
    }
  }

  Future<void> save(ProxyAuthResult result) async {
    await _store.write(_tokenKey, result.token);
    if (result.familyId.isNotEmpty) {
      await _store.write(_familyKey, result.familyId);
    }
    await _store.write(_profilesKey, json.encode(result.profileIds));
  }

  Future<void> clear() async {
    await _store.delete(_tokenKey);
    await _store.delete(_familyKey);
    await _store.delete(_profilesKey);
    // The install id is per-install, not per-account: keep it so a
    // re-sign-in re-registers the same device instead of burning a slot.
  }

  /// The install's stable UUID v4, generated once and kept forever.
  Future<String> installId() async {
    try {
      final existing = await _store.read(_installKey);
      if (existing != null && existing.isNotEmpty) return existing;
    } catch (_) {
      // Fall through and generate.
    }
    final id = proxyUuid4();
    try {
      await _store.write(_installKey, id);
    } catch (_) {
      // Best effort — the caller still gets a usable id for this call.
    }
    return id;
  }
}
