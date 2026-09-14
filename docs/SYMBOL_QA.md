# Symbol QA pass — ARASAAC pictograms (v0.02 → MVP)

**Reviewer:** automated visual QA, 2026-09-14. **Status:** findings only — no
asset was changed. **Scope:** all 242 bundled pictograms, reviewed as rendered
images (not as search keywords).

> Word **ids and grid positions are untouched** by everything in this document.
> Replacing a pictogram swaps the PNG behind an id; the motor position never
> moves. That invariant is what makes this pass safe to run at any time.

## How this review was done

`assets/symbols/MAPPING.md` records the ARASAAC id for only **100 of the 242**
words (entries stop after the last fetch batch). Keyword-only review was
therefore impossible for 142 words, and unreliable for the rest — a keyword can
look right while the returned pictogram is wrong.

So every one of the 242 PNGs was rendered into labelled contact sheets and
reviewed against its English label, then the high-risk sets were re-rendered at
**38 px** — the real size `SymbolImage` draws at (`word_button.dart`, `38 *
scale`). Several findings below are only visible at that size.

## Summary

| Severity | What it means | Count |
|---|---|---|
| **P0 — wrong meaning** | The picture shows a different word. Teaches the wrong concept. | 18 |
| **P1 — duplicate** | Two distinct words share one picture. Teaches that they are the same word. | 11 |
| **P2 — mismatched pair** | Antonyms drawn from different domains; the contrast doesn't read. | 8 |
| **P3 — illegible at 38 px** | Distinct in a contact sheet, identical on a real button. | 6 sets |
| **P4 — style / culture / content** | Mixed art styles, culture-specific, or low-iconicity. | 11 |

**Headline:** 18 pictograms currently depict the wrong word, and 11 more are
duplicates. That is ~29 of 242 (12%) that would actively mislead a learner.
Three are serious enough to block a pilot on their own: `core.try` shows a
**courtroom trial**, `core.pull` shows **flushing a toilet**, and `core.just`
shows the **scales of justice**.

---

## P0 — Wrong meaning (replace before any pilot)

Homonym errors: the search term matched a different sense of the English word.

| id | Label | What the picture actually shows | Replace with (ARASAAC search) |
|---|---|---|---|
| `core.try` | try | **A judge at the bench with a gavel, scales of justice, and a prisoner in stripes** — "trial", the legal sense | `attempt`, `effort`, `try to` |
| `core.just` | just | **Scales of justice** — the fairness sense (MAPPING confirms `keyword="justice"`) | `only`, `solely` |
| `core.about` | about | **A blue roundabout road sign** — "roundabout" (MAPPING: `keyword="roundabout"`) | `about`, `regarding`, `concerning` |
| `core.pull` | pull | **A child pulling a toilet cistern chain, toilet bowl in frame** — "flush" | `pull`, `pull rope`, `tug` |
| `core.right` | right | **A thumbs-up** — "right = correct" (MAPPING: `keyword="well"`). Sits beside a left *arrow*. | `right direction`, `turn right` |
| `core.front` | front | **A hatched architectural elevation** — a building facade (MAPPING: `keyword="facade"`) | `in front of`, `ahead` |
| `core.back` | back | **An anatomical human back/torso** — the body part | `behind`, `at the back` |
| `core.out` | out | **A blown-out candle with smoke** — "out" as extinguished | `out of`, `outside box` — must pair with `core.in`'s box diagram |
| `core.down` | down | **A person climbing down a ladder into a swimming pool** (photo-style, coloured) | `down arrow`, `downwards` — must pair with `core.up` |
| `core.close` | close | **An abstract angled line with a ball** — unreadable; not "shut" | `close door` — must pair with `core.open`'s door |
| `play.park` | park | **Cars parked along a street** — "to park a vehicle" | `playground`, `park green space` |
| `core.for` | for | **A clock face with a shaded sector** — duration (MAPPING: `keyword="during"`) | `for`, `intended for` |
| `core.only` | only | **The numeral "1"** (MAPPING: `keyword="one"`) | `only`, `solely` |
| `core.too` | too | **Identical to `core.more`'s red-squares graphic** (MAPPING: `keyword="more"`). ES label is *también* = "also". | `also`, `as well`, `too` |
| `core.light` | light | **A glowing lightbulb** — illumination. But the ES label is *ligero* (not heavy) and the board pairs it with `core.heavy`. | Decide the sense first (see note below), then `light weight` |
| `core.hard` | hard | **A finger tapping a rock** — rigid/solid. ES label is *difícil* (difficult) and it pairs with `core.easy` (a counting task). | `difficult` |
| `core.scary` | scary | **A terrified face biting its nails** — that is *being* scared, and it duplicates `feel.scared` | `frightening`, `scary thing` |
| `play.game` | game | **A TV screen showing a football match with a scoreboard** — watching sport | `board game`, `play game` |

**`core.light` / `core.bright` / `core.dark` need a decision, not just a swap.**
Right now `light` is a bulb, `bright` is a sun and `dark` is an unlit room — so
`light` and `bright` are the same concept twice, while the Spanish pack says
`light` means *weight*. Pick one: either `light` = the opposite of `heavy`
(recommended — it already pairs with `core.heavy` on the grid), or `light` =
illumination and `bright` becomes a fringe word.

---

## P1 — Duplicates: two words, one picture

The board currently teaches these word pairs as the *same* word. Each needs a
distinct pictogram for whichever word is listed second (or both).

| Words sharing one image | What they share | Recommendation |
|---|---|---|
| `core.make` = `core.do` | Identical: a person hammering a red shape | Keep for `make`; `do` → `do`, `carry out`, `activity` |
| `core.say` = `core.tell` | Identical: a head with a "BLA,BLA,BLA" bubble | Keep for `say`; `tell` → `tell someone`, `inform` (two figures) |
| `core.see` = `core.look` | Identical: a head with an arrow from the eye | Keep for `see`; `look` → `look at`, `watch` (directed gaze + object) |
| `core.myturn` = `core.yourturn` | Identical: a playground climbing frame — **and neither depicts turn-taking** | Both → `my turn` / `your turn` (two figures, one indicated) |
| `core.wow` = `core.uhoh` | Identical: a surprised face, open O mouth | Keep for `wow`; `uh-oh` → `oops`, `mistake` |
| `core.sorry` = `core.excuseme` = `core.oops` | **All three** identical: a sad figure, hand on chest | Keep for `sorry`; `excuse me` → `excuse me`, `may I pass`; `oops` → `mistake` |
| `core.dont` ≈ `core.no` | Both are a large red X; indistinguishable on a button | `don't` → negation over an action (a crossed-out figure), keeping `no` as the plain X |
| `core.my` ≈ `core.mine` | Both: one figure holding a red square | `mine` → possession contrasted with another person |
| `core.your` ≈ `core.yours` | Both: a figure pointing at another holding a red square | `yours` → as above, mirrored |
| `core.i` ≈ `core.me` | Both: a figure pointing at itself | Low priority — semantically close; acceptable to keep |
| `core.cleanv` = `core.cleand` | Same word (verb + adjective), same blank hanging cloth | Acceptable as a duplicate, but the cloth reads as "laundry", not "clean" — see P4 |

---

## P2 — Antonym pairs that don't read as pairs

Each may be defensible alone, but the board puts them side by side and the
contrast is the teaching point.

| Pair | Problem | Recommendation |
|---|---|---|
| `core.big` / `core.little` | `big` = red squares of decreasing size; `little` = a grey person beside a black person. Different domains entirely. | Refetch both from one `big`/`small` series |
| `core.hot` / `core.cold` | `hot` = a sweating face (sensation); `cold` = a glass of iced water (an object) | Refetch both as sensations (or both as thermometers) |
| `core.easy` / `core.hard` | `easy` = counting 1,2,3,4; `hard` = tapping a rock | Refetch both from one `easy`/`difficult` series |
| `core.light` / `core.heavy` | `heavy` = a balance scale; `light` = a lightbulb | See the P0 note — resolve the sense, then pair |
| `core.good` / `core.bad` | `bad` = thumbs-down, but `good` = **a face with a golden halo** (angelic/well-behaved, and religiously loaded) | `good` → thumbs-up from the same series as `bad` |
| `core.okay` | Is the thumbs-up — which is where `good` should be | Re-point after fixing `good`; `okay` → `OK` hand sign |
| `core.hello` / `core.goodbye` | Both are waving figures, differing only in fill colour | Differentiate (approach vs. depart) |
| `core.left` / `core.right` | `left` shows **two** arrows (grey right + blue left) — ambiguous; `right` is a thumbs-up (P0) | Refetch both as a single-arrow directional pair |

---

## P3 — Distinct on paper, identical on a real button

Rendered at 38 px — the size `SymbolImage` actually draws. These are not
theoretical; they are what the child sees.

| Set | Why it fails at 38 px |
|---|---|
| `core.tomorrow` / `core.yesterday` | Both are a blue-header wall calendar with one red-marked day and a tiny arrow. The arrow direction is the *only* difference and it is invisible. |
| `people.cousin` / `people.aunt` | Both are a greyed-out family group with a small black arrow under one member. Indistinguishable. |
| `core.the` / `core.and` / `core.but` / `core.or` / `core.because` | ARASAAC's connector glyphs — the same triangle/arrow differing only in rotation and fill. At 38 px `and` and `or` are two green triangles. |
| `core.with` / `core.to` / `core.from` | Three orange-box diagrams differing only in arrow placement. |
| `core.now` / `core.later` | Clock + pointing figure; differ only in the hand position and a small arrow. |
| `people.sister` / `people.brother` | Full family-group composites (4 figures + arrow) shrunk into 38 px. |

**This one is not fixable by swapping pictograms alone.** Two options, both
worth putting to the SLP:
1. Raise the symbol size on the button and let the label carry more weight
   (`word_button.dart` currently gives the symbol 38 px and the label 12 px).
2. Accept that closed-class words (`the`, `and`, `but`, `or`, `because`, `with`,
   `to`, `from`) are learned by **position and text**, not by icon — which is
   what LAMP and Speak for Yourself do — and give them a deliberately plain
   text-forward treatment instead of a near-identical glyph.

---

## P4 — Style, culture, and low iconicity

| id | Issue | Recommendation |
|---|---|---|
| `core.walk`, `core.goodnight`, `core.home`, `play.park`, `core.down` | Full-colour illustrative scenes mixed in among flat line pictograms — the board looks inconsistent and the detailed ones lose more at 38 px | Refetch the flat/line variants; ARASAAC offers both |
| `core.church` | A specific Catholic church with a cross and bell tower. Blueprint §6 flags culture-specific ARASAAC symbols. | Neutral place-of-worship, or move to a fringe pack |
| `core.bathroom` | A literal toilet bowl (MAPPING: `keyword="toilet"`) | Common in AAC and defensible — confirm with the SLP |
| `people.mom` / `people.dad` | Both show an adult **holding an infant** — reads as "parent of a baby", confusing for a child who is not one | Refetch adult-with-child, or plain adult |
| `core.loud` | A pair of hi-fi stereo speakers — device-specific, not the concept | `loud`, `noisy` |
| `core.stand`, `core.wait` | Near-featureless standing stick figures; almost no iconicity and similar to each other | `stand up` (with motion arrow), `wait` (clock + figure) |
| `core.old` | An ambiguous cracked brown oval | `old` (person) or `old` (worn object) — pick the sense that matches ES *viejo* |
| `core.start` | An abstract technical line-and-dash diagram | `start`, `begin` |
| `core.new` | A glowing green blob with rays | `new` |
| `core.a` | The literal letter glyph "a" | Meaningless pre-literacy — see the P3 closed-class note |
| `core.which` | A cluttered collage of toys with a "?" (MAPPING keyword is the whole sentence `"which game do you want?"`) | `which`, `choose between` |
| `core.cleanv` / `core.cleand` | A blank cloth on a line reads as "laundry" | `clean` (wiping/scrubbing) |
| `food.yucky` | A crossed-out face (MAPPING: `keyword="dislike"`) | Acceptable; confirm with the SLP |

---

## The four folder tiles have no pictogram at all

`folder.food`, `folder.feelings`, `folder.people` and `folder.play` have no PNG
in `assets/symbols/`, so `SymbolImage` falls back to the emoji in the language
pack. These are the four most important navigation targets on the board — every
word behind them is a 2-tap word — and they are the only cells rendered in a
different visual language from everything around them.

The README's claim that "emoji fallback remains in code but no word currently
needs it" is wrong on exactly these four tiles. Fetch pictograms for them
(`food`, `feelings`, `people`, `play`) or decide deliberately that folder tiles
are emoji-styled to mark them as navigation rather than vocabulary — either is
defensible, the current state is just unexamined.

## Process defects to fix alongside the assets

1. **`MAPPING.md` covers 100 of 242 words.** The other 142 have no recorded
   ARASAAC id, so their provenance and licence attribution cannot be audited.
   Regenerate it for every word.
2. **The fetch script was never committed.** The symbol pipeline is not
   reproducible — nobody can re-run or correct it. `tools/fetch_symbols.py`
   (added with this pass) fixes that.
3. **Search keywords were recorded, chosen pictograms were not reviewed.**
   Several MAPPING entries record a keyword that is plainly wrong
   (`"justice"`, `"roundabout"`, `"facade"`, `"well"`, `"during"`) and were
   still shipped. The fetch step needs a human review gate before assets land.

## How to apply the fixes

`api.arasaac.org` is blocked by this environment's egress policy (403 on
CONNECT — verified for `api.arasaac.org`, `arasaac.org` and
`static.arasaac.org`), so no replacement pictogram could be downloaded here.
Everything needed to run the pass elsewhere is committed:

```bash
# on any machine with access to api.arasaac.org
python3 tools/fetch_symbols.py --review          # show candidates for each flagged word
python3 tools/fetch_symbols.py --apply           # download + rewrite manifest & MAPPING.md
flutter test                                     # pack invariants must stay green
```

The script only ever writes `assets/symbols/<word_id>.png`,
`assets/symbols/manifest.json` and `assets/symbols/MAPPING.md`. It never touches
`assets/lang/*.json`, so **ids and grid positions cannot drift**.

## Licence

Pictograms © ARASAAC (Government of Aragón), author Sergio Palao, CC BY-NC-SA.
Attribution is shown in Settings and in the Caregiver hub. Per blueprint §9.2,
get a written read on the NC clause before any paid tier bundles these assets.
