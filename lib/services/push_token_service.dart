import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

import 'device_role_service.dart';
import 'proxy_client.dart';

/// Source of the platform push token (FCM registration token; on iOS
/// the FCM SDK wraps the APNs token). Abstracted so the registration
/// lifecycle is testable and so the token vendor (Firebase, configured
/// in the native phase) can slot in without lifecycle changes.
abstract class PushTokenSource {
  /// The current token, or null when push is unavailable (no Firebase
  /// configuration yet, permission denied, web, tests).
  Future<String?> currentToken();

  /// Token rotations after the initial fetch.
  Stream<String> get tokenRefreshes;

  /// Asks the OS for notification permission. Returns the token when
  /// granted and available. Never throws.
  Future<String?> requestPermissionAndToken();
}

/// MethodChannel token source (channel `vidavoice/push`). Until the
/// native Firebase bridge lands, every call degrades to null —
/// registration simply waits, and the rest of the app is unaffected.
class MethodChannelPushTokenSource implements PushTokenSource {
  MethodChannelPushTokenSource({MethodChannel? channel})
      : _channel = channel ?? const MethodChannel(_channelName);

  static const _channelName = 'vidavoice/push';
  final MethodChannel _channel;
  final _refreshes = StreamController<String>.broadcast();

  /// Lazy handler registration (same binding-init rule as the
  /// geofence bridge): constructing this object in a bare unit test
  /// must not touch the binary messenger.
  bool _handlerReady = false;

  void _ensureHandler() {
    if (_handlerReady) return;
    _handlerReady = true;
    try {
      _channel.setMethodCallHandler((call) async {
        if (call.method == 'onTokenRefresh') {
          final args = call.arguments;
          if (args is Map) {
            final token = args['token']?.toString() ?? '';
            if (token.isNotEmpty) _refreshes.add(token);
          }
        }
        return null;
      });
    } catch (_) {
      // No binary messenger in this context (bare unit test): the
      // refresh stream simply never fires; current-token calls still
      // degrade to null below.
    }
  }

  @override
  Future<String?> currentToken() async {
    _ensureHandler();
    try {
      final token = await _channel.invokeMethod<String>('getToken');
      return (token == null || token.isEmpty) ? null : token;
    } catch (_) {
      return null;
    }
  }

  @override
  Stream<String> get tokenRefreshes {
    _ensureHandler();
    return _refreshes.stream;
  }

  @override
  Future<String?> requestPermissionAndToken() async {
    _ensureHandler();
    try {
      final token =
          await _channel.invokeMethod<String>('requestPermission');
      return (token == null || token.isEmpty) ? null : token;
    } catch (_) {
      return null;
    }
  }
}

/// Keeps this install's push-token registration in step with the
/// session lifecycle:
///
/// - signed in + token available → registered (with the device role,
///   so alert fanout can prefer caregiver devices);
/// - token rotation → re-registered;
/// - role change → re-registered;
/// - sign-out / revocation → unregistered (best-effort, while the
///   session token is still valid).
///
/// Tokens are routing endpoints and are treated as secret-grade: they
/// are sent only to our own worker and never logged. Every failure is
/// silent — push delivery must never block AAC communication or
/// sign-out.
class PushTokenService {
  PushTokenService({
    required this._proxy,
    required this._proxyAuth,
    required this._role,
    PushTokenSource? source,
    String Function()? platformName,
  })  : _source = source ?? MethodChannelPushTokenSource(),
        _platformName = platformName ?? _defaultPlatformName;

  final ProxyClient _proxy;
  final ProxyAuthStore _proxyAuth;

  /// The device's current role, or null before the role question is
  /// answered. Read fresh at every registration.
  final DeviceRole? Function() _role;
  final PushTokenSource _source;
  final String Function() _platformName;

  StreamSubscription<String>? _refreshSub;
  String? _registeredToken;

  /// The install id resolved during registration. Cached so
  /// unregistration can issue its DELETE immediately — no keychain
  /// await between "sign out" and the request leaving.
  String? _installId;
  bool _started = false;

  static String _defaultPlatformName() {
    if (kIsWeb) return 'web';
    return switch (defaultTargetPlatform) {
      TargetPlatform.iOS => 'ios',
      TargetPlatform.android => 'android',
      _ => 'web',
    };
  }

  /// Begins the lifecycle: registers the current token and follows
  /// rotations. Idempotent. Never throws (mirrors the geofence
  /// service: lifecycle hooks run inside session flows that must not
  /// fail on push bookkeeping).
  Future<void> start() async {
    if (_started) return;
    _started = true;
    try {
      _refreshSub = _source.tokenRefreshes.listen((token) {
        unawaited(_register(token));
      });
      final token = await _safeCurrentToken();
      if (token != null) await _register(token);
    } catch (_) {}
  }

  /// Re-registers with the current role (call after the device role is
  /// chosen or changed). A no-op before [start] or when push is
  /// unavailable.
  Future<void> refreshRegistration() async {
    if (!_started) return;
    final token = await _safeCurrentToken();
    if (token != null) await _register(token, force: true);
  }

  /// Ends the lifecycle. With [unregister] (sign-out, revocation),
  /// deletes the server-side registration first — while the session
  /// token is still valid — so a signed-out device stops receiving
  /// family alerts. All failures are swallowed: sign-out must never
  /// block on push bookkeeping.
  Future<void> stop({bool unregister = false}) async {
    _started = false;
    // Issue the DELETE before awaiting anything else: it must leave
    // with the still-valid session token.
    final pending = unregister ? _unregister() : null;
    // Subscription cleanup is local bookkeeping only. Don't await it:
    // a stream whose completion is timer-driven can starve a caller
    // that is itself being awaited (notably sign-out in tests).
    final sub = _refreshSub;
    _refreshSub = null;
    if (sub != null) unawaited(sub.cancel());
    await pending;
    _registeredToken = null;
    _installId = null;
  }

  Future<void> _unregister() async {
    try {
      if (!_proxy.hasToken) return;
      final id = _installId ?? await _proxyAuth.installId();
      await _proxy.deletePushToken(id);
    } catch (_) {
      // 404 (never registered) and network failures are both fine.
    }
  }

  Future<String?> _safeCurrentToken() async {
    try {
      return await _source.currentToken();
    } catch (_) {
      return null;
    }
  }

  Future<void> _register(String token, {bool force = false}) async {
    if (!force && token == _registeredToken) return;
    try {
      if (!_proxy.hasToken) return;
      _installId ??= await _proxyAuth.installId();
      await _proxy.registerPushToken(
        installId: _installId!,
        fcmToken: token,
        platform: _platformName(),
        role: _role()?.name,
      );
      _registeredToken = token;
    } catch (_) {
      // Registration retries on the next rotation / refresh call.
    }
  }
}
