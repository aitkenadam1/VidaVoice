"""Curate vocab10k drafts into canonical unique concepts.
Rules:
- One canonical record per normalized English spoken label (same spoken word = same concept).
- Artificial trailing category suffixes are stripped; if the bare label already exists, the suffixed record is rejected as a duplicate.
- Baseline (402 ids) wins: any draft colliding with a baseline normalized label or id is rejected.
- Canonical pick: no-suffix original > lower level > earlier chunk.
- Outputs: curated.json, rejected.json, CURATION_REPORT.md
"""
import glob, importlib.util, json, re, unicodedata, collections

def norm(s):
    s = unicodedata.normalize("NFKC", s).strip().lower()
    s = re.sub(r"['’`]", "", s)  # valentine's == valentines (spoken concepts)
    return re.sub(r"\s+", " ", s)

def slug(s):
    s = norm(s)
    s = re.sub(r"['’`]", "", s)
    s = re.sub(r"[^a-z0-9 ]", " ", s)
    return re.sub(r"\s+", "_", s).strip("_") or "x"

CATS = ["action","person","feeling","health","travel","room","path","store","music","science",
        "art","time","game","color","shape","money","tech","job","sport","food","animal",
        "clothes","body","vehicle","home","town","nature","question","description","safety",
        "everyday","phrase","drink","fruit","vegetable","snack","dessert"]
SUF = re.compile(r"\s+(?:" + "|".join(CATS) + r")$", re.I)

# Manual translation / label fixes for clear errors spotted in audit
FIX = {
    # (chunkfile, en) -> (en, es, fr)
    ("chunk34_art_music.py", "smile"): ("smile", "sonrisa", "sourire"),
    ("chunk19_feelings.py", "silly"): ("silly", "tonto", "bête"),
    ("chunk20_actions_a.py", "skip"): ("skip", "saltar", "sauter"),
    ("chunk20_actions_b.py", "snitch"): ("snitch", "delatar", "dénoncer"),
    ("chunk36_time.py", "presidents day"): ("presidents day", "día de los presidentes", "jour des Présidents"),
}

# Folder placement overrides: (normalized en) -> winning folder id.
# Same spoken word = one concept; place it where a user would look first.
FOLDER_OVERRIDE = {
    "watch": "folder.actions",        # verb (mirar) beats wristwatch noun
    "smile": "folder.feelings",       # expression of feeling
    "cool": "folder.descriptions",
    "rough": "folder.descriptions",
    "weak": "folder.descriptions",
    "strong": "folder.descriptions",
    "bright": "folder.descriptions",
    "camouflage": "folder.descriptions",
    "plaid": "folder.descriptions",
    "bald": "folder.descriptions",
    "tan": "folder.descriptions",
    "iron": "folder.actions",         # verb (planchar) beats element
    "sneeze": "folder.health",
    "cough": "folder.health",
    "date": "folder.time",            # calendar date beats fruit/romantic date
    "pilot": "folder.jobs",
    "astronaut": "folder.jobs",
    "dentist": "folder.jobs",
    "pediatrician": "folder.jobs",
    "mechanic": "folder.jobs",
    "flight attendant": "folder.jobs",
    "sailor": "folder.jobs",
    "bus driver": "folder.jobs",
    "taxi driver": "folder.jobs",
    "captain": "folder.jobs",
    "car seat": "folder.safety",
    "booster seat": "folder.safety",
    "timer": "folder.time",
    "calendar": "folder.time",
    "circus": "folder.town",
    "airport": "folder.town",
    "rocket": "folder.science",
    "satellite": "folder.science",
    "star": "folder.science",
    "diamond": "folder.science",
    "fossil": "folder.science",
    "rainbow": "folder.nature",
    "sand": "folder.nature",
    "coral": "folder.animals",
    "salmon": "folder.food",
    "peach": "folder.food",
    "lime": "folder.food",
    "dinosaur": "folder.animals",
    "fan": "folder.home",
    "carnival": "folder.town",
    "fair": "folder.town",
    "parade": "folder.town",
}

# ---- Review pass 2026-09-14: content filtering (B4) ----
# Normalized en labels to drop outright: garbled generator output, duplicate
# concepts of an existing bare label, child-inappropriate terms, and
# encyclopedic cultivar / taxonomic depth beyond the common species.
BLOCK_LABELS = {
    # garbled
    "gull dong", "gull terr",
    # duplicate of an existing bare label (spoken device would say these aloud)
    "telescope space", "gravity space", "sheep lamb", "pilot airline",
    "sphinx myth", "dwarf myth",
    # child-inappropriate bare label (slang); the bird is not core vocabulary
    "booby",
    # obscure breeds / wild species beyond common domestic breeds
    "cornish rex", "devon rex", "don sphynx", "belgian malinois", "caracal",
    # taxonomic residue
    "killifish", "striped killifish", "banded killifish", "bluefin killifish",
    "least killifish", "crappie", "white crappie", "black crappie",
    # citrus cultivar encyclopedia (keep kumquat, loquat)
    "limequat", "eustis limequat", "lakeland limequat", "tavares limequat",
    "orangequat", "mandarinquat", "sunquat", "thomasville citrangequat",
    "kumquat nagami", "kumquat meiwa",
    # whale-species depth (keep whale, blue/humpback/killer whale)
    "fin whale", "minke whale", "sperm whale", "right whale", "gray whale",
    "bowhead whale",
}

# Domestic breed-variety long tail: drop when level == 3 (advanced). Common
# breeds at L1/L2 (labrador, poodle, beagle, ...) stay.
BREED_RE = re.compile(
    r"retriever|shepherd|hound|terrier|bulldog|poodle|beagle|rottweiler|"
    r"doberman|husky|malamute|collie|mastiff|greyhound|whippet|saluki|"
    r"akita|shiba|corgi|dachshund|labrador|dalmatian|chihuahua|rex|"
    r"malinois|spaniel|setter|pointer|weimaraner|siamese|persian|maine|"
    r"bengal|sphynx|ragdoll|burmese|arabian|thoroughbred|clydesdale|"
    r"mustang|appaloosa", re.I)

# Label/translation repairs: (chunkfile, en) -> (en, es, fr).
# Applied before dedup; the repaired en label flows into the id slug.
RENAME = {
    ("chunk02_animals_b.py", "neigh horse"): (
        "neigh", "relincho", "hennissement"),
    ("chunk16_nature_b.py", "phoenix bird"): (
        "phoenix", "f\u00e9nix", "ph\u00e9nix"),
}

# ---- Review pass 2026-09-14: folder coherence (B5) ----
# id -> destination folder. Applied after dedup; id prefix is unchanged
# (same precedent as FOLDER_OVERRIDE).
MOVES = {
    # mythology / fantasy out of Nature -> Stories
    "nature.dragon": "folder.stories",
    "nature.unicorn": "folder.stories",
    "nature.witch": "folder.stories",
    "nature.sphinx": "folder.stories",
    "nature.jackalope": "folder.stories",
    "nature.sorcerer": "folder.stories",
    "nature.genie": "folder.stories",
    "nature.magic_wand": "folder.stories",
    "nature.leprechaun": "folder.stories",
    "nature.kraken": "folder.stories",
    "nature.bigfoot": "folder.stories",
    "nature.yeti": "folder.stories",
    "nature.phoenix": "folder.stories",
    "nature.griffin": "folder.stories",
    "nature.centaur": "folder.stories",
    "nature.minotaur": "folder.stories",
    "nature.medusa": "folder.stories",
    "nature.hydra": "folder.stories",
    "nature.cerberus": "folder.stories",
    "nature.pegasus": "folder.stories",
    "nature.chimera": "folder.stories",
    "nature.basilisk": "folder.stories",
    "nature.satyr": "folder.stories",
    "nature.nymph": "folder.stories",
    "nature.troll": "folder.stories",
    "nature.leprechaun_gold": "folder.stories",
    # life events out of Nature -> Celebrations
    "nature.wedding_day": "folder.celebrations",
    "nature.baby_shower": "folder.celebrations",
    "nature.bridal_shower": "folder.celebrations",
    "nature.bachelor_party": "folder.celebrations",
    "nature.retirement_party": "folder.celebrations",
    # named landmarks out of Nature -> Travel
    "nature.statue_of_liberty": "folder.travel",
    "nature.eiffel_tower": "folder.travel",
    "nature.pyramids": "folder.travel",
    "nature.colosseum": "folder.travel",
    "nature.sierra_nevada": "folder.travel",
    "nature.olympic_mountains": "folder.travel",
    "nature.olympic_park": "folder.travel",
}

# ---- Review pass 2026-09-14: level policy (B3) ----
# New words default to advanced (level 3); a beginning communicator's board
# must stay small. Baseline folders already carry level-1 words, so every
# new record placed in one goes to level 3. New folders keep a small seed
# of their most salient (first-in-chunk-order) level-1 words so G8
# (every folder has level-1 vocabulary) still holds; the rest go to 3.
# Deliberate promotion (SLP/parent) moves words down from there.
BASELINE_FOLDERS = {
    "folder.feelings", "folder.food", "folder.people",
    "folder.phrases", "folder.play", "folder.school",
}
L1_SEED_CAP = 12

# baseline
base_en = json.load(open("baseline_en.json"))
base_ids = set()
base_labels = set()
for r in base_en:
    base_ids.add(r["id"])
    if r["label"]: base_labels.add(norm(r["label"]))
# home items labels
d = json.load(open("../../assets/lang/en.json"))
for it in d.get("items", []):
    base_ids.add(it["id"])
    if it.get("label"): base_labels.add(norm(it["label"]))
print(f"baseline ids={len(base_ids)} labels={len(base_labels)}")

chunks = {}
recs = []
for f in sorted(glob.glob("chunk*.py")):
    spec = importlib.util.spec_from_file_location(f[:-3], f)
    m = importlib.util.module_from_spec(spec); spec.loader.exec_module(m)
    chunks[f] = m
    for w in m.WORDS:
        en, es, fr, emoji, lvl = w
        if (f, en) in FIX:
            en, es, fr = FIX[(f, en)]
        if (f, en) in RENAME:
            en, es, fr = RENAME[(f, en)]
        recs.append({"en": en, "es": es, "fr": fr, "emoji": emoji, "level": lvl,
                     "chunk": f, "folder": m.FOLDER_ID, "prefix": m.ID_PREFIX,
                     "had_suffix": bool(SUF.search(en))})

# review-pass filtering (B4): drop before dedup so blocked records can never
# shadow a legitimate concept; record them as rejected for the audit trail.
rejected = []
kept = []
for r in recs:
    nl = norm(r["en"])
    if nl in BLOCK_LABELS:
        rejected.append({"en": r["en"], "reason": "review-blocklist",
                         "chunk": r["chunk"]})
    elif r["level"] == 3 and BREED_RE.search(r["en"]):
        rejected.append({"en": r["en"], "reason": "review-breed-depth",
                         "chunk": r["chunk"]})
    else:
        kept.append(r)
recs = kept

# strip suffixes
for r in recs:
    if r["had_suffix"]:
        r["en"] = SUF.sub("", r["en"]).strip()

groups = collections.defaultdict(list)
for r in recs:
    groups[norm(r["en"])].append(r)

curated = []
for label, rs in groups.items():
    # canonical pick: no suffix first, then lower level, then earlier chunk,
    # then folder override preference
    def pick_key(r):
        over = 0 if FOLDER_OVERRIDE.get(label) == r["folder"] else 1
        return (over, r["had_suffix"], r["level"], r["chunk"])
    rs_sorted = sorted(rs, key=pick_key)
    win = rs_sorted[0]
    losers = rs_sorted[1:]
    cid = f"{win['prefix']}.{slug(win['en'])}"
    # baseline collision?
    if label in base_labels or cid in base_ids:
        rejected.append({"en": win["en"], "reason": "baseline-collision", "id": cid,
                         "chunk": win["chunk"], "also_rejected_dupes": len(losers)})
        for l in losers:
            rejected.append({"en": l["en"], "reason": "duplicate-of-rejected-baseline-collision",
                             "chunk": l["chunk"]})
        continue
    curated.append({"id": cid, "en": win["en"], "es": win["es"], "fr": win["fr"],
                    "emoji": win["emoji"], "level": win["level"],
                    "folder": win["folder"], "chunk": win["chunk"]})
    for l in losers:
        reason = "artificial-suffix-dupe" if l["had_suffix"] else "cross-folder-duplicate"
        if l["chunk"] == win["chunk"]:
            reason = "intra-chunk-duplicate"
        rejected.append({"en": l["en"], "reason": reason, "kept_in": win["folder"],
                         "chunk": l["chunk"]})

# ---- review pass (B5): folder coherence moves ----
moved = 0
for c in curated:
    if c["id"] in MOVES:
        c["folder"] = MOVES[c["id"]]
        moved += 1
print(f"MOVED={moved}")
missing_moves = set(MOVES) - {c["id"] for c in curated}
if missing_moves:
    raise SystemExit(f"MOVES ids not found in curated: {sorted(missing_moves)}")

# ---- review pass (B3): level policy ----
# curated order == chunk WORDS order (salience proxy): the first L1_SEED_CAP
# level-1 records per new folder stay; everything else new at level 1 -> 3.
l1_seen = collections.Counter()
restamped = 0
for c in curated:
    if c["level"] != 1:
        continue
    if c["folder"] in BASELINE_FOLDERS:
        c["level"] = 3
        restamped += 1
    elif l1_seen[c["folder"]] >= L1_SEED_CAP:
        c["level"] = 3
        restamped += 1
    else:
        l1_seen[c["folder"]] += 1
print(f"RESTAMPED_L1_TO_L3={restamped}")
print("L1_SEEDS:", dict(l1_seen))

# id uniqueness within curated (slug collisions across prefixes shouldn't happen, verify)
idc = collections.Counter(c["id"] for c in curated)
coll = [k for k, v in idc.items() if v > 1]
print(f"RAW={len(recs)} CURATED={len(curated)} REJECTED={len(rejected)} ID_COLLISIONS={len(coll)}")
for k in coll[:10]: print("  COLL", k)

json.dump(curated, open("curated.json", "w"), ensure_ascii=False, indent=1)
json.dump(rejected, open("rejected.json", "w"), ensure_ascii=False, indent=1)

rc = collections.Counter(r["reason"] for r in rejected)
print("REJECT REASONS:", dict(rc))
fc = collections.Counter(c["folder"] for c in curated)
print("FOLDERS:", len(fc))
for k, v in fc.most_common(): print(f"  {k}: {v}")
lc = collections.Counter(c["level"] for c in curated)
print("LEVELS:", dict(lc))
print("NEED_MORE:", 10000 - len(curated))
