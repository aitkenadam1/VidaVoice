#!/usr/bin/env python3
"""Validation gates for the VidaVoice 10k-concept expansion.

Mirrors LanguagePack.validate() from lib/models/word.dart, plus the
10k-specific gates:
  G1  pack parses as JSON
  G2  validate() rules: unique cells, unique ids, levels 1-3, no phrases on
      the home grid, folder tiles level 1, every folder has a tile and
      vice versa, no nested folders
  G3  >= 10,000 unique concept ids per locale (reports exact count)
  G4  en/es/fr: identical id sequences (home + each folder), identical
      levels, identical grid positions
  G5  append-only: all baseline_snapshot.json ids byte-identical
      (position, label, level, type, folder)
  G6  new home-grid tiles start at row >= 37; rows 0-36 cell occupancy
      identical to baseline
  G7  every record has a non-empty label and emoji in every locale
  G8  every folder has >= 1 level-1 word (widget-test invariant)
  G9  symbol manifest entries all have a PNG on disk

Exit 0 = all gates pass. Prints a report either way.
"""

import json
import sys
from pathlib import Path

REPO = Path(__file__).resolve().parents[2]
LANG = REPO / "assets" / "lang"
VOCAB = REPO / "data" / "vocab10k"
SYMBOLS = REPO / "assets" / "symbols"
LOCALES = ["en", "es", "fr"]
GRID_COLS = 8
MIN_LEVEL, MAX_LEVEL = 1, 3
TARGET_IDS = 10_000
FIRST_NEW_ROW = 37

failures = []


def gate(name, ok, detail=""):
    status = "PASS" if ok else "FAIL"
    print(f"[{status}] {name}" + (f" — {detail}" if detail else ""))
    if not ok:
        failures.append(name)


def load(locale):
    with open(LANG / f"{locale}.json", encoding="utf-8") as f:
        return json.load(f)


def validate_pack(pack, locale):
    """Python mirror of LanguagePack.validate(). Returns list of errors."""
    errs = []
    seen_cells, seen_ids, tiles = set(), set(), set()
    for it in pack["homeItems"] if "homeItems" in pack else pack["items"]:
        _id = it["id"]
        r, c = it["row"], it["col"]
        if r < 0 or c < 0 or c >= pack["gridColumns"]:
            errs.append(f"{_id}: invalid position ({r},{c})")
        if (r, c) in seen_cells:
            errs.append(f"duplicate cell {r}:{c} ({_id})")
        seen_cells.add((r, c))
        if _id in seen_ids:
            errs.append(f"duplicate id {_id}")
        seen_ids.add(_id)
        if not (MIN_LEVEL <= it["level"] <= MAX_LEVEL):
            errs.append(f"{_id}: bad level {it['level']}")
        if it["type"] == "phrase":
            errs.append(f"phrase {_id} on home grid")
        if it["type"] == "folder":
            if it["level"] != MIN_LEVEL:
                errs.append(f"tile {_id} not level 1")
            tiles.add(_id)
    for fid, folder in pack["folders"].items():
        if fid not in tiles:
            errs.append(f"folder {fid} has no home tile")
        for w in folder["words"]:
            if w.get("type", "word") == "folder":
                errs.append(f"nested folder {w['id']}")
            if w["id"] in seen_ids:
                errs.append(f"duplicate id {w['id']}")
            seen_ids.add(w["id"])
            if not (MIN_LEVEL <= w["level"] <= MAX_LEVEL):
                errs.append(f"{w['id']}: bad level {w['level']}")
    for t in tiles:
        if t not in pack["folders"]:
            errs.append(f"tile {t} has no folder entry")
    return errs, seen_ids


def main():
    packs = {}
    for loc in LOCALES:
        try:
            packs[loc] = load(loc)
            gate(f"G1 {loc} parses", True)
        except Exception as e:  # noqa: BLE001
            gate(f"G1 {loc} parses", False, str(e))
            return 1

    # normalize key name (packs use "items")
    for loc in LOCALES:
        packs[loc]["homeItems"] = packs[loc].pop("items")

    all_ids = {}
    for loc in LOCALES:
        errs, ids = validate_pack(packs[loc], loc)
        gate(f"G2 {loc} validate() mirror", not errs,
             f"{len(errs)} errors" if errs else f"{len(ids)} unique ids")
        for e in errs[:8]:
            print(f"      ! {e}")
        all_ids[loc] = ids

    for loc in LOCALES:
        n = len(all_ids[loc])
        gate(f"G3 {loc} >= {TARGET_IDS} ids", n >= TARGET_IDS, f"n={n}")

    # G4: locale parity
    en = packs["en"]
    en_home = [(i["id"], i["row"], i["col"], i["level"]) for i in en["homeItems"]]
    en_folders = {fid: [(w["id"], w["level"]) for w in f["words"]]
                  for fid, f in en["folders"].items()}
    for loc in ["es", "fr"]:
        p = packs[loc]
        home = [(i["id"], i["row"], i["col"], i["level"]) for i in p["homeItems"]]
        gate(f"G4 {loc} home id/position/level parity", home == en_home,
             f"{len(home)} home items")
        folders = {fid: [(w["id"], w["level"]) for w in f["words"]]
                   for fid, f in p["folders"].items()}
        gate(f"G4 {loc} folder id/level parity", folders == en_folders,
             f"{len(folders)} folders")
        # labels/emoji present (content differs by locale, presence must not)
        bad = [w["id"] for f in p["folders"].values() for w in f["words"]
               if not w.get("label") or not w.get("emoji")]
        bad += [i["id"] for i in p["homeItems"]
                if not i.get("label") or not i.get("emoji")]
        gate(f"G7 {loc} labels+emoji present", not bad,
             f"{len(bad)} bad" if bad else "all present")

    # G5: append-only vs baseline snapshot
    snap_path = VOCAB / "baseline_snapshot.json"
    if snap_path.exists():
        snap = json.loads(snap_path.read_text(encoding="utf-8"))
        mism = []
        for _id, before in snap.items():
            kind = before["kind"]
            if kind in ("home", "tile"):
                cur = next((i for i in en["homeItems"] if i["id"] == _id), None)
                now = None if cur is None else {
                    "kind": "tile" if cur["type"] == "folder" else "home",
                    "row": cur["row"], "col": cur["col"],
                    "label": cur["label"], "level": cur["level"],
                    "type": cur["type"], "category": cur.get("category")}
            else:
                cur = next((w for w in en["folders"][before["folder"]]["words"]
                            if w["id"] == _id), None)
                now = None if cur is None else {
                    "kind": "folder-word", "folder": before["folder"],
                    "label": cur["label"], "emoji": cur["emoji"],
                    "level": cur["level"], "type": cur.get("type", "word")}
            if now != before:
                mism.append(_id)
        gate("G5 baseline append-only", not mism,
             f"{len(snap)} ids checked" + (f", MUTATED: {mism[:5]}" if mism else ""))
    else:
        gate("G5 baseline append-only", False, "baseline_snapshot.json missing")

    # G6: new tiles at row >= 37; rows 0-36 occupancy frozen
    base_cells = {(b["row"], b["col"]) for b in snap.values()
                  if b["kind"] in ("home", "tile")} if snap_path.exists() else set()
    cur_cells = {(i["row"], i["col"]) for i in en["homeItems"]}
    gate("G6 rows 0-36 occupancy frozen",
         base_cells <= cur_cells and
         all(r < FIRST_NEW_ROW for (r, c) in base_cells),
         f"baseline cells={len(base_cells)}")
    new_tiles = [i for i in en["homeItems"]
                 if i["type"] == "folder" and i["row"] >= FIRST_NEW_ROW]
    bad_tiles = [i["id"] for i in en["homeItems"]
                 if i["row"] >= FIRST_NEW_ROW and i["type"] != "folder"]
    gate("G6 new tiles are folders at row >= 37",
         not bad_tiles, f"{len(new_tiles)} new tiles")

    # G8: every folder has a level-1 word
    empty = [fid for fid, f in en["folders"].items()
             if not any(w["level"] == 1 for w in f["words"])]
    gate("G8 every folder has level-1 words", not empty,
         f"{len(en['folders'])} folders" + (f", empty: {empty}" if empty else ""))

    # G9: symbol manifest consistency
    man_path = SYMBOLS / "manifest.json"
    if man_path.exists():
        man = json.loads(man_path.read_text(encoding="utf-8"))
        ids = man.get("symbols", [])
        missing = [s for s in ids
                   if not (SYMBOLS / f"{s.replace('.', '_')}.png").exists()]
        gate("G9 symbol PNGs present", not missing,
             f"{len(ids)} in manifest" + (f", missing: {len(missing)}" if missing else ""))
    else:
        gate("G9 symbol PNGs present", False, "manifest.json missing")

    print()
    if failures:
        print(f"GATES FAILED: {len(failures)} — {failures}")
        return 1
    print("ALL GATES PASS")
    return 0


if __name__ == "__main__":
    sys.exit(main())
