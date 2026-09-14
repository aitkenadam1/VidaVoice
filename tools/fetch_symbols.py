#!/usr/bin/env python3
"""Fetch and audit ARASAAC pictograms for the VidaVoice vocabulary.

The v0.02 symbol set was built by taking the FIRST search hit for each English
label. docs/SYMBOL_QA.md shows where that went wrong (`try` returned a
courtroom, `just` returned the scales of justice, `pull` returned a toilet).
This script exists so the pass is reproducible and reviewable:

    python3 tools/fetch_symbols.py --review            # candidates for flagged words
    python3 tools/fetch_symbols.py --review --all      # candidates for every word
    python3 tools/fetch_symbols.py --apply             # download the pinned choices
    python3 tools/fetch_symbols.py --remap-only        # rebuild manifest + MAPPING.md

Word ids and grid positions live in assets/lang/*.json and are NEVER written
here — this script only ever touches assets/symbols/. A pictogram swap changes
what a button looks like, never where it is.

Requires network access to api.arasaac.org.

Pictograms (c) ARASAAC (Government of Aragon), author Sergio Palao, CC BY-NC-SA.
"""
from __future__ import annotations

import argparse
import json
import sys
import urllib.error
import urllib.parse
import urllib.request
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent
LANG = ROOT / "assets" / "lang" / "en.json"
SYMBOLS = ROOT / "assets" / "symbols"
CHOICES = ROOT / "tools" / "symbol_choices.json"

API = "https://api.arasaac.org/api/pictograms"
RESOLUTION = 500
TIMEOUT = 30

# Search terms to offer for each word flagged in docs/SYMBOL_QA.md.
# The first entry is the recommended starting point; --review shows candidates
# for all of them so a reviewer can compare. A word absent from this map is
# searched by its English label.
REVIEW_TERMS: dict[str, list[str]] = {
    # --- P0: the picture shows a different word -----------------------------
    "core.try": ["attempt", "effort", "try"],
    "core.just": ["only", "solely"],
    "core.about": ["about", "regarding", "concerning"],
    "core.pull": ["pull", "tug", "pull rope"],
    "core.right": ["turn right", "right direction"],
    "core.front": ["in front of", "ahead"],
    "core.back": ["behind", "at the back"],
    "core.out": ["out of", "outside box", "exit"],
    "core.down": ["down", "downwards", "go down"],
    "core.close": ["close door", "shut", "closed"],
    "play.park": ["playground", "park", "green space"],
    "core.for": ["for", "intended for"],
    "core.only": ["only", "solely", "just one"],
    "core.too": ["also", "as well", "too"],
    "core.light": ["light weight", "lightweight"],
    "core.hard": ["difficult", "hard task"],
    "core.scary": ["frightening", "scary"],
    "play.game": ["board game", "play game"],
    # --- P1: duplicates - the word that needs its own picture ---------------
    "core.do": ["do", "carry out", "activity"],
    "core.tell": ["tell", "inform", "tell someone"],
    "core.look": ["look at", "watch", "observe"],
    "core.myturn": ["my turn"],
    "core.yourturn": ["your turn"],
    "core.uhoh": ["oops", "mistake"],
    "core.excuseme": ["excuse me", "may I pass"],
    "core.oops": ["mistake", "error"],
    "core.dont": ["do not", "forbidden", "not allowed"],
    "core.mine": ["mine", "belongs to me"],
    "core.yours": ["yours", "belongs to you"],
    # --- P2: antonym pairs, refetch both from one series --------------------
    "core.big": ["big", "large"],
    "core.little": ["small", "little"],
    "core.hot": ["hot", "heat"],
    "core.cold": ["cold", "freezing"],
    "core.easy": ["easy", "simple"],
    "core.heavy": ["heavy", "heavy weight"],
    "core.good": ["good", "thumbs up"],
    "core.bad": ["bad", "thumbs down"],
    "core.okay": ["ok", "okay"],
    "core.hello": ["hello", "greet"],
    "core.goodbye": ["goodbye", "farewell"],
    "core.left": ["turn left", "left direction"],
    # --- P3: illegible at 38px, simpler art wanted --------------------------
    "core.tomorrow": ["tomorrow"],
    "core.yesterday": ["yesterday"],
    "core.now": ["now"],
    "core.later": ["later", "afterwards"],
    "people.cousin": ["cousin"],
    "people.aunt": ["aunt"],
    "people.sister": ["sister"],
    "people.brother": ["brother"],
    # --- P4: style, culture, iconicity --------------------------------------
    "core.walk": ["walk"],
    "core.goodnight": ["good night"],
    "core.home": ["home", "house"],
    "core.church": ["place of worship", "church"],
    "people.mom": ["mother"],
    "people.dad": ["father"],
    "core.loud": ["loud", "noisy"],
    "core.stand": ["stand up"],
    "core.wait": ["wait"],
    "core.old": ["old"],
    "core.start": ["start", "begin"],
    "core.new": ["new"],
    "core.which": ["which", "choose"],
    "core.cleanv": ["clean", "wipe"],
    "core.cleand": ["clean", "wipe"],
}


def die(msg: str) -> None:
    print(f"error: {msg}", file=sys.stderr)
    raise SystemExit(1)


def vocabulary() -> list[tuple[str, str]]:
    """Every (word_id, english_label) that needs a pictogram, folders included."""
    pack = json.loads(LANG.read_text(encoding="utf-8"))
    words: list[tuple[str, str]] = []
    for item in pack["items"]:
        words.append((item["id"], item["label"]))
    for folder in pack["folders"].values():
        for word in folder["words"]:
            words.append((word["id"], word["label"]))
    return words


def asset_for(word_id: str) -> Path:
    """Mirrors SymbolService.assetPath in lib/services/symbol_service.dart."""
    return SYMBOLS / f"{word_id.replace('.', '_')}.png"


def get_json(url: str):
    with urllib.request.urlopen(url, timeout=TIMEOUT) as response:
        return json.loads(response.read().decode("utf-8"))


def search(term: str, limit: int = 6) -> list[dict]:
    url = f"{API}/en/search/{urllib.parse.quote(term)}"
    try:
        results = get_json(url)
    except urllib.error.HTTPError as exc:
        if exc.code == 404:
            return []
        raise
    hits = []
    for entry in results[:limit]:
        keywords = [k.get("keyword", "") for k in entry.get("keywords", [])]
        hits.append({"id": entry["_id"], "keywords": keywords})
    return hits


def download(pictogram_id: int, dest: Path) -> int:
    url = f"{API}/{pictogram_id}?resolution={RESOLUTION}&download=false"
    with urllib.request.urlopen(url, timeout=TIMEOUT) as response:
        data = response.read()
    if not data.startswith(b"\x89PNG"):
        die(f"pictogram {pictogram_id} did not return a PNG")
    dest.write_bytes(data)
    return len(data)


def load_choices() -> dict[str, int]:
    if not CHOICES.exists():
        return {}
    raw = json.loads(CHOICES.read_text(encoding="utf-8"))
    return {k: int(v) for k, v in raw.get("choices", {}).items()}


def load_mapping() -> dict[str, dict]:
    """Existing provenance, so --remap-only keeps what is already recorded."""
    path = SYMBOLS / "MAPPING.json"
    if path.exists():
        return json.loads(path.read_text(encoding="utf-8"))
    return {}


def write_provenance(mapping: dict[str, dict]) -> None:
    """Rewrite MAPPING.json (machine) and MAPPING.md (human) for EVERY word.

    v0.02's MAPPING.md covered only 100 of 242 words, so most pictograms had no
    auditable source. Both files are regenerated from the full vocabulary here.
    """
    (SYMBOLS / "MAPPING.json").write_text(
        json.dumps(mapping, indent=2, sort_keys=True) + "\n", encoding="utf-8"
    )
    lines = [
        "# ARASAAC symbol mapping",
        "",
        "Pictograms (c) ARASAAC (Government of Aragon), author Sergio Palao,",
        "CC BY-NC-SA. Regenerated by `tools/fetch_symbols.py` — do not hand-edit.",
        "",
        "`reviewed: no` means the pictogram was taken from a search hit and has",
        "not been checked by a human against the word. See docs/SYMBOL_QA.md.",
        "",
        "| word id | English | ARASAAC id | search term | reviewed |",
        "|---|---|---|---|---|",
    ]
    missing = []
    for word_id, label in vocabulary():
        entry = mapping.get(word_id)
        if not entry:
            missing.append(word_id)
            continue
        lines.append(
            f"| `{word_id}` | {label} | "
            f"[{entry['arasaac_id']}](https://arasaac.org/pictograms/en/{entry['arasaac_id']}) | "
            f"{entry.get('term', '?')} | {'yes' if entry.get('reviewed') else 'no'} |"
        )
    if missing:
        lines += ["", "## Words with no recorded pictogram", ""]
        lines += [f"- `{w}`" for w in missing]
    (SYMBOLS / "MAPPING.md").write_text("\n".join(lines) + "\n", encoding="utf-8")
    print(f"wrote MAPPING.md and MAPPING.json ({len(mapping)} recorded, {len(missing)} missing)")


def write_manifest() -> None:
    present = sorted(
        word_id for word_id, _ in vocabulary() if asset_for(word_id).exists()
    )
    (SYMBOLS / "manifest.json").write_text(
        json.dumps({"symbols": present}, indent=2) + "\n", encoding="utf-8"
    )
    print(f"wrote manifest.json ({len(present)} symbols)")


def cmd_review(review_all: bool) -> None:
    words = vocabulary()
    labels = dict(words)
    targets = words if review_all else [(w, labels[w]) for w in REVIEW_TERMS if w in labels]
    print(f"# ARASAAC candidates for {len(targets)} words\n")
    print("Pick an id per word and put it in tools/symbol_choices.json, then --apply.\n")
    for word_id, label in targets:
        terms = REVIEW_TERMS.get(word_id, [label])
        print(f"\n## {word_id}  (English: \"{label}\")")
        for term in terms:
            try:
                hits = search(term)
            except Exception as exc:  # noqa: BLE001 - surface the real reason
                print(f"  search {term!r} failed: {exc}")
                continue
            if not hits:
                print(f"  search {term!r}: no results")
                continue
            print(f"  search {term!r}:")
            for hit in hits:
                kws = ", ".join(hit["keywords"][:4])
                print(
                    f"    {hit['id']:>6}  {kws}"
                    f"\n            https://arasaac.org/pictograms/en/{hit['id']}"
                )


def cmd_apply() -> None:
    choices = load_choices()
    if not choices:
        die(
            f"no choices found in {CHOICES.relative_to(ROOT)}.\n"
            "Run --review first, then record one ARASAAC id per word, e.g.\n"
            '  {"choices": {"core.try": 12345, "core.pull": 6789}}'
        )
    valid = {w for w, _ in vocabulary()}
    unknown = sorted(set(choices) - valid)
    if unknown:
        die(f"unknown word ids in choices (not in en.json): {', '.join(unknown)}")

    mapping = load_mapping()
    for word_id, pictogram_id in sorted(choices.items()):
        dest = asset_for(word_id)
        size = download(pictogram_id, dest)
        mapping[word_id] = {
            "arasaac_id": pictogram_id,
            "term": (REVIEW_TERMS.get(word_id) or ["?"])[0],
            "reviewed": True,
        }
        print(f"  {word_id:<20} <- arasaac {pictogram_id} ({size // 1024} KB)")
    write_provenance(mapping)
    write_manifest()
    print("\nNow run: flutter test  (pack invariants must stay green)")


def main() -> None:
    parser = argparse.ArgumentParser(description=__doc__.splitlines()[0])
    mode = parser.add_mutually_exclusive_group(required=True)
    mode.add_argument("--review", action="store_true", help="show candidates")
    mode.add_argument("--apply", action="store_true", help="download pinned choices")
    mode.add_argument(
        "--remap-only", action="store_true", help="rebuild manifest + MAPPING without network"
    )
    parser.add_argument("--all", action="store_true", help="with --review: every word")
    args = parser.parse_args()

    if not LANG.exists():
        die(f"{LANG} not found — run from the repo root")
    SYMBOLS.mkdir(parents=True, exist_ok=True)

    if args.review:
        cmd_review(args.all)
    elif args.apply:
        cmd_apply()
    else:
        write_provenance(load_mapping())
        write_manifest()


if __name__ == "__main__":
    main()
