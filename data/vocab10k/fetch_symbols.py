#!/usr/bin/env python3
"""Fetch ARASAAC pictograms for the 10k-expansion vocabulary.

For every curated word id not already in assets/symbols/manifest.json:
  1. Search https://api.arasaac.org/api/pictograms/en/search/<english label>
  2. Take the first hit's pictogram id
  3. Download https://static.arasaac.org/pictograms/<id>/<id>_500.png
     to assets/symbols/<word_id with _ for .>.png

Idempotent: skips words whose PNG already exists. Words with no ARASAAC
hit keep the emoji fallback (no manifest entry).

First search hit is used, consistent with the existing MAPPING.md
convention — every batch-10k entry is flagged [10k-batch unreviewed] and
needs SLP review before release.

Run in background: python3 data/vocab10k/fetch_symbols.py
Logs: data/vocab10k/symbol_fetch.log
"""

import json
import time
import urllib.parse
import urllib.request
from concurrent.futures import ThreadPoolExecutor
from pathlib import Path
from threading import Lock

REPO = Path(__file__).resolve().parents[2]
VOCAB = REPO / "data" / "vocab10k"
SYMBOLS = REPO / "assets" / "symbols"
WORKERS = 8
TIMEOUT = 30

API = "https://api.arasaac.org/api/pictograms/en/search/{}"
PNG = "https://static.arasaac.org/pictograms/{0}/{0}_500.png"

log_lock = Lock()
stats = {"ok": 0, "nohit": 0, "dled": 0, "dled_fail": 0, "skip": 0}
failures = []
mapping_lines = []


def log(msg):
    with log_lock:
        ts = time.strftime("%H:%M:%S")
        line = f"[{ts}] {msg}"
        print(line, flush=True)
        with open(VOCAB / "symbol_fetch.log", "a", encoding="utf-8") as f:
            f.write(line + "\n")


def http_get_json(url):
    req = urllib.request.Request(url, headers={"User-Agent": "VidaVoice/0.02"})
    with urllib.request.urlopen(req, timeout=TIMEOUT) as r:
        return json.loads(r.read().decode("utf-8"))


def http_get_bytes(url):
    req = urllib.request.Request(url, headers={"User-Agent": "VidaVoice/0.02"})
    with urllib.request.urlopen(req, timeout=TIMEOUT) as r:
        return r.read()


def process(rec):
    wid = rec["id"]
    fname = SYMBOLS / f"{wid.replace('.', '_')}.png"
    if fname.exists():
        with log_lock:
            stats["skip"] += 1
        return ("skip", wid)

    label = rec["en"]
    for attempt in range(3):
        try:
            hits = http_get_json(API.format(urllib.parse.quote(label)))
            break
        except Exception as e:  # noqa: BLE001
            if attempt == 2:
                with log_lock:
                    failures.append({"id": wid, "label": label,
                                     "stage": "search", "error": str(e)})
                    stats["nohit"] += 1
                return ("fail", wid)
            time.sleep(2 * (attempt + 1))

    if not hits:
        with log_lock:
            failures.append({"id": wid, "label": label,
                             "stage": "search", "error": "no hits"})
            stats["nohit"] += 1
        return ("nohit", wid)

    pid = hits[0]["_id"]
    kw = ""
    for k in hits[0].get("keywords", []):
        if isinstance(k, dict) and k.get("keyword"):
            kw = k["keyword"]
            break
    for attempt in range(3):
        try:
            data = http_get_bytes(PNG.format(pid))
            if not data.startswith(b"\x89PNG"):
                raise ValueError("not a PNG")
            fname.write_bytes(data)
            break
        except Exception as e:  # noqa: BLE001
            if attempt == 2:
                with log_lock:
                    failures.append({"id": wid, "label": label,
                                     "stage": "download",
                                     "error": f"pictogram {pid}: {e}"})
                    stats["dled_fail"] += 1
                return ("fail", wid)
            time.sleep(2 * (attempt + 1))

    with log_lock:
        stats["ok"] += 1
        stats["dled"] += 1
        mapping_lines.append(
            f'- {wid} ("{label}" via "{kw}"): arasaac_id={pid} '
            f'keyword="{kw}" [10k-batch unreviewed]')
    return ("ok", wid)


def main():
    (VOCAB / "symbol_fetch.log").write_text("", encoding="utf-8")
    curated = json.loads((VOCAB / "curated.json").read_text(encoding="utf-8"))
    manifest = json.loads((SYMBOLS / "manifest.json").read_text(encoding="utf-8"))
    have = set(manifest["symbols"])
    todo = [r for r in curated
            if r["id"].replace(".", "_") not in have]
    log(f"curated={len(curated)} already_have={len(have)} to_fetch={len(todo)}")
    t0 = time.time()
    done = 0
    with ThreadPoolExecutor(max_workers=WORKERS) as ex:
        for _status, _wid in ex.map(process, todo):
            done += 1
            if done % 200 == 0:
                el = time.time() - t0
                log(f"progress {done}/{len(todo)} "
                    f"ok={stats['ok']} nohit={stats['nohit']} "
                    f"dlfail={stats['dled_fail']} skip={stats['skip']} "
                    f"elapsed={el:.0f}s")

    # manifest: keep existing order, append new ids sorted
    new_ids = sorted(s for s in
                     (r["id"].replace(".", "_") for r in todo
                      if (SYMBOLS / f"{r['id'].replace('.', '_')}.png").exists())
                     if s not in have)
    manifest["symbols"] = list(manifest["symbols"]) + new_ids
    (SYMBOLS / "manifest.json").write_text(
        json.dumps(manifest, ensure_ascii=True, indent=2) + "\n",
        encoding="utf-8")

    with open(SYMBOLS / "MAPPING.md", "a", encoding="utf-8") as f:
        f.write("\n## 10k-expansion batch (auto-generated — NEEDS SLP REVIEW)\n\n")
        f.write("First ARASAAC search hit used; matches not clinically reviewed. "
                "Words with no usable pictogram fall back to emoji.\n\n")
        for line in sorted(mapping_lines):
            f.write(line + "\n")

    with open(VOCAB / "symbol_fetch_failures.json", "w", encoding="utf-8") as f:
        json.dump(failures, f, ensure_ascii=True, indent=2)
        f.write("\n")

    el = time.time() - t0
    log(f"DONE ok={stats['ok']} nohit={stats['nohit']} "
        f"dlfail={stats['dled_fail']} skip={stats['skip']} "
        f"manifest_new={len(new_ids)} elapsed={el:.0f}s")
    # report total size
    total = sum(p.stat().st_size for p in SYMBOLS.glob("*.png"))
    log(f"assets/symbols total: {total / 1e6:.1f} MB")


if __name__ == "__main__":
    main()
