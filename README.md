# VidaVoice — v0.02 overnight build

Affordable, multilingual AAC for nonverbal children and adults.
A VidaCare Foundation project. Full product blueprint:
[`../aac-app-blueprint.md`](../aac-app-blueprint.md)

> App name is final: **VidaVoice** (see `lib/app_config.dart`).
> Logo is final: the **V-waveform** concept (Adam's pick, 2026-09-14), wired as
> the app icon via `flutter_launcher_icons` and shown in-app on onboarding and
> Settings. Source: `branding/media-generation-vidavoice-logo-v-wave-*.webp`.

## What was built (v0.02)

- **Core-word board**: **192 core words** (EN) in FIXED grid positions declared
  in `assets/lang/en.json` (motor planning is sacred — positions are data, never
  computed; the original 48 words from v0.01 kept their exact cells). 4 category
  folders (Food, Feelings, People, Play) with 50 words.
- **ARASAAC pictograms**: real symbols for **all 242 words**, fetched from the
  ARASAAC API (`assets/symbols/*.png` + `manifest.json`), rendered by
  `SymbolImage` (emoji fallback remains in code but no word currently needs
  it). Attribution shown in Settings and Caregiver (CC BY-NC-SA).
  `MAPPING.md` records exactly which pictogram id backs each word — an SLP
  should review the auto-picked matches (all are first-search-hit choices,
  6 were re-fetched with alternate search terms).
- **Spanish pack**: `assets/lang/es.json` mirrors EN exactly — same ids, same
  grid positions — with Spanish labels and `es-ES` TTS locale. Language switcher
  in Settings (clears the message bar on switch). ⚠️ The ES translation is a
  first draft and **must be reviewed by a native-speaker SLP before any pilot**.
- **2-tap budget enforced in code**: every word is on the home grid (1 tap) or
  in exactly one folder (2 taps). `LanguagePack.validate()` throws on violation,
  and `test/language_pack_test.dart` pins the invariant for both locales plus
  EN↔ES position identity.
- **Tap-to-speak**: `flutter_tts` (OS TTS) speaks each word immediately on tap.
- **Message bar**: tapped words accumulate into a sentence; Speak replays it,
  plus Undo-last and Clear. Visible on the home board and inside folders.
- **First-run onboarding wizard** (4 steps): welcome → profile name → voice
  speed (with live preview) → quick tour. Runs once; re-runnable from Caregiver.
- **Caregiver hub**: communicator profiles (add / switch / remove, persisted
  locally via `shared_preferences`), 7 research-backed modeling tips, setup
  replay, and the honest roadmap checklist.
- **Settings**: language switcher, voice speed + pitch sliders (with "Hear it"
  preview), button size (Small/Medium/Large — visual size only; the grid layout
  never changes, positions stay fixed).
- **App icon**: V-waveform wired via `flutter_launcher_icons` (generated into
  android/ios) and shown in-app.

## How to run

Prerequisites: Flutter SDK (stable) on PATH, Android SDK for APK builds.

```bash
cd ~/workspace/vidacare-aac/vidavoice

flutter pub get

# static analysis + pack invariant tests
flutter analyze
flutter test

# run on a connected device / emulator
flutter run

# debug APK (installable on any Android tablet, incl. Fire tablets via sideload)
flutter build apk --debug
# → build/app/outputs/flutter-apk/app-debug.apk
```

> TTS note: `flutter_tts` uses the device's OS speech engine. On a fresh
> emulator with no TTS engine/data, taps will be silent — install Google TTS
> (or test on a physical tablet) to hear speech.

## Project structure

```
lib/
  main.dart                  # entry: Provider wiring, boot → status/onboarding/home
  app_config.dart            # SINGLE SOURCE OF TRUTH: name, locales, voice defaults
  models/word.dart           # BoardItem / FolderPack / LanguagePack + validate()
  services/
    tts_service.dart         # flutter_tts wrapper (speak/rate/pitch/language)
    language_pack_service.dart  # loads + validates assets/lang/<locale>.json
    symbol_service.dart      # ARASAAC manifest → hasSymbol/assetPath
    profile_service.dart     # local communicator profiles (SharedPreferences)
  state/session_state.dart   # ChangeNotifier: pack, sentence, locale, prefs, onboarding
  widgets/
    word_button.dart         # tappable board cell (symbol + label, scaled)
    symbol_image.dart        # ARASAAC pictogram w/ emoji fallback
    message_bar.dart         # pinned sentence bar: Speak / Undo / Clear
  screens/
    boot_screen.dart         # loading + error states
    onboarding_screen.dart   # 4-step first-run wizard
    home_board_screen.dart   # fixed-position core grid + folders
    category_screen.dart     # inside a folder (2nd tap)
    settings_screen.dart     # language, voice rate/pitch, button size
    caregiver_screen.dart    # profiles, modeling tips, setup replay, roadmap
assets/
  lang/en.json               # THE vocabulary: 192 core words + 4 folders (v2)
  lang/es.json               # Spanish mirror: same ids + positions (DRAFT — SLP review needed)
  symbols/*.png              # ARASAAC pictograms per word id
  symbols/manifest.json      # which word ids have a symbol
  symbols/MAPPING.md         # arasaac id per word (review aid)
  images/app_icon.png        # V-waveform logo (1024×1024)
test/
  language_pack_test.dart    # pins 192 words, unique cells, 2-tap budget, EN↔ES parity
```

## Adding a language

1. Copy `assets/lang/en.json` → `assets/lang/<locale>.json`.
2. Translate `label` fields only — **never change ids, rows, or cols**.
3. Set `ttsLocale` (e.g. `fr-FR`).
4. Add the locale to `AppConfig.supportedLocales`.

The Settings switcher, TTS locale switching, and validation pick it up with no
other code changes. Get a native-speaker SLP to review the word list before
shipping it to families.

## What's stubbed / not yet built

- All 242 words have an ARASAAC pictogram (first-search-hit choices — SLP
  review of `MAPPING.md` still needed); emoji fallback exists in code but is
  currently unused.
- `es.json` is a draft translation — native-speaker SLP review required.
- Profiles are local-only (SharedPreferences); no backend/sync yet.
- No vocabulary levels / progressive reveal, no custom photos/recordings.
- No switch scanning, dwell, high-contrast mode, or adult typing mode.
- No usage analytics.

## App icon

`flutter_launcher_icons` is configured in `pubspec.yaml`
(`image_path: assets/images/app_icon.png`, the **V-waveform** final logo).
To regenerate after any future logo change:

```bash
# 1. Replace assets/images/app_icon.png with a 1024×1024 PNG
# 2. Regenerate:
dart run flutter_launcher_icons
```

## Verification (run 2026-09-14, this machine)

Toolchain: Flutter 3.47.4 (Dart 3.13.3) · Amazon Corretto JDK 17.0.20.1 ·
Android SDK: platform android-34 (ext12), build-tools 34.0.0,
platform-tools r37.0.1 · Gradle 9.3.1.

```text
$ flutter analyze
Analyzing vidavoice...
No issues found! (ran in 14.5s)

$ flutter test
00:00 +11: All tests passed!

$ flutter build bundle --debug
Build succeeded — build/flutter_assets (61M): kernel_blob.bin,
  assets/lang/en.json + es.json, 242 symbol PNGs, app icon.
```

`flutter build apk --debug` did **not** complete in this sandbox — and this is
an environment block, not an app defect:

```text
$ flutter build apk --debug
Running Gradle task 'assembleDebug'...
FAILURE: Build failed with an exception.
* What went wrong:
Could not dispatch a message to the daemon.
Caused by: org.gradle.internal.remote.internal.MessageIOException:
  Could not write '/127.0.0.1:37371'.
Caused by: java.io.IOException: Broken pipe
Gradle task assembleDebug failed with exit code 1
```

Root cause (proven with minimal Java repro programs): this sandbox denies
**all** loopback TCP to Java processes. Any Java `Socket`/`SocketChannel`
connect to 127.0.0.1 is answered by the sandbox with:

```text
muse: Other TCP connections is turned off for this assistant. To allow it,
ask the user to open Muse settings -> Permissions -> Direct network protocols
and switch other_tcp from Deny to Ask.
```

The Gradle daemon architecture requires Java→Java TCP on 127.0.0.1, so no
Gradle invocation can reach its daemon here (the daemon starts and listens
fine, then every client dispatch dies with broken pipe). Non-Java loopback
(curl, Python) works — only Java processes are restricted.

**To finish the APK**: on any machine where Java loopback TCP is allowed
(Adam's Windows laptop, CI), run the exact command below. Everything is
pre-staged: `flutter pub get` resolved, launcher icons generated, Gradle 9.3.1
wrapper dist pre-seeded, Android SDK components installed, licenses accepted.

```bash
cd ~/workspace/vidacare-aac/vidavoice
flutter build apk --debug
# → build/app/outputs/flutter-apk/app-debug.apk
```

(Note for this sandbox's network: Java's HttpURLConnection also cannot parse
this environment's egress-proxy CONNECT responses, so a local proxy shim at
`~/workspace/vidacare-aac/proxy_shim.py` (127.0.0.1:8888, chained to the
egress proxy) was used with `~/.gradle/gradle.properties` pointing Gradle at
it. Keep the shim running during the first build so AGP/Kotlin dependencies
can download; it is only needed on this sandbox.)
