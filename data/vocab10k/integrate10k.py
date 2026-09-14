#!/usr/bin/env python3
"""Integrate the curated 10k vocabulary into assets/lang/{en,es,fr}.json.

Append-only contract (motor planning is sacred):
- Every existing id keeps its exact position, label, level, and folder.
- New words go ONLY into folders (2-tap budget); nothing new on the home
  grid except folder tiles.
- New folder tiles start at row 37 (rows 0-36 are the frozen baseline grid).
- en/es/fr keep identical id order, positions, and levels.
- Phrase records (id starts with "phrase.") get "type": "phrase" inside
  folder.phrases; phrases never touch the home grid.

Reads: data/vocab10k/curated.json
Writes: assets/lang/en.json, es.json, fr.json (version 3 -> 4)
Also writes: data/vocab10k/baseline_snapshot.json (pre-integration baseline,
used by validate10k.py to prove append-only).
"""

import ast
import json
import re
from collections import defaultdict
from pathlib import Path

REPO = Path(__file__).resolve().parents[2]
VOCAB = REPO / "data" / "vocab10k"
LANG = REPO / "assets" / "lang"
LOCALES = ["en", "es", "fr"]

FIRST_FOLDER_ROW = 37
GRID_COLS = 8


def load_pack(locale):
    with open(LANG / f"{locale}.json", encoding="utf-8") as f:
        return json.load(f)


def folder_registry():
    """First-seen FOLDER_ID -> (emoji, en, es, fr) across all chunk files."""
    reg = {}
    for path in sorted(VOCAB.glob("chunk*.py")):
        src = path.read_text(encoding="utf-8")
        m_id = re.search(r'FOLDER_ID = "([^"]+)"', src)
        m_lab = re.search(r"FOLDER_LABEL = (\{[^\}]+\})", src)
        m_emo = re.search(r'FOLDER_EMOJI = "([^"]+)"', src)
        if not (m_id and m_lab and m_emo):
            raise SystemExit(f"Bad chunk header in {path.name}")
        fid = m_id.group(1)
        if fid not in reg:
            lab = ast.literal_eval(m_lab.group(1))
            reg[fid] = (m_emo.group(1), lab["en"], lab["es"], lab["fr"])
    return reg


def snapshot_baseline(packs):
    """id -> (kind, row, col, folder, label_en, level, type) for every
    pre-existing id. Saved to disk; gates compare post-integration packs
    against it."""
    snap = {}
    en = packs["en"]
    for it in en["items"]:
        snap[it["id"]] = {
            "kind": "tile" if it["type"] == "folder" else "home",
            "row": it["row"],
            "col": it["col"],
            "label": it["label"],
            "level": it["level"],
            "type": it["type"],
            "category": it.get("category"),
        }
    for fid, folder in en["folders"].items():
        for w in folder["words"]:
            snap[w["id"]] = {
                "kind": "folder-word",
                "folder": fid,
                "label": w["label"],
                "emoji": w["emoji"],
                "level": w["level"],
                "type": w.get("type", "word"),
            }
    return snap


def main():
    with open(VOCAB / "curated.json", encoding="utf-8") as f:
        curated = json.load(f)
    print(f"curated records: {len(curated)}")

    packs = {loc: load_pack(loc) for loc in LOCALES}
    reg = folder_registry()

    # --- baseline snapshot (proves append-only later) ---
    snap = snapshot_baseline(packs)
    with open(VOCAB / "baseline_snapshot.json", "w", encoding="utf-8") as f:
        json.dump(snap, f, ensure_ascii=True, indent=2, sort_keys=True)
        f.write("\n")
    print(f"baseline snapshot: {len(snap)} ids")

    curated_ids = {r["id"] for r in curated}
    overlap = curated_ids & set(snap)
    if overlap:
        raise SystemExit(f"ID COLLISION with baseline: {sorted(overlap)[:10]}")

    # group new words per folder, deterministic order
    by_folder = defaultdict(list)
    for r in sorted(curated, key=lambda r: (r["folder"], r["id"])):
        by_folder[r["folder"]].append(r)

    unknown_folders = set(by_folder) - set(reg)
    if unknown_folders:
        raise SystemExit(f"Folders with no registry entry: {unknown_folders}")

    for loc in LOCALES:
        pack = packs[loc]
        existing_folders = list(pack["folders"].keys())
        new_folders = sorted(set(by_folder) - set(existing_folders))
        print(f"[{loc}] existing folders: {len(existing_folders)}, "
              f"new folders: {len(new_folders)}")

        # 1) create new folder entries (appended after existing, sorted by id)
        for fid in new_folders:
            emoji, en_l, es_l, fr_l = reg[fid]
            label = {"en": en_l, "es": es_l, "fr": fr_l}[loc]
            pack["folders"][fid] = {
                "emoji": emoji,
                "label": label,
                "words": [],
            }

        # 2) append words to their folders (existing words untouched)
        added = 0
        for fid in sorted(by_folder):
            words = pack["folders"][fid]["words"]
            for r in by_folder[fid]:
                label = r[loc]
                if not label or not label.strip():
                    raise SystemExit(f"Empty {loc} label for {r['id']}")
                if r["id"].startswith("phrase."):
                    entry = {
                        "emoji": r["emoji"],
                        "id": r["id"],
                        "label": label,
                        "type": "phrase",
                        "level": r["level"],
                    }
                else:
                    entry = {
                        "emoji": r["emoji"],
                        "id": r["id"],
                        "label": label,
                        "level": r["level"],
                    }
                words.append(entry)
                added += 1
        print(f"[{loc}] words appended: {added}")

        # 3) new folder tiles on the home grid, starting at row 37
        for idx, fid in enumerate(new_folders):
            emoji, en_l, es_l, fr_l = reg[fid]
            label = {"en": en_l, "es": es_l, "fr": fr_l}[loc]
            row = FIRST_FOLDER_ROW + idx // GRID_COLS
            col = idx % GRID_COLS
            pack["items"].append({
                "category": "folder",
                "col": col,
                "emoji": emoji,
                "id": fid,
                "label": label,
                "row": row,
                "type": "folder",
                "level": 1,
            })
        print(f"[{loc}] new tiles: {len(new_folders)} "
              f"(rows {FIRST_FOLDER_ROW}.."
              f"{FIRST_FOLDER_ROW + (len(new_folders) - 1) // GRID_COLS})")

        # 4) version bump + comment
        pack["version"] = 4
        pack["comment"] = (
            "VidaVoice v0.02 English core pack + 10k-concept expansion "
            "(draft vocabulary, machine-translated es/fr pending professional "
            "review). Grid positions are FIXED (motor planning is sacred): "
            "never reorder, never compute at runtime. Word ids are "
            "language-independent so bilingual users keep motor positions "
            "across languages."
            if loc == "en" else pack["comment"]
        )

    for loc in LOCALES:
        out = LANG / f"{loc}.json"
        with open(out, "w", encoding="utf-8") as f:
            # ensure_ascii=False: repo convention is raw UTF-8 emoji in packs
            json.dump(packs[loc], f, ensure_ascii=False, indent=2)
            f.write("\n")
        print(f"wrote {out}")

    # --- post-write sanity: baseline ids untouched in en pack ---
    en = packs["en"]
    after = snapshot_baseline({"en": en})
    for _id, before in snap.items():
        if after.get(_id) != before:
            raise SystemExit(f"BASELINE MUTATED: {_id}\n  before={before}\n"
                             f"  after ={after.get(_id)}")
    print(f"baseline intact: {len(snap)} ids unchanged")


if __name__ == "__main__":
    main()
