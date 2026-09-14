# VidaCare AAC App — Product Blueprint

**Owner:** VidaCarefoundation.org (nonprofit)
**Mission:** One affordable, multilingual AAC app for nonverbal children and adults — the best of every existing app, not locked to iPad, priced for families.
**Date:** 2026-09-13
**Status:** Draft for review. All prices/features cited to sources; anything unverified is labeled ESTIMATE or ASSUMPTION.

---

## 1. Problem & Market Teardown

### The gap

The AAC app market is split into two bad options for families:

1. **Clinical-grade, expensive, Apple-only.** The best apps cost $150–$300 upfront *and* require an iPad ($329+ new). Total first-year cost of ownership routinely exceeds $500–$600 per user.
2. **Affordable, but limited.** Free/freemium apps exist but are kids-only, vocabulary-limited, single-language, or subscription-gated for core features.

Nobody ships: full core-word vocabulary + cross-platform (cheap Android tablets) + genuinely multilingual + caregiver-grade onboarding + nonprofit pricing. That is the product.

### Competitor table

| App | Vendor | Price (verified Sep 2026) | Platforms | Strengths | Gaps we exploit |
|---|---|---|---|---|---|
| Proloquo2Go | AssistiveWare | **$149.99 USD** one-time on official site; third-party trackers show $249.99 (likely stale/regional) [^1][^2] | iOS, macOS, watchOS only [^1] | Crescendo vocabulary: research-based core-word placement + 10,000+ fringe words; 25,000+ symbols; 100+ Acapela neural voices; bilingual EN/ES/FR/NL with mid-sentence switching [^3] | iOS lock-in; $150 + iPad = $500+ entry; setup is heavy (multiple comparisons note hours of setup/videos); Apple Personal Voice is English-only and literacy-gated [^4] |
| LAMP Words for Life | PRC-Saltillo | **~$299.99** iOS (price history shows $149.99–$299.99) [^5] | iOS only | One motor pattern per word; Unity language system; Vocabulary Builder; strong motor-planning evidence base | Most expensive app option; no trial; "very little guidance offered to new users" unless a Support Plan is purchased [^6] |
| Speak for Yourself | SFY LLC / AbleNet | **$299.99** + in-app purchases [^7] | iOS only | Every word reachable in ≤2 taps; designed by SLPs; motor-learning foundation | iOS-only; English only; $300 sticker shock |
| TD Snap | Tobii Dynavox | **$49.99 + subscription** (~$9.99/mo per recent roundup) [^8][^9] | iOS, Android, Windows, web [^10] | Cross-platform; Core First / Motor Plan / PODD page sets; eye-tracking ecosystem; cloud accounts; "Help and Tutorials" section | Subscription stacking gets expensive; premium voices inconsistent across platforms [^11]; onboarding still thin ("not much onboarding support from the CoughDrop team" applies industry-wide — see Goally comparisons) |
| CoughDrop | CoughDrop Inc. | **$9/mo or $295 lifetime** per communicator; 2-month free trial; free supporter accounts [^10] | iOS, Android, Windows, Chromebook, web [^10] | The cross-platform + offline + cloud-sync reference implementation; Open Board Format (OBF) support; modeling mode; switch/eye/head tracking | $9/mo is still $108/yr forever for a family; UI described as clunky in older reviews; modeling UX exposes settings on the user's device [^11] |
| Spoken – Tap to Talk | Spoken | **Free**; premium $12.99/mo, $99.99/yr, $249.99 lifetime [^12] | Android, iOS, Mac [^12] | Only major app designed *for adults*; predictive text learns your speech patterns; type/draw/handwrite input; context-aware suggestions | Not symbol-based — unsuitable for pre-literate users and many children; premium lifetime costs as much as Proloquo2Go |
| Leeloo AAC | DOYBLS | **Free**; premium $6.99/mo, $59.99/yr, lifetime $99.99–$149.99 (sources vary) [^12][^13] | Android, iOS [^12] | Best kids-first design; multiple profiles; many languages; genuinely free base tier | Limited vocabulary — "would not suggest for adult AAC users or anyone who needs a robust vocabulary" [^12]; removed from Google Play at one point (APK sideload only) — a distribution cautionary tale [^12] |
| Avaz | Avaz Inc. | $9.99/mo, $99.99/yr, $299.99 lifetime [^14] | Android | Strong Android option; vocabulary levels by age; multiple Indian languages | Same pricing tier as the expensive incumbents; no free tier |

### What the teardown tells us

- **The price anchor is $150–$300 + iPad.** Beating that decisively (sub-$100 total entry, ideally $0 to start) is the single biggest differentiator — bigger than any feature.
- **Nobody owns onboarding.** Every comparison notes weak tutorials, heavy setup, or absent coaching. A guided first-run + caregiver modeling coach is an open lane.
- **Multilingual is shallow everywhere.** Proloquo2Go covers 4 European languages; Leeloo lists ~29 languages but with thin vocabulary. Deep, SLP-reviewed vocabulary in 6–8 languages would be a first.
- **Cross-platform + offline + cloud sync is proven** (CoughDrop), but nobody pairs it with nonprofit pricing.
- **Open symbol libraries are production-ready** (see §5) — incumbents pay for SymbolStix/PCS licenses; we don't have to.

---

## 2. Product Vision — "Best of All in One"

### Design principles

1. **Runs on the device the family already owns** — or a $60 tablet, not a $329 iPad.
2. **Free to start, cheap forever.** No family should be priced out of communication.
3. **Motor planning is sacred.** Core words never move. (This is the LAMP/SFY insight and the #1 clinical non-negotiable.)
4. **Caregivers are first-class users.** Modeling tools, tutorials, and progress live alongside the communicator's board — not buried in settings.
5. **Every language is a first-class language**, not a translation layer.

### Feature synthesis (what we take from whom)

| Capability | Source of the idea | Our implementation |
|---|---|---|
| Core-word engine: 200–400 core words in fixed positions (research: core words ≈ 80% of daily speech) | Proloquo2Go Crescendo, LAMP | Fixed-position core grid; positions locked across vocabulary levels; progressive reveal as skills grow |
| 10,000+ fringe vocabulary | Proloquo2Go (10k+), SFY (14k) | Fringe word packs per language, lazy-downloaded, cached offline |
| ≤2-tap access to every word | Speak for Yourself | Navigation depth budget: no word more than 2 taps from home; enforce in vocabulary QA |
| One motor pattern per word | LAMP | Consistent motor paths; never reshuffle on updates |
| Customizable grids, photos, recorded audio | Proloquo2Go, CoughDrop | Grid size 1–144 buttons; per-button symbol/photo/text/voice recording |
| Typing + word prediction + handwriting | Proloquo2Go, Spoken | Keyboard view with prediction for literate users (adult mode) |
| Predictive, learning vocabulary | Spoken | On-device personalization: frequently used fringe words surface; no cloud needed |
| Cloud sync + offline-first | CoughDrop | Local-first database; sync when online; works fully offline after first setup |
| Free supporter/caregiver accounts | CoughDrop | Unlimited caregiver profiles free; separate "modeling mode" that doesn't hijack the communicator's screen (fixing CoughDrop's modeling UX gap) |
| Multiple user profiles | Leeloo | Profiles per communicator on shared devices (schools, clinics) |
| Guided onboarding + in-app coaching | Nobody does this well | Interactive first-run: 10-minute setup wizard; daily 2-minute modeling tips for caregivers; video library co-designed with SLPs |
| Bilingual mid-sentence switching | Proloquo2Go | Per-button language tagging; switch languages without leaving the board |

### Accessibility roadmap

- **MVP:** Touch (direct selection), full offline, high-contrast mode, adjustable button sizes/timing.
- **v1:** Switch scanning (auditory + visual), dwell selection, keyguard-friendly layouts.
- **v2:** Eye/head tracking hooks (platform APIs), Apple VoiceOver / Android TalkBack deep integration, personal voice banking hooks.

[^1]: https://www.assistiveware.com/products/proloquo2go (official price table lists USD 149.99)
[^2]: https://www.appbrain.com/appstore/proloquo2go-aac/ios-308368164 ($249.99)
[^3]: https://www.assistivetech.com.au/collections/apps/products/proloquo2go-app-for-ipad (Crescendo 10,000+ fringe, 25,000+ symbols, 100+ Acapela voices, bilingual mid-sentence switching)
[^4]: https://github.com/ahayman/ai-research (voice-cloning cost/access gaps; Apple Personal Voice English-only)
[^5]: https://appagg.com/ios/education/lamp-words-for-life-3554468.html (price history $149.99–$299.99, current $299.99)
[^6]: https://getgoally.com/compare-aac-apps/touchchat-vs-lamp-word-for-life-aac/ (setup/onboarding scores)
[^7]: https://spokenaac.com/best-aac-for-ios/ ($299.99, ≤2 taps, SLP-designed)
[^8]: https://rareparenting.com/tablet-aac-apps-nonverbal-kids/ ($49.99 + monthly subscription)
[^9]: https://spokenaac.com/best-aac-for-ios/ (TD Snap $9.99/mo)
[^10]: https://www.assistivetech.com.au/products/coughdrop-communicator-access-app-for-ipad ($9/mo or $295 lifetime, cross-platform, 8+ languages, 2-month trial)
[^11]: https://getgoally.com/compare-aac-apps/grid3-vs-coughdrop-aac/ (voice inconsistency, modeling UX, onboarding gaps)
[^12]: https://spokenaac.com/best-aac-apps/ (Spoken and Leeloo pricing, platform availability, adult/kids positioning)
[^13]: https://apps.appfollow.io/ios/leeloo-aac-autism-speech-app/1508952198 (Leeloo lifetime $149.99 variant)
[^14]: https://spokenaac.com/best-aac-for-android/ (Avaz pricing)

---

## 3. User Segmentation — Phased Approach

### The two users are genuinely different products

| | Children (emerging communicators) | Adults (literate / acquired conditions) |
|---|---|---|
| Primary buyer/onboarder | Parent, teacher, SLP | The user themselves, or a spouse/caregiver |
| Vocabulary need | Core words + school/home fringe; grows over years | Broad adult vocabulary: work, medical, finance, humor |
| Best input | Symbol grids, motor planning, caregiver modeling | Typing + prediction, phrase banking, TTS |
| Symbol style | Playful, high-iconicity, photo-friendly | Neutral, professional, dignity-preserving |
| Success metric | Language growth over months (new words, longer utterances) | Speed (words per minute), independence in specific situations |

### Recommendation: children first (MVP), adults in v1

**Why children for MVP:**

1. **The buyer is not the user.** Parents/SLPs do setup and onboarding — this lets us ship a caregiver-guided first-run (our differentiator) without requiring the communicator to self-onboard. Adult self-onboarding is a harder UX problem.
2. **Highest impact per dollar for a nonprofit.** Early-intervention window + parents paying out of pocket = the affordability story is strongest here, and it's the strongest grant narrative (pediatric disability, special education).
3. **Smaller scope, faster MVP.** A core-word symbol grid with 2–3 vocabulary levels is a bounded build. Adult mode needs prediction engines, phrase banking, and typing UX — a second product surface.
4. **Market proof.** Leeloo validated that a kids-first, free-tier AAC app gets adoption on Android+iOS [^12]; its failure was vocabulary depth, which we fix.

**Why adults must be v1, not v2:** Spoken proves adults are underserved by symbol-only apps, and acquired conditions (ALS, stroke, aphasia) skew adult. Shipping an "adult mode" — typing-first UI, predictive text, professional symbol styling, quick phrases (medical, emergency, daily living) — within the same app, sharing the sync/profile/TTS infrastructure, doubles the addressable mission without doubling the platform cost.

**Phasing:** MVP = kids core (symbol grids, 1 language deep + 1 shallow). v1 = adult mode + multilingual expansion. v2 = advanced access methods + institutional tooling.

---

## 4. Technical Architecture

### Cross-platform: Flutter (recommended)

| Option | Verdict |
|---|---|
| **Flutter** | **Pick.** One codebase for iOS, Android, web, and desktop; 60fps custom grid rendering (critical for large symbol grids); mature TTS plugin (`flutter_tts` wraps iOS AVSpeechSynthesizer + Android TextToSpeech); strong offline story; no dependency on Expo's native-module ceiling for accessibility APIs. |
| React Native + Expo | Defensible runner-up — larger JS talent pool, and an open-source AAC project (SayThrough) ships React Native + Expo with web-first via react-native-web [^15]. But Expo constrains native modules (switch access, TTS edge cases), and grid-heavy UIs are smoother in Flutter. |
| Native (Swift + Kotlin) | Rejected: 2x engineering cost for zero user-visible benefit at this stage. |
| PWA only | Rejected: TTS reliability and offline behavior on iOS Safari are not good enough for a communication device. Ship native shells; web as companion (caregiver portal, board editing). |

### Offline-first design

- **Local-first database** (SQLite via Drift): vocabulary, profiles, settings, symbol cache. The app must be 100% functional with no network after first setup — a communication device cannot depend on connectivity.
- **Symbol strategy:** bundle the ~400 core-word symbols in the install; lazy-fetch fringe symbols on first use and cache permanently (IndexedDB/SQLite blob store). This keeps install size sane (Proloquo2Go ships ~956MB [^2] — we should target <150MB initial).
- **Sync:** lightweight backend (see below) syncs profiles/boards/usage stats when online; conflict resolution = last-writer-wins per board with version vectors. Caregiver edits on web propagate to the device.

### Language-pack architecture

Each language ships as a versioned **pack**: `{ vocabulary.json, symbol-map.json, tts-config.json, grammar-hints.json }`.

- `vocabulary.json`: core words (fixed IDs, fixed grid positions), fringe words by category, phrases. Word IDs are language-independent (`core.want`) so a bilingual user keeps motor positions across languages.
- `symbol-map.json`: word ID → symbol asset (ARASAAC/Mulberry/custom). Falls back to text label when no symbol exists.
- `tts-config.json`: locale, preferred voice list, rate/pitch defaults per language.
- Packs download on demand, cached offline, independently updatable without app release. Community contributors can submit packs via GitHub; SLP review gate before publish.

### TTS engine options

1. **On-device OS TTS (default, free):** iOS AVSpeechSynthesizer + Android TextToSpeech. Zero marginal cost, works offline, covers 30+ languages via system voices. Quality is the tradeoff — acceptable, not delightful.
2. **Bundled neural voices (v1+):** License a compact neural TTS (e.g., Acapela-style voices as used by Proloquo2Go [^3], or an open model like Piper/Coqui) for flagship languages. Ship 2–4 high-quality voices per launch language as downloadable packs.
3. **Voice banking / cloning (v2):** platform hooks (Apple Personal Voice where available) or partner API; note current gaps — Personal Voice is English-only and literacy-gated [^4], so don't depend on it.

### Backend needs (keep it boring)

- Auth + profiles (email/OAuth; COPPA-aware — no accounts for under-13 without parent).
- Board/profile sync, language-pack CDN, anonymized usage analytics (opt-in; needed for grant reporting on outcomes).
- Caregiver web portal (board editing, modeling guides, progress dashboards).
- Stack suggestion: Postgres + a simple API (Adam's call on framework), object storage for symbols/voices, CDN for packs. No ML infra needed until predictive features in v1 — and even then, on-device personalization first.

### Build phases (scope, not dates)

- **Phase 0 — Foundation (ESTIMATE: 6–10 weeks, 2 engineers):** Flutter shell, grid engine, SQLite local-first store, OS TTS, ARASAAC symbol pipeline, English core pack (400 words), 1 profile, no backend.
- **Phase 1 — MVP (ESTIMATE: +8–12 weeks):** vocabulary levels + progressive reveal, fringe packs, custom photos/recordings, caregiver onboarding wizard + modeling tips, backend sync v1, Spanish pack, Amazon Appstore + Play Store + App Store submission.
- **Phase 2 — v1 adult mode (ESTIMATE: +8–12 weeks):** typing/prediction UI, phrase banking, adult symbol styling, 2 more languages, switch scanning, web caregiver portal.
- **Phase 3 — v2 (ESTIMATE: ongoing):** premium neural voices, eye/head tracking hooks, school/clinic admin console, outcomes analytics for grants.

Estimates assume engineers with Flutter + AAC/SLP advisor involvement; clinical review is on the critical path, not just code.

[^15]: https://github.com/3583bytes/saythrough (open-source AAC: React Native + Expo, local-first, ARASAAC symbols, expo-speech TTS)

---

## 5. Symbol & Voice Sourcing

### Symbols: ARASAAC primary, Mulberry secondary

| Library | License | Size | Implication for VidaCare |
|---|---|---|---|
| **ARASAAC** (Government of Aragón, by Sergio Palao) | **CC BY-NC-SA** (4.0; older sets 3.0) — free for non-commercial use with attribution [^16][^17] | 30,000+ pictograms; color, B/W, photos, sign-language videos [^16] | Fits a nonprofit free app perfectly. **Constraint:** the NC (non-commercial) clause means any future paid tier must be reviewed — keep ARASAAC assets in the free tier or negotiate terms. REST API available (`api.arasaac.org`) with PNG at configurable resolution [^18]. |
| **Mulberry Symbols** (Steve Lee) | **CC BY-SA 4.0** — commercial use allowed with attribution; derived symbols stay under the same license; you may charge for added value but not for the symbols themselves [^19] | Smaller set, clean modern style | The safe choice for anything behind a paywall. Use for adult mode and premium styling. |

**Strategy:** dual-source with attribution screens. ARASAAC for the free kids' core (nonprofit use = NC-compliant), Mulberry where commercial flexibility matters. Custom photo upload always available (all incumbents offer this; parents expect it). High iconicity matters for learning — ARASAAC pictograms score well on transparency/iconicity in published research [^16].

### Voices: see §4 TTS options. Default to free on-device TTS; neural voice packs as the premium upsell, never the gate to basic communication.

---

## 6. Multilingual Plan

### Launch order (recommended)

1. **English** — MVP. Deepest SLP review resources; largest user base.
2. **Spanish** — first expansion. Largest US non-English AAC need; ARASAAC originates in Spain so Spanish symbol metadata and vocabulary structure already exist [^16][^17]; Proloquo2Go parity language [^3].
3. **French** — competitive parity (Proloquo2Go supports it [^3]); strong Canadian/European nonprofit funding angle.
4. **Portuguese or Arabic** — Portuguese for Brazil/LatAm reach; **Arabic as the RTL test case** (TouchChat already ships Arabic+Hebrew [^20], proving demand; RTL forces the layout engine to be direction-agnostic early, which is cheaper than retrofitting).

### Per-language work (checklist, not optional)

- Core-word list adapted by a native-speaking SLP (core words don't translate 1:1 — frequency lists differ by language).
- Symbol mapping review (some ARASAAC symbols are culture-specific).
- TTS voice evaluation per locale (quality varies wildly by language on OS TTS).
- UI strings + RTL layout pass.
- Bilingual mode: per-button language tags, mid-sentence switching like Proloquo2Go [^3].

### What NOT to do

Don't ship 29 shallow languages (the Leeloo trap [^12]). Ship fewer languages with full core+fringe depth and SLP sign-off. Depth beats count for clinical credibility and grant applications.

---

## 7. Nonprofit Pricing & Sustainability

### Proposed tiers

| Tier | Price (proposed) | Includes |
|---|---|---|
| **Free** | $0 forever | Full core vocabulary, 1 language, 1 profile, OS TTS voices, ARASAAC symbols, offline use |
| **Plus** | **$4.99/mo or $39/yr** (ESTIMATE — set after cost modeling; positioned well under CoughDrop's $9/mo [^10]) | Everything in Free + all languages, cloud sync, unlimited profiles, neural voice packs, caregiver web portal, priority support |
| **Lifetime** | **$149 one-time** (ESTIMATE — undercuts CoughDrop $295 [^10] and Spoken $249.99 [^12]) | Plus, forever |
| **Schools / clinics** | Per-site annual (TBD after pilot) | Admin console, bulk profiles, outcomes reporting, PD/training |

### Unit-economics reasoning

- **Marginal cost per free user ≈ $0.** On-device TTS, bundled/cached symbols, local-first storage. The expensive inputs incumbents pay for (SymbolStix/PCS licenses, Acapela per-seat voice licenses) are replaced by open libraries and OS voices.
- **Real costs:** engineering, SLP clinical review (per language), app-store fees, backend hosting (tiny at start — sync payloads are JSON), support. Support is the sleeper cost: budget for it from day one (a part-time AAC-trained support lead beats a ticket queue).
- **Break-even logic (ASSUMPTION, model before committing):** if Plus converts at even 5–10% of active users at $39/yr, hosting+support per user must stay under ~$2–4/yr. Achievable with the local-first architecture (§4) — the backend is sync + CDN, not compute.
- **Hardware wedge:** certify and recommend Fire HD 8/10 (regularly $55–$130 on sale [^21][^22]) and publish to the **Amazon Appstore** — Fire tablets don't ship Google Play [^21]. A "VidaCare AAC bundle" (app + setup guide + optional donated tablet program) is a concrete, fundable offering.

### Grant funding (program types — verify current solicitations on grants.gov before applying)

- **NIDILRR Disability and Rehabilitation Research Projects (DRRP)** — explicitly funds assistive-technology R&D for independent and community living [^23]. Nonprofits are eligible applicants [^24].
- **NIDILRR Rehabilitation Engineering Research Centers (RERC)** — funds engineering research + tech transfer of assistive tech; recent rounds include AI-driven assistive tech [^24].
- **NIH NIDCD AAC research** — NIH's communication-disorders institute has run AAC-specific funding (e.g., the R21 "Advancing Research in AAC" program [^25]; expired, but the program area is active — watch for reissues).
- **U.S. Department of Education, Office of Special Education Programs (OSEP)** — technology to support students with disabilities; state assistive-technology programs are also distribution partners.
- **Private disability foundations** — many fund AAC access and pediatric disability tech; approach with pilot-outcome data, not just a pitch deck.
- **Corporate / platform grants** — accessibility programs at major tech companies periodically fund assistive-tech nonprofits.

Grant strategy: **build the MVP on donations, use pilot outcomes (words gained, utterances, family NPS) as the evidence base, then apply for R&D grants to fund v1/v2.** Funders buy measured communication outcomes, not app ideas.

---

## 8. Roadmap

| Milestone | Scope | Exit criteria |
|---|---|---|
| **M0 — Foundation** | Flutter shell, grid engine, SQLite local-first, OS TTS, ARASAAC pipeline, English core-400 | Runs fully offline on Android + iOS; 60fps grid; SLP signs off core list |
| **MVP — Kids core** | Vocabulary levels + progressive reveal, fringe packs, photos/recordings, caregiver onboarding wizard + modeling tips, backend sync v1, Spanish pack, store submissions (Play, App Store, **Amazon Appstore**) | 50 pilot families complete 10-min setup unassisted; 4-week retention tracked |
| **v1 — Adult mode + multilingual** | Typing/prediction UI, phrase banking, adult styling, +2 languages, switch scanning, caregiver web portal, neural voice packs (Plus) | Adult pilot (ALS/stroke/aphasia orgs); Plus tier live |
| **v2 — Access + institutions** | Eye/head tracking hooks, school/clinic admin console, outcomes analytics, Arabic (RTL), donated-tablet program | 10 school/clinic sites; grant-funded outcomes study published |

---

## 9. Risks & Open Questions for Adam

1. **Clinical credibility is the moat — and the bottleneck.** Every vocabulary decision needs SLP review. Do we have 1–2 SLP advisors lined up? Without them, schools and grant reviewers won't take the app seriously.
2. **ARASAAC's NC license vs. a paid tier.** Free tier = clean. The moment Plus exists, get a written read on whether bundled ARASAAC symbols in a freemium app violates BY-NC-SA. Mulberry (BY-SA) is the fallback — decide the symbol split before writing paywall code.
3. **Support burden.** AAC apps generate high-touch support (setup, vocabulary questions, device issues). A nonprofit can't out-staff this — the onboarding wizard and video library must deflect 80%+ of tickets. Budget a support lead in the grant applications.
4. **App-store kids' compliance.** COPPA (under-13 accounts), Apple's kids-category rules, Google Play's Families policy. Design auth/profiles around this from M0, not as a retrofit.
5. **Voice quality expectations.** OS TTS in Spanish/French/Arabic varies in quality; if the free voice sounds robotic, users blame the app. Evaluate per-locale voices during each language pack build.
6. **Android fragmentation + Fire OS.** Test matrix must include Fire HD 8/10 (Fire OS quirks, no Play Services) — these are the actual devices low-income families buy [^21].
7. **Leeloo's Play Store removal** [^12] is a warning: keep builds compliant, maintain the Amazon Appstore listing as a hedge, and keep an APK distribution path.
8. **Scope discipline.** The #1 risk is building the adult product, the kids product, 8 languages, and eye tracking in the MVP. The phasing in §3/§8 exists to prevent exactly this.

---

### Sources

[^1]: https://www.assistiveware.com/products/proloquo2go
[^2]: https://www.appbrain.com/appstore/proloquo2go-aac/ios-308368164
[^3]: https://www.assistivetech.com.au/collections/apps/products/proloquo2go-app-for-ipad
[^4]: https://github.com/ahayman/ai-research
[^5]: https://appagg.com/ios/education/lamp-words-for-life-3554468.html
[^6]: https://getgoally.com/compare-aac-apps/touchchat-vs-lamp-word-for-life-aac/
[^7]: https://spokenaac.com/best-aac-for-ios/
[^8]: https://rareparenting.com/tablet-aac-apps-nonverbal-kids/
[^9]: https://spokenaac.com/best-aac-for-ios/
[^10]: https://www.assistivetech.com.au/products/coughdrop-communicator-access-app-for-ipad
[^11]: https://getgoally.com/compare-aac-apps/grid3-vs-coughdrop-aac/
[^12]: https://spokenaac.com/best-aac-apps/
[^13]: https://apps.appfollow.io/ios/leeloo-aac-autism-speech-app/1508952198
[^14]: https://spokenaac.com/best-aac-for-android/
[^15]: https://github.com/3583bytes/saythrough
[^16]: https://revistas.ucm.es/index.php/RLOG/article/download/101612/4564456575687 (ARASAAC: CC BY-NC-SA, 30,000+ pictograms, multilingual, iconicity research)
[^17]: https://openassistive.org/item/arasaacpictograms/ (CC BY-NC-SA licensing)
[^18]: https://github.com/scottgandhi-ship-it/aac-board/blob/HEAD/.project/features/SymbolLibrary.md (ARASAAC REST API, PNG at configurable resolution)
[^19]: https://github.com/mulberrysymbols/mulberry-symbols/blob/HEAD/docs/README.md (CC BY-SA 4.0; commercial use allowed with attribution; cannot charge for the symbols themselves)
[^20]: https://getgoally.com/compare-aac-apps/touchchat-vs-lamp-word-for-life-aac/ (TouchChat: English, Spanish, Hebrew, Arabic)
[^21]: https://gizmodo.com/amazon-fire-hd-10-tablet-is-now-a-budget-ipad-alternative-no-prime-day-needed-to-get-it-this-cheap-2000800756 (Fire HD 10 ~$130; Fire OS = Amazon Appstore, no Google Play)
[^22]: https://www.androidauthority.com/amazon-fire-hd-10-half-price-deal-3709324/ (Fire HD 10 at $76.99 record low; Fire HD 8 at $54.99)
[^23]: https://acl.gov/news-and-events/news/new-grants-forecasted-research-and-development-projects-assistive-technology (NIDILRR DRRP assistive-technology R&D)
[^24]: https://simpler.grants.gov/opportunity/c08bbf7a-563b-4af4-a79b-b1cb7bdd71ad (NIDILRR RERC; nonprofits eligible)
[^25]: https://grants.nih.gov/grants/guide/pa-files/PA-19-046.html (NIH NIDCD R21 "Advancing Research in AAC" — expired; program area precedent)
