import 'dart:async';
import 'dart:convert';
import 'dart:math';
import 'dart:typed_data';

import 'package:http/http.dart' as http;

import 'elevenlabs_key_store.dart';

/// Base URL of the managed OneVoz voice backend.
///
/// PLACEHOLDER — MUST-REPLACE before any public build: the company domain
/// is TBD and this host has no DNS record, so a build pointed here fails
/// closed (which is correct) and can never reach a real backend. Override
/// Base URL of the managed OneVoz voice proxy. Overridable
/// per build without a code change:
///   flutter build ... --dart-define=VIDAVOICE_PROXY_URL=https://...
///
/// The proxy is live at https://voice.onevoz.me. The default below must
/// always be the live URL: shipping the old vidavoice.org placeholder
/// default silently breaks cloud voices (the app reports "Couldn't reach
/// the OneVoz service"). An unreachable proxy is still treated as
/// "offline": onboarding offers to continue with on-device voices, and
/// speech falls back to on-device voices. Nothing in the app may break
/// when the host doesn't resolve.
const kProxyBaseUrl = String.fromEnvironment(
  'VIDAVOICE_PROXY_URL',
  defaultValue: 'https://voice.onevoz.me',
);

/// Error from the managed voice proxy (or from reaching it).
///
/// [code] is the server's machine-readable error code when one was
/// provided (e.g. "email_taken", "quota_exceeded", "unauthorized") or a
/// client-side code ("unreachable", "bad_response").
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
    this.syncSalt,
  });

  final String token;
  final String familyId;
  final List<String> profileIds;

  /// Base64 per-family salt for deriving the end-to-end encrypted
  /// dashboard-sync key. Stable per family; null when the server predates
  /// the sync endpoints (callers fall back to GET /v1/sync/salt).
  final String? syncSalt;

  factory ProxyAuthResult.fromJson(Map<String, dynamic> json) {
    final token = json['token']?.toString() ?? '';
    if (token.isEmpty) {
      throw ProxyException(
        'The service returned an unexpected response.',
        code: 'bad_response',
      );
    }
    final rawIds = json['profile_ids'];
    final salt = json['sync_salt']?.toString();
    return ProxyAuthResult(
      token: token,
      familyId: json['family_id']?.toString() ?? '',
      profileIds: rawIds is List
          ? rawIds.map((e) => e.toString()).toList()
          : const [],
      syncSalt: (salt == null || salt.isEmpty) ? null : salt,
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
  ProxyDeviceRegistration({required this.device, required this.devicesUsed});

  final ProxyDevice device;
  final int devicesUsed;

  factory ProxyDeviceRegistration.fromJson(Map<String, dynamic> json) {
    final device = json['device'];
    return ProxyDeviceRegistration(
      device: device is Map<String, dynamic>
          ? ProxyDevice.fromJson(device)
          : ProxyDevice(installId: ''),
      devicesUsed: (json['devices_used'] as num?)?.toInt() ?? 0,
    );
  }
}

/// GET /v1/devices response.
class ProxyDeviceList {
  ProxyDeviceList({required this.devicesUsed, required this.devices});

  final int devicesUsed;
  final List<ProxyDevice> devices;

  factory ProxyDeviceList.fromJson(Map<String, dynamic> json) {
    final raw = json['devices'];
    return ProxyDeviceList(
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

/// HTTP client for the managed OneVoz voice backend.
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

  /// Background location uploads get a roomier budget than interactive
  /// calls: a ping that trips the 5s UI timeout on a slow link would show
  /// a scary "upload failed" even though the server is fine. These calls
  /// are best-effort and non-interactive, so waiting longer is strictly
  /// better than crying wolf.
  static const _locationTimeout = Duration(seconds: 25);

  /// POST [path], returning the decoded JSON body. Throws [ProxyException]
  /// on transport failure or any non-2xx status.
  Future<Map<String, dynamic>> _postJson(
    String path,
    Map<String, dynamic> body, {
    Duration? timeout,
  }) async {
    final uri = Uri.parse('$baseUrl$path');
    late http.Response res;
    try {
      res = await _client
          .post(uri, headers: _headers(), body: json.encode(body))
          .timeout(timeout ?? _timeout);
    } on TimeoutException {
      throw ProxyException(
        'The request timed out.',
        code: 'unreachable',
        fallbackAllowed: true,
      );
    } catch (_) {
      throw ProxyException(
        'Could not reach the OneVoz service.',
        code: 'unreachable',
        fallbackAllowed: true,
      );
    }
    return _decode(res);
  }

  /// PUT [path], returning the decoded JSON body. Throws [ProxyException]
  /// on transport failure or any non-2xx status. Used by the dashboard
  /// sync upload, which the contract defines as PUT (idempotent upsert).
  Future<Map<String, dynamic>> _putJson(
    String path,
    Map<String, dynamic> body, {
    Duration? timeout,
  }) async {
    final uri = Uri.parse('$baseUrl$path');
    late http.Response res;
    try {
      res = await _client
          .put(uri, headers: _headers(), body: json.encode(body))
          .timeout(timeout ?? _timeout);
    } on TimeoutException {
      throw ProxyException(
        'The request timed out.',
        code: 'unreachable',
        fallbackAllowed: true,
      );
    } catch (_) {
      throw ProxyException(
        'Could not reach the OneVoz service.',
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
        'Could not reach the OneVoz service.',
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
        'Could not reach the OneVoz service.',
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
      // Defensive: the contract promises an absolute URL, but resolve a
      // relative one against the proxy base so a server regression can
      // never break speech with a malformed-URL failure.
      final audioUri = Uri.parse(url);
      final resolved = audioUri.hasScheme
          ? audioUri
          : Uri.parse(baseUrl).resolveUri(audioUri);
      res = await _client
          .get(resolved, headers: _headers(jsonBody: false))
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
  /// 200 when the same install_id re-registers. There is no device cap.
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

  /// List the family's registered devices.
  Future<ProxyDeviceList> listDevices() async {
    _requireAuth();
    return ProxyDeviceList.fromJson(await _getJson('/v1/devices'));
  }

  /// Remove a device and revoke its access. 404 → code "device_not_found".
  Future<void> deleteDevice(String installId) async {
    _requireAuth();
    await _deleteJson('/v1/devices/$installId');
  }

  /// Register (or refresh) this install's push token for safe-zone
  /// alert fanout. The token is a routing endpoint only — it is never
  /// echoed back by the server. [role] is the device's caregiver/
  /// communicator role when known; the worker stores it so fanout can
  /// prefer caregiver devices (worker-side filtering).
  Future<void> registerPushToken({
    required String installId,
    required String fcmToken,
    required String platform,
    String? role,
  }) async {
    _requireAuth();
    await _postJson('/v1/devices/push-token', {
      'install_id': installId,
      'fcm_token': fcmToken,
      'platform': platform,
      'role': ?role,
    });
  }

  /// Remove this install's push token (sign-out). 404
  /// ("push_token_not_found") is a normal outcome when no token was
  /// registered — callers treat unregistration as best-effort.
  Future<void> deletePushToken(String installId) async {
    _requireAuth();
    await _deleteJson('/v1/devices/push-token/$installId');
  }

  // --------------------------------- dashboard sync (E2E encrypted) -----
  // The dashboard sync blob is END-TO-END ENCRYPTED on the device before
  // upload: it contains the family's AAC dashboard content (words and
  // phrases), which the server must never see in plaintext per the
  // no-content promise. The server stores the blob opaquely — it never
  // decrypts, inspects, logs, or returns anything but the stored bytes.
  // Key derivation (PBKDF2 from the caregiver password + per-family salt)
  // happens in DashboardSyncService; this client only moves bytes.

  /// The per-family base64 salt for the sync-key derivation. Stable per
  /// family — generated server-side on first request.
  Future<String> getSyncSalt() async {
    _requireAuth();
    final body = await _getJson('/v1/sync/salt');
    final salt = body['sync_salt']?.toString() ?? '';
    if (salt.isEmpty) {
      throw ProxyException(
        'The service returned an unexpected response.',
        code: 'bad_response',
      );
    }
    return salt;
  }

  /// Upload the encrypted dashboard blob via PUT (idempotent upsert per
  /// the contract). Returns the stored {version, updated_at}.
  Future<Map<String, dynamic>> putDashboardBlob({
    required String ciphertext,
    required String nonce,
    required int version,
  }) async {
    _requireAuth();
    return await _putJson('/v1/sync/dashboards', {
      'ciphertext': ciphertext,
      'nonce': nonce,
      'version': version,
    });
  }

  /// Download the encrypted dashboard blob, or null when the family has
  /// never synced (404/no_sync_data). Other errors are rethrown.
  Future<Map<String, dynamic>?> getDashboardBlob() async {
    _requireAuth();
    try {
      return await _getJson('/v1/sync/dashboards');
    } on ProxyException catch (e) {
      if (e.statusCode == 404 &&
          (e.code == 'no_sync_data' || e.code == 'not_found')) {
        return null;
      }
      rethrow;
    }
  }

  // ---- Phase 2A location sharing (E2E-encrypted; same no-content ----
  // ---- guarantee as dashboard sync: the server stores opaque blobs) ----

  /// Upload one encrypted position ping (last-write-wins). The payload is
  /// ciphertext the server never decrypts; [installId] identifies the
  /// sharing device. Throws [ProxyException] on transport/server errors —
  /// share sessions treat failures as best-effort and keep going.
  Future<void> putLocationLatest({
    required String installId,
    required String ciphertext,
    required String nonce,
    required int version,
  }) async {
    _requireAuth();
    await _putJson(
      '/v1/sync/location/latest',
      {
        'install_id': installId,
        'ciphertext': ciphertext,
        'nonce': nonce,
        'version': version,
      },
      timeout: _locationTimeout,
    );
  }

  /// Download the encrypted latest-position blob for [installId], or null
  /// when that device never shared (404). Other errors are rethrown.
  Future<Map<String, dynamic>?> getLocationLatest(String installId) async {
    _requireAuth();
    try {
      return await _getJson(
        '/v1/sync/location/latest?install_id=${Uri.encodeComponent(installId)}',
      );
    } on ProxyException catch (e) {
      if (e.statusCode == 404) return null;
      rethrow;
    }
  }

  /// Upload a batch of encrypted history points (≤500 per call). Each
  /// point is {ciphertext, nonce, ts}. Best-effort like [putLocationLatest].
  Future<void> postLocationPoints({
    required String installId,
    required List<Map<String, dynamic>> points,
  }) async {
    _requireAuth();
    await _postJson(
      '/v1/sync/location/points',
      {
        'install_id': installId,
        'points': points,
      },
      timeout: _locationTimeout,
    );
  }

  /// Download encrypted history points for [installId] in [since, until)
  /// (unix ms). Returns {'points': [...], 'next_before': ...} for paging.
  Future<Map<String, dynamic>> getLocationPoints({
    required String installId,
    required int since,
    required int until,
    int limit = 500,
  }) async {
    _requireAuth();
    final q = 'install_id=${Uri.encodeComponent(installId)}'
        '&since=$since&until=$until&limit=$limit';
    return await _getJson('/v1/sync/location/points?$q');
  }

  /// Post an alert event. [kind] is plaintext (routing only): 'sos',
  /// 'location_request', 'share_started', 'share_stopped'. Everything
  /// sensitive (coordinates, zone names) is inside [ciphertext]. [ts] is
  /// the event time in unix millis — the server rejects alerts without
  /// one, so it defaults to now when the caller doesn't have a better
  /// clock (the encrypted payload usually carries its own ts).
  Future<void> postAlert({
    required String installId,
    required String kind,
    required String ciphertext,
    required String nonce,
    int? ts,
    Map<String, String>? envelope,
  }) async {
    _requireAuth();
    await _postJson(
      '/v1/alerts',
      {
        'install_id': installId,
        'kind': kind,
        'ciphertext': ciphertext,
        'nonce': nonce,
        'ts': ts ?? DateTime.now().millisecondsSinceEpoch,
        // Optional opaque routing IDs (safe-zone fanout): the worker
        // validates their shape and passes them to push routing only —
        // never names or coordinates.
        'envelope': ?envelope,
      },
      timeout: _locationTimeout,
    );
  }

  /// List alert events since [sinceMs] (unix ms), newest last. Each item
  /// is {id, install_id, kind, ciphertext, nonce, ts}; content decrypts
  /// client-side with the family sync key.
  Future<List<Map<String, dynamic>>> getAlerts({required int sinceMs}) async {
    _requireAuth();
    final res = await _getJson('/v1/alerts?since=$sinceMs');
    final raw = res['alerts'];
    if (raw is! List) return const [];
    return [
      for (final e in raw)
        if (e is Map) Map<String, dynamic>.from(e),
    ];
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
  static const _syncKeyKey = 'vidavoice.proxy.syncKey';

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
    await _store.delete(_syncKeyKey);
    // The install id is per-install, not per-account: keep it so a
    // re-sign-in re-registers the same device instead of burning a slot.
  }

  /// The raw dashboard-sync key bytes, base64-encoded. A billing-adjacent
  /// secret: keychain only, never SharedPreferences, never logs. Written
  /// at sign-in (derived from the caregiver password + server salt),
  /// deleted at sign-out.
  Future<String?> readSyncKey() async {
    try {
      final key = await _store.read(_syncKeyKey);
      return (key == null || key.isEmpty) ? null : key;
    } catch (_) {
      return null;
    }
  }

  Future<void> writeSyncKey(String base64Key) async {
    await _store.write(_syncKeyKey, base64Key);
  }

  Future<void> deleteSyncKey() async {
    await _store.delete(_syncKeyKey);
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
