# VidaVoice — build plan from v0.02 to MVP

Written after reading the blueprint (§4 architecture, §5 symbols, §6
multilingual, §8 roadmap) and working through the whole v0.02 tree.

Blueprint §8 puts MVP at: vocabulary levels + progressive reveal, fringe packs,
custom photos/recordings, caregiver onboarding wizard + modeling tips, backend
sync v1, Spanish pack, and store submissions — with the exit criterion **"50
pilot families complete 10-min setup unassisted; 4-week retention tracked."**

That exit criterion is the useful lens. It is not a feature list — it is a
statement that the app must be *trustworthy and measurable* in a stranger's
hands. Most of what follows is chosen against it.

## Done in this session

| Ask | Outcome |
|---|---|
| 2 — Symbol QA | `docs/SYMBOL_QA.md`: 18 wrong-meaning pictograms, 11 duplicates, 8 mismatched pairs, 6 illegible-at-button-size sets, 11 style/culture issues. `tools/fetch_symbols.py` makes the pipeline reproducible; `MAPPING.md` regenerated for all 246 entries instead of 100. Re-fetch is blocked here by egress policy — see Verification. |
| 3 — Spanish review | `docs/ES_SLP_REVIEW.md`: the variety/TTS mismatch, the four items in the brief, plus duplicate labels, `hambriento`/`sediento`/`algo`, and the pack-wide gender decision. `es.json` untouched. |
| 4 — Vocabulary levels | `level` (1–3) in the pack schema; caregiver-controlled reveal; locked cells stay empty so nothing moves. Tests 11 → 28. |
| 5 — First-week plan | Seven static tips → a guided day-by-day plan with "try it today" tasks, stored per profile. Tests 28 → 37. |

## Refactors to make before building further

**Proposals — none of these were performed.** They are ordered by what blocks
the MVP exit criterion soonest.

### 1. `SessionState` cannot be tested, so nothing above the data layer is

`SessionState` owns TTS, symbols, profiles, the modeling plan, preferences, the
sentence, locale, levels and onboarding, and it reaches for
`SharedPreferences.getInstance()` and `FlutterTts()` directly in `boot()`.

There is no seam to inject a fake, so no widget test can construct one. That is
why all 37 tests are pure data tests and **zero test the board**: nothing
verifies that tapping a button speaks and appends, that the level control
actually blanks cells on screen, or that the message bar renders a sentence.

Shipping to 50 families with no UI test coverage is the largest single risk in
the repo. **Fix first**: constructor-inject the three services behind small
interfaces, add in-memory fakes, then write the board/message-bar/level widget
tests. Splitting the god object (board state vs. settings vs. caregiver) can
follow, but the seam is the part that unblocks everything.

### 2. The grid rebuild is O(cells × words), against a 60fps exit criterion

`HomeBoardScreen` builds every cell eagerly and each one calls
`LanguagePack.itemAt()`, which linearly scans `homeItems`:

> **25 rows × 8 cols = 200 cells, each scanning 196 items = 39,200 comparisons
> per board rebuild.**

It is survivable at 192 words. It is not survivable at the blueprint's 10,000+
fringe vocabulary, and blueprint M0 lists "60fps grid" as an exit criterion.

**Fix**: build a `Map<int, BoardItem>` keyed by `row * gridColumns + col` once at
pack load (positions are immutable, so it can be built in the constructor), and
switch to `GridView.builder` so off-screen rows are not built at all. Same for
`wordById`, which is another linear scan — and `SessionState.sentence` calls it
once per word on **every** `MessageBar` rebuild.

### 3. Profile switching does not switch the profile

`unlockedLevel`, `buttonScale`, `currentLocale`, speech rate and pitch are all
stored as device-global preference keys. Only the *name* and (as of this
session) the modeling plan are per profile.

On a shared classroom or clinic tablet — explicitly a target in blueprint §7 —
switching communicator hands the next child the previous child's vocabulary
level and voice settings. The modeling plan being correctly per-profile makes
the inconsistency sharper, not better.

**Fix**: move communicator-scoped settings into the profile record. Do it at the
same time as #4, since both change the storage shape.

### 4. `SharedPreferences` → SQLite (Drift)

Blueprint §4 calls for a local-first SQLite store; the Phase 0 remainder names
it explicitly. Today everything is flat key-value with hand-namespaced string
prefixes (`vidavoice.modelingPlan.v1.<profileId>`), which is already awkward and
does not support the MVP's "usage insights: most-used words" at all — that needs
event rows, not scalars.

**Fix**: Drift, with profiles, settings, and a word-tap event table. This is also
the natural seam for backend sync v1.

### 5. A missing TTS engine takes down the whole app

`boot()` wraps pack load, symbols, profiles **and** `tts.init()` in one
try/catch, and any exception sets `BootStatus.error`. On a device with no TTS
engine or no voice data — blueprint §9.6 puts Fire HD tablets in the test matrix
precisely because they are quirky — the communicator gets *"Couldn't start
VidaVoice"* instead of a working board.

A silent board is bad. A board that refuses to open is worse. **Fix**: catch TTS
failure separately, boot to a working board, and surface a dismissible banner
pointing at the TTS install.

### 6. The app chrome is English-only

The *vocabulary* is multilingual; the *interface* is not. Every screen carries
hard-coded English literals — `'Caregiver'`, `'Settings'`, `'Speak'`, `'Clear'`,
`'Tap words to build a sentence…'`, `'Start day 1'`. A Spanish-speaking parent
gets a Spanish board inside an English app, including the entire caregiver
onboarding that blueprint §1 identifies as our differentiator.

Blueprint §6 lists "UI strings + RTL layout pass" as non-optional per language.
**Fix**: `flutter_localizations` + ARB files, done **before** the French pack —
otherwise every new language adds to the debt.

### 7. RTL readiness while it is still cheap

Blueprint §6 wants Arabic as the RTL test case and warns that retrofitting costs
more than building direction-agnostic early. Three `EdgeInsets.only(left:/right:)`
uses should be `EdgeInsetsDirectional`, and the fixed-column grid needs an
explicit decision: **does the motor position mirror in RTL, or stay absolute?**
That is a clinical question (motor planning vs. reading direction), and answering
it now is nearly free.

### 8. Smaller things

- **Symbol assets are 500×500 PNGs rendered at 38 px** — 4.5 MB for 242 words.
  Fine now; against the blueprint's 10,000-word fringe target and <150 MB install
  budget, bundled core symbols should ship downscaled with fringe lazy-fetched.
- **`es.json` declares `version: 1`, `en.json` declares `version: 2`**, though
  they are mirrors. Pack versioning currently means nothing — define it or drop it.
- **The board is tablet-only in practice.** Eight fixed columns at phone width
  (~400 px) gives ~50 px cells holding a 38 px symbol plus a label. That is
  probably the right call for motor planning, but it should be a stated minimum
  screen size, not an accident.
- **`pubspec.yaml` uses the legacy `flutter_icons:` key** rather than
  `flutter_launcher_icons:`.
- **`wordById` throws on an unknown id** and is called from the `sentence`
  getter on every message-bar rebuild — a future pack that drops a word would
  crash the board rather than skipping the word.

## Proposed order to MVP

1. **Testability seam + board widget tests** (refactor 1). Everything else is
   safer afterwards.
2. **Grid indexing + `GridView.builder`** (refactor 2). Cheap, and it is a
   stated exit criterion.
3. **Drift + per-profile settings** (refactors 3 and 4 together — one storage
   change, not two).
4. **TTS degradation + Fire tablet pass** (refactor 5). Directly serves
   "50 families complete setup unassisted".
5. **UI localization** (refactor 6), then the Spanish SLP fixes land in a UI a
   Spanish-speaking family can actually navigate.
6. **Symbol QA fixes applied** — run `tools/fetch_symbols.py --review` somewhere
   with ARASAAC access, get SLP sign-off on the choices, apply. The 18
   wrong-meaning pictograms should not reach a pilot family.
7. **Usage insights** (most-used words), which the Drift event table makes easy
   and which supplies the "4-week retention tracked" half of the exit criterion.
8. **Custom photos and recordings** — the most-requested parent feature, and
   the one incumbents all ship.
9. **Backend sync v1**, then **store submissions** (Play, App Store, Amazon
   Appstore for Fire).

**Not now**, per the blueprint's own scope discipline (§9.8): adult typing mode,
switch scanning, neural voices, eye tracking, and the French pack — French
should wait until the Spanish pack has been through SLP review, so the process
is proven once before it is repeated.
