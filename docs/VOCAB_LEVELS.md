# Vocabulary levels — assignment and review

Every word in every pack now carries a `level` (1–3), declared in
`assets/lang/*.json` next to `row` and `col`. Level is **data, never computed** —
the same rule that governs grid position.

## The invariant

Raising the unlocked level **only fills in empty cells.** A word visible at
level 1 is at the identical `(row, col)` at levels 2 and 3. Locked words are not
filtered out of the list — their cell is drawn empty, exactly like a position
that was never filled.

This is enforced, not just intended:

- `progressive reveal NEVER moves a visible word` — walks every level and
  asserts each visible word answers at its own `(row, col)`.
- `the set of visible words grows monotonically` — level *n+1* is a superset.
- `locked cells read as empty, and unlock without displacing`.
- `en and es share identical levels` — a bilingual child must not have the
  board change shape when they switch language.
- `folder tiles are never locked` (also enforced in `LanguagePack.validate()`) —
  locking navigation would strand the level-1 words behind a folder.
- `every folder still has level-1 words behind it` — no folder opens onto an
  empty grid.

Folder contents follow the same rule: a locked folder word keeps its slot rather
than letting the words after it slide up. Position inside a folder is a motor
pattern too.

## Current split (242-word pack)

| Level | Home grid | Folder words | Total |
|---|---|---|---|
| 1 — Starter | 46 | 20 | 66 (+4 folder tiles) |
| 2 — Growing | 116 | 22 | 138 |
| 3 — Full board | 80 | 8 | 88 |
| | **242** | **50** | **292** |

The level-1 core (46 home words + folder tiles) is unchanged from the original
192-word assignment: it is the set a first message is built from — `want`,
`need`, `like`, `don't`, `go`, `come`, `stop`, `help`, `more`, `again`,
`finished`, `yes`, `no`, the basic pronouns and prepositions, `what`/`where`/
`who`, `big`/`little`/`good`/`bad`, all four folders, and inside them the basic
wants, closest people, basic play, and the safety/regulation feelings.

### The 50 added words (rows 25–31)

Assigned by the same frequency reasoning; level 1 was deliberately untouched
so existing starter boards do not change shape:

- **Level 2 (29):** the four common animals (`dog`, `cat`, `bird`, `fish`),
  all 11 colors, all 10 numbers, `playground` and `pool` (play contexts), and
  the high-frequency treats `ice cream` and `cake`. These are describing and
  counting words a growing communicator reaches for early.
- **Level 3 (21):** the remaining 11 animals (`horse` through `snake`), the
  less-frequent places (`library`, `restaurant`, `farm`, `garden`, `museum`,
  `cinema`), and the less-frequent foods (`grapes`, `strawberry`, `carrot`,
  `sandwich`).

**Level 1** is the set a first message is built from: `want`, `need`, `like`,
`don't`, `go`, `come`, `stop`, `help`, `more`, `again`, `finished`, `yes`, `no`,
the basic pronouns and prepositions, `what`/`where`/`who`, `big`/`little`/
`good`/`bad`, all four folders, and inside them the basic wants (`water`,
`milk`, `juice`, `apple`, `cookie`, `hungry`, `thirsty`), the closest people
(`mom`, `dad`, `baby`), basic play (`ball`, `toy`, `book`, `outside`) and the
feelings that matter for safety and regulation (`scared`, `angry`, `tired`,
`sick`, `hurt`, `excited`).

**Level 2** adds the describing and asking vocabulary — `when`, `how`, `why`,
`now`, `today`, the opposites (`hot`/`cold`, `fast`/`slow`, `new`/`old`), most
remaining verbs, the social repair words (`sorry`, `excuse me`, `my turn`), and
the first connectors (`and`, `but`, `a`, `the`, `to`, `with`).

**Level 3** is everything else: time words (`tomorrow`, `yesterday`, `later`),
spatial and directional terms (`left`, `right`, `front`, `back`, `near`, `far`),
the abstract verbs (`remember`, `forget`, `dream`, `learn`), the remaining
places, and the low-frequency connectors (`because`, `or`, `just`, `only`,
`about`, `every`).

## ⚠️ This assignment needs SLP sign-off

The split above is a **defensible engineering proposal, not a clinical
decision.** It was built from general core-vocabulary frequency reasoning, not
from a validated instrument, and blueprint §9.1 is explicit that every
vocabulary decision needs SLP review.

Specific calls a reviewer should challenge:

1. **46 words is a large level 1.** Some starter boards use 12–20. If the pilot
   population is earlier-stage, a level 0 may be wanted — the schema supports it
   by raising `maxSupportedLevel` and re-stamping, with no code change to the
   reveal logic.
2. **`make` and `do` sit at level 2** despite being high-frequency core, because
   their pictograms are currently identical (`docs/SYMBOL_QA.md` P1). That is a
   symbol defect driving a vocabulary decision — it should be reversed once the
   symbols are fixed.
3. **Feelings are weighted into level 1** on the argument that a child needs to
   report pain and fear before they need to describe the weather. Worth an
   explicit yes/no.
4. **Connectors are split across levels 2 and 3** (`and`/`but` early, `because`/
   `or` late). The ordering is arguable.
5. **Levels are identical across English and Spanish.** Core-word frequency is
   *not* the same in the two languages (blueprint §6), so a Spanish-specific
   ordering may eventually be correct — but it would break the "same board in
   both languages" guarantee for bilingual users. That trade-off is a clinical
   call, and the test that currently forbids the drift is the place to record
   the decision.

## Changing the assignment

Edit `level` in `assets/lang/en.json`, `assets/lang/es.json` **and**
`assets/lang/fr.json` — they must match, and `flutter test` fails if they
drift. Never change `id`, `row` or `col` while doing it.
