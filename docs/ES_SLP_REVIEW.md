# Spanish pack — review list for a native-speaker SLP

**Source:** `assets/lang/es.json` (v0.02 draft, 192 core words + 50 folder words).
**Status:** nothing in this file has been changed. This is the question list.
**Reviewer needs:** native Spanish, AAC/CAA clinical experience, and a decision
on target variety (see Question 0 — it changes many answers below).

> **Ids and grid positions are not up for review.** Every id and cell in
> `es.json` must stay identical to `en.json` — that identity is what lets a
> bilingual child keep one motor pattern per word across languages, and
> `test/language_pack_test.dart` fails the build if it drifts. Only the `label`
> strings are in scope here.

---

## Question 0 — which Spanish? (answer this first)

The draft mixes varieties. Current labels include **`carro`** (core.car),
**`jalar`** (core.pull) and **`resbaladilla`** (play.slide) — Mexican/US-Latino
usage — while `ttsLocale` is **`es-ES`** (Peninsular Spanish), which would say
*coche*, *tirar* and *tobogán* and will read the current labels in a Castilian
accent with *seseo/ceceo* differences.

That is an inconsistency families will notice immediately. Pick one:

- **`es-US` / `es-MX` (recommended for the US pilot).** Largest US non-English
  AAC need (blueprint §6). Keep *carro*, *jalar*, *resbaladilla*; change
  `ttsLocale` to `es-US` or `es-MX`; re-check every label below for LatAm norms.
- **`es-ES`.** Keep the TTS locale; change *carro* → *coche*, *jalar* → *tirar*,
  *resbaladilla* → *tobogán*, *jugo* → *zumo*, *papá/mamá* stay.

Either way, blueprint §9.5 applies: **listen to the chosen OS voice reading
these words on a real device before sign-off.** Quality varies a lot by locale,
and a robotic voice gets blamed on the app.

---

## A. The items flagged in the brief

### A1. `core.dont` → **"no"** — must change

`core.dont` and `core.no` both have the label **"no"**. Two different buttons,
in two different grid positions, that speak the identical word and (per
`docs/SYMBOL_QA.md`) show an identical red X. The child gets no feedback that
they pressed different keys, and the caregiver cannot model the contrast.

English uses `don't` as a *negated auxiliary* — "I don't want", "don't go".
Spanish negates with a preverbal **no**, so there is no 1:1 auxiliary. Options:

| Option | Reads as | Notes |
|---|---|---|
| **"no quiero"** | "I don't want" | Too specific — locks the button to one verb |
| **"no" + distinct symbol** | same word, different picture | Fixes the symbol clash but not the audio clash |
| **"nada"** | "nothing" | Different meaning; not a substitute |
| **"ya no"** | "not any more" | Genuinely distinct and useful, but narrower than `don't` |

**Recommendation: "no quiero" is wrong, and so is leaving it.** The cleanest
answer is to accept that this English cell has no Spanish equivalent and give it
a *different high-frequency negator* — **"ya no"** (not any more) or **"nunca"**
(never) — so the position stays useful and speaks something distinct. The SLP
should decide; what is not acceptable is two buttons that say "no".

### A2. `core.make` → **"crear"** vs `core.do` → **"hacer"** — must change

**"crear"** is wrong. It means *to create* (artistic/abstract creation) and is
low-frequency in child language. Spanish uses **hacer** for both English *make*
and *do* — "hacer un dibujo" (make a drawing), "hacer la tarea" (do homework).

The draft assigned `hacer` to `core.do` and had to invent something for
`core.make`, producing a word a child will rarely need.

| Option | For `core.make` | Assessment |
|---|---|---|
| **"hacer" on both** | duplicate audio | Same defect as A1 — rejected |
| **"construir"** | to build | Concrete, child-friendly, high iconicity. **Recommended** if the pair must stay split |
| **"preparar"** | to prepare/make (food) | Good for snack/meal routines |
| Merge the cells | `make` → a different core verb | Cleanest linguistically: Spanish core lists do not need two cells here |

**Recommendation: `core.make` → "construir"** (or "preparar" if the pilot
families' routines are food-centred), keeping `core.do` → **"hacer"**. Flag to
the SLP that the *real* answer may be to re-purpose the `core.make` cell for a
verb that is genuinely core in Spanish, e.g. **"poner"** — but see B1, `poner`
is already used.

### A3. Possessive pronouns `core.his` → **"de él"**, `core.her` → **"de ella"**, `core.our` → **"de nosotros"**, `core.their` → **"de ellos"** — must change

These are **prepositional phrases, not possessives**, and they are the wrong
register for a core board. Spanish has true possessive determiners:

| id | Current | Recommended | Why |
|---|---|---|---|
| `core.his` | de él | **su** | The actual possessive determiner: *su libro* |
| `core.her` | de ella | **su** | Same form — see the collision note below |
| `core.our` | de nosotros | **nuestro** | *nuestra casa* |
| `core.their` | de ellos | **su** | Same form again |
| `core.my` | mi | **mi** | Correct already |
| `core.your` | tu | **tu** | Correct already |

**The collision:** Spanish `su` covers *his*, *her*, *their* **and** formal
*your*. Putting "su" on three separate cells recreates the A1 problem — three
buttons, one spoken word.

This is the single hardest decision in the pack and it is genuinely a clinical
one. Three defensible answers:

1. **Accept the collision.** Three cells say "su". Motor positions still differ,
   and the disambiguation comes from context, exactly as in adult Spanish. The
   symbol (per SYMBOL_QA P1) must then carry the whole distinction.
2. **Use the disambiguating long forms** — "su (de él)", "su (de ella)",
   "su (de ellos)" — natural Spanish for exactly this problem, but they speak a
   parenthetical aloud, which sounds odd in a sentence.
3. **Keep only one `su` cell** and re-purpose the other two positions. Cleanest
   speech, but breaks EN↔ES cell-for-cell parity of *meaning* (not of id — the
   ids and positions would still match; the labels would just be other words).

**Recommendation: option 1 for the pilot** (simplest, most natural speech),
with the SLP reviewing whether the symbol set makes the three distinguishable.

Also: `core.mine` → **"mío"** and `core.yours` → **"tuyo"** are correct, but note
they are gendered (*mío/mía*). Fine as citation forms.

### A4. Articles `core.a` → **"un"**, `core.the` → **"el"** — flag, do not change yet

Both are correct citation forms, but both are **gendered and number-marked**:
*un/una/unos/unas* and *el/la/los/las*. A single button will produce
"quiero un manzana" (should be *una*).

Options: leave as-is and accept agreement errors (normal in emerging AAC —
adults do not correct grammar, they model); or drop the articles from the
Spanish board entirely and re-purpose the cells (Spanish core-word lists often
rank articles lower than English ones do). **This is a clinical judgement call
and should be answered explicitly rather than inherited from the English pack.**

---

## B. Additional issues found in the same review

### B1. Duplicate labels — the same defect as A1, elsewhere in the pack

Every row below is two or more distinct buttons that speak the **identical
Spanish word**:

| Words | Shared label | Recommendation |
|---|---|---|
| `core.dont`, `core.no` | **no** | See A1 |
| `core.sorry`, `core.excuseme` | **perdón** | `excuse me` → **"con permiso"** (asking to pass) or **"disculpe"** |
| `core.loud`, `core.strong` | **fuerte** | `loud` → **"ruidoso"**; keep *fuerte* for `strong` |
| `core.gentle`, `core.soft` | **suave** | `gentle` → **"con cuidado"** or **"despacito"**; keep *suave* for `soft` |
| `core.playv`, `folder.play` | **jugar** | Acceptable (a verb and its folder), but consider folder → **"juegos"** |
| `core.tired`, `feel.tired` | **cansado** | Intentional — same word in two places |
| `core.sick`, `feel.sick` | **enfermo** | Intentional |
| `core.hungryd`, `food.hungry` | **hambriento** | Intentional, but see B2 — the word itself is wrong |

### B2. Word choices that are understood but not what a child would say

| id | English | Current | Recommended | Why |
|---|---|---|---|---|
| `core.hungryd` / `food.hungry` | hungry | hambriento | **"tengo hambre"** or **"hambre"** | *Hambriento* is literary/adjectival. Spanish expresses this with *tener*: children say *tengo hambre*. **High priority — a top-10 AAC word.** |
| `food.thirsty` | thirsty | sediento | **"tengo sed"** or **"sed"** | Same issue, same priority |
| `core.stop` | stop | alto | **"para"** or **"basta"** | *Alto* is a road sign (and in Spain means *tall*). *¡Para!* is what a child shouts |
| `core.scary` | scary | tenebroso | **"da miedo"** | *Tenebroso* is literary ("gloomy"). *Da miedo* is the everyday phrase |
| `core.funny` | funny | chistoso | **"gracioso"** | *Chistoso* is regional; *gracioso* is broader. Note `feel.silly` currently uses *gracioso* — resolve together |
| `feel.silly` | silly | gracioso | **"tonto"** or **"bobo"** | Frees *gracioso* for `funny` |
| `core.it` | it | eso | **"eso"** — flag | Spanish has no neuter subject pronoun; *eso* is a demonstrative. Probably correct but confirm the cell earns its place |
| `core.me` | me | mí | **"me"** or **"a mí"** | Stressed *mí* only appears after a preposition. Unstressed clitic is *me* |
| `core.get` | get | tomar | **"conseguir"** or **"agarrar"** | *Tomar* overlaps heavily with *drink* in LatAm |
| `core.take` | take | llevar | **"llevar"** — flag | *Llevar* = take *away*; *tomar/agarrar* = take *hold of*. Confirm which sense the cell means, and align with the pictogram |
| `core.only` | only | solamente | **"solo"** | *Solo* is far more frequent; also fixes the clash where `core.just` already uses *solo* |
| `core.just` | just | solo | see above | Resolve `just`/`only` as a pair |
| `core.some` | some | algo | **"algunos"** or **"un poco"** | *Algo* means *something*, not *some* — **this is a translation error** |
| `core.about` | about | acerca de | **"sobre"** | *Acerca de* is formal register |
| `core.bedroom` | bedroom | cuarto | **"habitación"** or keep *cuarto* | Regional; ties to Question 0 |
| `core.tv` (`play.tv`) | tv | tele | **"tele"** — fine | Colloquial and correct |
| `core.turn` | turn | girar | **"dar vuelta"** / **"voltear"** | *Girar* is technical; also check against `my turn`/`your turn` which use *turno* |
| `core.welcome` | welcome | bienvenido | fine, but gendered | *bienvenida* for a girl. Same class of issue as A4 |

### B3. Gender agreement — a pack-wide decision, not a per-word fix

Many adjectives ship in the masculine citation form: *bueno, malo, pequeño,
cansado, enfermo, hambriento, asustado, enojado, aburrido, orgulloso, bonito,
mojado, seco, limpio, sucio, nuevo, viejo, favorito, lastimado, tranquilo*.

For a girl using the board, every one of these speaks the wrong gender. This is
the most pervasive issue in the pack — it affects ~25 words — and it cannot be
fixed word-by-word. Options for the SLP and the engineering team:

1. **Leave masculine citation forms.** Standard practice in several shipping
   Spanish AAC packs; families adapt. Zero engineering cost.
2. **Ship `label` variants per gender** in the pack schema
   (`"label": {"m": "cansado", "f": "cansada"}`) and pick by profile. Real
   engineering work, but it is the kind of depth blueprint §6 says we compete on
   ("every language is a first-class language, not a translation layer").
3. **Use invariant phrasings** where they exist (*con cuidado* rather than
   *cuidadoso*). Only partially possible.

**Recommendation: decide before the Spanish pilot, not after.** Option 2 is the
differentiator but should be scheduled deliberately; option 1 is an acceptable
MVP answer *if it is a decision rather than an oversight*.

### B4. Symbol/translation mismatches (read with `docs/SYMBOL_QA.md`)

Three words where the Spanish label and the bundled pictogram mean different
things — fixing the label alone is not enough:

| id | ES label means | Pictogram shows | Resolve by |
|---|---|---|---|
| `core.on` | *encendido* = powered on | A block resting **on** a line (spatial) | Pick the sense; if spatial, → **"encima"** / **"en"** |
| `core.off` | *apagado* = powered off | A jar lifted **off** another (spatial) | If spatial, → **"quitar"** / **"fuera de"** |
| `core.light` | *ligero* = not heavy | A glowing **lightbulb** | See SYMBOL_QA P0 — the English pack has the same conflict |
| `core.hard` | *difícil* = difficult | A finger tapping a **rock** (rigid) | Same — decide the sense in English first |

These four must be decided in **English first**, then translated. Otherwise the
Spanish reviewer is being asked to translate an ambiguity.

---

## Summary for the reviewer

| Priority | Items |
|---|---|
| **Blocking** | Question 0 (variety/TTS mismatch); A1 `dont`; A2 `make`; A3 possessives; B2 *hambriento*/*sediento*/*algo* |
| **High** | B1 remaining duplicate labels; B3 gender decision; B4 (needs an English decision first) |
| **Medium** | A4 articles; the rest of B2 |

**Nothing in `es.json` has been edited.** When the answers come back, change
`label` strings only — never an `id`, `row` or `col`. `flutter test` enforces it.
