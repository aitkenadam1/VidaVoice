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
        recs.append({"en": en, "es": es, "fr": fr, "emoji": emoji, "level": lvl,
                     "chunk": f, "folder": m.FOLDER_ID, "prefix": m.ID_PREFIX,
                     "had_suffix": bool(SUF.search(en))})

# strip suffixes
for r in recs:
    if r["had_suffix"]:
        r["en"] = SUF.sub("", r["en"]).strip()

groups = collections.defaultdict(list)
for r in recs:
    groups[norm(r["en"])].append(r)

curated, rejected = [], []
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
