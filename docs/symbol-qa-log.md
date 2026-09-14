# Symbol QA log — overnight pass 2026-09-14

**Scope:** all 242 word pictograms reviewed (192 core + 50 folder words), each PNG
viewed individually against its English label for a nonverbal child (~3–10).
**Result:** 25 pictograms replaced (PNG contents only — filenames, word ids, and
grid positions unchanged). `manifest.json` unchanged (word-id list unaffected).

**Method:** 4 parallel reviewers (3× core, 1× folders). Priority suspects were
MAPPING.md `[retry]` lines and keyword/label mismatches. Replacements sourced
from the ARASAAC API (`api.arasaac.org/api/pictograms/en/search/<term>`,
downloaded via `/api/pictograms/<id>?download=true`, 500×500 PNG) and visually
confirmed after writing. All pictograms remain (c) ARASAAC, CC BY-NC-SA.

## Swaps (25)

| Word id | Label | Old ARASAAC id → New | Reason |
|---|---|---|---|
| core.want | want | unmapped → 36518 | Was disembodied hand reaching for ball; now whole person arms outstretched toward ball |
| core.need | need | unmapped → 7171 | Was finger on abstract red oval; now person with raised arms — unambiguous need |
| core.out | out | unmapped → 2806 | Was burnt-out candle (keyword miss); now person walking out a door |
| core.down | down | unmapped → 5355 | Was person climbing pool ladder; now "below" circle mirroring the "up" pictogram |
| core.look | look | unmapped → 16907 | Was pixel-identical to "see"; now person shading eyes looking into distance |
| core.tell | tell | unmapped → 5973 | Was pixel-identical to "say"; now storyteller narrating to a child |
| core.ask | ask | unmapped → 9847 | Was two people passing a ball (read as "give"); now head with "?" bubble |
| core.close | close | unmapped → 24022 | Old abstract red circle unreadable; person closing a door |
| core.pull | pull | unmapped → 36454 | Old showed toilet flush chain; tug-of-war shows clear pulling |
| core.wait | wait | unmapped → 35187 | Old figure = "stand"; people queuing clearly shows waiting |
| core.myturn | my turn | unmapped → 7158 | Old playground scene duplicated my/your turn; person pointing at self + turn arrow |
| core.yourturn | your turn | unmapped → 6625 | Same duplicated playground image; person pointing at viewer |
| core.uhoh | uh-oh | 35529 → 26985 | Old surprised face ≈ "wow"; facepalm with "!?" = something went wrong |
| core.oops | oops | 11625 → 6922 | Old hand-on-chest read as "sorry"; sheepish blushing face = "oops!" |
| core.old | old | unmapped → 34894 | Old cracked egg-blob unreadable; elderly person with cane |
| core.right | right | 5397 → 9202 | Old thumbs-up (keyword "well") — wrong meaning; blue right arrow mirrors core.left |
| core.front | front | 39779 → 5438 | Old building facade; new conveys spatial "in front/ahead" |
| core.light | light | unmapped → 5545 | Old light bulb read as lamp/idea; feather = AAC light-vs-heavy convention |
| core.today | today | 7131 → 38276 | Old sun+arrow read as sunset; calendar with highlighted day (matches tomorrow/yesterday) |
| play.park | park | 5379 → 2859 | Old showed cars parked on a road ("to park" mismatch — worst in set); playground |
| play.outside | outside | 5475 → 2806 | Old abstract diagram; person walking out a door |
| play.game | game | 6170 → 37952 | Old soccer on TV; two figures tossing a ball |
| food.water | water | 32464 → 4768 | Old faucet (sink? wash?); clear glass of water |
| play.music | music | 24791 → 6960 | Old staff notation; singing face with notes |
| feel.tired | tired | 35537 → 8513 | Old droopy face read as sad; yawning face, hand over mouth |

Note: `core.out` and `play.outside` intentionally share pictogram 2806 (person
exiting a door) — the words are closely related.

## Checked but kept — recommend human SLP review

- **core.try** (HIGH priority): current image is a courtroom "trial" (judge +
  gavel), not the verb "try/attempt". No usable ARASAAC alternative found.
- **core.new**: green egg with shine lines is meaningless; ARASAAC's only "new"
  pictograms are that egg, a "new car", and New Year items.
- **core.just**: justice scales for "just" (= merely). No "just" pictogram exists.
- **core.about**: roundabout traffic sign for "about" (= concerning). Nothing better exists.
- **core.her**: woman+arrow+faces mirrors "she" but doesn't convey possession;
  no distinctly female possessive pictogram found.
- **core.only**: number "1" — semi-reasonable as "just one", could read as the number.
- **core.gentle**: hand touching soft blue blob — ambiguous but not clearly wrong.
- **core.do**: shares "make"'s hammering-clay pictogram; nothing distinct for "do".
- **core.it / core.where / core.how / core.the**: abstract ARASAAC conventions,
  acceptable but odd; nothing better found.
- **feel.brave**: raised fist + starburst reads "strong/power"; only candidate for "brave".
- **feel.silly**: tongue-out face OK; odd pointing-at-red-dot detail; only candidate.
- **feel.hurt**: bloody cut is concrete for "owie" but may read scary for youngest.
- **feel.love**: heart + thumbs-up (keyword "like"); big red heart dominates — reads as love.
- **people.sister/brother/cousin/aunt**: kinship diagrams with arrow; complex but
  standard convention; only same-style variants exist.
- **food.yucky**: tongue-out + red X reads as disgust — kept.

## Duplicates resolved

"look"/"see", "tell"/"say", and "my turn"/"your turn" were pixel-identical
pictogram pairs — each now has a distinct image (motor-planning hazard removed).

## Remaining work

Every match above was a first-search-hit or reviewer-picked ARASAAC pictogram.
A human SLP should still review MAPPING.md end-to-end before any pilot,
especially the "checked but kept" list above and the abstract function words.
