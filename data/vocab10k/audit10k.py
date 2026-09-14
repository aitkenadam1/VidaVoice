"""Vocab10k draft audit: duplicates, baseline collisions, suffix flags, ID simulation."""
import glob, importlib.util, json, re, unicodedata, collections, sys

def norm(s):
    s = unicodedata.normalize("NFKC", s).strip().lower()
    s = re.sub(r"\s+", " ", s)
    return s

def slug(s):
    s = norm(s)
    s = re.sub(r"['’`]", "", s)
    s = re.sub(r"[^a-z0-9 ]", " ", s)
    s = re.sub(r"\s+", "_", s).strip("_")
    return s or "x"

chunks = {}
allrecs = []  # (en, es, fr, emoji, level, chunkfile)
for f in sorted(glob.glob("chunk*.py")):
    spec = importlib.util.spec_from_file_location(f[:-3], f)
    m = importlib.util.module_from_spec(spec); spec.loader.exec_module(m)
    chunks[f] = m
    for w in m.WORDS:
        allrecs.append((*w, f))

print(f"RAW_TOTAL={len(allrecs)}")

# 1. tuple validity
bad = [r for r in allrecs if len(r) != 6 or not all(isinstance(x, str) for x in r[:4]) or not isinstance(r[4], int) or not r[0].strip() or not r[1].strip() or not r[2].strip() or r[4] not in (1,2,3)]
print(f"BAD_TUPLES={len(bad)}")
for r in bad[:10]: print("  BAD:", r)

# 2. exact normalized English dupes across all chunks
by_en = collections.defaultdict(list)
for r in allrecs: by_en[norm(r[0])].append(r)
dupes = {k: v for k, v in by_en.items() if len(v) > 1}
print(f"EXACT_DUP_EN_LABELS={len(dupes)} covering {sum(len(v) for v in dupes.values())} records")
top = sorted(dupes.items(), key=lambda kv: -len(kv[1]))[:25]
for k, v in top:
    print(f"  {k!r} x{len(v)}: {[(x[5], x[0]) for x in v]}")

# 3. baseline collisions
base = json.load(open("../baseline_ids.json")) if False else None
import os
bl = None
for p in ["../../baseline_labels.json", "../baseline_labels.json", "baseline_labels.json"]:
    if os.path.exists(p): bl = json.load(open(p)); break
print("BASELINE_FILE:", "found" if bl else "NOT FOUND")

# 4. artificial disambiguation suffixes
suf_pat = re.compile(r"\b(action|person|feeling|health|travel|room|path|store|music|science|art|time|game|color|shape|money|tech|job|sport|food|animal|clothes|body|vehicle|home|town|nature|question|description|safety|everyday|phrase)\s*$", re.I)
suffixed = [r for r in allrecs if suf_pat.search(r[0])]
print(f"ARTIFICIAL_SUFFIX={len(suffixed)}")
from collections import Counter
print(Counter(suf_pat.search(r[0]).group(1).lower() for r in suffixed).most_common(15))

# 5. ID simulation per folder prefix
idmap = collections.defaultdict(list)
for r in allrecs:
    en, es, fr, emoji, lvl, f = r
    prefix = chunks[f].ID_PREFIX
    idmap[f"{prefix}.{slug(en)}"].append((f, en))
idcoll = {k: v for k, v in idmap.items() if len(v) > 1}
print(f"SIMULATED_ID_COLLISIONS={len(idcoll)}")
for k, v in list(idcoll.items())[:15]: print(f"  {k}: {v}")

# 6. level distribution
print("LEVELS:", Counter(r[4] for r in allrecs))
# 7. per-folder raw
fc = Counter(r[5] for r in allrecs)
print("FOLDERS:", len(fc))
# 8. es/fr exact dupes (same label reused for different en)
by_es = collections.defaultdict(set); by_fr = collections.defaultdict(set)
for r in allrecs:
    by_es[norm(r[1])].add(norm(r[0])); by_fr[norm(r[2])].add(norm(r[0]))
es_amb = {k: v for k, v in by_es.items() if len(v) > 1}
fr_amb = {k: v for k, v in by_fr.items() if len(v) > 1}
print(f"ES_AMBIGUOUS={len(es_amb)} FR_AMBIGUOUS={len(fr_amb)}")
for k, v in list(es_amb.items())[:10]: print("  ES", k, "->", sorted(v))
for k, v in list(fr_amb.items())[:10]: print("  FR", k, "->", sorted(v))

# 9. unique validated estimate
uniq_en = len(by_en)
print(f"UNIQUE_EN_LABELS={uniq_en}  (raw {len(allrecs)} -> unique {uniq_en})")
