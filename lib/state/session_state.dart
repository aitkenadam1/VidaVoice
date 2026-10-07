import 'package:flutter/foundation.dart';
import 'package:flutter/semantics.dart';
import 'package:flutter/widgets.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'dart:async';
import 'dart:convert';

import '../app_config.dart';
import '../models/dashboard.dart';
import '../models/word.dart';
import '../services/dashboard_service.dart';
import '../services/dashboard_sync_service.dart';
import '../services/caregiver_pin_service.dart';
import '../services/device_role_service.dart';
import '../services/elevenlabs_key_store.dart';
import '../services/elevenlabs_service.dart';
import '../services/elevenlabs_voice_store.dart';
import '../services/language_pack_service.dart';
import '../services/location_service.dart';
import '../services/location_share_service.dart';
import '../services/profile_service.dart';
import '../services/proxy_client.dart';
import '../services/symbol_override_service.dart';
import '../services/symbol_service.dart';
import '../services/tts_service.dart';
import '../services/kokoro_tts_service.dart';
import '../services/usage_service.dart';
import '../services/history_service.dart';
import '../services/prediction_service.dart';
import '../services/nudge_service.dart';
import '../services/first_week_plan_service.dart';

enum BootStatus { loading, ready, error }

/// App-wide session state: current language pack, sentence under
/// construction, TTS voice settings, symbols, profiles, onboarding flag.
class SessionState extends ChangeNotifier {
  /// Test seam: inject fakes so widget tests can boot a [SessionState]
  /// without touching platform channels (SharedPreferences / flutter_tts).
  /// Production always uses the default — no behavior change.
  SessionState({
    Future<SharedPreferences> Function()? prefsFactory,
    TtsService? tts,
    ElevenLabsKeyStore? elevenLabsKeys,
    ProxyClient? proxy,
    ProxyAuthStore? proxyAuth,
    CaregiverPinService? caregiverPin,
    DeviceRoleService? deviceRoleService,
    DateTime Function()? nudgeClock,
  }) : _prefsFactory = prefsFactory ?? SharedPreferences.getInstance,
       tts = tts ?? TtsService(),
       elevenLabsKeys = elevenLabsKeys ?? ElevenLabsKeyStore(),
       proxy = proxy ?? ProxyClient(),
       proxyAuth = proxyAuth ?? ProxyAuthStore(),
       caregiverPin = caregiverPin ?? CaregiverPinService(),
       deviceRoleService = deviceRoleService ?? DeviceRoleService(),
       nudge = ModeNudgeService(clock: nudgeClock) {
    // The managed-voice branch of TtsService.speak needs the server-issued
    // profile id (the proxy contract requires profile_id per request) and
    // the shared proxy client. Wired once here so every speak path —
    // board taps, dashboard cells, sentence replay — routes the same way.
    //
    // NOTE: only ids the server issued at auth are valid as profile_id.
    // The app's local profile ids are unrelated UUIDs the server never
    // issued, so they must never be sent. Until the proxy contract defines
    // a local↔server child-profile mapping, speech meters against the
    // family's first server profile id (created at signup); with no known
    // server id the TTS falls back to on-device voices.
    this.tts.proxy = this.proxy;
    this.tts.proxyProfileIdProvider = () =>
        _serverProfileIds.isNotEmpty ? _serverProfileIds.first : null;
    // The speech path calls proxy.synthesize directly (it must never throw
    // past the UI), so a 401 there bypasses _authed. It degrades the voice
    // (see handleProxySessionExpired) — it must never sign the device out
    // from under a communicator mid-conversation.
    this.tts.onProxyUnauthorized = () => handleProxySessionExpired();
    dashboardSync = DashboardSyncService(
      proxy: this.proxy,
      profiles: profiles,
      dashboards: dashboards,
      prefsFactory: _prefsFactory,
    );
    locationShare = LocationShareService(
      proxy: this.proxy,
      proxyAuth: this.proxyAuth,
      profiles: profiles,
      dashboardSync: dashboardSync,
      gps: locationService,
      prefsFactory: _prefsFactory,
    );
    locationShare.addListener(notifyListeners);
  }

  final Future<SharedPreferences> Function() _prefsFactory;
  final TtsService tts;
  final SymbolService symbols = SymbolService();
  final ProfileService profiles = ProfileService();
  final UsageService usage = UsageService();
  final HistoryService history = HistoryService();

  /// On-device Type-mode prediction ranks, per profile. Learned ONLY from
  /// intentionally-spoken messages, and only while the profile's
  /// predictionEnabled is true. See [setPredictionEnabled],
  /// [resetLearningFor], and [clearHistoryFor].
  final PredictionService prediction = PredictionService();

  /// Phase 5: caregiver progression-nudge eligibility counters. Local,
  /// counts-only, never changes the profile's mode.
  final ModeNudgeService nudge;

  final FirstWeekPlanService plan = FirstWeekPlanService();
  final DashboardService dashboards = DashboardService();
  final SymbolOverrideService symbolOverrides = SymbolOverrideService();

  /// The caregiver's own ElevenLabs API key (secure storage) and the
  /// per-profile saved cloud voices. Null key = cloud voices unavailable.
  final ElevenLabsKeyStore elevenLabsKeys;
  final ElevenLabsVoiceStore elevenLabsVoices = ElevenLabsVoiceStore();

  /// The managed voice backend client (caregiver account, cloud voices,
  /// device management). Constructor-injectable for tests.
  final ProxyClient proxy;

  /// Secure storage for the proxy token / family id / install id.
  final ProxyAuthStore proxyAuth;

  /// Device-local caregiver gate PIN for the caregiver hub. Injectable
  /// for tests; production uses the platform keychain.
  final CaregiverPinService caregiverPin;

  /// Which side of the family this device serves (communicator boards
  /// vs. the Caregiver Portal). Injectable for tests; production uses the
  /// platform keychain. Null until the first-launch role question is
  /// answered.
  final DeviceRoleService deviceRoleService;

  /// The device's role, loaded at boot. Null means "not chosen yet" — the
  /// router shows the role-selection screen.
  DeviceRole? deviceRole;

  /// One-shot request for which Caregiver Portal tab to open. Set by the
  /// discreet communicator-side entry (e.g. "Continue as caregiver" from
  /// the no-contacts sheet asks for the Safety tab). Consumed and cleared
  /// by CaregiverPortalScreen.initState; null means the default tab.
  /// Never persisted — a transient UI hint only.
  int? pendingPortalTab;

  /// End-to-end encrypted dashboard + profile sync across the family's
  /// devices. Initialized in the constructor; wired (change listeners,
  /// first pull) in [boot].
  late final DashboardSyncService dashboardSync;

  /// Phase 2A GPS. Production default; widget tests inject
  /// [NoopLocationService] into screens directly so they stay hermetic.
  final LocationService locationService = const GpsLocationService();

  /// Phase 2A on-demand location sharing (caregiver opt-in per profile).
  /// Initialized in the constructor; polling starts after sign-in.
  late final LocationShareService locationShare;

  /// True when a proxy token is in hand (restored from secure storage on
  /// boot, or freshly signed in). The token is validated lazily on first
  /// use — a 401 signs out silently.
  bool proxySignedIn = false;

  /// The family id from the last successful auth, if known.
  String? proxyFamilyId;

  /// Server-issued profile ids from the last auth (see the constructor
  /// note: the first is used as the speech profile_id).
  List<String> _serverProfileIds = const [];

  /// Set when device registration hit the family's device cap: the
  /// server's caregiver-readable message, shown once in the device
  /// section. Null otherwise.
  String? deviceLimitNotice;

  /// True when the last device registration hit the family's device cap.
  /// The session stays signed in (the token is needed to list and remove
  /// devices) but the app shows the blocking device-license screen instead
  /// of the home board until a slot is freed.
  bool deviceLicenseBlocked = false;

  BootStatus status = BootStatus.loading;
  String bootError = '';
  String currentLocale = AppConfig.defaultLocale;

  /// False when the device has no TTS engine or voice data. The board still
  /// boots — only the voice is missing, and the UI says so with a banner.
  bool ttsAvailable = true;

  /// The "no voice" banner is dismissible per session.
  bool ttsBannerDismissed = false;

  void dismissTtsBanner() {
    ttsBannerDismissed = true;
    notifyListeners();
  }

  late LanguagePack pack;

  final List<String> _sentenceIds = [];
  List<String> get sentenceIds => List.unmodifiable(_sentenceIds);
  List<BoardItem> get sentence =>
      _sentenceIds.map((id) => pack.wordById(id)).toList();

  double buttonScale = 1.0;
  bool onboardingComplete = false;

  /// The caregiver-set image (base64) for [itemId] on the active profile,
  /// or null when the standard symbol applies. Keeps board call sites to
  /// one lookup.
  String? symbolOverrideFor(String itemId) {
    final id = profiles.active?.id;
    if (id == null) return null;
    return symbolOverrides.imageFor(id, itemId);
  }

  /// Tell listeners the symbol overrides changed so boards re-read them.
  void symbolsChanged() => notifyListeners();

  /// Highest vocabulary level currently revealed on the board (1-3).
  ///
  /// Caregiver-controlled, and deliberately NOT in Settings: revealing
  /// vocabulary is a clinical decision, not a preference. Raising it only ever
  /// fills in empty cells — no word already on the board moves.
  int unlockedLevel = LanguagePack.minSupportedLevel;

  /// Whether the active profile's personal dashboard replaces the home
  /// board. An enabled but empty dashboard never takes over — the user
  /// must never be stranded on a blank board.
  bool get showDashboard {
    if (_dashboardBypassed) return false;
    final id = profiles.active?.id;
    if (id == null) return false;
    final dashboard = dashboards.forProfile(id);
    return dashboard != null && dashboard.enabled && dashboard.cells.isNotEmpty;
  }

  /// Session-only escape hatch: the communicator asked for the full board.
  /// The caregiver's enable/disable setting is untouched and rules again
  /// on profile switch, language switch, or next boot. [restoreDashboard]
  /// brings the dashboard back within the session.
  bool _dashboardBypassed = false;

  void bypassDashboard() {
    _dashboardBypassed = true;
    notifyListeners();
  }

  void restoreDashboard() {
    _dashboardBypassed = false;
    notifyListeners();
  }

  /// True when the dashboard is bypassed but still available to return to.
  bool get canRestoreDashboard {
    if (!_dashboardBypassed) return false;
    final id = profiles.active?.id;
    if (id == null) return false;
    final dashboard = dashboards.forProfile(id);
    return dashboard != null && dashboard.enabled && dashboard.cells.isNotEmpty;
  }

  SharedPreferences? _prefs;

  Future<void> boot() async {
    status = BootStatus.loading;
    notifyListeners();
    try {
      _prefs = await _prefsFactory();
      final savedLocale = _prefs!.getString('vidavoice.locale');
      currentLocale =
          (savedLocale != null &&
              AppConfig.supportedLocales.contains(savedLocale))
          ? savedLocale
          : AppConfig.defaultLocale;
      buttonScale = _prefs!.getDouble('vidavoice.buttonScale') ?? 1.0;
      onboardingComplete =
          _prefs!.getBool('vidavoice.onboardingComplete') ?? false;
      // Restore the proxy session best-effort: a stored token means the
      // caregiver signed in before. The token is validated lazily on first
      // use (a 401 signs out silently) — never a boot failure.
      try {
        final token = await proxyAuth.readToken();
        if (token != null && token.isNotEmpty) {
          proxy.setToken(token);
          proxySignedIn = true;
          proxyFamilyId = await proxyAuth.readFamilyId();
          _serverProfileIds = await proxyAuth.readProfileIds();
        }
      } catch (_) {}
      // A restored session for a family that already has profiles means
      // setup happened: don't re-run the wizard just because the local
      // "done" flag was wiped (same reasoning as signIn above).
      if (proxySignedIn &&
          _serverProfileIds.isNotEmpty &&
          !onboardingComplete) {
        onboardingComplete = true;
        await _prefs!.setBool('vidavoice.onboardingComplete', true);
      }
      unlockedLevel = _clampLevel(
        _prefs!.getInt('vidavoice.unlockedLevel') ??
            LanguagePack.minSupportedLevel,
      );
      // The device role is per-device secure storage. Best-effort like
      // the proxy session: a read failure asks the question again rather
      // than failing boot.
      try {
        deviceRole = await deviceRoleService.readRole();
      } catch (_) {
        deviceRole = null;
      }

      pack = await LanguagePackService.loadPack(currentLocale);
      // Throws PackValidationError on any violation — boot must fail fast.
      pack.validate();
      await symbols.load();
      await profiles.load();
      await dashboards.load();
      // Heal pre-fallback cells (stored with wordId but no label) while
      // their words still resolve — see DashboardService.backfillLabels.
      await dashboards.backfillLabels(pack);
      _wireDashboardSync();
      await symbolOverrides.load();
      await usage.load();
      await history.load(profiles.active?.id ?? '');
      await prediction.load(profiles.active?.id ?? '');
      // Phase 5: nudge counters are profile-agnostic (all profiles in one
      // blob), so a single load covers profile switches too.
      await nudge.load();
      await plan.load(profiles.active?.id ?? '');
      // Wire the ElevenLabs cloud backend when the caregiver entered an API
      // key. Best-effort like TTS itself: a missing key only means cloud
      // voices are unavailable, never a boot failure.
      await refreshElevenLabs();
      // TTS is best-effort and NEVER fails boot: a device with no voice
      // engine (bare Fire tablet, missing voice data) still gets the full
      // board, plus a banner explaining the missing voice.
      ttsBannerDismissed = false;
      try {
        ttsAvailable = await tts.init(
          language: pack.ttsLocale,
          rate:
              _prefs!.getDouble('vidavoice.speechRate') ??
              AppConfig.defaultSpeechRate,
          pitch:
              _prefs!.getDouble('vidavoice.speechPitch') ??
              AppConfig.defaultSpeechPitch,
        );
      } catch (_) {
        ttsAvailable = false;
      }
      // Restore the caregiver's voice choice for this language, if the
      // engine still has that voice installed.
      await _applySavedVoice();
      // Converge with the family's synced dashboards in the background.
      // Never fails boot: the device keeps working with local state.
      if (proxySignedIn) {
        unawaited(_backgroundSyncPull());
      }
      status = BootStatus.ready;
    } catch (e) {
      status = BootStatus.error;
      bootError = e.toString();
    }
    notifyListeners();
  }

  /// Wires the dashboard sync engine once: local dashboard/profile changes
  /// schedule a debounced encrypted push (only after the first pull —
  /// see [DashboardSyncService.autoPushEnabled]).
  bool _syncWired = false;

  void _wireDashboardSync() {
    if (_syncWired) return;
    _syncWired = true;
    dashboardSync.onChanged = notifyListeners;
    unawaited(dashboardSync.loadPersisted());
    dashboards.onChanged = () => dashboardSync.schedulePush();
    profiles.onChanged = () => dashboardSync.schedulePush();
  }

  /// Background converge after boot with a cached session: re-register
  /// this device (refreshes last-seen, catches a device-cap change),
  /// pull the family's blob, merge, then allow auto-push. Sync never
  /// fails boot.
  Future<void> _backgroundSyncPull() async {
    try {
      // Best-effort: a failure here must not block the dashboard sync.
      await _registerDevice();
      final keyB64 = await proxyAuth.readSyncKey();
      if (keyB64 == null || keyB64.isEmpty) return;
      dashboardSync.setKey(base64.decode(keyB64));
      locationShare.beginPolling();
      final result = await dashboardSync.pullNow();
      if (result.changed) {
        await dashboards.backfillLabels(pack);
        await reloadProfileData();
        notifyListeners();
      }
    } catch (_) {
      // Local state stays as-is; the caregiver can retry from Device sync.
    } finally {
      // A failed first pull must not disable auto-push forever: local
      // edits should still converge once connectivity returns.
      dashboardSync.autoPushEnabled = true;
      // Registration may have flipped the device-license block; make
      // sure the router rebuilds.
      notifyListeners();
    }
  }

  Future<void> setSpeechRate(double rate) async {
    await tts.setRate(rate);
    await _prefs?.setDouble('vidavoice.speechRate', rate);
  }

  Future<void> setSpeechPitch(double pitch) async {
    await tts.setPitch(pitch);
    await _prefs?.setDouble('vidavoice.speechPitch', pitch);
  }

  /// (Re)reads the ElevenLabs API key from secure storage and wires the
  /// cloud backend into [tts]. Call after the key is saved or cleared.
  /// Never throws: without a key the backend is simply unavailable.
  Future<void> refreshElevenLabs() async {
    try {
      final key = await elevenLabsKeys.readKey();
      tts.elevenLabs = (key == null || key.isEmpty)
          ? null
          : ElevenLabsService(apiKey: key);
    } catch (_) {
      tts.elevenLabs = null;
    }
    notifyListeners();
  }

  // ------------------------------------------------- managed voice proxy ---

  /// Create a caregiver account on the managed backend and sign in.
  /// Throws [ProxyException] with the server's code on failure
  /// ("email_taken", "weak_password", "unreachable", ...).
  Future<void> signUp({
    required String email,
    required String username,
    required String password,
  }) async {
    deviceLimitNotice = null;
    final result = await proxy.signup(
      email: email,
      username: username,
      password: password,
    );
    await _afterProxyAuth(result);
    await _setupSyncKey(result, password);
  }

  /// Sign in with email or username. Throws [ProxyException] on failure.
  ///
  /// A login is always to an existing family, so when the server reports
  /// profiles, first-time setup already happened and the onboarding wizard
  /// is skipped: its "done" flag lives in local storage, which the OS or
  /// browser can wipe (e.g. Safari "Clear History and Website Data") while
  /// the account — and its profiles — still exist. Re-asking "who will
  /// use the app" on every fresh device or data wipe is wrong; the
  /// server's profile list is the source of truth. A brand-new signup
  /// keeps the wizard: naming the child happens there.
  Future<void> signIn({
    required String identifier,
    required String password,
  }) async {
    deviceLimitNotice = null;
    final result = await proxy.login(
      identifier: identifier,
      password: password,
    );
    await _afterProxyAuth(result);
    await _setupSyncKey(result, password);
    if (result.profileIds.isNotEmpty && !onboardingComplete) {
      await setOnboardingComplete(true);
    }
  }

  /// Derives the dashboard-sync key from the password the caregiver just
  /// typed and converges with the family's synced state (pull, then push
  /// local state). Best-effort: sync failures never fail sign-in.
  Future<void> _setupSyncKey(ProxyAuthResult result, String password) async {
    try {
      final salt = result.syncSalt ?? await proxy.getSyncSalt();
      final key = await DashboardSyncService.deriveSyncKey(password, salt);
      await proxyAuth.writeSyncKey(base64.encode(key));
      dashboardSync.setKey(key);
      await dashboardSync.loadPersisted();
      final syncResult = await dashboardSync.syncNow();
      if (syncResult.changed) {
        await dashboards.backfillLabels(pack);
        await reloadProfileData();
        notifyListeners();
      }
    } catch (_) {
      // The account works without sync; the caregiver can retry from the
      // Device sync section.
    } finally {
      // A failed first sync must not disable auto-push forever: local
      // edits should still converge once connectivity returns.
      dashboardSync.autoPushEnabled = true;
    }
  }

  /// Common post-auth: persist the token, register this install as a
  /// family device (best-effort), and clear any earlier account deferral.
  Future<void> _afterProxyAuth(ProxyAuthResult result) async {
    proxy.setToken(result.token);
    proxySignedIn = true;
    proxyFamilyId = result.familyId;
    _serverProfileIds = List<String>.of(result.profileIds);
    deviceLimitNotice = null;
    deviceLicenseBlocked = false;
    try {
      await proxyAuth.save(result);
    } catch (_) {}
    await _registerDevice();
    locationShare.beginPolling();
    notifyListeners();
  }

  /// Registers this install as a family device. Best-effort: an offline
  /// device still gets a working account. On DEVICE_LIMIT_REACHED the
  /// session stays signed in but [deviceLicenseBlocked] is set, so the UI
  /// shows the blocking device-license screen instead of the home board.
  Future<void> _registerDevice() async {
    try {
      final installId = await proxyAuth.installId();
      await _authed(
        () => proxy.registerDevice(
          installId: installId,
          deviceName: _deviceName(),
          platform: kIsWeb ? 'web' : defaultTargetPlatform.name,
        ),
      );
      deviceLicenseBlocked = false;
      deviceLimitNotice = null;
    } on ProxyException catch (e) {
      if (e.code == 'DEVICE_LIMIT_REACHED') {
        deviceLicenseBlocked = true;
        deviceLimitNotice = e.message;
      }
    } catch (_) {}
  }

  /// Re-runs device registration — used by the device-license screen after
  /// the caregiver frees a slot. Clears the block on success.
  Future<void> retryDeviceRegistration() async {
    await _registerDevice();
    notifyListeners();
  }

  /// Human-readable device name sent at registration, so caregivers can
  /// tell their devices apart in the device list.
  String _deviceName() {
    if (kIsWeb) return 'web browser';
    switch (defaultTargetPlatform) {
      case TargetPlatform.iOS:
        return 'iOS device';
      case TargetPlatform.android:
        return 'Android device';
      case TargetPlatform.macOS:
        return 'macOS device';
      case TargetPlatform.windows:
        return 'Windows device';
      case TargetPlatform.linux:
        return 'Linux device';
      case TargetPlatform.fuchsia:
        return 'Fuchsia device';
    }
  }

  /// A proxy 401 (expired or rejected family token) degrades cloud
  /// features — it never signs the device out. Signing out from under a
  /// communicator would strand them on the role question, and account or
  /// cloud trouble must never block AAC communication. Instead: drop the
  /// in-memory token so cloud features stop presenting as live, forget
  /// the cloud-voice choice so speech honestly falls back to on-device
  /// voices, and keep the session, the device role, and every cached
  /// board. A caregiver restores cloud access by signing in again from
  /// the Portal; a revoked device simply never gets cloud access back,
  /// while its cached boards keep working.
  Future<void> handleProxySessionExpired() async {
    if (!proxy.hasToken) return; // already degraded — stay quiet
    proxy.setToken(null);
    _entitlementVoices = null;
    _entitlementFetched = null;
    if (tts.currentVoice?.isProxy ?? false) {
      await clearVoice();
    }
    notifyListeners();
  }

  /// Sign out of the managed backend: drop the token (secure storage too)
  /// and forget any proxy voice choice. The install id is kept so a
  /// re-sign-in re-registers the same device instead of burning a slot.
  Future<void> signOut() async {
    proxy.setToken(null);
    proxySignedIn = false;
    proxyFamilyId = null;
    _serverProfileIds = const [];
    deviceLimitNotice = null;
    deviceLicenseBlocked = false;
    _entitlementVoices = null;
    _entitlementFetched = null;
    dashboardSync.clearKey();
    locationShare.stopPolling();
    try {
      await locationShare.stopSession(quiet: true);
    } catch (_) {}
    try {
      await proxyAuth.clear();
    } catch (_) {}
    // The role question belongs to the device setup for this account — a
    // different family signing in must be asked again. Best-effort and
    // non-blocking: a wedged keychain must never stall sign-out. The
    // in-memory role is already cleared, so the worst case is the role
    // question reappearing on next launch (the safe direction).
    deviceRole = null;
    unawaited(deviceRoleService.clearRole().then((_) {}, onError: (_) {}));
    // A tab deep-link from before sign-out must not survive into the next
    // family's session.
    pendingPortalTab = null;
    if (tts.currentVoice?.isProxy ?? false) {
      await clearVoice();
    }
    notifyListeners();
  }

  /// Run a proxy call, degrading cloud features when the token is
  /// rejected. A 401 drops the in-memory token (see
  /// [handleProxySessionExpired]) but never signs the device out —
  /// listeners are still notified so the UI reflects the degraded state.
  Future<T> _authed<T>(Future<T> Function() call) async {
    try {
      return await call();
    } on ProxyException catch (e) {
      if (e.code == 'unauthorized') await handleProxySessionExpired();
      rethrow;
    }
  }

  List<ProxyVoice>? _entitlementVoices;
  DateTime? _entitlementFetched;
  static const _entitlementTtl = Duration(seconds: 60);

  /// The family's cloud voices, cached briefly in memory. Throws
  /// [ProxyException] on failure (an "unauthorized" first degrades the
  /// session via [_authed]; it never signs the device out).
  Future<List<ProxyVoice>> proxyEntitlement({bool force = false}) async {
    final now = DateTime.now();
    if (!force &&
        _entitlementVoices != null &&
        _entitlementFetched != null &&
        now.difference(_entitlementFetched!) < _entitlementTtl) {
      return _entitlementVoices!;
    }
    final entitlement = await _authed(() => proxy.getEntitlement());
    _entitlementVoices = entitlement.voices;
    _entitlementFetched = now;
    return entitlement.voices;
  }

  /// Quota and request counts for the current period, or null when the
  /// service can't be reached. Never throws.
  Future<ProxyUsage?> proxyUsage() async {
    try {
      return await _authed(() => proxy.getUsageSummary());
    } on ProxyException {
      return null;
    }
  }

  /// The family's registered devices and slot counts. Throws
  /// [ProxyException] on failure.
  Future<ProxyDeviceList> proxyDevices() => _authed(() => proxy.listDevices());

  /// Remove a device, freeing its slot. Throws [ProxyException] on failure.
  Future<void> removeProxyDevice(String installId) =>
      _authed(() => proxy.deleteDevice(installId));

  /// Saved ElevenLabs voices for the active profile, as picker entries.
  Future<List<TtsVoice>> elevenLabsVoiceEntries() async {
    final id = profiles.active?.id;
    if (id == null) return const [];
    final saved = await elevenLabsVoices.load(id);
    final prefix = currentLocale.toLowerCase();
    final matching = saved
        .where((v) => v.locale.toLowerCase().startsWith(prefix))
        .toList();
    final list = matching.isNotEmpty ? matching : saved;
    return [
      for (final v in list)
        TtsVoice(name: v.name, locale: v.locale, elevenLabsVoiceId: v.id),
    ];
  }

  /// Engine voices for the current language, for the voice picker. Empty
  /// when TTS is unavailable. Falls back to the full engine list when no
  /// voice reports a matching locale (some engines report bare tags).
  /// Kokoro on-device neural voices are listed first when the model pack
  /// is downloaded.
  Future<List<TtsVoice>> loadVoices() async {
    if (!ttsAvailable) return const [];
    final all = await tts.getVoices();
    final prefix = currentLocale.toLowerCase();
    final matching = all
        .where((v) => v.locale.toLowerCase().startsWith(prefix))
        .toList();
    final system = matching.isNotEmpty ? matching : all;
    final kokoro = await _kokoroVoicesForLocale();
    final elevenLabs = await elevenLabsVoiceEntries();
    return [...kokoro, ...elevenLabs, ...system];
  }

  /// The on-device neural TTS backend (for the Settings download UI).
  KokoroTtsService get kokoro => tts.kokoro;

  /// Kokoro voices for [currentLocale] as picker entries. Empty when the
  /// platform can't run Kokoro (web) or the model pack isn't downloaded.
  Future<List<TtsVoice>> _kokoroVoicesForLocale() async {
    if (!KokoroTtsService.isSupported) return const [];
    if (!await tts.kokoro.isModelReady()) return const [];
    return kokoroVoices
        .where((v) => v.locale == currentLocale)
        .map(
          (v) => TtsVoice(
            name: 'Kokoro ${v.displayName}',
            locale: kokoroLocaleTag(v.locale),
            kokoroVoiceId: v.id,
          ),
        )
        .toList();
  }

  TtsVoice? get currentVoice => tts.currentVoice;

  String _voiceNameKey(String locale) => 'vidavoice.voice.$locale.name';
  String _voiceLocaleKey(String locale) => 'vidavoice.voice.$locale.locale';
  String _voiceKokoroKey(String locale) => 'vidavoice.voice.$locale.kokoro';
  String _voiceElevenLabsKey(String locale) =>
      'vidavoice.voice.$locale.elevenlabs';
  String _voiceProxyKey(String locale) => 'vidavoice.voice.$locale.proxy';

  /// Persist and apply a voice choice for the current language.
  Future<void> setVoice(TtsVoice voice) async {
    await tts.setVoice(voice);
    await _prefs?.setString(_voiceNameKey(currentLocale), voice.name);
    await _prefs?.setString(_voiceLocaleKey(currentLocale), voice.locale);
    final kokoroId = voice.kokoroVoiceId;
    if (kokoroId != null) {
      await _prefs?.setString(_voiceKokoroKey(currentLocale), kokoroId);
      // Warm the engine now so the first real utterance isn't slow.
      unawaited(tts.kokoro.warmup());
    } else {
      await _prefs?.remove(_voiceKokoroKey(currentLocale));
    }
    final elevenId = voice.elevenLabsVoiceId;
    if (elevenId != null) {
      await _prefs?.setString(_voiceElevenLabsKey(currentLocale), elevenId);
    } else {
      await _prefs?.remove(_voiceElevenLabsKey(currentLocale));
    }
    final proxyId = voice.proxyVoiceId;
    if (proxyId != null) {
      await _prefs?.setString(_voiceProxyKey(currentLocale), proxyId);
    } else {
      await _prefs?.remove(_voiceProxyKey(currentLocale));
    }
    notifyListeners();
  }

  /// Back to the engine default voice for the current language.
  Future<void> clearVoice() async {
    await tts.clearVoice();
    await _prefs?.remove(_voiceNameKey(currentLocale));
    await _prefs?.remove(_voiceLocaleKey(currentLocale));
    await _prefs?.remove(_voiceKokoroKey(currentLocale));
    await _prefs?.remove(_voiceElevenLabsKey(currentLocale));
    await _prefs?.remove(_voiceProxyKey(currentLocale));
    notifyListeners();
  }

  /// Re-applies the saved voice for [currentLocale], if the engine still
  /// has it. Returns true when a saved voice was applied. Best-effort: a
  /// missing or rejected voice keeps the default.
  Future<bool> _applySavedVoice() async {
    if (!ttsAvailable) return false;
    try {
      final name = _prefs?.getString(_voiceNameKey(currentLocale));
      final locale = _prefs?.getString(_voiceLocaleKey(currentLocale));
      if (name == null || locale == null) return false;
      // Kokoro voices aren't in the engine list — restore from the table.
      final kokoroId = _prefs?.getString(_voiceKokoroKey(currentLocale));
      if (kokoroId != null && kokoroId.isNotEmpty) {
        final kv = kokoroVoiceById(kokoroId);
        if (kv != null &&
            kv.locale == currentLocale &&
            await tts.kokoro.isModelReady()) {
          await tts.setVoice(
            TtsVoice(
              name: 'Kokoro ${kv.displayName}',
              locale: kokoroLocaleTag(kv.locale),
              kokoroVoiceId: kv.id,
            ),
          );
          unawaited(tts.kokoro.warmup());
          return true;
        }
        return false;
      }
      // ElevenLabs voices aren't in the engine list either — restore from
      // the profile's saved cloud voices. A missing entry (or no API key)
      // keeps the default; speech falls back on-device anyway.
      final elevenId = _prefs?.getString(_voiceElevenLabsKey(currentLocale));
      if (elevenId != null && elevenId.isNotEmpty) {
        final entries = await elevenLabsVoiceEntries();
        final match = entries.where((v) => v.elevenLabsVoiceId == elevenId);
        if (match.isNotEmpty) {
          await tts.setVoice(match.first);
          return true;
        }
        return false;
      }
      // Managed ("included") cloud voices aren't in the engine list
      // either. The voice id alone is enough to synthesize, so restore it
      // directly — synthesis fails lazily (→ on-device fallback) when the
      // account is signed out or offline. Only restore while signed in, so
      // the picker never shows a cloud voice selected that can't speak.
      final proxyId = _prefs?.getString(_voiceProxyKey(currentLocale));
      if (proxyId != null && proxyId.isNotEmpty && proxySignedIn) {
        await tts.setVoice(
          TtsVoice(name: name, locale: locale, proxyVoiceId: proxyId),
        );
        return true;
      }
      final voices = await tts.getVoices();
      final match = voices.where((v) => v.name == name && v.locale == locale);
      if (match.isNotEmpty) {
        await tts.setVoice(match.first);
        return true;
      }
    } catch (_) {}
    return false;
  }

  static int _clampLevel(int level) => level.clamp(
    LanguagePack.minSupportedLevel,
    LanguagePack.maxSupportedLevel,
  );

  /// Reveal vocabulary up to [level]. Words above it keep their cells — the
  /// cells are simply drawn empty — so unlocking never reshuffles the board.
  Future<void> setUnlockedLevel(int level) async {
    final next = _clampLevel(level);
    if (next == unlockedLevel) return;
    unlockedLevel = next;
    await _prefs?.setInt('vidavoice.unlockedLevel', next);
    notifyListeners();
  }

  Future<void> setButtonScale(double scale) async {
    buttonScale = scale;
    await _prefs?.setDouble('vidavoice.buttonScale', scale);
    notifyListeners();
  }

  /// Switch language pack + TTS locale. Clears the sentence because word
  /// labels are language-specific.
  Future<void> setLocale(String locale) async {
    if (!AppConfig.supportedLocales.contains(locale) ||
        locale == currentLocale) {
      return;
    }
    currentLocale = locale;
    _sentenceIds.clear();
    // Strip labels are language-specific, like the sentence bar.
    _buildStrip.clear();
    buildNotice = null;
    _dashboardBypassed = false;
    pack = await LanguagePackService.loadPack(locale);
    await tts.setLanguage(pack.ttsLocale);
    // A voice choice is per-language: apply the saved one for the new
    // language, or drop back to the engine default (the old language's
    // voice must not leak across).
    if (!await _applySavedVoice()) await tts.clearVoice();
    await _prefs?.setString('vidavoice.locale', locale);
    notifyListeners();
  }

  /// Reload per-profile data (sentence history, prediction ranks,
  /// first-week plan) for the currently active profile. Call after the
  /// active profile changes.
  Future<void> reloadProfileData() async {
    await history.load(profiles.active?.id ?? '');
    await prediction.load(profiles.active?.id ?? '');
    await plan.load(profiles.active?.id ?? '');
  }

  /// Switch the active communicator profile and reload per-profile data
  /// (sentence history, first-week plan) for them.
  Future<void> switchProfile(String id) async {
    await profiles.setActive(id);
    _dashboardBypassed = false;
    // Composition state is per profile: never leak an unsent phrase strip
    // (or a notice about it) into another profile's session.
    _buildStrip.clear();
    buildNotice = null;
    await reloadProfileData();
    notifyListeners();
  }

  /// Reload the profile list from storage — a backup import rewrites the
  /// profile blob in SharedPreferences directly, so the in-memory list
  /// would otherwise stay stale (including the communication mode, which
  /// decides which home screen is shown). Reloads per-profile data for
  /// the active profile and notifies so the home surface rebuilds.
  Future<void> reloadProfiles() async {
    await profiles.load();
    _buildStrip.clear();
    buildNotice = null;
    await reloadProfileData();
    notifyListeners();
  }

  /// Explicit caregiver save for a profile's communication mode. This is
  /// the UI-level entry point to [ProfileService.setCommunicationMode] —
  /// it persists the mode AND notifies listeners, so the home screen
  /// switches to the new mode surface immediately. A raw
  /// [ProfileService] call persists but does not rebuild the MaterialApp
  /// home; UI code must call this instead.
  Future<void> setCommunicationMode(String id, CommunicationMode mode) async {
    await profiles.setCommunicationMode(id, mode);
    notifyListeners();
  }

  /// Explicit caregiver save for a profile's Build-mode phrase length.
  /// Same contract as [setCommunicationMode]: persists through
  /// [ProfileService] and notifies so the phrase strip re-reads the
  /// limit immediately.
  Future<void> setBuildMaxSymbols(String id, int max) async {
    await profiles.setBuildMaxSymbols(id, max);
    notifyListeners();
  }

  /// Delete a communicator profile and everything stored for it — including
  /// its custom button images, saved cloud voices, spoken-history records,
  /// and learned prediction ranks — then reload per-profile data for
  /// whoever is now active.
  Future<void> removeProfile(String id) async {
    await profiles.removeProfile(id);
    await symbolOverrides.removeProfile(id);
    await elevenLabsVoices.clearProfile(id);
    // Phase 5: drop the deleted profile's nudge counters (counts only;
    // the durable "do not suggest" preference lives on the profile blob,
    // which is already gone with the profile).
    await nudge.removeProfile(id);
    // The profile's spoken history and learned prediction ranks are
    // per-profile stores keyed by this id: they must not linger on the
    // device for a profile that no longer exists.
    await history.clear(id);
    await prediction.reset(id);
    // The unsent composition belongs to the deleted profile's session.
    _buildStrip.clear();
    buildNotice = null;
    await reloadProfileData();
    notifyListeners();
  }

  Future<void> completeOnboarding(String name) async {
    final trimmed = name.trim();
    if (trimmed.isNotEmpty) {
      await profiles.renameActive(trimmed);
    }
    onboardingComplete = true;
    await _prefs?.setBool('vidavoice.onboardingComplete', true);
    notifyListeners();
  }

  Future<void> reopenOnboarding() async {
    onboardingComplete = false;
    await _prefs?.setBool('vidavoice.onboardingComplete', false);
    notifyListeners();
  }

  /// Sets the onboarding flag directly (used by profile-backup import so a
  /// restored value is reflected without re-running the wizard).
  Future<void> setOnboardingComplete(bool value) async {
    onboardingComplete = value;
    await _prefs?.setBool('vidavoice.onboardingComplete', value);
    notifyListeners();
  }

  /// Persist the device's role (first-launch question, or a
  /// password-verified mode switch). The router rebuilds on notify.
  Future<void> setDeviceRole(DeviceRole role) async {
    deviceRole = role;
    try {
      await deviceRoleService.writeRole(role);
    } catch (_) {}
    notifyListeners();
  }

  /// Forget the device role (used on sign-out so the next account is
  /// asked fresh — the role belongs to the device setup, not the OS).
  Future<void> clearDeviceRole() async {
    deviceRole = null;
    try {
      await deviceRoleService.clearRole();
    } catch (_) {}
    notifyListeners();
  }

  /// Mode-aware board tap used by every board surface (home grid, folders,
  /// dashboards). In Build mode a tap collects the symbol into the phrase
  /// strip and NEVER speaks; in Tap mode behavior is exactly the old
  /// [tapWord] (words speak immediately and accumulate; phrases speak whole
  /// immediately). Folder tiles never reach here (the UI navigates).
  void tapBoardItem(BoardItem item) {
    if (item.type == BoardItemType.folder) return;
    if (profiles.active?.communicationMode == CommunicationMode.build) {
      buildAdd(item);
    } else {
      tapWord(item);
    }
  }

  void tapWord(BoardItem item) {
    if (item.type == BoardItemType.folder) return;
    if (item.type == BoardItemType.phrase) {
      speakPhrase(item);
      return;
    }
    tts.speak(item.label);
    _sentenceIds.add(item.id);
    // Fire-and-forget: usage counts must never block a tap.
    unawaited(usage.recordTap(item.id));
    // Phase 5: count intentional Tap-mode speaks for nudge eligibility.
    // tapWord is the Tap-mode speak path (Build routes through buildAdd,
    // Type through its own screen), so a mode check here is enough.
    final profileId = profiles.active?.id;
    if (profileId != null &&
        profiles.active?.communicationMode == CommunicationMode.tap) {
      unawaited(nudge.recordTapSpeak(profileId));
    }
    notifyListeners();
  }

  /// Phrases are atomic utterances: spoken whole immediately and logged to
  /// history and usage, without touching the sentence bar. Caregivers see
  /// them in activity; replay speaks them again via [replayHistory].
  void speakPhrase(BoardItem item) {
    tts.speak(item.label);
    // Fire-and-forget: logging must never block or delay speech.
    unawaited(usage.recordTap(item.id));
    _logSpoken(
      profiles.active?.id ?? '',
      [item.id],
      item.label,
      currentLocale,
    );
  }

  Future<void> speakText(String text) => tts.speak(text);

  /// Taps a personal-dashboard cell. Vocabulary cells behave exactly as on
  /// the standard board in the active mode ([tapBoardItem]: Build adds to
  /// the strip without speaking, Tap speaks immediately and joins the
  /// sentence bar). Custom buttons are atomic: their stored text either
  /// joins the Build strip as one unit or — in other modes — speaks
  /// immediately, exactly as before. A vocab reference whose word vanished
  /// from a newer pack falls back to its stored text instead of doing
  /// nothing.
  void tapDashboardCell(DashboardCell cell) {
    final wordId = cell.wordId;
    if (wordId != null) {
      try {
        tapBoardItem(pack.wordById(wordId));
        return;
      } on Object {
        // Word removed from the pack — fall through to stored text.
      }
    }
    final text = cell.customText;
    if (text.isEmpty) return;
    if (profiles.active?.communicationMode == CommunicationMode.build) {
      buildAddText(text);
    } else {
      tts.speak(text);
    }
  }

  /// Shared spoken-message logging for every mode's speech path.
  ///
  /// Records the intentionally-spoken message in the profile's history
  /// (caregiver-visible activity) AND feeds the on-device prediction
  /// ranks — but only while that profile's predictionEnabled is true.
  /// Fire-and-forget: logging must never block or delay speech.
  ///
  /// History and learned ranks are INDEPENDENT stores: clearing one never
  /// touches the other (see [clearHistoryFor] / [resetLearningFor]).
  void _logSpoken(
    String profileId,
    List<String> ids,
    String text,
    String locale,
  ) {
    unawaited(history.record(profileId, ids, text, locale));
    final p = profiles.active;
    if (p != null && p.id == profileId && p.predictionEnabled) {
      unawaited(prediction.learn(profileId, text, locale));
    }
  }

  void speakSentence() {
    final text = sentence.map((w) => w.label).join(' ');
    if (text.isEmpty) return;
    tts.speak(text);
    _logSpoken(
      profiles.active?.id ?? '',
      List.of(_sentenceIds),
      text,
      currentLocale,
    );
  }

  /// Reload a history entry into the sentence bar and speak it again.
  /// Ids that no longer exist in the current pack are skipped; the pack's
  /// cells and positions are untouched. Free-typed entries (Type mode,
  /// empty ids) have no board ids — the stored text is spoken directly.
  void replayHistory(HistoryEntry entry) {
    if (entry.text.trim().isEmpty) return;
    if (entry.ids.isEmpty) {
      tts.speak(entry.text);
      _logSpoken(
        profiles.active?.id ?? '',
        const [],
        entry.text,
        currentLocale,
      );
      return;
    }
    _sentenceIds.clear();
    for (final id in entry.ids) {
      try {
        pack.wordById(id);
        _sentenceIds.add(id);
      } on Object {
        // Word removed from a newer pack — skip it.
      }
    }
    notifyListeners();
    speakSentence();
  }

  /// Type-mode Speak — the ONLY Type-path method that may touch the TTS
  /// layer. Speaks [text] exactly as typed, records it in the active
  /// profile's spoken history (typed entries carry no board ids), and
  /// feeds the on-device prediction ranks when learning is enabled for
  /// the profile. Returns a Future so tests can await the recording;
  /// the UI treats it as fire-and-forget like every other speak path.
  Future<void> typeSpeak(String text) async {
    final message = text.trim();
    if (message.isEmpty) return;
    final id = profiles.active?.id ?? '';
    await tts.speak(message);
    await history.record(id, const [], message, currentLocale);
    final p = profiles.active;
    if (p != null && p.predictionEnabled) {
      await prediction.learn(id, message, currentLocale);
    }
    notifyListeners();
  }

  void clearSentence() {
    _sentenceIds.clear();
    notifyListeners();
  }

  void undoLast() {
    if (_sentenceIds.isNotEmpty) {
      _sentenceIds.removeLast();
      notifyListeners();
    }
  }

  // ------------------------------------------------- build mode strip -----
  // The Build-mode composition surface: symbols collect in a visible,
  // ordered strip and NOTHING speaks until the communicator presses Speak
  // ([buildSpeak]). No other method on this path touches the TTS layer.
  //
  // DOCUMENTED DESIGN CHOICE — phrase-type items (isPhrase): a phrase
  // joins the strip as ONE unit and speaks only with the composed
  // message. Speaking it immediately would break Build mode's defining
  // contract (speech only after an intentional Speak), so it behaves as a
  // single composed symbol rather than the Tap-mode atomic utterance.
  final List<BuildStripEntry> _buildStrip = [];

  /// The Build-mode phrase strip in order. Unmodifiable.
  List<BuildStripEntry> get buildStrip => List.unmodifiable(_buildStrip);

  /// The caregiver-set maximum phrase length for the active profile
  /// (default 4, see [ProfileService.buildMaxSymbols]).
  int get buildMax =>
      profiles.active?.buildMaxSymbols ?? ProfileService.defaultBuildMaxSymbols;

  // --------------------------------------- type mode: prediction --------
  // Caregiver controls for Type-mode prediction. The three actions are
  // INDEPENDENT by design (plan acceptance criteria):
  // * clearing history never touches learned ranks;
  // * resetting learning never touches history;
  // * disabling learning stops accumulation AND clears existing ranks.

  /// Whether Type-mode prediction learns from [id]'s spoken messages.
  /// Turning learning OFF also clears that profile's learned ranks — a
  /// disabled profile must not keep (or keep growing) a personal language
  /// model. History is untouched.
  Future<void> setPredictionEnabled(String id, bool enabled) async {
    await profiles.setPredictionEnabled(id, enabled);
    if (!enabled) {
      await prediction.reset(id);
    }
    notifyListeners();
  }

  /// Clear the profile's spoken-message history. Learned prediction ranks
  /// are a separate store and are NOT touched.
  Future<void> clearHistoryFor(String id) async {
    await history.clear(id);
    notifyListeners();
  }

  /// Reset the profile's learned prediction ranks. Spoken history is a
  /// separate store and is NOT touched.
  Future<void> resetLearningFor(String id) async {
    await prediction.reset(id);
    notifyListeners();
  }

  final Map<String, List<VocabLabel>> _vocabLabels = {};

  /// 10,000-concept vocabulary labels for Type-mode prediction fallback,
  /// per locale. Loaded lazily from the bundled compact asset and cached —
  /// fully offline, no network, and the history-first ranking works even
  /// when the asset is missing.
  Future<List<VocabLabel>> vocabLabelsFor(String locale) async {
    final cached = _vocabLabels[locale];
    if (cached != null) return cached;
    final labels = await LanguagePackService.loadVocabLabels(locale);
    _vocabLabels[locale] = labels;
    return labels;
  }

  /// True when the strip already holds [buildMax] units.
  bool get buildStripFull => _buildStrip.length >= buildMax;

  /// Accessible feedback about the last strip interaction — currently only
  /// the full-strip rejection. Null when there is nothing to report. The
  /// UI renders it as text AND the session announces it for screen
  /// readers, so the limit is never communicated by speaking the rejected
  /// word and never by adding it silently.
  String? buildNotice;

  void _announceBuild(String message) {
    // SessionState is not a widget, so it has no BuildContext to resolve a
    // view from — take the first platform view instead. Silent when no
    // view exists (e.g. a headless unit test); the strip state and
    // buildNotice still carry the information.
    final views = WidgetsBinding.instance.platformDispatcher.views;
    if (views.isEmpty) return;
    unawaited(
      SemanticsService.sendAnnouncement(
        views.first,
        message,
        TextDirection.ltr,
      ),
    );
  }

  /// Adds [item] to the strip. Returns false and leaves the strip (and the
  /// TTS layer) untouched when the strip is full — the limit is
  /// communicated via [buildNotice] + a screen-reader announcement, never
  /// by speaking the rejected word and never by adding it silently.
  bool buildAdd(BoardItem item) {
    final max = buildMax;
    if (_buildStrip.length >= max) {
      buildNotice =
          'Phrase strip is full — ${_buildStrip.length} of $max symbols.';
      _announceBuild(buildNotice!);
      notifyListeners();
      return false;
    }
    _buildStrip.add(BuildStripEntry(wordId: item.id, text: item.label));
    buildNotice = null;
    _announceBuild('Added ${item.label}. ${_buildStrip.length} of $max.');
    // Fire-and-forget: usage counts must never block a tap.
    unawaited(usage.recordTap(item.id));
    notifyListeners();
    return true;
  }

  /// Adds ad-hoc text (e.g. a dashboard custom button) as one strip unit.
  /// Same full-strip contract as [buildAdd].
  bool buildAddText(String text) {
    final max = buildMax;
    if (_buildStrip.length >= max) {
      buildNotice =
          'Phrase strip is full — ${_buildStrip.length} of $max symbols.';
      _announceBuild(buildNotice!);
      notifyListeners();
      return false;
    }
    _buildStrip.add(BuildStripEntry(text: text));
    buildNotice = null;
    _announceBuild('Added $text. ${_buildStrip.length} of $max.');
    notifyListeners();
    return true;
  }

  /// Tap-to-remove: drops the strip unit at [index]. Out-of-range is a
  /// no-op.
  void buildRemoveAt(int index) {
    if (index < 0 || index >= _buildStrip.length) return;
    final removed = _buildStrip.removeAt(index);
    buildNotice = null;
    _announceBuild(
      'Removed ${removed.text}. ${_buildStrip.length} of $buildMax.',
    );
    notifyListeners();
  }

  /// Clears the whole strip. Empty strip is a no-op.
  void buildClear() {
    if (_buildStrip.isEmpty) return;
    _buildStrip.clear();
    buildNotice = null;
    _announceBuild('Phrase strip cleared.');
    notifyListeners();
  }

  /// Speaks the composed phrase — the ONLY Build-path method that may
  /// touch the TTS layer. Records history through the same path as Tap's
  /// [speakSentence] so caregivers see Build messages in activity too. The
  /// strip is kept so the message can be replayed.
  void buildSpeak() {
    final text = _buildStrip.map((e) => e.text).join(' ');
    if (text.isEmpty) return;
    tts.speak(text);
    // Fire-and-forget: history must never block or delay speech.
    _logSpoken(
      profiles.active?.id ?? '',
      [for (final e in _buildStrip) if (e.wordId != null) e.wordId!],
      text,
      currentLocale,
    );
    // Phase 5: count intentional full-strip Build speaks for nudge
    // eligibility. Counts only — the text never reaches the nudge store.
    // Fire-and-forget: counting must never block or delay speech.
    final profileId = profiles.active?.id;
    if (profileId != null) {
      unawaited(
        nudge.recordBuildSpeak(
          profileId: profileId,
          stripLength: _buildStrip.length,
          maxLength:
              profiles.active?.buildMaxSymbols ??
              ProfileService.defaultBuildMaxSymbols,
        ),
      );
    }
    _announceBuild('Speaking: $text');
    notifyListeners();
  }

  /// Session teardown. Stops location polling and disposes the share service
  /// so no periodic timer outlives the session (widget tests fail on leaked
  /// timers; production disposes this once at app shutdown).
  @override
  void dispose() {
    locationShare.dispose();
    super.dispose();
  }
}

/// One unit in the Build-mode phrase strip: a vocabulary word (with its
/// language-independent id, so history records resolve it) or ad-hoc text
/// (a dashboard custom button) which has no id and contributes no id to
/// the history record.
class BuildStripEntry {
  const BuildStripEntry({this.wordId, required this.text});

  final String? wordId;
  final String text;
}
