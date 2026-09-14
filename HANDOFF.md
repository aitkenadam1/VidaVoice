# Claude Code continuation handoff — VidaVoice v0.02 → MVP

Paste everything below the line into Claude Code as one message.

---

```
TASK: Continue building VidaVoice (VidaCare Foundation's affordable, multilingual
AAC app for nonverbal children and adults) from the v0.02 overnight build toward
the MVP milestone defined in the blueprint.

REPO / BRANCH STATE:
- Repo: https://github.com/aitkenadam1/VidaVoice — clone it (Flutter, stable channel).
- Git repo initialized; v0.02 committed as 18f91eb ("VidaVoice v0.02..."),
  working tree clean. Work feature-by-feature on branches from here.
- App name is FINAL: VidaVoice. Display name is centralized in
  lib/app_config.dart — do not hardcode the name anywhere else.
- Logo is FINAL: the V-waveform concept
  (branding/media-generation-vidavoice-logo-v-wave-0-6635e593-953d-4f3f-ad25-1283fa9f61c9.webp),
  already wired as assets/images/app_icon.png and launcher icons. No action needed
  unless rebranding.

KEY FILE PATHS:
- Product blueprint (read FIRST): docs/aac-app-blueprint.md
  (§3 phasing, §4 architecture, §5 symbols, §6 multilingual, §8 roadmap)
- lib/app_config.dart — app identity, supportedLocales (en, es), voice defaults
- assets/lang/en.json — THE vocabulary: 192 core words at FIXED grid positions
  + 4 folders (Food/Feelings/People/Play, 50 words). Positions are data, never computed.
- assets/lang/es.json — Spanish mirror: SAME ids, SAME positions, es-ES TTS.
  DRAFT translation — flag every uncertain word choice for native SLP review.
- assets/symbols/ — ARASAAC pictograms per word id + manifest.json + MAPPING.md
  (which ARASAAC id backs each word; first-search-hit, needs SLP review).
- lib/models/word.dart — BoardItem/FolderPack/LanguagePack + validate()
  (enforces the 2-tap budget) + wordById()
- lib/services/ — tts_service (rate/pitch/language), language_pack_service,
  symbol_service (manifest), profile_service (local profiles)
- lib/state/session_state.dart — ChangeNotifier: pack, sentence, locale,
  button scale, onboarding flag, persisted prefs
- lib/screens/ — home_board, category, onboarding_screen (4-step wizard),
  settings_screen (language/voice/button size), caregiver_screen (profiles +
  7 modeling tips + replay tour + roadmap), boot_screen
- lib/widgets/ — word_button, symbol_image (pictogram w/ emoji fallback),
  message_bar
- test/language_pack_test.dart — pins 192 words, unique cells, 2-tap budget,
  EN↔ES position identity
- pubspec.yaml — deps: provider, flutter_tts, shared_preferences,
  flutter_launcher_icons (config at bottom)

BACKGROUND (what v0.02 does):
- Boots: loads + validates pack for saved locale, loads symbol manifest +
  profiles, inits OS TTS with saved rate/pitch. First run → 4-step onboarding
  (welcome, profile name, voice speed w/ preview, quick tour); then home board.
- Home board: 192 core words at fixed positions + 4 folder tiles, 8 columns,
  25 rows, scrollable. Tap word → speaks immediately + appends to message bar.
- Message bar (pinned, board + folders): Speak replays sentence, Undo, Clear.
- Folders open on tile tap; words inside speak + append (2-tap max, enforced).
- Symbols: ARASAAC pictogram for ALL 242 word ids (first-search-hit choices;
  6 re-fetched with alternate terms). No emoji gaps remain, but every match
  needs SLP review — see assets/symbols/MAPPING.md (arasaac id per word).
  CC BY-NC-SA attribution in Settings + Caregiver.
- Settings: EN/ES switcher (clears message bar; positions identical), speech
  rate + pitch sliders with live preview, button size S/M/L (visual only —
  grid layout locked for motor planning).
- Caregiver: profiles (add/switch/remove, local), 7 modeling tips, replay
  setup tour, planned-next checklist.
- v0.02 verification: `flutter analyze` clean (No issues found),
  `flutter test` 11/11 green, `flutter build bundle --debug` OK (242 symbols
  bundled). `flutter build apk --debug` was BLOCKED in the overnight sandbox
  only: the sandbox denies all loopback TCP to Java processes, so the Gradle
  daemon can never receive a dispatch ("Could not dispatch a message to the
  daemon ... Broken pipe"). Not an app defect. On any normal machine just run
  `flutter build apk --debug` — everything is pre-staged. Full details +
  toolchain versions in README.md "Verification".

BACKGROUND (blueprint's next milestones after v0.02):
- Phase 0 remainder: local-first SQLite (Drift) replacing SharedPreferences for
  profiles/settings; vocabulary levels + progressive reveal (hide/show by level,
  positions never shift); SLP review of MAPPING.md (all 242 first-search-hit
  pictograms); install size target <150MB.
- Phase 1 (MVP): native-SLP review of es.json, then French pack; caregiver
  onboarding wizard EXTENSION (guided first-week modeling plan); custom
  photos/recordings; backend sync v1; usage insights (most-used words);
  Play Store + App Store + Amazon Appstore submissions (Fire tablets = sideload).
- Non-goals for now: adult typing mode (v1), switch scanning (v1),
  neural voices (Plus tier), eye tracking (v2).

CONVENTIONS TO KEEP:
- lib/app_config.dart is the single source of truth for identity/config.
- Grid positions live ONLY in assets/lang/*.json. Never compute or reorder
  positions in code. validate() must keep passing; extend the tests if packs grow.
- New words go in NEW rows below existing ones — never move a shipped word.
- Adding a language = new assets/lang/<locale>.json (same ids/positions) +
  AppConfig.supportedLocales. Nothing else should need code changes.
- flutter analyze must stay clean; add widget/unit tests for new logic.

EXACT ORDERED ASKS:
1. Read the blueprint (§4–§6, §8) and the v0.02 tree. Summarize your build plan
   and flag anything in v0.02 you'd refactor before extending (do not refactor
   yet — propose first).
2. Symbol QA pass: review assets/symbols/MAPPING.md against the EN labels;
   list every pictogram you'd replace and why, and re-fetch better matches via
   the ARASAAC API (api.arasaac.org). All 242 words currently have a pictogram
   (no emoji gaps), but all are first-search-hit choices — the QA pass is what
   makes them trustworthy. Ids and positions must not change.
3. Spanish SLP review prep: go through assets/lang/es.json and flag every word
   choice you're unsure about (especially: core.dont→"no", core.make→"crear"
   vs core.do→"hacer", pronouns like core.his→"de él", articles core.a/core.the)
   with your recommended alternative and reasoning. Do NOT rewrite the file —
   produce the review list for a human SLP.
4. Vocabulary levels + progressive reveal: add a "level" field to the pack
   schema (1–3), hide level-2/3 words behind a caregiver-unlocked setting
   (empty cells stay empty — visible positions never shift), extend tests.
5. Caregiver onboarding extension: turn the 7 static modeling tips into a
   guided first-week plan (one tip per day with a "try it today" prompt),
   stored per profile. Keep it simple and local.
6. After each ask: `flutter analyze` clean, `flutter test` green,
   `flutter build apk --debug` succeeds. Report the verbatim outputs.
```
