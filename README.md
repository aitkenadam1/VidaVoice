# VidaVoice — v0.03

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

## New in v0.03

- **Vocabulary levels + progressive reveal.** Every word declares a `level`
  (1–3) in the pack, beside `row`/`col`. The caregiver picks the level; words
  above it leave their cell **empty** rather than being filtered out, so no
  visible word ever moves. Enforced by test, including EN↔ES level parity.
  Split and rationale: `docs/VOCAB_LEVELS.md` (needs SLP sign-off).
- **Caregiver first-week plan.** The seven modeling tips became a guided week —
  one habit a day, each with a concrete "try it today" task. Progress is stored
  per profile, so a shared classroom tablet tracks each communicator separately.
- **Symbol QA pass.** All 242 pictograms reviewed as images, not keywords:
  18 show the wrong word, 11 are duplicates shared by two words. See
  `docs/SYMBOL_QA.md`. **Not yet fixed** — the re-fetch needs ARASAAC access.
- **Spanish review list.** `docs/ES_SLP_REVIEW.md`. `es.json` is unchanged.
- **Reproducible symbol pipeline.** `tools/fetch_symbols.py`. `MAPPING.md` now
  covers all 246 vocabulary entries (it recorded 100) with a `reviewed` column.

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
  models/word.dart           # BoardItem / FolderPack / LanguagePack + validate() + level
  models/modeling_plan.dart  # the caregiver's 7-day first-week plan (content + progress)
  services/
    tts_service.dart         # flutter_tts wrapper (speak/rate/pitch/language)
    language_pack_service.dart  # loads + validates assets/lang/<locale>.json
    symbol_service.dart      # ARASAAC manifest → hasSymbol/assetPath
    profile_service.dart     # local communicator profiles (SharedPreferences)
    modeling_plan_service.dart  # per-profile first-week progress (SharedPreferences)
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
    caregiver_screen.dart    # profiles, vocabulary level, first-week plan, setup replay
assets/
  lang/en.json               # THE vocabulary: 192 core words + 4 folders (v2), each with a level
  lang/es.json               # Spanish mirror: same ids + positions (DRAFT — SLP review needed)
  symbols/*.png              # ARASAAC pictograms per word id
  symbols/manifest.json      # which word ids have a symbol
  symbols/MAPPING.md         # arasaac id per word (review aid)
  images/app_icon.png        # V-waveform logo (1024×1024)
test/
  language_pack_test.dart    # 192 words, unique cells, 2-tap budget, levels, EN↔ES parity
  modeling_plan_test.dart    # 7-day plan content + progress/day-advance logic
tools/
  fetch_symbols.py           # ARASAAC review/fetch/remap — the symbol pipeline
docs/
  BUILD_PLAN.md              # plan to MVP + the refactors proposed before extending
  SYMBOL_QA.md               # every pictogram reviewed; what to replace and why
  ES_SLP_REVIEW.md           # Spanish review list for a native-speaker SLP
  VOCAB_LEVELS.md            # the level split, and what an SLP should challenge
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

- **18 pictograms show the wrong word and 11 are duplicated across two words**
  (`docs/SYMBOL_QA.md`). Documented, not fixed — needs ARASAAC access plus SLP
  sign-off. `core.try` currently shows a courtroom trial and `core.pull` shows
  flushing a toilet; these should not reach a pilot family.
- The four folder tiles have no pictogram and fall back to emoji.
- `es.json` is a draft translation — see `docs/ES_SLP_REVIEW.md`.
- The vocabulary level split is an engineering proposal, not a clinical one
  (`docs/VOCAB_LEVELS.md`).
- Profiles are local-only; no backend/sync. **Profile switching does not switch
  vocabulary level, button size, language or voice** — those are still
  device-global. See `docs/BUILD_PLAN.md` refactor 3.
- Storage is still SharedPreferences, not SQLite/Drift.
- **The app interface is English-only** even when the board is Spanish.
- No custom photos/recordings, no usage analytics.
- No switch scanning, dwell, high-contrast mode, or adult typing mode.
- **No widget or integration tests** — all 37 tests are data-level, because
  `SessionState` has no injection seam. This is the top item in the build plan.

## App icon

`flutter_launcher_icons` is configured in `pubspec.yaml`
(`image_path: assets/images/app_icon.png`, the **V-waveform** final logo).
To regenerate after any future logo change:

```bash
# 1. Replace assets/images/app_icon.png with a 1024×1024 PNG
# 2. Regenerate:
dart run flutter_launcher_icons
```

## Verification (run 2026-09-14)

Toolchain: Flutter 3.47.4 (Dart 3.13.3) · OpenJDK 21.0.10 · no Android SDK
(see below).

```text
$ flutter analyze
Analyzing VidaVoice...
No issues found! (ran in 5.7s)

$ flutter test
00:00 +37: All tests passed!

$ flutter build bundle --debug
Build succeeded — build/flutter_assets (61M): kernel_blob.bin,
  assets/lang/en.json + es.json, 242 symbol PNGs, app icon.
```

### `flutter build apk --debug` has not been run

It is blocked in this environment, and for a **different reason** than in the
v0.02 overnight sandbox. That sandbox denied loopback TCP to Java, so Gradle
could never reach its own daemon. **That blocker is gone** — Java loopback works
here (verified with a minimal `ServerSocket`/`Socket` round trip).

The blocker now is egress policy: the Android SDK is not installed and cannot be
downloaded, because `dl.google.com` is denied.

```text
$ curl -sS -o cmdline-tools.zip https://dl.google.com/android/repository/commandlinetools-linux-11076708_latest.zip
curl: (56) CONNECT tunnel failed, response 403

$ flutter build apk --debug
[!] No Android SDK found. Try setting the ANDROID_HOME environment variable.
```

`api.arasaac.org` is denied the same way, which is why the symbol QA findings
are documented but not applied:

```text
$ curl -sS https://api.arasaac.org/api/pictograms/en/search/want
curl: (56) CONNECT tunnel failed, response 403
```

(`arasaac.org` and `static.arasaac.org` are denied too.)

Neither is an app defect. On any machine with an Android SDK, `flutter build apk
--debug` should work — nothing in this release touches the Android build
configuration. Treat the APK as **unverified until someone runs it**, not as
known-good.

